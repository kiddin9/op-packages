/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * Copyright (C) 2023-2025 ImmortalWrt.org
 */

'use strict';

import { urldecode, urlencode } from 'luci.http';

import { decodeBase64Str, parseURL, isEmpty, validation } from 'homeproxy';

/*
 * Share-link parsers. Every protocol has its own parse_<scheme>_uri() so the
 * branches can be read, changed and unit-tested in isolation; parse_uri() only
 * dispatches on the scheme and applies the common address/port validation and
 * label fallback afterwards.
 *
 * `features` is the sing-box feature map (with_quic/with_utls/...), `log` is a
 * logging callback, both injected so the parsers stay free of ubus/uci.
 */

/* https://shadowsocks.org/guide/sip008.html */
export function parse_sip008_uri(uri) {
	return {
		label: uri.remarks,
		type: 'shadowsocks',
		address: uri.server,
		port: uri.server_port,
		shadowsocks_encrypt_method: uri.method,
		password: uri.password,
		shadowsocks_plugin: uri.plugin,
		shadowsocks_plugin_opts: uri.plugin_opts
	};
};

/* https://github.com/anytls/anytls-go/blob/v0.0.8/docs/uri_scheme.md */
export function parse_anytls_uri(uri) {
	uri = split(trim(uri), '://');

	const url = parseURL('http://' + uri[1]) || {};
	const params = url.searchParams || {};

	return {
		label: url.hash ? urldecode(url.hash) : null,
		type: 'anytls',
		address: url.hostname,
		port: url.port,
		password: urldecode(url.username),
		tls: '1',
		tls_sni: params.sni,
		tls_insecure: (params.insecure === '1') ? '1' : '0'
	};
};

export function parse_http_uri(uri) {
	uri = split(trim(uri), '://');

	const url = parseURL('http://' + uri[1]) || {};

	return {
		label: url.hash ? urldecode(url.hash) : null,
		type: 'http',
		address: url.hostname,
		port: url.port,
		username: url.username ? urldecode(url.username) : null,
		password: url.password ? urldecode(url.password) : null,
		tls: (uri[0] === 'https') ? '1' : '0'
	};
};

/* https://github.com/HyNetwork/hysteria/wiki/URI-Scheme */
export function parse_hysteria_uri(uri, features, log) {
	uri = split(trim(uri), '://');

	const url = parseURL('http://' + uri[1]) || {};
	const params = url.searchParams || {};

	if (!features.with_quic || (params.protocol && params.protocol !== 'udp')) {
		log(sprintf('Skipping unsupported %s node: %s.', uri[0], urldecode(url.hash) || url.hostname));
		if (!features.with_quic)
			log(sprintf('Please rebuild sing-box with %s support!', 'QUIC'));

		return null;
	}

	return {
		label: url.hash ? urldecode(url.hash) : null,
		type: 'hysteria',
		address: url.hostname,
		port: url.port,
		hysteria_protocol: params.protocol || 'udp',
		hysteria_auth_type: params.auth ? 'string' : null,
		hysteria_auth_payload: params.auth,
		hysteria_obfs_password: params.obfsParam,
		hysteria_down_mbps: params.downmbps,
		hysteria_up_mbps: params.upmbps,
		tls: '1',
		tls_insecure: (params.insecure in ['true', '1']) ? '1' : '0',
		tls_sni: params.peer,
		tls_alpn: params.alpn
	};
};

/* https://v2.hysteria.network/docs/developers/URI-Scheme/ */
export function parse_hysteria2_uri(uri, features, log) {
	uri = split(trim(uri), '://');

	const url = parseURL('http://' + uri[1]) || {};
	const params = url.searchParams || {};

	if (!features.with_quic) {
		log(sprintf('Skipping unsupported %s node: %s.', uri[0], urldecode(url.hash) || url.hostname));
		log(sprintf('Please rebuild sing-box with %s support!', 'QUIC'));
		return null;
	}

	return {
		label: url.hash ? urldecode(url.hash) : null,
		type: 'hysteria2',
		address: url.hostname,
		port: url.port,
		password: url.username ? (
			urldecode(url.username + (url.password ? (':' + url.password) : ''))
		) : null,
		hysteria_obfs_type: params.obfs,
		hysteria_obfs_password: params['obfs-password'],
		tls: '1',
		tls_insecure: (params.insecure === '1') ? '1' : '0',
		tls_sni: params.sni
	};
};

