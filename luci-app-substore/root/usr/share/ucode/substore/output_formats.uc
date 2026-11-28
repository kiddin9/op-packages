// output_formats.uc — Surge 系 / Loon / QX / Stash / Plain JSON 输出（纯 ucode）
// （Egern 不在这里：它的配置是 YAML，见 output_egern.uc）
// luci-app-substore
//
// 多返回值约定：ucode 函数只有一个返回值，原 Lua 版的多返回值一律改成数组。
// 本模块只有 M.generate 在原 Lua 版里返回 `nil, err`（未知格式），这里返回
// `[null, err]`，调用方用 `let [text, err] = ...` 解构；其余函数返回单个字符串。
//
// ucode 假值与 Lua 不同（Lua 的 0 与 "" 为真）：原实现依赖 Lua 真值的判断
// 用 truthy() / lor() 显式还原。

const util = require('substore.util');
const clash_meta = require('substore.output_clash_meta');
const msg = require('substore.msg');

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

// 原 Lua `tostring(x or 0)`（nil / false → 0）
function port_str(v) {
	return (v == null || v === false) ? '0' : `${v}`;
}

// 规范化协议名
function props(n) {
	let proto = lc(str(n.proto));
	if (proto == 'ss')
		proto = 'shadowsocks';
	return proto;
}

// Loon 的 VMess「加密方式」（位置参数的第 1 个）取值，取自
// nsloon.app/docs/Node/ 的 VMess 一行：none / auto / aes-128-cfb /
// aes-128-gcm / chacha20-ietf-poly1305。
//
// 与统一模型的 VMESS_CIPHERS（node.uc：auto / none / zero / aes-128-gcm /
// chacha20-poly1305）有两处对不上，直接照抄会让节点在 Loon 上加载失败：
//   * 同一个算法两种拼写：模型写 chacha20-poly1305，Loon 写 chacha20-ietf-poly1305；
//   * 模型的 zero 是 Xray 专用的取值，Loon 的清单里没有。
// 所以做一次显式映射，未列出的取值退回 auto（Loon 与各家都认的默认值）。
// 只用于 Loon；Surge / Surfboard / SurgeMac 的 vmess 走具名 username=，
// 加密方式是另一个参数（encrypt-method），见 LEGACY_ISSUES 的 7.9。
const LOON_VMESS_CIPHER = {
	auto: 'auto', none: 'none',
	'aes-128-gcm': 'aes-128-gcm', 'aes-128-cfb': 'aes-128-cfb',
	'chacha20-poly1305': 'chacha20-ietf-poly1305',
	'chacha20-ietf-poly1305': 'chacha20-ietf-poly1305'
};

// Surge 家族的 VMess「加密方式」是**具名**参数 encrypt-method，与 Loon 把它放在
// 位置参数上不同（manual.nssurge.com/policies/vmess.html 原文：
//   `Name = vmess, <host>, <port>, username=<UUID>[, parameter=value, ...]`
//   encrypt-method 取值只有 aes-128-gcm / chacha20-ietf-poly1305，默认 aes-128-gcm；
//   Surfboard 的 vmess 页同此）。
//
// 只有模型的 chacha20-poly1305 需要写出来：它的拼写与客户端不同
// （chacha20-ietf-poly1305），不写这个参数 Surge 会按默认的 aes-128-gcm 去连，
// chacha20 的节点**静默用错算法**——握手失败或更糟。aes-128-gcm 是客户端默认值，
// 写与不写等价，这里仍写出来是为了让导出结果自解释。
// 其余取值（none / zero / auto / aes-128-cfb）不在客户端的清单里，映射不到就不写
// 该参数、由客户端取默认值；写一个客户端不认的取值是「写了读不懂的东西」，
// 与本文件丢弃 wireguard / ssr 同一约定。
const SURGE_VMESS_CIPHER = {
	'aes-128-gcm': 'aes-128-gcm',
	'chacha20-poly1305': 'chacha20-ietf-poly1305',
	'chacha20-ietf-poly1305': 'chacha20-ietf-poly1305'
};

// 支持 Reality 的目标格式。Reality 只在 Loon 的节点行里有官方文档：
// nsloon.app/docs/Node/ 给出 VLESS / VMess / Trojan / AnyTLS 的 Reality 示例，
// 统一用 public-key / short-id 两个具名参数。
//
// Surge 家族没有 Reality：Surge 手册的协议清单里没有 VLESS，共享 TLS 参数页
// （manual.nssurge.com/policies/tls.html）也只列 skip-cert-verify / sni / alpn /
// server-cert-verify-name / server-cert-fingerprint-sha256 / client-cert，
// 没有任何公钥参数；Surfboard 的 AnyTLS 文档同样只有 password / skip-cert-verify /
// sni / server-cert-fingerprint-sha256 / reuse。给它们写 public-key 是「写了客户端
// 不认识的参数」，节点必然连不上，那个参数对客户端也只是噪声。
// 注意：Surge 对「不认识的代理行 / 参数」的处置**没有官方依据** —— 官方只说明过
// 无法识别的 *section* 会原样保留且不报错，代理行的情况未提及（本仓库早期的注释
// 与 LEGACY_ISSUES 里写的「会拒绝加载整份配置」未经证实，已按此更正）。
// 所以这里的判据是「不写客户端读不懂的东西」，与本文件丢弃 wireguard / ssr 同一约定，
// 不依赖任何未经证实的「整份配置会被拒绝」前提。
// Egern 确实有 Reality，但它的写法是 YAML 里的 reality 对象，与本文件输出的逗号行
// 对不上 —— 那部分由 output_egern.uc 实现（7.2 已实施）。
const REALITY_FLAVORS = { loon: true };

