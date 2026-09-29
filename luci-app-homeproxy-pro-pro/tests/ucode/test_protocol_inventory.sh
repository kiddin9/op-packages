#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
#
# Protocol inventory invariant.
#
# The protocol surface is spread over several places that must agree.  PR-02
# moved two of them, so the paths here are the current ones:
#
#   parser/uri.uc       scheme -> type            (what a share link becomes)
#   model.uc            CREDENTIALS               (which UCI option holds each credential)
#   parser/mapping.uc   PROTOCOL_TO_UCI           (which UCI option holds each protocol option;
#                                                  the Loader imports it as PROTOCOL_OPTIONS)
#   adapter.uc          REQUIRED_CREDENTIALS      (what a buildable node needs)
#   adapter.uc          OPTION_FIELDS             (what becomes a sing-box field)
#   snapshots/generator/outbounds.json            (what is actually emitted)
#
# The frontend has a matching check of its own,
# tests/frontend-protocol-inventory.js: the browser's protocol list must be a
# subset of what the backend models, which is the direction this shape test
# cannot see.
#
# Adding a protocol to one of them and forgetting another is the failure mode
# this test exists for: WireGuard shipped with no loader row (so the endpoint
# builder read fields that did not exist) and SSH shipped with no loader row
# and the wrong credential option name.  Neither failed any test.
#
# Usage: sh tests/ucode/test_protocol_inventory.sh <repo-root> [work-dir]

ROOT="${1:-.}"
WORK="${2:-/tmp/hp-inventory-test}"

ROOT="$(cd "$ROOT" && pwd)"
SCRIPTS="$ROOT/root/etc/homeproxy/scripts"
SNAPSHOT="$ROOT/tests/snapshots/generator/outbounds.json"
FAILED=0

rm -rf "$WORK"
mkdir -p "$WORK/parser" "$WORK/inventory/config"

# --- stage 1: what does the parser produce? ------------------------------
# PR-02 moved the parsers to scripts/parser/{uri,protocols,validator,
# normalize,mapping}.uc; stage the whole tree plus the homeproxy mock
# so the share-link importer can find every import it needs.
cp "$ROOT/tests/ucode/mocks/homeproxy.uc" "$WORK/parser/homeproxy.uc"
# The test module imports 'parser/uri.uc', which resolves relative to
# the -L search root, so the parser tree must be staged as a `parser/`
# subdirectory of that root (not flattened into it).
mkdir -p "$WORK/parser/parser"
cp "$SCRIPTS/parser/"*.uc "$WORK/parser/parser/"
# The Loader imports PROTOCOL_OPTIONS from '../parser/mapping.uc'.
# After staging, the loader lives at $WORK/inventory/config/loader.uc,
# so the parser tree must also live at $WORK/inventory/parser/ for the
# import to resolve.  Mirror it once now so inventory.uc below can use
# the loader as-is.
mkdir -p "$WORK/inventory/parser"
cp "$SCRIPTS/parser/"*.uc "$WORK/inventory/parser/"

cat > "$WORK/parser/types.uc" <<'EOF'
'use strict';

import { parse_uri } from 'parser/uri.uc';

const FEATURES = { with_quic: true, with_utls: true };
const LOG = function() {};

/* One sample per scheme the parser accepts.  The values are the same ones
 * test_parse_uri.uc asserts on, so this list stays honest. */
const SAMPLES = [
	'anytls://secret@a.example.com:443?sni=a.example.com#AnyTLS',
	'https://user:pass@b.example.com:8443#HTTPS',
	'http://c.example.com:8080#HTTP',
	'hysteria://d.example.com:36712?auth=pass&peer=d.example.com&protocol=udp#Hy1',
	'hysteria2://pass@e.example.com:443?sni=e.example.com&obfs=salamander&obfs-password=op#Hy2',
	'hy2://pass@e.example.com:443#Hy2Alias',
	'snell://f.example.com:443?psk=pskvalue&version=4&obfs=http&obfs-host=bing.com#Snell',
	'socks5://user:pass@g.example.com:1080#Socks',
	'ss://YWVzLTI1Ni1nY206cGFzc3dvcmQ=@i.example.com:8388#SS',
	'trojan://pass@l.example.com:443?type=grpc&serviceName=gs&sni=l.example.com#Trojan',
	'tuic://tuic-uuid:pass@m.example.com:443?congestion_control=bbr&sni=m.example.com#Tuic',
	'vless://vless-uuid@n.example.com:443?security=reality&pbk=PUBKEY&sid=abcd&type=grpc&serviceName=gs&sni=n.example.com#Vless',
	'vmess://eyJ2IjoiMiIsInBzIjoiVk1lc3MiLCJhZGQiOiJwLmV4YW1wbGUuY29tIiwicG9ydCI6IjQ0MyIsImlkIjoiM2FmODg1NjEtOWM2OS00YjE5LThmN2UtZjA4ZDU4MGJjMzM5IiwiYWlkIjoiMCIsIm5ldCI6IndzIiwidHlwZSI6Im5vbmUiLCJob3N0IjoicC5leGFtcGxlLmNvbSIsInBhdGgiOiIvd3MiLCJ0bHMiOiJ0bHMiLCJzbmkiOiJwLmV4YW1wbGUuY29tIn0='
];

let types = [];
for (let uri in SAMPLES) {
	const config = parse_uri(uri, FEATURES, LOG);
	if (config)
		push(types, config.type);
}

printf('%.J\n', types);
EOF

if ! ( cd "$WORK/parser" && ucode -L "$WORK/parser" types.uc > "$WORK/parser/types.json" 2> "$WORK/parser/types.err" ); then
	echo "FAIL: could not run the share-link parsers"
	head -8 "$WORK/parser/types.err"
	exit 1
