#!/usr/bin/ucode
/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * Stage A1.2 domain-model test: assert that Loader.load(fixture) populates
 * every HomeProxyConfig sub-object from the corresponding UCI section(s).
 *
 *   general            <- config (single)
 *   infra              <- infra (single)
 *   nodes              <- node (list)
 *   dns                <- dns (single) + dns_server (list) + dns_rule (list)
 *   routing            <- routing (single) + routing_node / routing_rule /
 *                        ruleset (lists)
 *   access_control     <- control (single) + subscription (single)
 *   server             <- server (single) + server (list)
 *   endpoints          <- DERIVED (stays {}; A3 / A4 fill it)
 *
 * The fixture (tests/fixtures/generators/domain.uci) carries at least one
 * row per section so the assertions exercise both single-section reads
 * and list reads, plus list-valued options (`wan_proxy_ipv4_ips`,
 * `filter_keywords`, `subscription_url`).
 *
 * Run from tests/ucode/run.sh, which stages this file next to a scratch
 * homeproxy-pro.uc and config/loader.uc + config/model.uc.
 */

'use strict';

import { Loader } from './config/loader.uc';
import { Config, Node, ConfigQuery } from './config/model.uc';

let failures = 0;
let checks = 0;

function expect(name, actual, expected) {
	checks++;
	if (sprintf('%J', actual) !== sprintf('%J', expected)) {
		printf('FAIL %s: expected %J, got %J\n', name, expected, actual);
		failures++;
	}
}

function expect_null(name, value) {
	checks++;
	if (value !== null && value !== undefined) {
		printf('FAIL %s: expected null, got %J\n', name, value);
		failures++;
	}
}

function by_id(items, id) {
	for (let it in items)
		if (it.id === id)
			return it;
	return null;
}

const config = Loader.load('./config');

/* --- general --------------------------------------------------------- */
expect('general.routing_mode', config.general.routing_mode, 'bypass_mainland_china');
expect('general.proxy_mode', config.general.proxy_mode, 'redirect_tproxy');
expect('general.main_node', config.general.main_node, 'urltest');
expect('general.main_udp_node', config.general.main_udp_node, 'nil');
expect('general.ipv6_support', config.general.ipv6_support, '0');

/* --- infra ----------------------------------------------------------- */
expect('infra.dns_port', config.infra.dns_port, '5333');
expect('infra.mixed_port', config.infra.mixed_port, '5330');
expect('infra.self_mark', config.infra.self_mark, '100');
expect('infra.tun_name', config.infra.tun_name, 'singtun0');
expect('infra.tproxy_mark', config.infra.tproxy_mark, '101');
expect('infra.tun_addr4', config.infra.tun_addr4, '172.19.0.1/30');
expect('infra.ntp_server', config.infra.ntp_server, 'time.apple.com');
expect('infra.common_port', config.infra.common_port, '22,53,80,443');

/* --- nodes ----------------------------------------------------------- */
expect('nodes.length', length(config.nodes), 2);

const n_anytls = by_id(config.nodes, 'n_anytls');
const n_snell  = by_id(config.nodes, 'n_snell');

expect('n_anytls.type', n_anytls?.type, 'anytls');
expect('n_anytls.credentials.password', n_anytls?.credentials?.password, 'secret');
expect('n_snell.credentials.psk', n_snell?.credentials?.psk, 'psk123456789012');
expect('n_snell.credentials.userkey', n_snell?.credentials?.userkey, 'ukey');

/* --- dns ------------------------------------------------------------- */
expect('dns.settings.default_strategy', config.dns?.settings?.default_strategy, 'prefer_ipv4');
expect('dns.settings.default_server', config.dns?.settings?.default_server, 'default-dns');
expect('dns.settings.optimistic_cache', config.dns?.settings?.optimistic_cache, '0');
expect('dns.settings.dns_timeout', config.dns?.settings?.dns_timeout, '5s');
expect('dns.servers.length', length(config.dns?.servers), 1);
expect('dns.servers[0].type', config.dns?.servers?.[0]?.type, 'udp');
expect('dns.servers[0].server', config.dns?.servers?.[0]?.server, '8.8.8.8');
expect('dns.servers[0].name', config.dns?.servers?.[0]?.name, 'ds_main');
expect('dns.rules.length', length(config.dns?.rules), 1);
expect('dns.rules[0].action', config.dns?.rules?.[0]?.action, 'hijack-dns');
expect('dns.rules[0].name', config.dns?.rules?.[0]?.name, 'dr_hijack');
/* PR-01: dns_rule has `enabled '1'` in the fixture, the loader must
 * surface it as a real boolean. */
