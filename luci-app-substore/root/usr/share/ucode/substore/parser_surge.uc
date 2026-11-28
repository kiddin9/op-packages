// parser_surge.uc — Surge 系 / Loon / QX 配置文件解析 → 统一节点模型（ucode）
// luci-app-substore
//
// 从 parser_surge.lua 移植。对外 API 不变：
//   M.parse(content)      返回统一节点模型**数组**
//   M.is_config(content)  返回布尔值
// Lua 版的多返回值在 ucode 里改为数组（util.split_hostport 返回 [host, port]）。
// Lua 表里「nil 值 = 键不存在」，ucode 对象允许存 null，故所有可能为 nil 的
// 赋值都经 put() 跳过 null，保持与 Lua 版相同的节点形状。

import { isnan } from 'math';

const util = require('substore.util');
const node = require('substore.node');
// 协议白名单复用 Clash YAML 那张表：两边都是「外部格式的类型名 → 统一模型 proto」，
// 各维护一份必然漂移。TYPE_MAP 的键就是这里要判定的原始类型名。
const TYPE_MAP = require('substore.parser_clash_yaml').TYPE_MAP;

const M = {};

// Lua 的 %s 字符集合（isspace）
const WS = ' \t\r\n\v\f';

function is_ws(c) {
	return c != null && c != '' && index(WS, c) >= 0;
}

// Lua 的 `a or b`：只有 nil / false 才回退（`??` 只回退 null，`||` 把 0/"" 也当假）。
function lua_or(a, b) {
	return (a == null || a === false) ? b : a;
}

// Lua 的 tonumber()：只接受数字与字符串；空串 / 纯空白 / 无法解析返回 nil。
// 不能用裸 `+v`：ucode 里 +"" == 0、+"abc" == NaN、+"0b101" == 5（Lua 得 nil）、
// +".5" == NaN（Lua 得 0.5）。因此先按 Lua 5.1 认可的写法过一遍正则再转换。
function lua_tonumber(v) {
	let t = type(v);

	if (t == 'int' || t == 'double')
		return v;

	if (t != 'string')
		return null;

	let s = trim(v);
	if (s == '')
		return null;

	// 十六进制整数（Lua 5.1 的 tonumber 对 0x/0X 走 strtoul base16）
	if (match(s, /^[+-]?0[xX][0-9A-Fa-f]+$/))
		return +s;

	// 十进制：strtod 接受的完整写法（允许 `.5` / `5.` / `1e2`）
	if (!match(s, /^[+-]?([0-9]+(\.[0-9]*)?|\.[0-9]+)([eE][+-]?[0-9]+)?$/))
		return null;

	// ucode 的 + 不认前导小数点：+.5 == NaN，补一个 0
	if (match(s, /^[+-]?\.[0-9]/)) {
		let sign = match(s, /^[+-]/) ? substr(s, 0, 1) : '';
		s = sign + '0' + substr(s, length(sign));
	}

	let n = +s;
	if (isnan(n))
		return null;

	return n;
}

// Lua 表赋值 nil 等于删键：只在值非 null 时写入，保持节点形状一致。
function put(obj, k, v) {
	if (v != null)
		obj[k] = v;
}

// 把 Surge / QX 行里的类型名映射到统一模型 proto，未知类型返回 nil。
// 与 parser_clash_yaml 的未知协议处理保持一致（见那边的长注释）：snell / ssh /
// shadowtls / mieru 这类在统一模型里没有对应字段，原样透传会在输出端变成
// sing-box 的 type: "snell"、Xray 的 protocol: "snell" 这类非法取值，
// 客户端会拒绝加载整份配置；兜底成 vmess 更糟（凭空造出字段全错的假节点）。
// 两者都比丢弃差，所以丢弃。
function map_proto(raw) {
	if (type(raw) != 'string')
		return null;
	return TYPE_MAP[lc(raw)];
}

// 剥掉 Loon 位置参数外面的双引号：`"password"` → `password`。
// Loon 的节点行一律把凭据写成带引号的位置参数，Surge 家族的具名参数则不带引号；
// 只剥一层（`""x""` → `"x"`），没有引号时原样返回。
function unquote(v) {
	v = util.trim(v ?? '');
	let inner = match(v, /^"(.*)"$/);
	return inner ? inner[1] : v;
}

