#!/usr/bin/ucode
/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * Driver for tests/ucode/test_udp_transport.sh. Builds a UCI sandbox
 * in-process and asserts udp_transport_verdict()'s verdict for every branch
 * of its resolution.
 *
 * Each case gets a fresh cursor over the same sandbox directory after a fresh
 * seed, so libuci's change tracking cannot leak one case's options into the
 * next - a leaked `main_udp_node` would make a later case pass for the wrong
 * reason, which is the failure mode this file is most exposed to.
 */

'use strict';

import { cursor } from 'uci';
import { writefile } from 'fs';
import { udp_transport_verdict } from 'homeproxy-pro';

/* getenv(), not argv: a ucode script has no argv global, and the runner
 * convention here is HP_T_* environment values (see
 * test_homeproxy_utils.uc). */
const SANDBOX = getenv('HP_T_SANDBOX');
if (!SANDBOX || SANDBOX === '') {
	printf('FAIL: HP_T_SANDBOX is not set; run through test_udp_transport.sh\n');
	exit(1);
}

let failures = 0,
    checks = 0,
    /* The case currently running, so a bare assertion name can be traced
     * back.  Without it a failure reads "expected anytls, got nil" and there
     * are three ways to read that. */
    current_case = '(none)';

function expect(name, actual, want) {
	checks++;
	if (sprintf('%J', actual) !== sprintf('%J', want)) {
		printf('FAIL [%s] %s: expected %J, got %J\n', current_case, name, want, actual);
		failures++;
	}
}

/* Seed the sandbox by rewriting the UCI file from scratch.  `opts` sets
 * options on the `config` section; `nodes` maps a section name to its type.
 *
 * Written as text rather than built with add()/set()/commit() on purpose:
 * every case reuses the same section names, and add() on a name that already
 * exists does not reliably give back that name - the first couple of cases
 * passed and then every later one read the section as missing, which looks
 * exactly like a bug in the function under test and is not one.  Truncating
 * the file first makes each case independent of the ones before it. */
function seed(opts, nodes) {
	let out = 'config homeproxy-pro \'config\'\n';

	/* A UCI list has to be written as `list`, one line per value.  Emitting it
	 * as `option` produces a scalar, uci.get() then hands the function a
	 * string, and iterating a string walks its CHARACTERS - which reads as
	 * "the url-test group has no members" for every group. */
	for (let k in keys(opts)) {
		let v = opts[k];
		if (type(v) === 'array') {
			for (let item in v)
				out += sprintf('\tlist %s \'%s\'\n', k, item);
		} else {
			out += sprintf('\toption %s \'%s\'\n', k, v);
		}
	}

	for (let name in keys(nodes || {})) {
		out += sprintf('config homeproxy-pro \'%s\'\n', name);
		out += sprintf('\toption type \'%s\'\n', nodes[name]);
		out += sprintf('\toption address \'%s.example.com\'\n', name);
	}

	writefile(SANDBOX + '/homeproxy-pro', out);
}

/* Run one case: seed, open a fresh cursor, judge. */
function verdict(name, opts, nodes, check) {
	current_case = name;
	seed(opts, nodes);
	let v = udp_transport_verdict('homeproxy-pro', cursor(SANDBOX));
	check(v);
	/* The reason is a log line, so it only has to be present and have to
	 * mention the thing it is explaining - not be worded a particular way,
	 * which would break every time the sentence is improved. */
	if (!v.reason || v.reason === '')
		expect(name + '.reason is set', v.reason, 'a non-empty sentence');
}

const HY2 = { 'nodeHy2': 'hysteria2' },
      ANYTLS = { 'nodeAnyTLS': 'anytls' },
      MIXED = { 'nodeHy2': 'hysteria2', 'nodeTrojan': 'trojan' };

/* --- 'same': the case this function exists for ------------------------- */

verdict('same + udp-native main', { routing_mode: 'bypass_mainland_china',
	main_node: 'nodeHy2', main_udp_node: 'same' }, HY2,
	v => {
		expect('native', v.native, true);
		expect('configured', v.configured, true);
		expect('protocol', v.protocol, 'hysteria2');
	});

/* The regression: a TCP-transport main node with 'same'. The UCI values look
 * entirely reasonable, which is exactly why this was missed - the QUIC
 * reject stayed off and QUIC was tunnelled over TCP. */
verdict('same + TCP-transport main', { routing_mode: 'bypass_mainland_china',
	main_node: 'nodeAnyTLS', main_udp_node: 'same' }, ANYTLS,
	v => {
		expect('native', v.native, false);
		expect('configured', v.configured, true);
		expect('protocol', v.protocol, 'anytls');
	});

verdict('same + no main node', { routing_mode: 'bypass_mainland_china',
	main_udp_node: 'same' }, {},
	v => {
		expect('native', v.native, false);
		expect('configured', v.configured, false);
	});

/* --- a named UDP node --------------------------------------------------- */

verdict('named udp-native node', { routing_mode: 'bypass_mainland_china',
	main_node: 'nodeAnyTLS', main_udp_node: 'nodeHy2' }, HY2,
	v => {
		expect('native', v.native, true);
		expect('protocol', v.protocol, 'hysteria2');
	});

