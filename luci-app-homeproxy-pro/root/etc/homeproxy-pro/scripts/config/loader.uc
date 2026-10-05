/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * Stage A1.1 of the architecture refactor:
 *
 *     UCI -> Config Loader -> HomeProxyConfig
 *
 * This file originated as the demo loader and was promoted into the
 * production tree; the demo copy is gone, so this is the only one.
 *
 * What this layer does:
 *   - owns the only `uci.cursor()` in the client configuration path
 *   - reads general + infra + nodes + dns + routing + access_control + server
 *   - never emits sing-box JSON
 *   - never mutates/commits UCI
 */

'use strict';

import { cursor } from 'uci';

import {
	Config, Node, CREDENTIALS, Inbound,
	INBOUND_CREDENTIALS, INBOUND_OPTIONS, INBOUND_COMMON, INBOUND_TLS_SERVER
} from './model.uc';

import { PROTOCOL_TO_UCI as PROTOCOL_OPTIONS } from '../parser/mapping.uc';

const UCICONFIG = 'homeproxy-pro';

const SECTION = {
	main: 'config',
	infra: 'infra',
	node: 'node',
	dns: 'dns',
	dns_server: 'dns_server',
	dns_rule: 'dns_rule',
	routing: 'routing',
	routing_node: 'routing_node',
	routing_rule: 'routing_rule',
	ruleset: 'ruleset',
	control: 'control',
	subscription: 'subscription',
	server: 'server'
};

/* Booleans are UCI '0'/'1'; keep the conversion in one place. */
function bool(value) {
	return value === '1';
}

function opt(uci, section, name) {
	/* UCI returns null for an absent option; the old code papered over that
	 * with `|| ''` at every call site, losing the distinction between "not
	 * set" and "set to empty". The model keeps null instead. */
	return uci.get(UCICONFIG, SECTION[section], name);
}

function node_opt(uci, section_id, name) {
	return uci.get(UCICONFIG, section_id, name);
}

/* --- sub-object extraction --------------------------------------------- */

/* These three functions are the whole reason a Node is hierarchical: the
 * shared TLS/transport/multiplex builders (homeproxy-pro.uc) take a flat,
 * prefixed dict today, so every caller has to hand them the right subset. A
 * sub-object makes the boundary explicit and testable.
 *
 * load_tls and load_transport are exported so the server generator can
 * shape its UCI inbound sections the same way; only the multiplex shape is
 * Loader-internal because no caller outside the client node path needs it. */

export function load_tls(get) {
	return {
		enabled: get('tls'),
		server_name: get('tls_sni'),
		insecure: get('tls_insecure'),
		alpn: get('tls_alpn'),
		min_version: get('tls_min_version'),
		max_version: get('tls_max_version'),
		handshake_timeout: get('tls_handshake_timeout'),
		cipher_suites: get('tls_cipher_suites'),
		cert_path: get('tls_cert_path'),
		ech: {
			enabled: get('tls_ech'),
			config: get('tls_ech_config'),
			config_path: get('tls_ech_config_path')
		},
		utls: {
			fingerprint: get('tls_utls')
		},
		reality: {
			enabled: get('tls_reality'),
			public_key: get('tls_reality_public_key'),
			short_id: get('tls_reality_short_id')
		}
	};
};

export function load_transport(get) {
	const transport = get('transport');

	if (transport == null || transport === '')
		return { type: null };

	return {
		type: transport,
		host: get('http_host') || get('httpupgrade_host'),
		path: get('http_path') || get('ws_path'),
		headers: get('ws_host') ? { Host: get('ws_host') } : null,
		method: get('http_method'),
		max_early_data: get('websocket_early_data'),
		early_data_header_name: get('websocket_early_data_header'),
		service_name: get('grpc_servicename'),
		idle_timeout: get('http_idle_timeout'),
		ping_timeout: get('http_ping_timeout'),
		permit_without_stream: get('grpc_permit_without_stream')
	};
};

function load_multiplex(get) {
	return {
		enabled: get('multiplex'),
		protocol: get('multiplex_protocol'),
		max_connections: get('multiplex_max_connections'),
		min_streams: get('multiplex_min_streams'),
		max_streams: get('multiplex_max_streams'),
		padding: get('multiplex_padding'),
		brutal: {
			enabled: get('multiplex_brutal'),
			up_mbps: get('multiplex_brutal_up'),
			down_mbps: get('multiplex_brutal_down')
		}
	};
}

