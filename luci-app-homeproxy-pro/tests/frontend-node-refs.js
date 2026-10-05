#!/usr/bin/env node
/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * `hp.repairNodeRefs()` - the repair that keeps a deleted node from becoming a
 * permanent generation failure.
 *
 * Deleting a node from the grid stages a plain `uci.remove`; nothing rewrites
 * `config.main_node` / `main_udp_node` / the urltest member lists.  The
 * generator then dies on every later run:
 *
 *   cannot build main-out: the node it refers to does not exist (it may have
 *   been deleted, or the reference is stale).
 *
 * Measured on the device: generation exit 254 with exactly that message, the
 * reload aborted, and the UI still reported the save as applied.  The repair
 * runs before every save of the node map (including the footer's Save & Apply,
 * which calls map.save() itself).
 *
 * The helper takes the cursor as an argument, so this drives it with a fake
 * one - no form, no browser.  `nil` and `urltest` are not section names and a
 * reference that still resolves must be left alone: both are asserted, because
 * a repair that "fixes" a working configuration is worse than none.
 *
 * Usage: node tests/frontend-node-refs.js <repo-root>
 */

'use strict';

const path = require('path');
const { loadLuciModule } = require('./lib/luci-module.js');

const root = path.resolve(process.argv[2] || '.');

const hp = loadLuciModule(
	path.join(root, 'htdocs/luci-static/resources/homeproxy-pro.js'),
	{
		baseclass: { extend: (o) => o },
		form: { DynamicList: { extend: (o) => o } },
		fs: {}, rpc: {}, uci: {}, ui: {}
	});

let checks = 0, failures = 0;

function check(what, ok, detail) {
	checks++;
	if (ok)
		return;
	failures++;
	console.error(`FAIL ${what}${detail ? ': ' + detail : ''}`);
}

/* A cursor over a fixed set of sections, recording the writes. */
function fake_uci(sections, options) {
	const state = Object.assign({}, options);
	const writes = [];

	return {
		writes: writes,
		state: state,
		get: function(cfg, a, b) {
			if (b !== undefined)
				return state[a + '.' + b];
			return Object.prototype.hasOwnProperty.call(sections, a) ? sections[a] : null;
		},
		set: function(cfg, section, option, value) {
			writes.push({ section: section, option: option, value: value });
			state[section + '.' + option] = value;
		}
	};
}

if (typeof hp.repairNodeRefs !== 'function') {
	console.error('FAIL homeproxy-pro.js does not export repairNodeRefs()');
	process.exit(1);
}

/* 1. A dangling main_node is cleared. */
{
	const uci = fake_uci({ cfgOTHER: 'node' }, { 'config.main_node': 'cfgGONE' });
	const repaired = hp.repairNodeRefs(uci, 'homeproxy-pro');
	check('a dangling main_node is reported', repaired.includes('main_node'), JSON.stringify(repaired));
	check('a dangling main_node becomes nil', uci.state['config.main_node'] === 'nil',
		String(uci.state['config.main_node']));
}

/* 2. A main_node that resolves is untouched. */
{
	const uci = fake_uci({ cfgALIVE: 'node' }, { 'config.main_node': 'cfgALIVE' });
	const repaired = hp.repairNodeRefs(uci, 'homeproxy-pro');
	check('a resolving main_node is not repaired', repaired.length === 0, JSON.stringify(repaired));
	check('a resolving main_node keeps its value', uci.state['config.main_node'] === 'cfgALIVE');
	check('a resolving main_node is not written', uci.writes.length === 0, JSON.stringify(uci.writes));
}

/* 3. The two sentinels are not section names. */
for (const sentinel of [ 'nil', 'urltest' ]) {
	const uci = fake_uci({}, { 'config.main_node': sentinel });
	const repaired = hp.repairNodeRefs(uci, 'homeproxy-pro');
	check(`main_node='${sentinel}' is left alone`, repaired.length === 0 && uci.state['config.main_node'] === sentinel,
		JSON.stringify([ repaired, uci.state['config.main_node'] ]));
}

/* 4. main_udp_node is repaired the same way (the UDP node is a separate
 *    reference and used to be forgotten by the subscription cleanup). */
{
	const uci = fake_uci({}, { 'config.main_udp_node': 'cfgGONE' });
	const repaired = hp.repairNodeRefs(uci, 'homeproxy-pro');
	check('a dangling main_udp_node is reported', repaired.includes('main_udp_node'), JSON.stringify(repaired));
	check('a dangling main_udp_node becomes nil', uci.state['config.main_udp_node'] === 'nil');
}

/* 5. urltest member lists drop only the missing members. */
{
	const uci = fake_uci({ cfgA: 'node', cfgB: 'node' }, {
		'config.main_urltest_nodes': [ 'cfgA', 'cfgGONE', 'cfgB' ]
	});
	const repaired = hp.repairNodeRefs(uci, 'homeproxy-pro');
	check('a stale urltest member is reported', repaired.includes('main_urltest_nodes'), JSON.stringify(repaired));
	check('a stale urltest member is dropped and the rest kept',
		JSON.stringify(uci.state['config.main_urltest_nodes']) === JSON.stringify([ 'cfgA', 'cfgB' ]),
		JSON.stringify(uci.state['config.main_urltest_nodes']));
}

/* 6. A fully valid urltest list is untouched. */
{
	const uci = fake_uci({ cfgA: 'node', cfgB: 'node' }, {
		'config.main_urltest_nodes': [ 'cfgA', 'cfgB' ]
	});
	const repaired = hp.repairNodeRefs(uci, 'homeproxy-pro');
	check('a valid urltest list is not repaired', repaired.length === 0 && uci.writes.length === 0,
		JSON.stringify([ repaired, uci.writes ]));
}

/* 7. An empty or absent list is not a repair either. */
{
	const uci = fake_uci({}, {});
	const repaired = hp.repairNodeRefs(uci, 'homeproxy-pro');
	check('absent references are not repaired', repaired.length === 0 && uci.writes.length === 0);
}

console.log(`frontend node references: ${checks} checks, ${failures} failures`);
process.exit(failures ? 1 : 0);
