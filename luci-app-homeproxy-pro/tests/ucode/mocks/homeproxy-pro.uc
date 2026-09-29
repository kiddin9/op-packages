/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * Copyright (C) 2025 ImmortalWrt.org
 *
 * Test double for root/etc/homeproxy-pro/scripts/homeproxy-pro.uc.
 *
 * Only `validation()` is stubbed: the real one shells out to
 * /sbin/validate_data, which does not exist outside OpenWrt. That stand-in
 * reproduces the `libvalidate` decisions for the five datatypes the callers
 * actually use - see the comment on validation() below for the contract and
 * the known differences. Everything else (isEmpty, decodeBase64Str, parseURL,
 * shellQuote, redactUrl) is a verbatim copy so the parser tests exercise the
 * same string handling as production. Keep these in sync when homeproxy-pro.uc
 * changes; tests/ucode/test_mock_sync.sh enforces that for everything except
 * validation().
 */

import { urldecode_params } from 'luci.http';

/* Verbatim copy of homeproxy-pro.uc:shellQuote - migrate_config.uc imports it to
 * build the crontab rewrite, so it has to exist here too. Compared against
 * production by tests/ucode/test_mock_sync.sh. */
export function shellQuote(s) {
	return `'${replace(s, "'", "'\\''")}'`;
};

export function isEmpty(res) {
	return !res || res === 'nil' || (type(res) in ['array', 'object'] && length(res) === 0);
};

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

/* Verbatim copy of homeproxy-pro.uc:redactUrl - decoder.uc imports it so the
 * subscription token stays out of the parse-failed log line. */
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

/* inet_pton(AF_INET, ...): four decimal octets, 0-255, no leading zeros.
 * A helper rather than a call through validation(), because ucode resolves
 * module names lexically and validation() is declared below these. */
function isValidIp4(data) {
	if (match(data, /^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$/) === null)
		return false;
	for (let octet in split(data, '.'))
		if (int(octet) > 255 || (length(octet) > 1 && substr(octet, 0, 1) === '0'))
			return false;
	return true;
};

/* inet_pton(AF_INET6, ...) for the textual forms a share link can carry:
 * at most one "::", 1-4 hex digits per group, exactly eight groups unless
 * "::" fills the gap, and an optional dotted-quad tail (the last 32 bits)
 * that counts as two groups. A "%zone" suffix, a CIDR prefix and surrounding
 * whitespace are all rejected, exactly as inet_pton rejects them. */
function isValidIp6(data) {
	if (match(data, /^[0-9A-Fa-f:.]+$/) == null)
		return false;

	/* A dotted-quad must be the tail; rewrite it as the two hex groups it
	 * stands for, so the rest of the parse only sees "[0-9A-Fa-f:]". */
	if (index(data, '.') !== -1) {
		const quad = match(data, /^(.*:)([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3})$/);
		if (quad === null || !isValidIp4(quad[2]))
			return false;

		const octets = split(quad[2], '.');
		data = quad[1] + sprintf('%02x%02x:%02x%02x',
			int(octets[0]), int(octets[1]), int(octets[2]), int(octets[3]));
	}

	const dbl = index(data, '::');
	let left = data, right = '';

	if (dbl !== -1) {
		if (index(substr(data, dbl + 2), '::') !== -1)
			return false;
		left = substr(data, 0, dbl);
		right = substr(data, dbl + 2);
	}

	let explicit = 0;
	for (let part in [ left, right ]) {
		if (part === '')
			continue;
		const groups = split(part, ':');
		for (let group in groups)
			if (match(group, /^[0-9A-Fa-f]{1,4}$/) === null)
				return false;
		explicit += length(groups);
	}

	/* "::" has to stand for at least one group, so with it at most seven
	 * groups may be written out; without it there must be exactly eight. */
	return dbl === -1 ? explicit === 8 : explicit < 8;
};

/* Pure-ucode stand-in for the datatypes homeproxy-pro.uc asks /sbin/validate_data
 * to check. Production shells out to OpenWrt's `libvalidate` (ubox
 * src/validate.c); off-target this function is what the parser unit tests and
 * tests/toolchain/validate-data.sh exercise, so it answers the same way the
 * real binary does for those five types:
 *
 *   ip4addr   inet_pton(AF_INET) - four decimal octets, 0-255, no leading
 *                                  zeros ("01.2.3.4" and "1.2.3.04" are invalid)
 *   ip6addr   inet_pton(AF_INET6) - see isValidIp6 above; "2001:db8::1",
 *                                  "::ffff:1.2.3.4" and "1:2:3:4:5:6:7:8" are
 *                                  valid, "12345::1" and "fe80::1%eth0" are not
 *   hostname  dt_type_hostname - dot-separated labels of [A-Za-z0-9_-], each
 *                                  1..63 chars, the final label 1..255 chars;
 *                                  "-a", "a-" and "a_b" are valid, "a..b",
 *                                  "a%b", "foo." and ".foo" are not
 *   host      hostname || ip4addr || ip6addr
 *   port      dt_type_port - strtoul(v, &e, 10) with the whole string consumed
 *                                  and the value compared as a signed 32-bit
 *                                  int, so "-1" and " 80" are accepted and
 *                                  "65536"/"80 " are not
 *
 * Known differences, none reachable from the callers:
 *   - only those five types are modelled. The real binary also validates
 *     macaddr, cidr, netmask, file/directory, uci references, ...; an unknown
 *     type exits non-zero there (falsy) and returns false here.
 *   - strtoul()'s saturation above 2^64 is not reproduced: a digit string
 *     that long would wrap instead of clamping, so a port > 2^64 might
 *     disagree. No share link carries one.
 *
 * tests/ucode/test_mock_sync.sh deliberately excludes this function from its
 * production-vs-mock corpus (it is a stand-in, not a copy); it is pinned by
 * the parser tests and by tests/toolchain/validate-data.sh. */
export function validation(datatype, data) {
	if (!datatype || !data)
		return null;

	switch (datatype) {
	case 'port': {
		const parts = match(data, /^[ \t\n\v\f\r]*([+-]?)([0-9]+)$/);
		if (parts === null)
			return false;

		let n = 0;
		for (let digit in split(parts[2], ''))
			n = (n * 10 + int(digit)) % 4294967296;

		if (parts[1] === '-' && n !== 0)
			n = 4294967296 - n;
		if (n > 2147483647)
			n -= 4294967296;

		return n <= 65535;
	}
	case 'ip4addr':
		return isValidIp4(data);
	case 'ip6addr':
		return isValidIp6(data);
	case 'hostname':
		/* dt_type_hostname: every dot-terminated label is 1..63 chars, the
		 * last one 1..255, all from [A-Za-z0-9_-]. */
		return match(data, /^([A-Za-z0-9_-]{1,63}\.)*[A-Za-z0-9_-]{1,255}$/) !== null;
	case 'host':
		return validation('ip4addr', data) === true ||
			validation('ip6addr', data) === true ||
			validation('hostname', data) === true;
	default:
		return false;
	}
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
