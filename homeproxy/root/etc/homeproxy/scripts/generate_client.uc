#!/usr/bin/ucode
/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * Copyright (C) 2023-2025 ImmortalWrt.org
 */

'use strict';

import { open, readfile, writefile } from 'fs';
import { isnan } from 'math';
import { connect } from 'ubus';
import { cursor } from 'uci';

import {
	isEmpty, parseURL, strToBool, strToInt, strToTime,
	removeBlankAttrs, validation, getTime, HP_DIR, RUN_DIR
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
const ucisimple = 'simple',
      ucisimplerule = 'simple_rule';

const routing_mode = uci.get(uciconfig, ucimain, 'routing_mode') || 'bypass_mainland_china';

let wan_dns = ubus.call('network.interface', 'status', {'interface': 'wan'})?.['dns-server']?.[0];
if (!wan_dns)
	wan_dns = (routing_mode in ['proxy_mainland_china', 'global']) ? '8.8.8.8' : '223.5.5.5';

const dns_port = uci.get(uciconfig, uciinfra, 'dns_port') || '5333';

const ntp_server = uci.get(uciconfig, uciinfra, 'ntp_server') || 'time.apple.com';

const ipv6_support = uci.get(uciconfig, ucimain, 'ipv6_support') || '0';

let main_node, main_udp_node, dedicated_udp_node, default_outbound, default_outbound_dns,
    domain_strategy, dns_server, china_dns_server, dns_default_strategy, dns_default_server,
    dns_disable_cache, dns_disable_cache_expire, dns_client_subnet,
    cache_file_store_rdrc, cache_file_rdrc_timeout, direct_domain_list, proxy_domain_list;

if (routing_mode === 'simple') {
	/* Simple routing provides its own DNS, outbounds and route rules. */
	dns_default_strategy = (ipv6_support !== '1') ? 'ipv4_only' : null;
} else if (routing_mode !== 'custom') {
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
} else {
	/* DNS settings */
	dns_default_strategy = uci.get(uciconfig, ucidnssetting, 'default_strategy');
	dns_default_server = uci.get(uciconfig, ucidnssetting, 'default_server');
	dns_disable_cache = uci.get(uciconfig, ucidnssetting, 'disable_cache');
	dns_disable_cache_expire = uci.get(uciconfig, ucidnssetting, 'disable_cache_expire');
	dns_client_subnet = uci.get(uciconfig, ucidnssetting, 'client_subnet');
	cache_file_store_rdrc = uci.get(uciconfig, ucidnssetting, 'cache_file_store_rdrc'),
	cache_file_rdrc_timeout = uci.get(uciconfig, ucidnssetting, 'cache_file_rdrc_timeout');

	/* Routing settings */
	default_outbound = uci.get(uciconfig, uciroutingsetting, 'default_outbound') || 'nil';
	default_outbound_dns = uci.get(uciconfig, uciroutingsetting, 'default_outbound_dns') || 'default-dns';
	domain_strategy = uci.get(uciconfig, uciroutingsetting, 'domain_strategy');
}

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
	if (main_udp_node !== 'nil' || routing_mode in ['custom', 'simple'])
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
		udp_fragment: strToBool(node.udp_fragment)
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
		password: node.password,

		/* Direct */
		override_address: node.override_address,
		override_port: strToInt(node.override_port),
		proxy_protocol: strToInt(node.proxy_protocol),
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
			utls: !isEmpty(node.tls_utls) ? {
				enabled: true,
				fingerprint: node.tls_utls
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
			else if (node === 'urltest')
				return 'cfg-' + cfg + '-out';
			else
				return 'cfg-' + node + '-out';
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
	for (let i in cfg)
		push(rules, isEmpty(i) ? null : 'cfg-' + i + '-rule');
	return rules;
}
/* Config helper end */

/* Simple routing translation start */
function simple_array(value) {
	if (isEmpty(value))
		return [];
	return (type(value) === 'array') ? value : [ value ];
}

function simple_node_tag(name) {
	return 'simple-n-' + name + '-out';
}

/* "geosite/netflix" -> <base>/geosite/netflix.srs, bare names default to geosite,
 * and full URLs are used verbatim. */
function simple_ruleset_url(base, value) {
	if (match(value, /^https?:\/\//))
		return value;

	let category = 'geosite', name = value;
	const parts = split(value, '/');
	if (length(parts) === 2 && (parts[0] in ['geosite', 'geoip'])) {
		category = parts[0];
		name = parts[1];
	}

	return base + '/' + category + '/' + replace(name, /@/g, '%40') + '.srs';
}

function simple_log(message) {
	const logfile = open(RUN_DIR + '/homeproxy.log', 'a');
	if (!logfile)
		return;

	logfile.write(`${getTime()} [CLIENT] ${message}\n`);
	logfile.close();
}

function simple_track_node(ctx, name) {
	if (isEmpty(name))
		return null;

	const node = uci.get_all(uciconfig, name) || {};
	/* A node deleted from the node page or removed by a subscription update
	 * leaves a dangling reference. Callers promote a fallback or fail closed;
	 * never emit an outbound that cannot be resolved. */
	if (isEmpty(node.type)) {
		simple_log(sprintf('Simple routing: node %s is missing.', name));
		return null;
	}

	ctx.node_cfgs[name] = node;
	if (node.type === 'direct')
		ctx.direct_outbounds[simple_node_tag(name)] = true;
	return name;
}

/* Only a direct node's own outbound is registered above. URLTest group tags
 * never are, so a row that mixes direct and proxy nodes keeps proxy DNS. */
function simple_is_direct_outbound(ctx, tag) {
	return ctx.direct_outbounds[tag] === true;
}

function simple_track_outbound(ctx, tag) {
	if (!~index(ctx.route_outbounds, tag))
		push(ctx.route_outbounds, tag);
	return tag;
}

function simple_add_group(ctx, primary, fallbacks) {
	let nodes = [ primary ];
	for (let f in fallbacks)
		if (f !== primary && !~index(nodes, f))
			push(nodes, f);

	/* A single node does not need URLTest: reference its outbound directly. */
	if (length(nodes) === 1)
		return simple_track_outbound(ctx, simple_node_tag(nodes[0]));

	/* Reuse a group when several rows share the same ordered node sequence. */
	const signature = join(',', nodes);
	if (ctx.group_tags[signature])
		return ctx.group_tags[signature];

	const tag = 'simple-grp-' + length(ctx.groups) + '-out';
	ctx.group_tags[signature] = tag;
	push(ctx.groups, { tag: tag, nodes: nodes });
	return simple_track_outbound(ctx, tag);
}

function simple_add_ruleset(ctx, base, value) {
	if (isEmpty(value))
		return null;

	const url = simple_ruleset_url(base, value);
	if (ctx.ruleset_tags[url])
		return ctx.ruleset_tags[url];

	const tag = 'simple-rs-' + length(ctx.rulesets) + '-rule';
	ctx.ruleset_tags[url] = tag;
	push(ctx.rulesets, { tag: tag, url: url });
	return tag;
}

/* Only GeoSite-like rule sets can be reused in DNS rules. Bare identifiers
 * default to GeoSite; full URLs without a known category are skipped with a
 * log instead of risking a DNS rule that references an IP-only rule set. */
function simple_add_dns_ruleset(ctx, base, value) {
	if (match(value, /(^|\/)geoip\//))
		return null;

	if (match(value, /^https?:\/\//) && !match(value, /\/geosite\//)) {
		simple_log(sprintf('Simple routing: skipping DNS condition for unknown rule set %s.', value));
		return null;
	}

	const tag = simple_add_ruleset(ctx, base, value);
	return tag ? { rule_set: tag } : null;
}

function simple_add_dns_server(ctx, sb_config, detour) {
	if (!ctx.remote_dns_used)
		return null;

	let remote_detour = detour;
	if (ctx.remote_dns_detour === 'direct-out')
		remote_detour = 'direct-out';
	else if (!isEmpty(ctx.remote_dns_detour))
		remote_detour = ctx.remote_dns_detour;
	if (isEmpty(remote_detour))
		return null;

	if (ctx.dns_server_tags[remote_detour])
		return ctx.dns_server_tags[remote_detour];

	const tag = 'simple-dns-' + length(keys(ctx.dns_server_tags));
	ctx.dns_server_tags[remote_detour] = tag;

	let dns_addr = ctx.dns_server;
	if (isEmpty(dns_addr) || dns_addr === 'wan')
		dns_addr = wan_dns;

	push(sb_config.dns.servers, {
		tag: tag,
		domain_resolver: {
			server: 'default-dns',
			strategy: (ipv6_support !== '1') ? 'ipv4_only' : null
		},
		detour: remote_detour,
		...parse_dnsserver(dns_addr, 'tcp')
	});
	return tag;
}

const simple = (routing_mode === 'simple') ? {
	groups: [],
	group_tags: {},
	rulesets: [],
	ruleset_tags: {},
	node_cfgs: {},
	rules: [],
	route_outbounds: [],
	final: 'direct-out',
	default_proxy: false,
	download_detour: null,
	remote_dns_detour: null,
	dns_server_tags: {},
	dns_server: null,
	china_dns_server: null,
	cn_ruleset_tag: null,
	noncn_ruleset_tag: null,
	geoip_cn_ruleset_tag: null,
	remote_dns_used: false,
	cn_dns_enabled: false,
	dns_rule_count: 0,
	direct_outbounds: {},
	health_url: 'https://www.gstatic.com/generate_204',
	health_interval: null,
	health_tolerance: 30000,
	update_interval: '1d',
	dns_cache_size: '4096',
	dns_optimistic: '0'
} : null;

if (simple) {
	const simple_cfg = uci.get_all(uciconfig, ucisimple) || {};
	const base = replace(simple_cfg.ruleset_url_base ||
		'https://cdn.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@sing/geo', /\/+$/, '');

	simple.dns_server = simple_cfg.dns_server;
	simple.china_dns_server = simple_cfg.china_dns_server;
	simple.health_url = simple_cfg.health_check_url || 'https://www.gstatic.com/generate_204';
	simple.health_interval = strToTime(simple_cfg.health_check_interval || '180');
	/* 30000 keeps the selected node until it fails (no automatic failback).
	 * A smaller value lets a recovered, faster primary take over again.
	 * Clamp to stay well below the uint16 delay sing-box adds this to. */
	let failback_tolerance = strToInt(simple_cfg.failback_tolerance);
	/* strToInt() yields NaN for non-numeric input, which is truthy in ucode,
	 * so test the type as well instead of relying on a truthiness check. */
	if (type(failback_tolerance) !== 'int' || failback_tolerance < 1 || failback_tolerance > 30000)
		failback_tolerance = 30000;
	simple.health_tolerance = failback_tolerance;
	simple.update_interval = simple_cfg.ruleset_update_interval || '1d';
	simple.dns_cache_size = simple_cfg.dns_cache_size || '4096';
	simple.dns_optimistic = simple_cfg.dns_optimistic || '0';

	/* simple_log() writes into RUN_DIR before the JSON is emitted. */
	system('mkdir -p ' + RUN_DIR);

	uci.foreach(uciconfig, ucisimplerule, (rule) => {
		if (rule.enabled !== '1')
			return;

		let primary = simple_track_node(simple, rule.node);
		let fallbacks = [];
		for (let f in simple_array(rule.fallback_nodes)) {
			const fb = simple_track_node(simple, f);
			if (fb)
				push(fallbacks, fb);
		}

		let conditions = [], dns_conditions = [];

		const builtin_sets = simple_array(rule.rule_sets);
		for (let ident in builtin_sets) {
			const tag = simple_add_ruleset(simple, base, ident);
			if (tag)
				push(conditions, { rule_set: tag });

			const dns_condition = simple_add_dns_ruleset(simple, base, ident);
			if (dns_condition)
				push(dns_conditions, dns_condition);
		}

		const custom_sets = simple_array(rule.rule_set_urls);
		for (let value in custom_sets) {
			const tag = simple_add_ruleset(simple, base, value);
			if (tag)
				push(conditions, { rule_set: tag });

			const dns_condition = simple_add_dns_ruleset(simple, base, value);
			if (dns_condition)
				push(dns_conditions, dns_condition);
		}

		const domains = simple_array(rule.domains);
		if (length(domains)) {
			/* Distinct sub-rules: fields inside one route rule are ANDed. */
			push(conditions, { domain: domains });
			push(conditions, { domain_suffix: domains });
			push(dns_conditions, { domain: domains });
			push(dns_conditions, { domain_suffix: domains });
		}

		const ip_cidrs = simple_array(rule.ip_cidrs);
		if (length(ip_cidrs))
			push(conditions, { ip_cidr: ip_cidrs });

		/* A logical "or" rule is required: fields inside a plain route rule
		 * are combined with AND, which would almost never match. */
		if (length(conditions)) {
			let group = null;
			let blocked = false;

			if (primary) {
				group = simple_add_group(simple, primary, fallbacks);
			} else if (length(fallbacks)) {
				/* A deleted primary must not discard the whole row: that would
				 * let its domains, IPs and rule sets fall through to the
				 * default outbound even though a healthy fallback exists. */
				primary = fallbacks[0];
				group = simple_add_group(simple, primary, fallbacks);
				simple_log(sprintf('Simple routing: rule %s lost its primary node, promoting %s.',
					rule['.name'], primary));
			} else {
				/* No usable node at all: fail closed instead of silently
				 * letting this traffic go direct. block-out always exists. */
				group = 'block-out';
				blocked = true;
				simple_log(sprintf('Simple routing: rule %s has no valid node, blocking its traffic.',
					rule['.name']));
			}

			const direct_group = simple_is_direct_outbound(simple, group);

			push(simple.rules, {
				group: group,
				conditions: conditions,
				/* DNS follows the same ordered row and the same domain
				 * conditions as routing; the DNS stage then picks a resolver
				 * matching this row's outbound. A blocked row has no resolver. */
				dns_conditions: blocked ? [] : dns_conditions
			});
			if (!blocked && !direct_group && length(dns_conditions))
				simple.dns_rule_count = simple.dns_rule_count + 1;
		}
	});

	/* Outbound for traffic not matched by any row. */
	const final_node = simple_cfg.default_outbound || 'direct-out';
	if (final_node in ['direct-out', 'block-out'])
		simple.final = final_node;
	else if (simple_track_node(simple, final_node)) {
		simple.final = simple_node_tag(final_node);
		simple_track_outbound(simple, simple.final);
	} else {
		/* The user explicitly asked for a proxy default. Never fail open to
		 * direct when that node has been deleted by a subscription update. */
		simple.final = 'block-out';
		simple_log(sprintf('Simple routing: default outbound %s is missing, blocking unmatched traffic.', final_node));
	}
	simple.default_proxy = true;
	if (simple.final in ['direct-out', 'block-out'] || simple_is_direct_outbound(simple, simple.final))
		simple.default_proxy = false;

	/* Remote DNS is independent from rule set downloads. Empty means align
	 * each DNS query with its data outbound, "wan" forces WAN DNS for all
	 * queries, and "direct-out" reaches the configured remote DNS directly. */
	const dns_node = simple_cfg.remote_dns_detour;
	if (dns_node === 'wan' || dns_node === 'direct-out')
		simple.remote_dns_detour = dns_node;
	else if (simple_track_node(simple, dns_node))
		simple.remote_dns_detour = simple_node_tag(dns_node);
	else if (!isEmpty(dns_node))
		simple_log(sprintf('Simple routing: remote DNS node %s is missing, using automatic DNS routing.', dns_node));

	/* Rule sets are downloaded independently from DNS. Automatic reuses the
	 * first proxy-capable routing outbound so a multi-node group keeps its
	 * fallback order; a direct node cannot reliably fetch remote rule sets. */
	const download_node = simple_cfg.ruleset_download_detour;
	if (download_node === 'direct-out')
		simple.download_detour = null;
	else if (simple_track_node(simple, download_node))
		simple.download_detour = simple_node_tag(download_node);
	else {
		if (!isEmpty(download_node))
			simple_log(sprintf('Simple routing: download node %s is missing, using automatic selection.', download_node));
		for (let tag in simple.route_outbounds)
			if (isEmpty(simple.download_detour) && !simple_is_direct_outbound(simple, tag))
				simple.download_detour = tag;
		if (isEmpty(simple.download_detour))
			for (let name in keys(simple.node_cfgs))
				if (isEmpty(simple.download_detour) && !simple_is_direct_outbound(simple, simple_node_tag(name)))
					simple.download_detour = simple_node_tag(name);
	}

	simple.remote_dns_used = (simple.remote_dns_detour !== 'wan') &&
		(simple.default_proxy || simple.dns_rule_count > 0) &&
		(length(simple.route_outbounds) > 0 || !isEmpty(simple.remote_dns_detour));

	/* Domestic DNS uses the same GeoSite and GeoIP combination as the classic
	 * bypass-mainland-China mode. No proxy DNS means no extra rule sets. */
	if (simple.remote_dns_used && !isEmpty(simple.china_dns_server) && simple.china_dns_server !== 'nil') {
		simple.cn_ruleset_tag = simple_add_ruleset(simple, base, 'geosite/geolocation-cn');
		simple.noncn_ruleset_tag = simple_add_ruleset(simple, base, 'geosite/geolocation-!cn');
		simple.geoip_cn_ruleset_tag = simple_add_ruleset(simple, base, 'geoip/cn');
		simple.cn_dns_enabled = true;
	}
}
/* Simple routing translation end */

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
			rule_set_ip_cidr_accept_empty: strToBool(cfg.rule_set_ip_cidr_accept_empty),
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
} else if (simple) {
	/* Return expired answers immediately and refresh them in the background
	 * (sing-box 1.14+, default stale window: 3 days). Opt-in: a shorter TTL
	 * keeps the cache closer to the upstream view. */
	config.dns.optimistic = strToBool(simple.dns_optimistic);

	/* Keep the sing-box LRU in step with the dnsmasq cache. sing-box defaults
	 * to 1024 entries, which would evict answers that dnsmasq still considers
	 * hot. Zero keeps the sing-box default. */
	let cache_capacity = strToInt(simple.dns_cache_size);
	if (cache_capacity) {
		if (cache_capacity < 1024)
			cache_capacity = 1024;
		else if (cache_capacity > 10000)
			cache_capacity = 10000;
		config.dns.cache_capacity = cache_capacity;
	}

	/* Domestic DNS resolves over a direct connection so Chinese sites keep
	 * their local CDN addresses. Define it before the per-row DNS rules. */
	if (simple.cn_dns_enabled) {
		let china_dns_addr = simple.china_dns_server;
		if (china_dns_addr === 'wan')
			china_dns_addr = wan_dns;

		push(config.dns.servers, {
			tag: 'china-dns',
			domain_resolver: { server: 'default-dns' },
			detour: self_mark ? 'direct-out' : null,
			...parse_dnsserver(china_dns_addr)
		});
	}

	/* DNS rules mirror the ordered routing rows and use the same domain
	 * conditions, so a domain is resolved through a resolver matching the
	 * outbound that carries its data: proxy rows use their own remote DNS,
	 * direct rows resolve locally. GeoIP / IP CIDR conditions cannot be
	 * evaluated at the DNS stage and are not part of dns_conditions. */
	for (let r in simple.rules) {
		if (!length(r.dns_conditions))
			continue;

		let dns_tag;
		if (simple_is_direct_outbound(simple, r.group))
			dns_tag = simple.cn_dns_enabled ? 'china-dns' : 'default-dns';
		else
			dns_tag = simple_add_dns_server(simple, config, r.group);
		if (!dns_tag)
			continue;

		push(config.dns.rules, {
			type: 'logical',
			mode: 'or',
			rules: r.dns_conditions,
			action: 'route',
			server: dns_tag
		});
	}

	config.dns.final = 'default-dns';
	if (simple.default_proxy) {
		const final_dns = simple_add_dns_server(simple, config, simple.final);
		if (final_dns)
			config.dns.final = final_dns;
	}

	/* Fallback for domestic domains not covered by any row: keep the local
	 * CDN address even when the default DNS final goes through a proxy.
	 * Explicit per-row DNS rules above take precedence. */
	if (simple.cn_dns_enabled) {
		push(config.dns.rules, {
			rule_set: simple.cn_ruleset_tag,
			action: 'route',
			server: 'china-dns'
		});
		push(config.dns.rules, {
			type: 'logical',
			mode: 'and',
			rules: [
				{
					rule_set: simple.noncn_ruleset_tag,
					invert: true
				},
				{
					rule_set: simple.geoip_cn_ruleset_tag
				}
			],
			action: 'route',
			server: 'china-dns'
		});
	}

	if (isEmpty(config.dns.rules))
		config.dns.rules = null;
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
		endpoint_independent_nat: strToBool(endpoint_independent_nat),
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
		const main_urltest_nodes = uci.get(uciconfig, ucimain, 'main_urltest_nodes') || [];
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
		const main_udp_urltest_nodes = uci.get(uciconfig, ucimain, 'main_udp_urltest_nodes') || [];
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
			push(config.outbounds, {
				type: 'urltest',
				tag: 'cfg-' + cfg['.name'] + '-out',
				outbounds: map(cfg.urltest_nodes, (k) => `cfg-${k}-out`),
				url: cfg.urltest_url,
				interval: strToTime(cfg.urltest_interval),
				tolerance: strToInt(cfg.urltest_tolerance),
				idle_timeout: strToTime(cfg.urltest_idle_timeout),
				interrupt_exist_connections: strToBool(cfg.urltest_interrupt_exist_connections)
			});
			urltest_nodes = [...urltest_nodes, ...filter(cfg.urltest_nodes, (l) => !~index(urltest_nodes, l))];
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
				/* A direct outbound has no server address to resolve. */
				if (cfg.domain_resolver && outbound.type !== 'direct')
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
} else if (simple) {
	/* One outbound per referenced node, shared by all groups using it. */
	for (let name in keys(simple.node_cfgs)) {
		const node = simple.node_cfgs[name];
		if (node.type === 'wireguard') {
			const endpoint = generate_endpoint(node);
			endpoint.tag = simple_node_tag(name);
			endpoint.domain_resolver = { server: 'default-dns' };
			push(config.endpoints, endpoint);
		} else {
			const outbound = generate_outbound(node);
			outbound.tag = simple_node_tag(name);
			/* A direct outbound has no upstream server to resolve. */
			if (node.type !== 'direct')
				outbound.domain_resolver = { server: 'default-dns' };
			push(config.outbounds, outbound);
		}
	}

	/* Only multi-node rows need URLTest. Outbound order is the failover
	 * priority: sing-box keeps the selected node unless a candidate beats it
	 * by more than "tolerance" ms, and falls through when a node fails. */
	for (let g in simple.groups) {
		push(config.outbounds, {
			type: 'urltest',
			tag: g.tag,
			outbounds: map(g.nodes, (n) => simple_node_tag(n)),
			url: simple.health_url,
			interval: simple.health_interval,
			tolerance: simple.health_tolerance,
			interrupt_exist_connections: true
		});
	}

	simple_log(sprintf('Simple routing: generated %d node outbounds and %d URLTest groups.',
		length(keys(simple.node_cfgs)), length(simple.groups)));
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
			download_detour: 'main-out'
		});
		push(config.route.rule_set, {
			type: 'remote',
			tag: 'geosite-cn',
			format: 'binary',
			url: 'https://fastly.jsdelivr.net/gh/1715173329/sing-geosite@rule-set-unstable/geosite-geolocation-cn.srs',
			download_detour: 'main-out'
		});
		push(config.route.rule_set, {
			type: 'remote',
			tag: 'geosite-noncn',
			format: 'binary',
			url: 'https://fastly.jsdelivr.net/gh/1715173329/sing-geosite@rule-set-unstable/geosite-geolocation-!cn.srs',
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

		const rule = {
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
			invert: strToBool(cfg.invert),
			action: cfg.action,
			outbound: get_outbound(cfg.outbound),
			override_address: cfg.override_address,
			override_port: strToInt(cfg.override_port),
			udp_disable_domain_unmapping: strToBool(cfg.udp_disable_domain_unmapping),
			udp_connect: strToBool(cfg.udp_connect),
			udp_timeout: strToTime(cfg.udp_timeout),
			tls_fragment: strToBool(cfg.tls_fragment),
			tls_fragment_fallback_delay: strToTime(cfg.tls_fragment_fallback_delay),
			tls_record_fragment: strToBool(cfg.tls_record_fragment)
		};

		if (cfg.action === 'resolve') {
			rule.server = get_resolver(cfg.resolve_server);
			rule.strategy = cfg.resolve_strategy;
			rule.disable_cache = strToBool(cfg.resolve_disable_cache);
			rule.rewrite_ttl = strToInt(cfg.resolve_rewrite_ttl);
			rule.client_subnet = cfg.resolve_client_subnet;
		}

		push(config.route.rules, rule);
	});

	config.route.final = get_outbound(default_outbound);

	/* Rule set */
	uci.foreach(uciconfig, uciruleset, (cfg) => {
		if (cfg.enabled !== '1')
			return null;

		push(config.route.rule_set, {
			type: cfg.type,
			tag: 'cfg-' + cfg['.name'] + '-rule',
			format: cfg.format,
			path: cfg.path,
			url: cfg.url,
			download_detour: get_outbound(cfg.outbound),
			update_interval: cfg.update_interval
		});
	});
} else if (simple) {
	config.route.default_domain_resolver = {
		action: 'route',
		server: 'default-dns',
		strategy: (ipv6_support !== '1') ? 'prefer_ipv4' : null
	};

	for (let r in simple.rules) {
		const route_rule = {
			type: 'logical',
			mode: 'or',
			rules: r.conditions
		};

		/* A rule without any usable node must fail closed. Use the explicit
		 * reject action instead of routing to the legacy block outbound. */
		if (r.group === 'block-out') {
			route_rule.action = 'reject';
		} else {
			route_rule.action = 'route';
			route_rule.outbound = r.group;
		}

		push(config.route.rules, route_rule);
	}

	config.route.final = simple.final;

	for (let rs in simple.rulesets)
		push(config.route.rule_set, {
			type: 'remote',
			tag: rs.tag,
			format: 'binary',
			url: rs.url,
			download_detour: simple.download_detour,
			update_interval: simple.update_interval
		});

	for (let rs in simple.rulesets)
		simple_log(sprintf('Simple routing: queued remote rule set %s via %s.',
			rs.url, simple.download_detour || 'direct-out'));

	simple_log(sprintf('Simple routing: %d remote rule sets queued; runtime results are in sing-box-c.log.',
		length(simple.rulesets)));
	simple_log(sprintf('Simple routing: DNS final %s; %d proxy DNS rules; CN split %s; remote DNS mode %s.',
		config.dns.final, simple.dns_rule_count,
		simple.cn_dns_enabled ? 'enabled' : 'disabled',
		simple.remote_dns_detour || 'auto'));
	simple_log(sprintf('Simple routing: sing-box DNS cache capacity %s; optimistic cache %s.',
		config.dns.cache_capacity || 'default',
		strToBool(simple.dns_optimistic) ? 'enabled' : 'disabled'));

	if (isEmpty(config.route.rule_set))
		config.route.rule_set = null;
}
/* Routing rules end */

/* Experimental start */
if (routing_mode in ['bypass_mainland_china', 'custom', 'simple']) {
	config.experimental = {
		cache_file: {
			enabled: true,
			path: RUN_DIR + '/cache.db',
			store_rdrc: strToBool(cache_file_store_rdrc),
			rdrc_timeout: strToTime(cache_file_rdrc_timeout),
		}
	};
}
/* Experimental end */

system('mkdir -p ' + RUN_DIR);
writefile(RUN_DIR + '/sing-box-c.json', sprintf('%.J\n', removeBlankAttrs(config)));
