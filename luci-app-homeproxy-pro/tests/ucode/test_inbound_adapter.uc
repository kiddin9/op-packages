#!/usr/bin/ucode
/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * PR-04 (Protocol Adapter Completion): unit tests for InboundFactory, the
 * server-side half of the adapter.
 *
 * The inbound golden snapshot (tests/ucode/test_golden_inbounds.sh) pins
 * what the adapter *emits* for the fixture's seven protocols. This test
 * covers the decisions that a snapshot cannot express:
 *
 *   - a protocol with no users[] block (snell, shadowsocks) must not get
 *     one: sing-box interprets a snell users entry as an extra user key
 *     and rejects the config outright ("snell: bad user key")
 *   - vless / vmess carry flow / alterId per user, never top-level
 *   - the snell listener set omits udp_fragment / udp_timeout / network
 *     even when the section carries them
 *   - REQUIRED_INBOUND_CREDENTIALS is enforced by problems()/buildable()
 *   - the server-only TLS tail reaches buildTLSObject() under the UCI
 *     names it reads (key_path, ech_key, reality, ACME)
 *   - hysteria v1 emits obfs as a string while hysteria2 emits the
 *     {type, password, ...} object
 *
 * Run through tests/ucode/run.sh, which stages config/ + parser/ next to
 * the homeproxy-pro test double.
 */

'use strict';

import { Inbound, INBOUND_CREDENTIALS, INBOUND_OPTIONS } from './config/model.uc';
import { InboundFactory } from './config/adapter.uc';

let failures = 0, checks = 0;

function expect(name, actual, expected) {
	checks++;
	if (sprintf('%J', actual) !== sprintf('%J', expected)) {
		printf('FAIL %s: expected %J, got %J\n', name, expected, actual);
		failures++;
	}
}

function not_in(name, obj, key) {
	checks++;
	if (key in obj) {
		printf('FAIL %s: %s should be absent, got %J\n', name, key, obj[key]);
		failures++;
	}
}

/* Build an Inbound the way the Loader would, from a flat option map.
 * `opts` uses UCI option names; the tables in model.uc do the renaming,
 * so this helper exercises the same canonical boundary the Loader does. */
function make_inbound(id, type, opts) {
	const get = (name) => (name in opts) ? opts[name] : null;
	const credentials = {};
	const protocol_options = {};

	for (let canonical, uci in (INBOUND_CREDENTIALS[type] || {}))
		credentials[canonical] = get(uci);

	for (let canonical, uci in (INBOUND_OPTIONS[type] || {}))
		protocol_options[canonical] = get(uci);

	const tls = {
		enabled: get('tls'),
		server_name: get('tls_sni'),
		insecure: get('tls_insecure'),
		alpn: get('tls_alpn'),
		min_version: get('tls_min_version'),
		max_version: get('tls_max_version'),
		handshake_timeout: get('tls_handshake_timeout'),
		cipher_suites: get('tls_cipher_suites'),
		cert_path: get('tls_cert_path'),
		ech: {
			enabled: get('tls_ech'),
			config: get('tls_ech_config'),
			config_path: get('tls_ech_config_path')
		},
		utls: { fingerprint: get('tls_utls') },
		reality: {
			enabled: get('tls_reality'),
			public_key: get('tls_reality_public_key'),
			short_id: get('tls_reality_short_id')
		}
	};

	return Inbound.create({
		id: id,
		name: opts.label || id,
		type: type,
		enabled: true,
		address: get('address'),
		port: get('port'),
		firewall: get('firewall'),
		common: {
			bind_interface: get('bind_interface'),
			reuse_addr: get('reuse_addr'),
			tcp_fast_open: get('tcp_fast_open'),
			tcp_multi_path: get('tcp_multi_path'),
			udp_fragment: get('udp_fragment'),
			udp_timeout: get('udp_timeout'),
			network: get('network')
		},
		credentials: credentials,
		tls: tls,
		tls_server: {
			key_path: get('tls_key_path'),
			ech_key: get('tls_ech_key'),
			reality_private_key: get('tls_reality_private_key'),
			reality_max_time_difference: get('tls_reality_max_time_difference'),
			reality_server_addr: get('tls_reality_server_addr'),
			reality_server_port: get('tls_reality_server_port'),
			acme: get('tls_acme'),
			acme_domain: get('tls_acme_domain'),
			acme_email: get('tls_acme_email'),
			acme_provider: get('tls_acme_provider'),
			dns01_challenge: get('tls_dns01_challenge'),
			dns01_provider: get('tls_dns01_provider')
		},
		transport: {
			type: get('transport'),
			host: get('ws_host') || get('httpupgrade_host') || get('http_host'),
			path: get('ws_path') || get('http_path'),
			headers: get('ws_host') ? { Host: get('ws_host') } : null,
			service_name: get('grpc_servicename')
		},
		multiplex: {
			enabled: get('multiplex'),
			padding: get('multiplex_padding'),
			brutal: {
				enabled: get('multiplex_brutal'),
				up_mbps: get('multiplex_brutal_up'),
				down_mbps: get('multiplex_brutal_down')
			}
		},
		protocol_options: protocol_options
	});
}

