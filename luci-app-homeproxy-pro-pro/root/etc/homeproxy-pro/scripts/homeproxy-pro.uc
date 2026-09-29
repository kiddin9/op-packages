/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * Copyright (C) 2023 ImmortalWrt.org
 */

import { access, lstat, mkdtemp, open, rmdir, unlink } from 'fs';
import { urldecode_params } from 'luci.http';

/* Global variables start */
export const HP_DIR = '/etc/homeproxy';
export const RUN_DIR = '/var/run/homeproxy';
/* Where the UCI configuration lives. This is /etc/config - NOT HP_DIR/config.
 * The package ships its config as the conffile /etc/config/homeproxy, and
 * ucode's `cursor(dir)` treats `dir` as the *confdir*, so
 * cursor(HP_DIR + '/config') would read /etc/homeproxy/config/homeproxy, a
 * path that exists nowhere.  uci.load() then returns null, every uci.get()
 * returns null, and the Loader silently yields pure defaults: no main-out,
 * no route/direct final, none of the user's ports or nodes.
 * Verified on a device: cursor('/etc/homeproxy/config').get(...) is empty
 * while cursor().get(...) returns the configured value.
 * The test suite stages a rewritten copy of this constant instead of the
 * old `__LOADER_DIR__` source sed. */
export const UCICONFIG_DIR = '/etc/config';
/* Largest subscription body we will fetch, in bytes. See wGETVerbose(). */
export const HP_FETCH_CAP = 5 * 1024 * 1024;
/* Global variables end */

/* Utilities start */
/* Kanged from luci-app-commands */
export function shellQuote(s) {
	return `'${replace(s, "'", "'\\''")}'`;
};

export function isBinary(str) {
	for (let off = 0, byte = ord(str); off < length(str); byte = ord(str, ++off))
		if (byte <= 8 || (byte >= 14 && byte <= 31))
			return true;

	return false;
};

/* Whitelist absolute paths the generators are allowed to put into
 * sing-box config. sing-box runs as root and reads the file itself; an
 * arbitrary UCI value of e.g. /etc/passwd would leak the file to anyone
 * who could write to the UCI tree. The LuCI UI already gates the input
 * via validateCertificatePath() in homeproxy.js, but UCI can be set from
 * any node on the LAN (subscription updates, scripted edits) and the
 * UI check is only UX - we have to enforce on the backend.
 *
 *   /etc/homeproxy/...   - project-managed certs / ruleset paths / etc.
 *   /tmp/homeproxy_*     - upload staging files (cert_upload_* writes)
 *
 * Anything else (relative paths, /etc/passwd, /var/run/...) returns false
 * and the caller is expected to die() / warn() / strip the value. */
export function validateHomeProxyPath(p) {
	if (!p || type(p) !== 'string')
		return false;

	/* Reject traversal *before* the prefix checks below: a plain prefix
	 * comparison accepts '/etc/homeproxy/../../etc/shadow', and sing-box reads
	 * these paths as root. */
	if (match(p, /(^|\/)\.\.(\/|$)/))
		return false;

	/* Reject anything that does not start with '/' - relative paths in
	 * sing-box resolve against the process CWD, which is /tmp at boot
	 * but is not a position we want any UCI value to land in. */
	if (substr(p, 0, 1) !== '/')
		return false;

	if (substr(p, 0, length('/etc/homeproxy/')) === '/etc/homeproxy/')
		return true;

	if (substr(p, 0, length('/tmp/homeproxy_')) === '/tmp/homeproxy_')
		return true;

	return false;
};