expect('dns.rules[0].enabled', config.dns?.rules?.[0]?.enabled, true);

/* PR-01: the UCI pseudo-fields (.name / .index / .type) must not
 * leak into the loaded shape - the loader drops them via
 * normalize_section(). */
for (let s in (config.dns?.servers || [])) {
	if ('.name' in s || '.index' in s || '.type' in s) {
		printf('FAIL dns.servers normalisation: pseudo-field leaked %J\n', s);
		failures++;
	}
}
checks++;
for (let r in (config.dns?.rules || [])) {
	if ('.name' in r || '.index' in r || '.type' in r) {
		printf('FAIL dns.rules normalisation: pseudo-field leaked %J\n', r);
		failures++;
	}
}
checks++;
/* PR-01: sections with `enabled` must have it coerced to boolean.
 * The fixture carries no `enabled` option on dns_server/dns_rule, so
 * `enabled` is absent rather than coerced - the check is "no
 * string-shaped `enabled` value sneaked through". */
for (let s in (config.dns?.servers || [])) {
	if ('enabled' in s && type(s.enabled) !== 'bool') {
		printf('FAIL dns.servers.enabled: not coerced to boolean, got %J\n', s.enabled);
		failures++;
	}
}
checks++;
for (let r in (config.dns?.rules || [])) {
	if ('enabled' in r && type(r.enabled) !== 'bool') {
		printf('FAIL dns.rules.enabled: not coerced to boolean, got %J\n', r.enabled);
		failures++;
	}
}
checks++;

/* absent options must NOT appear in settings */
if ('client_subnet' in (config.dns?.settings || {})) {
	printf('FAIL dns.settings.client_subnet: should be omitted, got %J\n', config.dns.settings.client_subnet);
	failures++;
}
checks++;

/* --- routing --------------------------------------------------------- */
expect('routing.settings.default_outbound', config.routing?.settings?.default_outbound, 'direct-out');
expect('routing.settings.default_outbound_dns', config.routing?.settings?.default_outbound_dns, 'default-dns');
expect('routing.settings.find_neighbor', config.routing?.settings?.find_neighbor, '0');
expect('routing.settings.udp_timeout', config.routing?.settings?.udp_timeout, '5m');
expect('routing.settings.tcpip_stack', config.routing?.settings?.tcpip_stack, 'system');

expect('routing.nodes.length', length(config.routing?.nodes), 1);
expect('routing.nodes[0].label', config.routing?.nodes?.[0]?.label, 'main');
expect('routing.nodes[0].node', config.routing?.nodes?.[0]?.node, 'urltest');

expect('routing.rules.length', length(config.routing?.rules), 1);
expect('routing.rules[0].action', config.routing?.rules?.[0]?.action, 'route');
expect('routing.rules[0].name', config.routing?.rules?.[0]?.name, 'rr_sniff');

expect('routing.rulesets.length', length(config.routing?.rulesets), 1);
expect('routing.rulesets[0].type', config.routing?.rulesets?.[0]?.type, 'remote');
expect('routing.rulesets[0].url', config.routing?.rulesets?.[0]?.url, 'https://example.com/cn.list');
expect('routing.rulesets[0].download_detour', config.routing?.rulesets?.[0]?.download_detour, 'main-out');
expect('routing.rulesets[0].name', config.routing?.rulesets?.[0]?.name, 'rs_cn');

/* PR-01: same normalisation guarantees for the routing lists. */
for (let n in (config.routing?.nodes || [])) {
	if ('.name' in n || '.index' in n || '.type' in n) {
		printf('FAIL routing.nodes normalisation: pseudo-field leaked %J\n', n);
		failures++;
	}
}
checks++;
for (let r in (config.routing?.rules || [])) {
	if ('.name' in r || '.index' in r || '.type' in r) {
		printf('FAIL routing.rules normalisation: pseudo-field leaked %J\n', r);
		failures++;
	}
}
checks++;
for (let rs in (config.routing?.rulesets || [])) {
	if ('.name' in rs || '.index' in rs || '.type' in rs) {
		printf('FAIL routing.rulesets normalisation: pseudo-field leaked %J\n', rs);
		failures++;
	}
}
checks++;
expect('routing.nodes[0].name', config.routing?.nodes?.[0]?.name, 'rn_main');

