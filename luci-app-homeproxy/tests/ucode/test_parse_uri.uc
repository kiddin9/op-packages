#!/usr/bin/ucode
/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * Copyright (C) 2025 ImmortalWrt.org
 *
 * Unit tests for the share-link parsers in parse_uri.uc. Run through
 * tests/ucode/run.sh, which stages parse_uri.uc next to the mocked
 * homeproxy.uc.
 */

'use strict';

import { parse_uri } from 'parse_uri';

const FEATURES = { with_quic: true, with_utls: true };
const NO_QUIC = { with_quic: false, with_utls: true };
const LOG = (..._args) => {};

let failures = 0,
    checks = 0;

function expect_fields(name, cfg, expected) {
	if (type(cfg) !== 'object') {
		printf('FAIL %s: expected an object, got %J\n', name, cfg);
		failures++;
		return;
	}

	for (let key in expected) {
		checks++;
		if (sprintf('%J', cfg[key]) !== sprintf('%J', expected[key])) {
			printf('FAIL %s: %s expected %J, got %J\n', name, key, expected[key], cfg[key]);
			failures++;
		}
	}
}

function expect_null(name, cfg) {
	checks++;
	if (cfg !== null) {
		printf('FAIL %s: expected null, got %J\n', name, cfg);
		failures++;
	}
}

/* anytls */
expect_fields('anytls', parse_uri('anytls://secret@a.example.com:443?sni=a.example.com&insecure=1#AnyTLS-Node', FEATURES, LOG), {
	label: 'AnyTLS-Node', type: 'anytls', address: 'a.example.com', port: '443',
	password: 'secret', tls: '1', tls_sni: 'a.example.com', tls_insecure: '1'
});

/* http / https */
expect_fields('https', parse_uri('https://user:pass@b.example.com:8443#HTTPS-Node', FEATURES, LOG), {
	label: 'HTTPS-Node', type: 'http', address: 'b.example.com', port: '8443',
	username: 'user', password: 'pass', tls: '1'
});
expect_fields('http', parse_uri('http://c.example.com:8080#HTTP-Node', FEATURES, LOG), {
	label: 'HTTP-Node', type: 'http', address: 'c.example.com', port: '8080', tls: '0'
});

/* hysteria */
expect_fields('hysteria', parse_uri('hysteria://d.example.com:36712?auth=pass&peer=d.example.com&insecure=1&upmbps=100&downmbps=200&alpn=h3&protocol=udp#Hy1', FEATURES, LOG), {
	label: 'Hy1', type: 'hysteria', address: 'd.example.com', port: '36712',
	hysteria_protocol: 'udp', hysteria_auth_type: 'string', hysteria_auth_payload: 'pass',
	hysteria_up_mbps: '100', hysteria_down_mbps: '200',
	tls: '1', tls_insecure: '1', tls_sni: 'd.example.com', tls_alpn: 'h3'
});

/* hysteria2 */
expect_fields('hysteria2', parse_uri('hysteria2://pass@e.example.com:443?sni=e.example.com&obfs=salamander&obfs-password=op#Hy2', FEATURES, LOG), {
	label: 'Hy2', type: 'hysteria2', address: 'e.example.com', port: '443',
	password: 'pass', hysteria_obfs_type: 'salamander', hysteria_obfs_password: 'op',
	tls: '1', tls_insecure: '0', tls_sni: 'e.example.com'
});
expect_fields('hy2-alias', parse_uri('hy2://pass@e.example.com:443#Hy2Alias', FEATURES, LOG), {
	label: 'Hy2Alias', type: 'hysteria2', address: 'e.example.com', port: '443'
});

/* snell */
expect_fields('snell', parse_uri('snell://f.example.com:443?psk=pskvalue&version=4&obfs=http&obfs-host=bing.com&reuse=1#Snell', FEATURES, LOG), {
	label: 'Snell', type: 'snell', address: 'f.example.com', port: '443',
	password: 'pskvalue', snell_version: '4', snell_obfs_mode: 'http',
	snell_obfs_host: 'bing.com', snell_reuse: '1'
});

/* socks */
expect_fields('socks5', parse_uri('socks5://user:pass@g.example.com:1080#Socks', FEATURES, LOG), {
	label: 'Socks', type: 'socks', address: 'g.example.com', port: '1080',
	username: 'user', password: 'pass', socks_version: '5'
});
expect_fields('socks4', parse_uri('socks4://h.example.com:1080#Socks4', FEATURES, LOG), {
	socks_version: '4'
});

/* shadowsocks: SIP002 with base64 user info */
expect_fields('ss-sip002-b64', parse_uri('ss://YWVzLTI1Ni1nY206cGFzc3dvcmQ=@i.example.com:8388#SS-Node', FEATURES, LOG), {
	label: 'SS-Node', type: 'shadowsocks', address: 'i.example.com', port: '8388',
	shadowsocks_encrypt_method: 'aes-256-gcm', password: 'password'
});

/* shadowsocks: SIP002 with plugin */
expect_fields('ss-sip002-plugin', parse_uri('ss://YWVzLTI1Ni1nY206cGFzc3dvcmQ=@j.example.com:8388?plugin=simple-obfs%3Bobfs%3Dhttp#SS-Plugin', FEATURES, LOG), {
	label: 'SS-Plugin', type: 'shadowsocks', address: 'j.example.com', port: '8388',
	shadowsocks_plugin: 'obfs-local', shadowsocks_plugin_opts: 'obfs=http'
});

