#!/usr/bin/ucode
/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * Driver for tests/ucode/test_firewall_pre.sh.
 *
 * firewall_pre.uc is the fw4 pre-rules generator: it reads UCI and
 * writes the two nft fragments (fw4_forward.nft / fw4_input.nft)
 * that firewall_post.ut then includes. It has real branching - the
 * tun accept pair, the per-server accept rules, and two validation
 * guards that skip a malformed server rather than emitting a broken
 * nft statement - and none of it had a test.
 *
 * The driver imports the (staged, cursor-redirected) script, then
 * asserts on the generated fragments. Each scenario is a separate
 * import in a fresh process, because the module body runs once per
 * process; the shell wrapper drives the scenarios.
 *
 * Invoked as: ucode -L <stage> test_firewall_pre.uc <sandbox> <run-dir> <scenario>
 */

'use strict';

import { access, readfile } from 'fs';

global.HP_FW_RUN_DIR = ARGV[1];
import 'firewall_pre';

let failures = 0,
    checks = 0;

function expect(name, actual, want) {
	checks++;
	if (sprintf('%J', actual) !== sprintf('%J', want)) {
		printf('FAIL %s: expected %J, got %J\n', name, want, actual);
		failures++;
	}
}

const forward_file = ARGV[1] + '/fw4_forward.nft';
const input_file = ARGV[1] + '/fw4_input.nft';

const forward = access(forward_file) ? trim(readfile(forward_file)) : null;
const input = access(input_file) ? trim(readfile(input_file)) : null;

switch (ARGV[2]) {
case 'tun':
	/* tun_mode routing: forward accepts traffic leaving the tun, input
	 * accepts traffic arriving on it. */
	expect('tun forward', forward,
		'oifname singtun0 counter accept comment "!homeproxy-pro: accept tun forward"');
	expect('tun input', input,
		'iifname singtun0 counter accept comment "!homeproxy-pro: accept tun input"');
	break;

case 'no-tun':
	/* proxy_mode is tun but the outbound node is 'nil', so no tun rules
	 * are emitted at all. */
	expect('no-tun forward', forward, null);
	expect('no-tun input', input, null);
	break;

case 'bad-tun':
	/* A tun_name that is not a valid interface name must not reach the
	 * ruleset: the value is interpolated into an nft file that fw4 loads as
	 * root, and `;`/`}` need no newline to break out of the rule. */
	expect('bad-tun forward', forward, null);
	expect('bad-tun input', input, null);
	break;

case 'good-tun':
	/* The same path with a valid name still emits the pair, so the guard
	 * above cannot pass by disabling the feature. */
	expect('good-tun forward', forward,
		'oifname singtun9 counter accept comment "!homeproxy-pro: accept tun forward"');
	expect('good-tun input', input,
		'iifname singtun9 counter accept comment "!homeproxy-pro: accept tun input"');
	break;

case 'server':
	/* server enabled + firewall='1' + a valid port: one accept rule per
	 * server section, keyed on the destination port. */
	expect('server input', input,
		'meta l4proto { tcp, udp } th dport 443 counter accept comment "!homeproxy-pro: accept server srv_ok"');
	break;

case 'server-network':
	/* an explicit network narrows the l4proto match. */
	expect('server-network input', input,
		'meta l4proto tcp th dport 8080 counter accept comment "!homeproxy-pro: accept server srv_tcp"');
	break;

case 'invalid-port':
	/* a non-numeric port would emit `th dport  not-a-port` - broken nft.
	 * The guard skips the server instead, and says why on stdout. */
	expect('invalid-port input', input, null);
	break;

case 'invalid-network':
	/* a network outside {tcp, udp, {tcp,udp}} would be interpolated
	 * straight into the nft statement. The guard skips it. */
	expect('invalid-network input', input, null);
	break;

case 'invalid-section-name':
	/* The section name lands inside an nft comment, in a file fw4 loads as
	 * root, so a name containing a closing quote would end the comment and
	 * turn the rest of the name into nft syntax. libuci refuses such a name
	 * before it can reach this loop (see the shell wrapper), so this case is
	 * driven through a cursor stub that yields it verbatim: the server must
	 * be skipped, not interpolated. */
	expect('invalid-section-name input', input, null);
	break;

case 'mock-good-section-name':
	/* The same stub with a name libuci would accept: the rule is emitted,
	 * which is what makes the `null` above the guard's doing rather than the
	 * stub never reaching the emit path. */
	expect('mock-good-section-name input', input,
		'meta l4proto { tcp, udp } th dport 443 counter accept comment "!homeproxy-pro: accept server srv_ok_mock"');
	break;

case 'firewall-off':
	/* firewall='0' means the user opted this server out of the automatic
	 * rule; nothing is emitted. */
	expect('firewall-off input', input, null);
	break;

case 'both':
	/* tun + server together: both fragments exist, each with its own
	 * statements. */
	expect('both forward', forward,
		'oifname singtun0 counter accept comment "!homeproxy-pro: accept tun forward"');
	expect('both input has tun', match(input, /iifname singtun0 counter accept/) != null, true);
	expect('both input has server', match(input, /th dport 443 counter accept/) != null, true);
	break;

default:
	printf('FAIL: unknown scenario %s\n', ARGV[2]);
	exit(1);
}

if (failures > 0)
	printf('FAIL: %s: %d/%d checks failed\n', ARGV[2], failures, checks);
else
	printf('PASS: %s: %d checks\n', ARGV[2], checks);

exit(failures > 0 ? 1 : 0);
