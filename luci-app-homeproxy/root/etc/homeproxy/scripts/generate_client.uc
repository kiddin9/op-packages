#!/usr/bin/ucode
/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * Copyright (C) 2023-2025 ImmortalWrt.org
 */

'use strict';

import { readfile, writefile } from 'fs';
import { isnan } from 'math';
import { connect } from 'ubus';
import { cursor } from 'uci';

import {
	isEmpty, parseURL, strToBool, strToInt, strToTime,
	removeBlankAttrs, validation, buildTLSObject, buildTransportObject,
	HP_DIR, RUN_DIR
} from 'homeproxy';

const ubus = connect();

/* const features = ubus.call('luci.homeproxy', 'singbox_get_features') || {}; */

/* UCI config start */
const uci = cursor();

const uciconfig = 'homeproxy';
uci.load(uciconfig);

const uciinfra = 'infra',
      ucimain = 'config',
      ucicontrol = 'control';

const ucidnssetting = 'dns',
      ucidnsserver = 'dns_server',
      ucidnsrule = 'dns_rule';

const uciroutingsetting = 'routing',
      uciroutingnode = 'routing_node',
      uciroutingrule = 'routing_rule';

const ucinode = 'node';
const uciruleset = 'ruleset';

const routing_mode = uci.get(uciconfig, ucimain, 'routing_mode') || 'bypass_mainland_china';

let wan_dns = ubus.call('network.interface', 'status', {'interface': 'wan'})?.['dns-server']?.[0];
if (!wan_dns)
	wan_dns = (routing_mode in ['proxy_mainland_china', 'global']) ? '8.8.8.8' : '223.5.5.5';

const dns_port = uci.get(uciconfig, uciinfra, 'dns_port') || '5333';

const ntp_server = uci.get(uciconfig, uciinfra, 'ntp_server') || 'time.apple.com';

const ipv6_support = uci.get(uciconfig, ucimain, 'ipv6_support') || '0';

let main_node, main_udp_node, dedicated_udp_node, default_outbound, default_outbound_dns,
    domain_strategy, dns_server, china_dns_server, dns_default_strategy,
    dns_default_server, dns_disable_cache, dns_disable_cache_expire,
    dns_client_subnet, direct_domain_list, proxy_domain_list;

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
			china_dns_server = '223.5.5.5';
	}
	dns_default_strategy = (ipv6_support !== '1') ? 'ipv4_only' : null;

	const direct_list_raw = readfile(HP_DIR + '/resources/direct_list.txt');
	direct_domain_list = direct_list_raw ? split(trim(direct_list_raw), /[\r\n]/) : [];

	const proxy_list_raw = readfile(HP_DIR + '/resources/proxy_list.txt');
	proxy_domain_list = proxy_list_raw ? split(trim(proxy_list_raw), /[\r\n]/) : [];

} else {
	/* DNS settings */
	dns_default_strategy = uci.get(uciconfig, ucidnssetting, 'default_strategy');
	dns_default_server = uci.get(uciconfig, ucidnssetting, 'default_server');
	dns_disable_cache = uci.get(uciconfig, ucidnssetting, 'disable_cache');
	dns_disable_cache_expire = uci.get(uciconfig, ucidnssetting, 'disable_cache_expire');
	dns_client_subnet = uci.get(uciconfig, ucidnssetting, 'client_subnet');

	/* Routing settings */
	default_outbound = uci.get(uciconfig, uciroutingsetting, 'default_outbound') || 'nil';
	default_outbound_dns = uci.get(uciconfig, uciroutingsetting, 'default_outbound_dns') || 'default-dns';
	domain_strategy = uci.get(uciconfig, uciroutingsetting, 'domain_strategy');
}

const dns_optimistic_cache = uci.get(uciconfig, ucidnssetting, 'optimistic_cache') || '0',
      dns_optimistic_timeout = uci.get(uciconfig, ucidnssetting, 'optimistic_timeout'),
      dns_query_timeout = uci.get(uciconfig, ucidnssetting, 'dns_timeout'),
      dns_store_dns = uci.get(uciconfig, ucidnssetting, 'cache_file_store_dns') || '0';

const proxy_mode = uci.get(uciconfig, ucimain, 'proxy_mode') || 'redirect_tproxy',
      default_interface = uci.get(uciconfig, ucicontrol, 'bind_interface');

const mixed_port = uci.get(uciconfig, uciinfra, 'mixed_port') || '5330';

