/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 *     generator/outbound.uc: build the sing-box `outbounds` and `endpoints`
 *                            blocks, plus the urltest pruning the route
 *                            builder depends on.
 *
 * Two builders live here:
 *
 *   generate_endpoint(node, ctx) -> sing-box endpoint object (WireGuard only
 *     at the moment; the tag convention is the same as for outbounds).
 *
 *   generate_outbound(node, mark, direct_overrides) -> sing-box outbound
 *     object. Side effect: a direct node carrying override_address /
 *     override_port is recorded into the caller-supplied `direct_overrides`
 *     map so the route builder can later emit the route-options action.
 *     The Adapter (config/adapter.uc) already handles every protocol's
 *     payload; this module is just the orchestration and the override side
 *     effect.
 *
 *   build_outbounds(dm, ctx, direct_overrides) -> { outbounds, endpoints }
 *     Implements the routing-mode split (proxy vs custom), the urltest
 *     pruning via keep_candidate / buildable_candidates, and the
 *     routing_node -> outbound / endpoint resolution.
 *
 * The `direct_overrides` parameter is a mutable map the orchestrator owns
 * and threads through the generators. Making it explicit avoids the
 * "module-level side effect" the old generate_client.uc had, which was
 * the only thing tying outbound building to route building.
 */

'use strict';

import { isEmpty, strToInt, strToBool, strToTime } from '../homeproxy.uc';

import { ConfigQuery } from '../config/model.uc';
import { OutboundFactory, EndpointFactory } from '../config/adapter.uc';

import { get_outbound, get_resolver } from './common.uc';

/* --- single-endpoint / single-outbound builders ------------------------ */

/* WireGuard goes through the same Node as every other protocol; the
 * fields come from node.protocol_options (Loader's wireguard row) and
 * the cross-protocol options from node.common.
 *
 * This used to read the flat UCI keys (node.wireguard_*, and
 * node.tcp_fast_open / node.tcp_multi_path / node.udp_fragment) off a
 * Node.  Those keys only existed on the flat section dict the
 * pre-refactor call sites passed; once A2/A3 made every call site pass
 * a Node they were simply null, so every WireGuard main / UDP /
 * urltest node emitted an endpoint with no private key and a peer with
 * no public key.  tests/fixtures/generators/wireguard.uci guards it.
 *
 * The endpoint *shaping* lives in EndpointFactory in
 * config/adapter.uc, so the generator no longer holds protocol business
 * logic for WireGuard. This stays as the call sites' entry point, which
 * keeps the module's endpoint vocabulary without making every caller
 * import the adapter directly. */
export function generate_endpoint(node, ctx) {
	return EndpointFactory.create(node, ctx);
};

/* Build one outbound from a Node via the Adapter layer. A direct node
 * with override_address / override_port also gets recorded into the
 * caller's `direct_overrides` map so the route builder can emit the
 * route-options action; this is the only side effect of the function
 * beyond returning the outbound object. */
export function generate_outbound(node, mark, direct_overrides) {
	/* Stage A3+A5: this used to be a 110-line ternary soup that built the
	 * sing-box outbound by hand for every protocol. It now takes a
	 * Node (looked up via ConfigQuery.node_by_id) and hands it straight
	 * to OutboundFactory.create() (the Adapter layer).
	 *
	 * The direct-node override table is the one side effect that survives;
	 * the Adapter layer has no place to record it, and the route builder
	 * reads it later. */
	if (type(node) !== 'object' || isEmpty(node))
		return null;

	if (node.type === 'direct' && (!isEmpty(node.protocol_options.override_address) || !isEmpty(node.protocol_options.override_port)))
		direct_overrides[node.id] = {
			override_address: node.protocol_options.override_address,
			override_port: strToInt(node.protocol_options.override_port)
		};

	return OutboundFactory.create(node, mark);
};

/* Keep only the candidate ids the Adapter can actually build.
 *
 * urltest member lists are the one place a broken node must not be fatal:
 * a single bad node in a 200-node subscription used to make the Adapter
 * die(), which aborted the whole generator, so the service could not start
 * at all.  The node stays in UCI (the UI shows it and the next
 * subscription update can repair or drop it); it is only left out of the
 * urltest group, and the reason is logged.
 *
 * Nodes that routing rules or DNS actually resolve through are NOT pruned:
 * a rule pointing at a missing tag is invalid sing-box config, so those
 * stay fatal on purpose. */
function keep_candidate(dm, id) {
	const node = ConfigQuery.node_by_id(dm, id);

	if (!node) {
		warn(sprintf("homeproxy: urltest candidate '%s' no longer exists, skipping.", id));
		return false;
	}

	const problems = OutboundFactory.problems(node);
	if (length(problems)) {
		warn(sprintf("homeproxy: skipping urltest candidate '%s': %s.", id, join(', ', problems)));
		return false;
	}

	return true;
}