/* Certificates the sing-box instances are allowed to read.
 *
 * TLS certificate_path / key_path are not rule-set paths: a server's
 * certificate normally lives under /etc/ssl/ or under the ACME state in
 * /etc/acme/, and the two sing-box jails mount exactly those directories
 * (see runtime/service.sh's procd_add_jail_mount calls). validateHomeProxyPath()
 * only knows /etc/homeproxy/ and /tmp/homeproxy_, so a certificate the user
 * legitimately picked from /etc/ssl/ was accepted by the LuCI validator and
 * then silently dropped here - certificate_path became null and the TLS
 * listener failed with no error pointing at the path.
 *
 * The list is mirrored by HP_CERT_PATH_ROOTS in
 * htdocs/luci-static/resources/homeproxy.js; guard 29 in tests/arch-guard.sh
 * keeps the two in step.
 */
export const CERT_PATH_ROOTS = ['/etc/homeproxy/certs/', '/etc/acme/', '/etc/ssl/'];

/* validateCertificatePath(p) - the TLS certificate/key path gate.
 *
 * Same shape as validateHomeProxyPath(): reject traversal and relative paths,
 * then require one of CERT_PATH_ROOTS. Kept separate rather than folded into
 * validateHomeProxyPath() so a rule-set path cannot be pointed at /etc/ssl/
 * and a certificate cannot be pointed at /tmp/homeproxy_*. */
export function validateCertificatePath(p) {
	if (!p || type(p) !== 'string')
		return false;

	if (match(p, /(^|\/)\.\.(\/|$)/))
		return false;

	if (substr(p, 0, 1) !== '/')
		return false;

	for (let root in CERT_PATH_ROOTS)
		if (length(p) > length(root) && substr(p, 0, length(root)) === root)
			return true;

	return false;
};

/* Read at most `limit` bytes from a file, or '' when it does not exist.
 * The cap is deliberate: a command's output is not trustworthy input. */
function read_capped(path, limit) {
	const f = open(path);

	if (!f)
		return '';

	const data = f.read(limit) ?? '';
	f.close();
	return data;
};

/* Remove the scratch files and the directory created for one run. Best
 * effort: a command the shell could not even parse leaves no files behind,
 * and a failed cleanup must never mask the command's own result. */
function cleanup_exec_dir(dir, outpath, errpath) {
	try {
		if (access(outpath))
			unlink(outpath);
		if (access(errpath))
			unlink(errpath);
		rmdir(dir);
	} catch (e) {
		/* nothing useful to do - the results are already captured */
	}
};

export function executeCommand(...args) {
	const command = join(' ', args);
	const dir = mkdtemp();
	const outpath = dir + '/stdout';
	const errpath = dir + '/stderr';

	let exitcode = null, stdout = '', stderr = '';

	try {
		/* Redirect to real paths, not to the descriptors of two mkstemp()
		 * files. The old form appended `>&N 2>&N`, which only works when
		 * the child shell can see those descriptors; /bin/sh reports
		 * "Bad file descriptor" (bash) / "Bad fd number" (dash) when it
		 * cannot, so the command was never executed and every caller got
		 * an empty result with exit status 2. That is what happened in
		 * CI, where /bin/sh is dash. Redirecting to paths is plain POSIX
		 * and behaves identically under busybox ash, dash and bash. */
		exitcode = system(sprintf('%s >%s 2>%s', command, outpath, errpath));

		/* The reader has to be able to return one byte more than
		 * HP_FETCH_CAP, or wGETVerbose()'s "response exceeds the limit"
		 * branch below is unreachable: the reader used to stop at 512 KiB,
		 * so every subscription between 512 KiB and 5 MiB was handed to the
		 * parser as a truncated body with error: null - the size check
		 * could never fire and the caller had no way to tell.  stderr keeps
		 * the smaller cap: it is a diagnostic message, not a payload. The
		 * stderr_truncated flag on the result tells the caller the cap
		 * actually fired, so a "reload exited with status N" line is not
		 * the only signal that something went wrong upstream. */
		stdout = read_capped(outpath, HP_FETCH_CAP + 1);
		stderr = read_capped(errpath, 1024 * 512);
	} catch (e) {
		/* Never leave the scratch directory behind on a failing run.
		 * ucode has no `finally` clause, so the exception is re-raised
		 * by hand. */
		cleanup_exec_dir(dir, outpath, errpath);

		die(e);
	}

	const binary = isBinary(stdout);

	/* Did stderr actually overflow the 512 KiB cap?  The temp file is
	 * unlinked right after this, so size is read while it still exists.
	 * lstat() returns null on missing files, so the .size fallback is
	 * defensive against an exception-driven early cleanup. */
	const stderr_size = (lstat(errpath) || {}).size || 0;
	const stderr_truncated = stderr_size > 1024 * 512;

	cleanup_exec_dir(dir, outpath, errpath);

	return {
		command,
		stdout: binary ? null : stdout,
		stderr,
		stderr_truncated,
		exitcode,
		binary
	};
};

