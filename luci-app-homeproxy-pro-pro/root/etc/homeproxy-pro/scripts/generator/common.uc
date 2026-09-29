/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 *     generator/common.uc: shared helpers used by every generator module.
 *
 * Every "select a tag from a UCI-style reference" function lives in this
 * file because the same selector logic (a routing_node name, an
 * array-of-names, a direct/block/default marker, a ruleset id list) is
 * reached by the DNS section, the route section, the outbound/endpoint
 * builder and the ruleset section. Duplicating them per-module would
 * drift; consolidating them here keeps the convention "one place to
 * change a tag shape".
 *
 * The Loader owns UCI; nothing in here reads UCI directly. The orchestrator
 * passes `dm` for the routing_node lookups that need to resolve a name into
 * the underlying node id.
 */

'use strict';

import { isEmpty } from '../homeproxy.uc';

import { ConfigQuery } from '../config/model.uc';

/* parse_port() lives in homeproxy.uc. The Adapter layer needs it
 * too (EndpointFactory builds the WireGuard endpoint) and an adapter must
 * not import from generator/, so the util moved to the module both layers
 * already share. Callers import it from '../homeproxy.uc' now. */

/* Resolve a UCI outbound-style reference (string or array of strings)
 * into the sing-box tag the generator should emit. The arrays carry
 * either 'block-out' / 'direct-out' sentinels or routing_node section
 * names; a single string is the same thing with one entry.
 *
 * `dm` is needed for the routing_node -> node id lookup; we deliberately
 * do not read `dm.routing.nodes` until we know we need it (the common
 * case is the sentinel). */
export function get_outbound(cfg, dm) {
	if (isEmpty(cfg))
		return null;

	if (type(cfg) === 'array') {
		let outbounds = [];
		for (let i in cfg)
			push(outbounds, get_outbound(i, dm));
		return outbounds;
	}

	switch (cfg) {
	case 'block-out':
	case 'direct-out':
		return cfg;
	default:
		const rn = ConfigQuery.find_by_name(dm.routing.nodes, cfg);
		if (!rn || isEmpty(rn.node))
			die(sprintf("%s's node is missing, please check your configuration.", cfg));
		else if (rn.node === 'urltest')
			return 'cfg-' + cfg + '-out';
		else
			return 'cfg-' + rn.node + '-out';
	}
};

/* Find a loaded section by name, treating `enabled` as a gate. The Loader
 * normalises `enabled` on every list section; a section with the field unset
 * is enabled (boolean sections default to 0 in UCI, but a dns_server/ruleset
 * without the option is a valid, enabled row).
 *
 * Declared before its callers on purpose: ucode resolves function references
 * at call time from what has already been evaluated, so a `function` statement
 * placed after get_resolver() fails with "access to undeclared variable". */
function find_enabled(items, name) {
	const item = ConfigQuery.find_by_name(items || [], name);
	if (!item)
		return null;
	if (item.enabled === false || item.enabled === '0')
		return null;
	return item;
};

/* Resolve a UCI resolver reference (a dns_server section name or one of
 * the sentinels) into a sing-box resolver tag.
 *
 * `dm` is required for the same reason get_outbound() needs it: a reference to
 * a section that was deleted or disabled produces `cfg-<name>-dns`, which
 * nothing defines - sing-box then rejects the whole configuration with
 * "dns server not found", the reload silently keeps the previous one, and the
 * user only sees that their change did not take. Fail with the name instead. */
export function get_resolver(cfg, dm) {
	if (isEmpty(cfg))
		return null;

	switch (cfg) {
	case 'default-dns':
	case 'system-dns':
		return cfg;
	default:
		if (dm && !find_enabled((dm.dns || {}).servers, cfg))
			die(sprintf("the DNS server '%s' does not exist or is disabled; check the rule that refers to it.", cfg));
		return 'cfg-' + cfg + '-dns';
	}
};

/* Resolve a UCI ruleset reference list (array of ruleset section names)
 * into the corresponding sing-box rule_set tag list. Same existence gate as
 * get_resolver(): ruleset.uc skips disabled entries, so a reference to one
 * would leave a dangling `cfg-<name>-rule` tag behind. */