// 按逗号切分字段，但**引号内的逗号不作为分隔符**。
//
// Loon 把凭据写成双引号包裹的位置参数（nsloon.app/docs/Node/）：
//   Trojan = Trojan,trojan.example.com,443,"password",transport=tcp,...
// 密码里含逗号时，`rest:gmatch("[^,]+")` 会把它切成两段 ——
//   Trojan = Trojan,h,443,"pa,ss",sni=x
// 的密码会静默变成 `"pa`（连引号一起、少掉后半段），用户拿到的不是他填的凭据，
// 而且没有任何提示。生成端早就有「值里含逗号就整条丢弃」的防护（output_formats
// 的 surge_line），解析端此前没有对应处理。
//
// 两条边界：
//   * 引号个数为奇数时（订阅内容不可信，可能是落单的引号）**不做引号感知**，
//     退回按逗号切分。否则那个引号会一直「开着」，把后面的 sni= / over-tls=
//     全吞进同一个字段，比按逗号切更糟。
//   * 只跟踪引号开合，不做转义处理 —— Surge / Loon / QX 的行语法里都没有转义
//     机制（Loon 文档只把引号列为位置参数的写法，未提及任何转义序列）。
//
// 无引号的输入与旧的 `gmatch("[^,]+")` 逐字符等价：都按逗号切、都丢弃空字段、
// 都对每段做 trim（旧的 `[^,]+` 会保留纯空白段，trim 后成空串，这里同样保留）。
function split_fields(s) {
	let nquote = 0;
	for (let i = 0; i < length(s); i++) {
		if (substr(s, i, 1) == '"')
			nquote++;
	}
	if (nquote % 2 == 1) {
		let out = [];
		for (let part in split(s, ',')) {
			// `[^,]+` 不会产出空段
			if (part != '')
				push(out, util.trim(part));
		}
		return out;
	}
	let out = [], buf = [], quoted = false;
	for (let i = 0; i < length(s); i++) {
		let c = substr(s, i, 1);
		if (c == '"') {
			quoted = !quoted;
			push(buf, c);
		}
		else if (c == ',' && !quoted) {
			if (length(buf) > 0)
				push(out, util.trim(join('', buf)));
			buf = [];
		}
		else
			push(buf, c);
	}
	if (length(buf) > 0)
		push(out, util.trim(join('', buf)));
	return out;
}

