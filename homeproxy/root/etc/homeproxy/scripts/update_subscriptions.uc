#!/usr/bin/ucode
/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * Copyright (C) 2023 ImmortalWrt.org
 */

'use strict';

import { md5 } from 'digest';
import { open, writefile } from 'fs';
import { connect } from 'ubus';
import { cursor } from 'uci';

import { urldecode, urlencode } from 'luci.http';
import { init_action } from 'luci.sys';
import { remove_subscription_nodes } from '/etc/homeproxy/scripts/node_references.uc';
import { parse_surge_subscription } from '/etc/homeproxy/scripts/subscription_parsers.uc';

import {
	wGETResult, decodeBase64Str, getTime, isEmpty, parseURL,
	validation, HP_DIR, RUN_DIR
} from 'homeproxy';

/* UCI config start */
const uci = cursor();

const uciconfig = 'homeproxy';
uci.load(uciconfig);

const ucimain = 'config',
      ucinode = 'node',
      ucisubscription = 'subscription';

const allow_insecure = uci.get(uciconfig, ucisubscription, 'allow_insecure') || '0',
      allow_unsupported_tls_pin_fallback = uci.get(uciconfig, ucisubscription, 'allow_unsupported_tls_pin_fallback') || '0',
      filter_mode = uci.get(uciconfig, ucisubscription, 'filter_nodes') || 'disabled',
      filter_keywords = uci.get(uciconfig, ucisubscription, 'filter_keywords') || [],
      packet_encoding = uci.get(uciconfig, ucisubscription, 'packet_encoding') || 'xudp',
      subscription_urls = uci.get(uciconfig, ucisubscription, 'subscription_url') || [],
      user_agent = uci.get(uciconfig, ucisubscription, 'user_agent'),
      via_proxy = uci.get(uciconfig, ucisubscription, 'update_via_proxy') || '0';

const routing_mode = uci.get(uciconfig, ucimain, 'routing_mode') || 'bypass_mainalnd_china';
let main_node, main_udp_node;
if (routing_mode !== 'custom') {
	main_node = uci.get(uciconfig, ucimain, 'main_node') || 'nil';
	main_udp_node = uci.get(uciconfig, ucimain, 'main_udp_node') || 'nil';
}
/* UCI config end */

/* String helper start */
function filter_check(name) {
	if (isEmpty(name) || filter_mode === 'disabled' || isEmpty(filter_keywords))
		return false;

	let ret = false;
	for (let i in filter_keywords) {
		const patten = regexp(i);
		if (match(name, patten))
			ret = true;
	}
	if (filter_mode === 'whitelist')
		ret = !ret;

	return ret;
}
/* String helper end */

/* Common var start */
const node_cache = {},
      node_result = [];

const ubus = connect();
const sing_features = ubus.call('luci.homeproxy', 'singbox_get_features', {}) || {};
/* Common var end */

const SUBSCRIPTION_DIAGNOSTICS_PATH = RUN_DIR + '/subscription-diagnostics.json';
const SUBSCRIPTION_UPDATE_STATUS_PATH = RUN_DIR + '/subscription-update-status.json';
let subscription_diagnostics = [];

/* Log */
system(`mkdir -p ${RUN_DIR}`);
function log(...args) {
	const logfile = open(`${RUN_DIR}/homeproxy.log`, 'a');
	logfile.write(`${getTime()} [SUBSCRIBE] ${join(' ', args)}\n`);
	logfile.close();
}

function reportSubscriptionDiagnostic(type, message, suggestion) {
	push(subscription_diagnostics, {
		type,
		source: 'subscription',
		message,
		suggestion
	});
}

function writeSubscriptionDiagnostics() {
	system(`mkdir -p ${RUN_DIR}`);

	if (length(subscription_diagnostics)) {
		writefile(SUBSCRIPTION_DIAGNOSTICS_PATH, sprintf('%.J\n', {
			time: time(),
			items: subscription_diagnostics
		}));
	} else {
		system(`rm -f ${SUBSCRIPTION_DIAGNOSTICS_PATH}`);
	}
}