// 各 Surge 系客户端对「非通用协议」的支持情况。
//
// 通用协议（shadowsocks / vmess / trojan / socks5 / http / hysteria2 / tuic /
// anytls）各家都认；各家**不一致**的是 VLESS、SSR 与 Hysteria（v1）三个，
// 所以只记这三个。注意 Hysteria **2** 是通用的，各家都支持；不一致的是它的
// 上一代 Hysteria v1。
// 用一张表而不是给每个调用点传布尔参数：此前是 `supports_ssr` 一个布尔量，
// 加一个维度就要再加一个参数，调用点一多必然漏传（漏传的默认值还是「支持」，
// 于是导出里多出客户端读不懂的行，且不报错）。
//
// 依据（均为各客户端官方文档的协议清单）：
//   * Surge / SurgeMac：manual.nssurge.com 的 Proxy Protocols 一节只列
//     HTTP and HTTP/2、SOCKS5、Shadowsocks、Snell、VMess、Trojan、TUIC、
//     Hysteria 2、MASQUE、AnyTLS、Trust Tunnel、SSH、WireGuard、Tailscale
//     —— 没有 VLESS、没有 ShadowsocksR，也没有 Hysteria（v1）。
//     Hysteria v1 的证据：清单里写的是 "Hysteria 2"，且同目录下
//     manual.nssurge.com/policies/hysteria2.html 存在而 hysteria.html 是 404。
//   * Surfboard：getsurfboard.com 的 external-proxy 清单同样没有 VLESS / SSR。
//     （Surfboard 是否有 Hysteria v1 未获证据：该站文档的
//     profile-format/proxy/external-proxy 一节及其无斜杠形式都返回 404。
//     既然无法证实「读不懂」，就不替它丢弃 —— 见 LEGACY_ISSUES 的 (j)，
//     该条已实施：Surge / SurgeMac 丢弃 Hysteria v1，Surfboard 按此保留。）
//   * Loon：nsloon.app/docs/Node/ 有独立的 VLESS 与 ShadowsocksR 两节，都支持；
//     但节点类型清单里**只有 Hysteria2**，没有 Hysteria（v1）—— 与 Surge 家族
//     相反的两处之一（另一处是 VLESS / SSR）。
//
// Egern **不在**这张表里：它的配置是 YAML，已由 output_egern.uc 单独实现
// （7.2 已实施）。它的协议清单与 Surge 家族本就不同（有 VLESS 与 WireGuard，
// 没有 SSR 与 Hysteria v1），能力判定一并搬到了那个模块里。
//
// 注意 hysteria 指的是**上一代 v1**：Hysteria 2 是各家通用的，被丢的只有 v1
// （两者在 surge_line 里共用同一个输出分支，靠 proto 区分）。
const FAMILY_CAPS = {
	surge:     { vless: false, ssr: false, hysteria: false },
	surfboard: { vless: false, ssr: false },
	surgemac:  { vless: false, ssr: false, hysteria: false },
	// Loon 支持 VLESS 与 SSR（与 Surge 家族相反），但没有 Hysteria v1
	// （节点类型清单里只有 Hysteria2）。标 false 即整条丢弃，与丢弃 wireguard
	// 同一约定：不输出客户端读不懂的东西。
	loon:      { vless: true,  ssr: true, hysteria: false }
};