/* Map over a candidate id list, dropping the unbuildable ones. */
function buildable_candidates(dm, ids) {
	return filter(ids || [], (id) => keep_candidate(dm, id));
}

/* --- main-outbound building (proxy mode) ------------------------------- */

/* Decide whether a candidate node should be emitted as a sing-box endpoint
 * (WireGuard) or as an outbound (everything else). Returns the populated
 * object so the caller can retag it. */
function emitNode(node, mark, tag, direct_overrides, ctx) {
	if (node && node.type === 'wireguard') {
		const endpoint = generate_endpoint(node, ctx);
		endpoint.tag = tag;
		return { kind: 'endpoint', object: endpoint };
	}

	const outbound = generate_outbound(node, mark, direct_overrides);

	/* generate_outbound() returns null for an empty node, and a reference can
	 * point at a section that no longer exists: main_node and main_udp_node
	 * are stored by name, and deleting a node in the UI does not rewrite
	 * them. Setting `.tag` on null raised "left-hand side expression is
	 * null", which says nothing about which reference is stale. */
	if (outbound == null)
		die(sprintf("cannot build %s: the node it refers to does not exist (it may have been deleted, or the reference is stale).\n", tag));

	outbound.tag = tag;
	return { kind: 'outbound', object: outbound };
}

function buildMainOutbounds(dm, config, ctx, direct_overrides) {
	const outbounds = config.outbounds;
	const endpoints = config.endpoints;
	const mark = ctx.self_mark;
	let urltest_nodes = [];

	if (ctx.main_node === 'urltest') {
		const main_urltest_nodes = buildable_candidates(dm, ctx.main_urltest_nodes);
		const main_urltest_interval = ctx.main_urltest_interval;
		const main_urltest_tolerance = ctx.main_urltest_tolerance;

		/* An empty group means every candidate was unbuildable: there is
		 * nothing left to route through, so fail with the reason instead
		 * of emitting an urltest outbound with no members. */
		if (isEmpty(main_urltest_nodes))
			die("no buildable node in the main urltest group, please check your configuration.\n");

		push(outbounds, {
			type: 'urltest',
			tag: 'main-out',
			outbounds: map(main_urltest_nodes, (k) => `cfg-${k}-out`),
			interval: strToTime(main_urltest_interval),
			tolerance: strToInt(main_urltest_tolerance),
			idle_timeout: (strToInt(main_urltest_interval) > 1800) ? `${main_urltest_interval * 2}s` : null,
		});
		urltest_nodes = main_urltest_nodes;
	} else {
		const main_node_cfg = ConfigQuery.node_by_id(dm, ctx.main_node);
		const emitted = emitNode(main_node_cfg, mark, 'main-out', direct_overrides, ctx);
		if (emitted.kind === 'endpoint')
			push(endpoints, emitted.object);
		else
			push(outbounds, emitted.object);
	}

	if (ctx.main_udp_node === 'urltest') {
		const main_udp_urltest_nodes = buildable_candidates(dm, ctx.main_udp_urltest_nodes);
		const main_udp_urltest_interval = ctx.main_udp_urltest_interval;
		const main_udp_urltest_tolerance = ctx.main_udp_urltest_tolerance;

		if (isEmpty(main_udp_urltest_nodes))
			die("no buildable node in the main UDP urltest group, please check your configuration.\n");

		push(outbounds, {
			type: 'urltest',
			tag: 'main-udp-out',
			outbounds: map(main_udp_urltest_nodes, (k) => `cfg-${k}-out`),
			interval: strToTime(main_udp_urltest_interval),
			tolerance: strToInt(main_udp_urltest_tolerance),
			idle_timeout: (strToInt(main_udp_urltest_interval) > 1800) ? `${main_udp_urltest_interval * 2}s` : null,
		});
		urltest_nodes = [...urltest_nodes, ...filter(main_udp_urltest_nodes, (l) => !~index(urltest_nodes, l))];
	} else if (ctx.dedicated_udp_node) {
		const main_udp_node_cfg = ConfigQuery.node_by_id(dm, ctx.main_udp_node);
		const emitted = emitNode(main_udp_node_cfg, mark, 'main-udp-out', direct_overrides, ctx);
		if (emitted.kind === 'endpoint')
			push(endpoints, emitted.object);
		else
			push(outbounds, emitted.object);
	}

	for (let i in urltest_nodes) {
		const urltest_node = ConfigQuery.node_by_id(dm, i);
		if (!urltest_node)
			continue;
		const emitted = emitNode(urltest_node, mark, 'cfg-' + i + '-out', direct_overrides, ctx);
		if (emitted.kind === 'endpoint')
			push(endpoints, emitted.object);
		else
			push(outbounds, emitted.object);
	}
}

