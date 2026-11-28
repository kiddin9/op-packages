// util.uc — 通用工具（ucode，无外部依赖）
// luci-app-substore
//
// 约定：原 Lua 版用多返回值（`v, err` / `a, b, c`），ucode 函数只有一个
// 返回值，这里统一改成**数组**：`[v, err]`、`[host, port]` 等，调用方用
// 数组解构取值。解析类函数失败时返回 `[null, "msg"]`。

import { open, stat, chmod as fs_chmod, rename, unlink, mkdir,
	error as fserror } from 'fs';
import { floor, ceil, isnan, isinf, rand, srand } from 'math';
// LuCI / cron 都用 require() 加载本模块，因此模块间依赖也用 require()：
// ucode 的 import 要求文件是 module（export），而 require() 按普通脚本执行
// （顶层 return 即模块值）。两者不能同时满足，统一走 require。
const msg = require('substore.msg');

const M = {};

const B64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';

M.trim = function(s) {
	return trim(s ?? '');
};

// 安全 require：模块不存在时返回 null 而不报错
M.try_require = function(name) {
	try {
		return require(name);
	}
	catch (e) {
		return null;
	}
};

// ---------- Base64 ----------
M.base64_encode = function(s) {
	if (type(s) != 'string')
		return '';

	let out = [];
	for (let i = 0; i < length(s); i += 3) {
		let b1 = ord(substr(s, i, 1));
		let b2 = (i + 1 < length(s)) ? ord(substr(s, i + 1, 1)) : null;
		let b3 = (i + 2 < length(s)) ? ord(substr(s, i + 2, 1)) : null;
		let n = b1 * 65536 + (b2 ?? 0) * 256 + (b3 ?? 0);

		push(out, substr(B64, floor(n / 262144) % 64, 1));
		push(out, substr(B64, floor(n / 4096) % 64, 1));
		push(out, b2 != null ? substr(B64, floor(n / 64) % 64, 1) : '=');
		push(out, b3 != null ? substr(B64, n % 64, 1) : '=');
	}

	return join('', out);
};

M.base64_decode = function(s) {
	if (type(s) != 'string')
		return '';

	// 原实现先剔除所有非 base64 字符（含空白/换行），非法字符被忽略而非报错
	s = replace(s, /[^A-Za-z0-9+\/=]/g, '');

	let out = [];
	let n = 0, bits = 0;

	for (let i = 0; i < length(s); i++) {
		let c = substr(s, i, 1);

		if (c == '=')
			break;

		let v = index(B64, c);

		if (v >= 0) {
			n = n * 64 + v;
			bits += 6;

			while (bits >= 8) {
				bits -= 8;
				push(out, chr(floor(n / 2 ** bits) % 256));
				n = n % (2 ** bits);
			}
		}
	}

	return join('', out);
};