// 生成 Surge 风格代理行（Surge / Surfboard / SurgeMac / Loon 通用）。
// flavor 取目标格式名，只用于「各客户端写法确实不同」的参数 —— 目前是 AnyTLS
// 密码的位置与 Reality 是否支持；其余参数各家共用同一套 Surge 语法。
M.surge_line = function(n, flavor) {
	flavor = flavor ?? 'surge';
	let proto = props(n);
	let head_parts = [proto, str(n.server), port_str(n.port)];
	// 位置参数：紧跟端口之后的字段（Surfboard / Loon 的 AnyTLS 密码写在这里）。
	// 与 e（具名 key=value 列表）分开攒，最后按「端口, 位置参数…, 具名参数…」拼接。
	let positional = [];
	let e = [];
	let tls = (truthy(n.security) && n.security != 'none')
		|| (truthy(n.tls) && n.tls !== false && n.tls != 'none');

	// TLS 开关的**参数名**各家不同：
	//   Surge / Surfboard / SurgeMac：`tls=true`
	//     （manual.nssurge.com/policies/vmess.html 与 .../vless.html 的 tls 参数）
	//   Loon：`over-tls=true`
	//     （nsloon.app/docs/Node/ 通篇用 over-tls；文档只为 ws 传输列过别名
	//      「ws=true ↔ transport=ws」，从没把 tls 列为 over-tls 的别名）
	// 只换名字，不换语义：两边都是「本连接走 TLS」这一个布尔量。
	let is_loon = (flavor == 'loon');
	let tls_flag = is_loon ? 'over-tls=true' : 'tls=true';

	// Loon 的凭据写法：端口之后的**位置参数**且用双引号包起来
	//   Trojan = Trojan,h,p,"密码"
	//   VLESS  = VLESS,h,p,"UUID"
	//   VMess  = VMess,h,p,加密方式,"UUID"
	// （nsloon.app/docs/Node/）。Surge / Surfboard / SurgeMac 沿用同一套语法的
	// 具名写法（password= / username=），所以只在 flavor == "loon" 时分叉。
	//
	// 返回 nil 表示这个值用带引号的位置参数表达不了：值里本身含双引号时，
	// 包裹后的 `"pa"ss"` 该怎么切由客户端自行决定，没有文档依据 —— 调用方
	// 据此整条丢弃该节点（与「值里含逗号」同一约定，见函数末尾的检查）。
	function loon_positional(v) {
		let s = str(v);
		if (index(s, '"') >= 0)
			return null;
		return '"' + s + '"';
	}

	// ws 传输参数。vmess 与 vless 都要输出：这两个协议在 Surge 家族里共用同一套
	// 参数名，此前只有 vmess 分支写了，vless + ws 的节点导出后丢掉整个传输层，
	// 客户端按 tcp 去连一个只开了 ws 的端口，握手必然失败且不报错。
	function add_ws() {
		if (n.net == 'ws') {
			push(e, 'ws=true');
			if (truthy(n.path))
				push(e, 'ws-path=' + `${n.path}`);
			if (truthy(n.host))
				push(e, 'ws-headers=Host:' + `${n.host}`);
		}
	}

	// Reality 参数。Loon 的 VLESS / VMess / Trojan / AnyTLS Reality 示例共用
	// public-key（Base64 公钥）与 short-id（十六进制）这两个参数名
	// （nsloon.app/docs/Node/ 原文：「public-key 和 short-id 用于 Reality」）。
	//
	// 判据取「有没有 public-key」而不是 security == "reality"：public-key 就是
	// Reality 的凭据，缺了它客户端根本连不上；而 security 在两种来源里含义不同 ——
	// 分享链接写 security=reality，Loon 的行则写 over-tls=true + public-key
	// （security 只是 tls）。只看 security 会漏掉后者，导出后 Reality 参数全丢。
	function add_reality() {
		// 只有 Loon 的节点行文档化了 Reality 参数（见 REALITY_FLAVORS 的说明）
		if (REALITY_FLAVORS[flavor] !== true)
			return;
		if (!truthy(n['public-key']))
			return;
		// Loon 文档把公钥画成带双引号的值，short-id 不带：
		//   `public-key="LgJ9bNTyUqBLFkDA12-QgEL7c1yQ1ztk-V1Q-3OLXSk",short-id=164168844958a16d`
		// （nsloon.app/docs/Node/ 的 VLESS / VMess / Trojan / AnyTLS Reality 示例）。
		// Base64 字母表（A-Za-z0-9+/=）里没有双引号，加引号只是写法对齐，
		// 不会引入歧义，也不会与下面的逗号检查冲突。
		push(e, 'public-key="' + `${n['public-key']}` + '"');
		if (truthy(n['short-id']))
			push(e, 'short-id=' + `${n['short-id']}`);
	}

	if (proto == 'shadowsocks') {
		let cipher = lor(n.method, lor(n.cipher, 'aes-256-gcm'));
		if (is_loon) {
			// Loon 的 Shadowsocks 把加密方式与密码都画在位置参数上，密码带双引号：
			//   `Shadowsocks,服务器,端口,加密方式,"密码"`（nsloon.app/docs/Node/）
			// 加密方式是裸值，与 VMess 行的加密方式同形。
			// 此前写成具名的 encrypt-method= / password=，落在 Loon 的语法里就是
			// 第 4、5 个位置参数各拿到一串 `key=value` 文本 —— 加密方式解析不出来，
			// 密码也不再是密码，节点必然连不上。
			let pw = loon_positional(n.password);
			if (pw == null)
				return null;
			push(positional, cipher);
			push(positional, pw);
		}
		else {
			push(e, 'encrypt-method=' + cipher);
			push(e, 'password=' + str(n.password));
		}
	}
	else if (proto == 'vmess') {
		if (flavor == 'loon') {
			// Loon 的 VMess 把加密方式与 UUID 都放在位置参数上（见 loon_positional）
			let id = loon_positional(n.uuid);
			if (id == null)
				return null;
			// 加密方式取值按 Loon 的拼写映射（见 LOON_VMESS_CIPHER）
			push(positional, LOON_VMESS_CIPHER[n.cipher] ?? 'auto');
			push(positional, id);
		}
		else {
			push(e, 'username=' + str(n.uuid));
			// Surge 家族把加密方式写在具名参数 encrypt-method 上（见 SURGE_VMESS_CIPHER）
			let sc = SURGE_VMESS_CIPHER[n.cipher];
			if (sc)
				push(e, 'encrypt-method=' + sc);
		}
		if (tls)
			push(e, tls_flag);
		if (truthy(n.sni))
			push(e, 'sni=' + `${n.sni}`);
		// VMess 的 Reality 与 VLESS 同形。Loon 文档的 VMess-Reality 示例：
		// `VMess = VMess,host,443,aes-128-gcm,"uuid",transport=tcp,alterId=0,`
		// `public-key="…",short-id=…,over-tls=true`（nsloon.app/docs/Node/）。
		// 此前只在 vless / trojan / anytls 三个分支调了 add_reality()，vmess 的
		// Reality 节点导出到 Loon 后 public-key / short-id 全丢 —— 客户端按普通
		// TLS 去连，REALITY 握手建立不起来，而 Loon 不会因此报错。
		add_reality();
		add_ws();
	}
	else if (proto == 'vless') {
		if (flavor == 'loon') {
			// Loon 的 VLESS 只有一个位置参数：UUID（见 loon_positional）
			let id = loon_positional(n.uuid);
			if (id == null)
				return null;
			push(positional, id);
		}
		else {
			push(e, 'username=' + str(n.uuid));
		}
		if (tls)
			push(e, tls_flag);
		if (truthy(n.sni))
			push(e, 'sni=' + `${n.sni}`);
		if (truthy(n.flow))
			push(e, 'flow=' + `${n.flow}`);
		add_reality();
		add_ws();
	}
	else if (proto == 'trojan') {
		if (flavor == 'loon') {
			// Loon 的 Trojan 只有一个位置参数：密码（见 loon_positional）
			let pw = loon_positional(n.password);
			if (pw == null)
				return null;
			push(positional, pw);
		}
		else {
			push(e, 'password=' + str(n.password));
		}
		// Loon 的 Trojan 行**没有** TLS 开关：nsloon.app/docs/Node/ 的明文与 Reality
		// 两条示例都只写 `Trojan,服务器,端口,"密码",sni=…[,public-key=…,short-id=…]`，
		// 既没有 over-tls 也没有 tls。Trojan 本身就建立在 TLS 之上，Loon 不再要这个
		// 开关；写上去是客户端读不懂的参数。Surge 家族的 tls=true 相反是文档要求的。
		if (!is_loon)
			push(e, 'tls=true');
		if (truthy(n.sni))
			push(e, 'sni=' + `${n.sni}`);
		add_reality();
	}
	else if (proto == 'anytls') {
		// AnyTLS 建立在 TLS 之上，协议本身没有明文模式，行里也就没有 tls 开关
		// （Surge 手册：TLS 总是启用，共用 TLS 参数；sing-box 把 tls 标为 Required）。
		//
		// 密码的写法各家不同，且三家都有官方文档，只能按 flavor 分别输出：
		//   Surge（iOS 5.17.0+ / Mac 6.4.3+）与 SurgeMac：具名参数
		//     `Name = anytls, host, port, password=pwd`
		//     （manual.nssurge.com/policies/anytls.html）
		//   Surfboard：端口之后的位置参数，裸值不带引号
		//     `Name = anytls, host, port, password, skip-cert-verify=true, ...`
		//     （getsurfboard.com/docs/profile-format/proxy/external-proxy/anytls/）
		//   Loon：端口之后的位置参数，值用双引号包起来
		//     `Name = AnyTLS,host,port,"password",sni=...`（nsloon.app/docs/Node/）
		// 其余 flavor（surge / surgemac）走上面的具名写法。
		// （Egern 已不在本文件里 —— 它的配置是 YAML，见 output_egern.uc。）
		//
		// 按 flavor 分叉的协议不止 anytls：Loon 的 vmess / vless / trojan /
		// shadowsocks / ssr / hysteria2 同样把凭据画在位置参数上，TLS 开关与 UDP
		// 参数的名字也和 Surge 家族不同 —— 那些分叉在各分支里就地处理（见
		// is_loon / tls_flag 与 loon_positional 上方的说明）。anytls 的特别之处
		// 只在于它的密码写法在**三家之间**都不同（Surge 具名 / Surfboard 裸位置
		// 参数 / Loon 带引号位置参数），所以只有它在这里写成了三分支。
		if (flavor == 'surfboard') {
			push(positional, str(n.password));
		}
		else if (flavor == 'loon') {
			let pw = loon_positional(n.password);
			if (pw == null)
				return null;
			push(positional, pw);
		}
		else {
			push(e, 'password=' + str(n.password));
		}
		if (truthy(n.sni))
			push(e, 'sni=' + `${n.sni}`);
		add_reality();
	}
	else if (proto == 'ssr') {
		let cipher = lor(n.method, lor(n.cipher, 'aes-128-cfb'));
		if (is_loon) {
			// Loon 的 ShadowsocksR 同样把加密方式与密码放在位置参数上（密码带引号），
			// 其余仍是具名参数：
			//   `ShadowsocksR,服务器,端口,加密方式,"密码",protocol=…,obfs=…`
			// （nsloon.app/docs/Node/）。具名的 encrypt-method= / password= 在这里
			// 会各自占掉一个位置参数，加密方式与密码都解析不出来。
			let pw = loon_positional(n.password);
			if (pw == null)
				return null;
			push(positional, cipher);
			push(positional, pw);
		}
		else {
			push(e, 'encrypt-method=' + cipher);
			push(e, 'password=' + str(n.password));
		}
		push(e, 'protocol=' + lor(n.protocol, 'origin'));
		push(e, 'obfs=' + lor(n.obfs, 'plain'));
		let op = lor(n.obfs_param, n['obfs-param']);
		let pp = lor(n.protocol_param, n['protocol-param']);
		if (truthy(op) && op != '')
			push(e, 'obfs-param=' + `${op}`);
		if (truthy(pp) && pp != '')
			push(e, 'protocol-param=' + `${pp}`);
	}
	else if (proto == 'hysteria2' || proto == 'hysteria') {
		if (is_loon) {
			// Loon 的 Hysteria2 把密码放在位置参数上，带双引号：
			//   `Hysteria2,服务器,端口,"密码",sni=…`（nsloon.app/docs/Node/）
			let pw = loon_positional(n.password);
			if (pw == null)
				return null;
			push(positional, pw);
		}
		else {
			push(e, 'password=' + str(n.password));
		}
		if (truthy(n.sni))
			push(e, 'sni=' + `${n.sni}`);
	}
	else if (proto == 'tuic') {
		push(e, 'username=' + str(n.uuid));
		if (truthy(n.password))
			push(e, 'password=' + `${n.password}`);
		if (truthy(n.sni))
			push(e, 'sni=' + `${n.sni}`);
		if (truthy(n.alpn)) {
			// alpn 可能是数组：sing-box JSON 与 Clash YAML 的 alpn 列表导入后就是
			// 数组，直接拼接会得到数组的字符串形式（原 Lua 版是 "table: 0x..."），
			// 让整次导出失败 / 产出垃圾。先拼成逗号串。
			let alpn = n.alpn;
			if (type(alpn) == 'array')
				alpn = join(',', alpn);
			else if (type(alpn) == 'object')
				alpn = '';
			else
				alpn = `${alpn}`;
			// 多值 alpn 在这里表达不了：Surge 家族的行是逗号分隔的 key=value，
			// 没有引号 / 转义，`alpn=h3,h2` 会被读成 `alpn=h3` 加一个悬空字段。
			// 但 alpn 只是协商提示，缺省时客户端会用服务端给出的列表，
			// 不像密码那样一旦被截断就静默发错凭据 —— 所以这里丢掉该参数、
			// 保留节点，而不是像下面的通用逗号检查那样整条丢弃。
			if (alpn != '' && index(alpn, ',') < 0)
				push(e, 'alpn=' + alpn);
		}
	}
	else if (proto == 'socks5' || proto == 'socks' || proto == 'http') {
		// socks5 / http 在 Surge 家族里都用 username= / password= 具名参数
		// （Surge 手册：Name = http, <host>, <port>[, <username>, <password>]
		//   "may be given positionally after the port, or as named parameters"）
		if (truthy(n.username)) {
			push(e, 'username=' + `${n.username}`);
			if (truthy(n.password))
				push(e, 'password=' + `${n.password}`);
		}
	}
	else {
		// 未知协议：以前会一路掉到这里，生成 `Name = snell, host, port` 这样的残行。
		// 客户端遇到不认识的类型，这一个节点必然不可用（是跳过该节点还是拒绝加载
		// 整份配置，各家均未获官方证实），没有理由把它输出出去。
		// 返回 nil 由调用方整条剔除，与下面「值里含逗号」同一约定。
		return null;
	}

	// 取值写 true/false，不写 1：Loon 文档的示例就是 `skip-cert-verify=false`
	// （nsloon.app/docs/Node/ 的 Hysteria2 一行），直接证明 false 是合法字面量、
	// true 同理；而 Surge 手册的 TLS 页只写「Optional, boolean, default: false」，
	// 两家的文档里都找不到 `1` 这个取值。解析端两种都认
	// （parser_surge 把非 "0" / 非 "false" 都当 true），所以回环不受影响。
	if (truthy(n['skip-cert-verify']))
		push(e, 'skip-cert-verify=true');
	// UDP 转发的参数名同样各家不同：Surge 家族是 udp-relay=true，Loon 是 udp=true
	// （nsloon.app/docs/Node/ 的每个示例都写 udp=true，udp-relay 一次都没出现；
	// 相关的另外两个开关叫 udp-over-tcp / udp-port）。
	if (truthy(n.udp))
		push(e, is_loon ? 'udp=true' : 'udp-relay=true');

	// 参数值里的逗号无法用这些格式表达，整条丢弃（返回 nil，由调用方剔除）。
	// [Proxy] 行与 QX 的 [server_local] 行都是逗号分隔的 `key=value` 序列，
	// 语法里没有引号 / 转义机制：`password=pa,ss` 会被读成 `password=pa` 加上
	// 一个悬空的 `ss` 字段 —— 凭据被静默截断，用户不会收到任何提示。
	// 节点名里的逗号已由 names_of 单独处理（不进成员列表），但名字在 `=` 左侧，
	// 不影响本行解析；值在右侧，必须在这里挡掉。
	//
	// 原 Lua 版用 `kv:match("^[^=]*=(.*)$")` 取等号后的值；Lua 的 `.` 匹配包括
	// 换行在内的任意字符，等价于「第一个 = 之后的全部内容」。
	for (let kv in e) {
		let eq = index(kv, '=');
		if (eq >= 0 && index(substr(kv, eq + 1), ',') >= 0)
			return null;
	}
	// 位置参数（Loon 的凭据写法）与上面的具名参数不同：它**带双引号**，而 Loon
	// 文档明说「参数值中含有英文逗号时，请使用双引号包裹」（nsloon.app/docs/Node/）
	// —— 也就是说那对引号**确实**能保住逗号。所以这里放行「被引号完整包裹」的值：
	//   `Trojan, h, 443, "pa,ss", sni=x.com` 的密码就是 pa,ss。
	//
	// 判据不是「is_loon」而是「这个值是不是引号包裹的」：loon_positional 只在
	// Loon 分支里被调用，Surfboard 的 anytls 走的是**裸**位置参数，两者由这个
	// 判据自动分开，不必在这里再分叉一次。裸值（含加密方式这类不带引号的位置
	// 参数）仍按「值里含逗号就整条丢弃」处理 —— 它们没有引号语义。
	//
	// 安全性来自 loon_positional 的两条保证：值里含 `"` 时它直接返回 nil（节点
	// 已被丢弃，走不到这里），所以引号包裹的值内部不可能出现落单引号 ——
	// parser_surge.split_fields 的「奇数引号回退」分支不会被本行的输出触发。
	// （本行的具名参数仍然一律不带引号，含逗号的照样丢：Surge 家族的引号语义
	// 未获文档证据，且解析端不对具名值做 unquote，加了引号回环就断。）
	for (let v in positional) {
		if (index(v, ',') >= 0) {
			let quoted = length(v) >= 2
				&& substr(v, 0, 1) == '"' && substr(v, length(v) - 1, 1) == '"';
			if (!quoted)
				return null;
		}
	}

	for (let v in positional)
		push(head_parts, v);
	let line = str(n.name) + ' = ' + join(', ', head_parts);
	if (length(e) > 0)
		line = line + ', ' + join(', ', e);
	// 节点名与各参数值都来自订阅（不可信）：含换行会截断本行并伪造出一条新的代理行
	return util.one_line(line);
};

