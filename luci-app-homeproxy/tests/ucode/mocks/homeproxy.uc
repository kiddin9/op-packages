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
