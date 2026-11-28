// output_uri.uc — 分享链接（URI）输出：Shadowrocket / V2Ray URI（纯 ucode）
// luci-app-substore
// 生成 vmess:// / vless:// / trojan:// / ss:// / hysteria2:// / tuic:// / ssr:// 分享链接
//
// 导出 API（名称与 Lua 版一致）：
//   to_share_uri(n)      → 单节点 URI 字符串；无法生成时返回 null（单返回值）
//   to_ssr_uri(n)        → ssr:// URI 字符串；无法生成时返回 null（单返回值）
//   to_uri_list(nodes)   → 每行一条的 URI 列表（单返回值）
//   to_shadowrocket(nodes) → base64 编码的 URI 列表（单返回值）
//   to_v2ray_uri(nodes)  → 明文 URI 列表（单返回值）
//
// 与 Lua 版的差异：Lua 返回 nil 表示无法生成，这里统一返回 null；
// 本模块没有多返回值。

import { isnan } from 'math';

const util = require('substore.util');

const M = {};

// Lua tonumber() 语义：null / false / 布尔 / 非数字 → null
// （只接受字符串与数字；ucode 的 `+true` 会得到 1，Lua 的 tonumber(true) 是 nil）
function to_num(v) {
	let t = type(v);
	if (t != 'string' && t != 'int' && t != 'double')
		return null;
	let n = +v;
	if (n == null || isnan(n))
		return null;
	return n;
}

// Lua 真值判断：只有 nil / false 视为「没有」。ucode 的 if 还会把 0 与空串
// 当成假值，因此凡是对应 Lua `if x then` 的条件都走这里，保持逐函数一致。
function present(v) {
	return v != null && v !== false;
}

// URL 编码：保留字母数字 - . _ ~，其余转 %XX
// ucode 的 replace 按字节匹配（UTF-8 多字节字符每个字节各自编码），与 Lua 的
// string.gsub 逐字节语义一致；替换串里的 `%` 没有 Lua 的特殊含义，按字面输出。
function url_encode(s) {
	s = `${s ?? ''}`;
	return replace(s, /[^A-Za-z0-9._~-]/g, (c) => sprintf('%%%02X', ord(c)));
}

// alpn 归一成逗号分隔字符串。
// alpn 可能是数组：Clash YAML 的 alpn 列表与 sing-box JSON 的 tls.alpn 导入后
// 就是数组。直接交给 url_encode 会变成 `table: 0x...` / 逗号拼接的数组元数据，
// 链接里出现 `alpn=table%3A%200x...`（客户端解析失败）。
function alpn_str(v) {
	if (type(v) == 'array')
		return join(',', v);
	return v;
}

// 是否跳过证书校验。模型里的权威字段是 skip-cert-verify（见 parser.lua 中
// hysteria2/hysteria URI 解析处的说明）；insecure 只是 URI 参数名，且**只有**
// URI 解析器会写它 —— Clash YAML / sing-box JSON / 表单导入的节点只有
// skip-cert-verify。只读 insecure 会让这些节点在导出链接时丢掉该项，
// 客户端按严格校验握手直接失败。
function insecure_flag(n) {
	let v = n['skip-cert-verify'];
	if (v == null) v = n.skip_cert_verify;
	if (v == null) v = n.insecure;
	if (v == null) return null;
	if (v === false || v == 'false' || v === 0 || v == '0') return '0';
	return '1';
}

// 生成单节点分享链接；无法生成时返回 null
// 分享链接里的 server 字面量。IPv6 必须加方括号：RFC 3986 的 authority 是
// `host:port`，而裸 IPv6 本身就含冒号，`fd00::1:443` 无法判断哪一段是端口。
// 本项目自己的解析器（util.split_hostport）就拆不开，重新导入得到 0 个节点；
// 规范的客户端同样会拒绝或拆错。output_wireguard_conf 的 Endpoint 一直是这么做的。
function host_literal(server) {
	server = `${server ?? ''}`;
	if (index(server, ':') >= 0 && substr(server, 0, 1) != '[')
		return '[' + server + ']';
	return server;
}