/* Cross-protocol common fields (every outbound protocol carries them, not
 * just one). Lives as its own sub-object instead of being repeated in
 * every PROTOCOL_OPTIONS row, and the Adapter reads from `node.common`. */
function load_common(get) {
	return {
		proxy_protocol: get('proxy_protocol'),
		tcp_fast_open: get('tcp_fast_open'),
		tcp_multi_path: get('tcp_multi_path'),
		udp_fragment: get('udp_fragment')
	};
}

/* --- protocol options --------------------------------------------------- */

/* The canonical <-> UCI mapping table lives in scripts/parser/mapping.uc and
 * is imported as PROTOCOL_OPTIONS above. The Loader no longer maintains its
 * own copy, so the parser, the Loader, the parser's normalize(), and the
 * Repository all read from the same source. Anything not listed in
 * parser/mapping.uc for a given protocol is not part of the domain
 * contract; a stale UCI option is now dropped at the parser side too.
 */

function load_protocol_options(get, type) {
	const mapping = PROTOCOL_OPTIONS[type] || {};
	const options = {};

	for (let canonical, uci_name in mapping)
		options[canonical] = get(uci_name);

	return options;
}

/* Pull the protocol's credential fields out under canonical names, using the
 * single CREDENTIALS table from the model. This is the loader half of the
 * mapping that the old code spread across ~20 ternaries in generate_outbound().
 * Declared before Loader: ucode resolves module-level names at call time but
 * not before they are declared. */
function load_credentials(get, type) {
	const mapping = CREDENTIALS[type] || {};
	const credentials = {};

	for (let canonical, uci_name in mapping)
		credentials[canonical] = get(uci_name);

	return credentials;
}

/* --- domain sub-objects ------------------------------------------------ */

/* Settings: only the keys that exist in UCI are kept (null is dropped), so
 * the consumer can tell "not set" from "set to empty". A3 (Generator split)
 * will own the actual key list - this loader just preserves what UCI has. */
function load_settings(uci, section, keys) {
	const settings = {};

	for (let key in keys) {
		const v = uci.get(UCICONFIG, section, key);
		if (v != null)
			settings[key] = v;
	}

	return settings;
}

/* The raw UCI section dict that
 * uci.foreach() yields carries internal fields prefixed with a dot
 * (`.name`, `.index`, `.type`); downstream generators had to read those
 * directly, and every consumer had to remember `cfg.enabled !== '1'`
 * to gate a section. Normalise once here so consumers see a flat
 * domain object: the dot-prefixed pseudo-fields are dropped, the UCI
 * section name is exposed as `name`, and `enabled` (when present) is
 * coerced to a real boolean.
 *
 * Fields with non-prefixed names that happen to collide with the UCI
 * metadata (e.g. an option literally called `name` or `index`) would
 * be shadowed; in this codebase that does not happen, and the Adapter keeps
 * it that way. */
function normalize_section(cfg) {
	const item = {};

	for (let k, v in cfg) {
		/* substr(), not k[0]: the target ucode (2026.01.16) rejects
		 * string indexing with "left-hand side expression is not an
		 * array or object". subscription/repository.uc already uses
		 * the substr() form for the same check. */
		if (substr(k, 0, 1) === '.')
			continue;
		item[k] = v;
	}

	if ('enabled' in item)
		item.enabled = (item.enabled === '1');

	item.name = cfg['.name'];

	return item;
}

/* Single-section + list sections grouped under a domain sub-object.
 * Each list entry is the normalised section dict produced by
 * normalize_section(): the UCI `.name`/`.index`/`.type` pseudo-fields
 * are gone, `name` is set to the section name, and `enabled` is a
 * boolean. Sing-box field names are still produced by the generator
 * modules; this loader just preserves what UCI has. */
function load_sections(uci, type) {
	const items = [];

	uci.foreach(UCICONFIG, type, (cfg) => push(items, normalize_section(cfg)));

	return items;
}

function load_dns(uci) {
	return {
		settings: load_settings(uci, SECTION.dns, [
			'default_strategy', 'default_server',
			'disable_cache', 'disable_cache_expire',
			'client_subnet',
			'optimistic_cache', 'optimistic_timeout',
			'dns_timeout', 'cache_file_store_dns'
		]),
		servers: load_sections(uci, SECTION.dns_server),
		rules: load_sections(uci, SECTION.dns_rule)
	};
}

