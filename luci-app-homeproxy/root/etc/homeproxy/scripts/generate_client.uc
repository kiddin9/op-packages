#!/usr/bin/ucode
/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * Copyright (C) 2023-2025 ImmortalWrt.org
 */

'use strict';

import { md5 } from 'digest';
import { readfile, writefile } from 'fs';
import { isnan } from 'math';
import { connect } from 'ubus';
import { cursor } from 'uci';

import {
	isEmpty, parseURL, strToBool, strToInt, strToTime,
	removeBlankAttrs, validation, HP_DIR, RUN_DIR
} from 'homeproxy';

const ubus = connect();

/* const features = ubus.call('luci.homeproxy', 'singbox_get_features') || {}; */

/* UCI config start */
const uci = cursor();

const uciconfig = 'homeproxy';
uci.load(uciconfig);

const uciinfra = 'infra',
      ucimain = 'config',
      ucicontrol = 'control',
      uciclashapi = 'clash_api',
      ucintp = 'ntp',
      ucicache = 'cache';

const ucidnssetting = 'dns',
      ucidnsserver = 'dns_server',
      ucidnsrule = 'dns_rule';

const uciroutingsetting = 'routing',
      uciroutingnode = 'routing_node',
      uciroutingrule = 'routing_rule';

const ucinode = 'node';
const uciruleset = 'ruleset';
const RULESET_DIR = HP_DIR + '/ruleset';

const routing_mode = uci.get(uciconfig, ucimain, 'routing_mode') || 'bypass_mainland_china';

function normalize_list(value) {
	if (isEmpty(value))
		return [];
	if (type(value) === 'array')
		return value;
	return [value];
}

function ruleset_file_name(tag, format) {
	let filename = replace(tag || 'ruleset', /[^A-Za-z0-9_.-]+/g, '_');
	if (isEmpty(filename))
		filename = 'ruleset';

	return filename + ((format === 'source') ? '.json' : '.srs');
}

function ruleset_default_path(tag, format) {
	return RULESET_DIR + '/' + ruleset_file_name(tag, format);
}

function ruleset_remote_path(path, tag, format) {
	if (isEmpty(path))
		return ruleset_default_path(tag, format);

	if (match(path, /\/$/))
		return path + ruleset_file_name(tag, format);

	return path;
}

let wan_dns = ubus.call('network.interface', 'status', {'interface': 'wan'})?.['dns-server']?.[0];
if (!wan_dns)
	wan_dns = (routing_mode in ['proxy_mainland_china', 'global']) ? '9.9.9.9' : '223.5.5.5';

const dns_port = uci.get(uciconfig, uciinfra, 'dns_port') || '5333';

let ntp_enabled = uci.get(uciconfig, ucintp, 'enabled'),
    ntp_server = uci.get(uciconfig, ucintp, 'server'),
    ntp_server_port = uci.get(uciconfig, ucintp, 'server_port'),
    ntp_interval = uci.get(uciconfig, ucintp, 'interval');

if (isEmpty(ntp_enabled) && isEmpty(ntp_server)) {
	ntp_server = uci.get(uciconfig, uciinfra, 'ntp_server');
	ntp_enabled = !isEmpty(ntp_server) ? '1' : '0';
}

const ipv6_support = uci.get(uciconfig, ucimain, 'ipv6_support') || '0';

let cache_file_enabled, cache_file_path, cache_store_rdrc, cache_rdrc_timeout,
    main_node, main_udp_node, dedicated_udp_node, default_outbound, default_outbound_dns,
    domain_strategy, sniff_override, dns_server, china_dns_server, dns_default_strategy,
    dns_default_server, dns_disable_cache, dns_disable_cache_expire, dns_independent_cache,
    dns_client_subnet, direct_domain_list,
    proxy_domain_list;

if (routing_mode !== 'custom') {
	main_node = uci.get(uciconfig, ucimain, 'main_node') || 'nil';
	main_udp_node = uci.get(uciconfig, ucimain, 'main_udp_node') || 'nil';
	dedicated_udp_node = !isEmpty(main_udp_node) && !(main_udp_node in ['same', main_node]);

	dns_server = uci.get(uciconfig, ucimain, 'dns_server');
	if (isEmpty(dns_server) || dns_server === 'wan')
		dns_server = wan_dns;

	if (routing_mode === 'bypass_mainland_china') {
		china_dns_server = uci.get(uciconfig, ucimain, 'china_dns_server');
		if (isEmpty(china_dns_server) || type(china_dns_server) !== 'string' || china_dns_server === 'wan')
			china_dns_server = wan_dns;
	}
	dns_default_strategy = (ipv6_support !== '1') ? 'ipv4_only' : null;

	direct_domain_list = trim(readfile(HP_DIR + '/resources/direct_list.txt'));
	if (direct_domain_list)
		direct_domain_list = split(direct_domain_list, /[\r\n]/);

	proxy_domain_list = trim(readfile(HP_DIR + '/resources/proxy_list.txt'));
	if (proxy_domain_list)
		proxy_domain_list = split(proxy_domain_list, /[\r\n]/);

	sniff_override = uci.get(uciconfig, uciinfra, 'sniff_override') || '1';
} else {
	/* DNS settings */
	dns_default_strategy = uci.get(uciconfig, ucidnssetting, 'default_strategy');
	dns_default_server = uci.get(uciconfig, ucidnssetting, 'default_server');
	dns_disable_cache = uci.get(uciconfig, ucidnssetting, 'disable_cache');
	dns_disable_cache_expire = uci.get(uciconfig, ucidnssetting, 'disable_cache_expire');
	dns_independent_cache = uci.get(uciconfig, ucidnssetting, 'independent_cache');
	dns_client_subnet = uci.get(uciconfig, ucidnssetting, 'client_subnet');

	/* Routing settings */
	default_outbound = uci.get(uciconfig, uciroutingsetting, 'default_outbound') || 'nil';
	default_outbound_dns = uci.get(uciconfig, uciroutingsetting, 'default_outbound_dns') || 'default-dns';
	domain_strategy = uci.get(uciconfig, uciroutingsetting, 'domain_strategy');
	sniff_override = uci.get(uciconfig, uciroutingsetting, 'sniff_override');
}

