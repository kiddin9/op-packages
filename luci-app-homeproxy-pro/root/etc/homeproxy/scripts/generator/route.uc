/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 *     generator/route.uc: build the sing-box `route` block.
 *
 * The route block has the same routing-mode split as the DNS block:
 *
 *   proxy mode  - dns-in hijack, sniff, the bypass_mainland_china
 *                 resolve + geoip-cn split, dedicated UDP route,
 *                 main_override route-options, main-out final,
 *                 plus the static inline + remote rule_sets
 *                 (direct-domain / proxy-domain / geoip-cn /
 *                 geosite-cn).
 *   custom mode - the user-defined routing_node -> outbound graph,
 *                 routing_rule iteration with the 1.14 action-specific
 *                 fields, find_neighbor, the optional resolve prefix,
 *                 final_outbound resolution, final_override
 *                 route-options, and the rule_set user-defined loop
 *                 (the loop itself is in ruleset.uc).
 *
 * The orchestrator owns config.route.rule_set: route.uc may push static
 * entries (proxy mode), ruleset.uc may push user entries (custom mode),
 * and build_http_clients() runs at the end to normalise the legacy
 * download_detour into 1.14's http_clients / http_client pairing.
 */

'use strict';

import { isEmpty, strToInt, strToTime, strToBool, parse_port } from '../homeproxy.uc';


import { get_outbound, get_resolver, get_ruleset, get_direct_override } from './common.uc';

/* --- shared initial block (every routing mode) ------------------------- */

/* Initialise config.route with the always-on rules and the defaults
 * that every mode shares (dns-in hijack, sniff, optional auto_detect).
 * The caller must have created an empty config.route; we mutate it.
 *
 * Sniff tuning follows §2.7 of docs/linux.json 与 pro 的差距分析.md:
 * the default rule is the conservative 300ms / unconstrained sniffer list
 * (tutorial demo recommends 100ms + ['http','tls','stun','quic','dns'],
 * which costs less CPU but is a behaviour change). sniffer_advanced_mode
 * is the opt-in switch that flips to the tutorial profile. */
function initRoute(config, ctx) {
	const sniff_rule = (ctx.sniffer_advanced_mode === '1')
		? {
			action: 'sniff',
			sniffer: ['http', 'tls', 'stun', 'quic', 'dns'],
			timeout: '100ms'
		}
		: {
			action: 'sniff',
			timeout: '300ms'
		};
	config.route = {
		rules: [
			{
				inbound: 'dns-in',
				action: 'hijack-dns'
			},
			sniff_rule
		],
		rule_set: [],
		auto_detect_interface: isEmpty(ctx.default_interface) ? true : null,
		default_interface: ctx.default_interface
	};
}

/* --- proxy mode route rules + rule_set --------------------------------- */

