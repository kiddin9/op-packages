// output.uc — 订阅输出统一分发（所有目标格式的唯一注册点）
// luci-app-substore
//
// 多返回值改数组：M.generate 返回 [content, err]（成功时 err 为 null），
// 不再像 Lua 版那样「成功返回字符串、失败返回 nil, err」两种形态混用；
// content_type_for / extension_for 仍返回单个字符串或 null，与 Lua 一致。

const clash_meta = require('substore.output_clash_meta');
const output_uri = require('substore.output_uri');
const output_singbox = require('substore.output_singbox');
const output_v2ray = require('substore.output_v2ray');
const output_formats = require('substore.output_formats');
const output_egern = require('substore.output_egern');
const output_wgconf = require('substore.output_wireguard_conf');
const msg = require('substore.msg');

const M = {};

// 目标格式别名映射（兼容 ?target=X 的各类写法）
M.FORMAT_ALIASES = {
	// Clash 原版：vless/hysteria2/tuic/wireguard 等原版不支持的协议会被过滤
	clash: 'clash',
	clashclassic: 'clash',
	clashpremium: 'clash',
	// Clash.Meta / Mihomo
	yaml: 'clashmeta',
	clashmeta: 'clashmeta',
	mihomo: 'clashmeta',
	stash: 'stash',
	surge: 'surge',
	surfboard: 'surfboard',
	surgemac: 'surgemac',
	loon: 'loon',
	egern: 'egern',
	shadowrocket: 'shadowrocket',
	rocket: 'shadowrocket',
	qx: 'qx',
	quantumult: 'qx',
	singbox: 'singbox',
	sing_box: 'singbox',
	'sing-box': 'singbox',
	v2ray: 'v2ray',
	v2rayuri: 'v2rayuri',
	v2ray_uri: 'v2rayuri',
	uri: 'v2rayuri',
	// wg-quick / AmneziaWG .conf
	wgconf: 'wgconf',
	wg: 'wgconf',
	wireguard: 'wgconf',
	amneziawg: 'wgconf',
	amnezia: 'wgconf',
	conf: 'wgconf',
	plain: 'plain',
	plainjson: 'plain',
	json: 'plain',
	base64: 'shadowrocket',
};

// 目标格式的 HTTP Content-Type
const CONTENT_TYPES = {
	clash: 'text/plain; charset=utf-8',
	clashmeta: 'text/plain; charset=utf-8',
	stash: 'text/plain; charset=utf-8',
	surge: 'text/plain; charset=utf-8',
	surfboard: 'text/plain; charset=utf-8',
	surgemac: 'text/plain; charset=utf-8',
	loon: 'text/plain; charset=utf-8',
	// Egern 的配置正文是 YAML，但 Content-Type 与其它 YAML 格式（clash /
	// clashmeta / stash）保持 text/plain 一致：这三个是本仓库既有的约定，
	// 单独把 egern 改成 application/yaml 只会让同一类内容出现两种类型。
	// （后缀已按内容改成 .yaml，见 FILENAME_EXT。）
	egern: 'text/plain; charset=utf-8',
	qx: 'text/plain; charset=utf-8',
	shadowrocket: 'text/plain; charset=utf-8',
	singbox: 'application/json; charset=utf-8',
	v2ray: 'application/json; charset=utf-8',
	v2rayuri: 'text/plain; charset=utf-8',
	wgconf: 'text/plain; charset=utf-8',
	plain: 'application/json; charset=utf-8',
};

// 未指定 target 时的默认格式（保持历史行为：Clash.Meta）
const DEFAULT_FORMAT = 'clashmeta';

// 归一 target：空串 / 纯空白等同于「未指定」。
// `?target=` 传进来的是 ""，而 "" 在 Lua 里是**真值**，`format or DEFAULT_FORMAT`
// 兜不住它。M.generate 一直在做这件事，但 content_type_for / extension_for 漏了：
// 同一个请求里正文按 clashmeta 生成，而这两个函数拿 "" 去查表全部落空 ——
// Content-Type 变成 nil（响应头缺失），文件名后缀退回兜底的 .txt。下游按后缀
// 判断格式的客户端会把 YAML 当成纯文本，解析失败。
function normalize_format(format) {
	if (type(format) != 'string')
		return DEFAULT_FORMAT;
	// 对应 Lua 的 `format:match("^%s*(.-)%s*$")`。不能直接用 trim()：
	// ucode 的 trim 不处理 \v / \f，而 Lua 的 %s 处理，纯 "\v" 之类的
	// target 在 Lua 里会落回默认格式，用 trim 则会变成「不支持的格式」。
	format = replace(format, /^[[:space:]]+/, '');
	format = replace(format, /[[:space:]]+$/, '');
	if (format == '')
		return DEFAULT_FORMAT;
	return format;
}