// 解析 Surge 风格行：Name = proto, server, port, k=v, ...
function parse_surge_line(name, rest) {
	let parts = split_fields(rest);
	if (length(parts) < 3)
		return null;

	let proto = map_proto(parts[0]);
	if (!proto)
		return null;
	let server = parts[1];
	let port = lua_tonumber(parts[2]);

	// 具名参数（Surge 家族：`password=pwd`）与位置参数（Loon：`,443,"pwd",`）并存。
	// Loon 的凭据一律写成端口之后的位置参数并用双引号包起来：
	//   Trojan       = Trojan,trojan.example.com,443,"password",transport=tcp,...
	//   VLESS-Reality= VLESS,vless.example.com,443,"ae521383-...",transport=tcp,...
	//   AnyTLS       = AnyTLS,anytls.example.com,443,"password",sni=...
	//   VMess        = VMess,vmess.example.com,443,aes-128-gcm,"52396e06-...",transport=...
	// 此前只认具名参数，Loon 配置导入后 uuid / password 全丢，节点因缺凭据被
	// 下游静默丢弃。位置参数只收集「不含 = 的字段」，具名行完全不受影响。
	// 切分走 split_fields：引号内的逗号不再被当作分隔符，`"pa,ss"` 这种位置
	// 参数能原样保留（见该函数的说明）。
	let kv = {}, pos = [];
	for (let i = 3; i < length(parts); i++) {
		// Lua: "^([%w%-]+)%s*=%s*(.*)$" —— 键只允许字母数字与连字符（没有下划线）
		let m = match(parts[i], /^([A-Za-z0-9-]+)[ \t\r\n\v\f]*=[ \t\r\n\v\f]*(.*)$/);
		if (m)
			kv[m[1]] = util.trim(m[2]);
		else
			push(pos, unquote(parts[i]));
	}

	let data = {
		proto: proto, name: util.trim(name), server: server
	};
	put(data, 'port', port);
	// 凭据在两种写法里的落点，与 output_formats.surge_line 的分叉一一对应：
	//   shadowsocks : Surge 家族 `encrypt-method=…,password=…`；Loon `加密方式,"密码"`
	//   ssr         : 同上，另有 protocol= / obfs= / obfs-param= / protocol-param=
	//   vmess       : Surge 家族 `username=…`；Loon `加密方式,"UUID"`
	//   vless       : Surge 家族 `username=…`；Loon `"UUID"`
	//   trojan      : Surge 家族 `password=…`；Loon `"密码"`
	//   hysteria2   : Surge 家族 `password=…`；Loon `"密码"`
	//   anytls      : Surge 家族 `password=…`；Surfboard 裸位置参数；Loon `"密码"`
	// 位置参数（pos）只收集「不含 = 的字段」，具名写法完全不受影响，所以两种写法
	// 可以无条件并存 —— 本函数导入的既有 Surge / Loon 配置不会因此改变解析结果。
	if (proto == 'shadowsocks') {
		put(data, 'method', lua_or(lua_or(lua_or(kv['encrypt-method'], kv.cipher), kv.method), pos[0]));
		put(data, 'password', lua_or(kv.password, pos[1]));
	}
	else if (proto == 'ssr') {
		// SSR 此前**没有**取字段的分支：不管哪种写法导入，加密方式、密码、协议插件、
		// 混淆方式全是 nil，节点带着空凭据进入统一模型，导出时再被静默丢掉。
		put(data, 'method', lua_or(lua_or(lua_or(kv['encrypt-method'], kv.cipher), kv.method), pos[0]));
		put(data, 'password', lua_or(kv.password, pos[1]));
		if (kv.protocol != null)
			data.protocol = kv.protocol;
		if (kv.obfs != null)
			data.obfs = kv.obfs;
		// 两种拼写都写一份：PROTO_FIELDS / DEFAULTS 用的是带连字符的规范写法
		// （表单据此渲染），而 parser.lua 与各输出模块读的是下划线别名
		// （`n.obfs_param or n["obfs-param"]`）—— 与 parser.lua 同时写
		// method / cipher 是同一个理由，只写一份就会在某条输出路径上丢失。
		if (kv['obfs-param'] != null) {
			data['obfs-param'] = kv['obfs-param'];
			data.obfs_param = kv['obfs-param'];
		}
		if (kv['protocol-param'] != null) {
			data['protocol-param'] = kv['protocol-param'];
			data.protocol_param = kv['protocol-param'];
		}
	}
	else if (proto == 'vmess' || proto == 'vless') {
		// Loon 的 VMess 位置参数是「加密方式, UUID」两个字段；VLESS 只有一个 UUID
		if (proto == 'vmess' && pos[1] != null) {
			put(data, 'cipher', pos[0]);
			put(data, 'uuid', lua_or(lua_or(kv.username, kv.uuid), pos[1]));
		}
		else {
			put(data, 'uuid', lua_or(lua_or(kv.username, kv.uuid), pos[0]));
		}
		if (kv.flow != null)
			data.flow = kv.flow;
	}
	else if (proto == 'trojan') {
		put(data, 'password', lua_or(kv.password, pos[0]));
	}
	else if (proto == 'anytls') {
		put(data, 'password', lua_or(kv.password, pos[0]));
	}
	else if (proto == 'hysteria2' || proto == 'hysteria') {
		// Loon 的 Hysteria2 把密码写在端口之后的位置参数上（`Hysteria2,h,p,"密码"`）
		put(data, 'password', lua_or(kv.password, pos[0]));
	}

	// Reality 参数。Loon 的 VLESS / VMess / Trojan / AnyTLS Reality 行共用
	// public-key（Base64 公钥）与 short-id（十六进制）两个参数名，公钥取值带引号：
	//   public-key="LgJ9bNTyUqBLFkDA12-QgEL7c1yQ1ztk-V1Q-3OLXSk",short-id=164168844958a16d
	// 原样带过去即可 —— node.normalize 会据 public-key 把 security 定为 reality。
	if (kv['public-key'] != null)
		data['public-key'] = unquote(kv['public-key']);
	if (kv['short-id'] != null)
		data['short-id'] = unquote(kv['short-id']);

	// 传输/TLS 通用字段
	if (kv.net != null || kv.network != null)
		data.net = lua_or(kv.net, kv.network);
	if (kv['ws'] == 'true')
		data.net = 'ws';
	if (kv['ws-path'] != null)
		data.path = kv['ws-path'];
	if (kv['ws-headers'] != null) {
		let m = match(kv['ws-headers'], /^Host:[ \t\r\n\v\f]*(.*)$/);
		if (m)
			data.host = m[1];
	}
	// Loon 的传输写法是 transport=<tcp|ws|http> + path= + host=
	// （nsloon.app/docs/Node/ 的示例行），与 Surge 家族的 net= / ws=true /
	// ws-path / ws-headers=Host: 是同一组语义的两代写法 —— Loon 文档明说
	// 「旧参数 ws=true、ws-path、ws-headers=Host:域名 分别对应 transport=ws、
	// path、host」，即旧写法只是兼容别名。只认旧写法时，别人给的 Loon 配置
	// 导入后 net 保持默认 tcp、path / host 全丢，导出到任何格式都按 tcp 去连一个
	// 只开了 ws 的端口 —— 握手失败且不报错。
	// transport=http 按同一段文档「兼容配置中的 transport=http 会按 WebSocket
	// 处理」同样落成 ws。
	// 放在 ws=true / ws-path / ws-headers 之后：同一行两种写法都出现时以新写法为准。
	if (kv.transport != null)
		data.net = (kv.transport == 'http') ? 'ws' : kv.transport;
	if (kv.path != null)
		data.path = kv.path;
	if (kv.host != null)
		data.host = kv.host;
	if (kv.sni != null)
		data.sni = kv.sni;
	// Surge 家族写 tls=true，Loon 写 over-tls=true，两种都是「启用 TLS」
	if (kv.tls != null && kv.tls != 'false' && kv.tls != 'none')
		data.security = 'tls';
	if (kv['over-tls'] != null && kv['over-tls'] != 'false' && kv['over-tls'] != 'none')
		data.security = 'tls';
	if (kv['skip-cert-verify'] != null && kv['skip-cert-verify'] != '0' && kv['skip-cert-verify'] != 'false')
		data['skip-cert-verify'] = true;
	return node.normalize(data);
}

