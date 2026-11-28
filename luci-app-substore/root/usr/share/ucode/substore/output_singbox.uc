// output_singbox.uc — sing-box JSON 配置输出（纯 ucode）
// luci-app-substore
//
// 导出 API（名称与 Lua 版一致）：
//   to_outbound(n, tag)  → 单个 sing-box outbound 对象；不支持时返回 null（单返回值）
//   generate(nodes, options) → 完整 sing-box 配置 JSON 字符串（单返回值）
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

function bool(v) {
	if (v == null) return null;
	if (v === false || v == 'false' || v === 0 || v == '0') return false;
	return true;
}

// 把「数组或逗号分隔字符串」统一成数组（空项丢弃）。
// 节点模型里 wireguard 的 allowed-ips / reserved / dns 形态取决于来源：Clash YAML
// 的嵌套列表解析后是数组，表单导入 / URI 导入后是 "0.0.0.0/0, ::/0" 这样的
// 字符串。字符串原样写进 JSON 会得到 `"allowed_ips":"0.0.0.0/0"`，而 sing-box
// 这几个字段是 []string / []uint8，反序列化失败 → 整份配置拒绝启动。
function as_list(v) {
	let out = [];

	if (type(v) == 'array') {
		for (let x in v) {
			if (x != null && `${x}` != '')
				push(out, x);
		}
	}
	else if (type(v) == 'object') {
		// 对应 Lua 的 ipairs(映射表)：没有整数下标，什么也取不到。
		// （ucode 的 for-in 对对象给的是**键**，不能当列表项用。）
	}
	else {
		// 等价于 Lua 的 gmatch("[^,]+")：连续逗号 / 首尾逗号不产生空项
		for (let x in split(`${v ?? ''}`, ',')) {
			x = trim(x);
			if (x != '')
				push(out, x);
		}
	}

	return out;
}

// 同 as_list，但把每项转成数字（非数字项丢弃）。
// reserved 在 sing-box 里是 []uint8：JSON 里写成 ["1","2","3"]（字符串）同样
// 反序列化失败，必须输出 [1,2,3]。
function as_num_list(v) {
	let out = [];

	for (let x in as_list(v)) {
		let num = to_num(x);
		if (num != null)
			push(out, num);
	}

	return out;
}

// sing-box type 映射
const TYPE_MAP = {
	vmess: 'vmess',
	vless: 'vless',
	trojan: 'trojan',
	shadowsocks: 'shadowsocks',
	ss: 'shadowsocks',
	hysteria2: 'hysteria2',
	hysteria: 'hysteria',
	tuic: 'tuic',
	wireguard: 'wireguard',
	socks: 'socks',
	socks5: 'socks',
	http: 'http',
	// anytls：sing-box 自 1.12.0 起支持（option/anytls.go，type 字面量 "anytls"）。
	anytls: 'anytls',
};

// 该协议能否落到 sing-box outbound（SSR 无法表达，跳过）
function supported(proto) {
	return (TYPE_MAP[proto] ?? proto) != 'ssr';
}

// 构建 TLS 字段
//
// enabled 必须显式写 true：sing-box 的 OutboundTLSOptions.Enabled 是
// `bool` + `json:"enabled,omitempty"`（option/tls.go），缺省值即 false。
// 上游 common/tls/client.go 里 `if !options.Enabled { return dialer, nil }`
// 会直接按明文拨号，hysteria2 / tuic 更会因为 `options.TLS == nil ||
// !options.TLS.Enabled` 返回 C.ErrTLSRequired 而拒绝启动。只输出
// server_name / insecure 而不带 enabled 等于没配 TLS。
function build_tls(n) {
	// 对应 Lua 的 `not (n.security and n.security ~= "none")`：空串在 Lua 里是
	// 真值，因此只有 null / false / "none" 才跳过 TLS 块
	if (!(present(n.security) && n.security != 'none'))
		return null;

	let tls = { enabled: true };

	if (present(n.sni) || present(n.servername))
		tls.server_name = n.sni ?? n.servername;

	if (present(n.alpn)) {
		if (type(n.alpn) == 'string') {
			let list = [];
			for (let p in split(n.alpn, ',')) {
				p = trim(p);
				if (p != '')
					push(list, p);
			}
			tls.alpn = list;
		}
		else {
			tls.alpn = n.alpn;
		}
	}

	if (n['skip-cert-verify'] != null)
		tls.insecure = bool(n['skip-cert-verify']);
	else if (n.skip_cert_verify != null)
		tls.insecure = bool(n.skip_cert_verify);

	// uTLS 指纹与 Reality。键名与 mihomo 完全不同：sing-box 用 snake_case 且
	// 都嵌在 tls 里（option/tls.go 的 OutboundUTLSOptions / OutboundRealityOptions）。
	// Reality 下 uTLS 是**强制**的：上游 common/tls/reality_client.go 里
	// `if options.UTLS == nil || !options.UTLS.Enabled { return nil,
	// E.New("uTLS is required by reality client") }` —— 只写 reality 不写 utls
	// 会让整份配置起不来。
	if (present(n.fp))
		tls.utls = { enabled: true, fingerprint: n.fp };

	if (n.security == 'reality' && present(n['public-key'])) {
		tls.reality = { enabled: true, public_key: n['public-key'] };
		if (present(n['short-id']))
			tls.reality.short_id = n['short-id'];
		// Reality 规范里 fp 不可省略（缺省 chrome）。节点没带 fp 时补默认值，
		// 否则上面那条 uTLS 强制检查会让 sing-box 拒绝加载整份配置。
		if (tls.utls == null)
			tls.utls = { enabled: true, fingerprint: 'chrome' };
	}

	return tls;
}