// 收集可用于「逗号分隔成员列表」的节点名（Surge 家族 [Proxy Group] / QX [policy]）。
//
// 两类名字必须排除，否则生成的配置整体非法：
//   * 含逗号：这些格式的成员列表就是 `NAME = select, X, Y, DIRECT`，语法里没有
//     引号 / 转义机制，名字里的逗号会被当成成员分隔符 —— `A,B` 被读成两个成员
//     `A` 与 `B`，两个都不存在（客户端的处置未获官方证实，但引用不存在的代理
//     无论如何都不是用户想要的结果）。节点定义本身仍留在 [Proxy] /
//     [server_local] 中，只是不进成员列表。
//   * 换行：定义行经过 util.one_line（换行→空格），成员列表若用原始名就对不上
//     定义行，同样成为悬空引用。这里统一先 one_line 再比对，保证两边一致。
function names_of(nodes) {
	let out = [];
	for (let n in (nodes ?? [])) {
		let nm = util.one_line(n.name);
		if (nm != null && nm != '' && index(nm, ',') < 0)
			push(out, nm);
	}
	return out;
}

// Surge 家族配置（Surge / Surfboard / SurgeMac / Loon 通用）
// flavor：目标格式名。既决定 surge_line 里按客户端分叉的少数参数，也用来查
// FAMILY_CAPS —— 每个调用点不再各自传「支持什么」的布尔量（见 FAMILY_CAPS 的说明）。
function surge_config(nodes, group_name, flavor) {
	let caps = FAMILY_CAPS[flavor] ?? {};
	let list = nodes ?? [];
	// 过滤 Surge 家族无法用单行 [Proxy] 表达的协议：
	//   vless / ssr：按 FAMILY_CAPS 分客户端（Surge/Surfboard/SurgeMac 两个都不认）
	//   hysteria：同样按 FAMILY_CAPS（Surge/SurgeMac 只有 Hysteria 2，没有 v1；
	//     Surfboard 未获证据，本表没对它表态，故保留）
	//   wireguard：Surge 需专用多段 [WireGuard] 配置，单行无法表达，统一丢弃（不输出损坏行）
	let kept = [];
	for (let n in list) {
		let p = lc(str(n.proto));
		if (p == 'wireguard') {
			// drop
		}
		else if (caps[p] === false) {
			// drop：能力表显式标了 false 的协议。写成数据驱动而不是逐个协议写
			// `elseif p == "ssr" and not caps.ssr`：每加一个维度就要再加一条分支，
			// 漏掉的那条默认是「保留」，于是导出里多出客户端读不懂的行且不报错。
			// （caps[p] 为 nil 表示「这张表没对它表态」，一律保留。）
		}
		else {
			push(kept, n);
		}
	}
	list = kept;
	let out = [];
	push(out, '[Proxy]');
	// surge_line 对「值里含逗号」这类无法表达的节点返回 nil，这些节点必须
	// 同时从成员列表里剔除 —— 否则 [Proxy Group] 会引用一个不存在的代理。
	let rendered = [];
	for (let n in list) {
		let line = M.surge_line(n, flavor);
		if (line) {
			push(out, line);
			push(rendered, n);
		}
	}
	push(out, '');
	push(out, '[Proxy Group]');
	let names = names_of(rendered);
	let select = group_name + ' = select';
	for (let nm in names)
		select = select + ', ' + nm;
	select = select + ', DIRECT';
	push(out, util.one_line(select));
	return join('\n', out);
}