// 解析 QX server_local 行：proto=server:port, k=v, ..., tag=Name
function parse_qx_line(content) {
	let pm = match(content, /^([A-Za-z0-9_]+)[ \t\r\n\v\f]*=[ \t\r\n\v\f]*(.+)$/);
	if (!pm)
		return null;
	let rawproto = pm[1];
	let rest = pm[2];
	let parts = split_fields(rest);
	if (length(parts) < 1)
		return null;

	let hostport = parts[0];
	let hp = util.split_hostport(hostport);
	let host = hp[0], port = hp[1];
	let kv = {};
	for (let i = 1; i < length(parts); i++) {
		let m = match(parts[i], /^([A-Za-z0-9-]+)[ \t\r\n\v\f]*=[ \t\r\n\v\f]*(.*)$/);
		if (m)
			kv[m[1]] = m[2];
	}

	// Lua: kv.tag or (host .. ":" .. tostring(port or ""))
	let name = lua_or(kv.tag, `${host ?? ''}:${port ?? ''}`);
	let proto = map_proto(rawproto);
	if (!proto)
		return null;

	let data = { proto: proto, name: name, server: host };
	put(data, 'port', lua_tonumber(port));
	if (proto == 'shadowsocks') {
		put(data, 'method', kv.method);
		put(data, 'password', kv.password);
	}
	else if (proto == 'vmess' || proto == 'vless') {
		put(data, 'uuid', lua_or(kv.password, kv.uuid));
	}
	else if (proto == 'trojan') {
		put(data, 'password', kv.password);
	}
	else if (proto == 'anytls') {
		put(data, 'password', kv.password);
	}
	// QX 用 obfs= 表示传输 / TLS 模式（官方 sample.conf）：over-tls 是「纯 TLS」、
	// wss 是「ws + TLS」、ws 是明文 ws。obfs-host 在 ws 下是 Host 头、在 over-tls
	// 下是 SNI —— 语义不同，必须分别落到 host / sni，否则 vless + over-tls 的节点
	// 导入后 SNI 被写进 host，Reality 那条更是连不上。
	if (kv.obfs == 'over-tls') {
		data.security = 'tls';
		put(data, 'sni', kv['obfs-host']);
	}
	else {
		if (kv.obfs == 'ws' || kv.obfs == 'wss')
			data.net = 'ws';
		if (kv.obfs == 'wss')
			data.security = 'tls';
		put(data, 'path', kv['obfs-uri']);
		put(data, 'host', kv['obfs-host']);
	}
	put(data, 'sni', kv['tls-host']);
	if (kv['tls-verification'] == 'true' || kv['over-tls'] == 'true')
		data.security = 'tls';
	// flow：QX 的 vless 写 vless-flow=xtls-rprx-vision（sample.conf 的 Reality 条目）
	put(data, 'flow', kv['vless-flow']);
	// Reality：QX 的键名与分享链接 / Clash 都不同 —— Base64 公钥是
	// reality-base64-pubkey，十六进制 short id 是 reality-hex-shortid。
	// node.normalize 会据 public-key 把 security 定为 reality。
	if (kv['reality-base64-pubkey'] != null)
		data['public-key'] = kv['reality-base64-pubkey'];
	if (kv['reality-hex-shortid'] != null)
		data['short-id'] = kv['reality-hex-shortid'];
	return node.normalize(data);
}

