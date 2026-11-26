'use strict';

import * as fs from 'fs';
import { cursor } from 'uci';
import * as ubus from 'ubus';
import { sha256 } from 'digest';

const STATE_DIR = '/var/run/tencentddns';
const STATE_FILE = '/var/run/tencentddns/state.json';
const LOCK_FILE = '/var/run/tencentddns/sync.lock';
const LOG_FILE = '/var/log/tencentddns.log';

const DEFAULT_IPV4_URLS = [
	'https://4.ipw.cn',
	'https://myip.ipip.net/s',
	'https://ddns.oray.com/checkip',
	'https://api.ipify.org'
];

const DEFAULT_IPV6_URLS = [
	'https://6.ipw.cn',
	'https://speed.neu6.edu.cn/getIP.php',
	'https://api6.ipify.org'
];

function ensure_dirs() {
	if (!fs.access('/var/run', 'f'))
		fs.mkdir('/var/run');
	if (!fs.access(STATE_DIR, 'f'))
		fs.mkdir(STATE_DIR);
	if (!fs.access('/var/log', 'f'))
		fs.mkdir('/var/log');
}

function assign_obj(target, src) {
	let out = (type(target) == 'object' && target != null) ? target : {};
	if (type(src) == 'object' && src != null) {
		for (let k in keys(src))
			out[k] = src[k];
	}
	return out;
}

function now_str(epoch) {
	let tm = localtime(epoch != null ? epoch : time());
	return sprintf('%04d-%02d-%02d %02d:%02d:%02d',
		tm.year, tm.mon, tm.mday, tm.hour, tm.min, tm.sec);
}

function utc_date_str(epoch) {
	let tm = gmtime(epoch != null ? epoch : time());
	return sprintf('%04d-%02d-%02d', tm.year, tm.mon, tm.mday);
}

function to_bool(val, defval) {
	if (val == null || val === '')
		return !!defval;
	if (type(val) == 'bool')
		return val;
	let s = lc('' + val);
	return (s == '1' || s == 'true' || s == 'yes' || s == 'on' || s == 'enabled');
}

function to_int(val, defval, minval, maxval) {
	let n = int(val);
	if (n != n || type(n) != 'int')
		n = defval;
	if (minval != null && n < minval)
		n = minval;
	if (maxval != null && n > maxval)
		n = maxval;
	return n;
}

function shell_quote(s) {
	return "'" + replace('' + s, "'", "'\"'\"'") + "'";
}

function curl_escape(s) {
	let out = replace('' + s, '\\', '\\\\');
	out = replace(out, '"', '\\"');
	out = replace(out, '\n', '\\n');
	out = replace(out, '\r', '\\r');
	return out;
}

function urlencode(str) {
	let s = '' + (str != null ? str : '');
	let out = '';
	let len = length(s);
	for (let i = 0; i < len; i++) {
		let b = ord(s, i);
		if ((b >= 48 && b <= 57) ||
		    (b >= 65 && b <= 90) ||
		    (b >= 97 && b <= 122) ||
		    b == 45 || b == 95 || b == 46 || b == 126) {
			out += chr(b);
		} else {
			out += sprintf('%%%02X', b);
		}
	}
	return out;
}

/*
 * RFC 2104 HMAC-SHA256 implemented directly on ucode binary byte strings
 * and libmd sha256(), avoiding OpenSSL CLI forks or credential exposure.
 */
function hmac_sha256_hex(key, msg) {
	let k = (type(key) == 'string') ? key : ('' + key);
	let m = (type(msg) == 'string') ? msg : ('' + msg);

	if (length(k) > 64)
		k = hexdec(sha256(k), '');

	let ipad = '';
	let opad = '';
	let klen = length(k);
	for (let i = 0; i < 64; i++) {
		let b = (i < klen) ? ord(k, i) : 0;
		ipad += chr(b ^ 0x36);
		opad += chr(b ^ 0x5c);
	}

	let inner_hex = sha256(ipad + m);
	return lc(sha256(opad + hexdec(inner_hex, '')));
}

function hmac_sha256_bin(key, msg) {
	return hexdec(hmac_sha256_hex(key, msg), '');
}

/*
 * Tencent Cloud API 3.0 Signature v3 (TC3-HMAC-SHA256)
 */
function build_tc3_auth(secret_id, secret_key, host, service, action, payload, timestamp) {
	let ts = (timestamp != null) ? timestamp : time();
	let date = utc_date_str(ts);
	let ct = 'application/json; charset=utf-8';
	let lhost = lc(host);
	let laction = lc(action);

	let canonical_headers = 'content-type:' + ct + '\nhost:' + lhost + '\nx-tc-action:' + laction + '\n';
	let signed_headers = 'content-type;host;x-tc-action';
	let hashed_payload = lc(sha256(payload));

	let canonical_request = 'POST\n/\n\n' + canonical_headers + '\n' + signed_headers + '\n' + hashed_payload;
	let credential_scope = date + '/' + service + '/tc3_request';
	let string_to_sign = 'TC3-HMAC-SHA256\n' + sprintf('%d', ts) + '\n' + credential_scope + '\n' + lc(sha256(canonical_request));

	let k_date = hmac_sha256_bin('TC3' + secret_key, date);
	let k_service = hmac_sha256_bin(k_date, service);
	let k_signing = hmac_sha256_bin(k_service, 'tc3_request');
	let signature = hmac_sha256_hex(k_signing, string_to_sign);

	return {
		timestamp: ts,
		date: date,
		authorization: 'TC3-HMAC-SHA256 Credential=' + secret_id + '/' + credential_scope +
			', SignedHeaders=' + signed_headers + ', Signature=' + signature
	};
}

