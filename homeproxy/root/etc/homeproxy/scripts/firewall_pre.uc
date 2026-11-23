#!/usr/bin/ucode

'use strict';

import { writefile } from 'fs';
import { cursor } from 'uci';
import { RUN_DIR } from 'homeproxy';

const cfgname = 'homeproxy';
const uci = cursor();
uci.load(cfgname);

const routing_mode = uci.get(cfgname, 'config', 'routing_mode') || 'bypass_mainland_china',
      proxy_mode = uci.get(cfgname, 'config', 'proxy_mode') || 'redirect_tproxy';

let outbound_node, tun_name;
if (match(proxy_mode, /tun/)) {
	if (routing_mode === 'custom')
		outbound_node = uci.get(cfgname, 'routing', 'default_outbound') || 'nil';
	else if (routing_mode === 'simple')
		outbound_node = uci.get(cfgname, 'simple', 'default_outbound') || 'direct-out';
	else
		outbound_node = uci.get(cfgname, 'config', 'main_node') || 'nil';

	if (outbound_node !== 'nil')
		tun_name = uci.get(cfgname, 'infra', 'tun_name') || 'singtun0';
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

		let proto = s.network || '{ tcp, udp }';
		push(input, `meta l4proto ${proto} th dport ${s.port} counter accept comment "!${cfgname}: accept server ${s['.name']}"`);
	});
}

/* Always (re)write both includes, even when empty, so stale rules from a
 * previous configuration cannot survive a reload. */
writefile(RUN_DIR + '/fw4_forward.nft', join('\n', forward) + '\n');
writefile(RUN_DIR + '/fw4_input.nft', join('\n', input) + '\n');