function writeSubscriptionUpdateStatus(running, completed, update_result, error) {
	system(`mkdir -p ${RUN_DIR}`);
	writefile(SUBSCRIPTION_UPDATE_STATUS_PATH, sprintf('%.J\n', {
		time: time(),
		running: !!running,
		completed: !!completed,
		update_result,
		error: error || null
	}));
}

function sanitizeCommandError(text) {
	text = trim(text || '');
	if (isEmpty(text))
		return null;

	text = split(text, '\n')[0] || text;
	return text;
}

function uci_value_equal(a, b) {
	if (type(a) == 'array')
		a = map(a, (v) => sprintf('%s', v));
	else
		a = sprintf('%s', a);

	if (type(b) == 'array')
		b = map(b, (v) => sprintf('%s', v));
	else
		b = sprintf('%s', b);

	return sprintf('%J', a) == sprintf('%J', b);
}

function setOrDeleteList(section, option, values) {
	if (length(values))
		uci.set(uciconfig, section, option, values);
	else
		uci.delete(uciconfig, section, option);
}

function logCleanupChange(change) {
	if (!change || !change.node_id)
		return;

	let target = sprintf('%s.%s', change.section || '-', change.option || '-'),
	    action = change.action || 'update',
	    value = (action === 'set') ? sprintf(' to %s', change.value) : '';

	log(sprintf('Cleaned reference to deleted subscription node %s: %s %s%s.',
		change.node_id, target, action, value));
}

function version_at_least(version, major, minor, patch) {
	const m = match(version || '', /^([0-9]+)\.([0-9]+)\.([0-9]+)/);
	if (!m)
		return false;

	const current = [ int(m[1]), int(m[2]), int(m[3]) ],
	      required = [ major, minor, patch ];

	for (let i = 0; i < 3; i++) {
		if (current[i] > required[i])
			return true;
		if (current[i] < required[i])
			return false;
	}

	return true;
}

function tls_cert_pin_unsupported() {
	return !version_at_least(sing_features.version, 1, 13, 0);
}

function apply_tls_cert_pin_policy(config, label, pin) {
	if (!pin || !tls_cert_pin_unsupported())
		return;

	const node_label = label || config.label || 'NULL',
	      version = sing_features.version || 'unknown';

	if (config.tls_insecure === '1')
		return;

	if (allow_unsupported_tls_pin_fallback === '1' || config.type === 'hysteria2') {
		config.tls_insecure = '1';
		log(sprintf('Node %s uses server certificate fingerprint, but sing-box %s cannot express it; enabling explicit TLS insecure compatibility fallback.',
			node_label,
			version));
		reportSubscriptionDiagnostic('warning',
			sprintf('订阅节点 %s 使用证书指纹，但当前 sing-box %s 不支持 certificate_public_key_sha256；已降级为 TLS insecure 继续兼容。', node_label, version),
			(config.type === 'hysteria2')
				? '这是延续旧行为的兼容回退；如需更严格校验，请升级到支持 certificate_public_key_sha256 的 sing-box'
				: '若安全要求较高，请关闭“Allow unsupported certificate pin fallback”，让此类节点默认跳过');
		return;
	}

	config.__skip_reason = sprintf('该节点使用证书指纹，但当前 sing-box %s 不支持 certificate_public_key_sha256，已跳过。', version);
	reportSubscriptionDiagnostic('warning',
		sprintf('订阅节点 %s 使用证书指纹，但当前 sing-box %s 不支持 certificate_public_key_sha256，已跳过。', node_label, version),
		'升级到支持 certificate_public_key_sha256 的 sing-box，或显式开启兼容 fallback 后重新更新订阅');
	log(sprintf('Skipping node %s: server certificate fingerprint is unsupported by sing-box %s.',
		node_label,
		version));
}