fi

# --- stage 2: do the tables and the golden snapshot agree? ---------------
VALIDATE_DATA="${HP_VALIDATE_DATA:-/sbin/validate_data}"
sed -e "s#/sbin/validate_data#${VALIDATE_DATA}#" \
	"$SCRIPTS/homeproxy.uc" > "$WORK/inventory/homeproxy.uc"
cp "$SCRIPTS/config/loader.uc"  "$WORK/inventory/config/"
cp "$SCRIPTS/config/model.uc"   "$WORK/inventory/config/"
cp "$SCRIPTS/config/adapter.uc" "$WORK/inventory/config/"
cp "$WORK/parser/types.json" "$WORK/inventory/parser-types.json"
cp "$SNAPSHOT" "$WORK/inventory/outbounds.json"

cat > "$WORK/inventory/inventory.uc" <<'EOF'
'use strict';

import { readfile } from 'fs';

import {
	CREDENTIALS, INBOUND_CREDENTIALS, INBOUND_OPTIONS
} from './config/model.uc';
/* PR-02 moved the client option table to parser/mapping.uc; the Loader
 * imports it from there as PROTOCOL_OPTIONS. */
import { PROTOCOL_TO_UCI as PROTOCOL_OPTIONS } from './parser/mapping.uc';
import { OPTION_FIELDS, REQUIRED_CREDENTIALS } from './config/adapter.uc';

const parser_types = json(readfile('parser-types.json')) || [];
const golden = json(readfile('outbounds.json')) || {};

/* Types the adapter turns into a sing-box *outbound*. */
const emitted_types = [];
for (let id in keys(golden))
	push(emitted_types, golden[id].type);

/* Protocols that are modelled but deliberately produce something other than
 * an outbound: WireGuard becomes an endpoint (generate_endpoint()), and is
 * covered by tests/fixtures/generators/wireguard.uci instead of the golden
 * snapshot. */
const ENDPOINT_TYPES = ['wireguard'];

let failures = 0, checks = 0;

function check(what, ok, detail) {
	checks++;
	if (ok)
		return;
	printf('FAIL %s%s\n', what, detail ? ': ' + detail : '');
	failures++;
}

function contains(list, value) {
	return index(list, value) !== -1;
}

/* 1. Every protocol any layer names must exist in the loader's option table;
 *    that table is what makes the protocol reachable from UCI at all. */
const LAYERS = {
	'OPTION_FIELDS': keys(OPTION_FIELDS),
	'REQUIRED_CREDENTIALS': keys(REQUIRED_CREDENTIALS),
	'CREDENTIALS': keys(CREDENTIALS),
	'ENDPOINT_TYPES': ENDPOINT_TYPES
};

for (let layer in keys(LAYERS)) {
	for (let name in LAYERS[layer]) {
		check(sprintf('%s.%s is modelled by loader PROTOCOL_OPTIONS', layer, name),
			name in PROTOCOL_OPTIONS);
	}
}

/* 2. Every type the parser can produce must be fully modelled: the loader
 *    must know its options and the adapter must be able to emit it. */
/* Non-empty guard: with an empty parser-types.json every check below would
 * vanish and the section would "pass" by having nothing to check - which is
 * how a parser that stopped producing types could go unnoticed. */
check('the parser produced at least one type to cross-check', length(parser_types) > 0);

for (let type_name in parser_types) {
	check(sprintf("parser type '%s' is in PROTOCOL_OPTIONS", type_name),
		type_name in PROTOCOL_OPTIONS);
	check(sprintf("parser type '%s' is in OPTION_FIELDS", type_name),
		type_name in OPTION_FIELDS);
	check(sprintf("parser type '%s' has a golden outbound", type_name),
		contains(emitted_types, type_name));
}

/* 3. Every protocol the adapter can emit, and every protocol it requires
 *    credentials for, must be pinned by the golden snapshot - otherwise a
 *    field regression in that protocol is invisible. */
for (let type_name in keys(OPTION_FIELDS)) {
	check(sprintf("OPTION_FIELDS type '%s' has a golden outbound", type_name),
		contains(emitted_types, type_name));
}
for (let type_name in keys(REQUIRED_CREDENTIALS)) {
	if (contains(ENDPOINT_TYPES, type_name))
		continue;
	check(sprintf("REQUIRED_CREDENTIALS type '%s' has a golden outbound", type_name),
		contains(emitted_types, type_name));
}

/* 4. The server side of the surface must be modelled too. Every protocol
 *    with a per-protocol option row must also have a credential row, or
 *    the Loader reads options for a protocol whose credentials it never
 *    loads. (The reverse does not hold: trojan / shadowtls / http /
 *    mixed / naive / socks have credentials and no per-protocol
 *    options.) */
for (let name in keys(INBOUND_OPTIONS)) {
	check(sprintf("INBOUND_OPTIONS.%s has an INBOUND_CREDENTIALS row", name),
		name in INBOUND_CREDENTIALS);
}

/* 5. The golden snapshot must not carry a protocol nobody models. */
for (let type_name in emitted_types) {
	check(sprintf("golden type '%s' is in PROTOCOL_OPTIONS", type_name),
		type_name in PROTOCOL_OPTIONS);
}

printf('%d checks, %d failures\n', checks, failures);
exit(failures ? 1 : 0);
EOF

if ( cd "$WORK/inventory" && ucode -L "$WORK/inventory" inventory.uc ); then
	echo "PASS: protocol inventory is consistent"
else
	echo "FAIL: protocol inventory is inconsistent"
	FAILED=1
fi

exit $FAILED
