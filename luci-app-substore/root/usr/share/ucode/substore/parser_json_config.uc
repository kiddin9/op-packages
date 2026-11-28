// parser_json_config.uc — JSON 配置解析 → 统一节点模型
// luci-app-substore
// 支持 Sing-box、V2Ray、Clash JSON 配置解析。
//
// 移植自 parser_json_config.lua，对外 API 名称与返回结构不变：
//   parse_singbox_json(content) / parse_v2ray_json(content) / parse_clash_json(content)
// 都返回节点数组；空内容或解析失败返回 []。
// 与 Lua 版的差别只在内部：util.json_decode 返回 [value, err]（Lua 版直接返回
// 表或 nil），这里显式检查 err 与顶层类型；JSON 的空对象与空数组由 ucode
// 原生区分（Lua 版两者都是 {}）。

import { isnan } from 'math';

const util = require('substore.util');
const node = require('substore.node');

const M = {};

// 协议映射（与 parser_clash_yaml 的 TYPE_MAP 保持一致）
const proto_map = {
	vmess: 'vmess',
	vless: 'vless',
	trojan: 'trojan',
	shadowsocks: 'shadowsocks',
	ss: 'shadowsocks',
	socks: 'socks',
	socks5: 'socks',
	http: 'http',
	hysteria2: 'hysteria2',
	hysteria: 'hysteria',
	tuic: 'tuic',
	wireguard: 'wireguard',
	ssr: 'ssr',
	anytls: 'anytls'
};

const SUPPORTED = {
	vmess: true, vless: true, trojan: true, shadowsocks: true,
	hysteria2: true, hysteria: true, tuic: true, wireguard: true,
	socks: true, http: true, ssr: true, anytls: true
};

// ---------- 辅助 ----------

function str(v) {
	return v == null ? '' : `${v}`;
}

// Lua 真值：只有 nil / false 为假（0 与空串仍是真）。
// 直接写 `if (x)` 会把 0 / "" 也当成假，与 Lua 版行为不同。
function truthy(v) {
	return v != null && v !== false;
}

// Lua 的 `a or b or c or d`：返回第一个真值，都没有时 null。
function pick(a, b, c, d) {
	if (truthy(a)) return a;
	if (truthy(b)) return b;
	if (truthy(c)) return c;
	if (truthy(d)) return d;
	return null;
}

// Lua 的 tonumber：非数字串返回 nil。ucode 的 + 对非数字得到 NaN，
// 这里统一成 null，避免把 NaN 写进节点字段。
function to_number(v) {
	let n = +v;
	return isnan(n) ? null : n;
}

// Lua 的 type(x) == "table"：ucode 区分数组与对象，这里两者都算。
function is_table(v) {
	let t = type(v);
	return t == 'object' || t == 'array';
}

function is_array(v) {
	return type(v) == 'array';
}

// 只在值非 null 时写入字段。Lua 里 `t.k = nil` 不会产生键，而 ucode 里赋
// null 会产生一个 null 键（导出时会多出 "k": null）。
function set_field(t, k, v) {
	if (v != null)
		t[k] = v;
	return t;
}

// 解析 JSON 配置的公共入口：空内容 / 解析失败 / 顶层不是表 → null
function decode_config(content) {
	if (!content || content == '')
		return null;

	let [data, err] = util.json_decode(content);
	if (err || !is_table(data))
		return null;

	return data;
}