/* Surge Snell share link: snell://host:port?psk=..&obfs=http&obfs-host=..#name */
export function parse_snell_uri(uri) {
	uri = split(trim(uri), '://');

	const url = parseURL('http://' + uri[1]) || {};
	const params = url.searchParams || {};

	return {
		label: url.hash ? urldecode(url.hash) : null,
		type: 'snell',
		address: url.hostname,
		port: url.port,
		password: url.username ? urldecode(url.username)
			: (params.psk ? urldecode(params.psk) : null),
		snell_version: params.version || '4',
		snell_userkey: params.userkey,
		snell_obfs_mode: (params.obfs === 'http') ? 'http' : null,
		snell_obfs_host: params['obfs-host'],
		snell_reuse: (params.reuse === '1') ? '1' : '0'
	};
};

export function parse_socks_uri(uri) {
	uri = split(trim(uri), '://');

	const url = parseURL('http://' + uri[1]) || {};

	return {
		label: url.hash ? urldecode(url.hash) : null,
		type: 'socks',
		address: url.hostname,
		port: url.port,
		username: url.username ? urldecode(url.username) : null,
		password: url.password ? urldecode(url.password) : null,
		socks_version: (match(uri[0], /4/)) ? '4' : '5'
	};
};

export function parse_ss_uri(uri) {
	uri = split(trim(uri), '://');

	/* "Lovely" Shadowrocket format */
	const ss_suri = split(uri[1], '#');
	let ss_slabel = '';
	if (length(ss_suri) <= 2) {
		if (length(ss_suri) === 2)
			ss_slabel = '#' + urlencode(ss_suri[1]);
		if (decodeBase64Str(ss_suri[0]))
			uri[1] = decodeBase64Str(ss_suri[0]) + ss_slabel;
	}

	/* Legacy format is not supported, it should be never appeared in modern subscriptions */
	/* https://github.com/shadowsocks/shadowsocks-org/commit/78ca46cd6859a4e9475953ed34a2d301454f579e */

	/* SIP002 format https://shadowsocks.org/guide/sip002.html */
	const url = parseURL('http://' + uri[1]) || {};

	let ss_userinfo = {};
	if (url.username && url.password)
		/* User info encoded with URIComponent */
		ss_userinfo = [url.username, urldecode(url.password)];
	else if (url.username)
		/* User info encoded with base64 */
		ss_userinfo = split(decodeBase64Str(urldecode(url.username)), ':', 2);

	let ss_plugin, ss_plugin_opts;
	if (url.search && url.searchParams.plugin) {
		const ss_plugin_info = split(url.searchParams.plugin, ';', 2);
		ss_plugin = ss_plugin_info[0];
		if (ss_plugin === 'simple-obfs')
			/* Fix non-standard plugin name */
			ss_plugin = 'obfs-local';
		ss_plugin_opts = ss_plugin_info[1];
	}

	return {
		label: url.hash ? urldecode(url.hash) : null,
		type: 'shadowsocks',
		address: url.hostname,
		port: url.port,
		shadowsocks_encrypt_method: ss_userinfo[0],
		password: ss_userinfo[1],
		shadowsocks_plugin: ss_plugin,
		shadowsocks_plugin_opts: ss_plugin_opts
	};
};

/* https://p4gefau1t.github.io/trojan-go/developer/url/ */
export function parse_trojan_uri(uri) {
	uri = split(trim(uri), '://');

	const url = parseURL('http://' + uri[1]) || {};
	const params = url.searchParams || {};

	const config = {
		label: url.hash ? urldecode(url.hash) : null,
		type: 'trojan',
		address: url.hostname,
		port: url.port,
		password: urldecode(url.username),
		transport: (params.type !== 'tcp') ? params.type : null,
		tls: '1',
		tls_sni: params.sni
	};
	switch (params.type) {
	case 'grpc':
		config.grpc_servicename = params.serviceName;
		break;
	case 'ws':
		config.ws_host = params.host ? urldecode(params.host) : null;
		config.ws_path = params.path ? urldecode(params.path) : null;
		if (config.ws_path && match(config.ws_path, /\?ed=/)) {
			config.websocket_early_data_header = 'Sec-WebSocket-Protocol';
			config.websocket_early_data = split(config.ws_path, '?ed=')[1];
			config.ws_path = split(config.ws_path, '?ed=')[0];
		}
		break;
	}

	return config;
};

