// output_clash_meta.uc — Clash.Meta / Mihomo 格式输出（纯 ucode）
// luci-app-substore
//
// 多返回值约定：ucode 函数只有一个返回值，原 Lua 版的多返回值一律改成数组
// （`[v, err]`）。本模块对外函数均返回单个字符串（与原 Lua 版一致），
// 没有多返回值。
//
// ucode 假值与原 Lua 不同：只有 null / false / 0 / "" / NaN 为假，而 Lua 里
// 0 与空串都是真值。凡原实现依赖 Lua 真值语义的 `if x then` 判定，这里用
// truthy() 显式还原（0 与空串仍视为真），避免空串被误当作「未设置」。

import { isnan } from 'math';

const util = require('substore.util');
// node.uc 只 require util，不反向依赖任何输出模块，因此这里不会形成循环依赖。
// 需要它是因为「哪些协议支持 uTLS 客户端指纹」必须只有一个来源（见
// node.CLIENT_FP_PROTOS 的说明），在输出模块里另抄一份必然漂移。
const node_model = require('substore.node');

const M = {};

// 原 Lua 版的真值判断（nil / false 为假，0 与 "" 为真）
function truthy(v) {
	return v != null && v !== false;
}

// 原 Lua 版的 `a or b`（nil / false 时回退，0 与 "" 不回退）
function lor(a, b) {
	return truthy(a) ? a : b;
}

function str(v) {
	return (v == null || v === false) ? '' : `${v}`;
}

// YAML plain scalar 里不能出现的字符：space、流式集合/映射指示符、锚点/别名、
// 标签/指令前缀、引号与注释符。与 Lua 版的字符集逐字对应。
const PLAIN_UNSAFE = " :#{}[],&*?|>'\"%@`!%";

function has_control(s) {
	for (let i = 0; i < length(s); i++) {
		let c = ord(substr(s, i, 1));
		// C 的 iscntrl：0x00–0x1F 与 0x7F
		if (c < 32 || c == 127)
			return true;
	}
	return false;
}