M.to_surge = function(nodes, options) {
	options = options ?? {};
	return surge_config(nodes, options.name ?? 'PROXY', 'surge');
};

M.to_surfboard = function(nodes, options) {
	options = options ?? {};
	return surge_config(nodes, options.name ?? 'PROXY', 'surfboard');
};

M.to_surgemac = function(nodes, options) {
	options = options ?? {};
	return surge_config(nodes, options.name ?? 'PROXY', 'surgemac');
};

// Loon：Surge 兼容语法（支持 VLESS 与 SSR）
M.to_loon = function(nodes, options) {
	options = options ?? {};
	return surge_config(nodes, options.name ?? 'PROXY', 'loon');
};

// Egern 不在本文件里：它的配置是 YAML，而不是这里的逗号行，所以由
// output_egern.uc 单独实现（LEGACY_ISSUES 的 7.2 已实施）。
// 此前这里是 `surge_config(nodes, name, "egern")` —— 导出的是 Surge 的逗号行，
// Egern 根本读不了。

// Stash：Clash 兼容 YAML
M.to_stash = function(nodes, options) {
	return clash_meta.generate(nodes, options);
};

// Clash 原版（Dreamacro Clash / ClashX / Clash for Windows）不支持的协议类型。
// 只排除"确定不支持"的，不做白名单，避免误丢原版其实支持的类型。
const CLASH_LEGACY_UNSUPPORTED = {
	vless: true, hysteria2: true, hysteria: true, tuic: true, wireguard: true,
	// anytls 同样是原版 Clash 之后才出现的类型（Dreamacro/clash 的配置参考里
	// 只有 ss / ssr / vmess / snell / trojan / http / socks5）。不排除的话
	// to_clash 会把它交给 clash_meta 生成 `type: anytls`，原版 Clash 解析到
	// 未知类型会拒绝加载整份配置。
	anytls: true
};