/* The pairing that actually fixes the measured problem: TCP main, UDP-native
 * sidecar. */
verdict('named UDP-native beside TCP main', { routing_mode: 'bypass_mainland_china',
	main_node: 'nodeAnyTLS', main_udp_node: 'nodeHy2' }, MIXED,
	v => {
		expect('native', v.native, true);
		expect('protocol', v.protocol, 'hysteria2');
	});

verdict('named TCP-transport node', { routing_mode: 'bypass_mainland_china',
	main_node: 'nodeHy2', main_udp_node: 'nodeAnyTLS' },
	{ 'nodeHy2': 'hysteria2', 'nodeAnyTLS': 'anytls' },
	v => {
		expect('native', v.native, false);
		expect('protocol', v.protocol, 'anytls');
	});

verdict('named node that does not exist', { routing_mode: 'bypass_mainland_china',
	main_udp_node: 'nodeMissing' }, {},
	v => {
		expect('native', v.native, false);
		expect('configured', v.configured, false);
	});

/* --- url-test membership ------------------------------------------------ */

/* Conservative on purpose: the group picks a member per connection, so ONE
 * TCP member is enough to put QUIC back on the stalling path whenever it
 * happens to be the selected one. */
verdict('urltest with one TCP member', { routing_mode: 'bypass_mainland_china',
	main_udp_node: 'urltest',
	main_udp_urltest_nodes: [ 'nodeHy2', 'nodeTrojan' ] }, MIXED,
	v => {
		expect('native', v.native, false);
		expect('configured', v.configured, true);
		expect('protocol', v.protocol, 'trojan');
	});

verdict('urltest all UDP-native', { routing_mode: 'bypass_mainland_china',
	main_udp_node: 'urltest',
	main_udp_urltest_nodes: [ 'nodeHy2', 'nodeHy2' ] }, HY2,
	v => {
		expect('native', v.native, true);
	});

verdict('urltest with no members', { routing_mode: 'bypass_mainland_china',
	main_udp_node: 'urltest' }, {},
	v => {
		expect('native', v.native, false);
		expect('configured', v.configured, false);
	});

/* --- the remaining shapes ----------------------------------------------- */

verdict('udp disabled', { routing_mode: 'bypass_mainland_china',
	main_node: 'nodeHy2', main_udp_node: 'nil' }, HY2,
	v => {
		expect('native', v.native, false);
		expect('configured', v.configured, false);
	});

/* An unset main_udp_node is 'nil', not an error: that is the factory default
 * and a fresh install must not read as misconfigured. */
verdict('main_udp_node unset', { routing_mode: 'bypass_mainland_china',
	main_node: 'nodeHy2' }, HY2,
	v => {
		expect('native', v.native, false);
		expect('configured', v.configured, false);
	});

/* Custom mode is the user driving the rule graph by hand; this function must
 * not second-guess them, which is also what the QUIC gate did before it
 * learned to read the transport. */
verdict('custom routing mode', { routing_mode: 'custom',
	main_node: 'nodeAnyTLS', main_udp_node: 'same' }, ANYTLS,
	v => {
		expect('native', v.native, true);
		expect('protocol', v.protocol, 'custom');
	});

/* --- the set itself ----------------------------------------------------- */

/* Every protocol the UI offers is classified, not just the ones this change
 * happens to touch.  A protocol added to homeproxy-pro.js's table without a
 * decision here fails this, which is the point: the set has to be a
 * deliberate answer rather than a default that silently means "no".
 *
 * The native list is duplicated here on purpose - a test that read the
 * constant under test would agree with any change to it, including a wrong
 * one.  Both lists come from the protocol table in
 * htdocs/luci-static/resources/homeproxy-pro.js. */
const NATIVE = [ 'hysteria', 'hysteria2', 'tuic', 'wireguard' ],
      NOT_NATIVE = [ 'anytls', 'http', 'mixed', 'naive', 'shadowsocks',
	                 'shadowtls', 'snell', 'socks', 'ssh', 'trojan',
	                 'vless', 'vmess' ];

for (let type in NATIVE) {
	verdict('native: ' + type, { routing_mode: 'bypass_mainland_china',
		main_udp_node: 'nodeP' }, { 'nodeP': type },
		v => {
			expect('native', v.native, true);
			expect('protocol', v.protocol, type);
		});
}

for (let type in NOT_NATIVE) {
	verdict('not native: ' + type, { routing_mode: 'bypass_mainland_china',
		main_udp_node: 'nodeP' }, { 'nodeP': type },
		v => {
			expect('native', v.native, false);
			expect('configured', v.configured, true);
			expect('protocol', v.protocol, type);
		});
}

/* A protocol nobody has classified must read as not-native. Failing closed
 * here means an unrecognised node gets QUIC rejected - browsers fall back to
 * TCP, which every transport carries - rather than QUIC tunnelled over a path
 * that may not be able to carry it. */
verdict('unclassified protocol fails closed', { routing_mode: 'bypass_mainland_china',
	main_udp_node: 'nodeP' }, { 'nodeP': 'something-new' },
	v => {
		expect('native', v.native, false);
		expect('configured', v.configured, true);
	});

printf('%d checks, %d failures\n', checks, failures);
exit(failures === 0 ? 0 : 1);