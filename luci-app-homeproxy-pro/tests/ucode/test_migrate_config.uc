#!/usr/bin/ucode
/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * Driver for tests/ucode/test_migrate_config.sh.
 *
 * migrate_config.uc has no exports: the migration executes at import
 * time and writes through a UCI cursor. The staged copy of
 * migrate_config.uc has been rewritten by the runner so its cursor
 * reads ARGV[0] (the sandbox dir) instead of /etc/config - so this
 * driver just imports it and lets the side effect run.
 *
 * The assertions below then re-read the sandbox and check the
 * post-state step by step, so a failure names the migration step
 * that regressed rather than "migrate broke something".
 */

'use strict';

import { cursor } from 'uci';

import 'migrate_config';

const uci = cursor(ARGV[0]);
uci.load('homeproxy-pro');

let failures = 0,
    checks = 0;

function expect(name, actual, want) {
	checks++;
	if (sprintf('%J', actual) !== sprintf('%J', want)) {
		printf('FAIL %s: expected %J, got %J\n', name, want, actual);
		failures++;
	}
}

/* --- infra section ---------------------------------------------------- */

/* chinadns-ng removed: china_dns_port deleted. */
expect('infra.china_dns_port deleted', uci.get('homeproxy-pro', 'infra', 'china_dns_port'), null);

/* github_token moved from infra to config. */
expect('config.github_token set', uci.get('homeproxy-pro', 'config', 'github_token'), 'secret');
expect('infra.github_token deleted', uci.get('homeproxy-pro', 'infra', 'github_token'), null);

/* ntp_server introduced, defaults to the 'nil' sentinel. */
expect('infra.ntp_server default', uci.get('homeproxy-pro', 'infra', 'ntp_server'), 'nil');

/* tun_gso deprecated in sing-box 1.11: absent here, so nothing to do -
 * assert it stays absent rather than flapping to a default. */
expect('infra.tun_gso stays absent', uci.get('homeproxy-pro', 'infra', 'tun_gso'), null);

/* --- config section --------------------------------------------------- */

/* single-value chinadns server: legacy 'wan_114' maps to 114.114.114.114. */
expect('config.china_dns_server→114', uci.get('homeproxy-pro', 'config', 'china_dns_server'), '114.114.114.114');

/* log_level introduced, defaults to 'warn'. */
expect('config.log_level default', uci.get('homeproxy-pro', 'config', 'log_level'), 'warn');

/* routing_port='all' means "every port" = no option at all. */
expect('config.routing_port deleted', uci.get('homeproxy-pro', 'config', 'routing_port'), null);

/* --- dns section ------------------------------------------------------ */

/* default_server='block-dns' becomes 'default-dns' plus an appended
 * reject rule that reproduces the old "block everything" behaviour. */
expect('dns.default_server→default-dns', uci.get('homeproxy-pro', 'dns', 'default_server'), 'default-dns');
expect('dns final-block action', uci.get('homeproxy-pro', '_migration_dns_final_block', 'action'), 'reject');
expect('dns final-block enabled', uci.get('homeproxy-pro', '_migration_dns_final_block', 'enabled'), '1');

/* sing-box 1.14 deprecated DNS semantics. */
expect('dns.independent_cache deleted', uci.get('homeproxy-pro', 'dns', 'independent_cache'), null);
expect('dns.store_rdrc→store_dns', uci.get('homeproxy-pro', 'dns', 'cache_file_store_dns'), '1');
expect('dns.store_rdrc deleted', uci.get('homeproxy-pro', 'dns', 'cache_file_store_rdrc'), null);
expect('dns.rdrc_timeout deleted', uci.get('homeproxy-pro', 'dns', 'cache_file_rdrc_timeout'), null);

/* --- dns_server: legacy address form ---------------------------------- */

/* 'tls://1.1.1.1:853' splits into type/server/server_port, and the
 * legacy address key is dropped so the generator stops reading it. */
expect('ds_default.type', uci.get('homeproxy-pro', 'ds_default', 'type'), 'tls');
expect('ds_default.server', uci.get('homeproxy-pro', 'ds_default', 'server'), '1.1.1.1');
expect('ds_default.server_port', uci.get('homeproxy-pro', 'ds_default', 'server_port'), '853');
expect('ds_default.address deleted', uci.get('homeproxy-pro', 'ds_default', 'address'), null);

/* strategy / client_subnet moved out of the dns_server and into the
 * dns_rule that referenced it. */
expect('ds_default.strategy deleted', uci.get('homeproxy-pro', 'ds_default', 'strategy'), null);
expect('ds_default.client_subnet deleted', uci.get('homeproxy-pro', 'ds_default', 'client_subnet'), null);
expect('dr_uses_default.strategy', uci.get('homeproxy-pro', 'dr_uses_default', 'strategy'), 'prefer_ipv4');
expect('dr_uses_default.client_subnet', uci.get('homeproxy-pro', 'dr_uses_default', 'client_subnet'), '1.2.3.0/24');

/* RCode-as-address migrated into the predefined-rcode rule form; the
 * dns_server section itself is removed. */
expect('ds_rcode section deleted', uci.get_all('homeproxy-pro', 'ds_rcode'), null);

/* --- dns_rule --------------------------------------------------------- */

/* server='block-dns' moved into action='reject'. */
expect('dr_block.action=reject', uci.get('homeproxy-pro', 'dr_block', 'action'), 'reject');
expect('dr_block.server deleted', uci.get('homeproxy-pro', 'dr_block', 'server'), null);

/* rule_set_ipcidr_match_source renamed to rule_set_ip_cidr_match_source. */
expect('dr_stale.old key deleted', uci.get('homeproxy-pro', 'dr_stale', 'rule_set_ipcidr_match_source'), null);
expect('dr_stale.new key set', uci.get('homeproxy-pro', 'dr_stale', 'rule_set_ip_cidr_match_source'), '1');

/* a rule with no action gets the 'route' default. */
expect('dr_uses_default.action=route', uci.get('homeproxy-pro', 'dr_uses_default', 'action'), 'route');

/* --- routing_rule ----------------------------------------------------- */

/* outbound='block-out' moved into action='reject'. */
expect('rr_block.action=reject', uci.get('homeproxy-pro', 'rr_block', 'action'), 'reject');
expect('rr_block.outbound deleted', uci.get('homeproxy-pro', 'rr_block', 'outbound'), null);

/* --- server ----------------------------------------------------------- */

/* auto_firewall was a single global flag; it is redistributed onto
 * each server section as firewall='1'. */
expect('srv_one.firewall set', uci.get('homeproxy-pro', 'srv_one', 'firewall'), '1');
expect('server.auto_firewall deleted', uci.get('homeproxy-pro', 'server', 'auto_firewall'), null);

/* sniff_override deprecated in sing-box 1.11. */
expect('srv_one.sniff_override deleted', uci.get('homeproxy-pro', 'srv_one', 'sniff_override'), null);

/* server log_level introduced, defaults to 'warn'. */
expect('server.log_level default', uci.get('homeproxy-pro', 'server', 'log_level'), 'warn');

/* --- migration bookkeeping -------------------------------------------- */

/* the migration marker section must survive so the crontab cleanup
 * does not run twice. */
expect('migration.crontab marker', uci.get('homeproxy-pro', 'migration', 'crontab'), '1');

/* --- summary ---------------------------------------------------------- */

if (failures > 0)
	printf('FAIL: %d/%d checks failed\n', failures, checks);
else
	printf('PASS: %d checks\n', checks);

exit(failures > 0 ? 1 : 0);