/* --- access_control -------------------------------------------------- */
expect('access_control.control.lan_proxy_mode', config.access_control?.control?.lan_proxy_mode, 'disabled');
expect_null('access_control.control.bind_interface', config.access_control?.control?.bind_interface);

expect('access_control.wan_proxy_ipv4_ips', config.access_control?.wan_proxy_ipv4_ips, ['91.108.4.0/22']);
expect('access_control.wan_proxy_ipv6_ips', config.access_control?.wan_proxy_ipv6_ips, ['2001:67c:4e8::/48']);

expect('access_control.subscription.auto_update', config.access_control?.subscription?.auto_update, '0');
expect('access_control.subscription.packet_encoding', config.access_control?.subscription?.packet_encoding, 'xudp');
expect('access_control.subscription.filter_nodes', config.access_control?.subscription?.filter_nodes, 'blacklist');
expect('access_control.subscription_urls', config.access_control?.subscription_urls, ['https://example.com/sub']);
expect('access_control.filter_keywords', config.access_control?.filter_keywords,
	['重置|到期', 'Expiration']);

/* --- server ---------------------------------------------------------- */
expect('server.settings.enabled', config.server?.settings?.enabled, '1');
expect('server.settings.log_level', config.server?.settings?.log_level, 'warn');
expect('server.inbounds.length', length(config.server?.inbounds), 1);
expect('server.inbounds[0].type', config.server?.inbounds?.[0]?.type, 'vless');
expect('server.inbounds[0].port', config.server?.inbounds?.[0]?.port, '443');
/* PR-04: server inbounds are Inbound domain objects now, so `id` is the
 * UCI section name and `name` is the user-facing label (falling back to
 * the section name). Before PR-04 they were bare normalised sections and
 * `name` held the section name. */
expect('server.inbounds[0].id', config.server?.inbounds?.[0]?.id, 's_vless');
expect('server.inbounds[0].name', config.server?.inbounds?.[0]?.name, 'server-vless');
expect('server.inbounds[0].enabled', config.server?.inbounds?.[0]?.enabled, true);

/* PR-01: server inbounds must be normalised too - no UCI pseudo-field
 * may leak into the Inbound shape. */
for (let ib in (config.server?.inbounds || [])) {
	if ('.name' in ib || '.index' in ib || '.type' in ib) {
		printf('FAIL server.inbounds normalisation: pseudo-field leaked %J\n', ib);
		failures++;
	}
}
checks++;

/* PR-04: the Inbound sub-objects must be present so the Adapter can
 * shape sing-box JSON without falling back to flat UCI reads. */
expect('server.inbounds[0].credentials.uuid', config.server?.inbounds?.[0]?.credentials?.uuid,
	'3af88561-9c69-4b19-8f7e-f08d580bc339');
expect('server.inbounds[0].tls.enabled', config.server?.inbounds?.[0]?.tls?.enabled, '1');
expect('server.inbounds[0].tls.server_name', config.server?.inbounds?.[0]?.tls?.server_name,
	'server.example.com');
expect('server.inbounds[0].protocol_options.flow', config.server?.inbounds?.[0]?.protocol_options?.flow,
	null);
expect('server.inbounds[0].common keys are the listener set',
	sort(keys(config.server?.inbounds?.[0]?.common || {})),
	sort(['bind_interface', 'reuse_addr', 'tcp_fast_open', 'tcp_multi_path',
		'udp_fragment', 'udp_timeout', 'network']));

/* --- PR-01 removed the Config.endpoints placeholder and the dead
 *     ConfigQuery.endpoints / node_ids / main_node_id helpers; the
 *     remaining helpers (node_by_id, find_by_name, main_udp_node_id)
 *     are still wired up. */
expect('main_udp_node_id', ConfigQuery.main_udp_node_id(config), 'nil');
expect('node_by_id(n_anytls).type', ConfigQuery.node_by_id(config, 'n_anytls')?.type, 'anytls');
expect('node_by_id(missing)', ConfigQuery.node_by_id(config, 'missing'), null);

/* find_by_name is exercised against the normalised routing_node list:
 * `name` is the UCI section name and the lookup must find it. */
{
	let rn = null;
	for (let n in (config.routing?.nodes || []))
		if (n.name === 'rn_main') rn = n;
	expect('find_by_name(routing.nodes, rn_main).node',
		rn?.node, 'urltest');
}

printf('%d checks, %d failures\n', checks, failures);
exit(failures === 0 ? 0 : 1);