function write_log(level, tag, message, max_lines) {
	ensure_dirs();
	let limit = to_int(max_lines, 500, 50, 5000);
	let prefix = tag ? ('[' + tag + '] ') : '';
	let line = sprintf('%s [%-5s] %s%s\n', now_str(), uc(level || 'INFO'), prefix, '' + message);

	let fh = fs.open(LOG_FILE, 'a', 0o640);
	if (fh) {
		fh.write(line);
		fh.close();
	}

	let st = fs.stat(LOG_FILE);
	if (st && st.size > limit * 160) {
		let content = fs.readfile(LOG_FILE);
		if (content) {
			let lines = split(rtrim(content, '\n'), '\n');
			if (length(lines) > limit) {
				let kept = slice(lines, length(lines) - limit);
				let tmp = LOG_FILE + '.tmp';
				if (fs.writefile(tmp, join('\n', kept) + '\n') != null)
					fs.rename(tmp, LOG_FILE);
			}
		}
	}
}

function clear_logs() {
	ensure_dirs();
	fs.writefile(LOG_FILE, sprintf('%s [INFO ] Log cleared by user\n', now_str()));
	return true;
}

function read_logs(max_lines) {
	if (!fs.access(LOG_FILE, 'r'))
		return '';
	let limit = to_int(max_lines, 200, 10, 2000);
	let st = fs.stat(LOG_FILE);
	if (!st || st.size == 0)
		return '';

	let content = fs.readfile(LOG_FILE);
	if (!content)
		return '';
	let lines = split(rtrim(content, '\n'), '\n');
	if (length(lines) > limit)
		lines = slice(lines, length(lines) - limit);
	return join('\n', lines);
}

function load_state() {
	ensure_dirs();
	if (!fs.access(STATE_FILE, 'r'))
		return { updated_at: 0, records: {} };
	let raw = fs.readfile(STATE_FILE);
	if (!raw || !length(trim(raw)))
		return { updated_at: 0, records: {} };
	try {
		let parsed = json(raw);
		if (type(parsed) == 'object' && parsed != null) {
			if (type(parsed.records) != 'object' || parsed.records == null)
				parsed.records = {};
			return parsed;
		}
	} catch (e) {}
	return { updated_at: 0, records: {} };
}

function save_state(state) {
	ensure_dirs();
	state.updated_at = time();
	let tmp = sprintf('%s.tmp.%d', STATE_FILE, (clock(true)?.[1] ?? time()));
	let payload = sprintf('%.2J\n', state);
	if (fs.writefile(tmp, payload) != null) {
		fs.chmod(tmp, 0o644);
		fs.rename(tmp, STATE_FILE);
	}
}

function acquire_lock() {
	ensure_dirs();
	if (fs.access(LOCK_FILE, 'f')) {
		let st = fs.stat(LOCK_FILE);
		if (st && (time() - st.mtime) < 90)
			return false;
		fs.unlink(LOCK_FILE);
	}
	let fh = fs.open(LOCK_FILE, 'wx', 0o600);
	if (!fh)
		return false;
	fh.write(sprintf('%d\n', time()));
	fh.close();
	return true;
}

function release_lock() {
	if (fs.access(LOCK_FILE, 'f'))
		fs.unlink(LOCK_FILE);
}

function cleanup_temp_files(cfg_path, body_path) {
	if (cfg_path && fs.access(cfg_path, 'f'))
		fs.unlink(cfg_path);
	if (body_path && fs.access(body_path, 'f'))
		fs.unlink(body_path);
}

/*
 * Execute HTTP request via curl with an ephemeral 0600 config file so API keys,
 * tokens and signatures never appear in /proc/<pid>/cmdline.
 */
function http_request(opts) {
	ensure_dirs();
	let seq = sprintf('%d_%d', time(), (clock(true)?.[1] ?? 0));
	let cfg_path = STATE_DIR + '/curl_' + seq + '.cfg';
	let body_path = null;

	try {
		let lines = [
			'silent',
			'show-error',
			'location',
			sprintf('connect-timeout = %d', opts.connect_timeout || 8),
			sprintf('max-time = %d', opts.max_time || 20),
			sprintf('url = "%s"', curl_escape(opts.url)),
			'user-agent = "OpenWrt-TencentDDNS/2.0 (LuCI-25.12; ucode)"'
		];

		if (opts.family == 4)
			push(lines, 'ipv4');
		else if (opts.family == 6)
			push(lines, 'ipv6');

		if (opts.insecure_tls)
			push(lines, 'insecure');

		if (opts.bind_dev && match(opts.bind_dev, /^[A-Za-z0-9._-]+$/))
			push(lines, sprintf('interface = "%s"', curl_escape(opts.bind_dev)));

		if (opts.method == 'POST')
			push(lines, 'request = "POST"');

		if (type(opts.headers) == 'array') {
			for (let h in opts.headers)
				push(lines, sprintf('header = "%s"', curl_escape(h)));
		}

		if (opts.body != null) {
			body_path = STATE_DIR + '/body_' + seq + '.dat';
			let bfh = fs.open(body_path, 'wx', 0o600);
			if (!bfh) {
				cleanup_temp_files(cfg_path, body_path);
				return { ok: false, error: 'Failed to create temporary request payload file' };
			}
			bfh.write('' + opts.body);
			bfh.close();
			push(lines, sprintf('data-binary = "@%s"', curl_escape(body_path)));
		}

		let cfh = fs.open(cfg_path, 'wx', 0o600);
		if (!cfh) {
			cleanup_temp_files(cfg_path, body_path);
			return { ok: false, error: 'Failed to create temporary curl config file' };
		}
		cfh.write(join('\n', lines) + '\n');
		cfh.close();

		let cmd = '/usr/bin/curl -K ' + shell_quote(cfg_path) + ' 2>&1';
		let proc = fs.popen(cmd, 'r');
		if (!proc) {
			cleanup_temp_files(cfg_path, body_path);
			return { ok: false, error: 'Failed to invoke /usr/bin/curl' };
		}

		let out = proc.read('all');
		let rc = proc.close();
		cleanup_temp_files(cfg_path, body_path);

		if (rc != 0)
			return { ok: false, error: trim(out || sprintf('curl exited with code %d', rc)), raw: out };

		return { ok: true, body: out || '' };
	} catch (e) {
		cleanup_temp_files(cfg_path, body_path);
		return { ok: false, error: '' + (e?.message || e) };
	}
}

/*
 * IP address validation & public/private classification via ucode iptoarr/arrtoip
 */
