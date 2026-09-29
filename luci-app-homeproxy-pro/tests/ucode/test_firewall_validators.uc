#!/usr/bin/ucode
/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * Direct unit tests for the field validators that firewall_post.ut routes
 * every UCI-derived value through (the H1 fix from the 2026-09-16 review).
 *
 * What this catches that the rendering test cannot:
 *
 *   The renderer (tests/ucode/test_firewall_template.sh) needs the device-only
 *   `fw4` ucode module, so on a development host it only runs the source-level
 *   precondition check (the `{%-` glue guard).  The validators themselves are
 *   pure functions: they take a string or a list and return either an nft
 *   anonymous-set spelling or null.  This file exercises them directly, so a
 *   regex tightening, an accidental inversion of the predicate, or a missing
 *   drop branch shows up as a unit-test failure here even when the renderer
 *   layer is offline.
 *
 *   What the tests cover:
 *
 *     isValidIPv4  - accept dotted-quad with optional /CIDR, reject anything
 *                    that is not (e.g. "1.2.3", "1.2.3.4.5", "1.2.3.4 ", "abc").
 *     isValidMAC   - accept six colon-separated hex octets (case-insensitive),
 *                    reject anything else ("GG" octet, "1:2:3:4:5", "1:2:3:4:5:6:7").
 *     isValidIface  - accept alnum + . _ -, reject whitespace, brackets, slashes,
 *                     quotes, semicolons, the obvious injection characters.
 *     isValidPort   - accept 1..65535, reject 0, negatives, decimals, alpha.
 *
 *     ipv4_to_nftarr / mac_to_nftarr / iface_to_nftarr  - the canonical case
 *                     (all entries valid), the all-poison case (every entry
 *                     dropped, returns null), and the mixed case (poison
 *                     entries stripped, valid entries kept).
 *
 *     ports_to_nftarr - the comma-separated UCI string the routing_port option
 *                       actually ships: a clean list, an all-poison list, and
 *                       the report's example ("22,7890; reject,443,foo" ->
 *                       "{ 22, 443 }").
 *
 *   Reverse-proving: removing any drop branch - or relaxing a regex - makes
 *   the matching test fail, the way guard 11 in tests/arch-guard.sh would
 *   make a future regression in firewall_post.ut itself fail.  The two together
 *   are the report's "fix + reverse-verify" loop.
 *
 *   Run from tests/ucode/test_firewall_validators.sh, which stages
 *   firewall_utils.uc (and the homeproxy-pro.uc bits the validators depend on)
 *   in $WORK.
 */

'use strict';

import {
	isValidIPv4, ipv4_to_nftarr,
	isValidMAC, mac_to_nftarr,
	isValidIface, iface_to_nftarr,
	isValidPort, ports_to_nftarr
} from 'firewall_utils';

let failures = 0, checks = 0;

function expect(name, actual, want) {
	checks++;
	if (sprintf('%J', actual) !== sprintf('%J', want)) {
		printf('FAIL %s: expected %J, got %J\n', name, want, actual);
		failures++;
	}
}

/* isValidIPv4 ------------------------------------------------------------ */
{
	expect('isValidIPv4 accept 1.2.3.4',          isValidIPv4('1.2.3.4'),      true);
	expect('isValidIPv4 accept 255.255.255.255',  isValidIPv4('255.255.255.255'), true);
	expect('isValidIPv4 accept 10.0.0.0/8',       isValidIPv4('10.0.0.0/8'),   true);
	expect('isValidIPv4 accept 192.168.1.0/24',   isValidIPv4('192.168.1.0/24'), true);
	expect('isValidIPv4 accept 0.0.0.0/0',        isValidIPv4('0.0.0.0/0'),    true);
	expect('isValidIPv4 reject 1.2.3',            isValidIPv4('1.2.3'),        false);
	expect('isValidIPv4 reject 1.2.3.4.5',        isValidIPv4('1.2.3.4.5'),    false);
	expect('isValidIPv4 reject "1.2.3.4 "',       isValidIPv4('1.2.3.4 '),     false);
	expect('isValidIPv4 reject " 1.2.3.4"',       isValidIPv4(' 1.2.3.4'),     false);
	expect('isValidIPv4 reject abc',              isValidIPv4('abc'),          false);
	expect('isValidIPv4 reject empty',            isValidIPv4(''),             false);
	expect('isValidIPv4 reject null',             isValidIPv4(null),           false);
	expect('isValidIPv4 reject number',           isValidIPv4(123),            false);
	/* The H1 injection: a value that closes a nft set. */
	expect('isValidIPv4 reject injection',
		isValidIPv4('1.2.3.4 } ; reject ; set x {'), false);
}

/* isValidMAC ------------------------------------------------------------- */
{
	expect('isValidMAC accept aa:bb:cc:dd:ee:ff', isValidMAC('aa:bb:cc:dd:ee:ff'), true);
	expect('isValidMAC accept AA:BB:CC:DD:EE:FF', isValidMAC('AA:BB:CC:DD:EE:FF'), true);
	expect('isValidMAC reject GG octet',
		isValidMAC('00:11:22:33:44:GG'), false);
	expect('isValidMAC reject too few octets',
		isValidMAC('aa:bb:cc:dd:ee'),   false);
	expect('isValidMAC reject too many octets',
		isValidMAC('aa:bb:cc:dd:ee:ff:00'), false);
	expect('isValidMAC reject dash separator',
		isValidMAC('aa-bb-cc-dd-ee-ff'), false);
	expect('isValidMAC reject empty', isValidMAC(''), false);
}