M.to_share_uri = function(n) {
	if (type(n) != 'object' || !present(n.server) || !present(n.port))
		return null;

	let server = host_literal(n.server);
	let port = to_num(n.port) ?? 0;
	let name = url_encode(n.name ?? (server + ':' + `${port}`));
	let proto = lc(`${n.proto ?? ''}`);

	if (proto == 'ss') proto = 'shadowsocks';

	if (proto == 'shadowsocks') {
		let method = n.method ?? n.cipher ?? 'aes-256-gcm';
		let password = n.password ?? '';
		let userinfo = util.base64_encode(method + ':' + password);
		// SIP002：SS-URI = "ss://" userinfo "@" host ":" port [ "/" ] [ "?" plugin ] [ "#" tag ]
		// 插件参数整体做一次百分号编码（`;` 与 `=` 在 query 里必须转义）。
		// 不回写这一项时，带插件的节点导出后再导入就永久丢失插件配置。
		let query = '';
		if (type(n.plugin) == 'string' && n.plugin != '')
			query = '/?plugin=' + url_encode(n.plugin);
		return 'ss://' + userinfo + '@' + server + ':' + `${port}`
			+ query + '#' + name;
	}

	if (proto == 'vmess') {
		let json = {
			v: '2',
			ps: n.name ?? (server + ':' + `${port}`),
			add: server,
			port: `${port}`,
			id: n.uuid ?? '',
			aid: `${n.alterId ?? n.aid ?? 0}`,
			// scy 是 vmess 加密方式，取 cipher 而非 TLS 层
			scy: n.cipher ?? 'auto',
			net: n.net ?? n.network ?? 'tcp',
			type: n.type ?? n.headerType ?? 'none',
			host: n.host ?? '',
			path: n.path ?? '',
			// 经典 vmess JSON 的 tls 字段是 TLS 层（"tls" 或 ""），
			// security 经 node.normalize 归一后是唯一权威来源
			tls: (present(n.security) && n.security != 'none') ? 'tls' : '',
		};
		return 'vmess://' + util.base64_encode(util.json_encode(json));
	}

	if (proto == 'vless') {
		let q = [];
		push(q, 'encryption=none');
		push(q, 'type=' + url_encode(n.net ?? n.network ?? 'tcp'));
		push(q, 'security=' + url_encode(n.security ?? 'none'));
		if (present(n.sni)) push(q, 'sni=' + url_encode(n.sni));
		if (present(n.fp)) push(q, 'fp=' + url_encode(n.fp));
		if (present(n.alpn)) push(q, 'alpn=' + url_encode(alpn_str(n.alpn)));
		if (present(n.path)) push(q, 'path=' + url_encode(n.path));
		if (present(n.host)) push(q, 'host=' + url_encode(n.host));
		if (present(n.flow)) push(q, 'flow=' + url_encode(n.flow));
		// Reality 参数：键名 pbk / sid / spx 来自 Xray 分享链接规范
		// （XTLS/Xray-core discussion #716），mihomo 与 v2rayN 都按它解析。
		// 不写出 pbk 的话，链接导入到任何客户端都得不到 Reality 配置，节点不可用。
		if (present(n['public-key'])) push(q, 'pbk=' + url_encode(n['public-key']));
		if (present(n['short-id'])) push(q, 'sid=' + url_encode(n['short-id']));
		if (present(n['spider-x'])) push(q, 'spx=' + url_encode(n['spider-x']));
		return 'vless://' + (n.uuid ?? '') + '@' + server + ':' + `${port}`
			+ '?' + join('&', q) + '#' + name;
	}

	if (proto == 'trojan') {
		let q = [];
		push(q, 'security=' + url_encode(n.security ?? 'tls'));
		if (present(n.sni)) push(q, 'sni=' + url_encode(n.sni));
		if (present(n.alpn)) push(q, 'alpn=' + url_encode(alpn_str(n.alpn)));
		if (present(n.fp)) push(q, 'fp=' + url_encode(n.fp));
		return 'trojan://' + url_encode(n.password ?? '') + '@' + server + ':' + `${port}`
			+ '?' + join('&', q) + '#' + name;
	}

	if (proto == 'anytls') {
		// anytls:// 分享链接（由 anytls-go 定义）：anytls://[auth@]host[:port]/?sni=..&insecure=..
		// 密码放在 userinfo（auth）位置，端口缺省 443。URI 规范只定义了 sni 与
		// insecure 两个查询参数，alpn 之类只存在于各家客户端的配置文件里 ——
		// 写进链接是非法参数（严格解析器会拒绝，宽松的会静默忽略）。
		let q = [];
		if (present(n.sni)) push(q, 'sni=' + url_encode(n.sni));
		let ins = insecure_flag(n);
		if (ins != null) push(q, 'insecure=' + ins);
		let suffix = length(q) > 0 ? ('?' + join('&', q)) : '';
		return 'anytls://' + url_encode(n.password ?? '') + '@' + server + ':' + `${port}`
			+ suffix + '#' + name;
	}

	if (proto == 'hysteria2' || proto == 'hysteria') {
		let q = [];
		if (present(n.sni)) push(q, 'sni=' + url_encode(n.sni));
		let ins = insecure_flag(n);
		if (ins != null) push(q, 'insecure=' + ins);
		// 混淆：hysteria2 是 salamander，URI 参数为 obfs / obfs-password；
		// hysteria(v1) 的 obfs 只是普通字符串，**没有** obfs-password
		// （写到 v1 链接上是非法参数，且会误导下游客户端）
		if (present(n.obfs) && n.obfs != '' && n.obfs != 'plain') {
			push(q, 'obfs=' + url_encode(n.obfs));
			if (proto == 'hysteria2') {
				let opw = n['obfs-password'] ?? n.obfs_password;
				if (present(opw) && opw != '')
					push(q, 'obfs-password=' + url_encode(opw));
			}
		}
		let suffix = length(q) > 0 ? ('?' + join('&', q)) : '';
		return (proto == 'hysteria2' ? 'hysteria2://' : 'hysteria://')
			+ url_encode(n.password ?? '') + '@' + server + ':' + `${port}`
			+ suffix + '#' + name;
	}

	if (proto == 'tuic') {
		let userinfo = (n.uuid ?? '') + ':' + url_encode(n.password ?? '');
		let q = [];
		if (present(n.congestion_control)) push(q, 'congestion_control=' + url_encode(n.congestion_control));
		if (present(n.alpn)) push(q, 'alpn=' + url_encode(alpn_str(n.alpn)));
		if (present(n.sni)) push(q, 'sni=' + url_encode(n.sni));
		let suffix = length(q) > 0 ? ('?' + join('&', q)) : '';
		return 'tuic://' + userinfo + '@' + server + ':' + `${port}`
			+ suffix + '#' + name;
	}

	if (proto == 'socks5' || proto == 'socks') {
		let userinfo = '';
		if (present(n.username)) {
			userinfo = url_encode(n.username);
			if (present(n.password))
				userinfo = userinfo + ':' + url_encode(n.password);
			userinfo = userinfo + '@';
		}
		return 'socks5://' + userinfo + server + ':' + `${port}` + '#' + name;
	}

	if (proto == 'ssr')
		return M.to_ssr_uri(n);

	if (proto == 'wireguard') {
		// wireguard://base64(json)#name —— 本项目自定义 scheme（wireguard 无统一 URI 标准）
		// 值为 null 的键必须**不写**：util.json_encode 会把对象里的 null 编成
		// 字面量 null（Lua 的 table 则是直接缺键），客户端来回导入时会看到
		// 一堆空字段。
		let json = {
			server: server,
			port: `${port}`,
		};
		function put(key, val) {
			if (val != null) json[key] = val;
		}
		put('private-key', n['private-key'] ?? n.private_key);
		put('public-key', n['public-key'] ?? n.public_key ?? n['peer-public-key'] ?? n.peer_public_key);
		put('peer-public-key', n['peer-public-key'] ?? n.peer_public_key);
		put('pre-shared-key', n['pre-shared-key'] ?? n.pre_shared_key ?? n['preshared-key'] ?? n.preshared_key);
		put('preshared-key', n['preshared-key'] ?? n.preshared_key);
		put('ip', n.ip);
		put('ipv6', n.ipv6);
		put('allowed-ips', n['allowed-ips']);
		put('reserved', n.reserved);
		put('persistent-keepalive', n['persistent-keepalive']);
		put('listen-port', n['listen-port']);
		put('dns', n.dns);
		put('amnezia-wg-option', n['amnezia-wg-option']);
		if (present(n.mtu)) json.mtu = `${n.mtu}`;
		if (present(n.name)) json.name = n.name;
		return 'wireguard://' + util.base64_encode(util.json_encode(json)) + '#' + name;
	}

	return null;
};