const proxy_mode = uci.get(uciconfig, ucimain, 'proxy_mode') || 'redirect_tproxy',
      default_interface = uci.get(uciconfig, ucicontrol, 'bind_interface');

const mixed_port = uci.get(uciconfig, uciinfra, 'mixed_port') || '5330';

let self_mark, redirect_port, tproxy_port, tun_name,
    tun_addr4, tun_addr6, tun_mtu, tcpip_stack,
    udp_timeout;

if (routing_mode === 'custom')
	udp_timeout = uci.get(uciconfig, uciroutingsetting, 'udp_timeout');
else
	udp_timeout = uci.get(uciconfig, 'infra', 'udp_timeout');

if (match(proxy_mode, /redirect/)) {
	self_mark = uci.get(uciconfig, 'infra', 'self_mark') || '100';
	redirect_port = uci.get(uciconfig, 'infra', 'redirect_port') || '5331';
}
if (match(proxy_mode, /tproxy/))
	if (main_udp_node !== 'nil' || routing_mode === 'custom')
		tproxy_port = uci.get(uciconfig, 'infra', 'tproxy_port') || '5332';
if (match(proxy_mode, /tun/)) {
	tun_name = uci.get(uciconfig, uciinfra, 'tun_name') || 'singtun0';
	tun_addr4 = uci.get(uciconfig, uciinfra, 'tun_addr4') || '172.19.0.1/30';
	tun_addr6 = uci.get(uciconfig, uciinfra, 'tun_addr6') || 'fdfe:dcba:9876::1/126';
	tun_mtu = uci.get(uciconfig, uciinfra, 'tun_mtu') || '9000';
	tcpip_stack = 'system';
	if (routing_mode === 'custom')
		tcpip_stack = uci.get(uciconfig, uciroutingsetting, 'tcpip_stack') || 'system';
}

const log_level = uci.get(uciconfig, ucimain, 'log_level') || 'warn';

cache_file_enabled = uci.get(uciconfig, ucicache, 'enabled');
cache_file_path = uci.get(uciconfig, ucicache, 'path');
cache_store_rdrc = uci.get(uciconfig, ucicache, 'store_rdrc');
cache_rdrc_timeout = uci.get(uciconfig, ucicache, 'rdrc_timeout');

let clash_api = null;
/* UCI config end */

/* Config helper start */
function parse_port(strport) {
	if (type(strport) !== 'array' || isEmpty(strport))
		return null;

	let ports = [];
	for (let i in strport)
		push(ports, int(i));

	return ports;

}

