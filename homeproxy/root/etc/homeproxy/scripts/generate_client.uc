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
	removeBlankAttrs, validation, HP_DIR as DEFAULT_HP_DIR, RUN_DIR as DEFAULT_RUN_DIR
} from 'homeproxy';
import {
	apply_outbound_tag_rename as applyOutboundTagRenameHelper,
	assert_unique_outbound_tags as assertUniqueOutboundTagsHelper,
	assert_no_stale_outbound_tags as assertNoStaleOutboundTagsHelper,
	build_outbound_tag_map,
	get_outbound_tag,
	get_shadowtls_outbound_tag,
	get_fallback_outbound_tag
} from 'outbound_tag';
import { expand_node_filter as expandNodeFilterHelper } from 'node_filter';
import * as routingTarget from 'routing_target';

function testRootArg() {
	const argv = (type(ARGV) === 'array') ? ARGV : [];

	for (let i = 0; i < length(argv); i++)
		if (argv[i] === '--test-root' && !isEmpty(argv[i + 1]))
			return argv[i + 1];

	return null;
}

const TEST_ROOT = testRootArg();
const HP_DIR = TEST_ROOT ? TEST_ROOT + '/etc/homeproxy' : DEFAULT_HP_DIR;
const RUN_DIR = TEST_ROOT ? TEST_ROOT + '/var/run/homeproxy' : DEFAULT_RUN_DIR;
const DIAGNOSTICS_PATH = RUN_DIR + '/config-diagnostics.json';

/* 配置错误与诊断收集 */
let config_errors = [];

function reportError(type, message, suggestion) {
	push(config_errors, {
		type: type,           /* 'error', 'warning' */
		message: message,
		suggestion: suggestion
	});
}

function hasErrors() {
	for (let err in config_errors)
		if (err.type === 'error')
			return true;
	return false;
}

function formatErrors() {
	let output = '';
	for (let err in config_errors) {
		output += sprintf('[%s] %s\n', uc(err.type), err.message);
		if (err.suggestion)
			output += sprintf('建议: %s\n', err.suggestion);
		output += '\n';
	}
	return output;
}

function writeDiagnostics() {
	system('mkdir -p ' + RUN_DIR);

	if (length(config_errors)) {
		writefile(DIAGNOSTICS_PATH, sprintf('%.J\n', {
			time: time(),
			items: config_errors
		}));
	} else {
		system('rm -f ' + DIAGNOSTICS_PATH);
	}
}

const ubus = TEST_ROOT ? null : connect();

/* const features = ubus.call('luci.homeproxy', 'singbox_get_features') || {}; */

/* UCI config start */
const uci = TEST_ROOT ? cursor(TEST_ROOT + '/etc/config') : cursor();

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
const routing_target_max_depth = 20;
const routing_target_ctx = {
	uci: uci,
	config: uciconfig,
	node_type: ucinode,
	tag_map: build_outbound_tag_map(uci),
	max_depth: routing_target_max_depth,
	reportError: reportError
};

let wan_dns = TEST_ROOT ? null : ubus.call('network.interface', 'status', {'interface': 'wan'})?.['dns-server']?.[0];
if (!wan_dns)
	wan_dns = (routing_mode in ['proxy_mainland_china', 'global']) ? '8.8.8.8' : '223.5.5.5';

const dns_port = uci.get(uciconfig, uciinfra, 'dns_port') || '5333';

const ntp_server = uci.get(uciconfig, uciinfra, 'ntp_server') || 'time.apple.com';

const ipv6_support = uci.get(uciconfig, ucimain, 'ipv6_support') || '0';

let main_node, main_udp_node, dedicated_udp_node, default_outbound, default_outbound_dns,
    domain_strategy, sniff_override, dns_server, china_dns_server, dns_default_strategy,
    dns_default_server, dns_disable_cache, dns_disable_cache_expire, dns_independent_cache,
    dns_client_subnet, cache_file_store_rdrc, cache_file_rdrc_timeout, direct_domain_list,
    proxy_domain_list;