function build_route_proxy(config, dm, ctx, direct_overrides) {
	/* Resolve outbound server domains through the WAN default resolver.
	   Do not use china-dns here: china-dns is for resolving mainland China
	   destinations, not the proxy node itself. Coupling node bootstrap to
	   china_dns_server can break dialing when that resolver is polluted or
	   unsuitable for the node domain. */
	config.route.default_domain_resolver = {
		server: 'default-dns',
		strategy: (ctx.ipv6_support !== '1') ? 'prefer_ipv4' : null
	};

	/* Direct list */
	if (length(ctx.direct_domain_list))
		push(config.route.rules, {
			rule_set: 'direct-domain',
			action: 'route',
			outbound: 'direct-out'
		});

	/* Bypass CN traffic: resolve the destination first, then route by IP.
	   sing-box does not match an IP-based rule set (geoip-cn) against a domain
	   destination unless it is resolved first, so add an explicit resolve
	   action; geoip-cn then sends China IPs to direct and everything else falls
	   through to main-out (proxy). This avoids relying on the geosite-* domain
	   lists, which can mis-classify foreign domains (e.g. Google's gvt2.com
	   beacons) as "cn" and send them direct to time out. Keep the direct-domain
	   fast-path above for known direct domains. */
	if (ctx.routing_mode === 'bypass_mainland_china') {
		push(config.route.rules, {
			action: 'resolve',
			strategy: (ctx.ipv6_support !== '1') ? 'prefer_ipv4' : null
		});
		push(config.route.rules, {
			rule_set: 'geoip-cn',
			action: 'route',
			outbound: 'direct-out'
		});
	}

	/* Main UDP out */
	if (ctx.dedicated_udp_node) {
		const udp_override = direct_overrides[ctx.main_udp_node] || null;
		push(config.route.rules, {
			network: 'udp',
			action: 'route',
			outbound: 'main-udp-out',
			override_address: udp_override ? udp_override.override_address : null,
			override_port: udp_override ? udp_override.override_port : null
		});
	}

	/* Direct-node destination override, emitted as route-options action
	   (direct outbound options removed since sing-box 1.13) */
	const main_override = direct_overrides[ctx.main_node] || null;
	if (main_override)
		push(config.route.rules, {
			action: 'route-options',
			override_address: main_override.override_address,
			override_port: main_override.override_port
		});

	config.route.final = 'main-out';

	/* --- proxy-mode rule_set block ----------------------------------- */

	/* Direct list */
	if (length(ctx.direct_domain_list))
		push(config.route.rule_set, {
			type: 'inline',
			tag: 'direct-domain',
			rules: [
				{
					domain_keyword: ctx.direct_domain_list,
				}
			]
		});

	/* Proxy list */
	if (length(ctx.proxy_domain_list))
		push(config.route.rule_set, {
			type: 'inline',
			tag: 'proxy-domain',
			rules: [
				{
					domain_keyword: ctx.proxy_domain_list,
				}
			]
		});

	if (ctx.routing_mode === 'bypass_mainland_china') {
		/*
		 * Fetched straight from the upstream SagerNet repositories and
		 * downloaded through the selected node. A direct fetch depends on
		 * the CDN staying reachable from mainland China, where DNS pollution
		 * makes it fail intermittently; the files total ~250 KB per
		 * day, so proxying the download costs almost nothing.
		 *
		 * Only geosite-cn and geoip-cn are emitted: they are the two the
		 * DNS and route blocks actually reference.  A third geosite-noncn
		 * used to be declared here as well, but no rule ever referenced it -
		 * sing-box creates (and keeps updating, and holds in memory) every
		 * declared rule-set regardless of use, so it was a daily ~100 KB
		 * download through the proxy for nothing.
		 */
		push(config.route.rule_set, {
			type: 'remote',
			tag: 'geoip-cn',
			format: 'binary',
			url: 'https://raw.githubusercontent.com/SagerNet/sing-geoip/rule-set/geoip-cn.srs',
			update_interval: '24h',
			download_detour: 'main-out'
		});
		push(config.route.rule_set, {
			type: 'remote',
			tag: 'geosite-cn',
			format: 'binary',
			url: 'https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-geolocation-cn.srs',
			update_interval: '24h',
			download_detour: 'main-out'
		});
	}

	if (isEmpty(config.route.rule_set))
		config.route.rule_set = null;
}

/* --- custom-mode route rules ------------------------------------------- */

