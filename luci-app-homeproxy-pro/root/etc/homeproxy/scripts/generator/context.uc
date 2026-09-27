/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * GenerationContext: the routing-mode/proxy-mode scalars every section
 * builder consumes, built as a *pure* function of the domain model plus a
 * small, explicit environment record.
 *
 *     build_context(dm, env) -> ctx
 *
 *     env = {
 *         wan_dns,              the WAN resolver the CLI resolved via ubus
 *         direct_domain_list,   /etc/homeproxy/resources/direct_list.txt
 *         proxy_domain_list,    /etc/homeproxy/resources/proxy_list.txt
 *     }
 *
 * Why the split exists: this module used to sit inside generator/client.uc
 * and resolve `env` itself - it called `ubus network.interface status` for
 * the WAN DNS and `readfile()` for the two resource lists. The generator was
 * documented as a pure function while depending on live router state, so
 * "generate the same config twice" was not guaranteed. That is what made
 * reload's preflight generation and start_service's generation two different
 * artifacts in principle: the WAN lease can change between them.
 *
 * Now the impure part (ubus call, resource read, mode-dependent fallback for
 * a router with no lease) belongs to the CLI shells - scripts/
 * generate_client.uc and scripts/generate_server.uc - which are the
 * process-level boundary and already own the atomic write and
 * `sing-box check`. Everything under generator/ is a pure function of its
 * arguments, which tests/arch-guard.sh enforces (guard 27: no ubus/fs import
 * in generator/).
 *
 * `env` is allowed to be partial. A missing wan_dns still yields the same
 * public fallback the pre-split code used, as a pure function of the routing
 * mode - not a probe - so a caller that has no ubus keeps producing a valid
 * config instead of failing.
 */

'use strict';

import { isEmpty, strToInt } from '../homeproxy.uc';

/* Build the routing-mode-independent ctx the section builders consume.
 * Mode-dependent defaults are filled in here so each builder can stay a
 * straight consumer of its fields without recomputing them. */
