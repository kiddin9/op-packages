#!/usr/bin/ucode
/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * Copyright (C) 2025 ImmortalWrt.org
 */

'use strict';

import { popen } from 'fs';
import { cursor } from 'uci';
import { isEmpty, parseURL } from 'homeproxy';

const uci = cursor();

const uciconfig = 'homeproxy';
uci.load(uciconfig);

function random_secret() {
	const fd = popen('tr -dc "A-Za-z0-9" < /dev/urandom 2>/dev/null | head -c 16');
	let random = '';
	if (fd) {
		random = trim(fd.read('all') || '');
		fd.close();
	}

	if (isEmpty(random)) {
		const fallback = popen('awk \'BEGIN{srand(); printf "%06d", int(rand() * 1000000)}\'');
		if (fallback) {
			random = trim(fallback.read('all') || '');
			fallback.close();
		}
	}

	return random;
}

const uciinfra = 'infra',
      ucimigration = 'migration',
      ucimain = 'config',
      ucinode = 'node',
      ucidns = 'dns',
      ucidnsserver = 'dns_server',
      ucidnsrule = 'dns_rule',
      ucirouting = 'routing',
      uciroutingnode = 'routing_node',
      uciroutingrule = 'routing_rule',
      uciclashapi = 'clash_api',
      ucintp = 'ntp',
      ucicache = 'cache',
      uciserver = 'server';

function is_update_cron(value) {
	let matched = match(value || '', /^(\d{1,2})\s+(\d{1,2})\s+\*\s+\*\s+([0-7*])$/);
	return !isEmpty(matched) && int(matched[1]) <= 59 && int(matched[2]) <= 23;
}

/* chinadns-ng has been removed */
if (uci.get(uciconfig, uciinfra, 'china_dns_port'))
	uci.delete(uciconfig, uciinfra, 'china_dns_port');

/* chinadns server now only accepts single server */
const china_dns_server = uci.get(uciconfig, ucimain, 'china_dns_server');
if (type(china_dns_server) === 'array') {
	uci.set(uciconfig, ucimain, 'china_dns_server', china_dns_server[0]);
} else {
	if (match(china_dns_server, /,/))
		uci.set(uciconfig, ucimain, 'china_dns_server', split(china_dns_server, ',')[0]);
}

/* github_token option has been moved to config section */
const github_token = uci.get(uciconfig, uciinfra, 'github_token');
if (github_token) {
	uci.set(uciconfig, ucimain, 'github_token', github_token);
	uci.delete(uciconfig, uciinfra, 'github_token')
}

/* ntp_server was introduced */
if (!uci.get(uciconfig, uciinfra, 'ntp_server'))
	uci.set(uciconfig, uciinfra, 'ntp_server', 'nil');

/* tun_gso was deprecated in sb 1.11 */
if (!isEmpty(uci.get(uciconfig, uciinfra, 'tun_gso')))
	uci.delete(uciconfig, uciinfra, 'tun_gso');

/* endpoint_independent_nat was removed in sing-box 1.13 */
if (!isEmpty(uci.get(uciconfig, ucirouting, 'endpoint_independent_nat')))
	uci.delete(uciconfig, ucirouting, 'endpoint_independent_nat');

/* direct outbound proxy_protocol was removed in sing-box 1.13 */
uci.foreach(uciconfig, ucinode, (cfg) => {
	if (cfg.type === 'direct' && !isEmpty(cfg.proxy_protocol))
		uci.delete(uciconfig, cfg['.name'], 'proxy_protocol');
});

const legacy_panel_url = 'https://github.com/Zephyruso/zashboard/releases/latest/download/dist.zip';
const legacy_panel_proxy_url = 'https://gh-proxy.com/https://github.com/Zephyruso/zashboard/releases/latest/download/dist.zip';
const old_panel_url = 'https://github.com/Zephyruso/zashboard/releases/latest/download/dist-cdn-fonts.zip';
const old_panel_proxy_url = 'https://gh-proxy.com/https://github.com/Zephyruso/zashboard/releases/latest/download/dist-cdn-fonts.zip';
const default_panel_url = 'https://gh-proxy.com/https://github.com/Zephyruso/zashboard/releases/latest/download/dist-cdn-fonts.zip';