/* --- custom-mode outbound building (routing_node iteration) ------------- */

function buildCustomOutbounds(dm, config, ctx, direct_overrides) {
	const outbounds = config.outbounds;
	const endpoints = config.endpoints;
	const mark = ctx.self_mark;
	let urltest_nodes = [],
	    routing_nodes = [];

	for (let cfg in dm.routing.nodes) {
		if (!cfg.enabled)
			continue;

		if (cfg.node === 'urltest') {
			const cfg_urltest_nodes = buildable_candidates(dm, cfg.urltest_nodes);
			push(outbounds, {
				type: 'urltest',
				tag: 'cfg-' + cfg.name + '-out',
				outbounds: map(cfg_urltest_nodes, (k) => `cfg-${k}-out`),
				url: cfg.urltest_url,
				interval: strToTime(cfg.urltest_interval),
				tolerance: strToInt(cfg.urltest_tolerance),
				idle_timeout: strToTime(cfg.urltest_idle_timeout),
				interrupt_exist_connections: strToBool(cfg.urltest_interrupt_exist_connections)
			});
			urltest_nodes = [...urltest_nodes, ...filter(cfg_urltest_nodes, (l) => !~index(urltest_nodes, l))];
		} else {
			const outbound = ConfigQuery.node_by_id(dm, cfg.node);

			/* Same stale-reference case as emitNode(), but here the reference
			 * comes from a routing_node. `|| {}` made it look non-null and the
			 * failure surfaced as a null dereference two lines later. */
			if (isEmpty(outbound))
				die(sprintf("routing node '%s' refers to a node that does not exist.\n", cfg['.name']));

			if (outbound.type === 'wireguard') {
				/* WireGuard goes through generate_endpoint() which tags
				 * the endpoint as cfg-<node_id>-out (same convention as
				 * generate_outbound()). The routing_node section name is
				 * used by routing rules via get_outbound() but not as the
				 * tag itself; both paths agree on cfg-<node_id>-out. */
				const endpoint = generate_endpoint(outbound, ctx);
				endpoint.bind_interface = cfg.bind_interface;
				endpoint.detour = get_outbound(cfg.outbound, dm);
				if (cfg.domain_resolver)
					endpoint.domain_resolver = {
						server: get_resolver(cfg.domain_resolver, dm),
						strategy: cfg.domain_strategy
					};
				push(endpoints, endpoint);
			} else {
				const ob = generate_outbound(outbound, mark, direct_overrides);

				if (ob == null)
					die(sprintf("routing node '%s' cannot be built from node '%s'.\n", cfg['.name'], cfg.node));

				ob.bind_interface = cfg.bind_interface;
				ob.detour = get_outbound(cfg.outbound, dm);
				if (cfg.domain_resolver)
					ob.domain_resolver = {
						server: get_resolver(cfg.domain_resolver, dm),
						strategy: cfg.domain_strategy
					};
				push(outbounds, ob);
			}
			push(routing_nodes, cfg.node);
		}
	}

	for (let i in filter (urltest_nodes, (l) => !~index(routing_nodes, l))) {
		const urltest_node = ConfigQuery.node_by_id(dm, i) || {};
		if (urltest_node.type === 'wireguard')
			push(endpoints, generate_endpoint(urltest_node, ctx));
		else
			push(outbounds, generate_outbound(urltest_node, mark, direct_overrides));
	}
}

/* --- public entry ------------------------------------------------------ */

/* Build the sing-box `outbounds` and `endpoints` blocks. Mutates
 * config.endpoints and config.outbounds; the caller initialises them
 * with the always-on default outbounds (direct-out + block-out) and
 * passes the mutable accumulator in `ctx.acc` so the same arrays can
 * be threaded through this module, the ruleset module and the route
 * module without copying.
 *
 * `direct_overrides` is the same mutable map the route module will read
 * later; populate it here so the override information is available
 * when the route builder runs. */
export function build_outbounds(config, dm, ctx, direct_overrides) {
	if (isEmpty(ctx.main_node) && isEmpty(ctx.default_outbound))
		return config;

	if (!isEmpty(ctx.main_node))
		buildMainOutbounds(dm, config, ctx, direct_overrides);
	else if (!isEmpty(ctx.default_outbound))
		buildCustomOutbounds(dm, config, ctx, direct_overrides);

	return config;
};