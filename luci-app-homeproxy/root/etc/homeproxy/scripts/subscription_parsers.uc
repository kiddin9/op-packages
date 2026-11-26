/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * HomeProxy 订阅 parser helper。
 */

'use strict';

function is_empty(ctx, value) {
	if (type(ctx?.isEmpty) === 'function')
		return ctx.isEmpty(value);

	return !value || value === 'nil' || (type(value) in ['array', 'object'] && length(value) === 0);
}

function validate(ctx, kind, value) {
	return type(ctx?.validation) === 'function' ? ctx.validation(kind, value) : false;
}

function log(ctx, ...args) {
	if (type(ctx?.log) === 'function')
		ctx.log(...args);
}

function singFeatures(ctx) {
	return ctx?.sing_features || {};
}

function applyTlsCertPinPolicy(ctx, config, label, pin) {
	if (type(ctx?.apply_tls_cert_pin_policy) === 'function')
		ctx.apply_tls_cert_pin_policy(config, label, pin);
}

function parse_surge_proxy(ctx, line) {
	let config;

	const eq = index(line, '=');
	if (eq < 0)
		return null;

	const label = trim(substr(line, 0, eq));
	const rhs = trim(substr(line, eq + 1));
	if (is_empty(ctx, label) || is_empty(ctx, rhs))
		return null;

	const tokens = [];
	let cur = '';
	let in_quote = false;
	for (let i = 0; i < length(rhs); i++) {
		const ch = substr(rhs, i, 1);
		if (ch == '"')
			in_quote = !in_quote;
		else if (ch == ',' && !in_quote) {
			push(tokens, trim(cur));
			cur = '';
		} else
			cur += ch;
	}
	if (length(trim(cur)))
		push(tokens, trim(cur));

	if (length(tokens) < 3)
		return null;

	const surge_type = tokens[0];
	const address = tokens[1];
	const port = tokens[2];
	const opts = {};
	let last_key = null;
	for (let i = 3; i < length(tokens); i++) {
		const t = tokens[i];
		const k = index(t, '=');
		if (k < 0) {
			if (last_key == 'port-hopping')
				opts[last_key] = opts[last_key] + ',' + t;
			continue;
		}

		let key = lc(trim(substr(t, 0, k)));
		let val = trim(substr(t, k + 1));
		if (length(val) >= 2 && substr(val, 0, 1) == '"' && substr(val, length(val) - 1, 1) == '"')
			val = substr(val, 1, length(val) - 2);
		opts[key] = val;
		last_key = key;
	}

	function bval(v) { return (v == 'true') ? '1' : '0'; }

	switch (surge_type) {
	case 'trojan':
		config = {
			label: label,
			type: 'trojan',
			address: address,
			port: port,
			password: opts.password,
			tls: '1',
			tls_sni: opts.sni,
			tls_insecure: opts['skip-cert-verify'] ? bval(opts['skip-cert-verify']) : '0',
			tls_alpn: opts.alpn ? split(opts.alpn, ',') : null
		};
		if (opts.ws == 'true') {
			config.transport = 'ws';
			config.ws_path = opts['ws-path'];
			if (opts['ws-headers']) {
				const hm = match(opts['ws-headers'], /[Hh]ost\s*:\s*"?([^",]+)/);
				if (hm)
					config.ws_host = hm[1];
			}
		}
		break;
	case 'ss':
		config = {
			label: label,
			type: 'shadowsocks',
			address: address,
			port: port,
			shadowsocks_encrypt_method: opts['encrypt-method'],
			password: opts.password
		};
		if (opts['udp-over-tcp'] == 'true') {
			config.udp_over_tcp = '1';
			config.udp_over_tcp_version = '2';
		}
		if (opts['shadow-tls-password'] && opts['shadow-tls-sni']) {
			config.shadowtls_enabled = '1';
			config.shadowtls_address = address;
			config.shadowtls_port = port;
			config.shadowtls_password = opts['shadow-tls-password'];
			config.shadowtls_sni = opts['shadow-tls-sni'];
			config.shadowtls_version = opts['shadow-tls-version'] || '3';
		}
		break;
	case 'hysteria2':
	case 'hy2':
		if (!singFeatures(ctx).with_quic) {
			log(ctx, sprintf('Skipping unsupported %s node: %s.', surge_type, label));
			log(ctx, sprintf('Please rebuild sing-box with %s support!', 'QUIC'));
			return null;
		}
		config = {
			label: label,
			type: 'hysteria2',
			address: address,
			port: port,
			password: opts.password,
			hysteria_obfs_type: opts.obfs,
			hysteria_obfs_password: opts['salamander-password'] || opts['obfs-password'],
			tls: '1',
			tls_sni: opts.sni,
			tls_insecure: opts['skip-cert-verify'] ? bval(opts['skip-cert-verify']) : '0'
		};
		applyTlsCertPinPolicy(ctx, config, label, opts['server-cert-fingerprint-sha256']);
		if (opts['port-hopping'])
			config.hysteria_hopping_port = map(split(opts['port-hopping'], ','),
				(seg) => replace(trim(seg), '-', ':'));
		if (opts.alpn)
			config.tls_alpn = split(opts.alpn, ',');
		break;
	case 'anytls':
		config = {
			label: label,
			type: 'anytls',
			address: address,
			port: port,
			password: opts.password,
			tls: '1',
			tls_sni: opts.sni,
			tls_insecure: opts['skip-cert-verify'] ? bval(opts['skip-cert-verify']) : '0'
		};
		break;
	default:
		log(ctx, sprintf('Skipping unsupported Surge proxy type: %s (%s).', surge_type, label));
		return null;
	}

	if (!is_empty(ctx, config)) {
		if (config.address)
			config.address = replace(config.address, /\[|\]/g, '');

		if (!validate(ctx, 'host', config.address) || !validate(ctx, 'port', config.port)) {
			log(ctx, sprintf('Skipping invalid %s node: %s.', config.type, config.label || 'NULL'));
			return null;
		}
	}

	return config;
}

export function parse_surge_subscription(ctx, body) {
	const lines = split(body, '\n');
	const nodes = [];
	let in_proxies = false;

	for (let i = 0; i < length(lines); i++) {
		const ln = trim(lines[i]);

		if (match(lines[i], /^[ \t]*proxies\s*:/)) {
			in_proxies = true;
			continue;
		}
		if (in_proxies && match(lines[i], /^[A-Za-z0-9_-]+\s*:/) && !match(lines[i], /^\s/))
			in_proxies = false;
		if (!in_proxies)
			continue;

		if (is_empty(ctx, ln) || substr(ln, 0, 1) == '#')
			continue;

		if (index(ln, '=') < 0)
			continue;

		const cfg = parse_surge_proxy(ctx, ln);
		if (cfg)
			push(nodes, cfg);
	}

	return nodes;
};