export function get_ruleset(cfg, dm) {
	if (isEmpty(cfg))
		return null;

	let rules = [];
	for (let i in cfg) {
		if (isEmpty(i))
			continue;
		if (dm && !find_enabled((dm.routing || {}).rulesets, i))
			die(sprintf("the rule-set '%s' does not exist or is disabled; check the rule that refers to it.", i));
		push(rules, 'cfg-' + i + '-rule');
	}
	return rules;
};

/* Resolve the direct-node destination override that the route builder
 * needs for a `direct` routing_node target. The override is recorded
 * earlier by generate_outbound() (see outbound.uc) when a direct node
 * carries override_address / override_port; this helper just looks it
 * up. Returns null when the target is not a direct node or no override
 * is configured. */
export function get_direct_override(outbound_selector, dm, direct_overrides) {
	if (type(outbound_selector) === 'array' || isEmpty(outbound_selector))
		return null;

	switch (outbound_selector) {
	case 'direct-out':
	case 'block-out':
		return null;
	default:
		const rn = ConfigQuery.find_by_name(dm.routing.nodes, outbound_selector);
		const node = rn && rn.node;
		return (!isEmpty(node) && node !== 'urltest') ? (direct_overrides[node] || null) : null;
	}
};

/* True when `tag` (the sing-box outbound tag) belongs to a direct outbound.
 * Used by the http_clients builder to drop the detour field on a pure-TUN
 * setup: sing-box 1.14 rejects detouring to a direct outbound that has
 * nothing to detour through. */
export function isDirectOutboundTag(tag, dm) {
	if (isEmpty(tag) || tag === 'block-out')
		return false;
	if (tag === 'direct-out')
		return true;

	/* The caller passes the tag the generator emits - get_outbound() builds
	 * `cfg-<node>-out` - not the routing_node section name, so that wrapper has
	 * to be undone before the lookup.  Without this the two queries below were
	 * given a name that matches neither table, and the function returned false
	 * for every routing_node: build_http_clients() then kept a `detour` on a
	 * rule-set download in pure TUN mode, where sing-box refuses it ("detour to
	 * an empty direct outbound makes no sense") and rejects the whole
	 * configuration. */
	const unwrapped = match(tag, /^cfg-(.+)-out$/);
	const name = unwrapped ? unwrapped[1] : tag;

	const rn = ConfigQuery.find_by_name(dm.routing.nodes, name);
	const node_name = (rn && rn.node) || name;
	const node = ConfigQuery.node_by_id(dm, node_name);
	return !!(node && node.type === 'direct');
};

/* Append the sing-box JSON $schema field. Kept here because the value is
 * fixed and the two generators used to spell it the same way; if it ever
 * changes, both should pick up the new URL automatically. */
export function attachSchema(config) {
	config['$schema'] = 'https://sing-box.sagernet.org/schema.json';
	return config;
};

/* Attach the experimental cache_file block. Every routing mode benefits
 * from it: bypass_mainland_china and custom match a lot of DNS, and the
 * other modes still resolve the proxy node hostname and resolve any
 * domain the user clicks through. cache_file is a no-op on a fresh
 * install (no cache to read) and the file is the only piece of state the
 * generator writes outside /etc/config/homeproxy.  Routing-mode gating
 * used to limit it to bypass_mainland_china + custom, which left
 * gfwlist / proxy_mainland_china / global with cold-start DNS on every
 * reload and made the difference between modes hard to explain.
 *
 * Note: docs/linux.json 与 pro 的差距分析.md §2.5 once asked for an
 * explicit `reverse_mapping: true` here (so a future sing-box change to
 * the default would not silently move us off the mapping table). The
 * sing-box 1.14.0-r1 we test against rejects that field as
 * "json: unknown field" - the field is recognised by newer builds but
 * not the floor pinned by arch-guard 31. sing-box's default is already
 * `true`, so leaving it implicit matches runtime behaviour and keeps the
 * generated config compatible with the test target. Revisit if the
 * floor moves past the release where the field was introduced. */
export function attachExperimental(config, routing_mode, dns_store_dns) {
	config.experimental = {
		cache_file: {
			enabled: true,
			path: '/etc/homeproxy/cache.db',
			store_dns: (dns_store_dns === '1') ? true : null
		}
	};
	return config;
};