export function getTime(epoch) {
	const local_time = localtime(epoch);
	return replace(replace(sprintf(
		'%d-%2d-%2d@%2d:%2d:%2d',
		local_time.year,
		local_time.mon,
		local_time.mday,
		local_time.hour,
		local_time.min,
		local_time.sec
	), ' ', '0'), '@', ' ');

};

/* Redact the credential-bearing parts of a URL before logging it. Any
 * subscription URL we ship into /var/run/homeproxy/homeproxy.log is
 * readable by anyone who can read /var/run/homeproxy - including UCI
 * defaults that ship on the device and anyone with shell on the LAN.
 * (Confirmed on the device: the log is 0644.)
 *
 * Only the scheme, host and port are kept - enough to answer "which
 * provider/endpoint failed?". The userinfo, the path and the query string
 * all carry subscription tokens in practice: many providers hand out
 * `https://host:port/<user>/<token>` with no query string at all, which is
 * exactly what the device this was found on was configured with, and the
 * path used to survive the redaction. The original URL is still passed to
 * wGETVerbose.
 *
 *   https://user:token@host.example.com/path/sub?q=abc&token=secret
 *     -> https://***@host.example.com/***?*** */
export function redactUrl(url) {
	if (!url || type(url) !== 'string')
		return '';

	let u = url;

	/* userinfo: scheme://user:pass@host -> scheme://***@host */
	const at = index(u, '@');
	const scheme = match(u, /^[a-zA-Z][a-zA-Z0-9+.-]*:\/\//);
	if (scheme && at !== -1 && at > length(scheme[0]))
		u = substr(u, 0, length(scheme[0])) + '***' + substr(u, at);

	/* path and query: keep the authority, mark the rest.  Splitting them
	 * rather than masking from the first '/' keeps the structural markers
	 * (`/***?***`) so a reader can still tell a path from a query, and it is
	 * why the authority end is the *earlier* of the two separators. */
	const scheme_end = scheme ? length(scheme[0]) : 0;
	const rest = substr(u, scheme_end);
	const path_at = index(rest, '/');
	const query_at = index(rest, '?');
	const has_path = path_at !== -1 && (query_at === -1 || path_at < query_at);

	let authority_end = length(rest);
	if (has_path)
		authority_end = path_at;
	else if (query_at !== -1)
		authority_end = query_at;

	let tail = '';
	if (has_path)
		tail += '/***';
	if (query_at !== -1)
		tail += '?***';

	u = substr(u, 0, scheme_end + authority_end) + tail;

	return u;
};

/* Scan a free-form error string and redact every URL in it.  GNU wget's
 * stderr writes the requested URL back into the message:
 *
 *   https://host/path?q=token=secret: Bad port '80080'.
 *
 * The trailing `:` separator is greedy-matched here, which is harmless -
 * redactUrl leaves it as-is.  Doing this here, in wGETVerbose, means the
 * returned `error` is safe no matter where the caller ships it - the
 * fetcher logs it, the orchestrator returns it, anything that prints it
 * afterwards has already lost the token.  Centralising the redaction at
 * the source is the point: every call site used to have to
 * remember to redact, and the one that forgot was the original bug.
 *
 * A non-string input is returned unchanged so this is safe to apply to
 * the trimmed wget stderr even when it is empty.
 *
 * Both definitions sit above wGETVerbose on purpose: ucode does not hoist
 * `export function`, so a call compiled before the declaration is bound
 * fails at runtime with "access to undeclared variable". */
export function redactReason(reason) {
	if (!reason || type(reason) !== 'string')
		return reason;

	return replace(reason, /https?:\/\/\S+/g, (url) => redactUrl(url));
};

/*
 * Fetch a URL and report both the body and, on failure, the reason. The
 * reason is wget's own stderr (whitespace collapsed, length-capped) so the
 * caller can tell a DNS failure from a timeout or a TLS handshake error.
 */
export function wGETVerbose(url, ua) {
	if (!url || type(url) !== 'string')
		return { content: null, error: 'invalid URL' };

	if (!ua)
		ua = 'Wget/1.21 (HomeProxy, like v2rayN)';

	/* -nv (not -q) so wget still reports *why* a fetch failed on stderr.
	 *
	 * The size cap is enforced by piping through `head -c`, NOT with wget's
	 * --max-filesize: that option does not exist in busybox wget (the target's
	 * /usr/bin/wget), which exits 2 with "unrecognized option" before making a
	 * single request - so every subscription fetch failed. GNU wget has no
	 * such option either. `head` closing the pipe stops wget early, which
	 * bounds the download; the cap is therefore CAP+1 bytes rather than
	 * exactly CAP, and one byte past the limit means "too large".
	 *
	 * 5 MiB covers a 10 000-node subscription with ~3 KB per node plus the
	 * base64 inflation. Anything larger is almost certainly an attack or a
	 * misconfiguration.
	 *
	 * The pipeline does cost the exit status: `system()` returns head's, which
	 * is always 0. A wget failure therefore arrives as an empty body plus
	 * wget's own message on stderr, and that is reported below. */
	/* The braces matter: executeCommand() appends `>out 2>err` to the command,
	 * and in `a | b >out 2>err` those redirections bind to b only - wget's
	 * stderr would go to the caller's terminal and the failure message would
	 * be lost.  Grouping the pipeline makes both stream to the capture files. */
	const output = executeCommand(`{ /usr/bin/wget -nv -O- --user-agent ${shellQuote(ua)} --timeout=10 ${shellQuote(url)} | head -c ${HP_FETCH_CAP + 1}; }`) || {};
	let reason = trim(output.stderr || '');
	reason = reason ? replace(reason, /\s+/g, ' ') : '';
	/* Review H3: an HTTP-level wget failure echoes the full URL - query
	 * string and subscription token included - as in
	 * `https://host/path?token=secret: 404 Not Found`.  (A pure connection
	 * failure prints only `failed: Connection refused.` and leaks nothing,
	 * but the 404/403 case is enough.)  Redact at the source so every caller
	 * of wGETVerbose gets a safe `error` whether or not it remembers to call
	 * redactUrl itself. */
	if (reason)
		reason = redactReason(reason);

	if (length(output.stdout || '') > HP_FETCH_CAP)
		return { content: null, error: `response exceeds the ${HP_FETCH_CAP} byte limit` };

	if (output.exitcode !== 0) {
		if (length(reason) > 200)
			reason = substr(reason, 0, 200) + '...';

		return { content: null, error: `wget exited with status ${output.exitcode}: ${reason || 'no error output'}` };
	}

	/* head() masks wget's status, so a failed fetch shows up here instead. */
	if (!length(trim(output.stdout)) && reason) {
		if (length(reason) > 200)
			reason = substr(reason, 0, 200) + '...';

		return { content: null, error: `wget failed: ${reason}` };
	}

	return { content: trim(output.stdout), error: null };
};

/* Utilities end */

/* String helper start */
export function isEmpty(res) {
	return !res || res === 'nil' || (type(res) in ['array', 'object'] && length(res) === 0);
};

export function strToBool(str) {
	return str === '1' ? true : (str === '0' ? false : null);
};

export function strToInt(str) {
	/* Zero reads back as "not set" on purpose: several sing-box fields mean
	 * "omit me" at zero - a vmess user's alterId, for instance - and the
	 * generators depend on removeBlankAttrs() dropping the null this produces.
	 * A review flagged it as "a legitimate 0 becomes null"; the golden outbound
	 * snapshot and the vmess alterId assertion both say otherwise. */
	return !isEmpty(str) ? (int(str) || null) : null;
};

export function strToTime(str) {
	if (isEmpty(str))
		return null;

	/* Preserve values that already carry a time unit (e.g. "30s", "1m") */
	return match(str, /[a-zA-Z]$/) ? str : (str + 's');
};

/* Turn a UCI list of port strings into the int array sing-box wants
 * (e.g. the WireGuard `reserved` list, a routing rule's `port` /
 * `source_port`). Returns null for anything that is not a non-empty
 * array, so a caller can let removeBlankAttrs() drop the field.
 *
 * Lives here rather than in generator/common.uc because the Adapter
 * layer needs it too (EndpointFactory builds the WireGuard endpoint)
 * and an adapter must not import from generator/. */
export function parse_port(strport) {
	if (type(strport) !== 'array' || isEmpty(strport))
		return null;

	let ports = [];
	for (let i in strport) {
		/* Only a bare decimal is a port: int() truncates, so '80-90' used to
		 * become 80 and '443/tcp' become 443, silently widening the rule
		 * instead of dropping the malformed entry. */
		if (match(i, /^[0-9]+$/) && int(i) >= 1 && int(i) <= 65535)
			push(ports, int(i));
	}

	return ports;
};

export function removeBlankAttrs(res) {
	let content;

	if (type(res) === 'object') {
		content = {};
		map(keys(res), (k) => {
			if (type(res[k]) in ['array', 'object'])
				content[k] = removeBlankAttrs(res[k]);
			else if (res[k] !== null && res[k] !== '')
				content[k] = res[k];
		});
	} else if (type(res) === 'array') {
		content = [];
		map(res, (k, i) => {
			if (type(k) in ['array', 'object'])
				push(content, removeBlankAttrs(k));
			else if (k !== null && k !== '')
				push(content, k);
		});
	} else
		return res;

	return content;
};

export function validation(datatype, data) {
	if (!datatype || !data)
		return null;

	const ret = system(`/sbin/validate_data ${shellQuote(datatype)} ${shellQuote(data)} 2>/dev/null`);
	return (ret === 0);
};

/* Validate IP/CIDR format to prevent nftables template injection from resource files */
export function isValidCIDR(addr, family) {
	if (isEmpty(addr))
		return false;

	/* Strip leading/trailing whitespace */
	addr = trim(addr);
	if (!addr)
		return false;

	/* Split address and optional prefix. Reject a second '/' outright:
	 * the only legal form is "ip" or "ip/prefix", and a resource-list
	 * entry like "1.2.3.4/24/32" or "1.2.3.4/;}" would otherwise split
	 * into a benign-looking ip and a prefix the next checks would then
	 * have to defend.  Drop it here so all the following regexes only have
	 * to police a one-or-zero-slash input. */
	const parts = split(addr, '/');
	if (length(parts) > 2)
		return false;
	const ip = parts[0];
	const prefix = parts[1];

	/* Validate IP part */
	if (family === 4) {
		if (!match(ip, /^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/))
			return false;
		/* Validate octet ranges */
		const octets = split(ip, '.');
		for (let o in octets)
			if (int(o) > 255)
				return false;
		/* Validate prefix if present.  Anchor with a digit-only regex:
		 * without it, `int(prefix)` happily parses `24;}` as 24 (strtoll
		 * stops at the first non-digit), so a poisoned china_ip4.txt line
		 * `1.2.3.4/24;}` sailed past this check and ended up verbatim
		 * in the fw4 ruleset fw4 then loaded as root.
		 *
		 * ucode has no `undefined` (an absent index reads as null), and
		 * `if (prefix)` is also false for the empty string, so a
		 * trailing-slash entry like `1.2.3.4/` would slip past a plain
		 * `if (prefix)` gate and pass overall.  Gate on null, which
		 * keeps `''` from sneaking in; the regex naturally rejects the
		 * empty string and any non-digit. */
		if (prefix !== null) {
			if (!match(prefix, /^\d{1,3}$/) || int(prefix) > 32)
				return false;
		}
	} else if (family === 6) {
		/* Only hex digits and colons */
		if (!match(ip, /^[0-9a-fA-F:]+$/))
			return false;

		/* At most one "::" */
		if (match(ip, /::.*::/))
			return false;

		/* Validate group structure */
		const dcolon = index(ip, '::');
		if (dcolon === -1) {
			/* Uncompressed form: exactly 8 groups of 1-4 hex digits */
			const groups = split(ip, ':');
			if (length(groups) !== 8)
				return false;
			for (let g in groups)
				if (!match(g, /^[0-9a-fA-F]{1,4}$/))
					return false;
		} else {
			/* Compressed form: "::" expands to at least one zero group */
			let count = 0;
			for (let part in [substr(ip, 0, dcolon), substr(ip, dcolon + 2)]) {
				if (part === '')
					continue;
				for (let g in split(part, ':')) {
					if (!match(g, /^[0-9a-fA-F]{1,4}$/))
						return false;
					count++;
				}
			}
			if (count > 7)
				return false;
		}

		/* Same anchor as the IPv4 branch: `1.2.3.4/24;}` would let
		 * `int('24;}')` slip through unanchored and end up in fw4.  Same
		 * null-presence guard for `::1/` (empty prefix). */
		if (prefix !== null) {
			if (!match(prefix, /^\d{1,3}$/) || int(prefix) > 128)
				return false;
		}
	} else {
		return false;
	}

	return true;
};
/* String helper end */

/* String parser start */
export function decodeBase64Str(str) {
	if (isEmpty(str))
		return null;

	str = trim(str);
	str = replace(str, /_/g, '/');
	str = replace(str, /-/g, '+');

	const padding = length(str) % 4;
	if (padding)
		str = str + substr('====', padding);

	return b64dec(str);
};

export function parseURL(url) {
	if (type(url) !== 'string')
		return null;

	const services = {
		http: '80',
		https: '443'
	};

	const objurl = {};

	objurl.href = url;

	url = replace(url, /#(.+)$/, (_, val) => {
		objurl.hash = val;
		return '';
	});

	url = replace(url, /^(\w[A-Za-z0-9\+\-\.]+):/, (_, val) => {
		objurl.protocol = val;
		return '';
	});

	url = replace(url, /\?(.+)/, (_, val) => {
		objurl.search = val;
		objurl.searchParams = urldecode_params(val);
		return '';
	});

	url = replace(url, /^\/\/([^\/]+)/, (_, val) => {
		val = replace(val, /^([^@]+)@/, (_, val) => {
			objurl.userinfo = val;
			return '';
		});

		val = replace(val, /:(\d+)$/, (_, val) => {
			objurl.port = val;
			return '';
		});

		if (validation('ip4addr', val) ||
		    validation('ip6addr', replace(val, /\[|\]/g, '')) ||
		    validation('hostname', val))
			objurl.hostname = val;

		return '';
	});

	objurl.pathname = url || '/';

	if (!objurl.protocol || !objurl.hostname)
		return null;

	if (objurl.userinfo) {
		objurl.userinfo = replace(objurl.userinfo, /:(.+)$/, (_, val) => {
			objurl.password = val;
			return '';
		});

		if (match(objurl.userinfo, /^[A-Za-z0-9\+\-\_\.]+$/)) {
			objurl.username = objurl.userinfo;
			delete objurl.userinfo;
		} else {
			delete objurl.userinfo;
			delete objurl.password;
		}
	};

	if (!objurl.port)
		objurl.port = services[objurl.protocol];

	objurl.host = objurl.hostname + (objurl.port ? `:${objurl.port}` : '');
	objurl.origin = `${objurl.protocol}://${objurl.host}`;

	return objurl;
};
/* String parser end */