function is_valid_ipv4(ip, allow_private) {
	if (type(ip) != 'string')
		return false;
	let b = iptoarr(trim(ip));
	if (type(b) != 'array' || length(b) != 4)
		return false;
	if (b[0] == 0 || b[0] == 127 || b[0] >= 224)
		return false;
	if (b[0] == 169 && b[1] == 254)
		return false;
	if (allow_private)
		return true;
	if (b[0] == 10)
		return false;
	if (b[0] == 172 && b[1] >= 16 && b[1] <= 31)
		return false;
	if (b[0] == 192 && b[1] == 168)
		return false;
	if (b[0] == 100 && b[1] >= 64 && b[1] <= 127)
		return false;
	if (b[0] == 198 && (b[1] == 18 || b[1] == 19))
		return false;
	return true;
}

function is_valid_ipv6(ip, allow_private) {
	if (type(ip) != 'string')
		return false;
	let b = iptoarr(trim(ip));
	if (type(b) != 'array' || length(b) != 16)
		return false;

	let all_zero = true;
	for (let i = 0; i < 15; i++) {
		if (b[i] != 0) {
			all_zero = false;
			break;
		}
	}
	if (all_zero && (b[15] == 0 || b[15] == 1))
		return false;

	if (b[0] == 0xff)
		return false;
	if (b[0] == 0xfe && (b[1] & 0xc0) == 0x80)
		return false;

	if (b[0] == 0x20 && b[1] == 0x01 && b[2] == 0x0d && b[3] == 0xb8)
		return false;

	if (allow_private)
		return ((b[0] & 0xe0) == 0x20 || (b[0] & 0xfe) == 0xfc);

	return ((b[0] & 0xe0) == 0x20);
}