// ---------- Sing-box JSON 解析 ----------
M.parse_singbox_json = function(content) {
	let data = decode_config(content);
	if (data == null)
		return [];

	let nodes = [];
	let outbounds = is_array(data.outbounds) ? data.outbounds : [];

	for (let outbound in outbounds) {
		if (!is_table(outbound))
			continue;

		let proto = proto_map[outbound.type] ?? outbound.type;
		if (!truthy(proto) || !SUPPORTED[proto])
			continue;

		let server = outbound.server;
		let port = outbound.server_port;
		if (!truthy(server) || !truthy(port))
			continue;

		let node_data = {
			proto: proto,
			name: truthy(outbound.tag) ? outbound.tag : str(server) + ':' + str(port),
			server: server,
		};
		set_field(node_data, 'port', to_number(port));

		if (proto == 'vmess' || proto == 'vless') {
			set_field(node_data, 'uuid', outbound.uuid);
			if (truthy(outbound.flow))
				node_data.flow = outbound.flow;
		}
		else if (proto == 'trojan') {
			set_field(node_data, 'password', outbound.password);
		}
		else if (proto == 'shadowsocks') {
			set_field(node_data, 'method', outbound.method);
			set_field(node_data, 'password', outbound.password);
		}
		else if (proto == 'hysteria2' || proto == 'hysteria') {
			set_field(node_data, 'password', pick(outbound.password, outbound.auth_str, outbound.auth));
		}
		else if (proto == 'tuic') {
			set_field(node_data, 'uuid', outbound.uuid);
			set_field(node_data, 'password', outbound.password);
			if (truthy(outbound.congestion_control))
				node_data.congestion_control = outbound.congestion_control;
		}
		else if (proto == 'anytls') {
			set_field(node_data, 'password', outbound.password);
		}
		else if (proto == 'wireguard') {
			set_field(node_data, 'private-key', pick(outbound['private-key'], outbound.private_key));
			set_field(node_data, 'peer-public-key',
				pick(outbound['peer-public-key'], outbound.peer_public_key, outbound['public-key'], outbound.public_key));
			set_field(node_data, 'public-key',
				pick(outbound['public-key'], outbound.public_key, outbound['peer-public-key'], outbound.peer_public_key));
			set_field(node_data, 'preshared-key',
				pick(outbound['preshared-key'], outbound.preshared_key, outbound['pre-shared-key'], outbound.pre_shared_key));
			set_field(node_data, 'pre-shared-key',
				pick(outbound['pre-shared-key'], outbound.pre_shared_key, outbound['preshared-key'], outbound.preshared_key));
			// local_address 允许字符串或字符串数组；数组时按是否含 ":" 分归 ip / ipv6
			let la = pick(outbound['local-address'], outbound.local_address);
			if (is_array(la)) {
				for (let a in la) {
					if (type(a) == 'string' && a != '') {
						if (index(a, ':') >= 0) {
							if (node_data.ipv6 == null) node_data.ipv6 = a;
						}
						else {
							if (node_data.ip == null) node_data.ip = a;
						}
					}
				}
			}
			else if (type(la) == 'string' && la != '') {
				if (index(la, ':') >= 0)
					node_data.ipv6 = la;
				else
					node_data.ip = la;
			}
			set_field(node_data, 'allowed-ips', pick(outbound['allowed-ips'], outbound.allowed_ips));
			set_field(node_data, 'reserved', outbound.reserved);
			set_field(node_data, 'persistent-keepalive',
				pick(outbound['persistent-keepalive'], outbound.persistent_keepalive,
					outbound.persistent_keepalive_interval));
			set_field(node_data, 'listen-port', pick(outbound['listen-port'], outbound.listen_port));
			if (truthy(outbound.mtu))
				node_data.mtu = outbound.mtu;
			set_field(node_data, 'dns', outbound.dns);
			set_field(node_data, 'amnezia-wg-option', pick(outbound['amnezia-wg-option'], outbound.amnezia_wg_option));
		}
		else if (proto == 'socks' || proto == 'http') {
			set_field(node_data, 'username', outbound.username);
			set_field(node_data, 'password', outbound.password);
		}

		// sing-box 用 tls 对象表达 TLS 层。注意 enabled 的缺省值是 false
		// （option/tls.go: `Enabled bool` + omitempty），本输出模块因此总是
		// 显式写 enabled=true。读取侧这里放宽为「只要不是显式 false 就当作
		// 启用」，以便导入那些省略 enabled 的第三方配置时仍能保留 TLS 层。
		if (is_table(outbound.tls)) {
			let tls = outbound.tls;
			if (truthy(tls.server_name))
				node_data.sni = tls.server_name;
			if (tls.enabled !== false)
				node_data.security = 'tls';
			if (truthy(tls.alpn))
				node_data.alpn = tls.alpn;
			if (tls.insecure != null)
				node_data['skip-cert-verify'] = tls.insecure;
			// uTLS 指纹。简易 YAML 侧早就读了这个字段，JSON 侧一直漏着，
			// 同一条订阅走两条导入路径会得到不同的节点。
			if (is_table(tls.utls) && truthy(tls.utls.fingerprint))
				node_data.fp = tls.utls.fingerprint;
			// Reality：sing-box 的键是 tls.reality.{enabled, public_key, short_id}
			// （option/tls.go 的 OutboundRealityOptions）。这里必须把
			// security 覆写成 "reality" —— 上面那句 `if (tls.enabled !== false)
			// node_data.security = 'tls'` 已经把它写成了 "tls"，不覆写的话导出到
			// mihomo / Xray 时 Reality 参数会连同 security 一起丢掉，节点降级成
			// 普通 TLS 后连不上。
			let rz = tls.reality;
			if (is_table(rz) && rz.enabled !== false && truthy(rz.public_key)) {
				node_data.security = 'reality';
				node_data['public-key'] = rz.public_key;
				if (truthy(rz.short_id))
					node_data['short-id'] = rz.short_id;
			}
		}

		// sing-box 只有 vmess 出站有 security 字段，且它是加密方式
		// （cipher），不是 TLS 层；TLS 由上面的 tls 对象表达
		if (truthy(outbound.security) && proto == 'vmess')
			node_data.cipher = outbound.security;
		if (truthy(outbound.network))
			node_data.net = outbound.network;

		// sing-box 用 transport 对象表达传输层，字段名与 v2ray 的
		// streamSettings 完全不同（上游 configuration/shared/v2ray-transport/）：
		//   ws           path、headers.Host
		//   grpc         service_name
		//   http         path、host（**数组**）
		//   httpupgrade  path、host（**单个字符串**）
		//   quic         本项目模型没有该传输方式，不猜映射
		// 只读 outbound.network 是不够的：sing-box 出站里根本没有这个字段，
		// 于是 ws / grpc / h2 节点全部按 tcp 导入 —— 客户端拿明文 tcp 去连
		// 只开了 ws 的端口，握手必然失败且不报错。这类节点在机场导出的
		// sing-box 配置里占比很高。
		if (is_table(outbound.transport)) {
			let t = outbound.transport;
			if (t.type == 'ws') {
				node_data.net = 'ws';
				if (truthy(t.path))
					node_data.path = t.path;
				if (is_table(t.headers))
					set_field(node_data, 'host', pick(t.headers.Host, t.headers.host));
			}
			else if (t.type == 'grpc') {
				node_data.net = 'grpc';
				if (truthy(t.service_name))
					node_data.path = t.service_name;
			}
			else if (t.type == 'http') {
				node_data.net = 'http';
				if (truthy(t.path))
					node_data.path = t.path;
				if (is_array(t.host)) {
					if (truthy(t.host[0]))
						node_data.host = t.host[0];
				}
				else if (type(t.host) == 'string' && t.host != '') {
					node_data.host = t.host;
				}
			}
			else if (t.type == 'httpupgrade') {
				node_data.net = 'http';
				if (truthy(t.path))
					node_data.path = t.path;
				if (type(t.host) == 'string' && t.host != '')
					node_data.host = t.host;
			}
		}

		push(nodes, node.normalize(node_data));
	}

	return nodes;
};