let self_mark, redirect_port, tproxy_port, tun_name,
    tun_addr4, tun_addr6, tun_mtu, tcpip_stack,
    endpoint_independent_nat, udp_timeout;

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
	if (routing_mode === 'custom') {
		tcpip_stack = uci.get(uciconfig, uciroutingsetting, 'tcpip_stack') || 'system';
		endpoint_independent_nat = uci.get(uciconfig, uciroutingsetting, 'endpoint_independent_nat');
	}
}

const log_level = uci.get(uciconfig, ucimain, 'log_level') || 'warn';
/* UCI config end */

const tun_dns_mode_raw = uci.get(uciconfig, ucimain, 'tun_dns_mode'),
      tun_dns_address = uci.get(uciconfig, ucimain, 'tun_dns_address'),
      udp_mapping_raw = uci.get(uciconfig, ucimain, 'udp_mapping'),
      udp_filtering_raw = uci.get(uciconfig, ucimain, 'udp_filtering'),
      udp_nat_max = strToInt(uci.get(uciconfig, ucimain, 'udp_nat_max'));

const tun_dns_mode = (tun_dns_mode_raw === 'default') ? '' : tun_dns_mode_raw,
      udp_mapping = (udp_mapping_raw === 'default') ? '' : udp_mapping_raw,
      udp_filtering = (udp_filtering_raw === 'default') ? '' : udp_filtering_raw;

/* Config helper start */
/*
 * Direct-node destination override, keyed by node section name. It must be
 * declared before the helpers that touch it: ucode resolves let/const
 * lexically and does not hoist them, so a function defined earlier would
 * resolve the name as an undeclared global and throw under strict mode.
 */
const direct_overrides = {};

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

function parse_dnsquery(strquery) {
	if (type(strquery) !== 'array' || isEmpty(strquery))
		return null;

	let querys = [];
	for (let i in strquery)
		isnan(int(i)) ? push(querys, i) : push(querys, int(i));

	return querys;

}

function generate_endpoint(node) {
	if (type(node) !== 'object' || isEmpty(node))
		return null;

	const endpoint = {
		type: node.type,
		tag: 'cfg-' + node['.name'] + '-out',
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
		udp_fragment: strToBool(node.udp_fragment),
		udp_mapping: !isEmpty(udp_mapping) ? udp_mapping : null,
		udp_filtering: !isEmpty(udp_filtering) ? udp_filtering : null,
		udp_nat_max: udp_nat_max
	};

	return endpoint;
}

function generate_outbound(node) {
	if (type(node) !== 'object' || isEmpty(node))
		return null;

	const outbound = {
		type: node.type,
		tag: 'cfg-' + node['.name'] + '-out',
		routing_mark: strToInt(self_mark),

		server: node.address,
		server_port: strToInt(node.port),
		/* Hysteria(2) */
		server_ports: node.hysteria_hopping_port,

		username: (node.type !== 'ssh') ? node.username : null,
		user: (node.type === 'ssh') ? node.username : null,
		/* Snell authenticates with psk instead of password */
		password: (node.type !== 'snell') ? node.password : null,
		psk: (node.type === 'snell') ? node.password : null,
		userkey: (node.type === 'snell') ? node.snell_userkey : null,
		reuse: (node.type === 'snell') ? strToBool(node.snell_reuse) : null,
		/* Snell v4: HTTP obfuscation; v6: traffic shaping mode */
		obfs_mode: (node.type === 'snell') ? (node.snell_obfs_mode || null) : null,
		obfs_host: (node.type === 'snell') ? (node.snell_obfs_host || null) : null,
		mode: (node.type === 'snell') ? (node.snell_mode || null) : null,

		/* Direct */
		proxy_protocol: strToInt(node.proxy_protocol),
		/* AnyTLS */
		idle_session_check_interval: strToTime(node.anytls_idle_session_check_interval),
		idle_session_timeout: strToTime(node.anytls_idle_session_timeout),
		min_idle_session: strToInt(node.anytls_min_idle_session),
		/* Hysteria (2) */
		hop_interval: strToTime(node.hysteria_hop_interval),
		hop_interval_max: strToTime(node.hysteria_hop_interval_max),
		up_mbps: strToInt(node.hysteria_up_mbps),
		down_mbps: strToInt(node.hysteria_down_mbps),
		obfs: node.hysteria_obfs_type ? {
			type: node.hysteria_obfs_type,
			password: node.hysteria_obfs_password,
			min_packet_size: strToInt(node.hysteria_obfs_min_packet_size),
			max_packet_size: strToInt(node.hysteria_obfs_max_packet_size)
		} : node.hysteria_obfs_password,
		auth: (node.hysteria_auth_type === 'base64') ? node.hysteria_auth_payload : null,
		auth_str: (node.hysteria_auth_type === 'string') ? node.hysteria_auth_payload : null,
		/* sing-box 1.14: Hysteria2 QUIC params (Hysteria v1 recv-window tuning removed upstream) */
		bbr_profile: (node.type === 'hysteria2') ? (node.hysteria_bbr_profile || null) : null,
		disable_chrome_parrot: (node.type === 'hysteria2' && node.hysteria_disable_chrome_parrot === '1') ? true : null,
		/* Shadowsocks */
		method: node.shadowsocks_encrypt_method,
		plugin: node.shadowsocks_plugin,
		plugin_opts: node.shadowsocks_plugin_opts,
		/* ShadowTLS / Socks / Snell */
		version: (node.type === 'shadowtls') ? strToInt(node.shadowtls_version) : ((node.type === 'socks') ? node.socks_version : ((node.type === 'snell') ? (strToInt(node.snell_version) || 4) : null)),
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
		tls: buildTLSObject(node, false),
		transport: buildTransportObject(node, false),
		udp_over_tcp: (node.udp_over_tcp === '1') ? {
			enabled: true,
			version: strToInt(node.udp_over_tcp_version)
		} : null,
		tcp_fast_open: strToBool(node.tcp_fast_open),
		tcp_multi_path: strToBool(node.tcp_multi_path),
		udp_fragment: strToBool(node.udp_fragment)
	};

	/* Direct-node destination override: sing-box removed these options from
	   the direct outbound since 1.13; emit them via the route action instead */
	if (node.type === 'direct' && (!isEmpty(node.override_address) || !isEmpty(node.override_port)))
		direct_overrides[node['.name']] = {
			override_address: node.override_address,
			override_port: strToInt(node.override_port)
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
			else if (node === 'urltest')
				return 'cfg-' + cfg + '-out';
			else
				return 'cfg-' + node + '-out';
		}
	}
}

