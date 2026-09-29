/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * Copyright (C) 2025 ImmortalWrt.org
 *
 * Test double for root/etc/homeproxy/scripts/homeproxy.uc.
 *
 * Only `validation()` is stubbed: the real one shells out to
 * /sbin/validate_data, which does not exist outside OpenWrt. Everything else
 * (isEmpty, decodeBase64Str, parseURL) is a verbatim copy so the parser tests
 * exercise the same string handling as production. Keep these in sync when
 * homeproxy.uc changes.
 */

import { urldecode_params } from 'luci.http';

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

/* Pure-ucode stand-in for /sbin/validate_data (host/port/ip4/ip6/hostname). */
export function validation(datatype, data) {
	if (!datatype || !data)
		return null;

	switch (datatype) {
	case 'port':
		return match(data, /^\d+$/) != null && int(data) >= 0 && int(data) <= 65535;
	case 'ip4addr':
		if (match(data, /^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/) == null)
			return false;
		for (let octet in split(data, '.'))
			if (int(octet) > 255)
				return false;
		return true;
	case 'ip6addr':
		return match(data, /^[0-9a-fA-F:]+$/) != null && match(data, /::.*::/) == null;
	case 'hostname':
		return match(data, /^[A-Za-z0-9_][A-Za-z0-9_%-.]*[A-Za-z0-9]$/) != null ||
			match(data, /^[A-Za-z0-9_]$/) != null;
	case 'host':
		return validation('ip4addr', data) === true ||
			validation('ip6addr', data) === true ||
			validation('hostname', data) === true;
	default:
		return null;
	}
};

/*
 * Decode %XX escapes without touching '+'. urldecode() maps '+' to a space,
 * which corrupts base64 userinfo ("+" is part of the alphabet), so share-link
 * userinfo is percent-decoded with this instead.
 */
/*
 * ucode has no tolower(), so both hex cases are mapped by hand.
 */
function hexValue(ch) {
	const lower = index('0123456789abcdef', ch);
	if (lower >= 0)
		return lower;

	const upper = index('ABCDEF', ch);

	return upper < 0 ? -1 : 10 + upper;
}

/*
 * ucode's regex engine rejects \x00 inside a character class ("Missing ']'"),
 * so control bytes are checked by hand.
 */
function hasControlChar(str) {
	for (let i = 0; i < length(str); i++) {
		const code = ord(str, i);
		if (code < 0x20 || code === 0x7f)
			return true;
	}

	return false;
}

export function percentDecode(str) {
	if (isEmpty(str))
		return str;

	return replace(str, /%([0-9A-Fa-f]{2})/g, (whole, hex) => {
		const hi = hexValue(substr(hex, 0, 1));
		const lo = hexValue(substr(hex, 1, 1));

		return (hi < 0 || lo < 0) ? whole : chr(hi * 16 + lo);
	});
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
		/* keep in sync with the production parser (homeproxy.uc) */
		let userinfo = percentDecode(objurl.userinfo);

		userinfo = replace(userinfo, /:(.+)$/, (_, val) => {
			objurl.password = val;
			return '';
		});

		if (!match(userinfo, /\s/) && !hasControlChar(userinfo))
			objurl.username = userinfo;
		else
			delete objurl.password;

		delete objurl.userinfo;
	};

	if (!objurl.port)
		objurl.port = services[objurl.protocol];

	objurl.host = objurl.hostname + (objurl.port ? `:${objurl.port}` : '');
	objurl.origin = `${objurl.protocol}://${objurl.host}`;

	return objurl;
};
