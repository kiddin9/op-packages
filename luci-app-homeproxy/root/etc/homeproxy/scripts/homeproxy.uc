/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * Copyright (C) 2023 ImmortalWrt.org
 */

import { mkstemp } from 'fs';
import { urldecode_params } from 'luci.http';

/* Global variables start */
export const HP_DIR = '/etc/homeproxy';
export const RUN_DIR = '/var/run/homeproxy';
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

/* Close a file descriptor, swallowing secondary errors (e.g. an already
   closed fd). ucode has no `finally` clause, so both the normal and the
   exceptional path of executeCommand() have to close explicitly. */
function closeFD(fd) {
	if (fd) {
		try {
			fd.close();
		} catch (e) {
			/* already closed */
		}
	}
};

export function executeCommand(...args) {
	let outfd = null, errfd = null;

	try {
		outfd = mkstemp();
		errfd = mkstemp();

		const exitcode = system(`${join(' ', args)} >&${outfd.fileno()} 2>&${errfd.fileno()}`);

		outfd.seek(0);
		errfd.seek(0);

		const stdout = outfd.read(1024 * 512) ?? '';
		const stderr = errfd.read(1024 * 512) ?? '';

		const binary = isBinary(stdout);

		/* mkstemp() returns delete-on-close files, so closing is enough */
		closeFD(outfd);
		closeFD(errfd);

		return {
			command: join(' ', args),
			stdout: binary ? null : stdout,
			stderr,
			exitcode,
			binary
		};
	} catch (e) {
		/* Never leak the temporary descriptors on a failing run. ucode has
		   no `finally` clause, so the exception is re-raised by hand. */
		closeFD(outfd);
		closeFD(errfd);

		die(e);
	}
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

	/* -nv (not -q) so wget still reports *why* a fetch failed on stderr */
	const output = executeCommand(`/usr/bin/wget -nv -O- --user-agent ${shellQuote(ua)} --timeout=10 ${shellQuote(url)}`) || {};
	if (output.exitcode !== 0) {
		let reason = trim(output.stderr || '');
		reason = reason ? replace(reason, /\s+/g, ' ') : 'no error output';

		if (length(reason) > 200)
			reason = substr(reason, 0, 200) + '...';

		return { content: null, error: `wget exited with status ${output.exitcode}: ${reason}` };
	}

	return { content: trim(output.stdout), error: null };
};

export function wGET(url, ua) {
	return wGETVerbose(url, ua).content;
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
	return !isEmpty(str) ? (int(str) || null) : null;
};

