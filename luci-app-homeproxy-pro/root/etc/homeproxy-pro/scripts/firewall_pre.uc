#!/usr/bin/ucode
/* SPDX-License-Identifier: GPL-2.0-only
 *
 * Copyright (C) 2025 ImmortalWrt.org
 */

'use strict';

import { writefile } from 'fs';
import { cursor } from 'uci';
import { isEmpty, RUN_DIR, validation } from './homeproxy-pro.uc';

const cfgname = 'homeproxy-pro';
const uci = cursor();
uci.load(cfgname);

const routing_mode = uci.get(cfgname, 'config', 'routing_mode') || 'bypass_mainland_china',
      proxy_mode = uci.get(cfgname, 'config', 'proxy_mode') || 'redirect_tproxy';

let outbound_node, tun_name;
if (match(proxy_mode, /tun/)) {
	if (routing_mode === 'custom')
		outbound_node = uci.get(cfgname, 'routing', 'default_outbound') || 'nil';
	else
		outbound_node = uci.get(cfgname, 'config', 'main_node') || 'nil';

	/* Validate the interface name before it is interpolated into an nft
	 * ruleset that fw4 loads as root. It is a UCI value, and this file's own
	 * threat model treats UCI as untrusted - the port and network fields a few
	 * lines below are validated for exactly that reason, while tun_name was
	 * not. `;` and `}` need no newline, so a value like
	 * "singtun0 } ; chain evil { ..." would balance the template's trailing
	 * brace and add a chain of the attacker's choosing.
	 *
	 * Linux interface names are at most 15 characters and cannot contain
	 * whitespace or shell/nft metacharacters; anything outside that is not a
	 * name we could have created, so the tun rules are simply not emitted. */
	if (outbound_node !== 'nil') {
		const candidate = uci.get(cfgname, 'infra', 'tun_name') || 'singtun0';

		if (match(candidate, /^[A-Za-z0-9_.-]{1,15}$/) && candidate !== '.' && candidate !== '..')
			tun_name = candidate;
		else
			print(sprintf('WARN: ignoring invalid tun_name "%s" (not a valid interface name).', candidate));
	}
}

const server_enabled = uci.get(cfgname, 'server', 'enabled');

let forward = [],
    input = [];

if (tun_name) {
	push(forward, `oifname ${tun_name} counter accept comment "!${cfgname}: accept tun forward"`);
	push(input ,`iifname ${tun_name} counter accept comment "!${cfgname}: accept tun input"`);
}

if (server_enabled === '1') {
	uci.foreach(cfgname, 'server', (s) => {
		if (s.enabled !== '1' || s.firewall !== '1')
			return;

		/* The section name is interpolated into the nft comment below, in a
		 * file fw4 loads as root. libuci only accepts [A-Za-z0-9_] in a
		 * section name (a `"`, `}`, `;`, space, `.` or `-` is "invalid
		 * character in name field" / "Invalid argument" on both the parser
		 * and the `uci set` path), so today no name that could close the
		 * comment can reach this loop through UCI at all - this mirrors the
		 * tun_name guard above rather than trusting a writer's in-memory
		 * cursor or a future libuci. The alphabet is exactly libuci's and
		 * there is deliberately no length cap (libuci has none, and a cap
		 * would skip a legal name and silently drop that server's rule).
		 * The check runs first so the two warnings below only ever echo a
		 * name that already passed it. */
		if (!match(s['.name'], /^[A-Za-z0-9_]+$/)) {
			print(`WARN: skipping server ${s['.name']}: invalid section name.`);
			return;
		}

		if (!validation('port', s.port)) {
			print(`WARN: skipping server ${s['.name']}: invalid port "${s.port}".`);
			return;
		}

		let proto = s.network || '{ tcp, udp }';
		if (!(proto in ['tcp', 'udp', '{ tcp, udp }'])) {
			print(`WARN: skipping server ${s['.name']}: invalid network "${proto}".`);
			return;
		}

		push(input, `meta l4proto ${proto} th dport ${s.port} counter accept comment "!${cfgname}: accept server ${s['.name']}"`);
	});
}

if (!isEmpty(forward))
	writefile(RUN_DIR + '/fw4_forward.nft', join('\n', forward) + '\n');

if (!isEmpty(input))
	writefile(RUN_DIR + '/fw4_input.nft', join('\n', input) + '\n');
