#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
set -eu
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
HELPER="$ROOT/root/usr/libexec/smartsafehub-apps-metrics"
MANAGER="$ROOT/root/usr/libexec/smartsafehub-apps-manager"
DEVICE="$ROOT/root/usr/libexec/smartsafehub-device"
RESTORE="$ROOT/root/usr/libexec/smartsafehub-apps-restore"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
fail() { echo "FAIL: $*" >&2; exit 1; }
mkdir -p "$TMP/bin" "$TMP/pending"
cat > "$TMP/bin/jsonfilter" <<'SH2'
#!/bin/sh
exec python3 - "$@" <<'PY'
import json, sys
args = sys.argv[1:]
obj = json.load(open(args[args.index('-i') + 1]))
key = args[args.index('-e') + 1].removeprefix('@.')
if key in obj: print(obj[key])
PY
SH2
cat > "$TMP/bin/uclient-fetch" <<'SH2'
#!/bin/sh
[ "$APPS_METRICS_TEST_MODE" = fail ] && exit 1
while [ "$#" -gt 0 ]; do
 case "$1" in
  -O) out="$2"; shift 2;;
  --post-file=*) body="${1#--post-file=}"; shift;;
  --header=Authorization:*) auth="$1"; shift;;
  *) shift;;
 esac
done
[ -n "${auth:-}" ] && [ -n "${body:-}" ] || exit 1
cp "$body" "$APPS_METRICS_TEST_LAST_BODY"
printf '{"status":"%s"}
' "$APPS_METRICS_TEST_MODE" > "$out"
SH2
chmod +x "$TMP/bin/"*
export SMARTSAFEHUB_APPS_METRICS_DIR="$TMP/pending"
export SMARTSAFEHUB_APPS_METRICS_CREDENTIAL="$TMP/credential.json"
export SMARTSAFEHUB_APPS_METRICS_FETCH_BIN="$TMP/bin/uclient-fetch"
export SMARTSAFEHUB_APPS_JSONFILTER_BIN="$TMP/bin/jsonfilter"
export APPS_METRICS_TEST_MODE=fail
export APPS_METRICS_TEST_LAST_BODY="$TMP/last-body.json"
EVENT=1793170000-4321-1234567890abcdef
"$HELPER" enqueue retro-arcade 1.0.0-r1 "$EVENT"
[ "$(find "$TMP/pending" -name '*.json' | wc -l | tr -d ' ')" -eq 1 ] || fail 'receipt not queued'
"$HELPER" enqueue retro-arcade 1.0.0-r1 "$EVENT"
[ "$(find "$TMP/pending" -name '*.json' | wc -l | tr -d ' ')" -eq 1 ] || fail 'same event duplicated'
"$HELPER" enqueue '../../etc/passwd' x "$EVENT" >/dev/null 2>&1 && fail 'unsafe app ID accepted'
"$HELPER" enqueue retro-arcade 1.0.0-r1 "$EVENT" invalid >/dev/null 2>&1 && fail 'invalid event kind accepted'
"$HELPER" enqueue retro-arcade 1.0.0-r1 "$EVENT" update extra >/dev/null 2>&1 && fail 'extra event fields accepted'
"$HELPER" enqueue retro-arcade x 'bad/id' >/dev/null 2>&1 && fail 'unsafe event accepted'
"$HELPER" flush
[ -f "$TMP/pending/$EVENT.json" ] || fail 'unregistered device lost receipt'
printf '{"token":"ssh_dev_%064d"}
' 0 > "$TMP/credential.json"
"$HELPER" flush >/dev/null 2>&1 && fail 'failed upload returned success'
[ -f "$TMP/pending/$EVENT.json" ] || fail 'offline request lost receipt'
export APPS_METRICS_TEST_MODE=recorded
"$HELPER" flush
[ ! -f "$TMP/pending/$EVENT.json" ] || fail 'acknowledged event not cleared'
grep -Fq '"app_id":"retro-arcade"' "$TMP/last-body.json" || fail 'app ID lost'
grep -Fq '"kind":"install"' "$TMP/last-body.json" || fail 'legacy install kind lost'
# The same device can report a newer app release as an update; retry must
# preserve the kind and event ID without changing the install counter.
UPDATE_EVENT=1793170001-4322-abcdef1234567890
"$HELPER" enqueue retro-arcade 1.1.0-r5 "$UPDATE_EVENT" update
[ "$(find "$TMP/pending" -name '*.json' | wc -l | tr -d ' ')" -eq 1 ] || fail 'update receipt not queued'
grep -Fq '"kind":"update"' "$TMP/pending/$UPDATE_EVENT.json" || fail 'update recorded as install'
export APPS_METRICS_TEST_MODE=fail
"$HELPER" flush >/dev/null 2>&1 && fail 'failed update upload returned success'
[ -f "$TMP/pending/$UPDATE_EVENT.json" ] || fail 'update receipt lost on failure'
export APPS_METRICS_TEST_MODE=recorded
"$HELPER" flush
[ ! -f "$TMP/pending/$UPDATE_EVENT.json" ] || fail 'updated receipt not acknowledged'
grep -Fq '"kind":"update"' "$TMP/last-body.json" || fail 'update kind lost over HTTP'
"$HELPER" enqueue retro-arcade 1.0.0-r1 "$EVENT"
export APPS_METRICS_TEST_MODE=duplicate
"$HELPER" flush
[ ! -f "$TMP/pending/$EVENT.json" ] || fail 'deduplicated event not cleared'
! grep -Eiq '(credential|mac|ip_address|device_uuid|user)' "$TMP/last-body.json" || fail 'private metadata uploaded'
grep -Fq '"$METRICS" enqueue "$app" "$version" "$operation_id" "$action"' "$MANAGER" || fail 'successful installation/update not queued'
grep -Fq '[ "$source" = user ]' "$MANAGER" || fail 'restores are included in download count'
grep -Fq 'start install "$id" restore' "$RESTORE" || fail 'restore source missing'
grep -Fq '"$APPS_METRICS" flush' "$DEVICE" || fail 'background queue retry missing'
grep -Fxq '/etc/smartsafehub/apps-metrics-pending/' "$ROOT/root/lib/upgrade/keep.d/smartsafehub-apps" || fail 'sysupgrade lost pending receipts'
sh -n "$HELPER" "$MANAGER" "$DEVICE" "$RESTORE" || fail 'shell syntax invalid'
printf 'PASS: authenticated Apps install/update receipt queue, retry, dedup and restore exclusion
'
