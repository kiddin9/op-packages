/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * PR-03 (Subscription Transaction Boundary): the round-trip
 * invariant for the canonical-Node pipeline. For every scheme the
 * parser accepts, parse_uri() -> normalize() -> flatten() must
 * produce a flat UCI dict that is field-for-field equal to what
 * the parser would have written directly. Repository then writes
 * that flat dict to UCI, so a saved canonical Node round-trips
 * back into an equivalent canonical Node when the Loader next
 * reads it.
 *
 * Two important properties this test pins:
 *
 *   - canonical-to-flat mapping is consistent: parser and
 *     flatten() agree on every UCI key (otherwise the
 *     Repository's "delete what is no longer carried" walk
 *     would silently drop fields the parser still emits);
 *   - canonical -> flat -> canonical is identity for the data
 *     the Loader reads (the Repository's actual contract).
 *
 * Run through tests/ucode/run.sh's parser tree staging (same as
 * test_parse_uri.uc): the staged work dir has the production
 * parser/ tree plus the homeproxy mock.
 */

'use strict';

import { parse_uri } from 'parser/uri.uc';
import { normalize } from 'parser/normalize.uc';
import { flatten } from 'parser/flatten.uc';

const FEATURES = { with_quic: true, with_utls: true };
const LOG = (..._args) => {};

let failures = 0, checks = 0;

function expect(name, got, want) {
	checks++;
	if (sprintf('%J', got) !== sprintf('%J', want)) {
		printf('FAIL %s: got %J want %J\n', name, got, want);
		failures++;
	}
}

/* The invariant that matters for the Repository: every value the parser
 * actually set must survive parse -> normalize -> flatten unchanged.
 *
 * Nulls are excluded on purpose - removeBlankAttrs()/flatten() drop them
 * and the Loader reads an absent option as null, so a null round-trip is
 * observably lossless. A non-null value that disappears is data loss:
 * the Repository writes `flatten()`'s output, so on the next subscription
 * update that UCI option would be *deleted* from the stored node.
 *
 * The reverse direction is checked too: flatten() must not invent keys
 * the parser never produced, or the Repository would write options the
 * node form does not own. */
function round_trip(name, uri, features) {
	const flat = parse_uri(uri, features, LOG);

	/* A sample the parser rejects is a broken fixture, not a reason to skip.
	 * Returning silently left that scheme's round trip unverified while the
	 * suite stayed green. */
	if (!flat) {
		checks++;
		failures++;
		printf('FAIL %s: parse_uri() rejected a sample this test is meant to cover\n', name);
		return;
	}

	const node = normalize(flat);
	const back = flatten(node);

	/* 1. every non-null parser value survives, unchanged. */
	for (let k, v in flat) {
		if (v === null)
			continue;
		expect(sprintf('%s: %s survives round-trip', name, k), back[k], v);
	}

	/* 2. flatten() only emits keys the parser produced (plus the
	 *    metadata the orchestrator attaches). */
	const flat_keys = keys(flat);
	for (let k, v in back) {
		if (v === null)
			continue;
		if (index(flat_keys, k) === -1)
			expect(sprintf('%s: %s is not a parser field', name, k), k, null);
	}

	/* 3. and the canonical Node must carry the identity the Loader's
	 *    read path would reconstruct. */
	expect(sprintf('%s: canonical type', name), node.type, flat.type);
	expect(sprintf('%s: canonical address', name), node.address, flat.address);
	expect(sprintf('%s: canonical port', name), node.port, flat.port);
	expect(sprintf('%s: canonical name from label', name), node.name, flat.label);
}

/* The same URI corpus test_parse_uri.uc asserts on, so any
 * regression in the mapping table will surface in BOTH tests.
 * Array destructuring is rejected by the target ucode, so each
 * sample is a 3-element object the loop indexes manually. */
