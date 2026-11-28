// output_wireguard_conf.uc — wg-quick / AmneziaWG .conf 输出（纯 ucode）
// luci-app-substore
// 与 parser.parse_wireguard_conf 互为逆操作：导入解析 [Interface] / [Peer]，此处按同格式写回。
//
// 导出 API（名称与 Lua 版一致）：
//   generate(nodes, options) → 返回数组 [text, err]（Lua 多返回值改成数组）：
//     成功： [".conf 文本", null]
//     失败： [null, "错误消息"]
//   调用方：let [text, err] = M.generate(nodes); if (err) ...
//
// 与 Lua 版的差异：只有一个函数有多返回值，已按上述约定改成数组。

const util = require('substore.util');
const msg = require('substore.msg');

const M = {};

// 仅 wireguard 节点可用 .conf 表达；其余协议无法落到单行/单段，直接丢弃
// （与 output_formats.surge_config 丢弃 wireguard 的处理对称）
function is_wireguard(n) {
	let p = lc(`${n.proto ?? ''}`);
	return p == 'wireguard' || p == 'wg';
}

// amnezia-wg-option 子键 → .conf 键。
// 只输出能**确定**名字的键：多词键并不是把首字母大写就能得到 .conf 名
// （header-protection-key 的正确写法是 HeaderProtectionKey，不是 Header-protection-key），
// 靠规则猜出来的名字会被 AmneziaWG 客户端当成未知键，可能整份配置被拒。
// 因此用显式映射，映射不到的键一律不输出（§110：不输出未经验证的 AWG 字段）。
const AWG_CONF_KEY_MAP = {
	jc: 'Jc', jmin: 'Jmin', jmax: 'Jmax',
	s1: 'S1', s2: 'S2', s3: 'S3', s4: 'S4',
	h1: 'H1', h2: 'H2', h3: 'H3', h4: 'H4',
	i1: 'I1', i2: 'I2', i3: 'I3', i4: 'I4', i5: 'I5',
	j1: 'J1', j2: 'J2', j3: 'J3', itime: 'Itime',
	// AWG 3.0 / 3.1（键名核对自 amneziawg-tools src/config.c）
	'header-protection-key': 'HeaderProtectionKey',
	'content-padding-addition': 'ContentPaddingAddition',
	'rekey-after-time': 'RekeyAfterTime',
	'rekey-timeout': 'RekeyTimeout',
	'reject-after-time': 'RejectAfterTime',
	'keepalive-timeout': 'KeepaliveTimeout',
	'max-handshake-attempts': 'MaxHandshakeAttempts',
	'random-trailers': 'RandomTrailers',
	'disable-cookies': 'DisableCookies',
	'advanced-security': 'AdvancedSecurity',
};

// 布尔键在 .conf 里必须写成 on/off：amneziawg-tools 的 parse_bool 只接受
// on/off（大小写不敏感）或十进制数，写 true/false 会被判为非法值。
const AWG_BOOL_CONF_KEYS = {
	RandomTrailers: true, DisableCookies: true, AdvancedSecurity: true,
};

function conf_key(k) {
	return AWG_CONF_KEY_MAP[k];
}

// 值 → .conf 文本：布尔转 on/off，其余转字符串
function conf_val(conf_key_name, v) {
	if (AWG_BOOL_CONF_KEYS[conf_key_name] === true && type(v) == 'bool')
		return v ? 'on' : 'off';
	return `${v}`;
}

// 值可能是标量或数组，统一转为 "a, b, c"
function join_list(v) {
	if (v == null) return null;

	if (type(v) == 'array') {
		let t = [];
		for (let x in v) {
			if (x != null && `${x}` != '')
				push(t, `${x}`);
		}
		if (length(t) == 0) return null;
		return join(', ', t);
	}

	// 对应 Lua 的 ipairs(映射表)：没有整数下标 → 空列表 → nil
	if (type(v) == 'object')
		return null;

	if (`${v}` == '') return null;
	return `${v}`;
}

// Endpoint：IPv6 主机需加方括号（wg-quick 语法）
function endpoint_of(n) {
	let host = n.server;
	let port = n.port;
	if (host == null || host == '' || port == null || port === false) return null;
	host = `${host}`;
	if (index(host, ':') >= 0 && substr(host, 0, 1) != '[')
		host = '[' + host + ']';
	return host + ':' + `${port}`;
}

