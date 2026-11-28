// parser.uc — 订阅格式解析 → 统一节点模型
// luci-app-substore
//
// 多返回值约定：本模块的解析函数返回 `[node]` / `[nodes]`，失败返回
// `[null, err]`；调用方用 `let [v, err] = f()` 取用。

const util = require('substore.util');
const node = require('substore.node');
const msg = require('substore.msg');
const parser_clash_yaml = require('substore.parser_clash_yaml');
const parser_json_config = require('substore.parser_json_config');
const parser_surge = require('substore.parser_surge');

const M = {};

// 节点值的字符串化：`${null}` 在 ucode 里会得到 "null"，必须显式拦。
function str(v) {
	return v == null ? '' : `${v}`;
}

// 严格数字转换：ucode 的 int("1e999") 会截成 1，而 Lua 的 tonumber 得到 inf。
// 端口校验依赖「非法写法必须失败」，因此只接受完整的十进制/小数文本。
function tonum(v) {
	if (type(v) == 'int' || type(v) == 'double')
		return v;
	if (type(v) != 'string')
		return null;
	let s = util.trim(v);
	if (!match(s, /^[+-]?[0-9]+(\.[0-9]+)?$/))
		return null;
	return +s;
}

// Lua 的 `a or b or c` 对 nil / false / "" 一律回退；这里保留同一语义。
function first(...args) {
	for (let a in args) {
		if (a != null && a !== '' && a !== false)
			return a;
	}
	return null;
}

// 只在非 nil 时赋值，避免 ucode 对象留下值为 null 的键（Lua 里 nil 即不存在）
function put(obj, k, v) {
	if (v != null)
		obj[k] = v;
	return obj;
}

// URI 文本导入支持的 scheme。
// 必须覆盖 output_uri.to_share_uri 能生成的全部 scheme，否则「导出→导入」回环会
// 丢节点：之前 hysteria / socks 只出不进（导出为 hysteria:// / socks5://，
// 再导入却报 "unsupported proto"），含这两类节点的订阅文本也会被整行丢弃。
// socks5 与 socks 都接受，统一归一为 proto="socks"（见 node.normalize）。
const SUPPORTED = {
	vmess: true, vless: true, trojan: true, ss: true, ssr: true,
	hysteria: true, hysteria2: true, tuic: true, wireguard: true,
	socks: true, socks5: true,
	// anytls 同样必须能进：output_uri 会生成 anytls:// 链接，缺了这一项
	// 「导出→导入」回环就把节点整行丢掉（H 系列的老问题）。
	anytls: true,
};

function split_lines(content) {
	let out = [];
	for (let line in split(content, /\r\n|\r|\n/)) {
		if (line != '')
			push(out, line);
	}
	return out;
}

// 节点必须有可用的 server 与 port，否则解析阶段就丢弃。
//
// 依据：Clash / sing-box / v2ray 的输出都会把缺失值写成 `server: `（空字符串）
// 或 `port: 0`。这两个值不是「降级」，而是**非法配置**——mihomo 与 sing-box 会
// 拒绝加载整份文件，于是一个残缺节点废掉整个订阅的所有节点。
// 与 H6（未知协议）同理：模型承载不了的东西不进模型，而不是带着非法值往下传。
//
// port 来自 util.split_hostport，只会是 "%d+" 匹配到的数字串或 nil，
// 因此这里只需判空与范围（0 与 >65535 都是非法端口）。
function valid_hostport(host, port) {
	if (host == null || host == '')
		return false;
	let p = tonum(port);
	return p != null && p >= 1 && p <= 65535;
}

// `k=v&k2=v2` 查询串 → 对象（键非空、值做 URL 解码，与 Lua 的 gmatch 行为一致）
function query_parse(q) {
	let params = {};
	if (q == null || q == '')
		return params;
	for (let part in split(q, '&')) {
		let eq = index(part, '=');
		if (eq > 0)
			params[substr(part, 0, eq)] = util.url_decode(substr(part, eq + 1));
	}
	return params;
}

// 检测订阅格式：uri / base64 / json / yaml / empty / unknown
M.detect = function(content) {
	content = util.trim(content ?? '');
	content = replace(content, /^\xEF\xBB\xBF/, ''); // 去除 UTF-8 BOM（部分机场/CDN 会在开头塞 BOM）
	if (content == '')
		return 'empty';
	let stripped = replace(content, /\s+/g, '');
	if (substr(stripped, 0, 1) == '{')
		return 'json';
	// YAML 检测：包含 proxies: 或 outbounds: 键
	if (match(content, /^\s*proxies:/) || match(content, /^\s*outbounds:/))
		return 'yaml';
	// 检查内容中是否包含 proxies: 或 outbounds: 行
	for (let line in split_lines(content)) {
		if (match(line, /^\s*proxies:\s*$/) || match(line, /^\s*outbounds:\s*$/))
			return 'yaml';
	}
	// wg-quick / AmneziaWG .conf：[Interface] 段 + PrivateKey 行（双条件收紧，避免误判普通文本）
	let lower = lc(content);
	if (match(lower, /\[interface\]/) && match(lower, /privatekey\s*=/))
		return 'wireguard-conf';
	// Surge / Loon：必须排在下面的 URI 兜底判断之前。
	// Surge 配置头部的 "#!MANAGED-CONFIG https://…" 含 "://"，排在后面会被判成 uri，
	// 于是整份订阅解析出 0 个节点，且因为 parse 返回的是合法表，同步还会报成功。
	if (parser_surge.is_config(content))
		return 'surge';
	// JSON 数组（节点数组）：必须排在 .conf 判断之后，否则 "[Interface]" 会被当成数组
	if (substr(stripped, 0, 1) == '[')
		return 'json';
	if (index(stripped, 'vmess://') >= 0 || index(stripped, 'vless://') >= 0
		|| index(stripped, 'trojan://') >= 0 || index(stripped, 'ssr://') >= 0
		|| index(stripped, 'ss://') >= 0 || index(content, '://') >= 0)
		return 'uri';
	if (match(stripped, /^[A-Za-z0-9+\/_-]*=*$/) && length(stripped) > 10) {
		// 更严格：需含 = / + - _ 之一，或长度为 4 的整数倍（避免把纯字母数字文本误判为 base64）
		// 兼容 base64url（- _ 无 padding）：URL-safe 变体也常见于机场订阅
		if (index(stripped, '=') >= 0 || index(stripped, '/') >= 0
			|| index(stripped, '+') >= 0 || index(stripped, '-') >= 0
			|| index(stripped, '_') >= 0 || length(stripped) % 4 == 0)
			return 'base64';
		// 纯字母数字且长度非 4 倍数：可能是去掉 padding 的 base64url，尝试解码校验内容
		let decoded = util.base64_url_decode(stripped);
		if (decoded != '' && (index(decoded, 'vmess://') >= 0 || index(decoded, 'vless://') >= 0
			|| index(decoded, 'trojan://') >= 0 || index(decoded, 'ss://') >= 0
			|| index(decoded, 'ssr://') >= 0))
			return 'base64';
	}
	if (parser_surge.is_config(content))
		return 'surge';
	return 'unknown';
};

// 「混合格式」提示里各格式的显示名
const FORMAT_LABELS = {
	uri: 'URI link',
	json: 'JSON',
	yaml: 'Clash YAML',
	'wireguard-conf': 'WireGuard .conf',
	surge: 'Surge/Loon config',
};

