// http.uc — 订阅下载（SSRF 防护、超时、大小限制）
// luci-app-substore
//
// 多返回值约定：失败一律 `[null, ..., "err"]`，成功 `[body, headers]` 等数组。

import { popen, unlink } from 'fs';

const util = require('substore.util');
const msg = require('substore.msg');

const M = {};

M.DEFAULT_MAX_SIZE = 10 * 1024 * 1024; // 10MB
M.DEFAULT_TIMEOUT = 20;
M.MAX_REDIRECTS = 4;

// ---------- 私网 / 保留地址判断 ----------

// 单段数值：十进制 / 八进制（前导 0）/ 十六进制（0x 前缀）
function numeral(seg) {
	if (match(seg, /^0[xX][0-9a-fA-F]+$/))
		return int(substr(seg, 2), 16);

	if (match(seg, /^0[0-9]+$/))
		return int(substr(seg, 1), 8);

	if (match(seg, /^[0-9]+$/))
		return int(seg, 10);

	return null;
}

// 把 inet_aton 接受的各种数值型 IPv4 写法归一为点分十进制。
// curl / wget 都按 inet_aton 语义解析主机名，因此 SSRF 检查必须用同一套语义，
// 否则 "0177.0.0.1"（八进制 127.0.0.1）、"2130706433"（十进制）、
// "0x7f000001"（十六进制）、"127.1"（短写）会被当成公网地址放行。
// 段数与点号数必须一致（拒绝 "1..2" 这类畸形写法）。
function normalize_ipv4(host) {
	let parts = split(host, '.');

	if (length(parts) > 4)
		return null;

	if (match(host, /(^\.)|(\.$)/) || match(host, /\.\./))
		return null;

	let vals = [];
	for (let seg in parts) {
		let v = numeral(seg);
		if (v == null)
			return null;
		push(vals, v);
	}

	// inet_aton：前 k-1 段各 8 位，最后一段吃掉剩余位宽
	let k = length(vals);
	for (let i = 0; i < k - 1; i++) {
		if (vals[i] > 255)
			return null;
	}
	if (vals[k - 1] >= 2 ** (32 - 8 * (k - 1)))
		return null;

	let n = 0;
	for (let i = 0; i < k; i++) {
		let shift = (i < k - 1) ? (32 - 8 * (i + 1)) : 0;
		n += vals[i] * 2 ** shift;
	}

	// int / int 在 ucode 里就是整数除法（向下取整）
	let o1 = (n / 2 ** 24) % 256;
	let o2 = (n / 2 ** 16) % 256;
	let o3 = (n / 2 ** 8) % 256;
	let o4 = n % 256;

	return sprintf('%d.%d.%d.%d', o1, o2, o3, o4);
}

function is_private_ipv4(ip) {
	let m = match(ip, /^([0-9]+)\.([0-9]+)\.([0-9]+)\.([0-9]+)$/);
	if (!m)
		return false;

	let a = int(m[1]), b = int(m[2]), c = int(m[3]), d = int(m[4]);
	if (a == null || b == null || c == null || d == null)
		return true;

	if (a == 0) return true;
	if (a == 10) return true;
	if (a == 127) return true;
	if (a == 100 && b >= 64 && b <= 127) return true; // 100.64/10 CGNAT
	if (a == 169 && b == 254) return true;            // link-local
	if (a == 172 && b >= 16 && b <= 31) return true;  // 172.16/12
	if (a == 192 && b == 168) return true;            // 192.168/16
	if (a >= 224) return true;                        // multicast + reserved

	return false;
}

function is_private_ipv6(ip) {
	if (ip == '::' || ip == '::1')
		return true;

	let l = lc(ip);

	// 未指定地址的各种零压缩写法
	if (match(l, /^0*:/) && !match(l, /^0*::?0*$/) && l != '0')
		return true;

	if (substr(l, 0, 2) == 'fc' || substr(l, 0, 2) == 'fd')
		return true; // ULA fc00/7

	// link-local fe80::/10
	if (match(substr(l, 0, 4), /^fe[89ab][0-9a-f]$/))
		return true;

	if (substr(l, 0, 2) == 'ff')
		return true; // multicast

	return false;
}

function is_private(ip) {
	ip = ip ?? '';
	if (index(ip, ':') >= 0)
		return is_private_ipv6(ip);
	return is_private_ipv4(ip);
}

