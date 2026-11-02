#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
set -eu
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
HELPER="$ROOT/root/usr/libexec/smartsafehub-device"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT INT TERM
# Execute the actual body builder in isolation: never contact a real cloud.
sed -n '/^build_sync_request() {/,/^}/p' "$HELPER" > "$TMP/helper.sh"
[ -s "$TMP/helper.sh" ] || { echo 'FAIL: sync builder is missing' >&2; exit 1; }
. "$TMP/helper.sh"
json_escape() { printf '%s' "$1"; }
SAFESHIELD_VERSION_FILE="$TMP/version"
RECOMMENDED_RECEIPT="$TMP/receipt"
OUT="$TMP/request.json"

assert_json() {
 python3 - "$OUT" "$1" "$2" <<'PY_JSON'
import json, sys
payload = json.load(open(sys.argv[1], encoding='utf-8'))
version = sys.argv[2]
ack = sys.argv[3]
if version == 'absent':
    assert 'safeshield_version' not in payload, payload
else:
    assert payload['safeshield_version'] == version, payload
if ack == 'present':
    assert payload['recommended_rules_ack'] == {'revision': 'a' * 64, 'status': 'confirmed'}, payload
else:
    assert 'recommended_rules_ack' not in payload, payload
PY_JSON
}
printf '0.3.25-r1\n' > "$SAFESHIELD_VERSION_FILE"
build_sync_request "$OUT"
assert_json 0.3.25-r1 absent
printf '{"revision":"%s","status":"confirmed"}\n' "$(printf '%064d' 0 | tr 0 a)" > "$RECOMMENDED_RECEIPT"
build_sync_request "$OUT"
assert_json 0.3.25-r1 present
rm -f "$SAFESHIELD_VERSION_FILE"
build_sync_request "$OUT"
assert_json absent present
rm -f "$RECOMMENDED_RECEIPT"
build_sync_request "$OUT"
assert_json absent absent
printf 'invalid version\n' > "$SAFESHIELD_VERSION_FILE"
build_sync_request "$OUT"
assert_json absent absent
printf 'PASS: device sync version and receipt payloads\n'