/* shadowsocks: Shadowrocket whole-payload base64 */
expect_fields('ss-shadowrocket', parse_uri('ss://YWVzLTI1Ni1nY206cGFzc3dvcmRAay5leGFtcGxlLmNvbTo4Mzg4#SS-SR', FEATURES, LOG), {
	label: 'SS-SR', type: 'shadowsocks', address: 'k.example.com', port: '8388',
	shadowsocks_encrypt_method: 'aes-256-gcm', password: 'password'
});

/* trojan */
expect_fields('trojan-ws', parse_uri('trojan://pass@l.example.com:443?type=ws&host=l.example.com&path=%2Fpath%3Fed%3D2048&sni=l.example.com#TrojanWs', FEATURES, LOG), {
	label: 'TrojanWs', type: 'trojan', address: 'l.example.com', port: '443', password: 'pass',
	transport: 'ws', ws_host: 'l.example.com', ws_path: '/path',
	websocket_early_data: '2048', websocket_early_data_header: 'Sec-WebSocket-Protocol',
	tls: '1', tls_sni: 'l.example.com'
});
expect_fields('trojan-grpc', parse_uri('trojan://pass@l.example.com:443?type=grpc&serviceName=gs#TrojanGrpc', FEATURES, LOG), {
	transport: 'grpc', grpc_servicename: 'gs'
});

/* tuic */
expect_fields('tuic', parse_uri('tuic://tuic-uuid:pass@m.example.com:443?congestion_control=bbr&udp_relay_mode=native&alpn=h3&sni=m.example.com#Tuic', FEATURES, LOG), {
	label: 'Tuic', type: 'tuic', address: 'm.example.com', port: '443',
	uuid: 'tuic-uuid', password: 'pass', tuic_congestion_control: 'bbr',
	tuic_udp_relay_mode: 'native', tls: '1', tls_sni: 'm.example.com', tls_alpn: [ 'h3' ]
});

/* vless */
expect_fields('vless-reality-grpc', parse_uri('vless://vless-uuid@n.example.com:443?security=reality&pbk=PUBKEY&sid=abcd&fp=chrome&type=grpc&serviceName=gs&sni=n.example.com&flow=xtls-rprx-vision#Vless', FEATURES, LOG), {
	label: 'Vless', type: 'vless', address: 'n.example.com', port: '443', uuid: 'vless-uuid',
	transport: 'grpc', grpc_servicename: 'gs', tls: '1', tls_sni: 'n.example.com',
	tls_reality: '1', tls_reality_public_key: 'PUBKEY', tls_reality_short_id: 'abcd',
	tls_utls: 'chrome', vless_flow: 'xtls-rprx-vision'
});
expect_fields('vless-ws-early-data', parse_uri('vless://vless-uuid@o.example.com:443?security=tls&type=ws&host=o.example.com&path=%2Fws%3Fed%3D1024&sni=o.example.com&alpn=h2%2Chttp%2F1.1#VlessWs', FEATURES, LOG), {
	type: 'vless', transport: 'ws', ws_host: 'o.example.com', ws_path: '/ws',
	websocket_early_data: '1024', websocket_early_data_header: 'Sec-WebSocket-Protocol',
	tls: '1', tls_alpn: [ 'h2', 'http/1.1' ]
});

/* vmess */
expect_fields('vmess-ws', parse_uri('vmess://eyJ2IjoiMiIsInBzIjoiVk1lc3MiLCJhZGQiOiJwLmV4YW1wbGUuY29tIiwicG9ydCI6IjQ0MyIsImlkIjoiM2FmODg1NjEtOWM2OS00YjE5LThmN2UtZjA4ZDU4MGJjMzM5IiwiYWlkIjoiMCIsIm5ldCI6IndzIiwidHlwZSI6Im5vbmUiLCJob3N0IjoicC5leGFtcGxlLmNvbSIsInBhdGgiOiIvd3MiLCJ0bHMiOiJ0bHMiLCJzbmkiOiJwLmV4YW1wbGUuY29tIn0=', FEATURES, LOG), {
	label: 'VMess', type: 'vmess', address: 'p.example.com', port: '443',
	uuid: '3af88561-9c69-4b19-8f7e-f08d580bc339', vmess_alterid: '0', vmess_encrypt: 'auto',
	vmess_global_padding: '1', transport: 'ws', ws_host: 'p.example.com', ws_path: '/ws',
	tls: '1', tls_sni: 'p.example.com'
});

/* sip008 object */
expect_fields('sip008', parse_uri({
	nodetype: 'sip008', remarks: 'SIP008', server: 'q.example.com', server_port: 8388,
	method: 'aes-256-gcm', password: 'pw'
}, FEATURES, LOG), {
	label: 'SIP008', type: 'shadowsocks', address: 'q.example.com', port: 8388,
	shadowsocks_encrypt_method: 'aes-256-gcm', password: 'pw'
});

/* rejection paths */
expect_null('vless-kcp-unsupported', parse_uri('vless://u@r.example.com:443?type=kcp#Kcp', FEATURES, LOG));
expect_null('hysteria-without-quic', parse_uri('hysteria://s.example.com:443?auth=a#NoQuic', NO_QUIC, LOG));
expect_null('tuic-without-quic', parse_uri('tuic://u:p@s.example.com:443#NoQuic', NO_QUIC, LOG));
expect_null('invalid-port', parse_uri('vless://u@t.example.com:99999?security=tls#BadPort', FEATURES, LOG));
expect_null('unknown-scheme', parse_uri('unknown://u@t.example.com:443', FEATURES, LOG));

printf('%d checks, %d failures\n', checks, failures);
exit(failures === 0 ? 0 : 1);