/* clash api panel options were introduced */
if (!uci.get(uciconfig, uciclashapi))
	uci.set(uciconfig, uciclashapi, uciconfig);

if (isEmpty(uci.get(uciconfig, uciclashapi, 'external_ui')))
	uci.set(uciconfig, uciclashapi, 'external_ui', '/etc/homeproxy/run/ui');

const panel_url = uci.get(uciconfig, uciclashapi, 'external_ui_download_url');
if (isEmpty(panel_url) || panel_url === legacy_panel_url || panel_url === legacy_panel_proxy_url || panel_url === old_panel_proxy_url)
	uci.set(uciconfig, uciclashapi, 'external_ui_download_url', default_panel_url);

if (isEmpty(uci.get(uciconfig, uciclashapi, 'external_ui_download_detour')))
	uci.set(uciconfig, uciclashapi, 'external_ui_download_detour', 'direct-out');

if (isEmpty(uci.get(uciconfig, uciclashapi, 'external_controller')))
	uci.set(uciconfig, uciclashapi, 'external_controller', '0.0.0.0:9095');

if (isEmpty(uci.get(uciconfig, uciclashapi, 'secret')) || uci.get(uciconfig, uciclashapi, 'secret') === 'homeproxy') {
	let random = random_secret();
	if (!isEmpty(random))
		uci.set(uciconfig, uciclashapi, 'secret', random);
}

if (isEmpty(uci.get(uciconfig, uciclashapi, 'default_mode')))
	uci.set(uciconfig, uciclashapi, 'default_mode', 'rule');

/* ntp options were moved into a dedicated section */
if (!uci.get(uciconfig, ucintp))
	uci.set(uciconfig, ucintp, uciconfig);

const legacy_ntp_server = uci.get(uciconfig, uciinfra, 'ntp_server');
if (isEmpty(uci.get(uciconfig, ucintp, 'enabled')))
	uci.set(uciconfig, ucintp, 'enabled', '1');

if (isEmpty(uci.get(uciconfig, ucintp, 'server')))
	uci.set(uciconfig, ucintp, 'server', !isEmpty(legacy_ntp_server) ? legacy_ntp_server : 'ntp.aliyun.com');

if (isEmpty(uci.get(uciconfig, ucintp, 'server_port')))
	uci.set(uciconfig, ucintp, 'server_port', '123');

if (isEmpty(uci.get(uciconfig, ucintp, 'interval')))
	uci.set(uciconfig, ucintp, 'interval', '30m');

/* cache file options were moved into a dedicated section */
if (!uci.get(uciconfig, ucicache))
	uci.set(uciconfig, ucicache, uciconfig);

if (isEmpty(uci.get(uciconfig, ucicache, 'enabled')))
	uci.set(uciconfig, ucicache, 'enabled', '1');

const old_cache_path = '/var/run/homeproxy/cache.db';
const default_cache_path = '/etc/homeproxy/cache.db';
const cache_path = uci.get(uciconfig, ucicache, 'path');
if (isEmpty(cache_path) || cache_path === old_cache_path)
	uci.set(uciconfig, ucicache, 'path', default_cache_path);

if (!isEmpty(uci.get(uciconfig, ucicache, 'store_fakeip')))
	uci.delete(uciconfig, ucicache, 'store_fakeip');

if (isEmpty(uci.get(uciconfig, ucicache, 'store_rdrc')))
	uci.set(uciconfig, ucicache, 'store_rdrc', isEmpty(uci.get(uciconfig, ucidns, 'cache_file_store_rdrc')) ? '1' : uci.get(uciconfig, ucidns, 'cache_file_store_rdrc'));

if (isEmpty(uci.get(uciconfig, ucicache, 'rdrc_timeout')) && !isEmpty(uci.get(uciconfig, ucidns, 'cache_file_rdrc_timeout')))
	uci.set(uciconfig, ucicache, 'rdrc_timeout', uci.get(uciconfig, ucidns, 'cache_file_rdrc_timeout'));