// Clash 原版：过滤掉原版不认识的协议后，复用 Clash.Meta 的 YAML 生成
M.to_clash = function(nodes, options) {
	let kept = [];
	for (let n in (nodes ?? [])) {
		let p = props(n);
		if (!truthy(CLASH_LEGACY_UNSUPPORTED[p]))
			push(kept, n);
	}
	return clash_meta.generate(kept, options);
};

// QX 的 ws / tls 具名参数。vmess 与 vless 在 QX 里共用同一套参数名，
// 两个分支必须写出完全一致的集合 —— 此前 vless 一个都没写，vless + ws + tls
// 的节点导出成明文 tcp 条目，客户端按 tcp 去连只开了 ws 的端口，必然失败且不报错。
function qx_transport(n, f) {
	if (n.net == 'ws') {
		push(f, 'obfs=ws');
		if (truthy(n.path))
			push(f, 'obfs-uri=' + `${n.path}`);
		if (truthy(n.host))
			push(f, 'obfs-host=' + `${n.host}`);
	}
}

// 注意：带 Reality 公钥的 vmess / vless 不走这里，改走 qx_obfs_reality
// （QX 只认 obfs= 形式的 TLS 标志，见该函数的说明）。
function qx_tls(n, f) {
	if (truthy(n.sni))
		push(f, 'tls-host=' + `${n.sni}`);
	if (truthy(n.security) && n.security != 'none')
		push(f, 'tls-verification=true');
}