// ---------- V2Ray JSON 解析 ----------
M.parse_v2ray_json = function(content) {
	let data = decode_config(content);
	if (data == null)
		return [];

	let nodes = [];
	let outbounds = is_array(data.outbounds) ? data.outbounds : [];

	for (let outbound in outbounds) {
		if (!is_table(outbound))
			continue;

		let proto = proto_map[outbound.protocol] ?? outbound.protocol;
		if (!truthy(proto) || !SUPPORTED[proto])
			continue;

		let settings = outbound.settings;
		if (!is_table(settings))
			continue;

		let server = null, port = null, uuid = null, password = null;
		let method = null, flow = null, username = null;

		if (proto == 'vmess' || proto == 'vless') {
			let vnext = settings.vnext;
			if (is_array(vnext) && length(vnext) > 0) {
				let sc = vnext[0];
				server = sc.address;
				port = sc.port;
				if (is_array(sc.users) && length(sc.users) > 0) {
					let user = sc.users[0];
					uuid = user.id;
					if (truthy(user.flow))
						flow = user.flow;
				}
			}
		}
		else if (proto == 'trojan') {
			let servers = settings.servers;
			if (is_array(servers) && length(servers) > 0) {
				server = servers[0].address;
				port = servers[0].port;
				password = servers[0].password;
			}
		}
		else if (proto == 'shadowsocks') {
			let servers = settings.servers;
			if (is_array(servers) && length(servers) > 0) {
				server = servers[0].address;
				port = servers[0].port;
				method = servers[0].method;
				password = servers[0].password;
			}
		}
		else if (proto == 'socks' || proto == 'http') {
			let servers = settings.servers;
			if (is_array(servers) && length(servers) > 0) {
				server = servers[0].address;
				port = servers[0].port;
				if (is_array(servers[0].users) && length(servers[0].users) > 0) {
					username = servers[0].users[0].user;
					password = servers[0].users[0].pass;
				}
			}
		}

		if (!truthy(server) || !truthy(port))
			continue;

		let node_data = {
			proto: proto,
			name: truthy(outbound.tag) ? outbound.tag : str(server) + ':' + str(port),
			server: server,
		};
		set_field(node_data, 'port', to_number(port));
		set_field(node_data, 'uuid', uuid);
		set_field(node_data, 'password', password);
		set_field(node_data, 'method', method);
		set_field(node_data, 'flow', flow);
		set_field(node_data, 'username', username);

		let ss2 = outbound.streamSettings;
		if (is_table(ss2)) {
			if (truthy(ss2.network))
				node_data.net = ss2.network;
			if (truthy(ss2.security))
				node_data.security = ss2.security;
			if (is_table(ss2.tlsSettings) && truthy(ss2.tlsSettings.serverName))
				node_data.sni = ss2.tlsSettings.serverName;
			// Reality：Xray 的 realitySettings 是 camelCase
			// （fingerprint / serverName / publicKey / shortId / spiderX）。
			// 原先只读 serverName，publicKey 等全部丢失 —— 导入一份
			// Xray Reality 配置后导出的节点根本连不上。
			// publicKey 是客户端键名；旧配置可能写成 password
			// （Xray 侧 `if c.Password != "" { c.PublicKey = c.Password }`）。
			if (is_table(ss2.realitySettings)) {
				let rs = ss2.realitySettings;
				if (truthy(rs.serverName))
					node_data.sni = rs.serverName;
				if (truthy(rs.fingerprint))
					node_data.fp = rs.fingerprint;
				set_field(node_data, 'public-key', pick(rs.publicKey, rs.password));
				if (truthy(rs.shortId))
					node_data['short-id'] = rs.shortId;
				if (truthy(rs.spiderX))
					node_data['spider-x'] = rs.spiderX;
			}
		}

		push(nodes, node.normalize(node_data));
	}

	return nodes;
};