if (!isEmpty(uci.get(uciconfig, ucidns, 'cache_file_store_rdrc')))
	uci.delete(uciconfig, ucidns, 'cache_file_store_rdrc');

if (!isEmpty(uci.get(uciconfig, ucidns, 'cache_file_rdrc_timeout')))
	uci.delete(uciconfig, ucidns, 'cache_file_rdrc_timeout');

/* create migration section */
if (!uci.get(uciconfig, ucimigration))
	uci.set(uciconfig, ucimigration, uciconfig);

/* delete old crontab command */
const migration_crontab = uci.get(uciconfig, ucimigration, 'crontab');
if (!migration_crontab) {
	system('sed -i "/update_crond.sh/d" "/etc/crontabs/root" 2>"/dev/null"');
	uci.set(uciconfig, ucimigration, 'crontab', '1');
}

/* log_level was introduced */
if (isEmpty(uci.get(uciconfig, ucimain, 'log_level')))
	uci.set(uciconfig, ucimain, 'log_level', 'warn');

if (isEmpty(uci.get(uciconfig, uciserver, 'log_level')))
	uci.set(uciconfig, uciserver, 'log_level', 'warn');

if (!isEmpty(uci.get(uciconfig, 'subscription', 'auto_update_time')) &&
    !is_update_cron(uci.get(uciconfig, 'subscription', 'auto_update_time')))
	uci.set(uciconfig, 'subscription', 'auto_update_time', '0 0 * * *');

/* empty value defaults to all ports now */
if (uci.get(uciconfig, ucimain, 'routing_port') === 'all')
	uci.delete(uciconfig, ucimain, 'routing_port');

/* experimental section was removed */
if (uci.get(uciconfig, 'experimental'))
	uci.delete(uciconfig, 'experimental');

/* block-dns was removed from built-in dns servers */
const default_dns_server = uci.get(uciconfig, ucidns, 'default_server');
if (default_dns_server === 'block-dns') {
	/* append a rule at last to block all DNS queries */
	uci.set(uciconfig, '_migration_dns_final_block', ucidnsrule);
	uci.set(uciconfig, '_migration_dns_final_block', 'label', 'migration_final_block_dns');
	uci.set(uciconfig, '_migration_dns_final_block', 'enabled', '1');
	uci.set(uciconfig, '_migration_dns_final_block', 'mode', 'default');
	uci.set(uciconfig, '_migration_dns_final_block', 'action', 'reject');
	uci.set(uciconfig, ucidns, 'default_server', 'default-dns');
}