/* isValidIface ----------------------------------------------------------- */
{
	expect('isValidIface accept eth0',         isValidIface('eth0'),          true);
	expect('isValidIface accept br-lan',       isValidIface('br-lan'),        true);
	expect('isValidIface accept eth0.10',      isValidIface('eth0.10'),       true);
	expect('isValidIface accept lo',           isValidIface('lo'),            true);
	expect('isValidIface reject space',
		isValidIface('eth 0'), false);
	expect('isValidIface reject slash',
		isValidIface('eth0/1'), false);
	expect('isValidIface reject semicolon',
		isValidIface('eth0;reject'), false);
	expect('isValidIface reject injection',
		isValidIface('eth0 } reject ; set x {'), false);
}

/* isValidPort ------------------------------------------------------------ */
{
	expect('isValidPort reject 0',      isValidPort('0'),    false);
	expect('isValidPort accept 22',     isValidPort('22'),   true);
	expect('isValidPort accept 65535',  isValidPort('65535'), true);
	expect('isValidPort reject 65536',  isValidPort('65536'), false);
	expect('isValidPort reject -1',     isValidPort('-1'),   false);
	expect('isValidPort reject 22.5',   isValidPort('22.5'), false);
	expect('isValidPort reject abc',    isValidPort('abc'),  false);
	expect('isValidPort reject empty',  isValidPort(''),     false);
	expect('isValidPort reject injection',
		isValidPort('7890; reject'), false);
}

/* ipv4_to_nftarr --------------------------------------------------------- */
{
	/* Canonical case: every entry valid. */
	expect('ipv4_to_nftarr clean',
		ipv4_to_nftarr(['10.0.0.1', '192.168.1.0/24']),
		'{ 10.0.0.1, 192.168.1.0/24 }');
	/* All-poison: every entry dropped, returns null. */
	expect('ipv4_to_nftarr all-poison returns null',
		ipv4_to_nftarr(['1.2.3.4 } ; reject ; set x {',
		                'not.an.ip', '5']),
		null);
	/* Mixed: poison entries stripped, valid kept. */
	expect('ipv4_to_nftarr mixed drops the poison',
		ipv4_to_nftarr(['10.0.0.1', '1.2.3.4 } ; reject ; set x {', '192.168.1.1']),
		'{ 10.0.0.1, 192.168.1.1 }');
	/* Empty list. */
	expect('ipv4_to_nftarr empty returns null',
		ipv4_to_nftarr([]), null);
	expect('ipv4_to_nftarr null returns null',
		ipv4_to_nftarr(null), null);
	/* Dedup. */
	expect('ipv4_to_nftarr dedups',
		ipv4_to_nftarr(['10.0.0.1', '10.0.0.1', '10.0.0.2']),
		'{ 10.0.0.1, 10.0.0.2 }');
}

/* mac_to_nftarr ---------------------------------------------------------- */
{
	expect('mac_to_nftarr clean',
		mac_to_nftarr(['aa:bb:cc:dd:ee:ff', '00:11:22:33:44:55']),
		'{ aa:bb:cc:dd:ee:ff, 00:11:22:33:44:55 }');
	expect('mac_to_nftarr all-poison returns null',
		mac_to_nftarr(['00:11:22:33:44:GG',
		               'aa-bb-cc-dd-ee-ff',
		               'too:short']),
		null);
	expect('mac_to_nftarr mixed drops the poison',
		mac_to_nftarr(['aa:bb:cc:dd:ee:ff', '00:11:22:33:44:GG', '11:22:33:44:55:66']),
		'{ aa:bb:cc:dd:ee:ff, 11:22:33:44:55:66 }');
}

/* iface_to_nftarr -------------------------------------------------------- */
{
	expect('iface_to_nftarr clean',
		iface_to_nftarr(['eth0', 'br-lan']),
		'{ eth0, br-lan }');
	expect('iface_to_nftarr all-poison returns null',
		iface_to_nftarr(['eth0 } reject ; set x {',
		                 'eth 0',
		                 'eth0/1']),
		null);
	expect('iface_to_nftarr mixed drops the poison',
		iface_to_nftarr(['eth0', 'eth0;reject', 'br-lan']),
		'{ eth0, br-lan }');
}

/* ports_to_nftarr -------------------------------------------------------- */
{
	/* The exact injection the report called out. */
	expect('ports_to_nftarr clean',
		ports_to_nftarr('22,53,80,443'),
		'{ 22, 53, 80, 443 }');
	expect('ports_to_nftarr all-poison returns null',
		ports_to_nftarr('abc,7890; reject,-1,65536'),
		null);
	expect('ports_to_nftarr mixed drops the poison',
		ports_to_nftarr('22,7890; reject,443,foo'),
		'{ 22, 443 }');
	expect('ports_to_nftarr empty returns null',
		ports_to_nftarr(''), null);
	expect('ports_to_nftarr handles whitespace',
		ports_to_nftarr(' 22 , 53 , 80 '),
		'{ 22, 53, 80 }');
	expect('ports_to_nftarr handles common defaults',
		ports_to_nftarr('22,53,80,143,443,465,587,853,873,993,995,8080,8443,9418'),
		'{ 22, 53, 80, 143, 443, 465, 587, 853, 873, 993, 995, 8080, 8443, 9418 }');
}

if (failures > 0)
	printf('FAIL: %d/%d checks failed\n', failures, checks);
else
	printf('PASS: %d checks\n', checks);

exit(failures > 0 ? 1 : 0);