/* Config generator helper start */
/*
 * Shared sing-box TLS object builder for the client outbound and the server
 * inbound. The property order below is significant: the generated JSON keeps
 * the insertion order of this object after removeBlankAttrs() drops the blank
 * attributes, and both generators used to emit the fields in exactly this
 * order. Keep client-only fields (insecure/handshake_timeout/utls) and
 * server-only fields (key_path/certificate_provider) at their current
 * positions when editing.
 *
 * P1-B: the first arg is now a Node.tls-shape structured sub-object
 * (the same shape the Loader produces) rather than a flat UCI section.
 * The Adapter passes node.tls; the server generator builds a
 * structured view of its UCI inbound before calling. Server-only
 * fields (key material, ACME, server-side reality handshake) still
 * live on the flat UCI section - they are not part of the Node model
 * because no client outbound needs them - so the server passes them
 * through `server_extras` instead of expecting the structured tls
 * to carry them.
 */
export function buildTLSObject(tls, is_server, server_extras) {
	if ((tls && tls.enabled) !== '1')
		return null;

	/* When is_server the caller hands a flat UCI section's server-only
	 * tail. We accept either an object or null; null means "no server
	 * extras" which only matters when the caller still wants a TLS
	 * object built for an inbound that does not actually serve TLS
	 * itself (the enabled check above returns null first in that case). */
	const extras = is_server ? (server_extras || {}) : {};

	return {
		enabled: true,
		server_name: tls.server_name,
		insecure: is_server ? null : strToBool(tls.insecure),
		alpn: tls.alpn,
		min_version: tls.min_version,
		max_version: tls.max_version,
		handshake_timeout: is_server ? null : strToTime(tls.handshake_timeout),
		cipher_suites: tls.cipher_suites,
		certificate_path: tls.cert_path && validateCertificatePath(tls.cert_path) ? tls.cert_path : null,
		key_path: (is_server && extras.tls_key_path && validateCertificatePath(extras.tls_key_path)) ? extras.tls_key_path : null,
		certificate_provider: (is_server && extras.tls_acme === '1') ? {
			type: 'acme',
			domain: (type(extras.tls_acme_domain) === 'array') ? extras.tls_acme_domain
				: (isEmpty(extras.tls_acme_domain) ? [] : [extras.tls_acme_domain]),
			data_directory: HP_DIR + '/certs',
			default_server_name: extras.tls_acme_dsn,
			email: extras.tls_acme_email,
			provider: extras.tls_acme_provider,
			account_key: extras.tls_acme_account_key,
			key_type: extras.tls_acme_key_type,
			profile: extras.tls_acme_profile,
			disable_http_challenge: strToBool(extras.tls_acme_dhc),
			disable_tls_alpn_challenge: strToBool(extras.tls_acme_dtac),
			alternative_http_port: strToInt(extras.tls_acme_ahp),
			alternative_tls_port: strToInt(extras.tls_acme_atp),
			external_account: (extras.tls_acme_external_account === '1') ? {
				key_id: extras.tls_acme_ea_keyid,
				mac_key: extras.tls_acme_ea_mackey
			} : null,
			dns01_challenge: (extras.tls_dns01_challenge === '1') ? {
				provider: extras.tls_dns01_provider,
				access_key_id: extras.tls_dns01_ali_akid,
				access_key_secret: extras.tls_dns01_ali_aksec,
				region_id: extras.tls_dns01_ali_rid,
				api_token: extras.tls_dns01_cf_api_token
			} : null
		} : null,
		ech: is_server ? (extras.tls_ech_key ? {
			enabled: true,
			key: split(extras.tls_ech_key, '\n')
			/* config: split(extras.tls_ech_config, '\n') */
		} : null) : ((tls.ech && tls.ech.enabled === '1') ? {
			enabled: true,
			config: tls.ech.config,
			/* Same gate as certificate_path: this is a file sing-box opens as
			 * root, and it used to reach the config unvalidated. */
			config_path: tls.ech.config_path && validateCertificatePath(tls.ech.config_path) ? tls.ech.config_path : null
		} : null),
		utls: (is_server || isEmpty(tls.utls && tls.utls.fingerprint)) ? null : {
			enabled: true,
			fingerprint: tls.utls.fingerprint
		},
		reality: ((tls.reality && tls.reality.enabled) !== '1') ? null : (is_server ? {
			enabled: true,
			private_key: extras.tls_reality_private_key,
			short_id: tls.reality.short_id,
			max_time_difference: strToTime(extras.tls_reality_max_time_difference),
			handshake: {
				server: extras.tls_reality_server_addr,
				server_port: strToInt(extras.tls_reality_server_port)
			}
		} : {
			enabled: true,
			public_key: tls.reality.public_key,
			short_id: tls.reality.short_id
		})
	};
};

