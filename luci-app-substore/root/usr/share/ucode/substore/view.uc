// substore/view.uc — 服务器端模板共用的辅助函数
//
// 模板里重复用到的三件事集中在这里：查询串取值、时间格式化、注入 JS 的 JSON。
// 注意后端模块（core/parser/output 等）仍不依赖任何 LuCI 环境；本文件只被
// .ut 模板引用，属于「显示边界」，可以使用翻译函数（由调用方传入）。

'use strict';

const msg = require('substore.msg');

// 查询串 / 表单取值，与控制器里的同名逻辑保持一致：
// 同名字段重复提交时 LuCI 返回数组，取最后一个；null 保持 null。
const M = {};

M.fv = function(http, key) {
	let v = http.formvalue(key);

	if (type(v) == 'array')
		v = length(v) ? v[length(v) - 1] : null;

	if (v == null)
		return null;

	return `${v}`;
};

// 翻译一条（可能是组合消息的）用户可见文案。tr 是模板作用域里的 `_`。
M.tmsg = function(s, tr) {
	if (s == null)
		return '';

	return msg.translate(`${s}`, tr);
};

// 时间戳 → "YYYY-MM-DD HH:MM"（本地时区，等价 Lua 的 os.date("%Y-%m-%d %H:%M")）。
M.fmt_time = function(ts) {
	if (ts == null || ts === false || ts === '')
		return '-';

	const t = localtime(int(ts));

	if (t == null)
		return '-';

	return sprintf('%04d-%02d-%02d %02d:%02d', t.year, t.mon, t.mday, t.hour, t.min);
};

// 按字符（UTF-8 码点）截断，超过 max 个字符时保留前 max-1 个再加省略号，
// 结果正好 max 个字符；未超长时原样返回，调用方据此决定要不要加 title。
//
// 不能用 length()/substr() 直接做：ucode 里两者都按字节计数，中文名称
// “30 个字符”会变成 10 个字，还可能在半个汉字处切断出现乱码。
M.truncate_chars = function(s, max) {
	s = (s == null) ? '' : `${s}`;

	if (max <= 0)
		return '';

	const n = length(s);
	let chars = 0;
	let keep = n;        // 保留前 max-1 个字符时的字节长度
	let i = 0;

	while (i < n) {
		const b = ord(substr(s, i, 1));

		// 0xxxxxxx 或 11xxxxxx：一个字符的起始字节（10xxxxxx 是续字节）
		if (b < 0x80 || b >= 0xC0) {
			if (chars == max - 1)
				keep = i;
			chars++;
		}

		i++;
	}

	if (chars <= max)
		return s;

	return substr(s, 0, keep) + '…';
};

// 序列化成可安全嵌进 <script> 的 JSON 字面量。
//
// 编码用 sprintf('%J')，不是 json()：ucode 里 json() 只负责**解析**
// （传入对象时它要求对象实现 read()，直接报错），没有「传入值就编码」这回事。
//
// 只做 JSON 编码不够：%J 不转义 "<"，值一旦来自查询串或节点字段，
// "</script><script>…" 会在 HTML 词法阶段就闭合脚本块（与 JS 字符串上下文
// 无关），"<!--" 则会让脚本进入 escaped 状态、吞掉其后整页。
// 把**全部** "<" 转成 JSON 的 < 转义：在 JS 字符串里仍是 "<"，
// 而 HTML 词法阶段再也看不到 "<"。
M.jsq = function(v) {
	return replace(sprintf('%J', v), '<', '\\u003c');
};

// nodeform.js 用的字段标签与界面文本。两个编辑页共用一份，避免抄写漂移：
// 标签缺失时 nodeform.js 会回退成字段名，症状是「某些字段显示成 xxx」。
// 品牌/技术名词（Server、UUID、TLS…）保持原样，不翻译。
M.field_labels = function(tr) {
	return {
		name: tr('Name'),
		group: tr('Group'),
		type: tr('Type'),
		server: 'Server',
		port: 'Port',
		password: 'Password',
		uuid: 'UUID',
		alterId: 'Alter ID',
		cipher: 'Cipher',
		method: 'Method',
		security: 'Security',
		net: 'Network',
		headerType: 'Header Type',
		flow: 'Flow',
		fp: tr('Fingerprint'),
		path: 'Path',
		host: 'Host',
		sni: 'SNI',
		alpn: tr('ALPN'),
		tls: 'TLS',
		obfs: 'Obfs',
		'obfs-param': 'Obfs Param',
		'obfs-password': 'Obfs Password',
		// SIP003 插件串，形如 obfs-local;obfs=http;obfs-host=www.baidu.com
		plugin: 'Plugin (SIP003)',
		protocol: 'Protocol',
		'protocol-param': 'Protocol Param',
		udp: 'UDP',
		'skip-cert-verify': 'Skip Cert Verify',
		'private-key': 'Private Key',
		'peer-public-key': 'Peer Public Key',
		'public-key': 'Public Key',
		'short-id': tr('Short ID'),
		'spider-x': tr('Spider X'),
		'pre-shared-key': 'Pre Shared Key',
		ip: 'IP',
		ipv6: 'IPv6',
		'allowed-ips': 'Allowed IPs',
		reserved: 'Reserved',
		'persistent-keepalive': 'Persistent Keepalive',
		'listen-port': 'Listen Port',
		mtu: 'MTU',
		dns: 'DNS',
		'amnezia-wg-option': 'Amnezia WG Option',
		username: 'Username'
	};
};

M.nodeform_i18n = function(tr) {
	return {
		node: tr('Node'),
		defaultOpt: tr('Default')
	};
};

return M;
