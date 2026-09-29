/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 *     generator/client.uc: client-side orchestrator.
 *
 * This file is the only place the client generator still knows the
 * overall shape. Each section builder lives in its own module under
 * generator/; this file glues them together.
 *
 *     generate(dm, env)
 *         -> build_context(dm, env)
 *         -> build_dns
 *         -> build_inbounds
 *         -> build_outbounds (mutates direct_overrides)
 *         -> build_route
 *         -> build_user_rulesets (custom mode only)
 *         -> build_http_clients
 *         -> attachSchema, attachExperimental
 *         -> final config object (caller writes + sing-box check)
 *
 * Every section builder takes (config, ctx, ...) where `ctx` carries
 * the routing-mode- and proxy-mode-derived scalars (main_node,
 * dns_server, proxy_mode, ...) plus the mutable accumulators (outbounds,
 * endpoints, ...) the builders append to. The orchestrator owns them
 * and threads them through, which is what kept the original
 * generate_client.uc at 1240 lines: a 1100-line config blob with a
 * single closure scope.
 *
 * The output is the final config object: no `$schema`, no atomic write,
 * no `sing-box check`. The CLI shell (`scripts/generate_client.uc`)
 * is responsible for those - per the architecture guide, the generator
 * must not double as the runner.
 *
 * It is also responsible for resolving `env` (the WAN DNS via ubus and the
 * two resource lists) and passing it in. This module imports no ubus and no
 * fs: `generate(dm, env)` is a pure function, so the same arguments always
 * produce the same bytes. tests/arch-guard.sh guard 27 keeps it that way.
 */

'use strict';

import { isEmpty, strToInt, RUN_DIR } from '../homeproxy.uc';

import { build_context } from './context.uc';
import { build_dns } from './dns.uc';
import { build_inbounds } from './inbound.uc';
import { build_outbounds } from './outbound.uc';
import { build_route } from './route.uc';
import { build_user_rulesets, build_http_clients } from './ruleset.uc';
import { attachSchema, attachExperimental } from './common.uc';

/* --- public entry ------------------------------------------------------ */

/* Build the sing-box client config object. Pure function: takes the
 * HomeProxyConfig from the Loader plus the GenerationContext inputs the CLI
 * resolved (`env`), and returns the JSON object the caller writes and
 * `sing-box check`s. No UCI, no file I/O, no ubus, no procd. */
export function generate(dm, env) {
	const ctx = build_context(dm, env);

	const config = {
		log: {
			disabled: false,
			level: ctx.log_level,
			output: RUN_DIR + '/sing-box-c.log',
			timestamp: true
		}
	};

	if (!isEmpty(ctx.ntp_server))
		config.ntp = {
			enabled: true,
			server: ctx.ntp_server,
			detour: 'direct-out',
			domain_resolver: 'default-dns',
		};

	/* `direct_overrides` is the single side effect that survives the
	 * split: a direct node with override_address / override_port
	 * records the override here so build_route can emit the
	 * route-options action later. The orchestrator owns the map and
	 * passes it to both builders. */
	const direct_overrides = {};

	build_dns(config, dm, ctx);
	build_inbounds(config, ctx);

	/* direct_outbounds live on config.outbounds regardless of mode:
	 * the DNS path always references them, and a custom-mode config
	 * without any direct-out/block-out would not have a fallback for
	 * a routing rule that emits a missing tag. Initialised AFTER
	 * build_dns / build_inbounds so the JSON key order is
	 * log, ntp, dns, inbounds, outbounds, ... matching the
	 * pre-refactor generator. The builder appends to the same array
	 * (no reassignment), which preserves the key order that
	 * removeBlankAttrs() emits and keeps golden snapshots stable. */
	config.outbounds = [
		{
			type: 'direct',
			tag: 'direct-out',
			routing_mark: strToInt(ctx.self_mark)
		},
		{
			type: 'block',
			tag: 'block-out'
		}
	];
	config.endpoints = [];

	build_outbounds(config, dm, ctx, direct_overrides);

	build_route(config, dm, ctx, direct_overrides);

	/* User-defined rulesets are custom-mode only; passing an empty
	 * dm.routing.rulesets through build_user_rulesets is a no-op
	 * because every cfg in it is filtered by !cfg.enabled. */
	if (ctx.routing_mode === 'custom')
		build_user_rulesets(config.route.rule_set, dm, ctx);

	const http_clients = build_http_clients(config.route.rule_set, dm, ctx);
	if (length(http_clients))
		config.http_clients = http_clients;

	/* A direct node used as the main node yields a main-out with no fields of
	 * its own: generate_outbound() turns its override_address / override_port
	 * into a route action rather than outbound fields, leaving a bare
	 * {"type":"direct","tag":"main-out"}.  sing-box refuses to detour into
	 * such an outbound and the service never starts:
	 *
	 *   FATAL start service: start dns/tcp[main-dns]: detour to an empty
	 *   direct outbound makes no sense
	 *   FATAL start service: initialize rule-set[0]: ... detour to an empty
	 *   direct outbound makes no sense
	 *
	 * Dropping the detour is the equivalent behaviour - the query or the
	 * rule-set download leaves through the host's own network, which is what a
	 * direct outbound does - and mirrors the `ctx.self_mark ? 'direct-out' :
	 * null` that build_dns already applies to the other DNS servers.  Only
	 * main-out is touched: direct-out is deliberate and carries a routing
	 * mark.
	 *
	 * This has to run after build_http_clients(): the rule-set downloads
	 * reach main-out through an http_client, not through a detour of their
	 * own. */
	let bare_main_out = false;
	for (let i = 0; i < length(config.outbounds); i++) {
		const ob = config.outbounds[i];
		/* build_outbounds leaves a null in the array for a node it could not
		 * emit (a pruned urltest candidate); skip those. */
		if (ob && ob.tag === 'main-out' && ob.type === 'direct' && length(keys(ob)) === 2)
			bare_main_out = true;
	}
	if (bare_main_out) {
		for (let i = 0; i < length(config.dns.servers); i++) {
			const s = config.dns.servers[i];
			if (s && s.detour === 'main-out')
				delete s.detour;
		}
		for (let i = 0; i < length(config.http_clients || []); i++) {
			const c = config.http_clients[i];
			if (c && c.detour === 'main-out')
				delete c.detour;
		}
	}

	if (isEmpty(config.route.rule_set))
		config.route.rule_set = null;
	if (isEmpty(config.endpoints))
		config.endpoints = null;

	attachExperimental(config, ctx.routing_mode, ctx.dns_store_dns);
	attachSchema(config);

	return config;
};