// 把 `NAME = rest` 拆开。等价于 Lua 的 `t:match("^([^=]-)%s*=%s*(.+)$")`：
// `(.-)` 是非贪婪，取第一个 = 之前的文本并去掉尾部空白；`(.+)` 至少要一个字符，
// 全是空白时（贪婪的 %s* 回溯）保留最后一个空白字符 —— 此时后续 #parts < 3 会丢弃。
function split_name_rest(t) {
	let eq = index(t, '=');
	if (eq < 0)
		return null;
	let name = substr(t, 0, eq);
	while (name != '' && is_ws(substr(name, length(name) - 1, 1)))
		name = substr(name, 0, length(name) - 1);
	let rest = substr(t, eq + 1);
	let i = 0;
	while (i < length(rest) && is_ws(substr(rest, i, 1)))
		i++;
	if (i >= length(rest)) {
		if (length(rest) == 0)
			return null;
		rest = substr(rest, length(rest) - 1, 1);
	}
	else
		rest = substr(rest, i);
	return [name, rest];
}

// 解析客户端配置，返回节点列表（自动识别 Surge/Loon 与 QX 风格）
M.parse = function(content) {
	if (content == null || content == '')
		return [];
	let nodes = [];
	let section = '';
	for (let line in split(content, /[\r\n]+/)) {
		let t = util.trim(line);
		if (t == '' || substr(t, 0, 1) == '#' || substr(t, 0, 1) == ';') {
			// 跳过空行/注释
		}
		else if (match(t, /^\[/)) {
			let m = match(t, /^\[([^\]]+)\]/);
			section = lc(m ? m[1] : '');
		}
		else if (section == 'proxy') {
			let nr = split_name_rest(t);
			if (nr) {
				let n = parse_surge_line(nr[0], nr[1]);
				if (n)
					push(nodes, n);
			}
		}
		else if (section == 'server_local') {
			let n = parse_qx_line(t);
			if (n)
				push(nodes, n);
		}
	}
	return nodes;
};

// 判断内容是否为客户端配置文件。
// 段名大小写不敏感：Surge 官方配置写 `[Proxy]`，但 Loon / 第三方转换器常写
// `[PROXY]` / `[General]` 这类全大写段名。原来的 find("%[Proxy%]") 只认大小写
// 完全一致的写法，于是 detect 不认为这是 Surge 配置，继续往下走——
// 而 `[` 开头的内容会被判成 JSON 数组，整份订阅报「JSON 解析失败」，
// 一个节点都拿不到（M.parse 本身是按小写段名匹配的，本来就能解析）。
M.is_config = function(content) {
	content = content ?? '';
	let lower = lc(content);
	return index(lower, '[proxy]') >= 0
		|| index(lower, '[server_local]') >= 0;
};

return M;
