// output_v2ray.uc — V2Ray / Xray JSON 配置输出（纯 ucode）
// luci-app-substore
//
// 导出 API（名称与 Lua 版一致）：
//   to_outbound(n, tag) → 单个 Xray outbound 对象；协议不受支持时返回 null（单返回值）
//   generate(nodes, options) → 完整 V2Ray / Xray 配置 JSON 字符串（单返回值）
//
// 与 Lua 版的差异：Lua 用 nil 表示「无法生成」，这里返回 null；
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

// Lua 真值判断：只有 nil / false 视为「没有」（ucode 的 if 还会把 0 与空串当假值）。
function present(v) {
	return v != null && v !== false;
}

// 构建 streamSettings
function build_stream_settings(n) {
	let ss = {};
	let net = n.net ?? n.network ?? 'tcp';
	ss.network = net;

	// 传输层
	// 空表必须编码成 {} 而不是 []：Xray 用标准库 json.Unmarshal 解析配置，
	// wsSettings / grpcSettings / httpSettings 在它那边是结构体指针，把数组解进
	// 结构体会直接 UnmarshalTypeError，Xray 拒绝启动。触发条件很普通：grpc 节点
	// 没填服务名、ws 节点既没 path 也没 host。
	// ucode 原生区分 array / object，util.JSON_EMPTY_OBJECT 就是空对象，
	// 不再需要 Lua 版的元表哨兵。
	if (net == 'ws') {
		let ws = util.JSON_EMPTY_OBJECT;
		if (present(n.path) || present(n.host)) {
			ws = {};
			if (present(n.path)) ws.path = n.path;
			if (present(n.host)) ws.headers = { Host: n.host };
		}
		ss.wsSettings = ws;
	}
	else if (net == 'grpc') {
		let g = util.JSON_EMPTY_OBJECT;
		if (present(n.path)) g = { serviceName: n.path };
		ss.grpcSettings = g;
	}
	else if (net == 'http' || net == 'h2') {
		let h = util.JSON_EMPTY_OBJECT;
		if (present(n.host) || present(n.path)) {
			h = {};
			if (present(n.host)) h.host = [ n.host ];
			if (present(n.path)) h.path = n.path;
		}
		ss.httpSettings = h;
	}
	else if (net == 'kcp') {
		ss.kcpSettings = { header: { type: n.headerType ?? 'none' } };
	}

	// 安全层
	let security = n.security;
	let sni = n.sni ?? n.servername;

	if (security == 'reality' && present(n['public-key'])) {
		// Reality 必须写 realitySettings，**不是** tlsSettings。Xray 的 StreamConfig
		// 校验是 `case "reality": if c.REALITYSettings == nil { return nil,
		// errors.New(`REALITY: Empty "realitySettings".`) }` —— 写成 tlsSettings 的
		// reality 节点会被直接拒绝，一个节点废掉整份配置。
		// 客户端字段名取自 infra/conf/transport_security.go 的 REALITYConfig：
		// fingerprint / serverName / publicKey / shortId / spiderX（外加 show）。
		// 注意 publicKey 是**客户端**侧的键名（privateKey 只属于服务端），
		// spiderX 在 Xray 侧缺省为 "/"。
		let rs = { show: false, fingerprint: n.fp ?? 'chrome' };
		if (present(sni)) rs.serverName = sni;
		rs.publicKey = n['public-key'];
		if (present(n['short-id'])) rs.shortId = n['short-id'];
		if (present(n['spider-x'])) rs.spiderX = n['spider-x'];
		ss.security = 'reality';
		ss.realitySettings = rs;
	}
	else if (present(security) && security != 'none') {
		// security 声称 reality 却没有 public-key 时也走这里，但要把 security 降回
		// tls：REALITYConfig.Build() 在公钥为空时直接报错（客户端分支是
		// `empty "password"`，PublicKey 可由 Password 推导），而 StreamConfig 又要求
		// security == "reality" 必须配 realitySettings —— 照抄写出去会让 Xray
		// 拒绝加载**整份**配置。没有公钥就没有 Reality 可言，降级成普通 TLS
		// 至少配置能加载（与 sing-box / mihomo / QX 三个输出端的行为一致：
		// 它们同样只在有 public-key 时才写 Reality 配置）。
		ss.security = (security == 'reality') ? 'tls' : security;
		if (present(sni))
			ss.tlsSettings = { serverName: sni, allowInsecure: false };
	}
	else if (present(n.tls) && n.tls != 'none') {
		ss.security = 'tls';
		if (present(sni)) ss.tlsSettings = { serverName: sni };
	}

	return ss;
}

// 该协议能否落到 V2Ray / Xray outbound。
// 白名单而不是「排除 ssr」：原来的 `proto ~= "ssr"` 会把 hysteria2 / hysteria /
// tuic / wireguard / snell 一并放行，而 to_outbound 里没有它们的分支，全部落进
// 末尾的 else —— 于是生成 `"protocol": "hysteria2"` 这种 Xray 根本不认识的
// outbound，凭据还被塞进无意义的 users 字段。Xray 解析到未知 protocol 会拒绝
// 整份配置，一个节点废掉整个订阅（与 parser 侧丢弃未知协议是同一个理由）。
const V2RAY_PROTOS = {
	vmess: true,
	vless: true,
	trojan: true,
	shadowsocks: true,
	ss: true,
	socks: true,
	socks5: true,
	http: true,
};