const dns_server_migration = {};
/* DNS servers options */
uci.foreach(uciconfig, ucidnsserver, (cfg) => {
	/* legacy format was deprecated in sb 1.12 */
	if (cfg.address) {
		const addr = parseURL((!match(cfg.address, /:\/\//) ? 'udp://' : '') + (validation('ip6addr', cfg.address) ? `[${cfg.address}]` : cfg.address));
		/* RCode was moved into DNS rules */
		if (addr.protocol === 'rcode') {
			dns_server_migration[cfg['.name']] = { action: 'predefined' };
			switch (addr.hostname) {
			case 'success':
				dns_server_migration[cfg['.name']].rcode = 'NOERROR';
				break;
			case 'format_error':
				dns_server_migration[cfg['.name']].rcode = 'FORMERR';
				break;
			case 'server_failure':
				dns_server_migration[cfg['.name']].rcode = 'SERVFAIL';
				break;
			case 'name_error':
				dns_server_migration[cfg['.name']].rcode = 'NXDOMAIN';
				break;
			case 'not_implemented':
				dns_server_migration[cfg['.name']].rcode = 'NOTIMP';
				break;
			case 'refused':
			default:
				dns_server_migration[cfg['.name']].rcode = 'REFUSED';
				break;
			}

			uci.delete(uciconfig, cfg['.name']);
			return;
		}
		uci.set(uciconfig, cfg['.name'], 'type', addr.protocol);
		uci.set(uciconfig, cfg['.name'], 'server', addr.hostname);
		uci.set(uciconfig, cfg['.name'], 'server_port', addr.port);
		uci.set(uciconfig, cfg['.name'], 'path', (addr.pathname !== '/') ? addr.pathname : null);
		uci.delete(uciconfig, cfg['.name'], 'address');
	}

	if (cfg.strategy) {
		if (cfg['.name'] === default_dns_server)
			uci.set(uciconfig, ucidns, 'default_strategy', cfg.strategy);
		dns_server_migration[cfg['.name']] = { strategy: cfg.strategy };
		uci.delete(uciconfig, cfg['.name'], 'strategy');
	}

	if (cfg.client_subnet) {
		if (cfg['.name'] === default_dns_server)
			uci.set(uciconfig, ucidns, 'client_subnet', cfg.client_subnet);

		if (isEmpty(dns_server_migration[cfg['.name']]))
			dns_server_migration[cfg['.name']] = {};
		dns_server_migration[cfg['.name']].client_subnet = cfg.client_subnet;
		uci.delete(uciconfig, cfg['.name'], 'client_subnet');
	}
});

/* DNS rules options */
uci.foreach(uciconfig, ucidnsrule, (cfg) => {
	/* outbound was removed in sb 1.12 */
	if (cfg.outbound) {
		uci.delete(uciconfig, cfg['.name']);
		if (!cfg.enabled)
			return;

		map(cfg.outbound, (outbound) => {
			switch (outbound) {
			case 'direct-out':
			case 'block-out':
				break;
			case 'any-out':
				uci.set(uciconfig, ucirouting, 'default_outbound_dns', cfg.server);
				break;
			default:
				uci.set(uciconfig, cfg.outbound, 'domain_resolver', cfg.server);
				break;
			}
		});

		return;
	}

	/* rule_set_ipcidr_match_source was renamed in sb 1.10 */
	if (cfg.rule_set_ipcidr_match_source === '1')
		uci.rename(uciconfig, cfg['.name'], 'rule_set_ipcidr_match_source', 'rule_set_ip_cidr_match_source');

	/* block-dns was moved into action in sb 1.11 */
	if (cfg.server === 'block-dns') {
		uci.set(uciconfig, cfg['.name'], 'action', 'reject');
		uci.delete(uciconfig, cfg['.name'], 'server');
	} else if (!cfg.action) {
		/* add missing 'action' field */
		uci.set(uciconfig, cfg['.name'], 'action', 'route');
	}

	/* strategy and client_subnet were moved into dns rules */
	if (dns_server_migration[cfg.server]) {
		if (dns_server_migration[cfg.server].strategy)
			uci.set(uciconfig, cfg['.name'], 'strategy', dns_server_migration[cfg.server].strategy);

		if (dns_server_migration[cfg.server].client_subnet)
			uci.set(uciconfig, cfg['.name'], 'client_subnet', dns_server_migration[cfg.server].client_subnet);

		if (dns_server_migration[cfg.server].rcode) {
			uci.set(uciconfig, cfg['.name'], 'action', 'predefined');
			uci.set(uciconfig, cfg['.name'], 'rcode', dns_server_migration[cfg.server].rcode);
			uci.delete(uciconfig, cfg['.name'], 'server');
		}
	}
});

/* nodes options */
uci.foreach(uciconfig, ucinode, (cfg) => {
	/* tls_ech_tls_disable_drs is useless and deprecated in sb 1.12 */
	if (!isEmpty(cfg.tls_ech_tls_disable_drs))
		uci.delete(uciconfig, cfg['.name'], 'tls_ech_tls_disable_drs');

	/* tls_ech_enable_pqss is useless and deprecated in sb 1.12 */
	if (!isEmpty(cfg.tls_ech_enable_pqss))
		uci.delete(uciconfig, cfg['.name'], 'tls_ech_enable_pqss');

	/* wireguard_gso was deprecated in sb 1.11 */
	if (!isEmpty(cfg.wireguard_gso))
		uci.delete(uciconfig, cfg['.name'], 'wireguard_gso');
});

/* routing rules options */
uci.foreach(uciconfig, uciroutingrule, (cfg) => {
	/* rule_set_ipcidr_match_source was renamed in sb 1.10 */
	if (cfg.rule_set_ipcidr_match_source === '1')
		uci.rename(uciconfig, cfg['.name'], 'rule_set_ipcidr_match_source', 'rule_set_ip_cidr_match_source');

	/* block-out was moved into action in sb 1.11 */
	if (cfg.outbound === 'block-out') {
		uci.set(uciconfig, cfg['.name'], 'action', 'reject');
		uci.delete(uciconfig, cfg['.name'], 'outbound');
	} else if (!cfg.action) {
		/* add missing 'action' field */
		uci.set(uciconfig, cfg['.name'], 'action', 'route');
	}
});

/* routing node options */
uci.foreach(uciconfig, uciroutingnode, (cfg) => {
	if (cfg.node === 'urltest' && !isEmpty(cfg.urltest_nodes)) {
		let custom_nodes = [],
		    subscription_nodes = [];

		for (let node in (type(cfg.urltest_nodes) === 'array' ? cfg.urltest_nodes : [ cfg.urltest_nodes ])) {
			let node_cfg = uci.get_all(uciconfig, node);
			if (isEmpty(node_cfg))
				continue;

			if (!isEmpty(node_cfg.grouphash))
				push(subscription_nodes, node);
			else
				push(custom_nodes, node);
		}

		if (isEmpty(cfg.selected_nodes) && !isEmpty(custom_nodes))
			uci.set(uciconfig, cfg['.name'], 'selected_nodes', custom_nodes);

		if (isEmpty(cfg.subscription_nodes) && !isEmpty(subscription_nodes))
			uci.set(uciconfig, cfg['.name'], 'subscription_nodes', subscription_nodes);

		uci.delete(uciconfig, cfg['.name'], 'urltest_nodes');
	}
});

/* rule set options */
uci.foreach(uciconfig, uciruleset, (cfg) => {
	if (isEmpty(cfg.tag))
		uci.set(uciconfig, cfg['.name'], 'tag', 'cfg-' + cfg['.name'] + '-rule');

	if (cfg.type === 'remote') {
		if (isEmpty(cfg.auto_update))
			uci.set(uciconfig, cfg['.name'], 'auto_update', '1');

		if (!is_update_cron(cfg.update_interval))
			uci.set(uciconfig, cfg['.name'], 'update_interval', '0 0 * * *');
	}
});

/* server options */
/* auto_firewall was moved into server options */
const auto_firewall = uci.get(uciconfig, uciserver, 'auto_firewall');
if (!isEmpty(auto_firewall))
	uci.delete(uciconfig, uciserver, 'auto_firewall');

uci.foreach(uciconfig, uciserver, (cfg) => {
	if (!isEmpty(cfg.hysteria_revc_window_client) && isEmpty(cfg.hysteria_recv_window_client)) {
		uci.set(uciconfig, cfg['.name'], 'hysteria_recv_window_client', cfg.hysteria_revc_window_client);
	}

	if (!isEmpty(cfg.hysteria_revc_window_client))
		uci.delete(uciconfig, cfg['.name'], 'hysteria_revc_window_client');

	/* auto_firewall was moved into server options */
	if (auto_firewall === '1')
		uci.set(uciconfig, cfg['.name'], 'firewall' , '1');

	/* sniff_override was deprecated in sb 1.11 */
	if (!isEmpty(cfg.sniff_override))
		uci.delete(uciconfig, cfg['.name'], 'sniff_override');

	/* domain_strategy is now pointless without sniff override */
	if (!isEmpty(cfg.domain_strategy))
		uci.delete(uciconfig, cfg['.name'], 'domain_strategy');
});

if (!isEmpty(uci.changes(uciconfig)))
	uci.commit(uciconfig);