function esc_yaml(s) {
	s = str(s);
	// 是否需要双引号必须在转义之前判定：转义之后的 \t / \r 只剩「反斜杠 + 字母」，
	// 落在 plain scalar 里会被 YAML 当成两个字面字符而不是制表符/回车。含任何控制
	// 字符（\n \r \t 等）时必须加引号 —— 未加引号的换行/回车会直接破坏文档结构。
	let need_quote = has_control(s);

	// `%` `!` 与开头的 `-` 也是 YAML 的 c-indicator，不能作为 plain scalar 的首字符：
	// `password: %foo` → "found character '%' that cannot start any token"，
	// `name: !x` → 被当成标签（"could not determine a constructor for the tag '!x'"），
	// 裸 `-` → 被当成块序列条目（"sequence entries are not allowed here"）。
	// 三者都会让客户端拒绝**整份**配置。节点名以 `%`/`!` 开头并不罕见（机场命名
	// 很随意），密码里出现 `%` 更是常见，所以必须一起判。
	if (!need_quote) {
		for (let i = 0; i < length(s); i++) {
			if (index(PLAIN_UNSAFE, substr(s, i, 1)) >= 0) {
				need_quote = true;
				break;
			}
		}
	}

	if (!need_quote)
		need_quote = match(s, /^[-?]*:/) != null
			// 首字符是 `-`（含单独的 "-"）时同样要加引号：`^[-?]*:` 只覆盖
			// 「`-` 后跟冒号」的写法，覆盖不到裸 `-` 与 `-foo`。
			|| match(s, /^-/) != null;

	// 转义只在**加引号时**做：未加引号的 plain scalar 里反斜杠就是字面反斜杠，
	// 提前翻倍会让回读得到两个反斜杠（`pa\ss` → 输出 `pa\\ss` → 读回 `pa\\ss`，
	// 密码/路径直接错）。\ 本身不在上面的 need_quote 触发集里，所以含反斜杠的
	// 值恰恰是最容易走到这条路径的一类。
	if (need_quote) {
		s = replace(s, /\\/g, () => '\\\\');
		s = replace(s, /"/g, () => '\\"');
		s = replace(s, /\n/g, () => '\\n');
		s = replace(s, /\r/g, () => '\\r');
		s = replace(s, /\t/g, () => '\\t');
		return '"' + s + '"';
	}

	return s;
}

function indent(level) {
	let out = '';
	for (let i = 0; i < level; i++)
		out += '  ';
	return out;
}

function yaml_list(items, level) {
	let out = [];
	for (let v in items)
		push(out, indent(level) + '- ' + esc_yaml(v));
	return join('\n', out);
}

// 把「数组或逗号分隔字符串」统一成数组。
// mihomo 的 wireguard 出站里 allowed-ips / dns 是 []string、reserved 是 []uint8，
// 三者都**只接受列表**。节点模型里这些字段的形态取决于来源：Clash YAML 的嵌套
// 列表解析后是数组，表单导入 / URI 导入后是 "0.0.0.0/0, ::/0" 这样的字符串。
// 字符串原样输出会得到 `allowed-ips: 0.0.0.0/0` 这个标量，mihomo 反序列化
// 到 []string 失败，**整份配置拒绝加载**。
function as_list(v) {
	let out = [];
	let t = type(v);

	if (t == 'array') {
		for (let x in v) {
			if (x != null && `${x}` != '')
				push(out, x);
		}
	}
	else if (t == 'object') {
		// 原实现在 Lua 里对映射表走 ipairs，得到空列表
	}
	else {
		for (let x in split(str(v), ',')) {
			x = trim(x);
			if (x != '')
				push(out, x);
		}
	}

	return out;
}

// 值可能是数组也可能是逗号分隔字符串：一律输出为 YAML 列表。
// 空列表直接不输出该键（`allowed-ips: []` 同样是非法值）。
function yaml_value(lines, key, v, level) {
	let items = as_list(v);
	if (length(items) == 0)
		return;
	push(lines, indent(level) + key + ':');
	push(lines, yaml_list(items, level + 1));
}

const PROTOCOL_TYPE_MAP = {
	vmess: 'vmess',
	vless: 'vless',
	trojan: 'trojan',
	shadowsocks: 'ss',
	ss: 'ss',
	hysteria2: 'hysteria2',
	tuic: 'tuic',
	wireguard: 'wireguard',
	socks: 'socks5',
	socks5: 'socks5',
	ssr: 'ssr',
	// anytls：mihomo 的 type 字面量就是 "anytls"（adapter/outbound/anytls.go 里
	// AnyTLSOption 的注册名）。Stash 与 mihomo 同源，共用这份映射。
	anytls: 'anytls'
};

function get_clash_type(proto) {
	return PROTOCOL_TYPE_MAP[proto] ?? proto;
}

// 能写 `reality-opts` 的出站类型。mihomo 的 RealityOptions 只挂在
// vless / vmess / trojan 三个出站上（adapter/outbound/{vless,vmess,trojan}.go
// 都声明了 `RealityOpts RealityOptions `proxy:"reality-opts,omitempty"``）；
// anytls 的 AnyTLSOption 里**没有**任何 reality 字段，写了会被静默忽略
// （mihomo 的 proxy 解码器对未知键不报错），节点看起来配了 Reality 实际没配。
// 这里的键是 mihomo 的 type 字面量（get_clash_type 的输出），不是统一模型的 proto。
const REALITY_CTYPES = { vless: true, vmess: true, trojan: true };

// SIP003 插件 → mihomo 的 plugin / plugin-opts。
//
// 名称与参数名都和 SIP003 原文不同，需要逐项翻译：
//   obfs-local / simple-obfs / obfs  →  obfs，          参数 obfs → mode、obfs-host → host
//   v2ray-plugin                    →  v2ray-plugin，  参数 mode → mode、host → host、
//                                                      path → path、tls → tls
//
// mihomo 对这两类插件的参数是**强校验**的（adapter/outbound/shadowsocks.go）：
// obfs 的 mode 不在 {tls,http} 里报 "ss %s obfs mode error"，v2ray-plugin 的
// mode 不是 websocket 同样报错，两者都会让这个 outbound 构造失败，进而拒绝
// 加载**整份**配置 —— 一个坏节点废掉整个订阅。所以参数不全时宁可整个不输出
// 插件，也不能输出一个必然被拒绝的组合。
// 未知插件名直接忽略：mihomo 的 plugin 分支没有收尾 else，未知名字本来就静默跳过。
function ss_plugin_mihomo(node) {
	let parsed = util.parse_sip003_plugin(node.plugin);
	if (!parsed)
		return null;

	let [name, _, opts] = parsed;
	if (!name)
		return null;

	if (name == 'obfs-local' || name == 'simple-obfs' || name == 'obfs') {
		let mode = opts.obfs ?? opts.mode;
		if (mode != 'tls' && mode != 'http')
			return null;
		let out = [['mode', mode]];
		let host = opts['obfs-host'] ?? opts.host;
		if (host)
			push(out, ['host', host]);
		return ['obfs', out];
	}
	else if (name == 'v2ray-plugin') {
		if (opts.mode != 'websocket')
			return null;
		let out = [['mode', 'websocket']];
		if (opts.host)
			push(out, ['host', opts.host]);
		if (opts.path)
			push(out, ['path', opts.path]);
		if (opts.tls === true || opts.tls == 'true')
			push(out, ['tls', 'true']);
		return ['v2ray-plugin', out];
	}

	return null;
}

// 端口必须是有效数字：`port: abc` / `port: 443/tcp` 这类非数字值会让 mihomo
// 拒绝加载整份配置。ucode 的 `+非数字串` 得到 NaN（`+""` / `+null` 得到 0），
// 与 Lua 的 tonumber() or 0 对齐。
function port_num(v) {
	let n = +v;
	if (n == null || isnan(n))
		return 0;
	return n;
}

function format_node(node, name) {
	let lines = [];
	let ctype = get_clash_type(node.proto);
	push(lines, '  - name: ' + esc_yaml(name));
	push(lines, '    type: ' + esc_yaml(ctype));
	push(lines, '    server: ' + esc_yaml(node.server));
	push(lines, '    port: ' + `${port_num(node.port)}`);

	// 协议通用字段
	if (truthy(node.uuid))
		push(lines, '    uuid: ' + esc_yaml(node.uuid));
	if (truthy(node.password))
		push(lines, '    password: ' + esc_yaml(node.password));
	if (truthy(node.method)) {
		if (ctype == 'ss')
			push(lines, '    cipher: ' + esc_yaml(node.method));
	}
	// SIP003 插件。ss 节点带 obfs / v2ray-plugin 时，服务端只接受带插件的
	// 握手；丢掉这一项导出的配置会以明文 SS 去连，必然失败且客户端不报错。
	if (ctype == 'ss' && truthy(node.plugin)) {
		let plugin = ss_plugin_mihomo(node);
		if (plugin) {
			push(lines, '    plugin: ' + esc_yaml(plugin[0]));
			push(lines, '    plugin-opts:');
			for (let kv in plugin[1])
				push(lines, '      ' + esc_yaml(kv[0]) + ': ' + esc_yaml(kv[1]));
		}
	}
	if (truthy(node.cipher)) {
		if (ctype == 'vmess' || ctype == 'vless')
			push(lines, '    cipher: ' + esc_yaml(node.cipher));
	}
	if (truthy(node.net) || truthy(node.network)) {
		let net = lor(node.net, node.network);
		push(lines, '    network: ' + esc_yaml(net));
		// ws 特殊处理
		if (net == 'ws') {
			// ws-opts 是 path 与 headers 的**共同**父键：只有 host 没有 path 时
			// 也必须先把 ws-opts 写出来。原来 ws-opts 行放在 `if node.path` 里面，
			// 于是「有 host、无 path」的节点会输出一个缩进 6 空格的 headers，
			// 而它的父键根本不存在 —— YAML 直接报
			// "mapping values are not allowed here"，客户端拒绝整份配置。
			// 这条路径是真实可达的：Clash YAML 的 ws-opts.headers.Host 与
			// ws-opts.path 是各自独立读取的，表单里也允许只填 host。
			if (truthy(node.path) || truthy(node.host)) {
				push(lines, '    ws-opts:');
				if (truthy(node.path))
					push(lines, '      path: ' + esc_yaml(node.path));
				if (truthy(node.host)) {
					push(lines, '      headers:');
					push(lines, '        Host: ' + esc_yaml(node.host));
				}
			}
		}
		else if (net == 'grpc') {
			// 服务名写在 grpc-opts 里。只写 network: grpc 的话客户端用默认服务名
			// 去连，握手失败——与 ws 丢 path 是同一类问题（原来的实现只写了 network）。
			// 键名对照上游 transport 文档：grpc-service-name，带 grpc- 前缀。
			// 服务名取自 node.path，与 output_v2ray 的 serviceName、
			// output_singbox 的 service_name 同源。
			if (truthy(node.path)) {
				push(lines, '    grpc-opts:');
				push(lines, '      grpc-service-name: ' + esc_yaml(node.path));
			}
		}
		else if (net == 'h2') {
			// 上游 transport 文档：h2-opts.host 是**列表**，h2-opts.path 是标量。
			if (truthy(node.path) || truthy(node.host)) {
				push(lines, '    h2-opts:');
				if (truthy(node.host)) {
					push(lines, '      host:');
					push(lines, '        - ' + esc_yaml(node.host));
				}
				if (truthy(node.path))
					push(lines, '      path: ' + esc_yaml(node.path));
			}
		}
	}

	// TLS 相关
	let tls = false;
	if (truthy(node.security) && node.security != 'none')
		tls = true;
	else if (truthy(node.tls))
		tls = true;
	if (tls)
		push(lines, '    tls: true');

	// servername / sni
	// vmess / vless / trojan 在 mihomo 里用 servername；hysteria / hysteria2 用 sni
	// （已对照上游文档确认：hysteria 系列没有 servername 字段，写了会被忽略，
	// 结果 SNI 丢失 → 客户端拿 IP 校验证书直接握手失败）。hysteria 系列的 sni
	// 由下面的协议专属分支输出。
	// sni 与 servername 是同一个字段的两种写法，必须只输出一个键：Clash YAML 导入
	// 会同时填上两者（先 sni = p.sni or p.servername，随后的字段保留循环又原样复制了
	// servername），各写一行会让 YAML 出现重复键 —— 严格解析器直接报错，宽松解析器
	// 则取最后一个，行为不确定。
	// mihomo 里 vmess / vless / trojan 用 servername；hysteria / hysteria2 与 anytls
	// 用 sni。anytls 的 AnyTLSOption 结构体里**根本没有 servername 字段**（只有
	// sni），写了会被它的解码器静默忽略 —— SNI 丢失，客户端拿 IP 校验证书直接
	// 握手失败，与 hysteria 系列是同一个坑。anytls 的 sni 由下面的协议专属分支输出。
	let uses_sni = (ctype == 'hysteria' || ctype == 'hysteria2' || ctype == 'anytls');
	let tls_name = lor(node.sni, node.servername);
	if (truthy(tls_name) && !uses_sni)
		push(lines, '    servername: ' + esc_yaml(tls_name));

	// 特殊字段
	if (node['skip-cert-verify'] != null)
		push(lines, '    skip-cert-verify: ' + `${node['skip-cert-verify']}`);
	if (node.udp != null)
		push(lines, '    udp: ' + `${node.udp}`);
	if (truthy(node.alpn)) {
		push(lines, '    alpn:');
		let alpn_list = [];
		if (type(node.alpn) == 'string') {
			for (let part in split(node.alpn, ',')) {
				// 原实现的 gmatch("[^,]+") 跳过空段；这里同样跳过
				if (part == '')
					continue;
				push(alpn_list, trim(part));
			}
		}
		else if (type(node.alpn) == 'array') {
			alpn_list = node.alpn;
		}
		for (let v in alpn_list)
			push(lines, '      - ' + esc_yaml(v));
	}
	// uTLS 客户端指纹。键名是 client-fingerprint，**不是** fp —— 详见
	// node.CLIENT_FP_PROTOS 的说明：mihomo 全仓库没有任何结构体声明
	// `proxy:"fp,..."`，而它的解码器对未知键静默忽略，所以旧的 `fp:` 既不报错
	// 也不生效（配置看起来有指纹，实际用默认指纹）。
	// 同时只对真正支持 uTLS 的协议输出：hysteria / hysteria2 / tuic 上的
	// `fingerprint` 是证书固定（SHA256 pin），语义不同，不能拿 fp 顶上。
	if (truthy(node.fp) && node_model.supports_client_fp(node.proto))
		push(lines, '    client-fingerprint: ' + esc_yaml(node.fp));

	// 协议特定字段
	if (ctype == 'vmess') {
		if (node.alterId != null)
			push(lines, '    alterId: ' + `${node.alterId}`);
		if (!truthy(node.cipher))
			push(lines, '    cipher: auto');
	}

	if (ctype == 'vless') {
		// flow 是 XTLS Vision（xtls-rprx-vision）的必需参数。不写的话 mihomo 按
		// 普通 vless 处理，服务端要求 vision 时握手失败。surge / v2ray / URI 三个
		// 输出都写 flow，只有 clashmeta 漏了；parser_clash_yaml 也回读 flow，
		// 所以「Clash YAML → 导出 clashmeta」这条路径上 flow 会凭空消失。
		if (truthy(node.flow))
			push(lines, '    flow: ' + esc_yaml(node.flow));
	}

	// Reality：mihomo 的 RealityOptions 结构体是
	// `{public-key, short-id, support-x25519mlkem768}`，作为出站的 `reality-opts`
	// 子映射。缺 public-key 时 reality 握手无法建立，所以判据取「有没有 public-key」
	// 而不是 security == "reality" —— 与 output_formats / output_singbox 一致，
	// 也免得 security 写法不同（分享链接写 reality，Loon 的行只写 over-tls）
	// 导致同一节点在某个格式下漏掉 Reality 配置。
	// 能写这个子映射的类型见 REALITY_CTYPES；wireguard 顶层的 public-key 是
	// **对端公钥**，与 Reality 无关，绝不能落进这里。
	// uTLS 指纹**不在**这个子映射里 —— 它是代理顶层的 client-fingerprint，
	// 由上面的通用分支输出（两者是独立的键，别合并）。
	if (truthy(REALITY_CTYPES[ctype]) && truthy(node['public-key'])) {
		push(lines, '    reality-opts:');
		push(lines, '      public-key: ' + esc_yaml(node['public-key']));
		if (truthy(node['short-id']))
			push(lines, '      short-id: ' + esc_yaml(node['short-id']));
	}

	if (ctype == 'hysteria2') {
		if (truthy(node.sni))
			push(lines, '    sni: ' + esc_yaml(node.sni));
		// 混淆（salamander）：hysteria2 的 obfs 是 { type, password } 两段
		if (truthy(node.obfs) && node.obfs != '' && node.obfs != 'plain') {
			push(lines, '    obfs: ' + esc_yaml(node.obfs));
			let opw = lor(node['obfs-password'], node.obfs_password);
			if (truthy(opw) && opw != '')
				push(lines, '    obfs-password: ' + esc_yaml(opw));
		}
	}

	if (ctype == 'hysteria') {
		// hysteria(v1)：obfs 只是普通字符串，**没有** obfs-password
		// （obfs-password 是 hysteria2 的 salamander 专属字段，写到 v1 上是非法键）
		if (truthy(node.sni))
			push(lines, '    sni: ' + esc_yaml(node.sni));
		if (truthy(node.obfs) && node.obfs != '' && node.obfs != 'plain')
			push(lines, '    obfs: ' + esc_yaml(node.obfs));
	}

	if (ctype == 'anytls') {
		// 键名是 sni，不是 servername —— 见上面 uses_sni 的说明。
		let sn = lor(node.sni, node.servername);
		if (truthy(sn))
			push(lines, '    sni: ' + esc_yaml(sn));
	}

	if (ctype == 'tuic') {
		if (truthy(node['udp-relay-mode']))
			push(lines, '    udp-relay-mode: ' + esc_yaml(node['udp-relay-mode']));
	}

	if (ctype == 'wireguard') {
		if (truthy(node['private-key']))
			push(lines, '    private-key: ' + esc_yaml(node['private-key']));
		if (truthy(node['public-key']) || truthy(node['peer-public-key']))
			push(lines, '    public-key: ' + esc_yaml(lor(node['public-key'], node['peer-public-key'])));
		if (truthy(node['pre-shared-key']) || truthy(node['preshared-key']))
			push(lines, '    pre-shared-key: ' + esc_yaml(lor(node['pre-shared-key'], node['preshared-key'])));
		if (truthy(node.ip))
			push(lines, '    ip: ' + esc_yaml(node.ip));
		if (truthy(node.ipv6))
			push(lines, '    ipv6: ' + esc_yaml(node.ipv6));
		if (truthy(node['allowed-ips']))
			yaml_value(lines, 'allowed-ips', node['allowed-ips'], 2);
		if (truthy(node.reserved))
			yaml_value(lines, 'reserved', node.reserved, 2);
		if (truthy(node['persistent-keepalive']))
			push(lines, '    persistent-keepalive: ' + esc_yaml(node['persistent-keepalive']));
		if (truthy(node['listen-port']))
			push(lines, '    listen-port: ' + esc_yaml(node['listen-port']));
		if (truthy(node.mtu))
			push(lines, '    mtu: ' + esc_yaml(node.mtu));
		if (truthy(node.dns))
			yaml_value(lines, 'dns', node.dns, 2);
		let awg = node['amnezia-wg-option'];
		if (type(awg) == 'object' || type(awg) == 'array') {
			push(lines, '    amnezia-wg-option:');
			// 排序输出，保证同一节点每次导出结果一致（便于 diff / 校验）
			let awg_keys = keys(awg);
			sort(awg_keys);
			for (let k in awg_keys) {
				// 键名同样要过 esc_yaml。子表是从 Clash YAML / sing-box JSON /
				// wireguard:// 原样拷进来的，键名由订阅内容决定，不是我们写死的：
				// 键里带换行会在第 0 列插进一行，带 `: ` 会写出 `x: 1: 2` 这种
				// 映射值错误 —— 两者都让客户端拒绝整份配置。
				push(lines, '      ' + esc_yaml(k) + ': ' + esc_yaml(awg[k]));
			}
		}
	}

	// socks5 / http 的认证字段都是 username + password（已对照上游 mihomo 文档确认）。
	// password 已由上面的「协议通用字段」输出，这里只补 username——重复输出会让
	// YAML 里出现两个 password 键，属于非法/歧义配置。
	if (ctype == 'socks5' || ctype == 'http') {
		if (truthy(node.username))
			push(lines, '    username: ' + esc_yaml(node.username));
	}

	if (ctype == 'ssr') {
		push(lines, '    cipher: ' + esc_yaml(lor(node.method, lor(node.cipher, 'aes-128-cfb'))));
		push(lines, '    protocol: ' + esc_yaml(lor(node.protocol, 'origin')));
		push(lines, '    obfs: ' + esc_yaml(lor(node.obfs, 'plain')));
		let op = lor(node.obfs_param, node['obfs-param']);
		let pp = lor(node.protocol_param, node['protocol-param']);
		if (truthy(op) && op != '')
			push(lines, '    obfs-param: ' + esc_yaml(op));
		if (truthy(pp) && pp != '')
			push(lines, '    protocol-param: ' + esc_yaml(pp));
	}

	return join('\n', lines);
}

function generate_proxies(nodes, tags) {
	if (!nodes || length(nodes) == 0)
		return 'proxies: []';

	let out = ['proxies:'];
	for (let i = 0; i < length(nodes); i++)
		push(out, format_node(nodes[i], tags[i]));

	return join('\n', out);
}

function generate_groups(nodes, tags, options) {
	let out = ['proxy-groups:'];

	let names = tags;

	let group_name = (options && options.name) ?? 'Proxy';

	function add_members() {
		if (length(names) > 0) {
			for (let n in names)
				push(out, '      - ' + esc_yaml(n));
		}
		else {
			push(out, '      - REJECT');
		}
	}

	// SELECT
	push(out, '  - name: ' + esc_yaml(group_name));
	push(out, '    type: select');
	push(out, '    proxies:');
	add_members();

	// URL-TEST
	push(out, '  - name: URL-Test');
	push(out, '    type: url-test');
	push(out, '    url: http://www.gstatic.com/generate_204');
	push(out, '    interval: 300');
	push(out, '    tolerance: 50');
	push(out, '    proxies:');
	add_members();

	// LOAD-BALANCE
	push(out, '  - name: Load-Balance');
	push(out, '    type: load-balance');
	push(out, '    strategy: round-robin');
	push(out, '    proxies:');
	add_members();

	return join('\n', out);
}

// YAML 标量转义。导出给 output_egern.uc 复用：Egern 的配置同样是给客户端解析的
// YAML，引号规则、控制字符、c-indicator 的处理必须与这里完全一致。另抄一份必然
// 漂移 —— 同一个「未加引号的 `password: %foo` 会让客户端拒绝整份配置」的坑。
M.esc_yaml = esc_yaml;

M.generate = function(nodes, options) {
	options = options ?? {};
	nodes = nodes ?? [];
	let parts = [];

	// 重名节点必须改名后再输出。mihomo 的 parseProxies 遇到重复的 proxy 名会
	// 直接返回 "proxy %s is the duplicate name" 拒绝**整份**配置；节点重名在
	// 订阅里很常见（node.dedup 默认关闭，而且它按 proto+server+port+身份去重，
	// 同名不同服务器根本不会被去掉）。生成组名也要一起占位，节点名撞上组名
	// 同样是 "proxy group %s: the duplicate name"。
	// 与 sing-box / Xray 输出共用 util.unique_tags，两边的改名规则保持一致。
	let group_name = (options && options.name) ?? 'Proxy';
	let reserved = {
		'URL-Test': true,
		'Load-Balance': true,
		DIRECT: true,
		REJECT: true
	};
	reserved[group_name] = true;
	let tags = util.unique_tags(nodes, reserved);

	// 生成 proxies
	push(parts, generate_proxies(nodes, tags));

	// 生成 proxy-groups
	push(parts, generate_groups(nodes, tags, options));

	return join('\n\n', parts);
};

return M;