// 单个节点 → .conf 文本行数组
function build_section(n) {
	let out = [];

	function put(k, v) {
		if (v != null && v != '')
			push(out, k + ' = ' + v);
	}

	push(out, '[Interface]');
	put('PrivateKey', n['private-key'] ?? n.private_key);
	// Address 合并 IPv4 / IPv6
	let addr = [];
	if (n.ip != null) push(addr, n.ip);
	if (n.ipv6 != null) push(addr, n.ipv6);
	put('Address', join_list(addr));
	put('ListenPort', n['listen-port'] ?? n.listen_port);
	put('MTU', n.mtu);
	put('DNS', join_list(n.dns));

	// AmneziaWG 参数：按 .conf 键名排序输出，保证可 diff；
	// 无法确定 .conf 名的键直接跳过（见 AWG_CONF_KEY_MAP 说明）
	let opt = n['amnezia-wg-option'];
	if (type(opt) == 'object') {
		let mapped = [];
		for (let k, v in opt) {
			let ck = conf_key(k);
			if (ck != null)
				push(mapped, [ ck, v ]);
		}
		sort(mapped, (x, y) => (x[0] < y[0] ? -1 : (x[0] > y[0] ? 1 : 0)));
		for (let kv in mapped)
			put(kv[0], conf_val(kv[0], kv[1]));
	}

	push(out, '');
	push(out, '[Peer]');
	put('PublicKey', n['public-key'] ?? n.public_key ?? n['peer-public-key'] ?? n.peer_public_key);
	put('PresharedKey', n['pre-shared-key'] ?? n.pre_shared_key ?? n['preshared-key'] ?? n.preshared_key);
	put('AllowedIPs', join_list(n['allowed-ips']));
	put('Endpoint', endpoint_of(n));
	put('PersistentKeepalive', n['persistent-keepalive']);

	// 说明：不输出 Reserved —— 它不是 wg-quick 标准键，写进 .conf 可能被客户端拒绝。
	// reserved 仍保留在 clash.meta / sing-box / URI 输出中。
	return out;
}

// nodes → wg-quick .conf 文本；返回 [text, err]
// §55/§56：一个 .conf 文件 = 一个 [Interface]。wg-quick / AmneziaWG 客户端按「单条隧道」
// 导入，把多个 [Interface] 段拼进同一个文件会得到客户端无法导入（或只取首段）的畸形配置，
// 因此多于一个 WireGuard 节点时明确报错，而不是静默拼接。
M.generate = function(nodes, options) {
	let wg = [];
	for (let n in (nodes ?? [])) {
		if (type(n) == 'object' && is_wireguard(n))
			push(wg, n);
	}

	if (length(wg) == 0) {
		// 明确报错优于返回空文件：用户能知道是"没有 WireGuard 节点"而非订阅坏了
		return [ null, 'No WireGuard node to export' ];
	}

	if (length(wg) > 1) {
		return [ null, msg.compose('A WireGuard .conf file can hold only one tunnel, but there are ',
			length(wg), ' WireGuard nodes; export a single node instead') ];
	}

	let n = wg[0];

	// PrivateKey 是 wg-quick / AmneziaWG 的必填项：缺了它导出的 .conf 连本项目的
	// parser.detect 都认不出来（detect 要求 [Interface] + PrivateKey 同时存在），
	// 客户端更是无法导入。宁可不导出，也不要产出这种「看起来成功」的残缺文件。
	let priv = n['private-key'] ?? n.private_key;
	if (priv == null || priv == '') {
		return [ null, 'This WireGuard node has no private key (private-key), cannot export .conf' ];
	}

	// 注释行也必须压成单行：节点名来自订阅（不可信），含换行时会注入出真正的
	// 配置行（例如 "x\n[Interface]"），伪造出一段用户没写过的隧道配置
	let lines = [ '# ' + util.one_line(n.name ?? (`${n.server ?? ''}:${n.port ?? ''}`)) ];
	for (let line in build_section(n))
		push(lines, line);

	return [ join('\n', lines) + '\n', null ];
};

return M;
