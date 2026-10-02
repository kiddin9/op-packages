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

import { isEmpty, strToInt, strToTime, strToBool, parse_port, HP_DIR } from '../homeproxy-pro.uc';

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
		/* auto_detect_interface: explicit true when the user did not
		 * pin a default_interface, explicit false when they did - not
		 * null (the previous "null means no field" shape silently kept
		 * the auto-detect on when the user expected it off). */
		auto_detect_interface: isEmpty(ctx.default_interface) ? true : false,
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

	/* Split by destination IP, in both directions.
	 *
	 * sing-box does not match an IP-based rule set (geoip-cn) against a
	 * domain destination unless it is resolved first, so an explicit resolve
	 * action comes first.  Which way the split points is the mode's default
	 * policy (ctx.proxy_fallback):
	 *
	 *   bypass/global/gfwlist  mainland -> direct, the rest falls through to
	 *                          main-out (proxy)
	 *   proxy_mainland_china   mainland -> proxy, the rest falls through to
	 *                          direct-out
	 *
	 * Using geoip-cn rather than the geosite-* domain lists is deliberate:
	 * those mis-classify foreign domains (Google's gvt2.com beacons) as "cn"
	 * and would send them direct to time out.  Keep the direct-domain
	 * fast-path above for known direct domains. */
	if (ctx.routing_mode === 'bypass_mainland_china'
		|| ctx.routing_mode === 'proxy_mainland_china') {
		push(config.route.rules, {
			action: 'resolve',
			strategy: (ctx.ipv6_support !== '1') ? 'prefer_ipv4' : null
		});
		push(config.route.rules, {
			rule_set: 'geoip-cn',
			action: 'route',
			outbound: ctx.proxy_fallback ? 'direct-out' : 'main-out'
		});
	}
	if (ctx.routing_mode === 'bypass_mainland_china') {
		/* geoip-cn.srs is upstream's list; the firewall's mainland set is
		 * built from our own china_ip4.txt (firewall_post.ut reads it
		 * directly).  The two disagree - the bundled list has 8.152.0.0/13
		 * (Alibaba Cloud) and geoip-cn.srs does not - so a connection into
		 * that range passes the firewall as "not mainland" and would then be
		 * sent direct by the rule above instead of to the proxy.  This local
		 * rule-set is generated from the same china_ip4.txt, which is what
		 * makes both sides decide from one list.  In
		 * proxy_mainland_china it is not needed twice: the geoip-cn rule
		 * already selects the mainland side for the proxy. */
		push(config.route.rules, {
			rule_set: 'china-ip',
			action: 'route',
			outbound: 'direct-out'
		});

		/* IPv6 half of the same split, and the reason a mainland site opened
		 * over IPv6 used to go through the proxy even with IPv6 support on.
		 * geoip-cn.srs carries no IPv6 and china_ip4.json is generated from an
		 * IPv4 list, so a destination that resolved to an AAAA address matched
		 * neither and fell through to `final` - which in this mode is main-out.
		 * The rule is emitted in both mainland modes (unlike china-ip, which
		 * proxy_mainland_china does not need twice because geoip-cn already
		 * picks the mainland side there): with no IPv6 in geoip-cn there is
		 * nothing left to pick it, so the side has to be named explicitly.
		 * `prefer_ipv4` on the resolve rule above is what lets both families
		 * through - it biases, it does not filter. */
		if (ctx.ipv6_support === '1' && ctx.china_ip6_ready) {
			push(config.route.rules, {
				rule_set: 'china-ip6',
				action: 'route',
				outbound: ctx.proxy_fallback ? 'direct-out' : 'main-out'
			});
		}
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

	/* The route half of the mode's default policy - the other consumer of
	 * ctx.proxy_fallback, and the reason dns.final and this line are
	 * asserted together per mode. */
	config.route.final = ctx.proxy_fallback ? 'main-out' : 'direct-out';

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

	/* Both mainland modes split on geoip-cn, so both need it declared - it is
	 * what the route rule added above matches.  `proxy_mainland_china` used
	 * to reach this point without it and sing-box refused the whole config
	 * with "initialize rule[3]: rule-set not found: geoip-cn", which the
	 * health gate turned into a rollback and an unproxied network. */
	if (ctx.routing_mode === 'bypass_mainland_china'
		|| ctx.routing_mode === 'proxy_mainland_china') {
		/*
		 * Fetched straight from the upstream SagerNet repositories and
		 * downloaded through the selected node. A direct fetch depends on
		 * the CDN staying reachable from mainland China, where DNS pollution
		 * makes it fail intermittently; the files total ~250 KB per
		 * day, so proxying the download costs almost nothing.
		 *
		 * Both rule_sets are emitted, but they are consumed by different
		 * blocks:
		 *
		 *   geoip-cn  - referenced by the route rule above to split
		 *               destinations by IP: mainland -> direct-out in
		 *               bypass_mainland_china, mainland -> main-out in
		 *               proxy_mainland_china.
		 *   geosite-cn - referenced only by the DNS rule in
		 *               generator/dns.uc (rule_set: geosite-cn ->
		 *               server: china-dns); the route layer never matches
		 *               it. Sing-box still loads and keeps the rule-set in
		 *               memory even when only one block references it, so
		 *               removing it would also break the DNS split.  It is
		 *               only declared for bypass_mainland_china because that
		 *               is the only mode whose DNS chain routes through
		 *               china-dns.
		 *
		 * History: a third geosite-noncn used to be declared here as well,
		 * but no rule referenced it and sing-box still loaded and updated
		 * it daily, so it was removed (the comment above was rewritten
		 * during the 2026-09-29 review to clarify that geosite-cn is still
		 * in use - the DNS side - just not from this block).
		 */
		push(config.route.rule_set, {
			type: 'remote',
			tag: 'geoip-cn',
			format: 'binary',
			url: 'https://v4.gh-proxy.org/https://raw.githubusercontent.com/SagerNet/sing-geoip/rule-set/geoip-cn.srs',
			update_interval: '24h',
			download_detour: 'main-out'
		});
		push(config.route.rule_set, {
			type: 'remote',
			tag: 'geosite-cn',
			format: 'binary',
			url: 'https://v4.gh-proxy.org/https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-geolocation-cn.srs',
			update_interval: '24h',
			download_detour: 'main-out'
		});

		/* Local, and not downloaded: it is generated from the same
		 * china_ip4.txt the firewall renders homeproxy_mainland_addr_v4
		 * from, so the two cannot drift apart.  `type: local` is watched by
		 * sing-box with fswatch, so when the resource updater replaces the
		 * file the running instance reloads it in place - no restart and,
		 * more importantly, no second copy of the list to keep in sync. */
		push(config.route.rule_set, {
			type: 'local',
			tag: 'china-ip',
			path: HP_DIR + '/resources/china_ip4.json'
		});

		/* The IPv6 counterpart, from china_ip6.txt - the same list the
		 * firewall renders homeproxy_mainland_addr_v6 from, and the only
		 * IPv6 mainland data either side of the split has.  Declared only
		 * when the file is actually there: a rule_set pointing at a missing
		 * file takes the whole config down with it, and a router whose v6
		 * list is unusable must still start (the firewall has already
		 * degraded to passing IPv6 through, with a warning). */
		if (ctx.ipv6_support === '1' && ctx.china_ip6_ready) {
			push(config.route.rule_set, {
				type: 'local',
				tag: 'china-ip6',
				path: HP_DIR + '/resources/china_ip6.json'
			});
		}
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

		/* `route-options` only takes the override_* fields; `outbound` is the
		 * `route` action's field.  The two used to share one branch and
		 * `route-options` ended up carrying an `outbound` sing-box then
		 * refused as "unknown field" - the configuration as a whole was
		 * rejected and the user only saw "setting did not take".
		 * Match fields above are valid for every action, so the gates below
		 * cover the action-specific payload only. */
		if (cfg.action === 'route' || cfg.action === 'route-options') {
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
		/* `route` alone is the action that picks a destination - `route-options`
		 * adjusts the existing connection, so it does not take `outbound`. */
		if (cfg.action === 'route')
			rule.outbound = rule_outbound;

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