function parse_dnsserver(server_addr, default_protocol) {
	if (isEmpty(server_addr))
		return null;

	if (!match(server_addr, /:\/\//))
		server_addr = (default_protocol || 'udp') + '://' + (validation('ip6addr', server_addr) ? `[${server_addr}]` : server_addr);
	server_addr = parseURL(server_addr);

	return {
		type: server_addr.protocol,
		server: server_addr.hostname,
		server_port: strToInt(server_addr.port),
		path: (server_addr.pathname !== '/') ? server_addr.pathname : null,
	}
}

function parse_custom_dnsserver(cfg) {
	let server = cfg.server,
	    server_port = (cfg.type in ['https', 'h3']) ? null : strToInt(cfg.server_port),
	    path = cfg.path;

	if (!isEmpty(server) && match(server, /:\/\//)) {
		const server_url = parseURL(server);

		server = server_url.hostname;
		if (isEmpty(server_port))
			server_port = strToInt(server_url.port);
		if ((cfg.type in ['https', 'h3']) && isEmpty(path) && server_url.pathname !== '/')
			path = server_url.pathname;
	}
	if ((cfg.type in ['https', 'h3']) && isEmpty(path))
		path = '/dns-query';

	return {
		type: cfg.type,
		server,
		server_port,
		path
	};
}

function parse_dnsquery(strquery) {
	if (type(strquery) !== 'array' || isEmpty(strquery))
		return null;

	let querys = [];
	for (let i in strquery)
		isnan(int(i)) ? push(querys, i) : push(querys, int(i));

	return querys;

}

function filter_existing_nodes(nodes) {
	if (type(nodes) !== 'array' || isEmpty(nodes))
		return [];

	return filter(nodes, (k) => {
		const node = uci.get_all(uciconfig, k) || {};
		return !isEmpty(node);
	});
}

function collect_group_nodes(groups, subscription_nodes, nodes, legacy_nodes) {
	let result = [];

	for (let group in normalize_list(groups))
		uci.foreach(uciconfig, ucinode, (cfg) => {
			if (cfg.grouphash === group && !~index(result, cfg['.name']))
				push(result, cfg['.name']);
		});

	for (let node in filter_existing_nodes(normalize_list(subscription_nodes)))
		if (!~index(result, node))
			push(result, node);

	for (let node in filter_existing_nodes(normalize_list(nodes)))
		if (!~index(result, node))
			push(result, node);

	for (let node in filter_existing_nodes(normalize_list(legacy_nodes)))
		if (!~index(result, node))
			push(result, node);

	return result;
}

function collect_policy_nodes(nodes, current) {
	let result = [];

	for (let node in normalize_list(nodes)) {
		if (node === current || ~index(result, node))
			continue;

		const outbound = uci.get_all(uciconfig, node) || {};
		if (!isEmpty(outbound) && outbound['.type'] === uciroutingnode && outbound.enabled === '1' && outbound.node in ['urltest', 'selector'])
			push(result, node);
	}

	return result;
}

const reserved_outbound_tags = {
	'GLOBAL': true,
	'main-out': true,
	'main-udp-out': true,
	'direct-out': true,
	'block-out': true
};

let outbound_tag_map = {},
    outbound_tag_used = {};

function normalize_outbound_tag(tag) {
	if (isEmpty(tag))
		return null;

	tag = trim(sprintf('%s', tag));
	tag = replace(tag, /[\r\n\t]+/g, ' ');
	tag = replace(tag, /[\/\\?#%]+/g, '-');
	tag = replace(tag, /\s+/g, ' ');

	return tag || null;
}

function section_display_name(section) {
	if (type(section) !== 'object' || isEmpty(section))
		return null;

	let label = normalize_outbound_tag(section.label);
	if (!isEmpty(label))
		return label;

	if (section['.type'] === ucinode) {
		const address = trim(section.override_address || section.address || '');
		const port = trim(section.override_port || section.port || '');

		if (address && port)
			return normalize_outbound_tag(`${address}:${port}`);
	}

	return null;
}

function register_outbound_tag(section_id, display_name) {
	if (isEmpty(section_id))
		return null;

	let tag = outbound_tag_map[section_id];
	if (!isEmpty(tag))
		return tag;

	const fallback_tag = `cfg-${section_id}-out`;
	const base_tag = normalize_outbound_tag(display_name) || fallback_tag;

	tag = base_tag;
	let suffix = 2;
	while (reserved_outbound_tags[tag] || outbound_tag_used[tag]) {
		tag = `${base_tag} (${suffix})`;
		suffix++;
	}

	outbound_tag_map[section_id] = tag;
	outbound_tag_used[tag] = true;

	return tag;
}

function get_section_outbound_tag(section_id) {
	if (isEmpty(section_id))
		return null;

	let tag = outbound_tag_map[section_id];
	if (!isEmpty(tag))
		return tag;

	const section = uci.get_all(uciconfig, section_id) || {};
	return register_outbound_tag(section_id, section_display_name(section));
}

uci.foreach(uciconfig, ucinode, (cfg) => {
	register_outbound_tag(cfg['.name'], section_display_name(cfg));
});

uci.foreach(uciconfig, uciroutingnode, (cfg) => {
	if (cfg.enabled === '1')
		register_outbound_tag(cfg['.name'], section_display_name(cfg));
});

function generate_endpoint(node) {
	if (type(node) !== 'object' || isEmpty(node))
		return null;

	const endpoint = {
		type: node.type,
		tag: get_section_outbound_tag(node['.name']),
		address: node.wireguard_local_address,
		mtu: strToInt(node.wireguard_mtu),
		private_key: node.wireguard_private_key,
		peers: (node.type === 'wireguard') ? [
			{
				address: node.address,
				port: strToInt(node.port),
				allowed_ips: [
					'0.0.0.0/0',
					'::/0'
				],
				persistent_keepalive_interval: strToInt(node.wireguard_persistent_keepalive_interval),
				public_key: node.wireguard_peer_public_key,
				pre_shared_key: node.wireguard_pre_shared_key,
				reserved: parse_port(node.wireguard_reserved),
			}
		] : null,
		system: (node.type === 'wireguard') ? false : null,
		tcp_fast_open: strToBool(node.tcp_fast_open),
		tcp_multi_path: strToBool(node.tcp_multi_path),
		udp_fragment: strToBool(node.udp_fragment)
	};

	return endpoint;
}

function generate_outbound(node) {
	if (type(node) !== 'object' || isEmpty(node))
		return null;

	const tls_utls_value = (node.type === 'anytls' && isEmpty(node.tls_utls)) ? 'chrome' : node.tls_utls;
	const outbound = {
		type: node.type,
		tag: get_section_outbound_tag(node['.name']),
		routing_mark: strToInt(self_mark),

		server: (node.type !== 'direct') ? node.address : null,
		server_port: (node.type !== 'direct') ? strToInt(node.port) : null,
		/* Hysteria(2) */
		server_ports: node.hysteria_hopping_port,

		username: (node.type !== 'ssh') ? node.username : null,
		user: (node.type === 'ssh') ? node.username : null,
		password: node.password,

		/* AnyTLS */
		idle_session_check_interval: strToTime(node.anytls_idle_session_check_interval),
		idle_session_timeout: strToTime(node.anytls_idle_session_timeout),
		min_idle_session: strToInt(node.anytls_min_idle_session),
		/* Hysteria (2) */
		hop_interval: strToTime(node.hysteria_hop_interval),
		up_mbps: strToInt(node.hysteria_up_mbps),
		down_mbps: strToInt(node.hysteria_down_mbps),
		obfs: node.hysteria_obfs_type ? {
			type: node.hysteria_obfs_type,
			password: node.hysteria_obfs_password
		} : node.hysteria_obfs_password,
		auth: (node.hysteria_auth_type === 'base64') ? node.hysteria_auth_payload : null,
		auth_str: (node.hysteria_auth_type === 'string') ? node.hysteria_auth_payload : null,
		recv_window_conn: strToInt(node.hysteria_recv_window_conn),
		recv_window: strToInt(node.hysteria_revc_window),
		disable_mtu_discovery: strToBool(node.hysteria_disable_mtu_discovery),
		/* Shadowsocks */
		method: node.shadowsocks_encrypt_method,
		plugin: node.shadowsocks_plugin,
		plugin_opts: node.shadowsocks_plugin_opts,
		/* ShadowTLS / Socks */
		version: (node.type === 'shadowtls') ? strToInt(node.shadowtls_version) : ((node.type === 'socks') ? node.socks_version : null),
		/* SSH */
		client_version: node.ssh_client_version,
		host_key: node.ssh_host_key,
		host_key_algorithms: node.ssh_host_key_algo,
		private_key: node.ssh_priv_key,
		private_key_passphrase: node.ssh_priv_key_pp,
		/* Tuic */
		uuid: node.uuid,
		congestion_control: node.tuic_congestion_control,
		udp_relay_mode: node.tuic_udp_relay_mode,
		udp_over_stream: strToBool(node.tuic_udp_over_stream),
		zero_rtt_handshake: strToBool(node.tuic_enable_zero_rtt),
		heartbeat: strToTime(node.tuic_heartbeat),
		/* VLESS / VMess */
		flow: node.vless_flow,
		alter_id: strToInt(node.vmess_alterid),
		security: node.vmess_encrypt,
		global_padding: strToBool(node.vmess_global_padding),
		authenticated_length: strToBool(node.vmess_authenticated_length),
		packet_encoding: node.packet_encoding,

		multiplex: (node.multiplex === '1') ? {
			enabled: true,
			protocol: node.multiplex_protocol,
			max_connections: strToInt(node.multiplex_max_connections),
			min_streams: strToInt(node.multiplex_min_streams),
			max_streams: strToInt(node.multiplex_max_streams),
			padding: strToBool(node.multiplex_padding),
			brutal: (node.multiplex_brutal === '1') ? {
				enabled: true,
				up_mbps: strToInt(node.multiplex_brutal_up),
				down_mbps: strToInt(node.multiplex_brutal_down)
			} : null
		} : null,
		tls: (node.tls === '1') ? {
			enabled: true,
			server_name: node.tls_sni,
			insecure: strToBool(node.tls_insecure),
			alpn: node.tls_alpn,
			min_version: node.tls_min_version,
			max_version: node.tls_max_version,
			cipher_suites: node.tls_cipher_suites,
			certificate_path: node.tls_cert_path,
			ech: (node.tls_ech === '1') ? {
				enabled: true,
				config: node.tls_ech_config,
				config_path: node.tls_ech_config_path
			} : null,
			utls: !isEmpty(tls_utls_value) ? {
				enabled: true,
				fingerprint: tls_utls_value
			} : null,
			reality: (node.tls_reality === '1') ? {
				enabled: true,
				public_key: node.tls_reality_public_key,
				short_id: node.tls_reality_short_id
			} : null
		} : null,
		transport: !isEmpty(node.transport) ? {
			type: node.transport,
			host: node.http_host || node.httpupgrade_host,
			path: node.http_path || node.ws_path,
			headers: node.ws_host ? {
				Host: node.ws_host
			} : null,
			method: node.http_method,
			max_early_data: strToInt(node.websocket_early_data),
			early_data_header_name: node.websocket_early_data_header,
			service_name: node.grpc_servicename,
			idle_timeout: strToTime(node.http_idle_timeout),
			ping_timeout: strToTime(node.http_ping_timeout),
			permit_without_stream: strToBool(node.grpc_permit_without_stream)
		} : null,
		udp_over_tcp: (node.udp_over_tcp === '1') ? {
			enabled: true,
			version: strToInt(node.udp_over_tcp_version)
		} : null,
		tcp_fast_open: strToBool(node.tcp_fast_open),
		tcp_multi_path: strToBool(node.tcp_multi_path),
		udp_fragment: strToBool(node.udp_fragment)
	};

	return outbound;
}

function get_outbound(cfg) {
	if (isEmpty(cfg))
		return null;

	if (type(cfg) === 'array') {
		if ('any-out' in cfg)
			return 'any';

		let outbounds = [];
		for (let i in cfg)
			push(outbounds, get_outbound(i));
		return outbounds;
	} else {
		switch (cfg) {
		case 'block-out':
		case 'direct-out':
			return cfg;
		default:
			const node = uci.get(uciconfig, cfg, 'node');
			if (isEmpty(node))
				die(sprintf("%s's node is missing, please check your configuration.", cfg));
			else if (node in ['urltest', 'selector'])
				return get_section_outbound_tag(cfg);
			else
				return get_section_outbound_tag(node);
		}
	}
}

function get_resolver(cfg) {
	if (isEmpty(cfg))
		return null;

	switch (cfg) {
	case 'default-dns':
	case 'system-dns':
		return cfg;
	default:
		return 'cfg-' + cfg + '-dns';
	}
}

function get_ruleset(cfg) {
	if (isEmpty(cfg))
		return null;

	let rules = [];
	for (let i in cfg) {
		if (isEmpty(i)) {
			push(rules, null);
			continue;
		}

		const ruleset = uci.get_all(uciconfig, i);
		push(rules, !isEmpty(ruleset?.tag) ? ruleset.tag : ('cfg-' + i + '-rule'));
	}
	return rules;
}

function subscription_provider_name(name) {
	name = trim(name || '');
	return name;
}

function unique_provider_name(name, used) {
	const base = name;
	let suffix = 2;

	while (used[name]) {
		name = sprintf('%s (%d)', base, suffix);
		suffix++;
	}
	used[name] = true;

	return name;
}

function get_subscription_info(group_hash) {
	const value = uci.get(uciconfig, 'subscription', 'subinfo_' + substr(group_hash, 0, 16));
	if (isEmpty(value))
		return null;

	try {
		const info = json(value);
		if (type(info) !== 'object')
			return null;

		const has_subscription_info = ('upload' in info) || ('download' in info) ||
		      ('total' in info) || ('expire' in info);

		return {
			updated_at: info.updated_at,
			subscription_info: has_subscription_info ? {
				upload: info.upload,
				download: info.download,
				total: info.total,
				expire: info.expire
			} : null
		};
	} catch (e) {
		return null;
	}
}

function build_proxy_providers() {
	let providers = [],
	    used_names = {},
	    subscription_names = normalize_list(uci.get(uciconfig, 'subscription', 'subscription_name')),
	    sub_index = 0;

	for (let suburl in normalize_list(uci.get(uciconfig, 'subscription', 'subscription_url'))) {
		const subscription_name = subscription_names[sub_index];
		sub_index++;

		if (isEmpty(suburl) || isEmpty(trim(subscription_name || '')))
			continue;

		const url = replace(suburl, /#.*$/, ''),
		      group_hash = md5(url);

		let proxies = [];
		uci.foreach(uciconfig, ucinode, (cfg) => {
			if (cfg.grouphash !== group_hash)
				return;

			const tag = get_section_outbound_tag(cfg['.name']);
			if (!isEmpty(tag) && !~index(proxies, tag))
				push(proxies, tag);
		});

		if (isEmpty(proxies))
			continue;

		const subscription_info = get_subscription_info(group_hash);

		push(providers, {
			name: unique_provider_name(subscription_provider_name(subscription_name), used_names),
			type: 'Proxy',
			vehicle_type: 'HTTP',
			proxies: proxies,
			update_id: (routing_mode === 'custom') ? group_hash : null,
			updated_at: subscription_info?.updated_at,
			subscription_info: subscription_info?.subscription_info
		});
	}

	return providers;
}

clash_api = {
	external_controller: uci.get(uciconfig, uciclashapi, 'external_controller') || '127.0.0.1:9090',
	external_ui: uci.get(uciconfig, uciclashapi, 'external_ui'),
	external_ui_download_url: uci.get(uciconfig, uciclashapi, 'external_ui_download_url'),
	external_ui_download_detour: get_outbound(uci.get(uciconfig, uciclashapi, 'external_ui_download_detour')),
	secret: uci.get(uciconfig, uciclashapi, 'secret'),
	default_mode: uci.get(uciconfig, uciclashapi, 'default_mode') || 'rule',
	proxy_providers: build_proxy_providers()
};
/* Config helper end */

const config = {};

/* Log */
config.log = {
	disabled: false,
	level: log_level,
	output: RUN_DIR + '/sing-box-c.log',
	timestamp: true
};

/* NTP */
if (!isEmpty(ntp_server))
	config.ntp = {
		enabled: ntp_enabled === '1',
		server: ntp_server,
		server_port: strToInt(ntp_server_port),
		interval: ntp_interval,
		detour: 'direct-out',
		domain_resolver: 'default-dns',
	};

/* DNS start */
/* Default settings */
config.dns = {
	servers: [
		{
			tag: 'default-dns',
			type: 'udp',
			server: wan_dns,
			detour: self_mark ? 'direct-out' : null
		},
		{
			tag: 'system-dns',
			type: 'local',
			detour: self_mark ? 'direct-out' : null
		}
	],
	rules: [],
	strategy: dns_default_strategy,
	disable_cache: strToBool(dns_disable_cache),
	disable_expire: strToBool(dns_disable_cache_expire),
	independent_cache: strToBool(dns_independent_cache),
	client_subnet: dns_client_subnet
};

if (!isEmpty(main_node)) {
	/* Main DNS */
	push(config.dns.servers, {
		tag: 'main-dns',
		domain_resolver: {
			server: 'default-dns',
			strategy: (ipv6_support !== '1') ? 'ipv4_only' : null
		},
		detour: 'main-out',
		...parse_dnsserver(dns_server, 'tcp')
	});
	config.dns.final = 'main-dns';

	if (length(direct_domain_list))
		push(config.dns.rules, {
			rule_set: 'direct-domain',
			action: 'route',
			server: (routing_mode === 'bypass_mainland_china') ? 'china-dns' : 'default-dns'
		});

	/* Filter out SVCB/HTTPS queries for "exquisite" Apple devices */
	if (routing_mode === 'gfwlist' || length(proxy_domain_list))
		push(config.dns.rules, {
			rule_set: (routing_mode !== 'gfwlist') ? 'proxy-domain' : null,
			query_type: [64, 65],
			action: 'reject'
		});

	if (routing_mode === 'bypass_mainland_china') {
		push(config.dns.servers, {
			tag: 'china-dns',
			domain_resolver: {
				server: 'default-dns',
				strategy: 'prefer_ipv6'
			},
			detour: self_mark ? 'direct-out' : null,
			...parse_dnsserver(china_dns_server)
		});

		if (length(proxy_domain_list))
			push(config.dns.rules, {
				rule_set: 'proxy-domain',
				action: 'route',
				server: 'main-dns'
			});

		push(config.dns.rules, {
			rule_set: 'geosite-cn',
			action: 'route',
			server: 'china-dns',
			strategy: 'prefer_ipv6'
		});
		push(config.dns.rules, {
			type: 'logical',
			mode: 'and',
			rules: [
				{
					rule_set: 'geosite-noncn',
					invert: true
				},
				{
					rule_set: 'geoip-cn'
				}
			],
			action: 'route',
			server: 'china-dns',
			strategy: 'prefer_ipv6'
		});
	}
} else if (!isEmpty(default_outbound)) {
	/* DNS servers */
	uci.foreach(uciconfig, ucidnsserver, (cfg) => {
		if (cfg.enabled !== '1')
			return;

		let outbound = get_outbound(cfg.outbound);
		if (outbound === 'direct-out' && isEmpty(self_mark))
			outbound = null;

		push(config.dns.servers, {
			tag: 'cfg-' + cfg['.name'] + '-dns',
			...parse_custom_dnsserver(cfg),
			headers: cfg.headers,
			tls: cfg.tls_sni ? {
				enabled: true,
				server_name: cfg.tls_sni
			} : null,
			domain_resolver: (cfg.address_resolver || cfg.address_strategy) ? {
				server: get_resolver(cfg.address_resolver || dns_default_server),
				strategy: cfg.address_strategy
			} : null,
			detour: outbound
		});
	});

	/* DNS rules */
	uci.foreach(uciconfig, ucidnsrule, (cfg) => {
		if (cfg.enabled !== '1')
			return;

		push(config.dns.rules, {
			ip_version: strToInt(cfg.ip_version),
			query_type: parse_dnsquery(cfg.query_type),
			network: cfg.network,
			protocol: cfg.protocol,
			domain: cfg.domain,
			domain_suffix: cfg.domain_suffix,
			domain_keyword: cfg.domain_keyword,
			domain_regex: cfg.domain_regex,
			port: parse_port(cfg.port),
			port_range: cfg.port_range,
			source_ip_cidr: cfg.source_ip_cidr,
			source_ip_is_private: strToBool(cfg.source_ip_is_private),
			ip_cidr: cfg.ip_cidr,
			ip_is_private: strToBool(cfg.ip_is_private),
			source_port: parse_port(cfg.source_port),
			source_port_range: cfg.source_port_range,
			process_name: cfg.process_name,
			process_path: cfg.process_path,
			process_path_regex: cfg.process_path_regex,
			user: cfg.user,
			rule_set: get_ruleset(cfg.rule_set),
			rule_set_ip_cidr_match_source: strToBool(cfg.rule_set_ip_cidr_match_source),
			invert: strToBool(cfg.invert),
			outbound: get_outbound(cfg.outbound),
			action: cfg.action,
			server: get_resolver(cfg.server),
			strategy: cfg.domain_strategy,
			disable_cache: strToBool(cfg.dns_disable_cache),
			rewrite_ttl: strToInt(cfg.rewrite_ttl),
			client_subnet: cfg.client_subnet,
			method: cfg.reject_method,
			no_drop: strToBool(cfg.reject_no_drop),
			rcode: cfg.predefined_rcode,
			answer: cfg.predefined_answer,
			ns: cfg.predefined_ns,
			extra: cfg.predefined_extra
		});
	});

	if (isEmpty(config.dns.rules))
		config.dns.rules = null;

	config.dns.final = get_resolver(dns_default_server);
}
/* DNS end */

/* Inbound start */
config.inbounds = [];

push(config.inbounds, {
	type: 'direct',
	tag: 'dns-in',
	listen: '::',
	listen_port: int(dns_port)
});

push(config.inbounds, {
	type: 'mixed',
	tag: 'mixed-in',
	listen: '::',
	listen_port: int(mixed_port),
	udp_timeout: strToTime(udp_timeout),
	set_system_proxy: false
});

if (match(proxy_mode, /redirect/))
	push(config.inbounds, {
		type: 'redirect',
		tag: 'redirect-in',

		listen: '::',
		listen_port: int(redirect_port)
	});
if (match(proxy_mode, /tproxy/))
	push(config.inbounds, {
		type: 'tproxy',
		tag: 'tproxy-in',

		listen: '::',
		listen_port: int(tproxy_port),
		network: 'udp',
		udp_timeout: strToTime(udp_timeout)
	});
if (match(proxy_mode, /tun/))
	push(config.inbounds, {
		type: 'tun',
		tag: 'tun-in',

		interface_name: tun_name,
		address: (ipv6_support === '1') ? [tun_addr4, tun_addr6] : [tun_addr4],
		mtu: strToInt(tun_mtu),
		auto_route: false,
		udp_timeout: strToTime(udp_timeout),
		stack: tcpip_stack
	});
/* Inbound end */

/* Outbound start */
config.endpoints = [];

/* Default outbounds */
config.outbounds = [
	{
		type: 'direct',
		tag: 'direct-out',
		routing_mark: strToInt(self_mark)
	},
	{
		type: 'block',
		tag: 'block-out'
	}
];

/* Main outbounds */
if (!isEmpty(main_node)) {
	let urltest_nodes = [];

	if (main_node === 'urltest') {
		const main_urltest_nodes = filter_existing_nodes(
			normalize_list(uci.get(uciconfig, ucimain, 'main_urltest_nodes'))
		);
		const main_urltest_interval = uci.get(uciconfig, ucimain, 'main_urltest_interval');
		const main_urltest_tolerance = uci.get(uciconfig, ucimain, 'main_urltest_tolerance');

		push(config.outbounds, {
			type: 'urltest',
			tag: 'main-out',
			outbounds: map(main_urltest_nodes, (k) => get_section_outbound_tag(k)),
			interval: strToTime(main_urltest_interval),
			tolerance: strToInt(main_urltest_tolerance),
			idle_timeout: (strToInt(main_urltest_interval) > 1800) ? `${main_urltest_interval * 2}s` : null,
		});
		urltest_nodes = main_urltest_nodes;
	} else {
		const main_node_cfg = uci.get_all(uciconfig, main_node) || {};
		if (main_node_cfg.type === 'wireguard') {
			const main_endpoint = generate_endpoint(main_node_cfg);
			if (main_endpoint) {
				main_endpoint.tag = 'main-out';
				push(config.endpoints, main_endpoint);
			}
		} else {
			const main_outbound = generate_outbound(main_node_cfg);
			if (main_outbound) {
				main_outbound.tag = 'main-out';
				push(config.outbounds, main_outbound);
			}
		}
	}

	if (main_udp_node === 'urltest') {
		const main_udp_urltest_nodes = filter_existing_nodes(
			normalize_list(uci.get(uciconfig, ucimain, 'main_udp_urltest_nodes'))
		);
		const main_udp_urltest_interval = uci.get(uciconfig, ucimain, 'main_udp_urltest_interval');
		const main_udp_urltest_tolerance = uci.get(uciconfig, ucimain, 'main_udp_urltest_tolerance');

		push(config.outbounds, {
			type: 'urltest',
			tag: 'main-udp-out',
			outbounds: map(main_udp_urltest_nodes, (k) => get_section_outbound_tag(k)),
			interval: strToTime(main_udp_urltest_interval),
			tolerance: strToInt(main_udp_urltest_tolerance),
			idle_timeout: (strToInt(main_udp_urltest_interval) > 1800) ? `${main_udp_urltest_interval * 2}s` : null,
		});
		urltest_nodes = [...urltest_nodes, ...filter(main_udp_urltest_nodes, (l) => !~index(urltest_nodes, l))];
	} else if (dedicated_udp_node) {
		const main_udp_node_cfg = uci.get_all(uciconfig, main_udp_node) || {};
		if (main_udp_node_cfg.type === 'wireguard') {
			const main_udp_endpoint = generate_endpoint(main_udp_node_cfg);
			if (main_udp_endpoint) {
				main_udp_endpoint.tag = 'main-udp-out';
				push(config.endpoints, main_udp_endpoint);
			}
		} else {
			const main_udp_outbound = generate_outbound(main_udp_node_cfg);
			if (main_udp_outbound) {
				main_udp_outbound.tag = 'main-udp-out';
				push(config.outbounds, main_udp_outbound);
			}
		}
	}

	for (let i in urltest_nodes) {
		const urltest_node = uci.get_all(uciconfig, i) || {};
		if (isEmpty(urltest_node))
			continue;

		if (urltest_node.type === 'wireguard') {
			const endpoint = generate_endpoint(urltest_node);
			if (endpoint) {
				endpoint.tag = get_section_outbound_tag(i);
				push(config.endpoints, endpoint);
			}
		} else {
			const outbound = generate_outbound(urltest_node);
			if (outbound) {
				outbound.tag = get_section_outbound_tag(i);
				push(config.outbounds, outbound);
			}
		}
	}
} else if (!isEmpty(default_outbound)) {
	let urltest_nodes = [],
	    routing_nodes = [];

	uci.foreach(uciconfig, uciroutingnode, (cfg) => {
		if (cfg.enabled !== '1')
			return;

		if (cfg.node === 'urltest') {
			const legacy_nodes = (isEmpty(cfg.subscription_groups) && isEmpty(cfg.subscription_nodes) && isEmpty(cfg.selected_nodes)) ? cfg.urltest_nodes : null;
			const urltest_list = collect_group_nodes(cfg.subscription_groups, cfg.subscription_nodes, cfg.selected_nodes, legacy_nodes);
			push(config.outbounds, {
				type: 'urltest',
				tag: get_section_outbound_tag(cfg['.name']),
				outbounds: map(urltest_list, (k) => get_section_outbound_tag(k)),
				url: cfg.urltest_url,
				interval: strToTime(cfg.urltest_interval),
				tolerance: strToInt(cfg.urltest_tolerance),
				idle_timeout: strToTime(cfg.urltest_idle_timeout),
				interrupt_exist_connections: strToBool(cfg.urltest_interrupt_exist_connections)
			});
			urltest_nodes = [...urltest_nodes, ...filter(urltest_list, (l) => !~index(urltest_nodes, l))];
		} else if (cfg.node === 'selector') {
			const selector_node_list = collect_group_nodes(cfg.subscription_groups, cfg.subscription_nodes, cfg.selected_nodes, null);
			const selector_policy_list = collect_policy_nodes(cfg.policy_nodes, cfg['.name']);
			const selector_list = [...selector_node_list, ...filter(selector_policy_list, (l) => !~index(selector_node_list, l))];
			const selector_default = (!isEmpty(cfg.selector_default) && ~index(selector_list, cfg.selector_default)) ? cfg.selector_default : null;
			push(config.outbounds, {
				type: 'selector',
				tag: get_section_outbound_tag(cfg['.name']),
				outbounds: map(selector_list, (k) => get_section_outbound_tag(k)),
				default: selector_default ? get_section_outbound_tag(selector_default) : null,
				interrupt_exist_connections: strToBool(cfg.selector_interrupt_exist_connections)
			});
			urltest_nodes = [...urltest_nodes, ...filter(selector_node_list, (l) => !~index(urltest_nodes, l))];
		} else {
			const outbound = uci.get_all(uciconfig, cfg.node) || {};
			if (isEmpty(outbound))
				return;

			if (outbound.type === 'wireguard') {
				const endpoint = generate_endpoint(outbound);
				if (!endpoint)
					return;

				endpoint.bind_interface = cfg.bind_interface;
				endpoint.detour = get_outbound(cfg.outbound);
				if (cfg.domain_resolver)
					endpoint.domain_resolver = {
						server: get_resolver(cfg.domain_resolver),
						strategy: cfg.domain_strategy
					};
				push(config.endpoints, endpoint);
			} else {
				const routed_outbound = generate_outbound(outbound);
				if (!routed_outbound)
					return;

				routed_outbound.bind_interface = cfg.bind_interface;
				routed_outbound.detour = get_outbound(cfg.outbound);
				if (cfg.domain_resolver)
					routed_outbound.domain_resolver = {
						server: get_resolver(cfg.domain_resolver),
						strategy: cfg.domain_strategy
					};
				push(config.outbounds, routed_outbound);
			}
			push(routing_nodes, cfg.node);
		}
	});

	for (let i in filter(urltest_nodes, (l) => !~index(routing_nodes, l))) {
		const urltest_node = uci.get_all(uciconfig, i) || {};
		if (isEmpty(urltest_node))
			continue;

		if (urltest_node.type === 'wireguard') {
			const endpoint = generate_endpoint(urltest_node);
			if (endpoint)
				push(config.endpoints, endpoint);
		} else {
			const outbound = generate_outbound(urltest_node);
			if (outbound)
				push(config.outbounds, outbound);
		}
	}
}

if (isEmpty(config.endpoints))
	config.endpoints = null;
/* Outbound end */

/* Routing rules start */
/* Default settings */
config.route = {
	rules: [
		{
			inbound: 'dns-in',
			action: 'hijack-dns'
		},
		{
			action: 'sniff'
		}
	],
	rule_set: [],
	auto_detect_interface: isEmpty(default_interface) ? true : null,
	default_interface: default_interface
};

/* Routing rules */
if (!isEmpty(main_node)) {
	/* Avoid DNS loop */
	config.route.default_domain_resolver = {
		action: 'route',
		server: (routing_mode === 'bypass_mainland_china') ? 'china-dns' : 'default-dns',
		strategy: (ipv6_support !== '1') ? 'prefer_ipv4' : null
	};

	/* Direct list */
	if (length(direct_domain_list))
		push(config.route.rules, {
			rule_set: 'direct-domain',
			action: 'route',
			outbound: 'direct-out'
		});

	/* Main UDP out */
	if (dedicated_udp_node)
		push(config.route.rules, {
			network: 'udp',
			action: 'route',
			outbound: 'main-udp-out'
		});

	config.route.final = 'main-out';

	/* Rule set */
	/* Direct list */
	if (length(direct_domain_list))
		push(config.route.rule_set, {
			type: 'inline',
			tag: 'direct-domain',
			rules: [
				{
					domain_keyword: direct_domain_list,
				}
			]
		});

	/* Proxy list */
	if (length(proxy_domain_list))
		push(config.route.rule_set, {
			type: 'inline',
			tag: 'proxy-domain',
			rules: [
				{
					domain_keyword: proxy_domain_list,
				}
			]
		});

	if (routing_mode === 'bypass_mainland_china') {
		push(config.route.rule_set, {
			type: 'remote',
			tag: 'geoip-cn',
			format: 'binary',
			url: 'https://fastly.jsdelivr.net/gh/1715173329/IPCIDR-CHINA@rule-set/cn.srs',
			path: ruleset_default_path('geoip-cn', 'binary'),
			download_detour: 'main-out'
		});
		push(config.route.rule_set, {
			type: 'remote',
			tag: 'geosite-cn',
			format: 'binary',
			url: 'https://fastly.jsdelivr.net/gh/1715173329/sing-geosite@rule-set-unstable/geosite-geolocation-cn.srs',
			path: ruleset_default_path('geosite-cn', 'binary'),
			download_detour: 'main-out'
		});
		push(config.route.rule_set, {
			type: 'remote',
			tag: 'geosite-noncn',
			format: 'binary',
			url: 'https://fastly.jsdelivr.net/gh/1715173329/sing-geosite@rule-set-unstable/geosite-geolocation-!cn.srs',
			path: ruleset_default_path('geosite-noncn', 'binary'),
			download_detour: 'main-out'
		});
	}

	if (isEmpty(config.route.rule_set))
		config.route.rule_set = null;
} else if (!isEmpty(default_outbound)) {
	config.route.default_domain_resolver = {
		action: 'resolve',
		server: get_resolver(default_outbound_dns)
	};

	if (domain_strategy)
		push(config.route.rules, {
			action: 'resolve',
			strategy: domain_strategy
		});

	uci.foreach(uciconfig, uciroutingrule, (cfg) => {
		if (cfg.enabled !== '1')
			return null;

		push(config.route.rules, {
			ip_version: strToInt(cfg.ip_version),
			protocol: cfg.protocol,
			network: cfg.network,
			domain: cfg.domain,
			domain_suffix: cfg.domain_suffix,
			domain_keyword: cfg.domain_keyword,
			domain_regex: cfg.domain_regex,
			source_ip_cidr: cfg.source_ip_cidr,
			source_ip_is_private: strToBool(cfg.source_ip_is_private),
			ip_cidr: cfg.ip_cidr,
			ip_is_private: strToBool(cfg.ip_is_private),
			source_port: parse_port(cfg.source_port),
			source_port_range: cfg.source_port_range,
			port: parse_port(cfg.port),
			port_range: cfg.port_range,
			process_name: cfg.process_name,
			process_path: cfg.process_path,
			process_path_regex: cfg.process_path_regex,
			user: cfg.user,
			rule_set: get_ruleset(cfg.rule_set),
			rule_set_ip_cidr_match_source: strToBool(cfg.rule_set_ip_cidr_match_source),
			rule_set_ip_cidr_accept_empty: strToBool(cfg.rule_set_ip_cidr_accept_empty),
			invert: strToBool(cfg.invert),
			action: cfg.action,
			outbound: (cfg.action === 'route') ? get_outbound(cfg.outbound) : null,
			server: (cfg.action === 'resolve') ? get_resolver(cfg.resolve_server) : null,
			strategy: (cfg.action === 'resolve') ? cfg.resolve_strategy : null,
			disable_cache: (cfg.action === 'resolve') ? strToBool(cfg.resolve_disable_cache) : null,
			rewrite_ttl: (cfg.action === 'resolve') ? strToInt(cfg.resolve_rewrite_ttl) : null,
			client_subnet: (cfg.action === 'resolve') ? cfg.resolve_client_subnet : null,
			override_address: (cfg.action in ['route', 'route-options']) ? cfg.override_address : null,
			override_port: (cfg.action in ['route', 'route-options']) ? strToInt(cfg.override_port) : null,
			udp_disable_domain_unmapping: (cfg.action in ['route', 'route-options']) ? strToBool(cfg.udp_disable_domain_unmapping) : null,
			udp_connect: (cfg.action in ['route', 'route-options']) ? strToBool(cfg.udp_connect) : null,
			udp_timeout: (cfg.action in ['route', 'route-options']) ? strToTime(cfg.udp_timeout) : null,
			tls_fragment: (cfg.action in ['route', 'route-options']) ? strToBool(cfg.tls_fragment) : null,
			tls_fragment_fallback_delay: (cfg.action in ['route', 'route-options']) ? strToTime(cfg.tls_fragment_fallback_delay) : null,
			tls_record_fragment: (cfg.action in ['route', 'route-options']) ? strToBool(cfg.tls_record_fragment) : null,
			method: (cfg.action === 'reject') ? cfg.reject_method : null,
			no_drop: (cfg.action === 'reject') ? strToBool(cfg.reject_no_drop) : null
		});
	});

	config.route.final = get_outbound(default_outbound);

	/* Rule set */
	uci.foreach(uciconfig, uciruleset, (cfg) => {
		if (cfg.enabled !== '1')
			return null;

		const tag = !isEmpty(cfg.tag) ? cfg.tag : ('cfg-' + cfg['.name'] + '-rule');

		push(config.route.rule_set, {
			type: cfg.type,
			tag: tag,
			format: cfg.format,
			url: cfg.url,
			path: (cfg.type === 'remote') ? ruleset_remote_path(cfg.remote_path || cfg.path, tag, cfg.format) : cfg.path,
			download_detour: get_outbound(cfg.outbound),
			update_interval: (cfg.type === 'remote') ? '87600h' : null
		});
	});
}
/* Routing rules end */

/* Experimental start */
if (routing_mode in ['bypass_mainland_china', 'custom']) {
	config.experimental = {
		clash_api,
		cache_file: {
			enabled: cache_file_enabled !== '0',
			path: cache_file_path || (HP_DIR + '/cache.db'),
			store_rdrc: strToBool(cache_store_rdrc),
			rdrc_timeout: strToTime(cache_rdrc_timeout),
		}
	};
}
/* Experimental end */

system('mkdir -p ' + RUN_DIR);
system('mkdir -p ' + RULESET_DIR);
writefile(RUN_DIR + '/sing-box-c.json', sprintf('%.J\n', removeBlankAttrs(config)));