/* --- snell: no users[], reduced listener set ------------------------- */

{
	/* Deliberately set the fields snell must not be given, so the test
	 * fails if INBOUND_COMMON_OMIT is ever dropped. */
	const snell = make_inbound('s_snell', 'snell', {
		port: '8448',
		password: 'pskvalue',
		snell_version: '5',
		snell_obfs_mode: 'http',
		udp_fragment: '1',
		udp_timeout: '300',
		network: 'tcp'
	});
	const out = InboundFactory.create(snell);

	expect('snell: type', out.type, 'snell');
	expect('snell: tag', out.tag, 'cfg-s_snell-in');
	expect('snell: listen defaults to ::', out.listen, '::');
	expect('snell: listen_port', out.listen_port, 8448);
	expect('snell: psk', out.psk, 'pskvalue');
	expect('snell: version', out.version, 5);
	expect('snell: obfs_mode', out.obfs_mode, 'http');
	not_in('snell', out, 'users');
	not_in('snell', out, 'udp_fragment');
	not_in('snell', out, 'udp_timeout');
	not_in('snell', out, 'network');
	/* no `mode`: v6-only, sing-box 1.14 rejects it. */
	not_in('snell', out, 'mode');
}

/* --- shadowsocks: no users[], top-level method + password ------------ */

{
	const ss = make_inbound('s_ss', 'shadowsocks', {
		address: '10.0.0.1',
		port: '8447',
		password: 'secret',
		shadowsocks_encrypt_method: 'aes-256-gcm',
		network: 'tcp',
		udp_timeout: '300'
	});
	const out = InboundFactory.create(ss);

	expect('ss: listen honours the address', out.listen, '10.0.0.1');
	expect('ss: method', out.method, 'aes-256-gcm');
	expect('ss: password', out.password, 'secret');
	expect('ss: network is kept', out.network, 'tcp');
	expect('ss: udp_timeout is a duration', out.udp_timeout, '300s');
	not_in('ss', out, 'users');
}

/* --- vless: flow is per-user, never top-level ------------------------ */

{
	const vless = make_inbound('s_vless', 'vless', {
		port: '443',
		uuid: 'uuid-x',
		vless_flow: 'xtls-rprx-vision',
		tls: '1',
		tls_sni: 'v.example.com'
	});
	const out = InboundFactory.create(vless);

	expect('vless: user name', out.users[0].name, 'cfg-s_vless-server');
	expect('vless: user uuid', out.users[0].uuid, 'uuid-x');
	expect('vless: user flow', out.users[0].flow, 'xtls-rprx-vision');
	not_in('vless', out, 'flow');
	not_in('vless', out, 'uuid');
	expect('vless: tls enabled', out.tls.enabled, true);
	expect('vless: tls server_name', out.tls.server_name, 'v.example.com');
}

/* --- vmess: alterId is per-user, never top-level --------------------- */

{
	const vmess = make_inbound('s_vmess', 'vmess', {
		port: '443',
		uuid: 'uuid-y',
		vmess_alterid: '1'
	});
	const out = InboundFactory.create(vmess);

	expect('vmess: user alterId', out.users[0].alterId, 1);
	not_in('vmess', out, 'alterId');
	not_in('vmess', out, 'alter_id');

	/* vmess_alterid='0' is the modern (AEAD) setting, but the shared
	 * strToInt() helper maps '0' to null (`int('0') || null`), so the
	 * field is omitted and sing-box applies its own default. That is
	 * pre-existing behaviour of the common helper, not something PR-04
	 * changes; pinned here so a future strToInt() fix shows up as a
	 * deliberate diff rather than a surprise. */
	const vmess0 = InboundFactory.create(make_inbound('s_vmess0', 'vmess', {
		port: '443',
		uuid: 'uuid-y',
		vmess_alterid: '0'
	}));
	not_in('vmess0: user alterId', vmess0.users[0], 'alterId');
}