/* https://github.com/daeuniverse/dae/discussions/182 */
export function parse_tuic_uri(uri, features, log) {
	uri = split(trim(uri), '://');

	const url = parseURL('http://' + uri[1]) || {};
	const params = url.searchParams || {};

	if (!features.with_quic) {
		log(sprintf('Skipping unsupported %s node: %s.', uri[0], urldecode(url.hash) || url.hostname));
		log(sprintf('Please rebuild sing-box with %s support!', 'QUIC'));

		return null;
	}

	return {
		label: url.hash ? urldecode(url.hash) : null,
		type: 'tuic',
		address: url.hostname,
		port: url.port,
		uuid: url.username,
		password: url.password ? urldecode(url.password) : null,
		tuic_congestion_control: params.congestion_control,
		tuic_udp_relay_mode: params.udp_relay_mode,
		tls: '1',
		tls_sni: params.sni,
		tls_alpn: params.alpn ? split(urldecode(params.alpn), ',') : null,
	};
};

/* https://github.com/XTLS/Xray-core/discussions/716 */
export function parse_vless_uri(uri, features, log) {
	uri = split(trim(uri), '://');

	const url = parseURL('http://' + uri[1]) || {};
	const params = url.searchParams || {};

	/* Unsupported protocol */
	if (params.type === 'kcp') {
		log(sprintf('Skipping unsupported %s node: %s.', uri[0], urldecode(url.hash) || url.hostname));
		return null;
	} else if (params.type === 'quic' && ((params.quicSecurity && params.quicSecurity !== 'none') || !features.with_quic)) {
		log(sprintf('Skipping unsupported %s node: %s.', uri[0], urldecode(url.hash) || url.hostname));
		if (!features.with_quic)
			log(sprintf('Please rebuild sing-box with %s support!', 'QUIC'));

		return null;
	}

	const config = {
		label: url.hash ? urldecode(url.hash) : null,
		type: 'vless',
		address: url.hostname,
		port: url.port,
		uuid: url.username,
		transport: (params.type !== 'tcp') ? params.type : null,
		tls: (params.security in ['tls', 'xtls', 'reality']) ? '1' : '0',
		tls_sni: params.sni,
		tls_alpn: params.alpn ? split(urldecode(params.alpn), ',') : null,
		tls_reality: (params.security === 'reality') ? '1' : '0',
		tls_reality_public_key: params.pbk ? urldecode(params.pbk) : null,
		tls_reality_short_id: params.sid,
		tls_utls: features.with_utls ? params.fp : null,
		vless_flow: (params.security in ['tls', 'reality']) ? params.flow : null
	};
	switch (params.type) {
	case 'grpc':
		config.grpc_servicename = params.serviceName;
		break;
	case 'http':
	case 'tcp':
		if (params.type === 'http' || params.headerType === 'http') {
			config.http_host = params.host ? split(urldecode(params.host), ',') : null;
			config.http_path = params.path ? urldecode(params.path) : null;
		}
		break;
	case 'httpupgrade':
		config.httpupgrade_host = params.host ? urldecode(params.host) : null;
		config.http_path = params.path ? urldecode(params.path) : null;
		break;
	case 'ws':
		config.ws_host = params.host ? urldecode(params.host) : null;
		config.ws_path = params.path ? urldecode(params.path) : null;
		if (config.ws_path && match(config.ws_path, /\?ed=/)) {
			config.websocket_early_data_header = 'Sec-WebSocket-Protocol';
			config.websocket_early_data = split(config.ws_path, '?ed=')[1];
			config.ws_path = split(config.ws_path, '?ed=')[0];
		}
		break;
	}

	return config;
};