function load_routing(uci) {
	return {
		settings: load_settings(uci, SECTION.routing, [
			'default_outbound', 'default_outbound_dns',
			'domain_strategy', 'find_neighbor',
			'udp_timeout', 'tcpip_stack', 'endpoint_independent_nat'
		]),
		nodes: load_sections(uci, SECTION.routing_node),
		rules: load_sections(uci, SECTION.routing_rule),
		rulesets: load_sections(uci, SECTION.ruleset)
	};
}

/* access_control is two single sections: `control` (lan_proxy_mode,
 * wan_proxy_*_ips) and `subscription` (auto_update, filter, urls). */
function load_access_control(uci) {
	/* Normalised to an array.  uci.get() hands a single-value option over as a
	 * *string* and a list as an array, and `for (let url in <string>)` iterates
	 * zero times in ucode - so a URL written with `uci set` instead of
	 * `add_list` (or carried over from an older config) made the whole
	 * subscription update a silent no-op: exit 0, no log, nothing fetched.
	 * Measured on the device: list -> array, one iteration; option -> string,
	 * zero. */
	const sub_urls_raw = uci.get(UCICONFIG, SECTION.subscription, 'subscription_url');
	const sub_urls = sub_urls_raw == null ? []
		: (type(sub_urls_raw) === 'array' ? sub_urls_raw : [ sub_urls_raw ]);

	return {
		control: load_settings(uci, SECTION.control, [
			'bind_interface', 'lan_proxy_mode'
		]),
		/* wan_proxy_*_ips are list options on the control section; collect
		   them in their canonical form. */
		wan_proxy_ipv4_ips: uci.get(UCICONFIG, SECTION.control, 'wan_proxy_ipv4_ips') || [],
		wan_proxy_ipv6_ips: uci.get(UCICONFIG, SECTION.control, 'wan_proxy_ipv6_ips') || [],
		subscription: load_settings(uci, SECTION.subscription, [
			'auto_update', 'allow_insecure',
			'packet_encoding', 'update_via_proxy',
			'filter_nodes', 'user_agent'
		]),
		/* Normalised to an array.  uci.get() hands a single-value option over as a
		 * *string* and a list as an array, and `for (let url in <string>)` iterates
		 * zero times in ucode - so a URL written with `uci set` instead of
		 * `add_list` (or migrated from an older config) made the whole subscription
		 * update a silent no-op: exit 0, no log, nothing fetched.  Measured on the
		 * device: list -> array, one iteration; option -> string, zero. */
		subscription_urls: sub_urls,
		filter_keywords: uci.get(UCICONFIG, SECTION.subscription, 'filter_keywords') || []
	};
}

/* The two "read a table of canonical -> UCI names off a section"
 * helpers shared by the node and inbound paths. Same shape as
 * load_protocol_options() above; split out so the server side reads
 * the same way the client side does. */
function load_table(get, mapping) {
	const out = {};

	for (let canonical, uci_name in mapping)
		out[canonical] = get(uci_name);

	return out;
}

/* A server inbound is now a
 * domain object like a Node, built here and shaped into sing-box JSON
 * by config/adapter.uc's InboundFactory. Before this the generator read
 * the flat UCI section directly (`cfg.snell_version`,
 * `cfg.shadowsocks_encrypt_method`, ...), so the server path had no
 * domain model at all.
 *
 * Same sub-object split as Node: common (listener-level), credentials,
 * tls (the shared shape the client uses too), tls_server (the
 * server-only tail), transport, multiplex, protocol_options. */
function load_inbound(get, section) {
	const type = get('type');

	return Inbound.create({
		id: section['.name'],
		name: get('label') || section['.name'],
		type: type,
		enabled: section.enabled === '1',

		address: get('address'),
		port: get('port'),
		firewall: get('firewall'),

		common: load_table(get, INBOUND_COMMON),
		credentials: load_table(get, INBOUND_CREDENTIALS[type] || {}),
		tls: load_tls(get),
		tls_server: load_table(get, INBOUND_TLS_SERVER),
		transport: load_transport(get),
		multiplex: load_multiplex(get),
		protocol_options: load_table(get, INBOUND_OPTIONS[type] || {})
	});
}

/* server has one enabled/log_level single section + N inbound sections
 * (each with a `type` of vless / trojan / shadowsocks / ...). */
function load_server(uci) {
	const inbounds = [];

	uci.foreach(UCICONFIG, SECTION.server, (section) => {
		push(inbounds, load_inbound((name) => node_opt(uci, section['.name'], name), section));
	});

	return {
		settings: load_settings(uci, SECTION.server, [
			'enabled', 'log_level'
		]),
		inbounds
	};
}

/* --- loader ------------------------------------------------------------- */