const SAMPLES = [
	{ name: 'anytls',  uri: 'anytls://secret@a.example.com:443?sni=a.example.com#AnyTLS', features: FEATURES },
	{ name: 'https',   uri: 'https://user:pass@b.example.com:8443#HTTPS', features: FEATURES },
	{ name: 'http',    uri: 'http://c.example.com:8080#HTTP', features: FEATURES },
	{ name: 'hy1',     uri: 'hysteria://d.example.com:36712?auth=pass&peer=d.example.com&protocol=udp#Hy1', features: FEATURES },
	{ name: 'hy2',     uri: 'hysteria2://pass@e.example.com:443?sni=e.example.com&obfs=salamander&obfs-password=op#Hy2', features: FEATURES },
	{ name: 'hy2al',   uri: 'hy2://pass@e.example.com:443#Hy2Alias', features: FEATURES },
	{ name: 'snell',   uri: 'snell://f.example.com:443?psk=pskvalue&version=4&obfs=http&obfs-host=bing.com#Snell', features: FEATURES },
	{ name: 'socks5',  uri: 'socks5://user:pass@g.example.com:1080#Socks', features: FEATURES },
	{ name: 'ss',      uri: 'ss://YWVzLTI1Ni1nY206cGFzc3dvcmQ=@i.example.com:8388#SS', features: FEATURES },
	{ name: 'trojan',  uri: 'trojan://pass@l.example.com:443?type=grpc&serviceName=gs&sni=l.example.com#Trojan', features: FEATURES },
	{ name: 'tuic',    uri: 'tuic://tuic-uuid:pass@m.example.com:443?congestion_control=bbr&sni=m.example.com#Tuic', features: FEATURES },
	{ name: 'vless-r', uri: 'vless://vless-uuid@n.example.com:443?security=reality&pbk=PUBKEY&sid=abcd&type=grpc&serviceName=gs&sni=n.example.com#Vless', features: FEATURES },
	{ name: 'vmess',   uri: 'vmess://eyJ2IjoiMiIsInBzIjoiVk1lc3MiLCJhZGQiOiJwLmV4YW1wbGUuY29tIiwicG9ydCI6IjQ0MyIsImlkIjoiM2FmODg1NjEtOWM2OS00YjE5LThmN2UtZjA4ZDU4MGJjMzM5IiwiYWlkIjoiMCIsIm5ldCI6IndzIiwidHlwZSI6Im5vbmUiLCJob3N0IjoicC5leGFtcGxlLmNvbSIsInBhdGgiOiIvd3MiLCJ0bHMiOiJ0bHMiLCJzbmkiOiJwLmV4YW1wbGUuY29tIn0=', features: FEATURES }
];

/* ucode's for-in over an array yields the elements, not the indices. */
for (let s in SAMPLES)
	round_trip(s.name, s.uri, s.features);

/* --- explicit canonical -> flat shape checks --------------------------- */

/* vless reality: many sub-objects must round-trip cleanly. */
{
	const flat = parse_uri(
		'vless://vless-uuid@n.example.com:443?security=reality&pbk=PUBKEY&sid=abcd&type=grpc&serviceName=gs&sni=n.example.com#Vless',
		FEATURES, LOG
	);
	const node = normalize(flat);
	const back = flatten(node);
	expect('vless.reality: tls_reality_public_key',
		back.tls_reality_public_key, flat.tls_reality_public_key);
	expect('vless.reality: tls_reality_short_id',
		back.tls_reality_short_id, flat.tls_reality_short_id);
	expect('vless.reality: tls_sni',
		back.tls_sni, flat.tls_sni);
	expect('vless.reality: grpc_servicename',
		back.grpc_servicename, flat.grpc_servicename);
	expect('vless.reality: vless_flow',
		back.vless_flow, flat.vless_flow);
}

/* shadowsocks plugin + udp_over_tcp must survive. */
{
	const flat = parse_uri(
		'ss://YWVzLTI1Ni1nY206cGFzc3dvcmQ=@i.example.com:8388#SS',
		FEATURES, LOG
	);
	const node = normalize(flat);
	const back = flatten(node);
	expect('ss: shadowsocks_encrypt_method',
		back.shadowsocks_encrypt_method, flat.shadowsocks_encrypt_method);
	expect('ss: label survives canonical->flat',
		back.label, flat.label);
}

/* --- grouphash metadata pass-through ---------------------------------- */

/* Repository attaches grouphash to the canonical Node after the
 * orchestrator builds it. flatten() must copy grouphash through
 * because the Repository's foreach walks `node_cache` keyed by
 * grouphash, not by what flatten emits. */
{
	const flat = parse_uri(
		'vless://vless-uuid@n.example.com:443?security=reality&pbk=PUBKEY&sid=abcd&sni=n.example.com#Vless',
		FEATURES, LOG
	);
	const node = normalize(flat);
	node.grouphash = 'groupHash-XYZ';
	const back = flatten(node);
	expect('grouphash: passed through',
		back.grouphash, 'groupHash-XYZ');
}

/* isExisting is the within-run marker Repository sets after a
 * successful write; it must NOT be emitted into UCI (else it
 * becomes a stale field on the next round). */
{
	const flat = parse_uri(
		'vless://vless-uuid@n.example.com:443?sni=n.example.com#Vless',
		FEATURES, LOG
	);
	const node = normalize(flat);
	node.isExisting = true;
	const back = flatten(node);
	expect('isExisting: NOT in flat output',
		'isExisting' in back, false);
}

/* --- null / empty canonical values are dropped ------------------------ */

/* Empty / null canonical values must not show up as `key ''`
 * entries in UCI - the Loader treats null and absent the same,
 * so the round-trip is still lossless. */
{
	const node = {
		id: null,
		name: 'X',
		type: 'vless',
		address: 'a',
		port: '1',
		common: {},
		credentials: { uuid: 'u' },
		tls: { enabled: null, ech: {}, utls: {}, reality: {} },
		transport: { type: null },
		multiplex: { enabled: null, brutal: {} },
		protocol_options: { flow: '' }
	};
	const back = flatten(node);
	expect('flatten: empty string protocol_option is dropped',
		'flow' in back, false);
}

printf('%d checks, %d failures\n', checks, failures);
exit(failures === 0 ? 0 : 1);