/* https://github.com/2dust/v2rayN/wiki/Description-of-VMess-share-link */
export function parse_vmess_uri(uri, features, log) {
	uri = split(trim(uri), '://');

	/* "Lovely" shadowrocket format */
	if (match(uri, /&/)) {
		log(sprintf('Skipping unsupported %s format.', uri[0]));
		return null;
	}

	let payload;
	try {
		payload = json(decodeBase64Str(uri[1])) || {};
	} catch(e) {
		log(sprintf('Skipping unsupported %s format.', uri[0]));
		return null;
	}

	if (payload.v != '2') {
		log(sprintf('Skipping unsupported %s format.', uri[0]));
		return null;
	/* Unsupported protocol */
	} else if (payload.net === 'kcp') {
		log(sprintf('Skipping unsupported %s node: %s.', uri[0], payload.ps || payload.add));
		return null;
	} else if (payload.net === 'quic' && ((payload.type && payload.type !== 'none') || payload.path || !features.with_quic)) {
		log(sprintf('Skipping unsupported %s node: %s.', uri[0], payload.ps || payload.add));
		if (!features.with_quic)
			log(sprintf('Please rebuild sing-box with %s support!', 'QUIC'));

		return null;
	}
	/*
	 * https://www.v2fly.org/config/protocols/vmess.html#vmess-md5-%E8%AE%A4%E8%AF%81%E4%BF%A1%E6%81%AF-%E6%B7%98%E6%B1%B0%E6%9C%BA%E5%88%B6
	 * else if (payload.aid && int(payload.aid) !== 0) {
	 * 	log(sprintf('Skipping unsupported %s node: %s.', uri[0], payload.ps || payload.add));
	 * 	return null;
	 * }
	 */

	const config = {
		label: payload.ps ? urldecode(payload.ps) : null,
		type: 'vmess',
		address: payload.add,
		port: payload.port,
		uuid: payload.id,
		vmess_alterid: payload.aid,
		vmess_encrypt: payload.scy || 'auto',
		vmess_global_padding: '1',
		transport: (payload.net !== 'tcp') ? payload.net : null,
		tls: (payload.tls === 'tls') ? '1' : '0',
		tls_sni: payload.sni || payload.host,
		tls_alpn: payload.alpn ? split(payload.alpn, ',') : null,
		tls_utls: features.with_utls ? payload.fp : null
	};
	switch (payload.net) {
	case 'grpc':
		config.grpc_servicename = payload.path;
		break;
	case 'h2':
	case 'tcp':
		if (payload.net === 'h2' || payload.type === 'http') {
			config.transport = 'http';
			config.http_host = payload.host ? split(payload.host, ',') : null;
			config.http_path = payload.path;
		}
		break;
	case 'httpupgrade':
		config.httpupgrade_host = payload.host;
		config.http_path = payload.path;
		break;
	case 'ws':
		config.ws_host = payload.host;
		config.ws_path = payload.path;
		if (config.ws_path && match(config.ws_path, /\?ed=/)) {
			config.websocket_early_data_header = 'Sec-WebSocket-Protocol';
			config.websocket_early_data = split(config.ws_path, '?ed=')[1];
			config.ws_path = split(config.ws_path, '?ed=')[0];
		}
		break;
	}

	return config;
};

export function parse_uri(uri, features, log) {
	if (!features) features = {};
	if (!log) log = function() {};

	let config;

	if (type(uri) === 'object') {
		if (uri.nodetype === 'sip008')
			config = parse_sip008_uri(uri);
	} else if (type(uri) === 'string') {
		switch (split(trim(uri), '://')[0]) {
		case 'anytls':
			config = parse_anytls_uri(uri, features, log);
			break;
		case 'http':
		case 'https':
			config = parse_http_uri(uri, features, log);
			break;
		case 'hysteria':
			config = parse_hysteria_uri(uri, features, log);
			break;
		case 'hysteria2':
		case 'hy2':
			config = parse_hysteria2_uri(uri, features, log);
			break;
		case 'snell':
			config = parse_snell_uri(uri, features, log);
			break;
		case 'socks':
		case 'socks4':
		case 'socks4a':
		case 'socks5':
		case 'socks5h':
			config = parse_socks_uri(uri, features, log);
			break;
		case 'ss':
			config = parse_ss_uri(uri, features, log);
			break;
		case 'trojan':
			config = parse_trojan_uri(uri, features, log);
			break;
		case 'tuic':
			config = parse_tuic_uri(uri, features, log);
			break;
		case 'vless':
			config = parse_vless_uri(uri, features, log);
			break;
		case 'vmess':
			config = parse_vmess_uri(uri, features, log);
			break;
		}
	}

	if (!isEmpty(config)) {
		if (config.address)
			config.address = replace(config.address, /\[|\]/g, '');

		if (!validation('host', config.address) || !validation('port', config.port)) {
			log(sprintf('Skipping invalid %s node: %s.', config.type, config.label || 'NULL'));
			return null;
		} else if (!config.label)
			config.label = (validation('ip6addr', config.address) ?
				`[${config.address}]` : config.address) + ':' + config.port;
	}

	return config;
};