/* Shared sing-box transport object builder; the client transport additionally
   supports the gRPC keepalive hint, the server one does not.
   P1-B: the first arg is now a Node.transport-shape structured sub-object. */
export function buildTransportObject(transport, is_server) {
	if (isEmpty(transport && transport.type))
		return null;

	return {
		type: transport.type,
		host: transport.host,
		path: transport.path,
		headers: transport.headers,
		method: transport.method,
		max_early_data: strToInt(transport.max_early_data),
		early_data_header_name: transport.early_data_header_name,
		service_name: transport.service_name,
		idle_timeout: strToTime(transport.idle_timeout),
		ping_timeout: strToTime(transport.ping_timeout),
		permit_without_stream: is_server ? null : strToBool(transport.permit_without_stream)
	};
};
/* Config generator helper end */

/* PEM validation start */
/*
 * Check that `content` is a PEM certificate (is_private_key = false) or an
 * RSA/EC private key (is_private_key = true): matching BEGIN/END boundaries
 * with a base64 body in between. Kanged from luci-proto-openconnect; used by
 * the rpcd certificate upload and available for future certificate features.
 */
/* Shared by the certificate, private-key and ECH-config validators: only the
 * markers differ, the body rule does not (base64 lines - or a single 64
 * character line - between a BEGIN and an END marker). */
