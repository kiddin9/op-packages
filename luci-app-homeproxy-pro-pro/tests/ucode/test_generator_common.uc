/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * generator/common.uc's tag helpers, driven with a hand-built domain model.
 *
 * The one that regressed: isDirectOutboundTag() is called with the tag the
 * generator *emits* (get_outbound() builds `cfg-<node>-out`), not with the
 * routing_node section name, and it looked the value up in both tables
 * unchanged. Every routing_node therefore answered "not direct", so
 * build_http_clients() kept a detour on a rule-set download in pure TUN mode -
 * where sing-box refuses to detour into an empty direct outbound and rejects
 * the whole configuration.
 *
 * Run by tests/ucode/run.sh from a staging directory that holds homeproxy.uc,
 * config/ and parser/.
 */

'use strict';

import { isDirectOutboundTag, get_outbound } from 'generator/common.uc';

let checks = 0, failures = 0;

function expect(name, actual, want) {
	checks++;
	if (actual !== want) {
		failures++;
		printf('FAIL %s: got %s, want %s\n', name, actual, want);
	}
}

/* A domain model with just the tables the helpers walk. */
const dm = {
	nodes: [
		{ id: 'n_direct', type: 'direct' },
		{ id: 'n_proxy', type: 'vless' },
		{ id: 'n_wg', type: 'wireguard' }
	],
	routing: {
		nodes: [
			{ name: 'rn_direct', node: 'n_direct' },
			{ name: 'rn_group', node: 'urltest' }
		]
	}
};

expect('literal direct-out', isDirectOutboundTag('direct-out', dm), true);
expect('literal block-out', isDirectOutboundTag('block-out', dm), false);
expect('unknown tag', isDirectOutboundTag('cfg-n_missing-out', dm), false);

/* The emitted form, which is what the caller actually passes. */
expect('direct node via cfg- tag', isDirectOutboundTag('cfg-n_direct-out', dm), true);
expect('proxy node via cfg- tag', isDirectOutboundTag('cfg-n_proxy-out', dm), false);
expect('wireguard node via cfg- tag', isDirectOutboundTag('cfg-n_wg-out', dm), false);

/* A routing_node that points at a direct node is direct; one that points at
 * the urltest group is a group, not a direct outbound. */
expect('routing_node to direct node', isDirectOutboundTag('cfg-rn_direct-out', dm), true);
expect('routing_node to urltest', isDirectOutboundTag('cfg-rn_group-out', dm), false);

/* The tag the helper is asked about has to be the tag the generator emits. */
expect('get_outbound emits cfg- prefix', get_outbound('rn_direct', dm), 'cfg-n_direct-out');

printf('%d checks, %d failures\n', checks, failures);
exit(failures ? 1 : 0);