// 构建传输（transport）字段
function build_transport(n) {
	let net = n.net ?? n.network;
	if (!present(net) || net == 'tcp') return null;

	if (net == 'ws') {
		let t = { type: 'ws' };
		if (present(n.path)) t.path = n.path;
		if (present(n.host))
			t.headers = { Host: n.host };
		return t;
	}

	if (net == 'grpc') {
		let t = { type: 'grpc' };
		if (present(n.path)) t.service_name = n.path;
		return t;
	}

	if (net == 'http' || net == 'h2') {
		let t = { type: 'http' };
		if (present(n.host)) t.host = [ n.host ];
		if (present(n.path)) t.path = n.path;
		return t;
	}

	return null;
}

// 单节点 → sing-box outbound 表
// tag 可选：完整配置里由 util.unique_tags 统一分配，避免节点重名导致 tag 冲突
M.to_outbound = function(n, tag) {
	let stype = TYPE_MAP[n.proto] ?? n.proto;
	if (stype == 'ssr') return null; // sing-box 不支持 SSR，跳过

	let o = {
		type: stype,
		tag: tag ?? n.name ?? (`${n.server ?? ''}:${n.port ?? ''}`),
		server: n.server ?? '',
		server_port: to_num(n.port) ?? 0,
	};

	if (stype == 'vmess') {
		o.uuid = n.uuid ?? '';
		if (n.alterId != null) {
			let aid = to_num(n.alterId);
			if (aid != null) o.alter_id = aid;
		}
		// 此处的 security 是 vmess 加密方式，取 cipher 而非 TLS 层
		o.security = n.cipher ?? 'auto';
		if (present(n.flow)) o.flow = n.flow;
	}
	else if (stype == 'vless') {
		o.uuid = n.uuid ?? '';
		if (present(n.flow)) o.flow = n.flow;
	}
	else if (stype == 'trojan') {
		o.password = n.password ?? '';
	}
	else if (stype == 'shadowsocks') {
		o.method = n.method ?? n.cipher ?? 'aes-256-gcm';
		o.password = n.password ?? '';
		// SIP003 插件。sing-box 的 shadowsocks 出站只有 plugin（字符串）与
		// plugin_opts（字符串）两个字段，plugin_opts 就是 SIP003 的原始参数串
		// （`obfs=http;obfs-host=x`），不做任何翻译 —— 与 mihomo 的映射式
		// plugin-opts 正好相反。
		// 官方文档明确「Only two are supported: obfs-local and v2ray-plugin」，
		// 其余名字（kcptun / shadow-tls / restls / gost-plugin …）sing-box
		// 认不出来，会拒绝加载整份配置，所以按白名单过滤。
		// 丢掉这一项时服务端只接受带插件的握手，导出的配置必然连不上且不报错。
		let p = util.parse_sip003_plugin(n.plugin);
		if (p) {
			let pname = p[0], popts = p[1];
			if (pname == 'obfs-local' || pname == 'v2ray-plugin') {
				o.plugin = pname;
				if (popts != null && popts != '') o.plugin_opts = popts;
			}
		}
	}
	else if (stype == 'hysteria2') {
		o.password = n.password ?? '';
		// 混淆（salamander）：hysteria2 的 obfs 是 { type, password } 对象
		if (present(n.obfs) && n.obfs != '' && n.obfs != 'plain') {
			o.obfs = {
				type: n.obfs,
				password: n['obfs-password'] ?? n.obfs_password ?? '',
			};
		}
	}
	else if (stype == 'hysteria') {
		// hysteria(v1) 与 hysteria2 在 sing-box 里的字段名并不相同（已对照上游文档确认）：
		//   * 认证字段是 auth_str，不是 password（parser_json_config 也是按
		//     outbound.password or outbound.auth_str or outbound.auth 回读的）
		//   * obfs 是普通字符串，不是 { type, password } 对象
		// 注意：sing-box 的 hysteria 出站还要求 up/down（带宽），本项目的节点模型
		// 不承载该字段，需用户在自己的配置里补上（见 CHANGELOG 已知限制）。
		o.auth_str = n.password ?? '';
		if (present(n.obfs) && n.obfs != '' && n.obfs != 'plain')
			o.obfs = n.obfs;
	}
	else if (stype == 'tuic') {
		o.uuid = n.uuid ?? '';
		o.password = n.password ?? '';
		if (present(n.congestion_control)) o.congestion_control = n.congestion_control;
	}
	else if (stype == 'anytls') {
		// anytls 出站的认证字段就是 password，TLS 走通用的 tls 块
		// （parse_anytls 已补 security="tls"，build_tls 因此会写出 tls 对象）。
		o.password = n.password ?? '';
	}
	else if (stype == 'wireguard') {
		let pk = n['private-key'] ?? n.private_key;
		let ppk = n['peer-public-key'] ?? n.peer_public_key ?? n['public-key'] ?? n.public_key;
		let psk = n['pre-shared-key'] ?? n.pre_shared_key ?? n['preshared-key'] ?? n.preshared_key;
		if (present(pk)) o.private_key = pk;
		if (present(ppk)) o.peer_public_key = ppk;
		if (present(psk)) o.pre_shared_key = psk;

		// sing-box 的 local_address 接受字符串或字符串数组；同时有 IPv4/IPv6 时必须用数组，
		// 逗号拼接（"a,b"）不是合法值
		let addr = [];
		if (present(n.ip)) push(addr, n.ip);
		if (present(n.ipv6)) push(addr, n.ipv6);
		if (length(addr) == 1) o.local_address = addr[0];
		else if (length(addr) > 1) o.local_address = addr;

		// 三个字段在 sing-box 里都是列表（allowed_ips/dns 是 []string，reserved 是
		// []uint8），字符串形态必须归一后再写，否则整份配置起不来
		let aips = as_list(n['allowed-ips']);
		if (length(aips) > 0) o.allowed_ips = aips;

		let rsv = as_num_list(n.reserved);
		if (length(rsv) > 0) o.reserved = rsv;

		if (present(n['persistent-keepalive'])) {
			let ka = to_num(n['persistent-keepalive']);
			if (ka != null) o.persistent_keepalive_interval = ka;
		}
		if (present(n['listen-port'])) {
			let lp = to_num(n['listen-port']);
			if (lp != null) o.listen_port = lp;
		}
		if (present(n.mtu)) {
			let mtu = to_num(n.mtu);
			if (mtu != null) o.mtu = mtu;
		}

		let dns = as_list(n.dns);
		if (length(dns) > 0) o.dns = dns;
	}
	else if (stype == 'socks' || stype == 'http') {
		// socks 与 http 出站的认证字段相同（username / password）
		if (present(n.username)) o.username = n.username;
		if (present(n.password)) o.password = n.password;
	}

	let tls = build_tls(n);
	if (tls) o.tls = tls;

	let transport = build_transport(n);
	if (transport) o.transport = transport;

	return o;
};