export function strToTime(str) {
	if (isEmpty(str))
		return null;

	/* Preserve values that already carry a time unit (e.g. "30s", "1m") */
	return match(str, /[a-zA-Z]$/) ? str : (str + 's');
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

export function validateHostname(hostname) {
	return (match(hostname, /^[a-zA-Z0-9_]+$/) != null ||
		(match(hostname, /^[a-zA-Z0-9_][a-zA-Z0-9_%-.]*[a-zA-Z0-9]$/) &&
			match(hostname, /[^0-9.]/)));
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

	/* Split address and optional prefix */
	const parts = split(addr, '/');
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
		/* Validate prefix if present */
		if (prefix && (int(prefix) < 0 || int(prefix) > 32))
			return false;
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

		if (prefix && (int(prefix) < 0 || int(prefix) > 128))
			return false;
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
 */
export function buildTLSObject(cfg, is_server) {
	if (cfg.tls !== '1')
		return null;

	return {
		enabled: true,
		server_name: cfg.tls_sni,
		insecure: is_server ? null : strToBool(cfg.tls_insecure),
		alpn: cfg.tls_alpn,
		min_version: cfg.tls_min_version,
		max_version: cfg.tls_max_version,
		handshake_timeout: is_server ? null : strToTime(cfg.tls_handshake_timeout),
		cipher_suites: cfg.tls_cipher_suites,
		certificate_path: cfg.tls_cert_path,
		key_path: is_server ? cfg.tls_key_path : null,
		certificate_provider: (is_server && cfg.tls_acme === '1') ? {
			type: 'acme',
			domain: (type(cfg.tls_acme_domain) === 'array') ? cfg.tls_acme_domain
				: (isEmpty(cfg.tls_acme_domain) ? [] : [cfg.tls_acme_domain]),
			data_directory: HP_DIR + '/certs',
			default_server_name: cfg.tls_acme_dsn,
			email: cfg.tls_acme_email,
			provider: cfg.tls_acme_provider,
			account_key: cfg.tls_acme_account_key,
			key_type: cfg.tls_acme_key_type,
			profile: cfg.tls_acme_profile,
			disable_http_challenge: strToBool(cfg.tls_acme_dhc),
			disable_tls_alpn_challenge: strToBool(cfg.tls_acme_dtac),
			alternative_http_port: strToInt(cfg.tls_acme_ahp),
			alternative_tls_port: strToInt(cfg.tls_acme_atp),
			external_account: (cfg.tls_acme_external_account === '1') ? {
				key_id: cfg.tls_acme_ea_keyid,
				mac_key: cfg.tls_acme_ea_mackey
			} : null,
			dns01_challenge: (cfg.tls_dns01_challenge === '1') ? {
				provider: cfg.tls_dns01_provider,
				access_key_id: cfg.tls_dns01_ali_akid,
				access_key_secret: cfg.tls_dns01_ali_aksec,
				region_id: cfg.tls_dns01_ali_rid,
				api_token: cfg.tls_dns01_cf_api_token
			} : null
		} : null,
		ech: is_server ? (cfg.tls_ech_key ? {
			enabled: true,
			key: split(cfg.tls_ech_key, '\n')
			/* config: split(cfg.tls_ech_config, '\n') */
		} : null) : ((cfg.tls_ech === '1') ? {
			enabled: true,
			config: cfg.tls_ech_config,
			config_path: cfg.tls_ech_config_path
		} : null),
		utls: (is_server || isEmpty(cfg.tls_utls)) ? null : {
			enabled: true,
			fingerprint: cfg.tls_utls
		},
		reality: (cfg.tls_reality !== '1') ? null : (is_server ? {
			enabled: true,
			private_key: cfg.tls_reality_private_key,
			short_id: cfg.tls_reality_short_id,
			max_time_difference: strToTime(cfg.tls_reality_max_time_difference),
			handshake: {
				server: cfg.tls_reality_server_addr,
				server_port: strToInt(cfg.tls_reality_server_port)
			}
		} : {
			enabled: true,
			public_key: cfg.tls_reality_public_key,
			short_id: cfg.tls_reality_short_id
		})
	};
};

/* Shared sing-box transport object builder; the client transport additionally
   supports the gRPC keepalive hint, the server one does not. */
export function buildTransportObject(cfg, is_server) {
	if (isEmpty(cfg.transport))
		return null;

	return {
		type: cfg.transport,
		host: cfg.http_host || cfg.httpupgrade_host,
		path: cfg.http_path || cfg.ws_path,
		headers: cfg.ws_host ? {
			Host: cfg.ws_host
		} : null,
		method: cfg.http_method,
		max_early_data: strToInt(cfg.websocket_early_data),
		early_data_header_name: cfg.websocket_early_data_header,
		service_name: cfg.grpc_servicename,
		idle_timeout: strToTime(cfg.http_idle_timeout),
		ping_timeout: strToTime(cfg.http_ping_timeout),
		permit_without_stream: is_server ? null : strToBool(cfg.grpc_permit_without_stream)
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
export function isValidPEM(content, is_private_key) {
	if (isEmpty(content))
		return false;

	const beg = is_private_key ? /^-----BEGIN (RSA|EC) PRIVATE KEY-----$/ : /^-----BEGIN CERTIFICATE-----$/,
	      end = is_private_key ? /^-----END (RSA|EC) PRIVATE KEY-----$/ : /^-----END CERTIFICATE-----$/,
	      lines = split(trim(content), /[\r\n]/);
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
/* PEM validation end */