// QX 的 vmess / vless **带 Reality 公钥**时的传输 / TLS 标志。
//
// 官方 sample.conf（crossutility/Quantumult-X 仓库）的 [server_local] 前写明：
//
//   …if the corresponding line (socks5: over-tls=true, http: over-tls=true,
//   trojan: over-tls=true or obfs=wss, anytls: over-tls=true, … vmess:
//   obfs=over-tls or obfs=wss, vless: obfs=over-tls or obfs=wss) contains the
//   reality-base64-pubkey param, then the standard TLS will be replaced with
//   the Reality.
//
// 即 vmess / vless 的「TLS 标志」在 QX 里是 obfs= 形式，而 qx_tls() 对所有协议
// 统一输出 tls-host= + tls-verification=。两者写法不一致时 QX 会忽略公钥，
// 节点静默退回普通 TLS（握手必失败）。所以带公钥的 vmess / vless 改走这里，
// 不带公钥的一律不动 —— qx_tls() 是既有实现，全量改写会让所有 QX vmess / vless
// TLS 节点的输出形态变化（`tls-host` / `tls-verification` 对 vmess / vless 是否
// 同样有效没有官方依据：sample.conf 里只用 obfs= 形式，但「未出现」≠「无效」）。
//
// obfs 取值与 qx_transport 对齐：ws + TLS 写 wss，纯 TLS 写 over-tls。
// wss 下 obfs-host 同时充当 TLS 握手名与 Host 头（sample.conf 的注释），
// 所以 host 优先、退回 sni；over-tls 下 obfs-host 只是 SNI。
function qx_obfs_reality(n, f) {
	if (n.net == 'ws') {
		push(f, 'obfs=wss');
		if (truthy(n.path))
			push(f, 'obfs-uri=' + `${n.path}`);
		let h = lor(n.host, n.sni);
		if (truthy(h))
			push(f, 'obfs-host=' + `${h}`);
	}
	else {
		push(f, 'obfs=over-tls');
		if (truthy(n.sni))
			push(f, 'obfs-host=' + `${n.sni}`);
	}
}

// QX 的 Reality 参数。官方 sample.conf 的 [server_local] 里，vmess / vless /
// trojan / anytls 四类条目都用这两个键：Base64 公钥 reality-base64-pubkey 与
// 十六进制 reality-hex-shortid。sample.conf 的注释写明「只要该行设置了
// reality-base64-pubkey，标准 TLS 就会被换成 Reality TLS」。判据取「有没有
// public-key」，与 surge_line 的 add_reality 一致。
//
// TLS 标志由调用方负责：vmess / vless 走 qx_obfs_reality（obfs=over-tls / wss），
// trojan / anytls 走 over-tls=true + tls-host=。
function qx_reality(n, f) {
	if (!truthy(n['public-key']))
		return;
	push(f, 'reality-base64-pubkey=' + `${n['public-key']}`);
	if (truthy(n['short-id']))
		push(f, 'reality-hex-shortid=' + `${n['short-id']}`);
}