// 保留 tag：节点名不得与之重名（util.unique_tags 负责消解）
const RESERVED_TAGS = { select: true, auto: true, direct: true, block: true };

// 生成完整 sing-box 配置（outbounds + route）。
// 不含 inbounds / dns：这两项会绑定本地监听端口、覆盖用户既有 DNS 设置，
// 由用户在自己的配置里维护，本输出只负责节点与分流。
//
// 版本兼容说明：route 规则里的 action 字段自 1.11.0 起才存在，其默认值即 "route"，
// 因此这里刻意省略 action —— 未知字段会被 sing-box 拒绝，而省略默认值在
// 1.10 与 1.11+ 上都能工作。
M.generate = function(nodes, options) {
	let usable = [];
	for (let n in (nodes ?? [])) {
		if (type(n) == 'object' && supported(n.proto))
			push(usable, n);
	}

	let tags = util.unique_tags(usable, RESERVED_TAGS);

	let outbounds = [], proxy_tags = [];
	for (let i = 0; i < length(usable); i++) {
		push(outbounds, M.to_outbound(usable[i], tags[i]));
		push(proxy_tags, tags[i]);
	}

	let final;

	if (length(proxy_tags) > 0) {
		// select 供手工切换，auto 自动测速选优
		let sel = { type: 'selector', tag: 'select', outbounds: [ 'auto', 'direct' ] };
		for (let t in proxy_tags) push(sel.outbounds, t);
		sel.default = 'auto';
		push(outbounds, sel);
		push(outbounds, { type: 'urltest', tag: 'auto', outbounds: proxy_tags });
		final = 'select';
	}
	else {
		// 无可用节点时不能生成 selector / urltest（outbounds 不允许为空）
		final = 'direct';
	}

	push(outbounds, { type: 'direct', tag: 'direct' });
	push(outbounds, { type: 'block', tag: 'block' });

	return util.json_encode({
		outbounds: outbounds,
		route: {
			rules: [ { ip_is_private: true, outbound: 'direct' } ],
			final: final,
			auto_detect_interface: true,
		},
	});
};

return M;
