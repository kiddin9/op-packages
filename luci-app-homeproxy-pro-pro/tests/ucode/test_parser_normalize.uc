/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * PR-02 (Parser Normalization): the parser writes a flat UCI-key
 * dict, normalize() turns it into the canonical Node shape the
 * Adapter reads.  This test pins the contract so the mapping table
 * (parser/mapping.uc), the Loader's PROTOCOL_OPTIONS (now derived
 * from it) and the parser's normalize() cannot drift apart.
 *
 * Run through tests/ucode/run.sh's parser tree staging (same as
 * test_parse_uri.uc): the staged work dir has the production
 * parser/ tree plus the homeproxy mock.
 */

'use strict';

import { normalize } from 'parser/normalize.uc';

let checks = 0, failures = 0;
function expect(name, got, want) {
	checks++;
	if (got !== want) {
		printf('FAIL %s: got %J want %J\n', name, got, want);
		failures++;
	}
}
function expect_keys(name, got, want) {
	checks++;
	const keys_got = sort(keys(got));
	const keys_want = sort(want);
	const same = length(keys_got) === length(keys_want);
	if (!same || filter(keys_got, (k, i) => k !== keys_want[i]).length) {
		printf('FAIL %s: keys got %J want %J\n', name, keys_got, keys_want);
		failures++;
	}
}

/* --- null in -> null out -------------------------------------------- */
expect('normalize(null)', normalize(null), null);

/* --- shadowsocks: tls_sni + shadowsocks_* UCI keys -> canonical Node */
const ss_flat = {
	label: 'ss1',
	type: 'shadowsocks',
	address: '1.2.3.4',
	port: '8388',
	password: 'pw',
	shadowsocks_encrypt_method: 'aes-256-gcm',
	shadowsocks_plugin: 'obfs-local',
	shadowsocks_plugin_opts: 'obfs=http;obfs-host=bing.com',
	udp_over_tcp: '1',
	udp_over_tcp_version: '2'
};
const ss_node = normalize(ss_flat);
expect('ss.type', ss_node.type, 'shadowsocks');
expect('ss.address', ss_node.address, '1.2.3.4');
expect('ss.port', ss_node.port, '8388');
expect('ss.credentials.password', ss_node.credentials.password, 'pw');
expect('ss.credentials.method', ss_node.credentials.method, 'aes-256-gcm');
expect('ss.protocol_options.plugin', ss_node.protocol_options.plugin, 'obfs-local');
expect('ss.protocol_options.plugin_opts', ss_node.protocol_options.plugin_opts, 'obfs=http;obfs-host=bing.com');
expect('ss.protocol_options.udp_over_tcp', ss_node.protocol_options.udp_over_tcp, '1');
expect('ss.protocol_options.udp_over_tcp_version', ss_node.protocol_options.udp_over_tcp_version, '2');
/* shadowsocks has no transport, multiplex, tls enabled: */
expect('ss.transport.type', ss_node.transport.type, null);

/* --- vless: flow + packet_encoding -> canonical; tls shape filled */
const vless_flat = {
	label: 'vl1',
	type: 'vless',
	address: '5.6.7.8',
	port: '443',
	uuid: 'uuid-x',
	transport: 'ws',
	tls: '1',
	tls_sni: 'vl.example.com',
	tls_alpn: ['h2', 'http/1.1'],
	tls_reality: '1',
	tls_reality_public_key: 'PUBKEY',
	tls_reality_short_id: 'abcd',
	tls_utls: 'chrome',
	vless_flow: 'xtls-rprx-vision',
	packet_encoding: 'xudp',
	ws_host: 'ws.example.com',
	ws_path: '/ws'
};
const vless_node = normalize(vless_flat);
expect('vless.type', vless_node.type, 'vless');
expect('vless.credentials.uuid', vless_node.credentials.uuid, 'uuid-x');
expect('vless.protocol_options.flow', vless_node.protocol_options.flow, 'xtls-rprx-vision');
expect('vless.protocol_options.packet_encoding', vless_node.protocol_options.packet_encoding, 'xudp');
expect('vless.tls.enabled', vless_node.tls.enabled, '1');
expect('vless.tls.server_name', vless_node.tls.server_name, 'vl.example.com');
expect('vless.tls.reality.enabled', vless_node.tls.reality.enabled, '1');
expect('vless.tls.reality.public_key', vless_node.tls.reality.public_key, 'PUBKEY');
expect('vless.tls.utls.fingerprint', vless_node.tls.utls.fingerprint, 'chrome');
expect('vless.transport.type', vless_node.transport.type, 'ws');
expect('vless.transport.path', vless_node.transport.path, '/ws');
/* A websocket transport keeps its host in `headers.Host`, not `host`
 * (only the http / httpupgrade transports use `host`), matching the
 * Loader's load_transport() shape and buildTransportObject()'s
 * expectation. */
expect('vless.transport.host', vless_node.transport.host, null);
expect('vless.transport.headers', vless_node.transport.headers?.Host, 'ws.example.com');

/* --- hysteria2: hy_* UCI -> protocol_options.hop_interval / obfs_type */
const hy2_flat = {
	label: 'hy2',
	type: 'hysteria2',
	address: 'a.b.c',
	port: '443',
	password: 'pw',
	hysteria_obfs_type: 'salamander',
	hysteria_obfs_password: 'obfspw',
	hysteria_up_mbps: '100',
	hysteria_hop_interval: '30',
	tls: '1',
	tls_sni: 'hy2.example.com'
};
const hy2_node = normalize(hy2_flat);
expect('hy2.protocol_options.obfs_type', hy2_node.protocol_options.obfs_type, 'salamander');
expect('hy2.protocol_options.obfs_password', hy2_node.protocol_options.obfs_password, 'obfspw');
expect('hy2.protocol_options.up_mbps', hy2_node.protocol_options.up_mbps, '100');
expect('hy2.protocol_options.hop_interval', hy2_node.protocol_options.hop_interval, '30');
/* protocol_options must NOT carry over fields that are not in PROTOCOL_TO_UCI;
 * the parser may write extra keys (e.g. from the form) that should be
 * dropped at the canonical boundary. */
expect_keys('hy2.protocol_options keys',
	hy2_node.protocol_options,
	['obfs_type', 'obfs_password', 'up_mbps', 'hop_interval']);

/* --- direct: protocol_options carries override_address/port */
const direct_flat = {
	label: 'direct1',
	type: 'direct',
	address: '10.0.0.1',
	port: '80',
	override_address: '1.0.0.1',
	override_port: '443'
};
const direct_node = normalize(direct_flat);
expect('direct.protocol_options.override_address', direct_node.protocol_options.override_address, '1.0.0.1');
expect('direct.protocol_options.override_port', direct_node.protocol_options.override_port, '443');
/* direct has no credentials: */
expect_keys('direct.credentials keys', direct_node.credentials, []);

/* --- empty/null UCI values are dropped from protocol_options (the
 * Adapter's removeBlankAttrs would drop them again at emit time, but
 * keeping normalize strict means a stale `flow: ''` from a recent
 * share link does not appear in REQUIRED_CREDENTIALS or similar
 * checks that walk the canonical shape). */
const empty_flat = {
	type: 'vless',
	address: 'a',
	port: '1',
	uuid: 'u',
	vless_flow: '',
	packet_encoding: null
};
const empty_node = normalize(empty_flat);
expect_keys('empty.protocol_options keys', empty_node.protocol_options, []);

printf('%d checks, %d failures\n', checks, failures);
exit(failures === 0 ? 0 : 1);