// 生成 ssr:// 分享链接（外层与密码为标准 base64，参数为 base64url）
M.to_ssr_uri = function(n) {
	if (type(n) != 'object' || !present(n.server)) return null;
	let server = n.server;
	let port = `${to_num(n.port) ?? 0}`;
	let protocol = n.protocol ?? 'origin';
	let method = n.method ?? n.cipher ?? 'aes-128-cfb';
	let obfs = n.obfs ?? 'plain';
	let password = n.password ?? '';
	let main = join(':', [server, port, protocol, method, obfs, util.base64_encode(password)]);
	let q = [];
	let op = n.obfs_param ?? n['obfs-param'];
	let pp = n.protocol_param ?? n['protocol-param'];
	if (present(op) && op != '') push(q, 'obfsparam=' + util.base64_url_encode(op));
	if (present(pp) && pp != '') push(q, 'protoparam=' + util.base64_url_encode(pp));
	push(q, 'remarks=' + util.base64_url_encode(n.name ?? server));
	if (present(n.group) && n.group != '') push(q, 'group=' + util.base64_url_encode(n.group));
	return 'ssr://' + util.base64_encode(main + '/?' + join('&', q));
};

// 生成 URI 列表（每行一条，丢弃无法生成 URI 的节点）
M.to_uri_list = function(nodes) {
	let out = [];
	for (let n in (nodes ?? [])) {
		let u = M.to_share_uri(n);
		if (u) push(out, u);
	}
	return join('\n', out);
};

// Shadowrocket 订阅：base64 编码的 URI 列表
M.to_shadowrocket = function(nodes) {
	return util.base64_encode(M.to_uri_list(nodes));
};

// V2Ray URI 订阅：明文 URI 列表
M.to_v2ray_uri = function(nodes) {
	return M.to_uri_list(nodes);
};

return M;