function build_route_custom(config, dm, ctx, direct_overrides) {
	config.route.default_domain_resolver = {
		server: get_resolver(ctx.default_outbound_dns, dm)
	};

	if (ctx.find_neighbor === '1')
		config.route.find_neighbor = true;

	if (ctx.domain_strategy)
		push(config.route.rules, {
			action: 'resolve',
			strategy: ctx.domain_strategy
		});

	for (let cfg in dm.routing.rules) {
		if (!cfg.enabled)
			continue;

		const rule_outbound = get_outbound(cfg.outbound, dm);
		const rule_direct_override = get_direct_override(cfg.outbound, dm, direct_overrides);
		let rule_override_address = cfg.override_address,
		    rule_override_port = strToInt(cfg.override_port);
		if (isEmpty(rule_override_address) && isEmpty(rule_override_port) && rule_direct_override) {
			rule_override_address = rule_direct_override.override_address;
			rule_override_port = rule_direct_override.override_port;
		}

		/* sing-box routing rule: emit match fields plus action-specific fields.
		   client is the sniffed client type (only set with protocol quic/ssh);
		   resolve adds server/strategy/disable_cache/rewrite_ttl/client_subnet;
		   reject adds method/no_drop. Emitted conditionally so a given action
		   never carries fields sing-box rejects for it. */
		const rule = {
			ip_version: strToInt(cfg.ip_version),
			protocol: cfg.protocol,
			network: cfg.network,
			client: cfg.client,
			domain: cfg.domain,
			domain_suffix: cfg.domain_suffix,
			domain_keyword: cfg.domain_keyword,
			domain_regex: cfg.domain_regex,
			source_ip_cidr: cfg.source_ip_cidr,
			source_ip_is_private: strToBool(cfg.source_ip_is_private),
			ip_cidr: cfg.ip_cidr,
			ip_is_private: strToBool(cfg.ip_is_private),
			source_port: parse_port(cfg.source_port),
			source_port_range: cfg.source_port_range,
			port: parse_port(cfg.port),
			port_range: cfg.port_range,
			process_name: cfg.process_name,
			process_path: cfg.process_path,
			process_path_regex: cfg.process_path_regex,
			user: cfg.user,
			rule_set: get_ruleset(cfg.rule_set, dm),
			rule_set_ip_cidr_match_source: strToBool(cfg.rule_set_ip_cidr_match_source),
			invert: strToBool(cfg.invert),
			action: cfg.action,
			source_mac_address: cfg.source_mac_address,
			source_hostname: cfg.source_hostname
		};

		/* Route-option fields belong to the actions that dial out (`route` and
		 * `route-options`).  They used to be assigned unconditionally, which
		 * stayed invisible as long as the UI kept them hidden per action - but
		 * changing a rule's action leaves the previous values in UCI, and
		 * sing-box then refuses the whole configuration with "unknown field" on
		 * the first one the new action does not take. */
		if (cfg.action !== 'resolve' && cfg.action !== 'reject') {
			rule.outbound = rule_outbound;
			rule.override_address = rule_override_address;
			rule.override_port = rule_override_port;
			rule.udp_disable_domain_unmapping = strToBool(cfg.udp_disable_domain_unmapping);
			rule.udp_connect = strToBool(cfg.udp_connect);
			rule.udp_timeout = strToTime(cfg.udp_timeout);
			rule.tls_fragment = strToBool(cfg.tls_fragment);
			rule.tls_fragment_fallback_delay = strToTime(cfg.tls_fragment_fallback_delay);
			rule.tls_record_fragment = strToBool(cfg.tls_record_fragment);
			rule.tls_spoof = cfg.tls_spoof || null;
			rule.tls_spoof_method = cfg.tls_spoof_method || null;
		}

		if (cfg.action === 'resolve') {
			rule.server = get_resolver(cfg.resolve_server, dm);
			rule.strategy = cfg.resolve_strategy;
			rule.disable_cache = strToBool(cfg.resolve_disable_cache);
			rule.disable_optimistic_cache = strToBool(cfg.resolve_disable_optimistic_cache);
			rule.rewrite_ttl = strToInt(cfg.resolve_rewrite_ttl);
			rule.timeout = strToTime(cfg.resolve_timeout);
			rule.client_subnet = cfg.resolve_client_subnet;
		}
		if (cfg.action === 'reject') {
			rule.method = cfg.reject_method;
			rule.no_drop = strToBool(cfg.reject_no_drop);
		}
		push(config.route.rules, rule);
	}

	/* Direct-node destination override, emitted as route-options action
	   (direct outbound options removed since sing-box 1.13) */
	const final_override = get_direct_override(ctx.default_outbound, dm, direct_overrides);
	if (final_override)
		push(config.route.rules, {
			action: 'route-options',
			override_address: final_override.override_address,
			override_port: final_override.override_port
		});

	config.route.final = get_outbound(ctx.default_outbound, dm);
}

/* --- public entry ------------------------------------------------------ */

export function build_route(config, dm, ctx, direct_overrides) {
	initRoute(config, ctx);

	if (!isEmpty(ctx.main_node))
		build_route_proxy(config, dm, ctx, direct_overrides);
	else if (!isEmpty(ctx.default_outbound))
		build_route_custom(config, dm, ctx, direct_overrides);

	return config;
};