// ---------- Clash JSON 解析 ----------
M.parse_clash_json = function(content) {
	let data = decode_config(content);
	if (data == null)
		return [];

	let nodes = [];
	let proxies = is_array(data.proxies) ? data.proxies : [];

	for (let proxy in proxies) {
		if (!is_table(proxy))
			continue;

		let proto = proto_map[proxy.type] ?? proxy.type;
		if (!truthy(proto) || !SUPPORTED[proto])
			continue;

		let server = proxy.server;
		let port = proxy.port;
		if (!truthy(server) || !truthy(port))
			continue;

		let node_data = {
			proto: proto,
			name: truthy(proxy.name) ? proxy.name : str(server) + ':' + str(port),
			server: server,
		};
		set_field(node_data, 'port', to_number(port));

		if (proto == 'vmess' || proto == 'vless') {
			set_field(node_data, 'uuid', proxy.uuid);
			if (truthy(proxy.alterId))
				set_field(node_data, 'alterId', to_number(proxy.alterId));
		}
		else if (proto == 'trojan') {
			set_field(node_data, 'password', proxy.password);
		}
		else if (proto == 'shadowsocks') {
			set_field(node_data, 'method', pick(proxy.cipher, proxy.method));
			set_field(node_data, 'password', proxy.password);
		}
		else if (proto == 'hysteria2' || proto == 'hysteria') {
			set_field(node_data, 'password', pick(proxy.password, proxy['auth-str'], proxy.auth_str));
		}
		else if (proto == 'tuic') {
			set_field(node_data, 'uuid', proxy.uuid);
			set_field(node_data, 'password', proxy.password);
		}
		else if (proto == 'anytls') {
			set_field(node_data, 'password', proxy.password);
		}
		else if (proto == 'wireguard') {
			set_field(node_data, 'private-key', pick(proxy['private-key'], proxy.private_key));
			set_field(node_data, 'peer-public-key',
				pick(proxy['peer-public-key'], proxy.peer_public_key, proxy['public-key'], proxy.public_key));
			set_field(node_data, 'public-key',
				pick(proxy['public-key'], proxy.public_key, proxy['peer-public-key'], proxy.peer_public_key));
			set_field(node_data, 'preshared-key',
				pick(proxy['preshared-key'], proxy.preshared_key, proxy['pre-shared-key'], proxy.pre_shared_key));
			set_field(node_data, 'pre-shared-key',
				pick(proxy['pre-shared-key'], proxy.pre_shared_key, proxy['preshared-key'], proxy.preshared_key));
			set_field(node_data, 'ip', pick(proxy.ip, proxy['local-address'], proxy.local_address));
			set_field(node_data, 'ipv6', proxy.ipv6);
			set_field(node_data, 'allowed-ips', pick(proxy['allowed-ips'], proxy.allowed_ips));
			set_field(node_data, 'reserved', proxy.reserved);
			set_field(node_data, 'persistent-keepalive',
				pick(proxy['persistent-keepalive'], proxy.persistent_keepalive));
			set_field(node_data, 'listen-port', pick(proxy['listen-port'], proxy.listen_port));
			if (truthy(proxy.mtu))
				node_data.mtu = proxy.mtu;
			set_field(node_data, 'dns', proxy.dns);
			set_field(node_data, 'amnezia-wg-option', pick(proxy['amnezia-wg-option'], proxy.amnezia_wg_option));
		}
		else if (proto == 'socks' || proto == 'http') {
			set_field(node_data, 'username', proxy.username);
			set_field(node_data, 'password', proxy.password);
		}
		else if (proto == 'ssr') {
			set_field(node_data, 'method', pick(proxy.cipher, proxy.method));
			set_field(node_data, 'password', proxy.password);
			set_field(node_data, 'protocol', proxy.protocol);
			set_field(node_data, 'obfs', proxy.obfs);
			if (truthy(proxy['obfs-param']))
				node_data.obfs_param = proxy['obfs-param'];
			if (truthy(proxy['protocol-param']))
				node_data.protocol_param = proxy['protocol-param'];
		}

		if (truthy(proxy.network))
			node_data.net = proxy.network;
		if (truthy(proxy.sni))
			node_data.sni = proxy.sni;
		else if (truthy(proxy.servername))
			node_data.sni = proxy.servername;
		// uTLS 指纹与 Reality。键名与 parser_clash_yaml 完全一致
		// （client-fingerprint、reality-opts.{public-key, short-id}），
		// 两条 Clash 导入路径必须给出同样的节点，否则同一条订阅换个
		// 文件后缀就会导入出不同的结果。
		// 不读 `fingerprint`：hysteria/hysteria2/tuic 上那是证书固定
		// （SHA256 pin），语义与 uTLS 指纹不同。
		set_field(node_data, 'fp', pick(proxy['client-fingerprint'], proxy.fp));
		if (is_table(proxy['reality-opts'])) {
			let ro = proxy['reality-opts'];
			if (truthy(ro['public-key']))
				node_data['public-key'] = ro['public-key'];
			if (truthy(ro['short-id']))
				node_data['short-id'] = ro['short-id'];
		}
		if (truthy(proxy.tls))
			node_data.tls = proxy.tls;

		push(nodes, node.normalize(node_data));
	}

	return nodes;
};

return M;