function validatePEM(content, beg, end) {
	if (isEmpty(content))
		return false;

	const lines = split(trim(content), /[\r\n]/);
	let start = false, i;

	for (i = 0; i < length(lines); i++) {
		if (match(lines[i], beg))
			start = true;
		else if (start && !b64dec(lines[i]) && length(lines[i]) !== 64)
			break;
	}

	if (!start || i < length(lines) - 1 || !match(lines[i], end))
		return false;

	return true;
};

export function isValidPEM(content, is_private_key) {
	const beg = is_private_key ? /^-----BEGIN (RSA|EC) PRIVATE KEY-----$/ : /^-----BEGIN CERTIFICATE-----$/,
	      end = is_private_key ? /^-----END (RSA|EC) PRIVATE KEY-----$/ : /^-----END CERTIFICATE-----$/;

	return validatePEM(content, beg, end);
};

/* A client ECH config list is neither a certificate nor a private key - it is
 * wrapped in its own markers ("-----BEGIN ECH CONFIGS-----"), so isValidPEM()
 * rejects it.  The node form's "Upload ECH config" button has always sent
 * certificate_write('client_ech_conf'); the backend had no case for that name,
 * and would have rejected the body here even with one. */
export function isValidECHConfig(content) {
	return validatePEM(content,
		/^-----BEGIN ECH CONFIGS-----$/,
		/^-----END ECH CONFIGS-----$/);
};
/* PEM validation end */