// 单条 [server_local] 定义行。返回 nil 表示该节点无法用 QX 的行语法表达，
// 由调用方整条剔除（定义行与 [policy] 成员一并去掉）。
//
// 具名字段先攒成列表再拼接，而不是边拼字符串边追加：值里含逗号的条目在逗号
// 分隔语法里表达不了（`password=pa,ss` 会被读成 `password=pa` 加一个悬空字段，
// 凭据被静默截断），必须能逐字段判定后整条丢弃。若先拼成整行再回头用模式去切，
// 行内本来就有的 `, ` 结构分隔符与值里的逗号无法区分 —— 会把每条合法行都误判成非法。
function qx_server_line(n, tag) {
	let proto = props(n);
	let host = str(n.server) + ':' + port_str(n.port);
	let f = [];
	if (proto == 'shadowsocks') {
		push(f, 'method=' + lor(n.method, lor(n.cipher, 'aes-256-gcm')));
		push(f, 'password=' + str(n.password));
	}
	else if (proto == 'vmess') {
		push(f, 'method=none');
		push(f, 'password=' + str(n.uuid));
		// 带 Reality 公钥的 vmess 必须用 obfs= 形式的 TLS 标志，否则 QX 忽略公钥
		// （见 qx_obfs_reality 的说明）。不带公钥的维持既有写法。
		if (truthy(n['public-key'])) {
			qx_obfs_reality(n, f);
		}
		else {
			qx_transport(n, f);
			qx_tls(n, f);
		}
		// sample.conf 有 vmess 的 Reality 条目（obfs=over-tls + reality-base64-pubkey
		// + reality-hex-shortid），此前只给 vless / anytls 输出了公钥。
		qx_reality(n, f);
	}
	else if (proto == 'vless') {
		push(f, 'method=none');
		push(f, 'password=' + str(n.uuid));
		if (truthy(n['public-key'])) {
			qx_obfs_reality(n, f);
		}
		else {
			qx_transport(n, f);
			qx_tls(n, f);
		}
		// sample.conf 的 vless Reality 条目在公钥之外还带 vless-flow=xtls-rprx-vision
		if (truthy(n['public-key']) && truthy(n.flow))
			push(f, 'vless-flow=' + `${n.flow}`);
		qx_reality(n, f);
	}
	else if (proto == 'trojan') {
		push(f, 'password=' + str(n.password));
		push(f, 'over-tls=true');
		if (truthy(n.sni))
			push(f, 'tls-host=' + `${n.sni}`);
		// sample.conf 的 trojan Reality 条目就是这一形：
		// `trojan=host:443, password=pwd, over-tls=true, tls-host=apple.com,`
		// `reality-base64-pubkey=…, reality-hex-shortid=…, tag=…`
		qx_reality(n, f);
	}
	else if (proto == 'anytls') {
		// QX 1.6.0 起支持 anytls（版本号只有第三方转述，语法本身取自官方
		// sample.conf）。写法与上面的 trojan 同形：
		// `anytls=host:port, password=pwd, over-tls=true, tls-host=<sni>, ...`
		push(f, 'password=' + str(n.password));
		push(f, 'over-tls=true');
		if (truthy(n.sni))
			push(f, 'tls-host=' + `${n.sni}`);
		qx_reality(n, f);
	}
	if (length(f) == 0)
		return null;
	for (let kv in f) {
		let eq = index(kv, '=');
		if (eq >= 0 && index(substr(kv, eq + 1), ',') >= 0)
			return null;
	}
	// 节点名 / sni / path / host 全部来自订阅（不可信），含换行会截断本行并
	// 伪造出一条新的 server_local 行。tag 排在最后。
	return util.one_line(
		proto + '=' + host + ', ' + join(', ', f) + ', tag=' + `${tag}`);
}

// Quantumult X
M.to_qx = function(nodes, options) {
	options = options ?? {};
	let out = [];
	// 真正写出了 [server_local] 行的节点。QX 只支持下面这 5 类协议
	// （shadowsocks / vmess / vless / trojan / anytls），其余节点
	// （hysteria2 / hysteria / tuic / socks / wireguard / ssr …）没有定义行；
	// [policy] 若把它们也列进去，就成了引用不存在服务器的悬空条目。
	let emitted = [];
	push(out, '[server_local]');
	for (let n in (nodes ?? [])) {
		let tag = util.one_line(lor(n.name, str(n.server) + ':' + port_str(n.port)));
		// 名字里的逗号落在 `tag=` 的值上，而本行是逗号分隔的 `key=value` 序列，
		// 语法里没有引号 / 转义：`tag=A,B` 会被读成 `tag=A` 加一个悬空字段。
		// QX 对这种行的实际处置未经核实（本机没有 QX 可实测），但无论它是报错
		// 还是静默忽略，用户拿到的都不是他填的那个名字 —— 所以整条丢弃，与
		// Surge 家族丢 wireguard / ssr、Clash 原版丢不支持协议同一约定，也与
		// 下面 [policy] 成员列表的排除条件（names_of）保持一致。
		// 注意判定用 one_line 之后的名字：names_of 也是先 one_line 再比对，
		// 两边必须用同一个字符串，否则定义行与成员列表会对不上。
		if (index(tag, ',') < 0) {
			let line = qx_server_line(n, tag);
			if (line) {
				push(out, line);
				push(emitted, n);
			}
		}
	}
	push(out, '');
	push(out, '[policy]');
	let names = names_of(emitted);
	let policy = 'static=' + (options.name ?? 'PROXY') + ', DIRECT';
	for (let nm in names)
		policy = policy + ', ' + nm;
	push(out, util.one_line(policy));
	push(out, '');
	push(out, '[server_remote]');
	return join('\n', out);
};

// Plain JSON：节点统一模型 JSON 数组
M.to_plain = function(nodes) {
	return util.json_encode(nodes ?? []);
};

// 统一分发
// 未知格式返回 `[null, err]`（原 Lua 版是 `nil, err`）
M.generate = function(nodes, format, options) {
	format = lc(str(format));
	if (format == 'surge') return M.to_surge(nodes, options);
	if (format == 'surfboard') return M.to_surfboard(nodes, options);
	if (format == 'surgemac') return M.to_surgemac(nodes, options);
	if (format == 'loon') return M.to_loon(nodes, options);
	// egern 不在这里：见文件头的说明，它由 output_egern.uc 实现
	if (format == 'qx') return M.to_qx(nodes, options);
	if (format == 'stash') return M.to_stash(nodes, options);
	if (format == 'clash') return M.to_clash(nodes, options);
	if (format == 'plain') return M.to_plain(nodes);
	return [null, msg.join('Unsupported output format: ', `${format}`)];
};

return M;