// 别名解析：先去掉 -/_/空白再查（sing_box / sing-box → singbox），
// 查不到再用原串小写查（原样就是别名的写法）。
function resolve_alias(format) {
	let norm = M.FORMAT_ALIASES[replace(lc(format), /[-_[:space:]]/g, '')];
	if (norm == null)
		norm = M.FORMAT_ALIASES[lc(format)];
	return norm;
}

M.content_type_for = function(format) {
	format = normalize_format(format);
	return CONTENT_TYPES[resolve_alias(format)] ?? null;
};

// 目标格式的下载文件名后缀
const FILENAME_EXT = {
	clash: 'yaml',
	clashmeta: 'yaml',
	stash: 'yaml',
	surge: 'conf',
	surfboard: 'conf',
	surgemac: 'conf',
	loon: 'conf',
	// Egern 的配置是 YAML（output_egern.lua），后缀必须与内容一致：
	// 下游按后缀判断格式的客户端会把 .conf 当成 Surge 的逗号行去解析。
	egern: 'yaml',
	qx: 'conf',
	shadowrocket: 'txt',
	singbox: 'json',
	v2ray: 'json',
	v2rayuri: 'txt',
	wgconf: 'conf',
	plain: 'json',
};

M.extension_for = function(format) {
	format = normalize_format(format);
	return FILENAME_EXT[resolve_alias(format)] ?? 'txt';
};

// UI 下拉使用的有序格式列表（单一数据源；模板由此渲染，避免多处硬编码不同步）
M.FORMAT_OPTIONS = [
	['clashmeta', 'Clash.Meta / Mihomo'],
	['clash', 'Clash'],
	['stash', 'Stash'],
	['surge', 'Surge'],
	['surfboard', 'Surfboard'],
	['surgemac', 'SurgeMac'],
	['loon', 'Loon'],
	['egern', 'Egern'],
	['qx', 'Quantumult X'],
	['shadowrocket', 'Shadowrocket'],
	['singbox', 'sing-box'],
	['v2ray', 'V2Ray'],
	['v2rayuri', 'V2Ray URI'],
	['wgconf', 'WireGuard / AmneziaWG .conf'],
	['plain', 'Plain JSON'],
];

// 子模块返回值归一为 [content, err]：多数子模块成功时只返回字符串
// （Lua 版就是单返回值），能失败的（如 output_wireguard_conf.generate）
// 按全局约定返回 [content, err]。两种形态都在这里统一，分发分支不必各写一遍。
function as_pair(v) {
	if (type(v) == 'array')
		return v;
	return [v, null];
}

// 统一分发：nodes → 目标格式字符串
M.generate = function(nodes, format, options) {
	// 空串 / 纯空白等同于「未指定」。
	// `?target=` 会传进来 ""，而 "" 在 Lua 里是**真值**，所以 `format or DEFAULT_FORMAT`
	// 兜不住它，会一路落到 "Unsupported output format: "（冒号后面什么都没有）——
	// 用户拿到的是一个说不出原因的错误页。控制器只在 nil 时兜底，覆盖不到空串。
	format = normalize_format(format);
	let norm = resolve_alias(format);
	if (norm == null)
		return [null, msg.join('Unsupported output format: ', `${format}`)];

	if (norm == 'clashmeta') return as_pair(clash_meta.generate(nodes, options));
	if (norm == 'clash') return as_pair(output_formats.to_clash(nodes, options));
	if (norm == 'stash') return as_pair(output_formats.to_stash(nodes, options));
	if (norm == 'surge') return as_pair(output_formats.to_surge(nodes, options));
	if (norm == 'surfboard') return as_pair(output_formats.to_surfboard(nodes, options));
	if (norm == 'surgemac') return as_pair(output_formats.to_surgemac(nodes, options));
	if (norm == 'loon') return as_pair(output_formats.to_loon(nodes, options));
	if (norm == 'egern') return as_pair(output_egern.generate(nodes, options));
	if (norm == 'shadowrocket') return as_pair(output_uri.to_shadowrocket(nodes));
	if (norm == 'qx') return as_pair(output_formats.to_qx(nodes, options));
	if (norm == 'singbox') return as_pair(output_singbox.generate(nodes));
	if (norm == 'v2ray') return as_pair(output_v2ray.generate(nodes));
	if (norm == 'v2rayuri') return as_pair(output_uri.to_v2ray_uri(nodes));
	if (norm == 'wgconf') return as_pair(output_wgconf.generate(nodes, options));
	if (norm == 'plain') return as_pair(output_formats.to_plain(nodes));

	return [null, msg.join('Unsupported output format: ', `${format}`)];
};

return M;