function extract_ip_from_text(text, family, allow_private) {
	if (type(text) != 'string' || !length(text))
		return null;
	let trimmed = trim(text);

	if (family == 4 && is_valid_ipv4(trimmed, allow_private))
		return arrtoip(iptoarr(trimmed));
	if (family == 6 && is_valid_ipv6(trimmed, allow_private))
		return arrtoip(iptoarr(trimmed));

	if (family == 4) {
		let matches = match(trimmed, /[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/g);
		if (matches) {
			for (let m in matches) {
				let cand = m[0];
				if (is_valid_ipv4(cand, allow_private))
					return arrtoip(iptoarr(cand));
			}
		}
	} else {
		let tokens = split(trimmed, /[^0-9a-fA-F:]+/);
		for (let tok in tokens) {
			if (index(tok, ':') >= 0 && is_valid_ipv6(tok, allow_private))
				return arrtoip(iptoarr(tok));
		}
	}
	return null;
}

function merge_ipv6_prefix_suffix(prefix_addr, prefix_len, suffix_str) {
	let p_bytes = iptoarr(trim('' + prefix_addr));
	if (type(p_bytes) != 'array' || length(p_bytes) != 16)
		return null;

	let plen = to_int(prefix_len, 64, 1, 128);
	let s = trim('' + (suffix_str || '::1'));
	if (index(s, '::') < 0 && length(split(s, ':')) < 8)
		s = '::' + ltrim(s, ':');

	let s_bytes = iptoarr(s);
	if (type(s_bytes) != 'array' || length(s_bytes) != 16)
		return null;

	let out = [];
	for (let i = 0; i < 16; i++) {
		let bit_start = i * 8;
		let bit_end = bit_start + 8;
		if (bit_end <= plen) {
			push(out, p_bytes[i]);
		} else if (bit_start >= plen) {
			push(out, s_bytes[i]);
		} else {
			let keep = plen - bit_start;
			let mask_hi = (0xff << (8 - keep)) & 0xff;
			let mask_lo = (~mask_hi) & 0xff;
			push(out, (p_bytes[i] & mask_hi) | (s_bytes[i] & mask_lo));
		}
	}
	return arrtoip(out);
}

function get_ubus_iface_status(ubus_ctx, iface) {
	if (!iface || !match(iface, /^[A-Za-z0-9_]+$/))
		return null;
	if (!ubus_ctx)
		return null;
	return ubus_ctx.call('network.interface.' + iface, 'status');
}

function resolve_ipv4_from_iface(ubus_ctx, iface, allow_private) {
	let st = get_ubus_iface_status(ubus_ctx, iface);
	if (type(st) != 'object' || st == null)
		return { ip: null, error: sprintf('Interface %s not found or down', iface) };

	let addrs = st['ipv4-address'];
	if (type(addrs) == 'array') {
		for (let item in addrs) {
			if (item && is_valid_ipv4(item.address, allow_private))
				return { ip: arrtoip(iptoarr(item.address)), device: st.l3_device || st.device };
		}
	}
	return { ip: null, error: sprintf('No valid %sIPv4 address on interface %s', allow_private ? '' : 'public ', iface) };
}

function extract_ipv6_from_status(st, allow_private) {
	if (type(st) != 'object' || st == null)
		return null;

	let best = null;
	let best_pref = -1;

	let addrs = st['ipv6-address'];
	if (type(addrs) == 'array') {
		for (let item in addrs) {
			if (!item || !is_valid_ipv6(item.address, allow_private))
				continue;
			let pref = to_int(item.preferred, 0);
			if (pref > best_pref) {
				best_pref = pref;
				best = arrtoip(iptoarr(item.address));
			}
		}
	}
	if (best)
		return best;

	let assigns = st['ipv6-prefix-assignment'];
	if (type(assigns) == 'array') {
		for (let a in assigns) {
			let local_addr = a?.['local-address']?.address;
			if (local_addr && is_valid_ipv6(local_addr, allow_private))
				return arrtoip(iptoarr(local_addr));
		}
	}
	return null;
}

function resolve_ipv6_from_iface(ubus_ctx, iface, allow_private) {
	let candidates = [ iface ];
	if (iface == 'wan')
		push(candidates, 'wan_6', 'wan6');
	else if (iface == 'wan6')
		push(candidates, 'wan_6');

	for (let name in candidates) {
		let st = get_ubus_iface_status(ubus_ctx, name);
		let ip = extract_ipv6_from_status(st, allow_private);
		if (ip)
			return { ip: ip, device: st.l3_device || st.device, resolved_iface: name };
	}
	return { ip: null, error: sprintf('No valid %sIPv6 address on interface %s', allow_private ? '' : 'GUA ', iface) };
}

function resolve_ipv6_prefix_suffix(ubus_ctx, iface, suffix, allow_private) {
	let candidates = [ iface ];
	if (iface == 'wan')
		push(candidates, 'wan_6', 'wan6', 'lan');
	else if (iface == 'wan6' || iface == 'wan_6')
		push(candidates, 'lan');

	for (let name in candidates) {
		let st = get_ubus_iface_status(ubus_ctx, name);
		if (type(st) != 'object' || st == null)
			continue;

		let assigns = st['ipv6-prefix-assignment'];
		if (type(assigns) == 'array') {
			for (let a in assigns) {
				if (a && a.address) {
					let merged = merge_ipv6_prefix_suffix(a.address, a.mask || 64, suffix);
					if (merged && is_valid_ipv6(merged, allow_private))
						return { ip: merged, resolved_iface: name };
				}
			}
		}

		let prefixes = st['ipv6-prefix'];
		if (type(prefixes) == 'array') {
			for (let p in prefixes) {
				if (p && p.address) {
					let merged = merge_ipv6_prefix_suffix(p.address, p.mask || 64, suffix);
					if (merged && is_valid_ipv6(merged, allow_private))
						return { ip: merged, resolved_iface: name };
				}
			}
		}
	}

	return { ip: null, error: sprintf('No active IPv6 delegated prefix found on %s', iface) };
}

function resolve_ip_from_device(dev, family, allow_private) {
	if (!dev || !match(dev, /^[A-Za-z0-9._-]+$/))
		return { ip: null, error: 'Invalid network device name' };

	let cmd = sprintf('/sbin/ip -%d -o addr show dev %s scope global 2>/dev/null', family, shell_quote(dev));
	let proc = fs.popen(cmd, 'r');
	if (!proc)
		return { ip: null, error: 'Failed to execute /sbin/ip' };
	let out = proc.read('all') || '';
	proc.close();

	let lines = split(out, '\n');
	for (let line in lines) {
		if (index(line, 'deprecated') >= 0 || index(line, 'tentative') >= 0)
			continue;
		let m = (family == 4)
			? match(line, /inet ([0-9.]+)\//)
			: match(line, /inet6 ([0-9a-fA-F:]+)\//);
		if (m && m[1]) {
			let ok = (family == 4) ? is_valid_ipv4(m[1], allow_private) : is_valid_ipv6(m[1], allow_private);
			if (ok)
				return { ip: arrtoip(iptoarr(m[1])) };
		}
	}
	return { ip: null, error: sprintf('No valid IPv%d address on device %s', family, dev) };
}

function resolve_ip_from_urls(urls, family, bind_dev, allow_private, insecure_tls) {
	let list = (type(urls) == 'array' && length(urls) > 0)
		? urls
		: ((family == 4) ? DEFAULT_IPV4_URLS : DEFAULT_IPV6_URLS);

	let last_err = 'No check URLs configured';
	for (let u in list) {
		let url = trim('' + u);
		if (!length(url) || !match(url, /^https?:\/\//))
			continue;
		let res = http_request({
			url: url,
			family: family,
			bind_dev: bind_dev,
			insecure_tls: insecure_tls,
			connect_timeout: 5,
			max_time: 10
		});
		if (res.ok) {
			let ip = extract_ip_from_text(res.body, family, allow_private);
			if (ip)
				return { ip: ip, source_url: url };
			last_err = sprintf('Invalid IP response from %s', url);
		} else {
			last_err = sprintf('%s: %s', url, res.error || 'request failed');
		}
	}
	return { ip: null, error: last_err };
}

function get_target_ip(ubus_ctx, global_cfg, rule, family) {
	let allow_private = rule.allow_private_ip;
	if (family == 4) {
		let src = rule.ipv4_source || 'interface';
		if (src == 'interface')
			return resolve_ipv4_from_iface(ubus_ctx, rule.ipv4_interface || 'wan', allow_private);
		if (src == 'device')
			return resolve_ip_from_device(rule.ipv4_device || 'eth0', 4, allow_private);
		return resolve_ip_from_urls(global_cfg.ipv4_url, 4, rule.ipv4_bind_dev, allow_private, global_cfg.insecure_tls);
	} else {
		let src = rule.ipv6_source || 'interface';
		if (src == 'interface')
			return resolve_ipv6_from_iface(ubus_ctx, rule.ipv6_interface || 'wan6', allow_private);
		if (src == 'prefix_suffix')
			return resolve_ipv6_prefix_suffix(ubus_ctx, rule.ipv6_interface || 'lan', rule.ipv6_suffix || '::1', allow_private);
		if (src == 'device')
			return resolve_ip_from_device(rule.ipv6_device || 'br-lan', 6, allow_private);
		return resolve_ip_from_urls(global_cfg.ipv6_url, 6, rule.ipv6_bind_dev, allow_private, global_cfg.insecure_tls);
	}
}

/*
 * Normalize domain & subdomain (handling '@', empty string, '*', and accidental suffix duplication)
 */
function normalize_domain_pair(main_raw, sub_raw) {
	let main = lc(trim('' + (main_raw || '')));
	main = replace(main, /^https?:\/\//, '');
	main = rtrim(main, './');

	let sub = lc(trim('' + (sub_raw || '@')));
	sub = rtrim(sub, '.');
	if (sub == '' || sub == main)
		sub = '@';
	else if (length(main) > 0 && length(sub) > length(main) + 1) {
		let suffix = '.' + main;
		if (substr(sub, length(sub) - length(suffix)) == suffix)
			sub = substr(sub, 0, length(sub) - length(suffix));
	}

	let fqdn = (sub == '@') ? main : (sub + '.' + main);
	return { main: main, sub: sub, fqdn: fqdn };
}

function normalize_line(line_raw, endpoint) {
	let line = trim('' + (line_raw || ''));
	if (line == '' || line == '默认' || lc(line) == 'default' || line == '0') {
		return {
			is_default: true,
			name: (endpoint == 'intl') ? 'Default' : '默认',
			id: '0'
		};
	}
	return {
		is_default: false,
		name: line,
		id: null
	};
}

/*
 * Tencent Cloud API 3.0 (dnspod.tencentcloudapi.com / dnspod.intl.tencentcloudapi.com, v2021-03-23)
 */
function tc3_call(creds, action, params, insecure_tls) {
	let host = (creds.endpoint == 'intl')
		? 'dnspod.intl.tencentcloudapi.com'
		: 'dnspod.tencentcloudapi.com';
	let payload = sprintf('%J', params || {});
	let sig = build_tc3_auth(creds.secret_id, creds.secret_key, host, 'dnspod', action, payload);

	let res = http_request({
		url: 'https://' + host + '/',
		method: 'POST',
		insecure_tls: insecure_tls,
		headers: [
			'Authorization: ' + sig.authorization,
			'Content-Type: application/json; charset=utf-8',
			'Host: ' + host,
			'X-TC-Action: ' + action,
			'X-TC-Version: 2021-03-23',
			sprintf('X-TC-Timestamp: %d', sig.timestamp)
		],
		body: payload
	});

	if (!res.ok)
		return { ok: false, error: res.error || 'Network request failed' };

	let parsed = null;
	try {
		parsed = json(res.body);
	} catch (e) {
		return { ok: false, error: 'Invalid JSON response from Tencent Cloud API' };
	}

	let resp = parsed?.Response;
	if (type(resp) != 'object' || resp == null)
		return { ok: false, error: 'Malformed Tencent Cloud API response' };

	if (resp.Error) {
		return {
			ok: false,
			code: resp.Error.Code || 'UnknownError',
			error: sprintf('[%s] %s', resp.Error.Code || 'Error', resp.Error.Message || 'API error'),
			request_id: resp.RequestId
		};
	}

	return { ok: true, data: resp, request_id: resp.RequestId };
}

/*
 * DNSPod Legacy Token API (dnsapi.cn / api.dnspod.com) for backward compatibility
 */
function dnspod_token_call(creds, action, params, insecure_tls) {
	let base = (creds.endpoint == 'intl') ? 'https://api.dnspod.com/' : 'https://dnsapi.cn/';
	let form = [
		'login_token=' + urlencode(creds.secret_id + ',' + creds.secret_key),
		'format=json',
		'error_on_empty=no'
	];
	if (type(params) == 'object') {
		for (let k in keys(params)) {
			if (params[k] != null && params[k] !== '')
				push(form, urlencode(k) + '=' + urlencode('' + params[k]));
		}
	}

	let res = http_request({
		url: base + action,
		method: 'POST',
		insecure_tls: insecure_tls,
		headers: [
			'Content-Type: application/x-www-form-urlencoded; charset=utf-8'
		],
		body: join('&', form)
	});

	if (!res.ok)
		return { ok: false, error: res.error || 'Network request failed' };

	let parsed = null;
	try {
		parsed = json(res.body);
	} catch (e) {
		return { ok: false, error: 'Invalid JSON response from DNSPod API' };
	}

	let code = '' + (parsed?.status?.code ?? '');
	if (code == '1')
		return { ok: true, data: parsed };

	if (action == 'Record.List' && code == '10')
		return { ok: true, data: { records: [] } };

	return {
		ok: false,
		code: code,
		error: sprintf('[Code %s] %s', code || '?', parsed?.status?.message || 'DNSPod API error')
	};
}

function api_list_records(creds, domain, sub, rec_type, line_info, insecure_tls) {
	if (creds.api_type == 'dnspod_token') {
		let p = {
			domain: domain,
			sub_domain: sub,
			record_type: rec_type
		};
		if (line_info.is_default)
			p.record_line_id = '0';
		else
			p.record_line = line_info.name;

		let r = dnspod_token_call(creds, 'Record.List', p, insecure_tls);
		if (!r.ok)
			return r;

		let out = [];
		let recs = r.data?.records;
		if (type(recs) == 'array') {
			for (let item in recs) {
				if (lc('' + item.name) == lc(sub) && uc('' + item.type) == uc(rec_type)) {
					push(out, {
						id: int(item.id),
						value: '' + item.value,
						ttl: to_int(item.ttl, 600),
						line: '' + (item.line || line_info.name),
						line_id: '' + (item.line_id ?? '0'),
						enabled: ('' + item.enabled) != '0'
					});
				}
			}
		}
		return { ok: true, records: out };
	}

	let p = {
		Domain: domain,
		Subdomain: sub,
		SubDomain: sub,
		RecordType: rec_type,
		ErrorOnEmpty: 'no',
		Limit: 100
	};
	if (line_info.is_default)
		p.RecordLineId = '0';
	else
		p.RecordLine = line_info.name;

	let r = tc3_call(creds, 'DescribeRecordList', p, insecure_tls);
	if (!r.ok) {
		if (r.code == 'ResourceNotFound.NoDataOfRecord')
			return { ok: true, records: [] };
		return r;
	}

	let out = [];
	let recs = r.data?.RecordList;
	if (type(recs) == 'array') {
		for (let item in recs) {
			if (lc('' + item.Name) == lc(sub) && uc('' + item.Type) == uc(rec_type)) {
				push(out, {
					id: int(item.RecordId),
					value: '' + item.Value,
					ttl: to_int(item.TTL, 600),
					line: '' + (item.Line || line_info.name),
					line_id: '' + (item.LineId ?? '0'),
					enabled: ('' + item.Status) != 'DISABLE'
				});
			}
		}
	}
	return { ok: true, records: out };
}

function api_create_record(creds, domain, sub, rec_type, line_info, value, ttl, insecure_tls) {
	if (creds.api_type == 'dnspod_token') {
		let p = {
			domain: domain,
			sub_domain: sub,
			record_type: rec_type,
			value: value,
			ttl: ttl
		};
		if (line_info.is_default)
			p.record_line_id = '0';
		else
			p.record_line = line_info.name;

		let r = dnspod_token_call(creds, 'Record.Create', p, insecure_tls);
		if (!r.ok)
			return r;
		return { ok: true, record_id: int(r.data?.record?.id) };
	}

	let p = {
		Domain: domain,
		SubDomain: sub,
		RecordType: rec_type,
		RecordLine: line_info.name,
		Value: value,
		TTL: ttl,
		Status: 'ENABLE'
	};
	if (line_info.is_default)
		p.RecordLineId = '0';

	let r = tc3_call(creds, 'CreateRecord', p, insecure_tls);
	if (!r.ok)
		return r;
	return { ok: true, record_id: int(r.data?.RecordId) };
}

function api_modify_record(creds, domain, sub, record_id, rec_type, line_info, value, ttl, insecure_tls) {
	if (creds.api_type == 'dnspod_token') {
		let p = {
			domain: domain,
			record_id: record_id,
			sub_domain: sub,
			record_type: rec_type,
			value: value,
			ttl: ttl
		};
		if (line_info.is_default)
			p.record_line_id = '0';
		else
			p.record_line = line_info.name;

		let r = dnspod_token_call(creds, 'Record.Modify', p, insecure_tls);
		if (!r.ok)
			return r;
		return { ok: true, record_id: int(r.data?.record?.id || record_id) };
	}

	let p = {
		Domain: domain,
		RecordId: int(record_id),
		SubDomain: sub,
		RecordType: rec_type,
		RecordLine: line_info.name,
		Value: value,
		TTL: ttl,
		Status: 'ENABLE'
	};
	if (line_info.is_default)
		p.RecordLineId = '0';

	let r = tc3_call(creds, 'ModifyRecord', p, insecure_tls);
	if (!r.ok) {
		if (r.code == 'InvalidParameter.DomainRecordExist')
			return { ok: true, record_id: int(record_id), unchanged: true };
		return r;
	}
	return { ok: true, record_id: int(r.data?.RecordId || record_id) };
}

function api_delete_record(creds, domain, record_id, insecure_tls) {
	if (creds.api_type == 'dnspod_token') {
		return dnspod_token_call(creds, 'Record.Remove', {
			domain: domain,
			record_id: record_id
		}, insecure_tls);
	}
	return tc3_call(creds, 'DeleteRecord', {
		Domain: domain,
		RecordId: int(record_id)
	}, insecure_tls);
}

/*
 * Load normalized configuration from /etc/config/tencentddns
 */
function load_config() {
	let uci_ctx = cursor();
	let all = (uci_ctx ? uci_ctx.get_all('tencentddns') : null) || {};

	let g = all.global || {};
	let global_cfg = {
		enabled: to_bool(g.enabled, false),
		api_type: (g.api_type == 'dnspod_token') ? 'dnspod_token' : 'tc3',
		endpoint: (g.endpoint == 'intl') ? 'intl' : 'cn',
		secret_id: trim('' + (g.secret_id || '')),
		secret_key: trim('' + (g.secret_key || '')),
		check_interval: to_int(g.check_interval, 5, 1, 1440),
		force_interval: to_int(g.force_interval, 24, 0, 720),
		retry_interval: to_int(g.retry_interval, 60, 10, 3600),
		log_max_lines: to_int(g.log_max_lines, 500, 50, 5000),
		insecure_tls: to_bool(g.insecure_tls, false),
		ipv4_url: (type(g.ipv4_url) == 'array') ? g.ipv4_url : (g.ipv4_url ? [ g.ipv4_url ] : DEFAULT_IPV4_URLS),
		ipv6_url: (type(g.ipv6_url) == 'array') ? g.ipv6_url : (g.ipv6_url ? [ g.ipv6_url ] : DEFAULT_IPV6_URLS)
	};

	let rules = [];
	if (uci_ctx) {
		uci_ctx.foreach('tencentddns', 'record', function(s) {
			let dm = normalize_domain_pair(s.main_domain, s.sub_domain);
			let use_custom = to_bool(s.use_custom_key, false);
			let endpoint = use_custom ? ((s.endpoint == 'intl') ? 'intl' : 'cn') : global_cfg.endpoint;
			let api_type = use_custom ? ((s.api_type == 'dnspod_token') ? 'dnspod_token' : 'tc3') : global_cfg.api_type;

			push(rules, {
				id: s['.name'],
				enabled: to_bool(s.enabled, true),
				remark: trim('' + (s.remark || '')),
				main_domain: dm.main,
				sub_domain: dm.sub,
				fqdn: dm.fqdn,
				ip_mode: (s.ip_mode == 'ipv6' || s.ip_mode == 'dual') ? s.ip_mode : 'ipv4',
				record_line: trim('' + (s.record_line || '默认')),
				line_info: normalize_line(s.record_line, endpoint),
				ttl: to_int(s.ttl, 600, 1, 604800),
				clean_duplicate: to_bool(s.clean_duplicate, false),
				allow_private_ip: to_bool(s.allow_private_ip, false),
				ipv4_source: s.ipv4_source || 'interface',
				ipv4_interface: s.ipv4_interface || 'wan',
				ipv4_device: s.ipv4_device || '',
				ipv4_bind_dev: s.ipv4_bind_dev || '',
				ipv6_source: s.ipv6_source || 'interface',
				ipv6_interface: s.ipv6_interface || 'wan6',
				ipv6_device: s.ipv6_device || 'br-lan',
				ipv6_suffix: s.ipv6_suffix || '::1',
				ipv6_bind_dev: s.ipv6_bind_dev || '',
				creds: {
					api_type: api_type,
					endpoint: endpoint,
					secret_id: use_custom ? trim('' + (s.secret_id || '')) : global_cfg.secret_id,
					secret_key: use_custom ? trim('' + (s.secret_key || '')) : global_cfg.secret_key
				}
			});
		});
	}

	return { global: global_cfg, rules: rules };
}

function validate_rule_creds(rule) {
	if (!length(rule.main_domain) || index(rule.main_domain, '.') <= 0)
		return 'Invalid main domain (e.g. example.com)';
	if (!length(rule.creds.secret_id) || !length(rule.creds.secret_key))
		return 'Missing API credentials (SecretId / SecretKey)';
	return null;
}

function sync_single_family(ubus_ctx, global_cfg, rule, family, state_entry, force) {
	let rec_type = (family == 4) ? 'A' : 'AAAA';
	let fkey = (family == 4) ? 'ipv4' : 'ipv6';
	let fstate = state_entry[fkey] || {};
	let now = time();

	let ip_res = get_target_ip(ubus_ctx, global_cfg, rule, family);
	if (!ip_res.ip) {
		fstate.status = 'error';
		fstate.last_check = now;
		fstate.error = ip_res.error || sprintf('Failed to obtain IPv%d address', family);
		state_entry[fkey] = fstate;
		write_log('WARN', rule.fqdn, sprintf('%s skipped: %s', rec_type, fstate.error), global_cfg.log_max_lines);
		return { ok: false, error: fstate.error };
	}

	let target_ip = ip_res.ip;
	fstate.local_ip = target_ip;
	fstate.last_check = now;

	let force_due = (global_cfg.force_interval > 0) &&
		(!fstate.last_update || (now - fstate.last_update) >= (global_cfg.force_interval * 3600));

	if (!force && !force_due && !rule.clean_duplicate &&
	    fstate.remote_ip == target_ip && fstate.record_id && fstate.status == 'synced') {
		state_entry[fkey] = fstate;
		return { ok: true, action: 'cached_noop', ip: target_ip };
	}

	let list_res = api_list_records(
		rule.creds, rule.main_domain, rule.sub_domain, rec_type, rule.line_info, global_cfg.insecure_tls
	);
	if (!list_res.ok) {
		fstate.status = 'error';
		fstate.error = list_res.error || 'Failed to query DNS records';
		state_entry[fkey] = fstate;
		write_log('ERROR', rule.fqdn, sprintf('%s query failed: %s', rec_type, fstate.error), global_cfg.log_max_lines);
		return { ok: false, error: fstate.error };
	}

	let records = list_res.records || [];
	let primary = length(records) > 0 ? records[0] : null;

	if (rule.clean_duplicate && length(records) > 1) {
		for (let i = 1; i < length(records); i++) {
			let dup = records[i];
			let del_res = api_delete_record(rule.creds, rule.main_domain, dup.id, global_cfg.insecure_tls);
			if (del_res.ok)
				write_log('INFO', rule.fqdn, sprintf('Removed duplicate %s record ID %d (%s)', rec_type, dup.id, dup.value), global_cfg.log_max_lines);
		}
	}

	if (!primary) {
		let add_res = api_create_record(
			rule.creds, rule.main_domain, rule.sub_domain, rec_type,
			rule.line_info, target_ip, rule.ttl, global_cfg.insecure_tls
		);
		if (!add_res.ok) {
			fstate.status = 'error';
			fstate.error = add_res.error || 'Failed to create DNS record';
			state_entry[fkey] = fstate;
			write_log('ERROR', rule.fqdn, sprintf('%s create failed: %s', rec_type, add_res.error), global_cfg.log_max_lines);
			return { ok: false, error: fstate.error };
		}

		fstate.status = 'synced';
		fstate.remote_ip = target_ip;
		fstate.record_id = add_res.record_id;
		fstate.last_update = now;
		fstate.error = '';
		state_entry[fkey] = fstate;
		write_log('INFO', rule.fqdn, sprintf('Created %s record -> %s (RecordId: %d, Line: %s)', rec_type, target_ip, add_res.record_id, rule.line_info.name), global_cfg.log_max_lines);
		return { ok: true, action: 'created', ip: target_ip, record_id: add_res.record_id };
	}

	if (!force && primary.value == target_ip && primary.enabled) {
		fstate.status = 'synced';
		fstate.remote_ip = primary.value;
		fstate.record_id = primary.id;
		if (!fstate.last_update)
			fstate.last_update = now;
		fstate.error = '';
		state_entry[fkey] = fstate;
		write_log('INFO', rule.fqdn, sprintf('%s already in sync (%s)', rec_type, target_ip), global_cfg.log_max_lines);
		return { ok: true, action: 'noop', ip: target_ip, record_id: primary.id };
	}

	let mod_res = api_modify_record(
		rule.creds, rule.main_domain, rule.sub_domain, primary.id, rec_type,
		rule.line_info, target_ip, rule.ttl, global_cfg.insecure_tls
	);
	if (!mod_res.ok) {
		fstate.status = 'error';
		fstate.remote_ip = primary.value;
		fstate.error = mod_res.error || 'Failed to update DNS record';
		state_entry[fkey] = fstate;
		write_log('ERROR', rule.fqdn, sprintf('%s update failed: %s', rec_type, fstate.error), global_cfg.log_max_lines);
		return { ok: false, error: fstate.error };
	}

	fstate.status = 'synced';
	fstate.remote_ip = target_ip;
	fstate.record_id = mod_res.record_id || primary.id;
	fstate.last_update = now;
	fstate.error = '';
	state_entry[fkey] = fstate;
	write_log('INFO', rule.fqdn, sprintf('Updated %s record %s -> %s (RecordId: %d)', rec_type, primary.value, target_ip, fstate.record_id), global_cfg.log_max_lines);
	return { ok: true, action: 'updated', ip: target_ip, record_id: fstate.record_id };
}

export function sync_rules(opts) {
	let options = opts || {};
	let filter_id = options.section || null;
	let force = !!options.force;

	if (!acquire_lock())
		return { ok: false, locked: true, error: 'Another synchronization task is currently running' };

	let ubus_ctx = null;
	try {
		let cfg = load_config();
		let state = load_state();
		ubus_ctx = ubus.connect();
		let summary = { ok: true, total: 0, succeeded: 0, failed: 0, results: {} };

		for (let rule in cfg.rules) {
			if (filter_id && rule.id != filter_id)
				continue;
			if (!filter_id && !rule.enabled) {
				let prev = assign_obj({}, state.records[rule.id]);
				prev.fqdn = rule.fqdn;
				prev.status = 'disabled';
				state.records[rule.id] = prev;
				continue;
			}

			summary.total++;
			let rstate = assign_obj({}, state.records[rule.id]);
			rstate.fqdn = rule.fqdn;

			let cred_err = validate_rule_creds(rule);
			if (cred_err) {
				rstate.status = 'error';
				rstate.error = cred_err;
				rstate.last_check = time();
				state.records[rule.id] = rstate;
				summary.failed++;
				summary.ok = false;
				summary.results[rule.id] = { ok: false, error: cred_err };
				write_log('ERROR', rule.fqdn || rule.id, cred_err, cfg.global.log_max_lines);
				continue;
			}

			let rule_ok = true;
			let detail = { ok: true };

			if (rule.ip_mode == 'ipv4' || rule.ip_mode == 'dual') {
				let r4 = sync_single_family(ubus_ctx, cfg.global, rule, 4, rstate, force);
				detail.ipv4 = r4;
				if (!r4.ok)
					rule_ok = false;
			} else {
				delete rstate.ipv4;
			}

			if (rule.ip_mode == 'ipv6' || rule.ip_mode == 'dual') {
				let r6 = sync_single_family(ubus_ctx, cfg.global, rule, 6, rstate, force);
				detail.ipv6 = r6;
				if (!r6.ok)
					rule_ok = false;
			} else {
				delete rstate.ipv6;
			}

			detail.ok = rule_ok;
			rstate.status = rule_ok ? 'synced' : 'error';
			rstate.error = rule_ok ? '' : (detail.ipv4?.error || detail.ipv6?.error || 'Sync failed');
			rstate.last_check = time();
			state.records[rule.id] = rstate;
			summary.results[rule.id] = detail;

			if (rule_ok)
				summary.succeeded++;
			else {
				summary.failed++;
				summary.ok = false;
			}
		}

		if (ubus_ctx) {
			ubus_ctx.disconnect();
			ubus_ctx = null;
		}

		save_state(state);
		release_lock();
		return summary;
	} catch (e) {
		if (ubus_ctx)
			ubus_ctx.disconnect();
		release_lock();
		return { ok: false, error: '' + (e?.message || e) };
	}
};

export function test_rule_connectivity(section_id) {
	let cfg = load_config();
	let target = null;
	for (let r in cfg.rules) {
		if (!section_id || r.id == section_id) {
			target = r;
			break;
		}
	}

	if (!target)
		return { ok: false, error: 'Rule not found (please save configuration first)' };

	let cred_err = validate_rule_creds(target);
	if (cred_err)
		return { ok: false, error: cred_err };

	let ubus_ctx = ubus.connect();
	let out = {
		ok: true,
		section: target.id,
		fqdn: target.fqdn,
		api_type: target.creds.api_type,
		endpoint: target.creds.endpoint
	};

	if (target.ip_mode == 'ipv4' || target.ip_mode == 'dual') {
		let ip4 = get_target_ip(ubus_ctx, cfg.global, target, 4);
		let rec4 = api_list_records(target.creds, target.main_domain, target.sub_domain, 'A', target.line_info, cfg.global.insecure_tls);
		out.ipv4 = {
			local_ip: ip4.ip,
			ip_error: ip4.error || null,
			api_ok: rec4.ok,
			api_error: rec4.error || null,
			remote_ip: rec4.records?.[0]?.value || null,
			record_id: rec4.records?.[0]?.id || null
		};
		if (!ip4.ip || !rec4.ok)
			out.ok = false;
	}

	if (target.ip_mode == 'ipv6' || target.ip_mode == 'dual') {
		let ip6 = get_target_ip(ubus_ctx, cfg.global, target, 6);
		let rec6 = api_list_records(target.creds, target.main_domain, target.sub_domain, 'AAAA', target.line_info, cfg.global.insecure_tls);
		out.ipv6 = {
			local_ip: ip6.ip,
			ip_error: ip6.error || null,
			api_ok: rec6.ok,
			api_error: rec6.error || null,
			remote_ip: rec6.records?.[0]?.value || null,
			record_id: rec6.records?.[0]?.id || null
		};
		if (!ip6.ip || !rec6.ok)
			out.ok = false;
	}

	if (ubus_ctx)
		ubus_ctx.disconnect();

	return out;
};

export function get_runtime_status() {
	let cfg = load_config();
	let state = load_state();
	let ubus_ctx = ubus.connect();

	let service_running = false;
	if (ubus_ctx) {
		let svc = ubus_ctx.call('service', 'list', { name: 'tencentddns' });
		let inst = svc?.tencentddns?.instances;
		if (type(inst) == 'object' && inst != null) {
			for (let k in keys(inst)) {
				if (inst[k]?.running) {
					service_running = true;
					break;
				}
			}
		}
		ubus_ctx.disconnect();
	}

	let records = [];
	for (let r in cfg.rules) {
		let st = state.records?.[r.id] || {};
		push(records, {
			id: r.id,
			enabled: r.enabled,
			remark: r.remark,
			fqdn: r.fqdn,
			main_domain: r.main_domain,
			sub_domain: r.sub_domain,
			ip_mode: r.ip_mode,
			record_line: r.record_line,
			ttl: r.ttl,
			api_type: r.creds.api_type,
			status: !r.enabled ? 'disabled' : (st.status || 'pending'),
			error: st.error || '',
			last_check: st.last_check || 0,
			ipv4: st.ipv4 || null,
			ipv6: st.ipv6 || null
		});
	}

	return {
		enabled: cfg.global.enabled,
		service_running: service_running,
		api_type: cfg.global.api_type,
		endpoint: cfg.global.endpoint,
		check_interval: cfg.global.check_interval,
		force_interval: cfg.global.force_interval,
		updated_at: state.updated_at || 0,
		syncing: !!fs.access(LOCK_FILE, 'f'),
		records: records
	};
};

export {
	load_config,
	write_log,
	read_logs,
	clear_logs,
	build_tc3_auth,
	hmac_sha256_hex,
	is_valid_ipv4,
	is_valid_ipv6,
	merge_ipv6_prefix_suffix,
	normalize_domain_pair
};