// 粗校验：像不像一个 IPv6 字面量。
// "127.0.0.1:" 这类写法 parse_url 取不到端口，会把整串当主机名；它既不是
// 合法域名，is_private_ipv6 也识别不出，于是可能被当成公网放行。
// 因此：含 ":" 但不像 IPv6 的一律拒绝（fail-closed）。
function looks_like_ipv6(h) {
	if (!match(h, /^[0-9a-fA-F:.]+$/))
		return false;

	if (length(replace(h, /[^:]/g, '')) < 2)
		return false;

	if (match(h, /::.*::/))
		return false; // "::" 最多出现一次

	return true;
}

// ---------- URL 解析 ----------
M.parse_url = function(url) {
	url = util.trim(url ?? '');

	let m = match(url, /^([A-Za-z0-9+.-]+):\/\/(.*)$/);
	if (!m)
		return [null, 'Invalid URL'];

	let scheme = lc(m[1]);
	if (scheme != 'http' && scheme != 'https')
		return [null, 'Only http/https is supported'];

	let rest = m[2];

	// 主机部分到第一个 / ? # 为止（RFC 3986）
	let hostport = match(rest, /^[^\/?#]*/)[0];

	// 剥掉 userinfo（user:pass@）：RFC 3986 里 userinfo 到**最后一个** @ 为止
	let at = index(hostport, '@');
	while (at >= 0) {
		hostport = substr(hostport, at + 1);
		at = index(hostport, '@');
	}

	let host, port;

	if (substr(hostport, 0, 1) == '[') {
		let close = index(hostport, ']');
		if (close < 0)
			return [null, 'Invalid hostname'];

		host = substr(hostport, 1, close - 1);
		let pm = match(substr(hostport, close + 1), /^:([0-9]+)$/);
		port = pm ? pm[1] : (scheme == 'https' ? '443' : '80');
	}
	else {
		let pm = match(hostport, /^([^:]+):([0-9]+)$/);
		if (pm) {
			host = pm[1];
			port = pm[2];
		}
		else {
			host = hostport;
			port = (scheme == 'https' ? '443' : '80');
		}
	}

	if (host == null || host == '')
		return [null, 'Invalid hostname'];

	let pn = int(port, 10);
	if (pn == null || pn < 1 || pn > 65535)
		return [null, 'Invalid port'];

	return [{ scheme: scheme, host: host, port: `${pn}` }, null];
};

// 校验 User-Agent：拒绝控制字符与超长串（防响应头注入 / 日志伪造）
M.validate_user_agent = function(ua) {
	if (ua == null)
		return ['', null];

	let s = util.trim(`${ua}`);
	if (s == '')
		return ['', null];

	if (length(s) > 256)
		return [null, 'User-Agent is too long (at most 256 characters)'];

	for (let i = 0; i < length(s); i++) {
		let code = ord(substr(s, i, 1));
		if (code < 32 || code == 127)
			return [null, 'User-Agent must not contain control characters'];
	}

	return [s, null];
};

// 校验并规范化代理地址：支持 http/https/socks4/socks5/socks5h，可含 user:pass@
// 空串 → ""（未使用）；合法 → 规范化地址；非法 → [null, err]
M.parse_proxy = function(p) {
	let s = util.trim(p ?? '');
	if (s == '')
		return ['', null];

	let m = match(s, /^([A-Za-z][A-Za-z0-9]*):\/\/(.*)$/);
	if (!m)
		return [null, 'Invalid proxy format'];

	let scheme = lc(m[1]);
	if (scheme != 'http' && scheme != 'https' && scheme != 'socks4'
		&& scheme != 'socks5' && scheme != 'socks5h')
		return [null, msg.join('Unsupported proxy protocol: ', scheme)];

	let userinfo = '';
	let hostport = replace(m[2], /\/.*$/, '');

	let at = index(hostport, '@');
	if (at >= 0) {
		userinfo = substr(hostport, 0, at);
		hostport = substr(hostport, at + 1);
	}

	if (userinfo != '' && !match(userinfo, /^[A-Za-z0-9._:-]+$/))
		return [null, 'Proxy username/password contains invalid characters'];

	let host, port;
	let bracketed = substr(hostport, 0, 1) == '[';

	if (bracketed) {
		let hm = match(hostport, /^\[([A-Za-z0-9._:-]+)\]/);
		host = hm ? hm[1] : null;
		let pm = match(hostport, /^\[.*\]:([0-9]+)$/);
		port = pm ? pm[1] : null;
	}
	else {
		let pm = match(hostport, /^([^:]+):([0-9]+)$/);
		if (pm) {
			host = pm[1];
			port = pm[2];
		}
		else {
			host = hostport;
		}
	}

	if (host == null || host == '' || !match(host, /^[A-Za-z0-9._:-]+$/))
		return [null, 'Invalid proxy host'];

	// 未加方括号的 IPv6 字面量无法判定端口，明确报错
	if (!bracketed && length(replace(host, /[^:]/g, '')) > 1)
		return [null, 'An IPv6 proxy address must be bracketed, e.g. http://[::1]:1080'];

	if (port != null) {
		let pn = int(port, 10);
		if (pn == null || pn < 1 || pn > 65535)
			return [null, 'Invalid proxy port'];
		port = `${pn}`;
	}

	// IPv6 字面量必须把方括号拼回去，否则 curl 解析不了
	if (index(host, ':') >= 0)
		host = '[' + host + ']';

	let r = scheme + '://';
	if (userinfo != '')
		r += userinfo + '@';
	r += host;
	if (port != null)
		r += ':' + port;

	return [r, null];
};

// ---------- 主机名解析 ----------
function have(cmd) {
	return system('command -v ' + cmd + ' >/dev/null 2>&1') == 0;
}

// busybox nslookup 的输出里，前面两行 Address 是 **DNS 服务器自己**的地址；
// 只取 "Name:" 之后的 Address 行，否则每个域名都会被判成内网。
function resolve_via_nslookup(host) {
	let p = popen('nslookup ' + util.shq(host) + ' 2>/dev/null');
	if (!p)
		return null;

	let out = p.read('all') ?? '';
	p.close();

	let ips = [];
	let in_answer = false;

	for (let line in split(out, /[\r\n]+/)) {
		if (match(line, /^[ \t]*Name[ \t]*:/)) {
			in_answer = true;
		}
		else if (in_answer) {
			let m = match(line, /^[ \t]*Address[ \t]*:[ \t]*(\S+)/);
			if (m) {
				let a = match(m[1], /^([^%]+)/);
				a = a ? a[1] : m[1];
				if (a != '')
					push(ips, a);
			}
		}
	}

	if (length(ips) == 0)
		return null;

	return ips;
}

// 解析主机 → [ips, have_resolver]
// 「解析失败」与「本机没有解析能力」必须分开：处置方式完全相反。
function resolve(host) {
	let have_resolver = false;

	if (have('nslookup')) {
		have_resolver = true;
		let ips = resolve_via_nslookup(host);
		if (ips)
			return [ips, true];
	}

	return [null, have_resolver];
}

const LOOPBACK_NAMES = {
	localhost: true,
	'localhost.localdomain': true,
	localhost4: true,
	'localhost4.localdomain4': true,
	localhost6: true,
	'localhost6.localdomain6': true,
	'ip6-localhost': true,
	'ip6-loopback': true,
	'ip6-localnet': true
};

// SSRF 预检：返回 [ok, reason, unverified]
// unverified 为 true 表示本机没有任何 DNS 解析手段，放行未经解析校验；
// 下载层必须在连接建立后重新核对对端地址。
M.check_public = function(host) {
	host = lc(util.trim(host ?? ''));

	if (host == '')
		return [false, 'Empty hostname'];

	if (index(host, '@') >= 0)
		return [false, 'Hostname contains the invalid character @'];

	// 空白 / 百分号编码在主机名里都不合法
	for (let i = 0; i < length(host); i++) {
		let code = ord(substr(host, i, 1));
		if (code <= 32 || code == 37 || code == 127)
			return [false, 'Hostname contains invalid characters'];
	}

	// 去掉尾部点："localhost." 与 "localhost" 指向同一台机器
	host = replace(host, /\.$/, '');
	if (host == '')
		return [false, 'Empty hostname'];

	if (index(host, ':') >= 0) {
		if (!looks_like_ipv6(host))
			return [false, 'Invalid hostname'];
		if (is_private_ipv6(host))
			return [false, 'Target is a private/reserved address'];
		return [true, null, false];
	}

	// 数值型 IPv4 按 inet_aton 语义归一后再判私网
	let norm = normalize_ipv4(host);
	if (norm != null) {
		if (is_private_ipv4(norm))
			return [false, 'Target is a private/reserved address'];
		return [true, null, false];
	}

	if (LOOPBACK_NAMES[host] === true)
		return [false, 'Target is localhost'];

	let [ips, have_resolver] = resolve(host);

	if (!ips) {
		if (have_resolver) {
			// 有解析手段却解析不出来 → NXDOMAIN，拒绝（fail-closed）
			return [false, 'Cannot resolve the target hostname'];
		}

		// 本机没有解析手段：不能按「解析失败」处理（否则所有域名订阅都被拒），
		// 放行，改由下载层连接后复核 %{remote_ip}
		return [true, 'No local DNS resolution; the peer address will be verified at connect time', true];
	}

	for (let ip in ips) {
		if (!is_private(ip))
			return [true, null, false];
	}

	return [false, 'Target resolves only to private/reserved addresses'];
};

// ---------- 下载 ----------
function detect_tool() {
	if (have('curl'))
		return 'curl';
	if (have('wget'))
		return 'wget';
	return null;
}

function location_from_headers(path) {
	let [raw] = util.read_file(path);
	if (raw == null)
		return null;

	for (let line in split(raw, /[\r\n]+/)) {
		let m = match(line, /^[ \t]*[Ll]ocation:[ \t]*(.+)$/);
		if (m)
			return util.trim(m[1]);
	}

	return null;
}

// 读取响应头（curl -D 输出），返回小写键 → 值的表；重复键取最后一个
function read_headers(path) {
	let h = {};
	let [raw] = util.read_file(path);
	if (raw == null)
		return h;

	for (let line in split(raw, /[\r\n]+/)) {
		let m = match(line, /^[ \t]*([^:]+):[ \t]*(.*)$/);
		if (m)
			h[lc(m[1])] = m[2];
	}

	return h;
}

function resolve_url(base, loc) {
	if (index(loc, '://') >= 0)
		return loc;

	let m = match(base, /^([A-Za-z0-9]+):\/\/([^\/]+)/);
	if (!m)
		return loc;

	let scheme = m[1], host = m[2];

	// 协议相对地址（//host/path）：沿用 scheme，主机取自 Location 本身
	if (substr(loc, 0, 2) == '//')
		return scheme + ':' + loc;

	if (substr(loc, 0, 1) == '/')
		return scheme + '://' + host + loc;

	let bm = match(base, /^[A-Za-z0-9]+:\/\/[^\/]+(.*)$/);
	let base_path = bm ? bm[1] : '/';
	let dm = match(base_path, /^(.*)\/[^\/]*$/);
	let dir = dm ? dm[1] : '';

	return scheme + '://' + host + dir + '/' + loc;
}

function locations_from_log(raw) {
	let locs = [];

	for (let line in split(raw ?? '', /[\r\n]+/)) {
		let m = match(line, /^[ \t]*[Ll]ocation:[ \t]*(.+)$/);
		if (m)
			push(locs, util.trim(m[1]));
	}

	return locs;
}

// 复检重定向链：每一跳都必须通过 check_public。纯函数，不触网。
M.validate_redirect_chain = function(base_url, log) {
	for (let loc in locations_from_log(log)) {
		let next_url = resolve_url(base_url, loc);
		let [np, perr] = M.parse_url(next_url);
		if (!np)
			return [false, msg.join('Invalid redirect target: ', loc)];

		let [ok, re] = M.check_public(np.host);
		if (!ok)
			return [false, msg.join('Unsafe redirect target: ', re ?? '')];
	}

	return [true, null];
};

// 代理地址去凭据，用于日志（不记录代理密码）
M.redact_proxy = function(p) {
	let m = match(`${p ?? ''}`, /^([A-Za-z][A-Za-z0-9]*):\/\/(.*)$/);
	if (!m)
		return '***';
	return m[1] + '://' + replace(m[2], /^[^@]*@/, '');
};

// 抹掉文本中的 URL 凭据（//user:pass@），用于日志与错误信息
M.scrub_credentials = function(text) {
	return replace(`${text ?? ''}`, /\/\/([^ \t\/@:]*):([^ \t\/@]*)@/g, '//***@');
};

// 连接建立后复核**实际**对端地址，返回 [ok, err]
function verify_peer_ip(ip, proxy, unverified) {
	if (proxy != null && proxy != '')
		return [true, null];

	if (ip == null || ip == '') {
		if (unverified) {
			// 预检放行且拿不到对端地址 —— 这个请求没有任何一处校验过目标
			return [false, 'Cannot verify the target address (no local DNS resolution and no peer IP obtained)'];
		}
		return [true, null];
	}

	if (is_private(ip))
		return [false, msg.compose('Target actually connects to a private/reserved address (', ip, ')')];

	return [true, null];
}

function fetch_curl(url, parsed, opts) {
	let max = opts.max_size, t = opts.timeout;

	let proxy_arg = '';
	if (opts.proxy != null && opts.proxy != '')
		proxy_arg = ' -x ' + util.shq(opts.proxy);

	let ua_arg = '';
	if (opts.user_agent != null && opts.user_agent != '')
		ua_arg = ' -A ' + util.shq(opts.user_agent);

	let tag = util.rnd_hex(8);
	let cur = url;

	for (let redirect = 0; redirect <= M.MAX_REDIRECTS; redirect++) {
		let tmp = '/tmp/substore_dl_' + tag + '_' + redirect + '.tmp';
		let hdr = tmp + '.hdr';
		let errf = tmp + '.err';

		// 清理必须在**每一条**退出路径上执行：/tmp 是 tmpfs，失败重试会堆满内存
		function cleanup() {
			unlink(tmp);
			unlink(hdr);
			unlink(errf);
		}

		cleanup();

		// -w 同时取 http_code 与 remote_ip：后者是真正建立连接的对端地址
		let cmd = 'curl -sS -o ' + util.shq(tmp)
			+ ' --max-time ' + t
			+ ' --connect-timeout ' + (t < 10 ? t : 10)
			+ ' --max-redirs 0 --max-filesize ' + max
			+ ' -D ' + util.shq(hdr)
			+ " -w '%{http_code} %{remote_ip}'"
			+ proxy_arg + ua_arg
			+ ' ' + util.shq(cur)
			+ ' 2>' + util.shq(errf);

		let p = popen(cmd);
		let raw = util.trim(p ? (p.read('all') ?? '') : '');
		if (p)
			p.close();

		let m = match(raw, /^([0-9]+)[ \t\r\n]*(\S*)$/);
		let code = m ? m[1] : raw;
		let peer = m ? m[2] : '';

		if (code == '' || code == '000') {
			let [errtext] = util.read_file(errf);
			cleanup();
			return [null, null, util.trim(errtext ?? '') || 'Download failed'];
		}

		// 只把 2xx 当成功；3xx 的响应体通常为空或一段 HTML，存下去会清空节点
		if (match(code, /^2[0-9][0-9]$/)) {
			let [pok, perr] = verify_peer_ip(peer, opts.proxy, opts.unverified);
			if (!pok) {
				cleanup();
				return [null, null, perr];
			}

			let size = util.file_size(tmp);
			if (size > max) {
				cleanup();
				return [null, null, msg.compose('Response exceeds the size limit (', max, ' bytes)')];
			}

			let [content] = util.read_file(tmp);
			let headers = read_headers(hdr);
			cleanup();

			if (content == null)
				return [null, null, 'Failed to read the response'];

			return [content, headers, null];
		}

		if (match(code, /^3[0-9][0-9]$/)) {
			// 重定向的**发起方**也要复核：否则公网域名可先 302 到 127.0.0.1
			let [pok, perr] = verify_peer_ip(peer, opts.proxy, opts.unverified);
			if (!pok) {
				cleanup();
				return [null, null, perr];
			}

			let loc = location_from_headers(hdr);
			if (loc == null) {
				cleanup();
				return [null, null, 'Redirect without a Location header'];
			}

			let next_url = resolve_url(cur, loc);
			let [np] = M.parse_url(next_url);
			if (!np) {
				cleanup();
				return [null, null, 'Invalid redirect target'];
			}

			let [ok, re] = M.check_public(np.host);
			if (!ok) {
				cleanup();
				return [null, null, msg.join('Unsafe redirect target: ', re ?? '')];
			}

			cleanup();
			cur = next_url;
		}
		else {
			cleanup();
			return [null, null, msg.join('HTTP error ', code)];
		}
	}

	return [null, null, 'Too many redirects'];
}

// wget 后端的代理环境变量。busybox wget 只认 http(s) 代理；不支持的协议必须
// 明确报错，不能丢掉代理静默直连。
M.wget_proxy_env = function(proxy) {
	if (proxy == null || proxy == '')
		return ['', null];

	let m = match(`${proxy}`, /^([A-Za-z][A-Za-z0-9]*):\/\//);
	let scheme = m ? lc(m[1]) : '';

	if (scheme != 'http' && scheme != 'https')
		return [null, msg.compose('The current download backend (wget) does not support ', uc(scheme),
			' proxies; install curl or use an http proxy')];

	return ['http_proxy=' + util.shq(proxy) + ' https_proxy=' + util.shq(proxy) + ' ', null];
};

function fetch_wget(url, parsed, opts) {
	// wget 拿不到对端地址，也没有重定向拦截；预检放行等于完全没有 SSRF 防护
	if (opts.unverified)
		return [null, null, 'No local DNS resolution: the wget backend cannot verify the target address and refused the download (install curl and retry)'];

	let max = opts.max_size, t = opts.timeout;

	let [proxy_env, perr] = M.wget_proxy_env(opts.proxy);
	if (proxy_env == null)
		return [null, null, perr];

	let ua_arg = '';
	if (opts.user_agent != null && opts.user_agent != '')
		ua_arg = ' -U ' + util.shq(opts.user_agent);

	let tag = util.rnd_hex(8);
	let tmp = '/tmp/substore_dl_wget_' + tag + '.tmp';
	let log = tmp + '.log';

	unlink(tmp);
	unlink(log);

	let cmd = proxy_env + 'wget -S -q -T ' + t + ua_arg
		+ ' -O ' + util.shq(tmp)
		+ ' ' + util.shq(url)
		+ ' >' + util.shq(log) + ' 2>&1';

	let rc = system(cmd);

	let [logtext] = util.read_file(log);
	unlink(log);

	let [safe, reason] = M.validate_redirect_chain(url, logtext ?? '');
	if (!safe) {
		unlink(tmp);
		return [null, null, reason];
	}

	let size = util.file_size(tmp);
	if (size > max) {
		unlink(tmp);
		return [null, null, msg.compose('Response exceeds the size limit (', max, ' bytes)')];
	}

	if (rc != 0) {
		unlink(tmp);
		return [null, null, 'Download failed (wget exit code is non-zero)'];
	}

	if (size == 0) {
		unlink(tmp);
		return [null, null, 'Download failed or the content is empty'];
	}

	let [content] = util.read_file(tmp);
	unlink(tmp);

	if (content == null)
		return [null, null, 'Failed to read the response'];

	return [content, {}, null]; // wget 不捕获响应头
}

function fetch(tool, url, parsed, opts) {
	if (tool == 'curl')
		return fetch_curl(url, parsed, opts);
	return fetch_wget(url, parsed, opts);
}

// 下载订阅内容。成功返回 [body, headers, nil]；失败 [null, null, err]
// opts.proxy 由调用方用 parse_proxy 校验；opts.user_agent 由 validate_user_agent 校验
M.download = function(url, opts) {
	opts = opts ?? {};

	let max_size = opts.max_size ?? M.DEFAULT_MAX_SIZE;
	let timeout = opts.timeout ?? M.DEFAULT_TIMEOUT;

	let [parsed] = M.parse_url(url);
	if (!parsed)
		return [null, null, 'Invalid URL'];

	let [ua, uaerr] = M.validate_user_agent(opts.user_agent);
	if (ua == null)
		return [null, null, uaerr];

	let [ok, reason, unverified] = M.check_public(parsed.host);
	if (!ok)
		return [null, null, reason];

	let tool = detect_tool();
	if (!tool)
		return [null, null, 'No download tool available (curl/wget)'];

	let [body, headers, ferr] = fetch(tool, url, parsed, {
		max_size: max_size,
		timeout: timeout,
		proxy: opts.proxy,
		user_agent: ua,
		unverified: unverified
	});

	if (body == null)
		return [null, null, ferr];

	return [body, headers ?? {}, null];
};

return M;