/* --- http / mixed / socks / naive: user has no name ------------------ */

{
	const http = make_inbound('s_http', 'http', {
		port: '8080',
		username: 'u',
		password: 'p'
	});
	const out = InboundFactory.create(http);

	expect('http: user username', out.users[0].username, 'u');
	expect('http: user has no name', out.users[0].name, null);
}

/* --- hysteria v1 vs hysteria2 obfs shape ----------------------------- */

{
	const hy1 = make_inbound('s_hy1', 'hysteria', {
		port: '36712',
		hysteria_auth_type: 'string',
		hysteria_auth_payload: 'secret',
		hysteria_obfs_password: 'obfspass',
		hysteria_up_mbps: '100',
		hysteria_down_mbps: '500',
		hysteria_masquerade: 'https://example.com',
		tls: '1',
		tls_sni: 'h.example.com'
	});
	const out = InboundFactory.create(hy1);

	expect('hy1: obfs is a plain string', out.obfs, 'obfspass');
	expect('hy1: up_mbps', out.up_mbps, 100);
	expect('hy1: down_mbps', out.down_mbps, 500);
	expect('hy1: masquerade', out.masquerade, 'https://example.com');
	expect('hy1: user auth_str', out.users[0].auth_str, 'secret');
	not_in('hy1: user auth', out.users[0], 'auth');
}

{
	const hy2 = make_inbound('s_hy2', 'hysteria2', {
		port: '8445',
		password: 'secret',
		hysteria_obfs_type: 'salamander',
		hysteria_obfs_password: 'obfspass',
		hysteria_obfs_min_packet_size: '512',
		hysteria_obfs_max_packet_size: '1200'
	});
	const out = InboundFactory.create(hy2);

	expect('hy2: obfs.type', out.obfs.type, 'salamander');
	expect('hy2: obfs.password', out.obfs.password, 'obfspass');
	expect('hy2: obfs.min_packet_size', out.obfs.min_packet_size, 512);
	expect('hy2: obfs.max_packet_size', out.obfs.max_packet_size, 1200);
	/* auth is not modelled on hysteria2's options row, so neither
	 * spelling is emitted. */
	not_in('hy2: user auth', out.users[0], 'auth');
	not_in('hy2: user auth_str', out.users[0], 'auth_str');
}

/* --- tuic ------------------------------------------------------------ */

{
	const tuic = make_inbound('s_tuic', 'tuic', {
		port: '8449',
		uuid: 'uuid-z',
		password: 'pw',
		tuic_congestion_control: 'bbr',
		tuic_auth_timeout: '3',
		tuic_enable_zero_rtt: '1',
		tuic_heartbeat: '10',
		tls: '1',
		tls_sni: 't.example.com'
	});
	const out = InboundFactory.create(tuic);

	expect('tuic: congestion_control', out.congestion_control, 'bbr');
	expect('tuic: auth_timeout', out.auth_timeout, '3s');
	expect('tuic: zero_rtt_handshake', out.zero_rtt_handshake, true);
	expect('tuic: heartbeat', out.heartbeat, '10s');
	expect('tuic: user uuid', out.users[0].uuid, 'uuid-z');
}

/* --- anytls: padding_scheme ----------------------------------------- */

{
	const anytls = make_inbound('s_anytls', 'anytls', {
		port: '8444',
		password: 'secret',
		anytls_padding_scheme: 'stop=8'
	});
	const out = InboundFactory.create(anytls);

	expect('anytls: padding_scheme', out.padding_scheme, 'stop=8');
	expect('anytls: user password', out.users[0].password, 'secret');
}

/* --- multiplex (server shape: no dialling knobs) -------------------- */

{
	const trojan = make_inbound('s_trojan', 'trojan', {
		port: '8446',
		password: 'secret',
		multiplex: '1',
		multiplex_padding: '1'
	});
	const out = InboundFactory.create(trojan);

	expect('trojan: multiplex enabled', out.multiplex.enabled, true);
	expect('trojan: multiplex padding', out.multiplex.padding, true);
	/* The server side has no protocol / max_connections / min_streams /
	 * max_streams: those are client dialling knobs. */
	not_in('trojan: multiplex', out.multiplex, 'protocol');
	not_in('trojan: multiplex', out.multiplex, 'max_connections');
	not_in('trojan: multiplex', out.multiplex, 'min_streams');
	not_in('trojan: multiplex', out.multiplex, 'max_streams');
}