/* Routing / DNS advanced settings may still be in use when非 custom模式下 main_node 为空 */
default_outbound = uci.get(uciconfig, uciroutingsetting, 'default_outbound') || 'nil';
default_outbound_dns = uci.get(uciconfig, uciroutingsetting, 'default_outbound_dns') || 'default-dns';
domain_strategy = uci.get(uciconfig, uciroutingsetting, 'domain_strategy');
dns_default_strategy = uci.get(uciconfig, ucidnssetting, 'default_strategy') ||
	uci.get(uciconfig, ucidnssetting, 'dns_strategy');
dns_default_server = uci.get(uciconfig, ucidnssetting, 'default_server') || 'default-dns';
dns_disable_cache = uci.get(uciconfig, ucidnssetting, 'disable_cache');
dns_disable_cache_expire = uci.get(uciconfig, ucidnssetting, 'disable_cache_expire');
dns_independent_cache = uci.get(uciconfig, ucidnssetting, 'independent_cache');
dns_client_subnet = uci.get(uciconfig, ucidnssetting, 'client_subnet');
cache_file_store_rdrc = uci.get(uciconfig, ucidnssetting, 'cache_file_store_rdrc');
cache_file_rdrc_timeout = uci.get(uciconfig, ucidnssetting, 'cache_file_rdrc_timeout');

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
	if (!isEmpty(main_node))
		dns_default_strategy = (ipv6_support !== '1') ? 'ipv4_only' : null;

	direct_domain_list = trim(readfile(HP_DIR + '/resources/direct_list.txt'));
	if (direct_domain_list)
		direct_domain_list = split(direct_domain_list, /[\r\n]/);

	proxy_domain_list = trim(readfile(HP_DIR + '/resources/proxy_list.txt'));
	if (proxy_domain_list)
		proxy_domain_list = split(proxy_domain_list, /[\r\n]/);

	sniff_override = uci.get(uciconfig, uciinfra, 'sniff_override') ||
		uci.get(uciconfig, uciroutingsetting, 'sniff_override') || '1';
} else {
	sniff_override = uci.get(uciconfig, uciroutingsetting, 'sniff_override');
}

const use_default_outbound_routing = isEmpty(main_node) && !isEmpty(default_outbound);

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
	if (main_udp_node !== 'nil' || routing_mode === 'custom' || use_default_outbound_routing)
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

const clash_api_enabled = uci.get(uciconfig, ucimain, 'clash_api_enabled') || '0',
      clash_api_external_controller = uci.get(uciconfig, ucimain, 'clash_api_external_controller') || '127.0.0.1:9090',
      clash_api_secret = uci.get(uciconfig, ucimain, 'clash_api_secret'),
      clash_api_default_mode = uci.get(uciconfig, ucimain, 'clash_api_default_mode') || 'Rule',
      clash_api_allow_origin = uci.get(uciconfig, ucimain, 'clash_api_allow_origin') || [],
      clash_api_allow_private_network = uci.get(uciconfig, ucimain, 'clash_api_allow_private_network') || '1';

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

function section_outbound_tag(section) {
	return get_fallback_outbound_tag(section);
}

function node_outbound_tag(node_or_section) {
	let section = (type(node_or_section) === 'object') ? node_or_section['.name'] : node_or_section;
	return section_outbound_tag(section);
}

function runtime_outbound_tag(node_or_section) {
	let section = (type(node_or_section) === 'object') ? node_or_section['.name'] : node_or_section;
	return get_outbound_tag(routing_target_ctx.tag_map, section);
}

function runtime_shadowtls_tag(node_or_section) {
	let section = (type(node_or_section) === 'object') ? node_or_section['.name'] : node_or_section;
	return get_shadowtls_outbound_tag(routing_target_ctx.tag_map, section);
}

function map_outbound_tags(node_ids) {
	return map(node_ids, (node_id) => node_outbound_tag(node_id));
}

