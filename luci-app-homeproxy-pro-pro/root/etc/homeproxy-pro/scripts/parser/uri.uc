/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * parse_uri() is a thin dispatcher.
 * The 11 per-scheme parsers moved to parser/protocols.uc; the
 * categorised post-parse checks moved to parser/validator.uc; the
 * canonical-shape conversion lives in parser/normalize.uc; and the
 * canonical <-> UCI mapping table lives in parser/mapping.uc.
 *
 * This file is the only one parse_uri.uc's old callers should reach
 * for. The output shape is unchanged (flat UCI-key dict) so the
 * Repository's contract is preserved; the next PR can flip the
 * parser to canonical Node output and teach the Repository to
 * flatten, with parser/mapping.uc as the single source of truth.
 */

'use strict';

import { isEmpty, validation } from '../homeproxy.uc';

import {
	parse_sip008_uri, parse_anytls_uri, parse_http_uri,
	parse_hysteria_uri, parse_hysteria2_uri, parse_snell_uri,
	parse_socks_uri, parse_ss_uri, parse_trojan_uri,
	parse_tuic_uri, parse_vless_uri, parse_vmess_uri
} from './protocols.uc';

import { validate } from './validator.uc';

/* Default label: ip6addr uses brackets for readability, otherwise
 * `address:port`. Exported because every scheme benefits and because a
 * caller that mutates a parsed config's address (subscription
 * apply_policy does not, but a future one could) can re-derive it.
 *
 * Declared above parse_uri on purpose: ucode does not hoist
 * `export function`, so the call below would otherwise fail at runtime
 * with "access to undeclared variable". */
export function derive_label(config) {
	if (config.label)
		return config.label;
	if (!config.address || !config.port)
		return null;
	return (validation('ip6addr', config.address) ?
		`[${config.address}]` : config.address) + ':' + config.port;
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

	if (isEmpty(config))
		return null;

	/* Strip the brackets UCI still allows around IPv6 literals - they
	 * survive into a sing-box `server` field verbatim otherwise. */
	if (config.address)
		config.address = replace(config.address, /\[|\]/g, '');

	/* validate() returns null (and logs) when the host or port is not
	 * usable, so the result has to be tested rather than merged with
	 * `|| config` - that fallback would hand the invalid config back. */
	const checked = validate(config, log);
	if (!checked)
		return null;

	if (!checked.label)
		checked.label = derive_label(checked);

	return checked;
};