/* --- the server-only TLS tail reaches buildTLSObject() --------------- */

{
	const inbound = make_inbound('s_tls', 'vless', {
		port: '443',
		uuid: 'u',
		tls: '1',
		tls_sni: 't.example.com',
		tls_key_path: '/etc/homeproxy-pro/certs/t.key',
		tls_ech_key: 'ECHKEY',
		tls_acme: '1',
		tls_acme_domain: 't.example.com',
		tls_acme_email: 'admin@example.com',
		tls_acme_provider: 'letsencrypt'
	});
	const out = InboundFactory.create(inbound);

	expect('tls: key_path', out.tls.key_path, '/etc/homeproxy-pro/certs/t.key');
	expect('tls: ech.key', out.tls.ech.key, ['ECHKEY']);
	expect('tls: acme type', out.tls.certificate_provider.type, 'acme');
	expect('tls: acme domain is an array', out.tls.certificate_provider.domain, ['t.example.com']);
	expect('tls: acme email', out.tls.certificate_provider.email, 'admin@example.com');
	expect('tls: acme provider', out.tls.certificate_provider.provider, 'letsencrypt');
	/* A client-side field must not appear on a server inbound. */
	not_in('tls', out.tls, 'insecure');
	not_in('tls', out.tls, 'utls');
}

{
	/* reality: the server side gets the private key + the handshake
	 * address, the client side's public key stays out. */
	const inbound = make_inbound('s_reality', 'vless', {
		port: '443',
		uuid: 'u',
		tls: '1',
		tls_reality: '1',
		tls_sni: 'r.example.com',
		tls_reality_private_key: 'PRIVKEY',
		tls_reality_short_id: 'abcd',
		tls_reality_server_addr: 'hw.example.com',
		tls_reality_server_port: '443'
	});
	const out = InboundFactory.create(inbound);

	expect('reality: private_key', out.tls.reality.private_key, 'PRIVKEY');
	expect('reality: short_id', out.tls.reality.short_id, 'abcd');
	expect('reality: handshake server', out.tls.reality.handshake.server, 'hw.example.com');
	expect('reality: handshake server_port', out.tls.reality.handshake.server_port, 443);
	not_in('reality', out.tls.reality, 'public_key');
}

/* --- validation ------------------------------------------------------ */

expect('vless without uuid is not buildable',
	InboundFactory.buildable(make_inbound('x', 'vless', { port: '443' })), false);
expect('vless with uuid is buildable',
	InboundFactory.buildable(make_inbound('x', 'vless', { port: '443', uuid: 'u' })), true);
expect('snell without psk is not buildable',
	InboundFactory.buildable(make_inbound('x', 'snell', { port: '443' })), false);
expect('snell with psk is buildable',
	InboundFactory.buildable(make_inbound('x', 'snell', { port: '443', password: 'k' })), true);
expect('shadowsocks without password is not buildable',
	InboundFactory.buildable(make_inbound('x', 'shadowsocks', { port: '443' })), false);
expect('http needs no credential',
	InboundFactory.buildable(make_inbound('x', 'http', { port: '8080' })), true);

{
	const bad = InboundFactory.tryCreate(make_inbound('s_bad', 'vless', { port: '443' }));
	expect('tryCreate returns no inbound on problems', bad.inbound, null);
	expect('tryCreate names the missing credential',
		length(filter(bad.problems, (p) => match(p, /requires uuid/))), 1);
}
{
	/* The port check is protocol-agnostic and lives on Inbound.validate(). */
	const bad = InboundFactory.tryCreate(make_inbound('s_badport', 'http', { port: '99999' }));
	expect('tryCreate rejects an out-of-range port', bad.inbound, null);
	expect('tryCreate reports the port',
		length(filter(bad.problems, (p) => match(p, /invalid port/))), 1);
}

/* --- transport ------------------------------------------------------- */

{
	const ws = make_inbound('s_ws', 'vless', {
		port: '443',
		uuid: 'u',
		transport: 'ws',
		ws_host: 'a.example.com',
		ws_path: '/ws'
	});
	const out = InboundFactory.create(ws);

	expect('transport: type', out.transport.type, 'ws');
	expect('transport: path', out.transport.path, '/ws');
	expect('transport: host from headers', out.transport.host, 'a.example.com');
}

printf('%d checks, %d failures\n', checks, failures);
exit(failures === 0 ? 0 : 1);