export const Loader = {
	/* Load the client side of the configuration. `dir` defaults to the
	 * production UCI directory but can be overridden, which removes the need
	 * for the test suite's `sed` of `const uci = cursor();`. */
	load: (dir) => {
		const uci = dir ? cursor(dir) : cursor();

		uci.load(UCICONFIG);

		const config = Config.create('homeproxy-pro');

		config.general = {
			routing_mode: opt(uci, 'main', 'routing_mode') || 'bypass_mainland_china',
			proxy_mode: opt(uci, 'main', 'proxy_mode') || 'redirect_tproxy',
			main_node: opt(uci, 'main', 'main_node') || 'nil',
			main_udp_node: opt(uci, 'main', 'main_udp_node') || 'nil',
			/* Booleans stay as raw UCI strings here, same as Node. The
			   Adapter (A3) is the one that calls strToBool(); coercing in
			   the Loader and again in the Adapter produced two different
			   defaults for absent / garbage values during A1.1. */
			ipv6_support: opt(uci, 'main', 'ipv6_support'),

			/* A2.1: scalar + list fields on the `config` section. */
			dns_server: opt(uci, 'main', 'dns_server'),
			china_dns_server: opt(uci, 'main', 'china_dns_server'),
			log_level: opt(uci, 'main', 'log_level') || 'warn',
			tun_dns_mode: opt(uci, 'main', 'tun_dns_mode'),
			tun_dns_address: opt(uci, 'main', 'tun_dns_address'),
			udp_mapping: opt(uci, 'main', 'udp_mapping'),
			udp_filtering: opt(uci, 'main', 'udp_filtering'),
			udp_nat_max: opt(uci, 'main', 'udp_nat_max'),
			cn_ip_fallback: opt(uci, 'main', 'cn_ip_fallback'),
			sniffer_advanced_mode: opt(uci, 'main', 'sniffer_advanced_mode'),
			/* The "do not block startup on the first rule-set download"
			 * opt-in.  Listed here because this object is an EXPLICIT key
			 * list: a field the generators read off dm.general that is not
			 * in it does not read as "absent", it reads as "never set" - and
			 * with a `|| '0'` fallback in context.uc that is indistinguishable
			 * from a user who left it off.  The first version of the feature
			 * added the option to /etc/config/homeproxy-pro and read it in
			 * context.uc, and nothing anywhere said the key was missing: the
			 * configuration generated cleanly, `sing-box check` passed, and the
			 * feature simply never turned on.  Guard 53 now compares the two
			 * lists so that class cannot come back quietly. */
			main_urltest_nodes: opt(uci, 'main', 'main_urltest_nodes') || [],
			main_urltest_interval: opt(uci, 'main', 'main_urltest_interval'),
			main_urltest_tolerance: opt(uci, 'main', 'main_urltest_tolerance'),
			main_udp_urltest_nodes: opt(uci, 'main', 'main_udp_urltest_nodes') || [],
			main_udp_urltest_interval: opt(uci, 'main', 'main_udp_urltest_interval'),
			main_udp_urltest_tolerance: opt(uci, 'main', 'main_udp_urltest_tolerance')
		};

		/* udp_timeout lives on two UCI sections: routing.udp_timeout
		 * (custom mode) and infra.udp_timeout (everything else). Mirror
		 * that split here so A2 can read either path without falling back
		 * to uci.get(). */
		config.infra = load_settings(uci, SECTION.infra, [
			'common_port', 'mixed_port', 'redirect_port', 'tproxy_port',
			'dns_port', 'dns_redirect',
			'tun_name', 'tun_addr4', 'tun_addr6', 'tun_mtu',
			'table_mark', 'self_mark', 'tproxy_mark', 'tun_mark',
			'ntp_server', 'udp_timeout'
		]);

		uci.foreach(UCICONFIG, SECTION.node, (section) => {
			const get = (name) => node_opt(uci, section['.name'], name);

			push(config.nodes, Node.create({
				id: section['.name'],
				name: get('label') || section['.name'],
				type: get('type'),
				address: get('address'),
				port: get('port'),
				common: load_common(get),
				credentials: load_credentials(get, get('type')),
				tls: load_tls(get),
				transport: load_transport(get),
				multiplex: load_multiplex(get),
				protocol_options: load_protocol_options(get, get('type'))
			}));
		});

		config.dns = load_dns(uci);
		config.routing = load_routing(uci);
		config.access_control = load_access_control(uci);
		config.server = load_server(uci);

		return config;
	}
};