function get_direct_override(outbound_selector) {
	if (type(outbound_selector) === 'array' || isEmpty(outbound_selector))
		return null;

	switch (outbound_selector) {
	case 'direct-out':
	case 'block-out':
		return null;
	default:
		const node = uci.get(uciconfig, outbound_selector, 'node');
		return (!isEmpty(node) && node !== 'urltest') ? (direct_overrides[node] || null) : null;
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
	for (let i in cfg)
		push(rules, isEmpty(i) ? null : 'cfg-' + i + '-rule');
	return rules;
}

function isDirectOutboundTag(tag) {
	if (isEmpty(tag) || tag === 'block-out')
		return false;
	if (tag === 'direct-out')
		return true;

	const node_name = uci.get(uciconfig, tag, 'node') || tag;
	const node = uci.get_all(uciconfig, node_name);
	return !isEmpty(node) && node.type === 'direct';
}
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
		enabled: true,
		server: ntp_server,
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
	client_subnet: dns_client_subnet,
	optimistic: (dns_optimistic_cache === '1') ? {
		enabled: true,
		timeout: !isEmpty(dns_optimistic_timeout) ? dns_optimistic_timeout : '3d'
	} : null,
	timeout: !isEmpty(dns_query_timeout) ? strToTime(dns_query_timeout) : null
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

	/* Reject SVCB/HTTPS queries to avoid proxy DNS timeout on null domains */
	push(config.dns.rules, {
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

		/* Route NAPTR (qtype 35) queries for SIP/ENUM domains to the ISP
		   default-dns directly: china-dns (223.5.5.5) has intermittent
		   multi-second first responses for NAPTR, causing 'context deadline
		   exceeded' (e.g. sipgz12.hbq.r.10086.cn) */
		push(config.dns.rules, {
			query_type: [35],
			domain_suffix: ['r.10086.cn', '10086.cn', 'pub.3gppnetwork.org'],
			action: 'route',
			server: 'default-dns'
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
			server: 'china-dns'
		});

		/* sing-box 1.14: restore CN-IP fallback via evaluate/match_response (opt-in) */
		if (uci.get(uciconfig, ucimain, 'cn_ip_fallback') === '1') {
			push(config.dns.rules, {
				action: 'evaluate',
				server: 'main-dns',
				tag: 'cn-fallback'
			});
			push(config.dns.rules, {
				match_response: 'cn-fallback',
				rule_set: 'geoip-cn',
				action: 'route',
				server: 'china-dns'
			});
		}
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
			type: cfg.type,
			server: cfg.server,
			server_port: strToInt(cfg.server_port),
			path: cfg.path,
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
	/* sing-box >= 1.14: legacy address-filter rules are auto-wrapped with an
	   evaluate action; deprecated strategy/accept_empty fields are dropped. */
	const builtin_dns_rules = [];
	uci.foreach(uciconfig, ucidnsrule, (cfg) => {
		if (cfg.enabled !== '1')
			return;

		const rule = {
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
			source_port: parse_port(cfg.source_port),
			source_port_range: cfg.source_port_range,
			process_name: cfg.process_name,
			process_path: cfg.process_path,
			process_path_regex: cfg.process_path_regex,
			user: cfg.user,
			rule_set: get_ruleset(cfg.rule_set),
			rule_set_ip_cidr_match_source: strToBool(cfg.rule_set_ip_cidr_match_source),
			invert: strToBool(cfg.invert),
			race: strToBool(cfg.race),
			speculative: strToBool(cfg.speculative),
			action: cfg.action,
			server: get_resolver(cfg.server),
			disable_cache: strToBool(cfg.dns_disable_cache),
			disable_optimistic_cache: strToBool(cfg.disable_optimistic_cache),
			rewrite_ttl: strToInt(cfg.rewrite_ttl),
			timeout: strToTime(cfg.dns_timeout),
			client_subnet: cfg.client_subnet,
			remove_client_subnet: strToBool(cfg.remove_client_subnet),
			method: cfg.reject_method,
			no_drop: strToBool(cfg.reject_no_drop),
			rcode: cfg.predefined_rcode,
			answer: cfg.predefined_answer,
			ns: cfg.predefined_ns,
			extra: cfg.predefined_extra
		};

		if (cfg.action === 'evaluate')
			rule.tag = cfg.evaluate_tag || null;

		if (cfg.match_response && cfg.match_response !== '0')
			rule.match_response = (cfg.match_response === '1') ? true : cfg.match_response;

		rule.query_client_subnet = cfg.query_client_subnet;
		rule.query_dnssec = strToBool(cfg.query_dnssec);
		rule.response_rcode = cfg.response_rcode;
		rule.response_answer = cfg.response_answer;
		rule.response_ns = cfg.response_ns;
		rule.response_extra = cfg.response_extra;
		rule.source_mac_address = cfg.source_mac_address;
		rule.source_hostname = cfg.source_hostname;

		const legacy_filter = !isEmpty(cfg.ip_cidr) || strToBool(cfg.ip_is_private) === true;
		if (legacy_filter && !rule.match_response && cfg.action === 'route') {
			/* Wrap a legacy address-filter rule into the 1.14 evaluate/match_response
			   paradigm. Carry the original query-matching fields onto the evaluate
			   prefix rule so only queries that would have hit this rule get
			   pre-resolved; an unconditional evaluate would resolve every query. */
			const eval_tag = '_hp_eval_' + cfg['.name'];
			const eval_rule = {
				action: 'evaluate',
				server: get_resolver(cfg.server),
				tag: eval_tag
			};
			const eval_match_fields = [
				'inbound', 'ip_version', 'query_type', 'network', 'protocol', 'auth_user',
				'domain', 'domain_suffix', 'domain_keyword', 'domain_regex',
				'port', 'port_range', 'source_ip_cidr', 'source_ip_is_private',
				'source_port', 'source_port_range', 'process_name', 'process_path',
				'process_path_regex', 'user', 'rule_set', 'rule_set_ip_cidr_match_source',
				'invert', 'query_client_subnet', 'query_dnssec', 'source_mac_address',
				'source_hostname'
			];
			for (let f in eval_match_fields)
				eval_rule[f] = rule[f];
			push(builtin_dns_rules, eval_rule);
			rule.match_response = eval_tag;
		}

		/* ip_cidr / ip_is_private are only valid with match_response in 1.14 */
		if (rule.match_response) {
			rule.ip_cidr = cfg.ip_cidr;
			rule.ip_is_private = strToBool(cfg.ip_is_private);
		}

		push(builtin_dns_rules, rule);
	});
	config.dns.rules = builtin_dns_rules;

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
		udp_timeout: strToTime(udp_timeout),
		udp_mapping: !isEmpty(udp_mapping) ? udp_mapping : null,
		udp_filtering: !isEmpty(udp_filtering) ? udp_filtering : null,
		udp_nat_max: udp_nat_max,
	});
if (match(proxy_mode, /tun/))
	push(config.inbounds, {
		type: 'tun',
		tag: 'tun-in',

		interface_name: tun_name,
		address: (ipv6_support === '1') ? [tun_addr4, tun_addr6] : [tun_addr4],
		mtu: strToInt(tun_mtu),
		auto_route: false,
		endpoint_independent_nat: strToBool(endpoint_independent_nat),
		udp_timeout: strToTime(udp_timeout),
		dns_mode: !isEmpty(tun_dns_mode) ? tun_dns_mode : null,
		dns_address: !isEmpty(tun_dns_address) ? tun_dns_address : null,
		udp_mapping: !isEmpty(udp_mapping) ? udp_mapping : null,
		udp_filtering: !isEmpty(udp_filtering) ? udp_filtering : null,
		udp_nat_max: udp_nat_max,
		stack: tcpip_stack,
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
		const main_urltest_nodes = filter(uci.get(uciconfig, ucimain, 'main_urltest_nodes') || [], (k) => uci.get(uciconfig, k));
		const main_urltest_interval = uci.get(uciconfig, ucimain, 'main_urltest_interval');
		const main_urltest_tolerance = uci.get(uciconfig, ucimain, 'main_urltest_tolerance');

		push(config.outbounds, {
			type: 'urltest',
			tag: 'main-out',
			outbounds: map(main_urltest_nodes, (k) => `cfg-${k}-out`),
			interval: strToTime(main_urltest_interval),
			tolerance: strToInt(main_urltest_tolerance),
			idle_timeout: (strToInt(main_urltest_interval) > 1800) ? `${main_urltest_interval * 2}s` : null,
		});
		urltest_nodes = main_urltest_nodes;
	} else {
		const main_node_cfg = uci.get_all(uciconfig, main_node) || {};
		if (main_node_cfg.type === 'wireguard') {
			push(config.endpoints, generate_endpoint(main_node_cfg));
			config.endpoints[length(config.endpoints)-1].tag = 'main-out';
		} else {
			push(config.outbounds, generate_outbound(main_node_cfg));
			config.outbounds[length(config.outbounds)-1].tag = 'main-out';
		}
	}

	if (main_udp_node === 'urltest') {
		const main_udp_urltest_nodes = filter(uci.get(uciconfig, ucimain, 'main_udp_urltest_nodes') || [], (k) => uci.get(uciconfig, k));
		const main_udp_urltest_interval = uci.get(uciconfig, ucimain, 'main_udp_urltest_interval');
		const main_udp_urltest_tolerance = uci.get(uciconfig, ucimain, 'main_udp_urltest_tolerance');

		push(config.outbounds, {
			type: 'urltest',
			tag: 'main-udp-out',
			outbounds: map(main_udp_urltest_nodes, (k) => `cfg-${k}-out`),
			interval: strToTime(main_udp_urltest_interval),
			tolerance: strToInt(main_udp_urltest_tolerance),
			idle_timeout: (strToInt(main_udp_urltest_interval) > 1800) ? `${main_udp_urltest_interval * 2}s` : null,
		});
		urltest_nodes = [...urltest_nodes, ...filter(main_udp_urltest_nodes, (l) => !~index(urltest_nodes, l))];
	} else if (dedicated_udp_node) {
		const main_udp_node_cfg = uci.get_all(uciconfig, main_udp_node) || {};
		if (main_udp_node_cfg.type === 'wireguard') {
			push(config.endpoints, generate_endpoint(main_udp_node_cfg));
			config.endpoints[length(config.endpoints)-1].tag = 'main-udp-out';
		} else {
			push(config.outbounds, generate_outbound(main_udp_node_cfg));
			config.outbounds[length(config.outbounds)-1].tag = 'main-udp-out';
		}
	}

	for (let i in urltest_nodes) {
		const urltest_node = uci.get_all(uciconfig, i) || {};
		if (isEmpty(urltest_node))
			continue;
		if (urltest_node.type === 'wireguard') {
			push(config.endpoints, generate_endpoint(urltest_node));
			config.endpoints[length(config.endpoints)-1].tag = 'cfg-' + i + '-out';
		} else {
			push(config.outbounds, generate_outbound(urltest_node));
			config.outbounds[length(config.outbounds)-1].tag = 'cfg-' + i + '-out';
		}
	}
} else if (!isEmpty(default_outbound)) {
	let urltest_nodes = [],
	    routing_nodes = [];

	uci.foreach(uciconfig, uciroutingnode, (cfg) => {
		if (cfg.enabled !== '1')
			return;

		if (cfg.node === 'urltest') {
			const cfg_urltest_nodes = filter(cfg.urltest_nodes || [], (k) => uci.get(uciconfig, k));
			push(config.outbounds, {
				type: 'urltest',
				tag: 'cfg-' + cfg['.name'] + '-out',
				outbounds: map(cfg_urltest_nodes, (k) => `cfg-${k}-out`),
				url: cfg.urltest_url,
				interval: strToTime(cfg.urltest_interval),
				tolerance: strToInt(cfg.urltest_tolerance),
				idle_timeout: strToTime(cfg.urltest_idle_timeout),
				interrupt_exist_connections: strToBool(cfg.urltest_interrupt_exist_connections)
			});
			urltest_nodes = [...urltest_nodes, ...filter(cfg_urltest_nodes, (l) => !~index(urltest_nodes, l))];
		} else {
			const outbound = uci.get_all(uciconfig, cfg.node) || {};
			if (outbound.type === 'wireguard') {
				push(config.endpoints, generate_endpoint(outbound));
				config.endpoints[length(config.endpoints)-1].bind_interface = cfg.bind_interface;
				config.endpoints[length(config.endpoints)-1].detour = get_outbound(cfg.outbound);
				if (cfg.domain_resolver)
					config.endpoints[length(config.endpoints)-1].domain_resolver = {
						server: get_resolver(cfg.domain_resolver),
						strategy: cfg.domain_strategy
					};
			} else {
				push(config.outbounds, generate_outbound(outbound));
				config.outbounds[length(config.outbounds)-1].bind_interface = cfg.bind_interface;
				config.outbounds[length(config.outbounds)-1].detour = get_outbound(cfg.outbound);
				if (cfg.domain_resolver)
					config.outbounds[length(config.outbounds)-1].domain_resolver = {
						server: get_resolver(cfg.domain_resolver),
						strategy: cfg.domain_strategy
					};
			}
			push(routing_nodes, cfg.node);
		}
	});

	for (let i in filter(urltest_nodes, (l) => !~index(routing_nodes, l))) {
		const urltest_node = uci.get_all(uciconfig, i) || {};
		if (urltest_node.type === 'wireguard')
			push(config.endpoints, generate_endpoint(urltest_node));
		else
			push(config.outbounds, generate_outbound(urltest_node));
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
			action: 'sniff',
			timeout: '300ms'
		}
	],
	rule_set: [],
	auto_detect_interface: isEmpty(default_interface) ? true : null,
	default_interface: default_interface
};