// URL-safe Base64（RFC 4648 base64url）：- _ 代替 + /，无 padding
M.base64_url_encode = function(s) {
	s = s ?? '';
	return replace(replace(replace(M.base64_encode(s), /\+/g, '-'), /\//g, '_'), /=+$/, '');
};

M.base64_url_decode = function(s) {
	if (type(s) != 'string')
		return '';
	return M.base64_decode(replace(replace(s, /-/g, '+'), /_/g, '/'));
};

// shell 单引号转义。拼进 shell 命令行的**一切外部数据**都必须走这里。
// 不能用 %q：它生成的是双引号字符串，而 /bin/sh 在双引号内仍然会做 $() 和
// `` 命令替换。单引号内除 ' 之外所有字符都是字面量，' 本身写作 '\'' 即可。
M.shq = function(s) {
	return "'" + replace(s == null ? '' : `${s}`, /'/g, () => "'\\''") + "'";
};

// 把值压成单行。Surge / Loon / Quantumult X / wg-quick .conf 都是行式格式：
// 值里一旦含换行，就会截断当前行并伪造出额外的一行（节点名、sni、path 等
// 全部来自订阅内容，属于不可信输入）。换行/回车压成空格，其余控制字符丢弃。
M.one_line = function(s) {
	if (s == null)
		return null;

	let t = replace(`${s}`, /[\r\n]+/g, ' ');
	let out = [];

	for (let i = 0; i < length(t); i++) {
		let c = substr(t, i, 1);
		let code = ord(c);

		// 其余控制字符（含制表符）直接丢弃
		if (code >= 32 && code != 127)
			push(out, c);
	}

	return join('', out);
};

// 生成随机十六进制 token（用于下载链接访问控制）。
// 优先直接读内核熵源；只有 /dev/urandom 不可用时才退回 PRNG（只播种一次）。
let prng_seeded = false;

function seed_prng() {
	if (prng_seeded)
		return;

	prng_seeded = true;
	srand(time());
}

M.rnd_hex = function(len) {
	len = len ?? 16;

	let fd = open('/dev/urandom', 'r');

	if (fd) {
		// 2.0 而不是 2：ucode 的 int / int 是整数除法，ceil(7 / 2) 会先截成 3、
		// 再 ceil 得到 3，奇数字节数于是少生成一个十六进制字符（rnd_hex(7)
		// 只有 6 个字符）。Lua 的 / 是浮点除法，不存在这个问题。
		let need = ceil(len / 2.0);
		let bytes = '';

		// read() 一次未必读满，短读会让返回的十六进制串变短（token 熵不足）
		while (length(bytes) < need) {
			let chunk = fd.read(need - length(bytes));
			if (chunk == null || chunk == '')
				break;
			bytes += chunk;
		}

		fd.close();

		if (length(bytes) == need) {
			let h = hexenc(bytes);
			return substr(h, 0, len);
		}
	}

	seed_prng();

	let out = [];
	const hex = '0123456789abcdef';

	for (let i = 0; i < len; i++)
		push(out, substr(hex, rand() % 16, 1));

	return join('', out);
};

// RFC 4122 version 4 UUID（8-4-4-4-12 十六进制）。
// 按规范置版本位（第 13 位 = 4）与变体位（第 17 位 ∈ 8/9/a/b），
// 而不是随便取 36 个字符。随机源复用 rnd_hex（优先 /dev/urandom）。
M.uuid = function() {
	let h = M.rnd_hex(32);
	if (length(h) < 32)
		return null;

	let variant = hex(substr(h, 16, 1)) % 4 + 8; // 8..11 → 8/9/a/b

	return sprintf('%s-%s-4%s-%x%s-%s',
		substr(h, 0, 8), substr(h, 8, 4), substr(h, 13, 3),
		variant, substr(h, 17, 3),
		substr(h, 20, 12));
};

// 原 Lua 版用于 string.gsub 替换串的字面转义。ucode 的 replace() 使用
// 正则与 `$1` 捕获引用，没有 `%` 语义；保留该函数只为兼容旧调用点/测试。
M.gsub_literal = function(s) {
	return replace(`${s ?? ''}`, /%/g, () => '%%');
};

// ---------- URL ----------
M.url_decode = function(s) {
	if (type(s) != 'string')
		return '';

	return replace(s, /%([0-9a-fA-F]{2})/g, (m, h) => chr(hex(h) ?? 0));
};

// 从 query string 提取字段（接受 URL 片段，如 "…?a=1&b=2#frag"）
M.url_extract = function(s, field) {
	if (type(s) != 'string')
		return null;

	let m = match(s, /[^#?]*\?([^#]*)/);
	if (!m)
		return null;

	for (let part in split(m[1], '&')) {
		let eq = index(part, '=');

		// 与原实现一致：只认完整的 "key=value" 对
		if (eq <= 0)
			continue;

		if (substr(part, 0, eq) == field)
			return M.url_decode(substr(part, eq + 1));
	}

	return null;
};

// 拆分 host:port，支持 [ipv6]:port。返回 [host, port]。
M.split_hostport = function(s) {
	if (type(s) != 'string')
		return [null, null];

	s = M.trim(s);

	// 去掉可能尾随的路径（如 "host:port/path"）
	let slash = index(s, '/');
	if (slash >= 0)
		s = substr(s, 0, slash);

	if (s == '')
		return [null, null];

	if (substr(s, 0, 1) == '[') {
		let close = index(s, ']');
		if (close < 0)
			return [null, null];

		let host = substr(s, 1, close - 1);
		let m = match(substr(s, close + 1), /^:(\d+)$/);

		return [host, m ? m[1] : null];
	}

	let m = match(s, /^([^:]+):(\d+)$/);
	if (m)
		return [m[1], m[2]];

	// 没有可识别的端口，整串就是主机名 —— 但必须先剥掉**尾随**冒号：
	// `"example.com:"` 若原样返回，调用方拿带冒号的串当主机名，DNS 解析必然
	// 失败，而失败点离这里很远、很难定位。只剥结尾冒号，裸 IPv6 不受影响。
	s = replace(s, /:$/, '');
	if (s == '')
		return [null, null];

	return [s, null];
};

// 解析 SIP003 插件串（shadowsocks 的 `plugin` 字段）。
// 返回 [name, opts_string, opts_map]；空串或没有插件名时返回 null。
M.parse_sip003_plugin = function(raw) {
	if (type(raw) != 'string' || raw == '')
		return null;

	let fields = [], buf = [];
	let i = 0, n = length(raw);

	while (i < n) {
		let c = substr(raw, i, 1);

		if (c == '\\' && i + 1 < n) {
			push(buf, c + substr(raw, i + 1, 1));
			i += 2;
		}
		else if (c == ';') {
			push(fields, join('', buf));
			buf = [];
			i++;
		}
		else {
			push(buf, c);
			i++;
		}
	}

	push(fields, join('', buf));

	let name = M.trim(fields[0] ?? '');
	if (name == '')
		return null;

	let opts_list = [];
	for (let idx = 1; idx < length(fields); idx++) {
		let f = M.trim(fields[idx]);
		if (f != '')
			push(opts_list, f);
	}

	let map = {};
	for (let f in opts_list) {
		let m = match(f, /^([^=]+)=(.*)$/);
		if (m)
			map[M.trim(m[1])] = m[2];
		else
			map[f] = true;
	}

	return [name, join(';', opts_list), map];
};

// ---------- JSON ----------
// ucode 原生区分 array / object / null，不再需要 Lua 版的元表哨兵；
// 这两个常量仅为兼容旧调用点与测试而保留。
M.JSON_NULL = null;
M.JSON_EMPTY_OBJECT = {};

function json_escape_string(s) {
	let out = ['"'];

	for (let i = 0; i < length(s); i++) {
		let c = substr(s, i, 1);
		let code = ord(c);

		if (c == '"')
			push(out, '\\"');
		else if (c == '\\')
			push(out, '\\\\');
		else if (code < 32) {
			switch (c) {
			case '\n': push(out, '\\n'); break;
			case '\r': push(out, '\\r'); break;
			case '\t': push(out, '\\t'); break;
			case '\b': push(out, '\\b'); break;
			case '\f': push(out, '\\f'); break;
			default: push(out, sprintf('\\u%04x', code));
			}
		}
		else
			push(out, c);
	}

	push(out, '"');
	return join('', out);
}

function json_encode_value(v) {
	let t = type(v);

	if (v == null)
		return 'null';
	else if (t == 'string')
		return json_escape_string(v);
	else if (t == 'int' || t == 'double') {
		// 非有限数必须编成 null：`%.14g` 对 inf / -inf 产出的是字面量
		// `inf` / `-inf`，那不是合法 JSON —— 整份文件会因此解析不了。
		if (isnan(v) || isinf(v))
			return 'null';
		return sprintf('%.14g', v);
	}
	else if (t == 'bool')
		return v ? 'true' : 'false';
	else if (t == 'array') {
		let out = [];
		for (let item in v)
			push(out, json_encode_value(item));
		return '[' + join(',', out) + ']';
	}
	else if (t == 'object') {
		let out = [];
		for (let k, val in v)
			push(out, json_escape_string(`${k}`) + ':' + json_encode_value(val));
		return '{' + join(',', out) + '}';
	}

	return 'null';
}

M.json_encode = function(v) {
	return json_encode_value(v);
};

function utf8_encode(cp) {
	if (cp < 0x80)
		return chr(cp);
	if (cp < 0x800)
		return chr(0xC0 + floor(cp / 0x40)) + chr(0x80 + cp % 0x40);
	if (cp < 0x10000)
		return chr(0xE0 + floor(cp / 0x1000)) +
			chr(0x80 + floor(cp / 0x40) % 0x40) + chr(0x80 + cp % 0x40);
	return chr(0xF0 + floor(cp / 0x40000)) +
		chr(0x80 + floor(cp / 0x1000) % 0x40) +
		chr(0x80 + floor(cp / 0x40) % 0x40) + chr(0x80 + cp % 0x40);
}

// 返回 [value, err]：`[null, null]` 是合法的顶层 null，`[null, "…"]` 才是错误。
M.json_decode = function(s) {
	if (type(s) != 'string')
		return [null, 'not a string'];

	let i = 0;
	const len = length(s);
	const MAX_DEPTH = 64;

	function skip_ws() {
		while (i < len) {
			let c = substr(s, i, 1);
			if (c == ' ' || c == '\t' || c == '\n' || c == '\r')
				i++;
			else
				break;
		}
	}

	function parse(depth) {
		skip_ws();
		if (i >= len)
			return [null, 'unexpected end'];

		let c = substr(s, i, 1);

		if ((c == '{' || c == '[') && depth >= MAX_DEPTH)
			return [null, 'nesting too deep'];

		if (c == '{') {
			i++;
			let obj = {};
			skip_ws();
			if (substr(s, i, 1) == '}') {
				i++;
				return [obj];
			}

			while (true) {
				skip_ws();
				let [k, ke] = parse(depth + 1);
				if (ke)
					return [null, ke];
				if (type(k) != 'string')
					return [null, 'expected string key'];

				skip_ws();
				if (substr(s, i, 1) != ':')
					return [null, "expected ':'"];
				i++;

				let [val, verr] = parse(depth + 1);
				if (verr)
					return [null, verr];
				obj[k] = val;

				skip_ws();
				let cc = substr(s, i, 1);
				if (cc == ',')
					i++;
				else if (cc == '}') {
					i++;
					return [obj];
				}
				else
					return [null, "expected ',' or '}'"];
			}
		}

		if (c == '[') {
			i++;
			let arr = [];
			skip_ws();
			if (substr(s, i, 1) == ']') {
				i++;
				return [arr];
			}

			while (true) {
				let [val, verr] = parse(depth + 1);
				if (verr)
					return [null, verr];
				push(arr, val);

				skip_ws();
				let cc = substr(s, i, 1);
				if (cc == ',')
					i++;
				else if (cc == ']') {
					i++;
					return [arr];
				}
				else
					return [null, "expected ',' or ']'"];
			}
		}

		if (c == '"') {
			i++;
			let out = [];

			while (true) {
				if (i >= len)
					return [null, 'unterminated string'];

				let ch = substr(s, i, 1);

				if (ch == '"') {
					i++;
					return [join('', out)];
				}

				if (ch == '\\') {
					i++;
					let e = substr(s, i, 1);
					i++;

					if (e == 'u') {
						let hexs = substr(s, i, 4);
						i += 4;
						let cp = hex(hexs);
						if (isnan(cp))
							return [null, 'bad unicode'];

						if (cp >= 0xD800 && cp <= 0xDBFF) {
							if (substr(s, i, 1) == '\\' && substr(s, i + 1, 1) == 'u') {
								let cp2 = hex(substr(s, i + 2, 4));
								if (!isnan(cp2) && cp2 >= 0xDC00 && cp2 <= 0xDFFF) {
									i += 6;
									cp = 0x10000 + (cp - 0xD800) * 0x400 + (cp2 - 0xDC00);
								}
							}
						}

						push(out, utf8_encode(cp));
					}
					else {
						switch (e) {
						case '"': push(out, '"'); break;
						case '\\': push(out, '\\'); break;
						case '/': push(out, '/'); break;
						case 'b': push(out, '\b'); break;
						case 'f': push(out, '\f'); break;
						case 'n': push(out, '\n'); break;
						case 'r': push(out, '\r'); break;
						case 't': push(out, '\t'); break;
						default: push(out, e);
						}
					}
				}
				else {
					push(out, ch);
					i++;
				}
			}
		}

		if (c == 't' && substr(s, i, 4) == 'true') {
			i += 4;
			return [true];
		}
		if (c == 'f' && substr(s, i, 5) == 'false') {
			i += 5;
			return [false];
		}
		if (c == 'n' && substr(s, i, 4) == 'null') {
			i += 4;
			return [null];
		}

		if (match(c, /[-0-9]/)) {
			let num = match(substr(s, i), /^-?\d+\.?\d*[eE]?[+-]?\d*/);
			if (!num || num[0] == '')
				return [null, 'bad number'];

			let tok = num[0];
			i += length(tok);

			let n = +tok;
			if (n == null || isnan(n))
				return [null, 'bad number value'];

			return [n];
		}

		return [null, 'unexpected char ' + c];
	}

	let [v, perr] = parse(0);
	if (perr)
		return [null, perr];

	// 解析出一个值还不够，必须确认**没有剩余内容**：parse 只消费一个值，
	// 于是 "1 2" / "[1] junk" / "1.2.3" 这类输入会被当成合法值静默接受。
	skip_ws();
	if (i < len)
		return [null, sprintf('trailing content at position %d', i + 1)];

	return [v, null];
};

// ---------- 文件 ----------
M.read_file = function(path) {
	let fd = open(path, 'r');
	if (!fd)
		return [null, fserror()];

	let data = fd.read('all');
	fd.close();

	if (data == null)
		return [null, fserror()];

	return [data, null];
};

M.file_size = function(path) {
	let s = stat(path);
	return s ? (s.size ?? 0) : 0;
};

// mode 传八进制字符串（如 "600"）
M.chmod = function(path, mode) {
	return fs_chmod(path, int(mode, 8)) == true;
};

// 原子写：先写临时文件再重命名，避免写一半损坏。
// 临时文件名带随机后缀；write / close 的返回值必须检查，否则磁盘写满时
// 会原子地换上一个残缺文件。mode 可选：rename 之后收紧权限。
M.atomic_write = function(path, content, mode) {
	let tmp = sprintf('%s.tmp.%s', path, M.rnd_hex(8));
	let fd = open(tmp, 'w');

	if (!fd)
		return [false, fserror()];

	let wok = fd.write(content);
	if (wok == null) {
		let err = fserror();
		fd.close();
		unlink(tmp);
		return [false, err];
	}

	let cok = fd.close();
	if (cok == false) {
		let err = fserror();
		unlink(tmp);
		return [false, err];
	}

	if (!rename(tmp, path)) {
		let err = fserror();
		unlink(tmp);
		return [false, err];
	}

	if (mode)
		M.chmod(path, mode);

	return [true, null];
};

// 建目录。mode 可选，仅在目录**由本次调用创建**时生效。
M.ensure_dir = function(path, mode) {
	if (mode)
		system(sprintf('mkdir -p -m %s %s >/dev/null 2>&1', mode, M.shq(path)));
	else
		system('mkdir -p ' + M.shq(path));
};

// ---------- 互斥锁（mkdir 锁 + 陈旧锁回收） ----------
// mkdir 本身是原子的，成功者只有一个，拿它当锁。崩溃残留靠锁目录自身的
// mtime 判定回收，否则永久死锁。持有者文件只作排障用，不参与判定。
M.LOCK_STALE = 60;

function lock_is_stale(path, stale) {
	let s = stat(path);

	// stat 失败时判定为陈旧：无法确认的锁宁可回收，也不要永久卡死
	if (!s)
		return true;

	return (time() - (s.mtime ?? 0)) > stale;
}

M.lock_acquire = function(path, opts) {
	opts = opts ?? {};
	let stale = opts.stale ?? M.LOCK_STALE;

	// 最多两轮：第一轮抢不到就查一次陈旧性，回收后第二轮重抢。
	for (let round = 0; round < 2; round++) {
		if (mkdir(path, 448)) {
			let fd = open(path + '/owner', 'w');
			if (fd) {
				fd.write(sprintf('%d %d\n', opts.pid ?? 0, time()));
				fd.close();
			}
			return true;
		}

		if (lock_is_stale(path, stale))
			system('rm -rf ' + M.shq(path) + ' >/dev/null 2>&1');
		else
			return false;
	}

	return false;
};

M.lock_release = function(path) {
	system('rm -rf ' + M.shq(path) + ' >/dev/null 2>&1');
};

// ---------- 人性化格式 ----------
M.human_bytes = function(n) {
	n = floor((+n ?? 0) + 0.5);
	if (n <= 0)
		return '0B';

	let units = ['B', 'K', 'M', 'G', 'T'];
	let i = 0, v = n;

	while (v >= 1024 && i < length(units) - 1) {
		// 必须用 1024.0：ucode 的 int / int 是整数除法，1.5 会被截成 1
		v = v / 1024.0;
		i++;
	}

	let s = replace(sprintf('%.1f', v), /\.0$/, '');
	return s + units[i];
};

// 秒数 → 可读时长。返回**语言中立的组合消息**（数字 + 单位 msgid），
// 由显示边界逐段翻译。单位 msgid 带前导空格：英文得 "3 days"，中文 msgstr
// 去掉空格即 "3天"。本模块不能依赖 LuCI i18n（cron 独立进程也会用它）。
M.human_duration = function(secs) {
	secs = +secs ?? 0;
	if (secs <= 0)
		return 'Expired';

	let d = secs / 86400;
	if (d >= 1)
		return msg.compose(floor(d), ' days');

	let h = secs / 3600;
	if (h >= 1)
		return msg.compose(floor(h), ' hours');

	let m = secs / 60;
	if (m >= 1)
		return msg.compose(floor(m), ' minutes');

	return 'Less than a minute';
};

// 为一组节点生成唯一 tag（供 sing-box / Xray 完整配置使用）。
// 重名时追加 " #2"、" #3"；reserved 中的保留 tag 不参与分配。
M.unique_tags = function(nodes, reserved) {
	let used = {};
	for (let k in (reserved ?? {}))
		used[k] = true;

	let tags = [];

	for (let n in (nodes ?? [])) {
		let base = n.name;
		if (base == null || base == '')
			base = `${n.server ?? ''}:${n.port ?? ''}`;

		let tag = base, k = 2;
		while (used[tag] === true) {
			tag = base + ' #' + k;
			k++;
		}

		used[tag] = true;
		push(tags, tag);
	}

	return tags;
};

return M;