function generate_endpoint(node, tag) {
	if (type(node) !== 'object' || isEmpty(node))
		return null;

	const endpoint = {
		type: node.type,
		tag: tag || node_outbound_tag(node),
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

function generate_outbound(node, tag) {
	if (type(node) !== 'object' || isEmpty(node))
		return null;

	const outbound = {
		type: node.type,
		tag: tag || node_outbound_tag(node),
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

function generate_shadowtls_outbound(node, tag) {
	if (type(node) !== 'object' || node.shadowtls_enabled === '0' || isEmpty(node.shadowtls_address))
		return null;

	return {
		type: 'shadowtls',
		tag: tag,
		routing_mark: strToInt(self_mark),
		server: node.shadowtls_address,
		server_port: strToInt(node.shadowtls_port),
		version: strToInt(node.shadowtls_version),
		password: node.shadowtls_password,
		tls: {
			enabled: true,
			server_name: node.shadowtls_sni
		}
	};
}

function has_shadowtls_detour(node) {
	return type(node) === 'object' &&
	       node.type === 'shadowsocks' &&
	       node.shadowtls_enabled !== '0' &&
	       !isEmpty(node.shadowtls_address);
}

function apply_routing_node_options(outbound, cfg) {
	if (type(outbound) !== 'object' || type(cfg) !== 'object' || isEmpty(cfg))
		return;

	outbound.bind_interface = cfg.bind_interface;
	if (cfg.outbound) {
		if (routingTarget.routing_node_has_path(routing_target_ctx, cfg.outbound, cfg['.name'], {}))
			reportError('error',
				sprintf('路由节点配置错误：%s 的上游出站与自身形成循环引用。', cfg.label || cfg['.name']),
				'进入 LuCI 界面 -> 服务 -> HomeProxy -> 路由节点，检查该节点的"上游出站"配置');
		else
			outbound.detour = get_outbound(cfg.outbound, 'block-out',
				sprintf('路由节点 %s 的上游出站', cfg.label || cfg['.name']));
	}
	if (cfg.domain_resolver)
		outbound.domain_resolver = {
			server: get_resolver(cfg.domain_resolver),
			strategy: cfg.domain_strategy
		};
}

function push_node_outbound(client_config, node, tag, routing_cfg) {
	if (type(node) !== 'object' || isEmpty(node))
		return;

	if (node.type === 'wireguard') {
		push(client_config.endpoints, generate_endpoint(node, tag));
		apply_routing_node_options(client_config.endpoints[length(client_config.endpoints)-1], routing_cfg);
	} else {
		let outbound = generate_outbound(node, tag);
		if (has_shadowtls_detour(node)) {
			const shadowtls_tag = (tag === node_outbound_tag(node))
				? runtime_shadowtls_tag(node)
				: tag + '-shadowtls';
			let shadowtls_outbound = generate_shadowtls_outbound(node, shadowtls_tag);
			apply_routing_node_options(shadowtls_outbound, routing_cfg);
			outbound.detour = shadowtls_tag;
			push(client_config.outbounds, shadowtls_outbound);
		} else {
			apply_routing_node_options(outbound, routing_cfg);
		}
		push(client_config.outbounds, outbound);
	}
}

function push_block_outbound(client_config, tag) {
	push(client_config.outbounds, {
		type: 'block',
		tag: tag
	});
}

function is_builtin_outbound(target) {
	return routingTarget.is_builtin_outbound(routing_target_ctx, target);
}

function is_node_section(target) {
	return routingTarget.is_node_section(routing_target_ctx, target);
}

function is_routing_node_section(target) {
	return routingTarget.is_routing_node_section(routing_target_ctx, target);
}

function expand_node_filter(manual_nodes, node_filter, node_filter_exclude, owner, allow_routing_node) {
	let result = expandNodeFilterHelper({
		uci: uci,
		config: uciconfig,
		node_type: ucinode,
		allow_manual_node: (node_id) => {
			if (is_node_section(node_id) ||
			    (allow_routing_node && (is_builtin_outbound(node_id) || is_routing_node_section(node_id))))
				return true;

			return false;
		},
		on_invalid_manual_node: (node_id) => {
			reportError('warning',
				sprintf('节点组 %s 引用了已删除的节点：%s，已在本次生成中跳过。', owner, node_id),
				'请进入 LuCI 界面检查对应的节点列表引用');
		}
	}, manual_nodes, node_filter, node_filter_exclude);

	if (!result.result) {
		if (!isEmpty(node_filter) && !isEmpty(node_filter_exclude)) {
			reportError('error',
				sprintf('路由节点 %s 的节点正则或排除正则无效：%s', owner, result.error),
				'请修正节点正则/排除正则，或清空该字段后重新生成配置');
		} else if (!isEmpty(node_filter)) {
			reportError('error',
				sprintf('路由节点 %s 的节点正则无效：%s', owner, result.error),
				'请修正节点正则，或清空该字段后重新生成配置');
		} else {
			reportError('error',
				sprintf('路由节点 %s 的排除正则无效：%s', owner, result.error),
				'请修正排除正则，或清空该字段后重新生成配置');
		}

		return [];
	}

	if (result.truncated)
		reportError('warning',
			sprintf('路由节点 %s 的节点正则命中超过 %d 个节点，已截断结果。', owner, result.max_result_nodes),
			'请收窄节点正则或拆分路由节点，避免一次生成过大的 outbound 组');

	if (result.scan_truncated)
		reportError('warning',
			sprintf('路由节点 %s 的节点正则扫描超过 %d 个节点，已停止继续匹配。', owner, result.max_scan_nodes),
			'请收窄订阅节点规模或正则范围，避免生成器长时间执行复杂匹配');

	return result.nodes || [];
}

function resolve_outbound_target(target, owner, seen_path) {
	return routingTarget.resolve_outbound_target(routing_target_ctx, target, owner, seen_path);
}

function get_routing_target_outbound(target, owner) {
	return routingTarget.get_routing_target_outbound(routing_target_ctx, target, owner);
}

function push_routing_target_outbound(client_config, target, routing_nodes) {
	return routingTarget.collect_routing_target_dependencies(
		routing_target_ctx,
		client_config,
		target,
		routing_nodes,
		push_node_outbound,
		node_outbound_tag
	);
}

function get_valid_selector_outbounds(selector_nodes, owner, owner_section) {
	return routingTarget.get_valid_selector_outbounds(routing_target_ctx, selector_nodes, owner, owner_section);
}

function get_outbound(cfg, fallback, owner) {
	return routingTarget.get_outbound(routing_target_ctx, cfg, fallback, owner);
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

function apply_outbound_tag_rename(client_config) {
	return applyOutboundTagRenameHelper(client_config, routing_target_ctx.tag_map);
}

function assert_unique_outbound_tags(client_config) {
	return assertUniqueOutboundTagsHelper(client_config, (tag) => {
		reportError('error',
			sprintf('rename 后出现重复 outbound tag: %s', tag),
			'通常意味着去重算法异常；请附带节点 label / section 列表反馈');
	});
}

function assert_no_stale_outbound_tags(client_config) {
	return assertNoStaleOutboundTagsHelper(client_config, routing_target_ctx.tag_map, (old_tag, final_tag) => {
		reportError('error',
			sprintf('rename 后仍残留旧 outbound tag 引用: %s -> %s', old_tag, final_tag),
			'请检查新增 sing-box 字段是否需要纳入 outbound tag rename 规则');
	});
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

		let outbound = get_outbound(cfg.outbound, 'block-out',
			sprintf('DNS Server %s 的出站', cfg.label || cfg['.name']));
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
			outbound: get_outbound(cfg.outbound, 'block-out',
				sprintf('DNS 规则 %s 的出站匹配', cfg.label || cfg['.name'])),
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
	sniff: true,
	sniff_override_destination: strToBool(sniff_override),
	set_system_proxy: false
});

if (match(proxy_mode, /redirect/))
	push(config.inbounds, {
		type: 'redirect',
		tag: 'redirect-in',

		listen: '::',
		listen_port: int(redirect_port),
		sniff: true,
		sniff_override_destination: strToBool(sniff_override)
	});
if (match(proxy_mode, /tproxy/) && !isEmpty(tproxy_port))
	push(config.inbounds, {
		type: 'tproxy',
		tag: 'tproxy-in',

		listen: '::',
		listen_port: int(tproxy_port),
		network: 'udp',
		udp_timeout: strToTime(udp_timeout),
		sniff: true,
		sniff_override_destination: strToBool(sniff_override)
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
		stack: tcpip_stack,
		sniff: true,
		sniff_override_destination: strToBool(sniff_override)
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
		const main_urltest_nodes = expand_node_filter(
			uci.get(uciconfig, ucimain, 'main_urltest_nodes') || [],
			null,
			null,
			'main_node',
			false);
		const main_urltest_interval = uci.get(uciconfig, ucimain, 'main_urltest_interval');
		const main_urltest_tolerance = uci.get(uciconfig, ucimain, 'main_urltest_tolerance');

		if (length(main_urltest_nodes)) {
			push(config.outbounds, {
				type: 'urltest',
				tag: 'main-out',
				outbounds: map_outbound_tags(main_urltest_nodes),
				interval: strToTime(main_urltest_interval),
				tolerance: strToInt(main_urltest_tolerance),
				idle_timeout: (strToInt(main_urltest_interval) > 1800) ? `${main_urltest_interval * 2}s` : null,
			});
		} else {
			reportError('warning',
				'主节点 URLTest 列表没有可用节点，已在本次生成中临时回退为阻断出站。',
				'请进入 LuCI 界面 -> 服务 -> HomeProxy -> 客户端，重新选择主节点 URLTest 列表');
			push_block_outbound(config, 'main-out');
		}
		urltest_nodes = main_urltest_nodes;
	} else {
		const main_node_cfg = uci.get_all(uciconfig, main_node) || {};
		if (is_node_section(main_node)) {
			push_node_outbound(config, main_node_cfg, 'main-out');
		} else {
			reportError('warning',
				sprintf('主节点引用了已删除的节点：%s，已在本次生成中临时回退为阻断出站。', main_node),
				'请进入 LuCI 界面 -> 服务 -> HomeProxy -> 客户端，重新选择主节点');
			push_block_outbound(config, 'main-out');
		}
	}

	if (main_udp_node === 'urltest') {
		const main_udp_urltest_nodes = expand_node_filter(
			uci.get(uciconfig, ucimain, 'main_udp_urltest_nodes') || [],
			null,
			null,
			'main_udp_node',
			false);
		const main_udp_urltest_interval = uci.get(uciconfig, ucimain, 'main_udp_urltest_interval');
		const main_udp_urltest_tolerance = uci.get(uciconfig, ucimain, 'main_udp_urltest_tolerance');

		if (length(main_udp_urltest_nodes)) {
			push(config.outbounds, {
				type: 'urltest',
				tag: 'main-udp-out',
				outbounds: map_outbound_tags(main_udp_urltest_nodes),
				interval: strToTime(main_udp_urltest_interval),
				tolerance: strToInt(main_udp_urltest_tolerance),
				idle_timeout: (strToInt(main_udp_urltest_interval) > 1800) ? `${main_udp_urltest_interval * 2}s` : null,
			});
		} else {
			reportError('warning',
				'主 UDP 节点 URLTest 列表没有可用节点，已在本次生成中临时回退为阻断出站。',
				'请进入 LuCI 界面 -> 服务 -> HomeProxy -> 客户端，重新选择主 UDP 节点 URLTest 列表');
			push_block_outbound(config, 'main-udp-out');
		}
		urltest_nodes = [...urltest_nodes, ...filter(main_udp_urltest_nodes, (l) => !~index(urltest_nodes, l))];
	} else if (dedicated_udp_node) {
		const main_udp_node_cfg = uci.get_all(uciconfig, main_udp_node) || {};
		if (is_node_section(main_udp_node)) {
			push_node_outbound(config, main_udp_node_cfg, 'main-udp-out');
		} else {
			reportError('warning',
				sprintf('主 UDP 节点引用了已删除的节点：%s，已在本次生成中临时回退为阻断出站。', main_udp_node),
				'请进入 LuCI 界面 -> 服务 -> HomeProxy -> 客户端，重新选择主 UDP 节点');
			push_block_outbound(config, 'main-udp-out');
		}
	}

	for (let i in urltest_nodes) {
		const urltest_node = uci.get_all(uciconfig, i) || {};
		push_node_outbound(config, urltest_node, node_outbound_tag(i));
	}
} else if (!isEmpty(default_outbound)) {
	let group_nodes = [],
	    routing_nodes = [];

	uci.foreach(uciconfig, uciroutingnode, (cfg) => {
		if (cfg.enabled !== '1')
			return;

		if (cfg.node === 'urltest') {
			const owner = cfg.label || cfg['.name'];
			const urltest_nodes = expand_node_filter(cfg.urltest_nodes, cfg.node_filter, cfg.node_filter_exclude, owner, false);
			if (!length(urltest_nodes)) {
				reportError('warning',
					sprintf('路由节点 %s 没有可用节点，已在本次生成中临时回退为阻断出站。', owner),
					'请手动选择节点，或调整节点正则/排除正则以命中可用节点');
				push_block_outbound(config, node_outbound_tag(cfg));
				return;
			}

			push(config.outbounds, {
				type: 'urltest',
				tag: node_outbound_tag(cfg),
				outbounds: map_outbound_tags(urltest_nodes),
				url: cfg.urltest_url,
				interval: strToTime(cfg.urltest_interval),
				tolerance: strToInt(cfg.urltest_tolerance),
				idle_timeout: strToTime(cfg.urltest_idle_timeout),
				interrupt_exist_connections: strToBool(cfg.urltest_interrupt_exist_connections)
			});
			group_nodes = [...group_nodes, ...filter(urltest_nodes, (l) => !~index(group_nodes, l))];
		} else if (cfg.node === 'selector') {
			const owner = cfg.label || cfg['.name'];
			const selector_nodes = expand_node_filter(cfg.selector_nodes, cfg.node_filter, cfg.node_filter_exclude, owner, true);
			const selector_outbounds = get_valid_selector_outbounds(selector_nodes, owner, cfg['.name']);
			if (!length(selector_outbounds)) {
				reportError('warning',
					sprintf('路由节点 %s 没有可用节点，已在本次生成中临时回退为阻断出站。', owner),
					'请手动选择节点，或调整节点正则/排除正则以命中可用节点');
				push_block_outbound(config, node_outbound_tag(cfg));
				return;
			}

			let selector_default = get_routing_target_outbound(
				cfg.selector_default,
				sprintf('路由节点 %s 的默认 Selector 节点', owner));
			if (!isEmpty(selector_default) && !~index(selector_outbounds, selector_default))
				selector_default = null;

			push(config.outbounds, {
				type: 'selector',
				tag: node_outbound_tag(cfg),
				outbounds: selector_outbounds,
				default: selector_default,
				interrupt_exist_connections: strToBool(cfg.selector_interrupt_exist_connections)
			});
			group_nodes = [...group_nodes, ...filter(selector_nodes, (l) => !~index(group_nodes, l))];
		} else {
			const resolved = resolve_outbound_target(
				cfg.node,
				sprintf('路由节点 %s 的节点', cfg.label || cfg['.name']),
				[]);

			if (!resolved || resolved.fatal || resolved.type !== 'node') {
				reportError('warning',
					sprintf('路由节点 %s 的节点引用已失效，已在本次生成中临时回退为阻断出站。', cfg.label || cfg['.name']),
					'请进入 LuCI 界面 -> 服务 -> HomeProxy -> 路由节点，重新选择有效节点');
				push_block_outbound(config, node_outbound_tag(cfg));
				return;
			}

			const outbound = uci.get_all(uciconfig, resolved.node_id) || {};
			push_node_outbound(config, outbound, node_outbound_tag(resolved.node_id), cfg);
			push(routing_nodes, resolved.node_id);
		}
	});

	for (let i in filter(group_nodes, (l) => !~index(routing_nodes, l)))
		push_routing_target_outbound(config, i, routing_nodes);

	uci.foreach(uciconfig, uciroutingrule, (cfg) => {
		if (cfg.enabled === '1' && cfg.action === 'route')
			push_routing_target_outbound(config, cfg.outbound, routing_nodes);
	});
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
		}
		/*
		 * leave for sing-box 1.13.0
		 * {
		 * 	action: 'sniff'
		 * }
		 */
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
			invert: strToBool(cfg.invert),
			action: cfg.action,
			outbound: get_outbound(cfg.outbound, 'block-out',
				sprintf('路由规则 %s 的出站', cfg.label || cfg['.name'])),
			override_address: cfg.override_address,
			override_port: strToInt(cfg.override_port),
			udp_disable_domain_unmapping: strToBool(cfg.udp_disable_domain_unmapping),
			udp_connect: strToBool(cfg.udp_connect),
			udp_timeout: strToTime(cfg.udp_timeout),
			tls_fragment: strToBool(cfg.tls_fragment),
			tls_fragment_fallback_delay: strToTime(cfg.tls_fragment_fallback_delay),
			tls_record_fragment: strToBool(cfg.tls_record_fragment)
		});
	});

	config.route.final = get_outbound(default_outbound, 'block-out', '默认出站');

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
			download_detour: get_outbound(cfg.outbound, 'block-out',
				sprintf('规则集 %s 的下载出站', cfg.label || cfg['.name'])),
			update_interval: cfg.update_interval
		});
	});
}
/* Routing rules end */