export function build_context(dm, env) {
	const routing_mode = dm.general.routing_mode || 'bypass_mainland_china';
	const proxy_mode = dm.general.proxy_mode || 'redirect_tproxy';

	/* Mode-shared scalars */
	const ipv6_support = dm.general.ipv6_support || '0';
	const log_level = dm.general.log_level || 'warn';
	const ntp_server = dm.infra.ntp_server || 'time.apple.com';
	const dns_port = dm.infra.dns_port || '5333';
	const mixed_port = dm.infra.mixed_port || '5330';
	const udp_timeout = (routing_mode === 'custom')
		? (dm.routing.settings.udp_timeout)
		: dm.infra.udp_timeout;

	/* self_mark is intentionally null for proxy_mode 'tun' only:
	 * the DNS server detour (default-dns / system-dns / china-dns) is
	 * gated on it, and the old generator kept the same code shape -
	 * any non-empty string is truthy, so the test fixture's
	 * self_mark='100' would leak a 'detour: direct-out' onto every
	 * DNS server when proxy_mode is tun. removeBlankAttrs() then
	 * strips the null detour, so the generated JSON stays identical
	 * to the pre-refactor output. */
	const self_mark = match(proxy_mode, /redirect/)
		? (dm.infra.self_mark || '100') : null;

	/* proxy-mode-derived ports / TUN params */
	let redirect_port, tproxy_port, tun_name, tun_addr4, tun_addr6,
	    tun_mtu, tcpip_stack, endpoint_independent_nat;
	if (match(proxy_mode, /redirect/))
		redirect_port = dm.infra.redirect_port || '5331';
	if (match(proxy_mode, /tproxy/))
		if ((dm.general.main_udp_node || 'nil') !== 'nil' || routing_mode === 'custom')
			tproxy_port = dm.infra.tproxy_port || '5332';
	if (match(proxy_mode, /tun/)) {
		tun_name = dm.infra.tun_name || 'singtun0';
		tun_addr4 = dm.infra.tun_addr4 || '172.19.0.1/30';
		tun_addr6 = dm.infra.tun_addr6 || 'fdfe:dcba:9876::1/126';
		tun_mtu = dm.infra.tun_mtu || '9000';
		tcpip_stack = 'system';
		if (routing_mode === 'custom') {
			tcpip_stack = dm.routing.settings.tcpip_stack || 'system';
			endpoint_independent_nat = dm.routing.settings.endpoint_independent_nat;
		}
	}

	/* The WAN resolver is an input, not a lookup. See the module header for
	 * the fallback's provenance - it is the same mode-dependent public
	 * resolver the pre-split generator chose when ubus had nothing to say. */
	const wan_dns = !isEmpty(env.wan_dns)
		? env.wan_dns
		: ((routing_mode in ['proxy_mainland_china', 'global']) ? '8.8.8.8' : '223.5.5.5');

	/* dns/routing fields used by both sections */
	const dns_optimistic_cache = (dm.dns.settings || {}).optimistic_cache || '0';
	const dns_optimistic_timeout = (dm.dns.settings || {}).optimistic_timeout;
	const dns_query_timeout = (dm.dns.settings || {}).dns_timeout;
	const dns_store_dns = (dm.dns.settings || {}).cache_file_store_dns || '0';

	const tun_dns_mode_raw = dm.general.tun_dns_mode,
	      tun_dns_address = dm.general.tun_dns_address,
	      udp_mapping_raw = dm.general.udp_mapping,
	      udp_filtering_raw = dm.general.udp_filtering,
	      udp_nat_max = strToInt(dm.general.udp_nat_max);

	const tun_dns_mode = (tun_dns_mode_raw === 'default') ? '' : tun_dns_mode_raw,
	      udp_mapping = (udp_mapping_raw === 'default') ? '' : udp_mapping_raw,
	      udp_filtering = (udp_filtering_raw === 'default') ? '' : udp_filtering_raw;

	/* Routing-mode-dependent defaults */
	const ctx = {
		routing_mode, proxy_mode, ipv6_support, log_level,
		self_mark, ntp_server, dns_port, mixed_port,
		redirect_port, tproxy_port,
		tun_name, tun_addr4, tun_addr6, tun_mtu,
		tcpip_stack, endpoint_independent_nat,
		udp_timeout, udp_mapping, udp_filtering, udp_nat_max,
		tun_dns_mode, tun_dns_address,
		wan_dns, dns_optimistic_cache, dns_optimistic_timeout,
		dns_query_timeout, dns_store_dns,
		default_interface: (dm.access_control.control || {}).bind_interface,

		/* udp/tcp shaping knobs the endpoint builder reads */
		endpoint_options: {
			udp_mapping, udp_filtering, udp_nat_max
		},

		/* Routing-mode-specific scalars; the dns/route modules consult
		 * only the fields their branch needs.
		 *
		 * The main-node reference is mode-dependent, and custom routing has
		 * its own outbound/rule tables (routing.default_outbound plus the
		 * routing_node / routing_rule / ruleset sections).  A residual
		 * config.main_node must therefore not switch the generator back to
		 * the preset path: LuCI hides that field in custom mode but does not
		 * clear it (`rmempty = false`), so a router that was configured in a
		 * preset mode and then switched to custom keeps the old value in
		 * UCI - and the pre-refactor code read it only when the mode was not
		 * custom.  Reading it here anyway silently dropped every custom
		 * routing rule and made route.final 'main-out'. */
		main_node: (routing_mode === 'custom') ? null : dm.general.main_node,
		main_udp_node: (routing_mode === 'custom') ? null : dm.general.main_udp_node,
		/* Custom-only scalars.  The gate is not cosmetic: route.uc picks its
		 * branch with `isEmpty(default_outbound)` and outbound.uc does the
		 * same, while the preset branch keys off main_node.  A residual
		 * default_outbound from an earlier custom configuration therefore
		 * switched a preset-mode router onto the custom branch with the
		 * preset DNS builder bailing out (it keys off main_node) - the DNS
		 * block then ended up with only default-dns/system-dns and no
		 * main-dns/china-dns, the route block with leftover custom rules -
		 * and the rule-set tags those rules reference are only built in
		 * custom mode, so `sing-box check` rejected the whole generation.
		 * Preset modes read custom-only fields nowhere; gate them all. */
		default_outbound: (routing_mode === 'custom') ? (dm.routing.settings || {}).default_outbound : null,
		default_outbound_dns: (routing_mode === 'custom')
			? ((dm.routing.settings || {}).default_outbound_dns || 'default-dns') : null,
		domain_strategy: (routing_mode === 'custom') ? (dm.routing.settings || {}).domain_strategy : null,
		find_neighbor: (routing_mode === 'custom') ? (dm.routing.settings || {}).find_neighbor : null,

		/* Main-line defaults, mirroring what the pre-refactor
		 * generate_client.uc did inline: an empty UCI value becomes 'wan'
		 * for the main DNS server, and 'wan' - the value the UI writes for
		 * "WAN DNS (read from interface)" - is replaced by the resolver the
		 * CLI read off the WAN interface (`wan_dns`, which itself falls back
		 * to a public resolver when ubus has no answer).  Leaving the
		 * literal 'wan' in place makes sing-box resolve a host by that name.
		 * The China DNS server falls back to the Aliyun public resolver
		 * instead of leaking into the default-dns pipeline. */
		dns_server: (isEmpty(dm.general.dns_server) || dm.general.dns_server === 'wan')
			? wan_dns : dm.general.dns_server,
		china_dns_server: (dm.general.china_dns_server && dm.general.china_dns_server !== 'wan')
			? dm.general.china_dns_server : '223.5.5.5',
		/* dns_default_strategy: in proxy mode, ipv4_only is the safe
		 * default whenever ipv6_support is off; in custom mode the
		 * UCI default_strategy field is the source of truth (no
		 * implicit fallback - missing UCI => strategy: null =>
		 * removeBlankAttrs strips it). */
		dns_default_strategy: (routing_mode === 'custom')
			? (dm.dns.settings || {}).default_strategy
			: ((ipv6_support !== '1') ? 'ipv4_only' : null),
		cn_ip_fallback: dm.general.cn_ip_fallback,
		main_urltest_nodes: dm.general.main_urltest_nodes || [],
		main_urltest_interval: dm.general.main_urltest_interval,
		main_urltest_tolerance: dm.general.main_urltest_tolerance,
		main_udp_urltest_nodes: dm.general.main_udp_urltest_nodes || [],
		main_udp_urltest_interval: dm.general.main_udp_urltest_interval,
		main_udp_urltest_tolerance: dm.general.main_udp_urltest_tolerance,

		/* Custom-mode DNS settings */
		dns_default_server: (dm.dns.settings || {}).default_server,
		dns_disable_cache: (dm.dns.settings || {}).disable_cache,
		dns_disable_cache_expire: (dm.dns.settings || {}).disable_cache_expire,
		dns_client_subnet: (dm.dns.settings || {}).client_subnet,
	};

	/* Inline static rule-sets (direct-domain, proxy-domain) only fire
	 * when the routing mode has a non-empty domain list. Both lists are
	 * inputs now: the CLI reads the two files under
	 * /etc/homeproxy/resources/ and passes them in. Custom mode ignores
	 * them entirely, exactly as the pre-split read did. */
	ctx.direct_domain_list = [];
	ctx.proxy_domain_list = [];
	if (routing_mode !== 'custom') {
		ctx.direct_domain_list = env.direct_domain_list || [];
		ctx.proxy_domain_list = env.proxy_domain_list || [];
	}

	/* `dedicated_udp_node` means main_udp_node was set to a different
	 * proxy-able node than main_node (the 'same'/'nil' sentinels don't
	 * qualify). Kept on ctx so both build_outbounds and build_route
	 * see the same value. */
	ctx.dedicated_udp_node = !isEmpty(ctx.main_udp_node) && !(ctx.main_udp_node in ['same', ctx.main_node]);

	return ctx;
};