function parse_uri(uri) {
	let config, url, params;

	if (type(uri) === 'object') {
		if (uri.nodetype === 'sip008') {
			/* https://shadowsocks.org/guide/sip008.html */
			config = {
				label: uri.remarks,
				type: 'shadowsocks',
				address: uri.server,
				port: uri.server_port,
				shadowsocks_encrypt_method: uri.method,
				password: uri.password,
				shadowsocks_plugin: uri.plugin,
				shadowsocks_plugin_opts: uri.plugin_opts
			};
		}
	} else if (type(uri) === 'string') {
		uri = split(trim(uri), '://');

		switch (uri[0]) {
		case 'anytls':
			/* https://github.com/anytls/anytls-go/blob/v0.0.8/docs/uri_scheme.md */
			url = parseURL('http://' + uri[1]) || {};
			params = url.searchParams || {};

			config = {
				label: url.hash ? urldecode(url.hash) : null,
				type: 'anytls',
				address: url.hostname,
				port: url.port,
				password: urldecode(url.username),
				tls: '1',
				tls_sni: params.sni,
				tls_insecure: (params.insecure === '1') ? '1' : '0'
			};

			break;
		case 'http':
		case 'https':
			url = parseURL('http://' + uri[1]) || {};

			config = {
				label: url.hash ? urldecode(url.hash) : null,
				type: 'http',
				address: url.hostname,
				port: url.port,
				username: url.username ? urldecode(url.username) : null,
				password: url.password ? urldecode(url.password) : null,
				tls: (uri[0] === 'https') ? '1' : '0'
			};

			break;
		case 'hysteria':
			/* https://github.com/HyNetwork/hysteria/wiki/URI-Scheme */
			url = parseURL('http://' + uri[1]) || {};
			params = url.searchParams || {};

			if (!sing_features.with_quic || (params.protocol && params.protocol !== 'udp')) {
				log(sprintf('Skipping unsupported %s node: %s.', uri[0], urldecode(url.hash) || url.hostname));
				if (!sing_features.with_quic)
					log(sprintf('Please rebuild sing-box with %s support!', 'QUIC'));

				return null;
			}

			config = {
				label: url.hash ? urldecode(url.hash) : null,
				type: 'hysteria',
				address: url.hostname,
				port: url.port,
				hysteria_protocol: params.protocol || 'udp',
				hysteria_auth_type: params.auth ? 'string' : null,
				hysteria_auth_payload: params.auth,
				hysteria_obfs_password: params.obfsParam,
				hysteria_down_mbps: params.downmbps,
				hysteria_up_mbps: params.upmbps,
				tls: '1',
				tls_insecure: (params.insecure in ['true', '1']) ? '1' : '0',
				tls_sni: params.peer,
				tls_alpn: params.alpn
			};

			break;
		case 'hysteria2':
		case 'hy2':
			/* https://v2.hysteria.network/docs/developers/URI-Scheme/ */
			url = parseURL('http://' + uri[1]) || {};
			params = url.searchParams || {};

			if (!sing_features.with_quic) {
				log(sprintf('Skipping unsupported %s node: %s.', uri[0], urldecode(url.hash) || url.hostname));
				log(sprintf('Please rebuild sing-box with %s support!', 'QUIC'));
				return null;
			}

			config = {
				label: url.hash ? urldecode(url.hash) : null,
				type: 'hysteria2',
				address: url.hostname,
				port: url.port,
				password: url.username ? (
					urldecode(url.username + (url.password ? (':' + url.password) : ''))
				) : null,
				hysteria_obfs_type: params.obfs,
				hysteria_obfs_password: params['obfs-password'],
				tls: '1',
				tls_insecure: (params.insecure === '1') ? '1' : '0',
				tls_sni: params.sni
			};
				apply_tls_cert_pin_policy(config, config.label, params.pinSHA256);

			break;
		case 'socks':
		case 'socks4':
		case 'socks4a':
		case 'socsk5':
		case 'socks5h':
			url = parseURL('http://' + uri[1]) || {};

			config = {
				label: url.hash ? urldecode(url.hash) : null,
				type: 'socks',
				address: url.hostname,
				port: url.port,
				username: url.username ? urldecode(url.username) : null,
				password: url.password ? urldecode(url.password) : null,
				socks_version: (match(uri[0], /4/)) ? '4' : '5'
			};

			break;
		case 'ss':
			/* "Lovely" Shadowrocket format */
			const ss_suri = split(uri[1], '#');
			let ss_slabel = '';
			if (length(ss_suri) <= 2) {
				if (length(ss_suri) === 2)
					ss_slabel = '#' + urlencode(ss_suri[1]);
				if (decodeBase64Str(ss_suri[0]))
					uri[1] = decodeBase64Str(ss_suri[0]) + ss_slabel;
			}

			/* Legacy format is not supported, it should be never appeared in modern subscriptions */
			/* https://github.com/shadowsocks/shadowsocks-org/commit/78ca46cd6859a4e9475953ed34a2d301454f579e */

			/* SIP002 format https://shadowsocks.org/guide/sip002.html */
			url = parseURL('http://' + uri[1]) || {};

			let ss_userinfo = {};
			if (url.username && url.password)
				/* User info encoded with URIComponent */
				ss_userinfo = [url.username, urldecode(url.password)];
			else if (url.username)
				/* User info encoded with base64 */
				ss_userinfo = split(decodeBase64Str(urldecode(url.username)), ':', 2);

			let ss_plugin, ss_plugin_opts;
			if (url.search && url.searchParams.plugin) {
				const ss_plugin_info = split(url.searchParams.plugin, ';', 2);
				ss_plugin = ss_plugin_info[0];
				if (ss_plugin === 'simple-obfs')
					/* Fix non-standard plugin name */
					ss_plugin = 'obfs-local';
				ss_plugin_opts = ss_plugin_info[1];
			}

			config = {
				label: url.hash ? urldecode(url.hash) : null,
				type: 'shadowsocks',
				address: url.hostname,
				port: url.port,
				shadowsocks_encrypt_method: ss_userinfo[0],
				password: ss_userinfo[1],
				shadowsocks_plugin: ss_plugin,
				shadowsocks_plugin_opts: ss_plugin_opts
			};

			break;
		case 'trojan':
			/* https://p4gefau1t.github.io/trojan-go/developer/url/ */
			url = parseURL('http://' + uri[1]) || {};
			params = url.searchParams || {};

			config = {
				label: url.hash ? urldecode(url.hash) : null,
				type: 'trojan',
				address: url.hostname,
				port: url.port,
				password: urldecode(url.username),
				transport: (params.type !== 'tcp') ? params.type : null,
				tls: '1',
				tls_sni: params.sni
			};
			switch(params.type) {
			case 'grpc':
				config.grpc_servicename = params.serviceName;
				break;
			case 'ws':
				config.ws_host = params.host ? urldecode(params.host) : null;
				config.ws_path = params.path ? urldecode(params.path) : null;
				if (config.ws_path && match(config.ws_path, /\?ed=/)) {
					config.websocket_early_data_header = 'Sec-WebSocket-Protocol';
					config.websocket_early_data = split(config.ws_path, '?ed=')[1];
					config.ws_path = split(config.ws_path, '?ed=')[0];
				}
				break;
			}

			break;
		case 'tuic':
			/* https://github.com/daeuniverse/dae/discussions/182 */
			url = parseURL('http://' + uri[1]) || {};
			params = url.searchParams || {};

			if (!sing_features.with_quic) {
				log(sprintf('Skipping unsupported %s node: %s.', uri[0], urldecode(url.hash) || url.hostname));
				log(sprintf('Please rebuild sing-box with %s support!', 'QUIC'));

				return null;
			}

			config = {
				label: url.hash ? urldecode(url.hash) : null,
				type: 'tuic',
				address: url.hostname,
				port: url.port,
				uuid: url.username,
				password: url.password ? urldecode(url.password) : null,
				tuic_congestion_control: params.congestion_control,
				tuic_udp_relay_mode: params.udp_relay_mode,
				tls: '1',
				tls_sni: params.sni,
				tls_alpn: params.alpn ? split(urldecode(params.alpn), ',') : null,
			};

			break;
		case 'vless':
			/* https://github.com/XTLS/Xray-core/discussions/716 */
			url = parseURL('http://' + uri[1]) || {};
			params = url.searchParams || {};

			/* Unsupported protocol */
			if (params.type === 'kcp') {
				log(sprintf('Skipping sunsupported %s node: %s.', uri[0], urldecode(url.hash) || url.hostname));
				return null;
			} else if (params.type === 'quic' && ((params.quicSecurity && params.quicSecurity !== 'none') || !sing_features.with_quic)) {
				log(sprintf('Skipping sunsupported %s node: %s.', uri[0], urldecode(url.hash) || url.hostname));
				if (!sing_features.with_quic)
					log(sprintf('Please rebuild sing-box with %s support!', 'QUIC'));

				return null;
			}

			config = {
				label: url.hash ? urldecode(url.hash) : null,
				type: 'vless',
				address: url.hostname,
				port: url.port,
				uuid: url.username,
				transport: (params.type !== 'tcp') ? params.type : null,
				tls: (params.security in ['tls', 'xtls', 'reality']) ? '1' : '0',
				tls_sni: params.sni,
				tls_alpn: params.alpn ? split(urldecode(params.alpn), ',') : null,
				tls_reality: (params.security === 'reality') ? '1' : '0',
				tls_reality_public_key: params.pbk ? urldecode(params.pbk) : null,
				tls_reality_short_id: params.sid,
				tls_utls: sing_features.with_utls ? params.fp : null,
				vless_flow: (params.security in ['tls', 'reality']) ? params.flow : null
			};
			switch(params.type) {
			case 'grpc':
				config.grpc_servicename = params.serviceName;
				break;
			case 'http':
			case 'tcp':
				if (params.type === 'http' || params.headerType === 'http') {
					config.http_host = params.host ? split(urldecode(params.host), ',') : null;
					config.http_path = params.path ? urldecode(params.path) : null;
				}
				break;
			case 'httpupgrade':
				config.httpupgrade_host = params.host ? urldecode(params.host) : null;
				config.http_path = params.path ? urldecode(params.path) : null;
				break;
			case 'ws':
				config.ws_host = params.host ? urldecode(params.host) : null;
				config.ws_path = params.path ? urldecode(params.path) : null;
				if (config.ws_path && match(config.ws_path, /\?ed=/)) {
					config.websocket_early_data_header = 'Sec-WebSocket-Protocol';
					config.websocket_early_data = split(config.ws_path, '?ed=')[1];
					config.ws_path = split(config.ws_path, '?ed=')[0];
				}
				break;
			}

			break;
		case 'vmess':
			/* "Lovely" shadowrocket format */
			if (match(uri, /&/)) {
				log(sprintf('Skipping unsupported %s format.', uri[0]));
				return null;
			}

			/* https://github.com/2dust/v2rayN/wiki/Description-of-VMess-share-link */
			try {
				uri = json(decodeBase64Str(uri[1])) || {};
			} catch(e) {
				log(sprintf('Skipping unsupported %s format.', uri[0]));
				return null;
			}

			if (uri.v != '2') {
				log(sprintf('Skipping unsupported %s format.', uri[0]));
				return null;
			/* Unsupported protocol */
			} else if (uri.net === 'kcp') {
				log(sprintf('Skipping unsupported %s node: %s.', uri[0], uri.ps || uri.add));
				return null;
			} else if (uri.net === 'quic' && ((uri.type && uri.type !== 'none') || uri.path || !sing_features.with_quic)) {
				log(sprintf('Skipping unsupported %s node: %s.', uri[0], uri.ps || uri.add));
				if (!sing_features.with_quic)
					log(sprintf('Please rebuild sing-box with %s support!', 'QUIC'));

				return null;
			}
			/*
			 * https://www.v2fly.org/config/protocols/vmess.html#vmess-md5-%E8%AE%A4%E8%AF%81%E4%BF%A1%E6%81%AF-%E6%B7%98%E6%B1%B0%E6%9C%BA%E5%88%B6
			 * else if (uri.aid && int(uri.aid) !== 0) {
			 * 	log(sprintf('Skipping unsupported %s node: %s.', uri[0], uri.ps || uri.add));
			 * 	return null;
			 * }
			 */

			config = {
				label: uri.ps ? urldecode(uri.ps) : null,
				type: 'vmess',
				address: uri.add,
				port: uri.port,
				uuid: uri.id,
				vmess_alterid: uri.aid,
				vmess_encrypt: uri.scy || 'auto',
				vmess_global_padding: '1',
				transport: (uri.net !== 'tcp') ? uri.net : null,
				tls: (uri.tls === 'tls') ? '1' : '0',
				tls_sni: uri.sni || uri.host,
				tls_alpn: uri.alpn ? split(uri.alpn, ',') : null,
				tls_utls: sing_features.with_utls ? uri.fp : null
			};
			switch (uri.net) {
			case 'grpc':
				config.grpc_servicename = uri.path;
				break;
			case 'h2':
			case 'tcp':
				if (uri.net === 'h2' || uri.type === 'http') {
					config.transport = 'http';
					config.http_host = uri.host ? split(uri.host, ',') : null;
					config.http_path = uri.path;
				}
				break;
			case 'httpupgrade':
				config.httpupgrade_host = uri.host;
				config.http_path = uri.path;
				break;
			case 'ws':
				config.ws_host = uri.host;
				config.ws_path = uri.path;
				if (config.ws_path && match(config.ws_path, /\?ed=/)) {
					config.websocket_early_data_header = 'Sec-WebSocket-Protocol';
					config.websocket_early_data = split(config.ws_path, '?ed=')[1];
					config.ws_path = split(config.ws_path, '?ed=')[0];
				}
				break;
			}

			break;
		}
	}

	if (!isEmpty(config)) {
		if (config.address)
			config.address = replace(config.address, /\[|\]/g, '');

		if (!validation('host', config.address) || !validation('port', config.port)) {
			log(sprintf('Skipping invalid %s node: %s.', config.type, config.label || 'NULL'));
			return null;
		} else if (!config.label)
			config.label = (validation('ip6addr', config.address) ?
				`[${config.address}]` : config.address) + ':' + config.port;
	}

	return config;
}