function supported(proto) {
	return V2RAY_PROTOS[proto ?? 'vmess'] === true;
}

// 单节点 → V2Ray outbound 表
// tag 可选：完整配置里由 util.unique_tags 统一分配，避免节点重名导致 tag 冲突
M.to_outbound = function(n, tag) {
	let proto = n.proto ?? 'vmess';
	if (!supported(proto)) return null;

	let o = {
		protocol: (proto == 'ss' ? 'shadowsocks' : proto),
		tag: tag ?? n.name ?? (`${n.server ?? ''}:${n.port ?? ''}`),
		settings: {},
		streamSettings: build_stream_settings(n),
	};

	let server = n.server ?? '';
	let port = to_num(n.port) ?? 0;

	if (proto == 'vmess') {
		o.settings.vnext = [ {
			address: server,
			port: port,
			users: [ {
				id: n.uuid ?? '',
				alterId: to_num(n.alterId ?? n.aid ?? 0) ?? 0,
				// users[].security 是 vmess 加密方式，取 cipher 而非 TLS 层
				security: n.cipher ?? 'auto',
			} ],
		} ];
	}
	else if (proto == 'vless') {
		let user = { id: n.uuid ?? '', encryption: 'none' };
		if (present(n.flow)) user.flow = n.flow;
		o.settings.vnext = [ { address: server, port: port, users: [ user ] } ];
	}
	else if (proto == 'trojan') {
		o.settings.servers = [ { address: server, port: port, password: n.password ?? '' } ];
	}
	else if (proto == 'shadowsocks' || proto == 'ss') {
		o.settings.servers = [ {
			address: server,
			port: port,
			method: n.method ?? n.cipher ?? 'aes-256-gcm',
			password: n.password ?? '',
		} ];
	}
	else {
		// socks / http 等。users 只在有用户名时出现：Lua 版 `n.username and {...} or nil`
		// 在字段为 nil 时**整键省略**，这里必须同样省略（写 null 会被 Xray 拒绝）。
		let srv = { address: server, port: port };
		if (present(n.username))
			srv.users = [ { user: n.username, pass: n.password ?? '' } ];
		o.settings.servers = [ srv ];
	}

	return o;
};

// Xray 的 balancer / observatory selector 按「前缀」匹配 outbound tag。
// 若某节点 tag 恰好是 "direct" / "block" / "auto" 的前缀（例如节点名就叫 "d"、"auto"），
// selector 会把这些保留出站一并纳入负载均衡，导致流量被丢进 direct / block。
// 因此把保留 tag 的所有真前缀也登记为冲突，交给 util.unique_tags 加后缀消解。
function reserved_with_prefixes(names) {
	let r = {};

	for (let s in names) {
		r[s] = true;
		for (let i = 1; i < length(s); i++)
			r[substr(s, 0, i)] = true;
	}

	return r;
}

// 生成完整 V2Ray / Xray 配置（outbounds + observatory + routing）。
// 不含 inbounds / dns：这两项会绑定本地监听端口、覆盖用户既有 DNS 设置，
// 由用户在自己的配置里维护，本输出只负责节点与分流。
M.generate = function(nodes, options) {
	let usable = [];
	for (let n in (nodes ?? [])) {
		if (type(n) == 'object' && supported(n.proto))
			push(usable, n);
	}

	let tags = util.unique_tags(usable, reserved_with_prefixes([ 'direct', 'block', 'auto' ]));

	let outbounds = [], proxy_tags = [];
	for (let i = 0; i < length(usable); i++) {
		push(outbounds, M.to_outbound(usable[i], tags[i]));
		push(proxy_tags, tags[i]);
	}

	// direct / block 必须存在：路由规则要按 tag 引用它们
	push(outbounds, { protocol: 'freedom', tag: 'direct', settings: util.JSON_EMPTY_OBJECT });
	push(outbounds, { protocol: 'blackhole', tag: 'block', settings: { response: { type: 'none' } } });

	let routing = {
		domainStrategy: 'IPIfNonMatch',
		rules: [ { type: 'field', ip: [ 'geoip:private' ], outboundTag: 'direct' } ],
	};

	let cfg = { log: { loglevel: 'warning' }, outbounds: outbounds, routing: routing };

	if (length(proxy_tags) > 0) {
		// leastPing 依赖 observatory 的探测结果；不配 observatory 时该策略不生效
		cfg.observatory = {
			subjectSelector: proxy_tags,
			probeUrl: 'https://www.gstatic.com/generate_204',
			probeInterval: '10s',
			enableConcurrency: true,
		};
		routing.balancers = [ { tag: 'auto', selector: proxy_tags, strategy: { type: 'leastPing' } } ];
		push(routing.rules, { type: 'field', network: 'tcp,udp', balancerTag: 'auto' });
	}
	else {
		// 无可用节点时没有 balancer 可引用；首元素 direct 即默认出站
		push(routing.rules, { type: 'field', network: 'tcp,udp', outboundTag: 'direct' });
	}

	return util.json_encode(cfg);
};

return M;