/* Routing rules */
if (!isEmpty(main_node)) {
	/* Resolve outbound server domains through the WAN default resolver.
	   Do not use china-dns here: china-dns is for resolving mainland China
	   destinations, not the proxy node itself. Coupling node bootstrap to
	   china_dns_server can break dialing when that resolver is polluted or
	   unsuitable for the node domain. */
	config.route.default_domain_resolver = {
		server: 'default-dns',
		strategy: (ipv6_support !== '1') ? 'prefer_ipv4' : null
	};

	/* Direct list */
	if (length(direct_domain_list))
		push(config.route.rules, {
			rule_set: 'direct-domain',
			action: 'route',
			outbound: 'direct-out'
		});

	/* Bypass CN traffic: resolve the destination first, then route by IP.
	   sing-box does not match an IP-based rule set (geoip-cn) against a domain
	   destination unless it is resolved first, so add an explicit resolve
	   action; geoip-cn then sends China IPs to direct and everything else falls
	   through to main-out (proxy). This avoids relying on the geosite-* domain
	   lists, which can mis-classify foreign domains (e.g. Google's gvt2.com
	   beacons) as "cn" and send them direct to time out. Keep the direct-domain
	   fast-path above for known direct domains. */
	if (routing_mode === 'bypass_mainland_china') {
		push(config.route.rules, {
			action: 'resolve',
			strategy: (ipv6_support !== '1') ? 'prefer_ipv4' : null
		});
		push(config.route.rules, {
			rule_set: 'geoip-cn',
			action: 'route',
			outbound: 'direct-out'
		});
	}

	/* Main UDP out */
	if (dedicated_udp_node) {
		const udp_override = direct_overrides[main_udp_node] || null;
		push(config.route.rules, {
			network: 'udp',
			action: 'route',
			outbound: 'main-udp-out',
			override_address: udp_override ? udp_override.override_address : null,
			override_port: udp_override ? udp_override.override_port : null
		});
	}

	/* Direct-node destination override, emitted as route-options action
	   (direct outbound options removed since sing-box 1.13) */
	const main_override = direct_overrides[main_node] || null;
	if (main_override)
		push(config.route.rules, {
			action: 'route-options',
			override_address: main_override.override_address,
			override_port: main_override.override_port
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
		/*
		 * Fetched straight from the upstream SagerNet repositories and
		 * downloaded through the selected node. A direct fetch depends on
		 * the CDN staying reachable from mainland China, where DNS pollution
		 * makes it fail intermittently; the three files total ~250 KB per
		 * day, so proxying the download costs almost nothing.
		 */
		push(config.route.rule_set, {
			type: 'remote',
			tag: 'geoip-cn',
			format: 'binary',
			url: 'https://raw.githubusercontent.com/SagerNet/sing-geoip/rule-set/geoip-cn.srs',
			update_interval: '24h',
			download_detour: 'main-out'
		});
		push(config.route.rule_set, {
			type: 'remote',
			tag: 'geosite-cn',
			format: 'binary',
			url: 'https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-geolocation-cn.srs',
			update_interval: '24h',
			download_detour: 'main-out'
		});
		push(config.route.rule_set, {
			type: 'remote',
			tag: 'geosite-noncn',
			format: 'binary',
			url: 'https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-geolocation-!cn.srs',
			update_interval: '24h',
			download_detour: 'main-out'
		});
	}

	if (isEmpty(config.route.rule_set))
		config.route.rule_set = null;
} else if (!isEmpty(default_outbound)) {
	config.route.default_domain_resolver = {
		server: get_resolver(default_outbound_dns)
	};

	if (uci.get(uciconfig, uciroutingsetting, 'find_neighbor') === '1')
		config.route.find_neighbor = true;

	if (domain_strategy)
		push(config.route.rules, {
			action: 'resolve',
			strategy: domain_strategy
		});

	uci.foreach(uciconfig, uciroutingrule, (cfg) => {
		if (cfg.enabled !== '1')
			return null;

		const rule_outbound = get_outbound(cfg.outbound);
		const rule_direct_override = get_direct_override(cfg.outbound);
		let rule_override_address = cfg.override_address,
		    rule_override_port = strToInt(cfg.override_port);
		if (isEmpty(rule_override_address) && isEmpty(rule_override_port) && rule_direct_override) {
			rule_override_address = rule_direct_override.override_address;
			rule_override_port = rule_direct_override.override_port;
		}

		/* sing-box routing rule: emit match fields plus action-specific fields.
		   client is the sniffed client type (only set with protocol quic/ssh);
		   resolve adds server/strategy/disable_cache/rewrite_ttl/client_subnet;
		   reject adds method/no_drop. Emitted conditionally so a given action
		   never carries fields sing-box rejects for it. */
		const rule = {
			ip_version: strToInt(cfg.ip_version),
			protocol: cfg.protocol,
			network: cfg.network,
			client: cfg.client,
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
			invert: strToBool(cfg.invert),
			action: cfg.action,
			outbound: rule_outbound,
			override_address: rule_override_address,
			override_port: rule_override_port,
			udp_disable_domain_unmapping: strToBool(cfg.udp_disable_domain_unmapping),
			udp_connect: strToBool(cfg.udp_connect),
			udp_timeout: strToTime(cfg.udp_timeout),
			tls_fragment: strToBool(cfg.tls_fragment),
			tls_fragment_fallback_delay: strToTime(cfg.tls_fragment_fallback_delay),
			tls_record_fragment: strToBool(cfg.tls_record_fragment),
			tls_spoof: cfg.tls_spoof || null,
			tls_spoof_method: cfg.tls_spoof_method || null,
			source_mac_address: cfg.source_mac_address,
			source_hostname: cfg.source_hostname
		};
		if (cfg.action === 'resolve') {
			rule.server = get_resolver(cfg.resolve_server);
			rule.strategy = cfg.resolve_strategy;
			rule.disable_cache = strToBool(cfg.resolve_disable_cache);
			rule.disable_optimistic_cache = strToBool(cfg.resolve_disable_optimistic_cache);
			rule.rewrite_ttl = strToInt(cfg.resolve_rewrite_ttl);
			rule.timeout = strToTime(cfg.resolve_timeout);
			rule.client_subnet = cfg.resolve_client_subnet;
		}
		if (cfg.action === 'reject') {
			rule.method = cfg.reject_method;
			rule.no_drop = strToBool(cfg.reject_no_drop);
		}
		push(config.route.rules, rule);
	});

	/* Direct-node destination override, emitted as route-options action
	   (direct outbound options removed since sing-box 1.13) */
	const final_override = get_direct_override(default_outbound);
	if (final_override)
		push(config.route.rules, {
			action: 'route-options',
			override_address: final_override.override_address,
			override_port: final_override.override_port
		});

	config.route.final = get_outbound(default_outbound);

	/* Rule set */
	uci.foreach(uciconfig, uciruleset, (cfg) => {
		if (cfg.enabled !== '1')
			return null;

		const extra_tags = cfg.extra_tags || [];
		let rs_tag = 'cfg-' + cfg['.name'] + '-rule';
		if (length(extra_tags) && cfg.type !== 'inline') {
			rs_tag = [rs_tag];
			for (let t in extra_tags)
				push(rs_tag, 'cfg-' + t + '-rule');
			/* sing-box 1.14: multi-tag requires a {tag} placeholder in the fetch source
			   (remote: url and initial_path, local: path) */
			const fetch_ref = (cfg.type === 'remote') ? (cfg.url || '') : (cfg.path || '');
			if (!match(fetch_ref, /\{tag\}/))
				warn(sprintf("homeproxy: rule-set '%s' uses extra tags but its %s source lacks a {tag} placeholder.", cfg['.name'], cfg.type));
			if (cfg.type === 'remote' && !isEmpty(cfg.initial_path) && !match(cfg.initial_path, /\{tag\}/))
				warn(sprintf("homeproxy: rule-set '%s' uses extra tags but its initial_path lacks a {tag} placeholder.", cfg['.name']));
		}

		const ruleset = {
			type: cfg.type,
			tag: rs_tag,
			format: cfg.format,
			path: cfg.path,
			url: cfg.url,
			update_interval: cfg.update_interval
		};
		/* download_detour is a pre-1.14 option that only makes sense for
		   remote rule-sets; emitting it for local/inline ones makes sing-box
		   1.14 reject the whole config. It is translated into http_clients
		   right below. */
		if (cfg.type === 'remote')
			ruleset.download_detour = get_outbound(cfg.outbound) || get_outbound(default_outbound);
		if (cfg.type === 'remote' && !isEmpty(cfg.initial_path))
			ruleset.initial_path = cfg.initial_path;
		push(config.route.rule_set, ruleset);
	});
}

/* sing-box 1.14: remote rule-sets download via top-level http_clients;
   replaces the legacy download_detour field everywhere (preset + custom). */
const http_clients = [];
const http_seen = {};
for (let rs in (config.route.rule_set || [])) {
	/* Strip the legacy field from every entry first, including the
	   local/inline ones: sing-box 1.14 rejects it everywhere except on
	   remote rule-sets, where it is replaced by http_client below. */
	let detour = rs.download_detour;
	delete rs.download_detour;

	if (rs.type !== 'remote')
		continue;

	if (isEmpty(detour))
		detour = (routing_mode === 'custom') ? (get_outbound(default_outbound) || 'direct-out') : 'direct-out';

	const tag = 'hp-' + detour;
	rs.http_client = tag;
	if (!http_seen[detour]) {
		http_seen[detour] = true;
		/* sing-box 1.14 rejects detouring to an empty direct outbound
		   (pure TUN mode has no self_mark on direct-out). Omitting detour
		   uses the same system direct dialer, so behavior is unchanged. */
		const client = { tag: tag };
		if (!(isEmpty(self_mark) && isDirectOutboundTag(detour)))
			client.detour = detour;
		push(http_clients, client);
	}
}
if (length(http_clients))
	config.http_clients = http_clients;
/* Routing rules end */

/* Experimental start */
if (routing_mode in ['bypass_mainland_china', 'custom']) {
	config.experimental = {
		cache_file: {
			enabled: true,
			path: '/etc/homeproxy/cache.db',
			store_dns: (dns_store_dns === '1') ? true : null
		}
	};
}
/* Experimental end */

config['$schema'] = 'https://sing-box.sagernet.org/schema.json';

system('mkdir -p ' + RUN_DIR);
const client_tmp = RUN_DIR + '/sing-box-c.json.tmp';
writefile(client_tmp, sprintf('%.J\n', removeBlankAttrs(config)));
if (system('/usr/bin/sing-box check --config ' + client_tmp) !== 0) {
	system('rm -f ' + client_tmp);
	exit(1);
}
system('mv -f ' + client_tmp + ' ' + RUN_DIR + '/sing-box-c.json');