/* Experimental start */
config.experimental = {};

if (routing_mode in ['bypass_mainland_china', 'custom'])
	config.experimental.cache_file = {
			enabled: true,
			path: RUN_DIR + '/cache.db',
			store_rdrc: strToBool(cache_file_store_rdrc),
			rdrc_timeout: strToTime(cache_file_rdrc_timeout),
		};

if (strToBool(clash_api_enabled))
	config.experimental.clash_api = {
		external_controller: clash_api_external_controller,
		secret: clash_api_secret,
		default_mode: clash_api_default_mode,
		access_control_allow_origin: clash_api_allow_origin,
		access_control_allow_private_network: strToBool(clash_api_allow_private_network)
	};

if (isEmpty(config.experimental))
	config.experimental = null;
/* Experimental end */

apply_outbound_tag_rename(config);
assert_unique_outbound_tags(config);
assert_no_stale_outbound_tags(config);
writeDiagnostics();

/*
 * fatal 级配置错误不能用无效配置覆盖现有 sing-box-c.json，否则 init 脚本中的
 * sing-box check 会失败并拖垮正在运行的代理。这里保留上一份有效配置，只报告
 * 聚合错误并退出非零，让服务继续使用上一份有效配置。
 */
if (hasErrors()) {
	warn('HomeProxy 配置验证发现以下问题:\n\n' + formatErrors());
	warn('为避免用无效配置覆盖当前可用配置，本次未写入新配置；服务将继续使用上次的有效配置。请修复上述问题后重启服务。\n');
	exit(1);
}

system('mkdir -p ' + RUN_DIR);
writefile(RUN_DIR + '/sing-box-c.json', sprintf('%.J\n', removeBlankAttrs(config)));