// 行首锚定，数出「整行就是一条节点链接」的行数。
//
// 不能用 detect() 里那条宽松的 `content:find("://")`：Clash YAML 的
// `url: https://…`、sing-box JSON 的 `"url": "https://…"` 都含 "://"，
// 拿它当 URI 判据的话，一份**完全正常**、只是带了个订阅地址的配置
// 会被判成「YAML + URI 混合」而拒绝导入 —— 误判比漏报更糟。
// 锚定行首之后，只有「一行就是一条链接」才算数，那正是 URI 订阅的形态。
function count_uri_lines(content) {
	let n = 0;
	for (let line in split_lines(content)) {
		let m = match(line, /^\s*([A-Za-z][A-Za-z0-9]*):\//);
		if (m && SUPPORTED[lc(m[1])])
			n++;
	}
	return n;
}

// INI 段头：`[Interface]` / `[Peer]` / `[Proxy]` / `[server_local]`
// 它们同样以 "[" 开头，但**不是** JSON 数组。
// detect() 靠判断次序避开了这一点（surge 与 .conf 都排在 "[" 之前，先命中就返回），
// 而 detect_all 是「全部收集」，次序挡不住，必须显式排除 ——
// 否则一份完全正常的 Surge 配置会被判成「Surge + JSON 混合」而拒绝导入。
function is_ini_section_head(line) {
	return match(line, /^\s*\[[A-Za-z][A-Za-z0-9_ \t-]*\]\s*$/) != null;
}

// 行首的 JSON 对象起始：`{` 单独一行，或 `{"key"…`。
// 对象的第一个键必然是带引号的字符串，因此 YAML 的流式映射 `{path: /x}`
// （未加引号的键）不会被误判成 JSON。
function has_json_object_line(content) {
	for (let line in split_lines(content)) {
		if (match(line, /^\s*\{\s*$/) || match(line, /^\s*\{\s*"/))
			return true;
	}
	return false;
}

// 行首的 JSON 数组起始，排除 INI 段头
function has_json_array_line(content) {
	for (let line in split_lines(content)) {
		if (match(line, /^\s*\[/) && !is_ini_section_head(line))
			return true;
	}
	return false;
}

// 内容**同时**命中的全部格式，按 detect() 的优先级排列。
//
// 只服务于「混合格式」提示（见 M.parse_local 的文本模式）：detect() 只返回
// 优先级最高的那一个，其余格式的内容会被**静默丢弃** —— 粘进「URI + WG conf」，
// 只导入到 WG 节点；粘进「URI + JSON」，只导入到 URI 节点。而 parse 返回的是
// 合法表，同步报成功，用户以为整份都导进来了。
//
// 判据必须从严：这个返回值会被用来**拒绝导入**，误判会把一份正常配置挡在门外。
// 因此一律用「整份文档级标记 + 行首锚定」，宁可漏报，不可误报。
M.detect_all = function(content) {
	content = util.trim(content ?? '');
	content = replace(content, /^\xEF\xBB\xBF/, '');
	let out = [];
	if (content == '')
		return out;
	let lower = lc(content);

	// .conf 的双条件与 detect() 一致
	let wg_conf = match(lower, /\[interface\]/) && match(lower, /privatekey\s*=/);
	if (wg_conf)
		push(out, 'wireguard-conf');

	if (match(content, /^\s*proxies:/) || match(content, /^\s*outbounds:/)) {
		push(out, 'yaml');
	}
	else {
		for (let line in split_lines(content)) {
			if (match(line, /^\s*proxies:\s*$/) || match(line, /^\s*outbounds:\s*$/)) {
				push(out, 'yaml');
				break;
			}
		}
	}
	if (parser_surge.is_config(content))
		push(out, 'surge');
	if (count_uri_lines(content) > 0)
		push(out, 'uri');
	// JSON 排在最后：它的判据最宽（一份 JSON 配置里也可能出现 URI 行），
	// 放前面不影响结果，但排最后读起来与 detect() 的优先级一致。
	if ((has_json_object_line(content) || has_json_array_line(content)) && !wg_conf)
		push(out, 'json');
	return out;
};

// ---------- 协议解析 ----------
function parse_ss(body) {
	// ss:// 兼容多种变体：base64(method:password@host:port)、method:password@host:port、
	// base64(method:password)@host:port；可选 ?plugin=、#name
	let fragment = '', rest = body;
	let hash = index(rest, '#');
	if (hash >= 0) {
		fragment = util.url_decode(substr(rest, hash + 1));
		rest = substr(rest, 0, hash);
	}
	let query = {};
	let qpos = index(rest, '?');
	let hp = rest;
	if (qpos >= 0) {
		hp = substr(rest, 0, qpos);
		query = query_parse(substr(rest, qpos + 1));
	}
	if (hp == '')
		return [null, 'bad ss'];

	let userinfo, hostport;
	let at = index(hp, '@');
	if (at >= 0) {
		userinfo = substr(hp, 0, at);
		hostport = substr(hp, at + 1);
	}
	else {
		// 整体可能是 base64(method:password@host:port)
		let decoded = util.base64_decode(hp);
		let d = index(decoded, '@');
		if (d >= 0) {
			userinfo = substr(decoded, 0, d);
			hostport = substr(decoded, d + 1);
		}
		else {
			return [null, 'bad ss (no @)'];
		}
	}
	// userinfo 可能是 base64(method:password)
	if (index(userinfo, ':') < 0)
		userinfo = util.base64_decode(userinfo) ?? '';
	let m = match(userinfo, /^([^:]+):(.*)$/);
	let method = m ? m[1] : null;
	let password = m ? m[2] : null;
	let [host, port] = util.split_hostport(hostport);
	if (!method || password == null || !valid_hostport(host, port))
		return [null, 'bad ss'];
	let name = fragment != '' ? fragment : host + ':' + str(port);
	let out = node.normalize({
		proto: 'shadowsocks', name: name, server: host, port: tonum(port),
		method: method, password: password, raw: 'ss://' + body,
	});
	if (query.plugin)
		out.plugin = query.plugin;
	return [out];
}

// SSR 参数值可能为 base64url、标准 base64 或纯文本：优先 base64url 解码，失败回退 URL 解码。
// util.base64_url_decode 永远不会「失败」——它把非 base64 字符直接剔掉再解码，
// 所以纯文本也会解出乱码字节而不是空串，原来的 `if v ~= ""` 回退分支根本不可达，
// 节点名 / obfsparam / group 会被解成乱码（并写盘、下发）。
// 可靠的判据是往返一致性：合法 base64url 重新编码后与原文逐字符相同，纯文本不会。
function b64u_decode(s) {
	s = s ?? '';
	let v = util.base64_url_decode(s);
	if (v != '' && util.base64_url_encode(v) == replace(s, /=+$/, ''))
		return v;
	return util.url_decode(s);
}

function parse_ssr(body) {
	// ssr://base64(server:port:protocol:method:obfs:base64(password)/?obfsparam=..&protoparam=..&remarks=..&group=..)
	// 外层为标准 base64；密码字段可为标准/base64url base64；obfsparam/protoparam/remarks/group 为 base64url
	if (!body || body == '')
		return [null, 'bad ssr'];
	// 容忍 #fragment 与 URL 转义（部分生成器会在末尾追加）
	let rest = body, frag = '';
	let hash = index(rest, '#');
	if (hash >= 0) {
		frag = util.url_decode(substr(rest, hash + 1));
		rest = substr(rest, 0, hash);
	}
	if (index(rest, '%') >= 0)
		rest = util.url_decode(rest);
	// 用 base64_url_decode 而不是 base64_decode：前者只是先把 -/_ 还原成 +//
	// 再走标准解码，对标准 base64 输入逐字节等价（标准字母表里没有 -/_），
	// 对 base64url 输入才是正确的。
	// 反过来的代价很大：base64_decode 会把 -/_ 当非法字符**直接剔除**
	// （util.lua 的 `s:gsub("[^%w%+/=]", "")`），于是外层用了 base64url 的
	// ssr:// 链接会少掉若干字符、整串解成乱码——server / port / 密码全错，
	// 而且不报错，用户只看到一个连不上的节点。
	let decoded = util.base64_url_decode(rest);
	if (decoded == '')
		return [null, 'bad ssr'];

	// 以首个 '?' 切分主体与参数（密码 base64 可能含 '/'，故不能按 '/' 切分）
	let qpos = index(decoded, '?');
	let main = decoded, query = '';
	if (qpos >= 0) {
		main = substr(decoded, 0, qpos);
		query = substr(decoded, qpos + 1);
	}
	main = replace(main, /\/+$/, '');

	let m = match(main, /^([^:]*):([^:]*):([^:]*):([^:]*):([^:]*):(.*)$/);
	if (!m || m[1] == '')
		return [null, 'bad ssr'];
	let server = m[1], port = m[2], protocol = m[3], method = m[4], obfs = m[5], pwd_b64 = m[6];
	let password = b64u_decode(pwd_b64 ?? '');

	let params = {};
	for (let part in split(query ?? '', '&')) {
		let eq = index(part, '=');
		if (eq > 0)
			params[substr(part, 0, eq)] = substr(part, eq + 1);
	}

	let name = b64u_decode(params.remarks ?? '');
	if (name == '')
		name = frag;
	if (name == '')
		name = server + ':' + str(port);

	let out = node.normalize({
		proto: 'ssr', name: name, server: server, port: tonum(port),
		method: method, password: password, protocol: protocol, obfs: obfs,
		raw: 'ssr://' + body,
	});
	let op = b64u_decode(params.obfsparam ?? '');
	let pp = b64u_decode(params.protoparam ?? '');
	if (op != '')
		out.obfs_param = op;
	if (pp != '')
		out.protocol_param = pp;
	let grp = b64u_decode(params.group ?? '');
	if (grp != '')
		out.group = grp;
	return [out];
}

function parse_vless(uri, body) {
	let name = '', rest = body;
	let hash = index(rest, '#');
	if (hash >= 0) {
		name = util.url_decode(substr(rest, hash + 1));
		rest = substr(rest, 0, hash);
	}
	let query = query_parse(substr(rest, index(rest, '?') >= 0 ? index(rest, '?') + 1 : length(rest)));
	let qpos = index(rest, '?');
	let hp = qpos >= 0 ? substr(rest, 0, qpos) : rest;
	let at = index(hp, '@');
	if (at < 0)
		return [null, 'bad vless'];
	let uuid = substr(hp, 0, at);
	let [host, port] = util.split_hostport(substr(hp, at + 1));
	if (!valid_hostport(host, port))
		return [null, 'bad vless'];
	let out = node.normalize({
		proto: 'vless', name: name, server: host, port: tonum(port), uuid: uuid, raw: uri,
	});
	if (query.type)
		out.net = query.type;
	if (query.security)
		out.security = query.security;
	if (query.sni)
		out.sni = query.sni;
	if (query.fp)
		out.fp = query.fp;
	if (query.alpn)
		out.alpn = query.alpn;
	if (query.headerType)
		out.headerType = query.headerType;
	// path / host / flow 以前没有回读：output_uri 会写出这三个参数，读不回来就造成
	// 往返丢字段。丢 path/host 的后果尤其严重——Clash 输出会得到 network: ws 却没有
	// ws-opts.path，客户端请求 "/" 而非真实路径，节点直接连不上。
	// flow 是 XTLS Vision（xtls-rprx-vision）的必需参数，丢了同样握手失败。
	if (query.path)
		out.path = query.path;
	if (query.host)
		out.host = query.host;
	if (query.flow)
		out.flow = query.flow;
	// Reality（security=reality）参数。键名取自 Xray 分享链接规范
	// （XTLS/Xray-core discussion #716）：pbk = public-key、sid = short-id、
	// spx = spiderX。三者都必须回读，否则「导出→导入」回环会把 Reality 参数
	// 丢光 —— 缺 public-key 的 Reality 节点客户端根本连不上。
	// fp 上面已经回读：Reality 规范里 fp 不可省略（缺省 chrome），它同时就是
	// 这条连接的 uTLS 指纹。
	if (query.pbk)
		out['public-key'] = query.pbk;
	if (query.sid)
		out['short-id'] = query.sid;
	if (query.spx)
		out['spider-x'] = query.spx;
	return [out];
}

function parse_trojan(uri, body) {
	let name = '', rest = body;
	let hash = index(rest, '#');
	if (hash >= 0) {
		name = util.url_decode(substr(rest, hash + 1));
		rest = substr(rest, 0, hash);
	}
	let query = {};
	let qpos = index(rest, '?');
	let hp = rest;
	if (qpos >= 0) {
		hp = substr(rest, 0, qpos);
		query = query_parse(substr(rest, qpos + 1));
	}
	// 取**最后**一个 @：userinfo 里不允许裸 @，未编码的 @ 只可能出现在密码里。
	// 按第一个 @ 切会把 "p@ss" 切成密码 "p" + server "ss@1.2.3.4"（静默出错）。
	// 与 parse_socks / parse_hysteria2 / parse_tuic 保持同一策略。
	let um = match(hp, /^(.*)@([^@]*)$/);
	if (!um)
		return [null, 'bad trojan'];
	// 密码必须 url_decode：output_uri 写链接时会 url_encode，不解码就是双重编码
	// （"p@ss:w/rd" → 回读成 "p%40ss%3Aw%2Frd"），回环一次密码就错了。
	let password = util.url_decode(um[1]);
	let [host, port] = util.split_hostport(um[2]);
	if (!valid_hostport(host, port))
		return [null, 'bad trojan'];
	let out = node.normalize({
		proto: 'trojan', name: name, server: host, port: tonum(port),
		password: password, raw: uri,
	});
	if (query.sni)
		out.sni = query.sni;
	if (query.security)
		out.security = query.security;
	if (query.alpn)
		out.alpn = query.alpn;
	// trojan 同样支持 ws/grpc 等传输：output_uri 会写出 type/path/host/fp，
	// 以前只回读 sni/security/alpn，造成往返丢字段
	if (query.type)
		out.net = query.type;
	if (query.path)
		out.path = query.path;
	if (query.host)
		out.host = query.host;
	if (query.fp)
		out.fp = query.fp;
	return [out];
}

function parse_vmess(uri, body) {
	let name = '', rest = body;
	let hash = index(rest, '#');
	if (hash >= 0) {
		name = util.url_decode(substr(rest, hash + 1));
		rest = substr(rest, 0, hash);
	}
	// v2rayN 新格式：vmess://uuid@host:port?type=tcp&security=none#name
	if (index(rest, '@') >= 0) {
		let query = {};
		let qpos = index(rest, '?');
		let hp = rest;
		if (qpos >= 0) {
			hp = substr(rest, 0, qpos);
			query = query_parse(substr(rest, qpos + 1));
		}
		let at = index(hp, '@');
		let uuid = substr(hp, 0, at);
		let [host, port] = util.split_hostport(substr(hp, at + 1));
		if (!valid_hostport(host, port))
			return [null, 'bad vmess'];
		let out = node.normalize({
			proto: 'vmess', name: name, server: host, port: tonum(port),
			uuid: uuid, raw: uri,
		});
		if (query.type)
			out.net = query.type;
		if (query.security)
			out.security = query.security;
		if (query.sni)
			out.sni = query.sni;
		if (query.fp)
			out.fp = query.fp;
		if (query.alpn)
			out.alpn = query.alpn;
		// 同上：vmess 新版 URI 也带 host / path / headerType
		if (query.host)
			out.host = query.host;
		if (query.path)
			out.path = query.path;
		if (query.headerType)
			out.headerType = query.headerType;
		return [out];
	}
	// 经典格式：vmess://base64(json)
	let decoded = util.base64_url_decode(rest);
	if (decoded == '')
		return [null, 'bad vmess b64'];
	let [j, jerr] = util.json_decode(decoded);
	if (type(j) != 'object' || j.add == null)
		return [null, 'bad vmess json'];
	if (!valid_hostport(j.add, j.port))
		return [null, 'bad vmess json'];
	let out = node.normalize({
		proto: 'vmess',
		name: first(j.ps, j.add + ':' + str(j.port)),
		server: j.add, port: tonum(j.port),
		uuid: j.id, alterId: tonum(j.aid),
		net: j.net, type: j.type,
		// scy 是 vmess 加密方式（cipher），不是 TLS 层；TLS 由 tls 字段表达
		// （"tls" 表示启用，"" 表示不启用）
		cipher: first(j.scy, j.security),
		security: (j.tls == 'tls' || j.tls == true) ? 'tls' : null,
		raw: uri,
	});
	// host / path 是 ws（以及 http/h2）传输的必需参数：output_uri 会把它们写成
	// vmess://…?host=…&path=…，不回读就等于导出→导入丢字段。丢 path 的后果最严重——
	// Clash 输出得到 network: ws 却没有 ws-opts.path，客户端请求 "/" 而非真实路径。
	// vless 分支与 vmess 新版 URI 分支早已回读这两个字段，此处是对齐。
	if (j.host && j.host != '')
		out.host = j.host;
	if (j.path && j.path != '')
		out.path = j.path;
	return [out];
}

// hysteria2://password@host:port/?sni=..&insecure=..#name
function parse_hysteria2(uri, body) {
	let name = '', rest = body;
	let hash = index(rest, '#');
	if (hash >= 0) {
		name = util.url_decode(substr(rest, hash + 1));
		rest = substr(rest, 0, hash);
	}
	let query = {};
	let qpos = index(rest, '?');
	let hp = rest;
	if (qpos >= 0) {
		hp = substr(rest, 0, qpos);
		query = query_parse(substr(rest, qpos + 1));
	}
	// 取最后一个 @（见 parse_socks 的说明）：按第一个 @ 切会把密码里的裸 @ 当成
	// userinfo 分隔符，得到密码 "p" 和 server "ss@1.2.3.4"——静默解析出一个错节点。
	let um = match(hp, /^(.*)@([^@]*)$/);
	if (!um)
		return [null, 'bad hysteria2'];
	let password = util.url_decode(um[1]);
	let [host, port] = util.split_hostport(um[2]);
	if (!valid_hostport(host, port))
		return [null, 'bad hysteria2'];
	let out = node.normalize({
		proto: 'hysteria2', name: name, server: host, port: tonum(port),
		password: password, raw: uri,
	});
	if (query.sni)
		out.sni = query.sni;
	// hysteria2 / hysteria 在 sing-box 与 mihomo 里都是 TLS-only，而 hy2 URI 不带
	// security 参数。不补上的话 output_singbox.build_tls 直接返回 nil，
	// sni / insecure 全部丢失，生成的 outbound 不可用。
	out.security = 'tls';
	// insecure 是 URI 参数名，模型里的权威字段是 skip-cert-verify
	// （parser_json_config 也把 sing-box 的 tls.insecure 映射到它）。
	// 两个都保留：skip-cert-verify 供各输出消费，insecure 供 URI 回写。
	if (query.insecure != null) {
		out.insecure = query.insecure;
		out['skip-cert-verify'] = !(query.insecure == '0' || query.insecure == 'false');
	}
	// 混淆参数回读，保证导出→导入回环不丢字段
	if (query.obfs)
		out.obfs = query.obfs;
	if (query['obfs-password'])
		out['obfs-password'] = query['obfs-password'];
	return [out];
}

// anytls://password@host:port/?sni=..&insecure=..#name
// 链接规范由 anytls-go 定义（mihomo 与 Shadowrocket 都按它解析）：密码放在
// userinfo（auth）位置，端口缺省 443，查询参数只有 sni 与 insecure 两个。
function parse_anytls(uri, body) {
	let name = '', rest = body;
	let hash = index(rest, '#');
	if (hash >= 0) {
		name = util.url_decode(substr(rest, hash + 1));
		rest = substr(rest, 0, hash);
	}
	let query = {};
	let qpos = index(rest, '?');
	let hp = rest;
	if (qpos >= 0) {
		hp = substr(rest, 0, qpos);
		query = query_parse(substr(rest, qpos + 1));
	}
	// 取最后一个 @（同 parse_socks / parse_hysteria2）：按第一个 @ 切会把密码里的
	// 裸 @ 当成 userinfo 分隔符，静默解析出 server="x@1.2.3.4" 这样的错节点。
	let um = match(hp, /^(.*)@([^@]*)$/);
	if (!um)
		return [null, 'bad anytls'];
	let password = util.url_decode(um[1]);
	let [host, port] = util.split_hostport(um[2]);
	// 端口缺省 443：规范写的是 hostname[:port]，省略端口是合法写法。不补默认值
	// 会让 valid_hostport 判假，整条链接被丢弃。
	if (port == null || port == '')
		port = 443;
	if (!valid_hostport(host, port))
		return [null, 'bad anytls'];
	let out = node.normalize({
		proto: 'anytls', name: name, server: host, port: tonum(port),
		password: password, raw: uri,
	});
	if (query.sni)
		out.sni = query.sni;
	// anytls 在 mihomo / sing-box / Surge 里都是 TLS-only（协议本身没有明文模式），
	// 而 anytls:// 不带 security 参数。不补上的话 output_singbox.build_tls 直接
	// 返回 nil，sni / insecure 全部丢失，生成的 outbound 不可用。
	out.security = 'tls';
	// insecure 是 URI 参数名，模型里的权威字段是 skip-cert-verify
	// （与 parse_hysteria2 的处理保持一致）。
	if (query.insecure != null) {
		out.insecure = query.insecure;
		out['skip-cert-verify'] = !(query.insecure == '0' || query.insecure == 'false');
	}
	return [out];
}

// hysteria://password@host:port/?sni=..&insecure=..&obfs=..#name（v1）
// 与 hysteria2 的区别（均已对照上游确认）：
//   * v1 的 obfs 是普通字符串，没有 obfs-password（obfs-password 是 hysteria2 的 salamander）
//   * 两者在 mihomo / sing-box 里都是 TLS-only，因此同样补 security="tls"
// 认不出的查询参数一律忽略（不报错），保证第三方生成的链接仍能解析出 server/port/password。
function parse_hysteria(uri, body) {
	let name = '', rest = body;
	let hash = index(rest, '#');
	if (hash >= 0) {
		name = util.url_decode(substr(rest, hash + 1));
		rest = substr(rest, 0, hash);
	}
	let query = {};
	let qpos = index(rest, '?');
	let hp = rest;
	if (qpos >= 0) {
		hp = substr(rest, 0, qpos);
		query = query_parse(substr(rest, qpos + 1));
	}
	let um = match(hp, /^(.*)@([^@]*)$/);
	if (!um)
		return [null, 'bad hysteria'];
	let password = util.url_decode(um[1]);
	let [host, port] = util.split_hostport(um[2]);
	if (!valid_hostport(host, port))
		return [null, 'bad hysteria'];
	let out = node.normalize({
		proto: 'hysteria', name: name, server: host, port: tonum(port),
		password: password, raw: uri,
	});
	if (query.sni)
		out.sni = query.sni;
	out.security = 'tls';
	if (query.insecure != null) {
		out.insecure = query.insecure;
		out['skip-cert-verify'] = !(query.insecure == '0' || query.insecure == 'false');
	}
	if (query.obfs && query.obfs != '')
		out.obfs = query.obfs;
	return [out];
}

// socks5://user:pass@host:port#name（socks:// 同义）
// 认证信息可选：没有 userinfo 时是无认证 socks。统一归一为 proto="socks"。
function parse_socks(uri, body) {
	let name = '', rest = body;
	let hash = index(rest, '#');
	if (hash >= 0) {
		name = util.url_decode(substr(rest, hash + 1));
		rest = substr(rest, 0, hash);
	}
	// socks 没有标准查询参数，但第三方链接可能带 ? 尾巴，截掉以免污染 host:port
	let qpos = index(rest, '?');
	let hp = qpos >= 0 ? substr(rest, 0, qpos) : rest;

	let username = null, password = null;
	// 取**最后**一个 @ 作为 userinfo 与 authority 的分界：未编码的 @ 只可能出现在
	// 密码里（userinfo 不允许裸 @），按第一个 @ 切会把 "p@ss" 这类密码切坏，
	// 而且失败是静默的（解析出一个错的密码）。
	let um = match(hp, /^(.*)@([^@]*)$/);
	let hostport;
	if (!um) {
		hostport = hp;
	}
	else {
		hostport = um[2];
		let userinfo = util.url_decode(um[1]);
		let cpos = index(userinfo, ':');
		if (cpos >= 0) {
			username = substr(userinfo, 0, cpos);
			password = substr(userinfo, cpos + 1);
		}
		else {
			username = userinfo;
		}
		if (username == '')
			username = null;
	}

	let [host, port] = util.split_hostport(hostport);
	if (host == null || host == '')
		return [null, 'bad socks'];
	let out = node.normalize({
		proto: 'socks', name: name, server: host, port: tonum(port), raw: uri,
	});
	if (username != null)
		out.username = username;
	if (password != null)
		out.password = password;
	return [out];
}

// tuic://uuid:password@host:port/?congestion_control=..&alpn=..&sni=..#name
function parse_tuic(uri, body) {
	let name = '', rest = body;
	let hash = index(rest, '#');
	if (hash >= 0) {
		name = util.url_decode(substr(rest, hash + 1));
		rest = substr(rest, 0, hash);
	}
	let query = {};
	let qpos = index(rest, '?');
	let hp = rest;
	if (qpos >= 0) {
		hp = substr(rest, 0, qpos);
		query = query_parse(substr(rest, qpos + 1));
	}
	// 取最后一个 @（见 parse_socks 的说明）
	let um = match(hp, /^(.*)@([^@]*)$/);
	if (!um)
		return [null, 'bad tuic'];
	let userinfo = util.url_decode(um[1]);
	let uuid = '', password = userinfo;
	let cpos = index(userinfo, ':');
	if (cpos >= 0) {
		uuid = substr(userinfo, 0, cpos);
		password = substr(userinfo, cpos + 1);
	}
	let [host, port] = util.split_hostport(um[2]);
	if (!valid_hostport(host, port))
		return [null, 'bad tuic'];
	let out = node.normalize({
		proto: 'tuic', name: name, server: host, port: tonum(port),
		uuid: uuid, password: password, raw: uri,
	});
	if (query.congestion_control)
		out.congestion_control = query.congestion_control;
	if (query.alpn)
		out.alpn = query.alpn;
	if (query.sni)
		out.sni = query.sni;
	return [out];
}

// wireguard://base64(json)#name —— 本项目自定义 scheme（wireguard 无统一 URI 标准）
function parse_wireguard(uri, body) {
	let name = '', rest = body;
	let hash = index(rest, '#');
	if (hash >= 0) {
		name = util.url_decode(substr(rest, hash + 1));
		rest = substr(rest, 0, hash);
	}
	let decoded = util.base64_decode(rest);
	if (decoded == '')
		return [null, 'bad wireguard'];
	let [j, jerr] = util.json_decode(decoded);
	if (type(j) != 'object' || j.server == null || j.port == null)
		return [null, 'bad wireguard json'];
	let data = {
		proto: 'wireguard', name: name, server: j.server, port: tonum(j.port),
	};
	put(data, 'private-key', first(j['private-key'], j.private_key));
	put(data, 'peer-public-key', first(j['peer-public-key'], j.peer_public_key, j['public-key'], j.public_key));
	put(data, 'public-key', first(j['public-key'], j.public_key, j['peer-public-key'], j.peer_public_key));
	put(data, 'preshared-key', first(j['preshared-key'], j.preshared_key, j['pre-shared-key'], j.pre_shared_key));
	put(data, 'pre-shared-key', first(j['pre-shared-key'], j.pre_shared_key, j['preshared-key'], j.preshared_key));
	put(data, 'ip', first(j.ip, j['local-address'], j.local_address));
	put(data, 'ipv6', j.ipv6);
	put(data, 'allowed-ips', first(j['allowed-ips'], j.allowed_ips));
	put(data, 'reserved', j.reserved);
	put(data, 'persistent-keepalive', first(j['persistent-keepalive'], j.persistent_keepalive));
	put(data, 'mtu', tonum(j.mtu));
	put(data, 'dns', j.dns);
	put(data, 'amnezia-wg-option', first(j['amnezia-wg-option'], j.amnezia_wg_option));
	put(data, 'raw', uri);
	let out = node.normalize(data);
	if (out.name == '' && j.name)
		out.name = j.name;
	return [out];
}

// AmneziaWG 参数。字段名与类型逐字段核对自两份一手来源，不靠推断：
//   .conf 键名 → amneziawg-tools src/config.c（process_line，大小写不敏感）
//   规范名/类型 → mihomo adapter/outbound/wireguard.go 的 AmneziaWGOption（proxy tag）
// 内部规范名 = mihomo 的 proxy tag（小写连字符）：Clash 输出直接透传这些键名，
// 所以必须与 mihomo 一致；.conf 导出时再用显式映射换成 CamelCase。
// 未列入的键一律丢弃（不猜语义，§110）。
const AWG_CONF_FIELDS = {
	// v1.0
	jc: 'jc', jmin: 'jmin', jmax: 'jmax',
	s1: 's1', s2: 's2',
	h1: 'h1', h2: 'h2', h3: 'h3', h4: 'h4',
	// v1.5
	s3: 's3', s4: 's4',
	i1: 'i1', i2: 'i2', i3: 'i3', i4: 'i4', i5: 'i5',
	j1: 'j1', j2: 'j2', j3: 'j3', itime: 'itime',
	// v3.0
	headerprotectionkey: 'header-protection-key',
	contentpaddingaddition: 'content-padding-addition',
	rekeyaftertime: 'rekey-after-time',
	rekeytimeout: 'rekey-timeout',
	rejectaftertime: 'reject-after-time',
	keepalivetimeout: 'keepalive-timeout',
	maxhandshakeattempts: 'max-handshake-attempts',
	// v3.1
	randomtrailers: 'random-trailers',
	disablecookies: 'disable-cookies',
};

// 布尔字段（mihomo 侧类型为 bool）。amneziawg-tools 的 parse_bool 只认
// on/off（大小写不敏感）或十进制数（0 假、非 0 真）；true/false/yes/no 都是非法值。
// 非法值一律丢弃：留着会让 mihomo 解析该字段时报错。
const AWG_BOOL_FIELDS = {
	'random-trailers': true,
	'disable-cookies': true,
};

// on/off 或十进制数 → 布尔；其余返回 nil（非法值，丢弃）
function awg_bool(raw) {
	let s = lc(str(raw));
	if (s == 'on')
		return true;
	if (s == 'off')
		return false;
	if (match(s, /^[0-9]+$/))
		return int(s) != 0;
	return null;
}

// wg-quick / AmneziaWG .conf 解析（[Interface] / [Peer] 分段，Key = Value）
// AmneziaWG 客户端导出的 .conf 即标准 wg-quick 格式 + Jc/Jmin/Jmax/S1/S2/H1..H4 等键
// 一个 .conf 可以含多个 [Peer]（wg-quick 的多对端隧道）。本项目的节点模型是
// 「一个节点 = 一个对端」，无法表达多对端隧道；旧实现把所有 [Peer] 写进同一个表，
// 后一段覆盖前一段，结果既丢掉前面的对端，又可能把 A 段的 PresharedKey 和
// B 段的 Endpoint 拼成一个并不存在的节点。这里改为每个 [Peer] 生成一个节点，
// 共享同一份 [Interface] 设置。返回 nodes 数组；失败返回 nil, err。
function parse_wireguard_conf(content) {
	let iface = {};
	let peers = [];
	let section = null;
	for (let line in split_lines(content)) {
		let s = util.trim(line);
		// 行内注释：wg-quick 的 parse_options 用 `stripped="${line%%\#*}"`，即从
		// **第一个** # 起全部丢弃（不要求 # 前有空白）。此处对齐同一语义：否则
		// `Endpoint = 1.2.3.4:51820 # 备用` 会把 "# 备用" 当成值的一部分，
		// split_hostport 取不到端口，整份 .conf 因此作废。
		// wg-quick 不把 ; 当注释符（; 是本实现额外容忍的写法），故 ; 只按整行
		// 注释处理，不参与行内剥离。
		s = util.trim(replace(s, /#.*$/, ''));
		if (s == '' || substr(s, 0, 1) == ';') {
			// 空行 / 纯注释行
		}
		else if (substr(s, 0, 1) == '[') {
			let hm = match(s, /^\[\s*(.*)\s*\]/);
			let name = hm ? lc(util.trim(hm[1])) : '';
			if (name == 'interface') {
				section = iface;
			}
			else if (name == 'peer') {
				let p = {};
				push(peers, p);
				section = p;
			}
			else {
				section = null;
			}
		}
		else if (section != null) {
			let eq = index(s, '=');
			if (eq > 0) {
				let k = lc(util.trim(substr(s, 0, eq)));
				let v = util.trim(substr(s, eq + 1));
				if (v != '')
					section[k] = v;
			}
		}
	}

	// 这条会一路传到用户（M.parse 里 `if not nodes then return nil, err end`），
	// 所以写成完整的英文 msgid，而不是 "bad wireguard conf: …" 那种内部诊断口吻。
	if (length(peers) == 0)
		return [null, 'A WireGuard .conf file has no [Peer] section'];

	// [Interface] 由各节点共享
	let common = { proto: 'wireguard' };
	put(common, 'private-key', iface.privatekey);
	put(common, 'listen-port', tonum(iface.listenport));
	put(common, 'mtu', tonum(iface.mtu));

	// Address 可含多个地址（逗号分隔），按是否含 ":" 分别归入 ip / ipv6
	for (let a in split(iface.address ?? '', ',')) {
		a = util.trim(a);
		if (a != '') {
			if (index(a, ':') >= 0) {
				if (common.ipv6 == null)
					common.ipv6 = a;
			}
			else {
				if (common.ip == null)
					common.ip = a;
			}
		}
	}

	// DNS 拆分：单值存字符串，多值存数组
	let dns = [];
	for (let a in split(iface.dns ?? '', ',')) {
		a = util.trim(a);
		if (a != '')
			push(dns, a);
	}
	if (length(dns) == 1)
		common.dns = dns[0];
	else if (length(dns) > 1)
		common.dns = dns;

	// Reserved（部分客户端写法，逗号或空格分隔）
	let reserved = [];
	for (let a in split(iface.reserved ?? '', /[ \t,]+/)) {
		if (a != '')
			push(reserved, tonum(a) ?? a);
	}
	if (length(reserved) > 0)
		common.reserved = reserved;

	// AmneziaWG [Interface] 参数：按 AWG_CONF_FIELDS 映射成规范名
	let awg = {};
	for (let ck, canon in AWG_CONF_FIELDS) {
		let raw = iface[ck];
		if (raw != null && raw != '') {
			if (AWG_BOOL_FIELDS[canon]) {
				let b = awg_bool(raw);
				if (b != null)
					awg[canon] = b;
			}
			else {
				awg[canon] = tonum(raw) ?? raw;
			}
		}
	}

	// 一层的表拷贝。common 里的 dns / reserved 是数组、awg 是子表，都必须按节点
	// 各拿一份：浅拷贝会让所有节点共享同一个表，之后任何一处改动（例如按节点编辑
	// DNS）会同时改到全部节点。
	function copy1(t) {
		// 数组必须保持数组类型：ucode 的数组与对象是不同类型，用 `{}` 拷贝数组
		// 会得到带 "0"/"1" 键的对象，序列化后就从列表变成映射。
		let o = type(t) == 'array' ? [] : {};
		for (let k, v in t)
			o[k] = v;
		return o;
	}

	let nodes = [];
	for (let p in peers) {
		let [host, port] = util.split_hostport(p.endpoint ?? '');
		// 单个 [Peer] 缺 Endpoint（或 Endpoint 解析不出端口）只跳过它自己：
		// 旧实现直接 return nil，一个坏段就让整份 .conf 作废，同文件里其它完好的
		// 对端全部丢失 —— 与「一个坏节点不该废掉整个订阅」同一原则。
		if (host != null && host != '' && port != null) {
			let out = {};
			for (let k, v in common) {
				if (type(v) == 'object' || type(v) == 'array')
					out[k] = copy1(v);
				else
					out[k] = v;
			}
			out.server = host;
			out.port = tonum(port);
			put(out, 'public-key', p.publickey);
			put(out, 'pre-shared-key', p.presharedkey);
			put(out, 'persistent-keepalive', tonum(p.persistentkeepalive));

			// AllowedIPs 拆分数组
			let allowed = [];
			for (let a in split(p.allowedips ?? '', ',')) {
				a = util.trim(a);
				if (a != '')
					push(allowed, a);
			}
			if (length(allowed) > 0)
				out['allowed-ips'] = allowed;

			// [Peer] 段的 AmneziaWG 参数（AdvancedSecurity）不在此处解析：
			// 它属于 [Peer] 段，而本项目的 amnezia-wg-option 只对应 [Interface] 段，
			// 合并进来会在导出时被写到 [Interface] 下（错误段落）。宁可不支持，
			// 也不要产出一份键位置错误的 .conf（§110）。
			if (length(keys(awg)) > 0)
				out['amnezia-wg-option'] = copy1(awg);

			push(nodes, node.normalize(out));
		}
	}

	// 一个可用 [Peer] 都没有时报错。此处 #peers > 0 已由上面保证，走到这里说明
	// 每个 [Peer] 都缺 Endpoint。不能返回空列表：空列表会被上层当成「解析成功但
	// 0 节点」，用户看到更新成功却一个节点都没有（H4/H5 的静默失败形态）。
	if (length(nodes) == 0)
		return [null, 'A WireGuard .conf file has no [Peer] with a usable Endpoint'];

	return [nodes];
}

// 解析单条节点 URI，返回节点表或 nil, err
M.parse_uri = function(uri) {
	uri = util.trim(uri);
	let m = match(uri, /^([A-Za-z0-9]+):\/\/(.*)$/);
	if (!m)
		return [null, 'no scheme'];
	let proto = lc(m[1]);
	let body = m[2];
	if (!SUPPORTED[proto])
		return [null, 'unsupported proto ' + proto];
	if (proto == 'ss')
		return parse_ss(body);
	if (proto == 'ssr')
		return parse_ssr(body);
	if (proto == 'vless')
		return parse_vless(uri, body);
	if (proto == 'trojan')
		return parse_trojan(uri, body);
	if (proto == 'vmess')
		return parse_vmess(uri, body);
	if (proto == 'hysteria')
		return parse_hysteria(uri, body);
	if (proto == 'hysteria2')
		return parse_hysteria2(uri, body);
	if (proto == 'tuic')
		return parse_tuic(uri, body);
	if (proto == 'wireguard')
		return parse_wireguard(uri, body);
	if (proto == 'anytls')
		return parse_anytls(uri, body);
	if (proto == 'socks' || proto == 'socks5')
		return parse_socks(uri, body);
	return [null, 'unsupported'];
};

function parse_lines(lines) {
	let nodes = [];
	for (let line in lines) {
		line = util.trim(line);
		if (line != '' && index(line, '://') >= 0) {
			let [n] = M.parse_uri(line);
			if (n)
				push(nodes, n);
		}
	}
	return nodes;
}

function parse_json_content(content) {
	let [data, derr] = util.json_decode(content);
	if (type(data) != 'object' && type(data) != 'array')
		return [null, 'Failed to parse JSON'];

	// 客户端配置文件分发：sing-box / V2Ray / Clash JSON
	if (type(data.outbounds) == 'array') {
		let firstout = data.outbounds[0];
		if (type(firstout) == 'object' && firstout.protocol)
			return [parser_json_config.parse_v2ray_json(content), null];
		return [parser_json_config.parse_singbox_json(content), null];
	}
	if (type(data.proxies) == 'array')
		return [parser_json_config.parse_clash_json(content), null];

	// 通用节点数组 / 单节点对象
	let list = type(data) == 'array' ? data : [data];
	let nodes = [];
	for (let o in list) {
		// 协议名可能写在 proto 或 type 里：表单导入落盘的 JSON 用的就是 type
		// （见 M.parse_local 的 form 分支），同一份 JSON 走文本导入也必须解析出
		// 同一个协议，否则 `{"type":"vless",…}` 会被当成 vmess。
		// 两者都没有时保留旧的 vmess 兜底；type 存在但不在 TYPE_MAP 里，说明这是
		// 统一模型承载不了的协议，丢弃而不是兜底成 vmess（理由见 H6 的说明：
		// 凭空造一个字段全错的假节点比丢弃更糟）。
		if (type(o) != 'object')
			continue;
		let proto = o.proto, type_is_proto = false;
		if (proto == null || proto == '') {
			if (o.type == null || o.type == '') {
				proto = 'vmess';
			}
			else {
				proto = parser_clash_yaml.TYPE_MAP[o.type];
				type_is_proto = true;
			}
		}
		if (proto && valid_hostport(o.server, o.port)) {
			// 与 M.parse_local 的 form 分支同样「透传全部字段」：这里原来是硬编码
			// 白名单，只搬 proto/name/server/port/uuid/password/method/net/security/sni，
			// 于是 path / host / cipher / alterId / flow / fp / alpn / tls / obfs 等
			// 全被静默丢掉——ws 节点丢掉 path 就连不上。字段清单散落成多份必然漂移，
			// 统一由 node.normalize 收口。
			let n = {};
			for (let k, v in o)
				n[k] = v;
			n.proto = proto;
			// 只有真的把 type 当作协议名消费掉时才清空它，避免误删 vmess 的
			// header type（output_uri 会读 n.type or n.headerType）
			if (type_is_proto)
				delete n.type;
			n.port = tonum(n.port) ?? n.port;
			if (n.alterId != null)
				n.alterId = tonum(n.alterId) ?? n.alterId;
			if (n.name == null || n.name == '')
				n.name = str(n.server ?? '') + ':' + str(n.port ?? '');
			push(nodes, node.normalize(n));
		}
	}
	return [nodes, null];
}

// 简易 YAML 解析器：处理 Clash YAML proxies 格式
// 支持基本键值对和列表项，不处理复杂嵌套
function parse_yaml_content(content) {
	let raw_nodes = [];
	let lines = split_lines(content);
	let current_node = null;
	let in_proxies = false;
	let proxies_indent = 0;

	// 读取从 start 行开始、缩进大于 min_indent 的 `k: v` 映射，递归处理嵌套 map
	// （sing-box 的 tls: {enabled, server_name, utls: {fingerprint}} 就有两层）。
	// 返回 [map, 下一个未消费的行号]。
	//
	// 单层收集是不够的：内层键会被摊平进外层，`utls.enabled` 会覆盖 `tls.enabled`，
	// `utls.fingerprint` 会变成 `tls.fingerprint`——取值看似还在，语义已经错了。
	let nlines = length(lines);

	// 缩进宽度（行首空白字符数）
	function indent_of(l) {
		let m = match(l, /^[ \t]*/);
		return m ? length(m[0]) : 0;
	}

	// 去掉一层引号
	function unquote(v) {
		return replace(v, /^["'](.*)["']$/, '$1');
	}

	// 读取从 start 行开始、缩进大于 min_indent 的 `- item` 序列。
	// 必须先于 read_map 声明：read_seq 被 read_map 调用，且序列必须先于嵌套 map
	// 尝试——read_map 碰到 `- ` 开头的行会立刻 break，于是 `alpn:` 这种序列键会让
	// 整个子块从该行起被截断——不只 alpn 丢失，排在它后面的键（sing-box 的
	// utls.fingerprint 等）也一并消失。
	function read_seq(start, min_indent) {
		let seq = [], j = start;
		while (j < nlines) {
			let l = lines[j];
			let t = util.trim(l);
			if (t == '') {
				j++;
			}
			else {
				let ind = indent_of(l);
				if (ind <= min_indent)
					break;
				let im = match(t, /^-\s*(.*)$/);
				if (!im)
					break;
				push(seq, unquote(im[1]));
				j++;
			}
		}
		return [seq, j];
	}

	function read_map(start, min_indent) {
		let map = {}, j = start;
		while (j < nlines) {
			let l = lines[j];
			let t = util.trim(l);
			if (t == '') {
				j++;
			}
			else {
				let ind = indent_of(l);
				if (ind <= min_indent || match(t, /^-/))
					break;
				let km = match(t, /^([^:]+):\s*(.*)$/);
				if (!km)
					break;
				let k = util.trim(km[1]), v = util.trim(km[2]);
				if (v != '') {
					// 去掉引号
					map[k] = unquote(v);
					j++;
				}
				else {
					// 先试序列，再试嵌套 map（见 read_seq 的注释：顺序不能反）
					let [seq, sj] = read_seq(j + 1, ind);
					if (length(seq) > 0) {
						map[k] = seq;
						j = sj;
					}
					else {
						let [sub, nj] = read_map(j + 1, ind);
						if (length(keys(sub)) > 0) {
							map[k] = sub;
							j = nj;
						}
						else {
							// 空值且不是嵌套 map / 序列：保持旧行为（跳过该键）
							j++;
						}
					}
				}
			}
		}
		return [map, j];
	}

	// 用 while 而不是 for：值为空的键要向后收集嵌套 map（sing-box 的
	// `tls:` 块），必须能一次吃掉多行。
	let i = 0;
	while (i < nlines) {
		let line = lines[i];
		let trimmed = util.trim(line);
		if (trimmed == '' || substr(trimmed, 0, 1) == '#') {
			i++;
		}
		else if (match(trimmed, /^proxies:\s*$/) || match(trimmed, /^outbounds:\s*$/)) {
			in_proxies = true;
			proxies_indent = indent_of(line);
			current_node = null;
			i++;
		}
		else if (in_proxies) {
			// 检测列表项开始：- name: xxx 或单独的 -
			let list_match = match(line, /^\s*-\s*(.*)$/);
			if (list_match) {
				// 保存上一个节点
				if (current_node != null)
					push(raw_nodes, current_node);
				current_node = {};
				// 检查列表项同一行是否有字段
				let km = match(list_match[1], /^([^:]+):\s*(.+)$/);
				if (km)
					current_node[util.trim(km[1])] = util.trim(km[2]);
				i++;
			}
			else {
				// 解析缩进的字段
				let indent = indent_of(line);
				if (current_node != null && indent > proxies_indent) {
					let km = match(trimmed, /^([^:]+):\s*(.*)$/);
					if (!km) {
						i++;
					}
					else {
						let k = util.trim(km[1]);
						let v = util.trim(km[2]);
						if (v != '') {
							// 去掉引号
							current_node[k] = unquote(v);
							i++;
						}
						else {
							// 值为空：可能是嵌套 map（sing-box 的 tls: {enabled: true, …}）。
							// 原先这类行直接被跳过，于是 security 永远读不到，TLS 整层丢失：
							// 导出的 sing-box 配置里 trojan/vmess/vless 静默退化成明文，
							// hysteria2/tuic 更让客户端以 C.ErrTLSRequired 拒绝启动。
							// 先试序列（alpn: 后面跟 - h2），再试嵌套 map（tls: {...}）
							let [seq, sj] = read_seq(i + 1, indent);
							if (length(seq) > 0) {
								current_node[k] = seq;
								i = sj;
							}
							else {
								let [sub, nj] = read_map(i + 1, indent);
								if (length(keys(sub)) > 0) {
									current_node[k] = sub;
									i = nj;
								}
								else {
									// 空值且不是嵌套 map / 序列：保持旧行为（跳过该键）
									i++;
								}
							}
						}
					}
				}
				else {
					// 遇到缩进减少，结束当前节点
					if (current_node != null) {
						push(raw_nodes, current_node);
						current_node = null;
					}
					in_proxies = false;
					i++;
				}
			}
		}
		else {
			i++;
		}
	}

	// 保存最后一个节点
	if (current_node != null)
		push(raw_nodes, current_node);

	// 协议映射：Clash type -> proto。
	// 复用 parser_clash_yaml 的权威表（单一事实来源），本处曾自维护一份，缺
	// hysteria2/hysteria/tuic/wireguard 且 socks5 未归一，后果是：
	//   * 认不出的 type 被 `or "vmess"` 兜底成 vmess —— 一份 sing-box YAML 里的
	//     hysteria2/tuic/wireguard 出站会变成 4 个没有 uuid 的假 vmess 节点（静默数据损坏）
	//   * socks5 原样保留，而节点页筛选/规则 proto_filter 用的是规范名 socks，节点查不到
	let proto_map = parser_clash_yaml.TYPE_MAP;

	// 转换字段名并归一化
	let result = [];
	for (let n in raw_nodes) {
		let proto = proto_map[first(n.type, n.proto)];
		// 上面的 in_proxies 分支同时接受 `proxies:`（Clash）与 `outbounds:`（sing-box）
		// 两种段名，但两者字段名并不相同：Clash 用 port / name，sing-box 用
		// server_port / tag。此前只读 port / name，导致 sing-box YAML 的 outbounds
		// 全部卡在下面的 `not port` 判断上被静默丢弃（识别了段名却一个节点都拿不到）。
		// 下列别名逐字对照 parser_json_config.parse_singbox_json 读取的键名，
		// 那是本项目读取 sing-box 出站的权威实现，不另立一套。
		let port = first(n.port, n.server_port);
		if (!n || n.server == null || n.server == '' || !port || !proto) {
			// 跳过无效节点 / 未知协议。
			// 未知协议不能兜底成 vmess：那是凭空造出一个字段全错的节点，
			// 比丢弃更糟（用户看到"导入成功"，实际拿到一批不可用的假节点）。
		}
		else {
			// vmess 的加密方式：Clash 写 cipher，sing-box 写 security。
			// security 在 node.normalize 里是 TLS 层，两者语义冲突，因此仅当取值
			// 落在 vmess 加密方式白名单内时才当作 cipher 消费掉，否则留给 TLS 层。
			let vmess_cipher = null;
			if (proto == 'vmess') {
				vmess_cipher = n.cipher;
				if (vmess_cipher == null && n.security != null
					&& node.VMESS_CIPHERS[n.security])
					vmess_cipher = n.security;
			}
			// 同上的字符串真值问题：只认明确的真值写法
			let scv = n['skip-cert-verify'] || n.insecure;
			let skip_cert_verify = null;
			if (scv === true || scv == 'true' || scv == '1')
				skip_cert_verify = true;
			else if (scv === false || scv == 'false' || scv == '0')
				skip_cert_verify = false;
			// sing-box 的 tls 是一个嵌套 map（tls: {enabled, server_name, insecure, alpn}），
			// 上面收集成子表后在这里展开。字段名对照 parser_json_config.parse_singbox_json
			// （本项目读取 sing-box 出站的权威实现），不另立一套。
			let tls_map = type(n.tls) == 'object' ? n.tls : null;
			if (tls_map) {
				// enabled 是显式开关：sing-box 的 OutboundTLSOptions.Enabled 默认 false，
				// 只有 tls 块存在并不代表启用
				let enabled = tls_map.enabled;
				if (enabled === true || enabled == 'true' || enabled == '1') {
					if (tls_map.reality && tls_map.reality != '' && tls_map.reality !== false)
						n.security = 'reality';
					else
						n.security = 'tls';
				}
				else if (tls_map.reality && tls_map.reality != '' && tls_map.reality !== false) {
					n.security = 'reality';
				}
				// server_name / insecure 只在节点顶层没有对应字段时补
				if ((n.sni == null || n.sni == '') && tls_map.server_name)
					n.sni = tls_map.server_name;
				if (scv == null && tls_map.insecure != null) {
					let ins = tls_map.insecure;
					if (ins === true || ins == 'true' || ins == '1')
						skip_cert_verify = true;
					else if (ins === false || ins == 'false' || ins == '0')
						skip_cert_verify = false;
				}
				if (n.alpn == null && tls_map.alpn != null)
					n.alpn = tls_map.alpn;
				// sing-box 的 utls 也是嵌套 map：{enabled, fingerprint}
				let utls = tls_map.utls;
				if (n.fp == null && type(utls) == 'object') {
					let ue = utls.enabled;
					if ((ue === true || ue == 'true' || ue == '1') && utls.fingerprint != null)
						n.fp = utls.fingerprint;
				}
			}
			// sing-box 的 transport 同样是嵌套 map：{type, path, headers.Host,
			// service_name, host}。字段名对照 parser_json_config.parse_singbox_json
			// （本项目读取 sing-box 出站的权威实现），不另立一套。
			// 不展开的话 net 只会取到 n.net / n.network —— sing-box 出站里这两个
			// 字段都不存在，ws / grpc 节点会全部按 tcp 导入，客户端拿明文 tcp 去连
			// 只开了 ws 的端口，握手必然失败且不报错。
			let transport_map = type(n.transport) == 'object' ? n.transport : null;
			let t_net = null, t_path = null, t_host = null;
			if (transport_map) {
				let tt = transport_map.type;
				if (tt == 'ws') {
					t_net = 'ws';
					t_path = transport_map.path;
					if (type(transport_map.headers) == 'object')
						t_host = first(transport_map.headers.Host, transport_map.headers.host);
				}
				else if (tt == 'grpc') {
					t_net = 'grpc';
					t_path = transport_map.service_name;
				}
				else if (tt == 'http') {
					t_net = 'http';
					t_path = transport_map.path;
					// http 的 host 是数组，取首个；httpupgrade 的是单个字符串
					if (type(transport_map.host) == 'array')
						t_host = transport_map.host[0];
					else if (type(transport_map.host) == 'string' && transport_map.host != '')
						t_host = transport_map.host;
				}
				else if (tt == 'httpupgrade') {
					t_net = 'http';
					t_path = transport_map.path;
					if (type(transport_map.host) == 'string' && transport_map.host != '')
						t_host = transport_map.host;
				}
			}
			// 注意不能用 `(cond) and nil or x` 写法：Lua 的 and/or 在 cond 为真时
			// 结果是 nil，会被后面的 or 继续兜底，等于没生效
			let tls_security = n.security;
			if (vmess_cipher != null)
				tls_security = null;
			// 同上：嵌套 map 已展开，标量 tls 才继续往下传。
			// 传 table 下去会被下游的 `if n.tls then` 当成「已启用 TLS」，
			// tls.enabled=false 也会被判成启用。
			let tls_scalar = n.tls;
			if (type(tls_scalar) == 'object' || type(tls_scalar) == 'array')
				tls_scalar = null;
			let node_data = { proto: proto };
			put(node_data, 'name', first(n.name, n.Name, n.tag, str(n.server) + ':' + str(port)));
			put(node_data, 'server', n.server);
			put(node_data, 'port', tonum(port));
			put(node_data, 'uuid', first(n.uuid, n.id));
			// sing-box 的 hysteria/hysteria2 认证字段是 password / auth_str / auth
			put(node_data, 'password', first(n.password, n.auth_str, n.auth));
			put(node_data, 'method', first(n.cipher, n.method));
			// Clash 的 cipher 是 vmess 加密方式；tls 才是 TLS 层，
			// 交由 node.normalize 归一到 security
			put(node_data, 'cipher', vmess_cipher);
			// 嵌套 map 已在上面展开成 security/sni/… ，这里只透传标量写法。
			put(node_data, 'tls', tls_scalar);
			// sing-box 的 vmess.security 已被上面消费为 cipher，不再当 TLS 层
			put(node_data, 'security', tls_security);
			// Clash 写 sni / servername，sing-box 的 tls 子块写 server_name
			put(node_data, 'sni', first(n.sni, n.servername, n.server_name));
			// 下面三项在 tls 子块里展开后挂在 n 上，必须显式带进 node_data，
			// 否则赋值后立刻被丢掉（n 只是个中间收集表，不参与最终结果）。
			// 字段名对照 parser_json_config.parse_singbox_json（本项目读取
			// sing-box 出站的权威实现）：那边同样读 flow 与 tls.alpn。
			put(node_data, 'flow', n.flow);
			put(node_data, 'alpn', n.alpn);
			put(node_data, 'fp', n.fp);
			// sing-box 的 tls.insecure 对应 skip-cert-verify。
			// 行解析器读出来的是字符串，而 "false" / "0" 在 Lua 里也是真值，
			// 直接透传会让 skip-cert-verify=false 变成「跳过证书校验」，故显式判假。
			put(node_data, 'skip-cert-verify', skip_cert_verify);
			// transport 展开的传输层优先：它才是 sing-box 的权威写法
			put(node_data, 'net', first(t_net, n.net, n.network));
			// 简易解析器此前**完全没有**把 path / host 带进 node_data，
			// 于是走这条回退路径的 ws / grpc 节点连 path 与 Host 都丢了
			put(node_data, 'path', first(t_path, n.path));
			put(node_data, 'host', first(t_host, n.host));
			put(node_data, 'alterId', tonum(n.alterId));
			push(result, node.normalize(node_data));
		}
	}

	return result;
}

M.parse_yaml = function(content) {
	// 优先使用完整 Clash YAML 解析器；失败/为空则回退简易解析
	let nodes = parser_clash_yaml.parse(content);
	if (nodes && length(nodes) > 0)
		return nodes;
	return parse_yaml_content(content);
};

// ---------- 局域网订阅链接 ----------

// 把 IPv6 字面量展开成 8 组 16 位数值（仅用于内网判定）；无法解析时返回 nil。
// 必须展开而不是比字符串前缀：`::1` / `0::1` / `0000::1` / `0:0:0:0:0:0:0:1`
// 是同一个地址的不同写法，前缀比较会全部漏判（旧实现即如此，`[0::1]` 被判成公网）。
function expand_v6(s) {
	let zm = match(s, /^[^%]*/);
	s = zm ? zm[0] : s; // 丢弃 zone id（fe80::1%eth0）
	let tail4 = null;
	let hm = match(s, /^(.*):([0-9]+)\.([0-9]+)\.([0-9]+)\.([0-9]+)$/);
	if (hm) {
		let a = int(hm[2]), b = int(hm[3]), c = int(hm[4]), d = int(hm[5]);
		if (a > 255 || b > 255 || c > 255 || d > 255)
			return null;
		tail4 = [a * 256 + b, c * 256 + d];
		s = hm[1];
	}

	function collect(part) {
		let out = [];
		for (let g in split(part, ':')) {
			if (g == '')
				continue;
			if (length(g) > 4 || !match(g, /^[0-9a-fA-F]+$/))
				return null;
			push(out, int(g, 16));
		}
		return out;
	}

	let groups = [];
	let pm = match(s, /^(.*)::(.*)$/);
	if (pm) {
		let left = pm[1], right = pm[2];
		if (index(left, '::') >= 0 || index(right, '::') >= 0)
			return null;
		let lg = collect(left), rg = collect(right);
		if (!lg || !rg)
			return null;
		let zeros = 8 - length(lg) - length(rg) - (tail4 ? 2 : 0);
		if (zeros < 1)
			return null;
		for (let v in lg)
			push(groups, v);
		for (let z = 0; z < zeros; z++)
			push(groups, 0);
		for (let v in rg)
			push(groups, v);
	}
	else {
		let flat = collect(s);
		if (!flat)
			return null;
		for (let v in flat)
			push(groups, v);
	}
	if (tail4) {
		push(groups, tail4[0]);
		push(groups, tail4[1]);
	}
	if (length(groups) != 8)
		return null;
	return groups;
}

// 判断主机是否为内网 / 回环 / 链路本地地址（SSRF 防护）
function is_private_host(host) {
	if (host == null)
		return false;
	host = lc(host);
	if (host == 'localhost')
		return true;
	// IPv6：去掉方括号
	let vm = match(host, /^\[([^\]]+)\]$/);
	if (vm)
		host = vm[1];
	if (index(host, ':') >= 0) {
		let g = expand_v6(host);
		if (!g)
			return false;
		// 未指定地址 :: 与回环 ::1（含 0::1 / 0000::1 / 0:0:0:0:0:0:0:1 等写法）
		let all_zero = true;
		for (let i = 0; i < 7; i++) {
			if (g[i] != 0) {
				all_zero = false;
				break;
			}
		}
		if (all_zero && g[7] <= 1)
			return true;
		// IPv4 映射 / 兼容地址（::ffff:a.b.c.d、::a.b.c.d）按 IPv4 规则判定
		let mapped = true;
		for (let i = 0; i < 5; i++) {
			if (g[i] != 0) {
				mapped = false;
				break;
			}
		}
		if (mapped && (g[5] == 0 || g[5] == 0xffff)) {
			return is_private_host(sprintf('%d.%d.%d.%d',
				int(g[6] / 256), g[6] % 256, int(g[7] / 256), g[7] % 256));
		}
		// ULA fc00::/7 与链路本地 fe80::/10
		if (g[0] >= 0xfc00 && g[0] <= 0xfdff)
			return true;
		if (g[0] >= 0xfe80 && g[0] <= 0xfebf)
			return true;
		return false;
	}
	let m = match(host, /^([0-9]+)\.([0-9]+)\.([0-9]+)\.([0-9]+)$/);
	if (!m)
		return false;
	let a = int(m[1]), b = int(m[2]);
	if (a == 0 || a == 127 || a == 10)
		return true;
	if (a == 100 && b >= 64 && b <= 127)
		return true; // CGNAT 100.64/10
	if (a == 192 && b == 168)
		return true;
	if (a == 172 && b >= 16 && b <= 31)
		return true;
	if (a == 169 && b == 254)
		return true;
	return false;
}

// 检测是否为局域网订阅链接（http/https + 内网主机）
M.detect_local_link = function(url) {
	url = util.trim(url ?? '');
	let sm = match(url, /^([A-Za-z]+):\/\/(.*)$/);
	if (!sm)
		return null;
	let scheme = lc(sm[1]);
	let rest = sm[2];
	if (scheme != 'http' && scheme != 'https')
		return null;
	let authority = match(rest, /^[^\/]*/)[0];
	if (authority == '')
		return null;
	// 去除 userinfo@
	if (index(authority, '@') >= 0) {
		let um = match(authority, /^.*@(.*)$/);
		authority = um ? um[1] : '';
	}
	let host = null;
	if (substr(authority, 0, 1) == '[') {
		let hm = match(authority, /^(\[[^\]]*\])/);
		host = hm ? hm[1] : null;
	}
	else {
		let hm = match(authority, /^([^:]+)/);
		host = hm ? hm[1] : null;
	}
	if (is_private_host(host))
		return true;
	return null;
};

// 解析局域网订阅链接，返回 { scheme, host, port, path, target, name, user }（host/port/path 为字符串；缺失为 nil）
M.parse_local_link = function(url) {
	url = util.trim(url ?? '');
	let sm = match(url, /^([A-Za-z]+):\/\/(.*)$/);
	if (!sm)
		return [null];
	let scheme = lc(sm[1]);
	let rest = sm[2];

	// authority 止于 / 或 ?：`http://host?target=x` 这种「没有路径、直接跟 query」
	// 的写法，旧模式 `[^/]*` 会把 "host?target=x" 整串当成 authority，
	// 于是 host 变成 "host?target=x"、query 全丢（target/name/uid 都没了）。
	let am = match(rest, /^([^\/?]*)(.*)$/);
	let authority = am ? am[1] : rest;
	let remainder = am ? am[2] : '';

	// 去掉 userinfo@（detect_local_link 一直这么做，此处此前漏了）
	if (index(authority, '@') >= 0) {
		let um = match(authority, /^.*@(.*)$/);
		authority = um ? um[1] : '';
	}

	// 提取 host 与 port
	let host = null, port = null;
	if (substr(authority, 0, 1) == '[') {
		let hm = match(authority, /^\[([^\]]+)\]/);
		host = hm ? hm[1] : null;
		let pm = match(authority, /^\[[^\]]+\]:([0-9]+)/);
		port = pm ? pm[1] : null;
	}
	else {
		let hm = match(authority, /^([^:]+)/);
		host = hm ? hm[1] : null;
		let pm = match(authority, /^[^:]+:([0-9]+)/);
		port = pm ? pm[1] : null;
	}

	// 拆分 path 与 query
	let pq = match(remainder, /^([^?]*)(.*)$/);
	let path = pq ? pq[1] : remainder;
	let query = pq ? pq[2] : '';

	let params = {};
	if (query != '' && substr(query, 0, 1) == '?')
		params = query_parse(substr(query, 1));

	// name：优先 ?name=；否则取路径最后一段
	let name = params.name;
	if (name == null || name == '') {
		let nm = path ? match(path, /\/([^\/]+)$/) : null;
		name = nm ? nm[1] : null;
	}

	// user：优先 ?uid= / ?user=；否则取 /<user>/download/ 路径中的用户名
	let user = first(params.uid, params.user);
	if (user == null || user == '') {
		let um = path ? match(path, /\/([^\/]+)\/download\//) : null;
		user = um ? um[1] : null;
	}

	let out = { scheme: scheme };
	put(out, 'host', host);
	put(out, 'port', port);
	put(out, 'path', path);
	put(out, 'target', params.target);
	put(out, 'name', name);
	put(out, 'user', user);
	return [out];
};

// 解析订阅内容，返回 { nodes = {...}, format = "..." } 或 nil, err
// 统一兜底：丢弃残缺节点（缺 server，或端口为空 / 不在 1–65535）。
//
// 这类节点会被写成客户端加载不了的配置，而 mihomo / sing-box / Xray 都是
// 「一个坏节点废掉整份文件」——用户看到的是整个订阅不可用，而不是少一个节点。
// URI 路径一直在各解析器内部做这个校验（valid_hostport），Clash YAML /
// sing-box JSON / Surge 路径漏了：一份 `port: 1e999` 的 YAML 能产出 port=inf
// 的节点，落盘读回来又是 nil。各解析器只管把字段填对，校验统一放在这里。
function finish(nodes, format) {
	let out = [];
	for (let n in (nodes ?? [])) {
		if (type(n) == 'object' && valid_hostport(n.server, n.port))
			push(out, n);
	}
	return { nodes: out, format: format };
}

M.parse = function(content) {
	if (content == null || content == '')
		return [{ nodes: [], format: 'empty' }];
	let format = M.detect(content);
	if (format == 'empty') {
		// 纯空白 / 只有 BOM 的内容：detect 会 trim 并去 BOM 后判为 empty，而上面的
		// `content == ""` 只挡住了完全空串。没有这个分支时，一份「全是空白」的订阅
		// 会一路掉到末尾报「无法识别的订阅格式」—— 对用户是误导，内容确实是空的，
		// 不是格式不认识。与空串保持同一返回形态（0 节点、格式 empty）。
		return [{ nodes: [], format: 'empty' }];
	}
	else if (format == 'uri') {
		return [finish(parse_lines(split_lines(content)), 'uri')];
	}
	else if (format == 'base64') {
		// 兼容标准 base64 与 base64url（- _ 无 padding）：base64_url_decode 两者皆可
		let decoded = util.base64_url_decode(content);
		if (decoded == '')
			return [null, 'Base64 decoding failed'];
		// 解出来的内容本身可能是 YAML / JSON：机场把整份 Clash 配置或 sing-box
		// 配置 base64 后直接下发是很常见的做法。原先一律按 URI 列表解析，这类
		// 订阅会得到 0 个节点且不报错（用户只看到「订阅为空」）。
		// 递归走一遍 detect/parse 复用既有分支；inner == "base64" 时不再递归，
		// 避免 base64 套 base64 时无限递归。外层容器格式仍是 base64。
		let inner = M.detect(decoded);
		if (inner != 'base64' && inner != 'empty' && inner != 'unknown') {
			let [res, err] = M.parse(decoded);
			if (res)
				res.format = 'base64';
			return [res, err];
		}
		return [finish(parse_lines(split_lines(decoded)), 'base64')];
	}
	else if (format == 'json') {
		let [nodes, err] = parse_json_content(content);
		if (!nodes)
			return [null, err];
		return [finish(nodes, 'json')];
	}
	else if (format == 'yaml') {
		let nodes = M.parse_yaml(content);
		return [finish(nodes, 'yaml')];
	}
	else if (format == 'surge') {
		let nodes = parser_surge.parse(content);
		return [finish(nodes, 'surge')];
	}
	else if (format == 'wireguard-conf') {
		let [nodes, err] = parse_wireguard_conf(content);
		if (!nodes)
			return [null, err];
		return [finish(nodes, 'wireguard-conf')];
	}
	return [null, 'Unrecognized subscription format'];
};

// 本地订阅解析：支持文本模式和表单模式
M.parse_local = function(content, mode) {
	mode = mode ?? 'text';
	if (content == null || content == '')
		return [{ nodes: [], format: 'empty' }];
	if (mode == 'form') {
		// 表单模式：content 为 JSON 数组
		let [data, derr] = util.json_decode(content);
		if (type(data) != 'array' && type(data) != 'object')
			return [null, 'Failed to parse form data'];
		let list = type(data) == 'array' ? data : [data];
		let nodes = [];
		for (let item in list) {
			if (type(item) != 'object')
				continue;
			// 透传表单全部字段，仅做协议/别名/类型修正，避免白名单丢字段
			let n = {};
			for (let k, v in item)
				n[k] = v;
			n.proto = first(item.type, item.proto, 'vmess');
			delete n.type;
			if (n.net == null && n.network != null)
				n.net = n.network;
			delete n.network;
			n.port = tonum(n.port) ?? n.port;
			if (n.alterId != null)
				n.alterId = tonum(n.alterId) ?? n.alterId;
			// 字符串布尔转布尔值
			for (let bk in ['udp', 'skip-cert-verify', 'skip_cert_verify']) {
				if (type(n[bk]) == 'string')
					n[bk] = (n[bk] == 'true' || n[bk] == '1');
			}
			if (n['skip-cert-verify'] != null && n.skip_cert_verify == null)
				n.skip_cert_verify = n['skip-cert-verify'];
			// shadowsocks 用 method；vmess/ssr 用 cipher，互为别名
			if (n.method == null && n.cipher != null)
				n.method = n.cipher;
			if (n.cipher == null && n.method != null)
				n.cipher = n.method;
			// SSR 参数别名
			if (n.obfs_param == null && n['obfs-param'] != null)
				n.obfs_param = n['obfs-param'];
			if (n.protocol_param == null && n['protocol-param'] != null)
				n.protocol_param = n['protocol-param'];

			// 表单里所有输入框的值都是字符串，但统一模型里这几个字段是数组
			// （见 parse_wireguard_conf：AllowedIPs/Reserved/DNS 都拆成数组）。
			// 不归一的话，从 UI 编辑 WireGuard 节点会把数组写成标量字符串，
			// 而 mihomo / sing-box 的对应字段是列表类型，导出结果非法。
			for (let lk in ['allowed-ips', 'reserved', 'dns']) {
				if (type(n[lk]) == 'string') {
					let arr = [];
					for (let piece in split(n[lk], /[ \t,]+/)) {
						piece = util.trim(piece);
						if (piece != '')
							push(arr, piece);
					}
					// reserved 是端口保留位，语义上是数字
					if (lk == 'reserved') {
						for (let i = 0; i < length(arr); i++)
							arr[i] = tonum(arr[i]) ?? arr[i];
					}
					if (length(arr) == 0)
						delete n[lk];
					else if (length(arr) == 1 && lk == 'dns')
						n[lk] = arr[0]; // 单值 DNS 保持字符串，与 .conf 解析一致
					else
						n[lk] = arr;
				}
			}

			// amnezia-wg-option 在表单里是一个 JSON 文本框，提交上来是字符串。
			// 下游（output_wireguard_conf / output_clash_meta / output_uri）
			// 一律要求它是 table，字符串会被静默忽略 —— 即从 UI 编辑
			// WireGuard 节点会丢掉全部 AmneziaWG 参数。这里统一解码；
			// 解不开就明确报错，而不是留个字符串让它在导出时无声消失。
			if (type(n['amnezia-wg-option']) == 'string') {
				let s = util.trim(n['amnezia-wg-option']);
				if (s == '') {
					delete n['amnezia-wg-option'];
				}
				else {
					let [opt] = util.json_decode(s);
					if (type(opt) != 'object' && type(opt) != 'array')
						return [null, 'The AmneziaWG options must be a valid JSON object'];
					n['amnezia-wg-option'] = opt;
				}
			}

			if (n.name == null || n.name == '')
				n.name = str(n.server ?? '') + ':' + str(n.port ?? '');
			push(nodes, node.normalize(n));
		}
		return [{ nodes: nodes, format: 'local-form' }];
	}
	// 文本模式：使用通用解析。
	//
	// 但先挡住「一份文本里混了多种格式」：detect() 只认优先级最高的那一种，
	// 其余部分被静默丢弃，而 parse 返回的是合法表 —— 同步报成功，
	// 用户以为整份都导进来了（实测：「URI + WG conf」只剩 WG 节点，
	// 「URI + JSON」只剩 URI 节点，err 均为 nil）。
	// 一次只导入一种格式，混用就明确报错，而不是默默少一半节点。
	let formats = M.detect_all(content);
	if (length(formats) > 1) {
		let names = [];
		for (let f in formats)
			push(names, FORMAT_LABELS[f] ?? f);
		return [null, msg.compose('Mixed formats in one text (',
			msg.compose_list(names, ' + '),
			'): only one format can be imported at a time; split the text and import the parts separately')];
	}
	return M.parse(content);
};

return M;