function main() {
	for (let url in subscription_urls) {
		url = replace(url, /#.*$/, '');
		const groupHash = md5(url);
		node_cache[groupHash] = {};

		const fetch_result = wGETResult(url, user_agent) || {},
		      res = fetch_result.stdout;
		if (isEmpty(res)) {
			const reason = sanitizeCommandError(fetch_result.stderr);

			log(sprintf('Failed to fetch resources from %s.', url));
			if (!isEmpty(reason))
				log(sprintf('Fetch stderr: %s', reason));
			reportSubscriptionDiagnostic('error',
				sprintf('订阅地址拉取失败：%s', url),
				reason || '请检查路由器到订阅源的连通性、DNS 解析和 TLS 访问是否正常');
			continue;
		}

		let nodes, parsed_as_surge = false;
		try {
			nodes = json(res).servers || json(res);

			/* Shadowsocks SIP008 format */
			if (nodes[0].server && nodes[0].method)
				map(nodes, (_, i) => nodes[i].nodetype = 'sip008');
		} catch(e) {
			/* 先识别 Surge/Clash 托管配置格式（YAML 风格），再回退 Base64。 */
			if (match(res, /(^|\n)[ \t]*proxies\s*:\s*(#[^\n]*)?(\n|$)/)) {
				nodes = parse_surge_subscription({
					isEmpty,
					validation,
					sing_features,
					log,
					apply_tls_cert_pin_policy
				}, res);
				parsed_as_surge = true;
			} else {
				nodes = decodeBase64Str(res);
				nodes = nodes ? split(trim(replace(nodes, / /g, '_')), '\n') : [];
			}
		}

		let count = 0;
		for (let node in nodes) {
			let config;
			if (!isEmpty(node)) {
				/* 信任边界来自控制流，而不是节点内容：只有 parse_surge_subscription()
				 * 分支产出的节点才会被当作已解析 config。任意 JSON 中伪造的
				 * 'nodetype'/'type' 不会绕过 parse_uri()，因为 JSON 路径下
				 * parsed_as_surge=false，仍然走原有校验和白名单映射。 */
				if (parsed_as_surge && type(node) == 'object')
					config = node;
				else
					config = parse_uri(node);
			}
			if (isEmpty(config))
				continue;
			if (!isEmpty(config.__skip_reason)) {
				log(sprintf('Skipping node %s: %s', config.label || 'NULL', config.__skip_reason));
				continue;
			}

			const label = config.label;
			config.label = null;
			const confHash = md5(sprintf('%J', config)),
			      nameHash = md5(label);
			config.label = label;

			if (filter_check(config.label))
				log(sprintf('Skipping blacklist node: %s.', config.label));
			else if (node_cache[groupHash][confHash] || node_cache[groupHash][nameHash])
				log(sprintf('Skipping duplicate node: %s.', config.label));
			else {
				if (config.tls === '1' && allow_insecure === '1')
					config.tls_insecure = '1';
				if (config.type in ['vless', 'vmess'])
					config.packet_encoding = packet_encoding;

				config.grouphash = groupHash;
				push(node_result, []);
				push(node_result[length(node_result)-1], config);
				node_cache[groupHash][confHash] = config;
				node_cache[groupHash][nameHash] = config;

				count++;
			}
		}

		if (count == 0)
			log(sprintf('No valid node found in %s.', url));
		else
			log(sprintf('Successfully fetched %s nodes of total %s from %s.', count, length(nodes), url));
	}

	if (isEmpty(node_result)) {
		let fetch_errors = filter(subscription_diagnostics, (item) => item?.type === 'error' && item?.source === 'subscription');

		log('Failed to update subscriptions: no valid node found.');
		if (!length(fetch_errors))
			reportSubscriptionDiagnostic('error',
				'订阅更新失败：没有找到可用节点。',
				'请检查订阅地址、过滤规则，以及是否有节点因当前 sing-box 不支持证书指纹而被跳过');

		return false;
	}

	let added = 0, updated = 0, removed = 0,
	    stale_nodes = [],
	    stale_labels = {};
	uci.foreach(uciconfig, ucinode, (cfg) => {
		/* Nodes created by the user */
		if (!cfg.grouphash)
			return null;

		/* Empty object - failed to fetch nodes */
		if (length(node_cache[cfg.grouphash]) === 0)
			return null;

		if (!node_cache[cfg.grouphash] || !node_cache[cfg.grouphash][cfg['.name']]) {
			push(stale_nodes, cfg['.name']);
			stale_labels[cfg['.name']] = cfg.label || cfg['.name'];
			return null;
		} else {
			const node = node_cache[cfg.grouphash][cfg['.name']];
			let node_changed = false;

			for (let v in node) {
				if (isEmpty(node[v]))
					continue;

				if (!(v in cfg) || !uci_value_equal(cfg[v], node[v]))
					node_changed = true;

				uci.set(uciconfig, cfg['.name'], v, node[v]);
			}
			map(keys(cfg), (v) => {
				if (substr(v, 0, 1) == '.')
					return null;

				if (!(v in node) || isEmpty(node[v])) {
					uci.delete(uciconfig, cfg['.name'], v);
					node_changed = true;
				}
			});

			if (node_changed)
				updated++;

			node.isExisting = true;
		}
	});

	if (length(stale_nodes)) {
		const cleanup = remove_subscription_nodes(uci, uciconfig, stale_nodes);
		removed += cleanup.removed;

		for (let node_id in stale_nodes)
			log(sprintf('Removing node: %s.', stale_labels[node_id] || node_id));

		if (cleanup.changed) {
			if (uci.get(uciconfig, ucimain, 'main_node') !== main_node)
				log(sprintf('Deleted subscription node affected main node, falling back to %s.',
					uci.get(uciconfig, ucimain, 'main_node') || 'nil'));
			if (uci.get(uciconfig, ucimain, 'main_udp_node') !== main_udp_node)
				log(sprintf('Deleted subscription node affected main UDP node, falling back to %s.',
					uci.get(uciconfig, ucimain, 'main_udp_node') || 'nil'));

			for (let change in cleanup.changes)
				logCleanupChange(change);
		}
	}

	for (let nodes in node_result)
		map(nodes, (node) => {
			if (node.isExisting)
				return null;

			const nameHash = md5(node.label);
			uci.set(uciconfig, nameHash, 'node');
			map(keys(node), (v) => uci.set(uciconfig, nameHash, v, node[v]));

			added++;
			log(sprintf('Adding node: %s.', node.label));
	});
	uci.commit(uciconfig);

	let need_restart = (via_proxy !== '1') || added > 0 || updated > 0 || removed > 0;
	if (!isEmpty(main_node)) {
		const has_server = !!uci.get_first(uciconfig, ucinode);
		if (has_server) {
			let main_urltest_nodes;
			if (main_node === 'urltest') {
				main_urltest_nodes = filter(uci.get(uciconfig, ucimain, 'main_urltest_nodes') || [], (v) => {
					if (!uci.get(uciconfig, v)) {
						log(sprintf('Node %s is gone, removing from urltest list.', v));
						return false;
					}
					return true;
				});
				setOrDeleteList(ucimain, 'main_urltest_nodes', main_urltest_nodes);
				uci.commit(uciconfig);
			}

			if ((main_node === 'urltest') ? !length(main_urltest_nodes) : !uci.get(uciconfig, main_node)) {
				uci.set(uciconfig, ucimain, 'main_node', 'nil');
				uci.commit(uciconfig);
				need_restart = true;

				log('Main node is gone, disabling main node.');
			}

			if (!isEmpty(main_udp_node) && main_udp_node !== 'same') {
				let main_udp_urltest_nodes;
				if (main_udp_node === 'urltest') {
					main_udp_urltest_nodes = filter(uci.get(uciconfig, ucimain, 'main_udp_urltest_nodes') || [], (v) => {
						if (!uci.get(uciconfig, v)) {
							log(sprintf('Node %s is gone, removing from urltest list.', v));
							return false;
						}
						return true;
					});
					setOrDeleteList(ucimain, 'main_udp_urltest_nodes', main_udp_urltest_nodes);
					uci.commit(uciconfig);
				}

				if ((main_udp_node === 'urltest') ? !length(main_udp_urltest_nodes) : !uci.get(uciconfig, main_udp_node)) {
					uci.set(uciconfig, ucimain, 'main_udp_node', 'same');
					uci.commit(uciconfig);
					need_restart = true;

					log('Main UDP node is gone, falling back to the main node.');
				}
			}
		} else {
			uci.set(uciconfig, ucimain, 'main_node', 'nil');
			uci.set(uciconfig, ucimain, 'main_udp_node', 'nil');
			uci.commit(uciconfig);
			need_restart = true;

			log('No available node, disable tproxy.');
		}
	}

	if (need_restart) {
		log('Restarting service...');
		init_action('homeproxy', 'stop');
		init_action('homeproxy', 'start');
	}

	log(sprintf('%s nodes added, %s updated, %s removed.', added, updated, removed));
	log('Successfully updated subscriptions.');

	return true;
}

if (!isEmpty(subscription_urls)) {
	writeSubscriptionUpdateStatus(true, false, null, null);

	try {
		const ok = call(main);
		writeSubscriptionUpdateStatus(false, true, ok === false ? false : true,
			(ok === false) ? (subscription_diagnostics[0]?.message || '订阅更新失败。') : null);
	} catch(e) {
		const status_error = sprintf('订阅更新异常：%s: %s', e.type || 'error', e.message || e);

		log('[FATAL ERROR] An error occurred during updating subscriptions:');
		log(sprintf('%s: %s', e.type, e.message));
		log(e.stacktrace[0].context);
		reportSubscriptionDiagnostic('error',
			status_error,
			'请查看 HomeProxy 日志中的 [SUBSCRIBE] 记录并修复订阅配置');

		log('Restarting service...');
		init_action('homeproxy', 'stop');
		init_action('homeproxy', 'start');
		writeSubscriptionUpdateStatus(false, true, false, status_error);
	}
} else {
	subscription_diagnostics = [];
	writeSubscriptionUpdateStatus(false, true, false, '未配置订阅地址。');
}

writeSubscriptionDiagnostics();
