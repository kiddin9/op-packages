#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
set -eu
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
HELPER="$ROOT/root/usr/libexec/smartsafehub-rpc-jobs"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
mkdir -p "$TMP/run"
# Simulate start-stop-daemon, keeping the real job-launch argument contract.
cat > "$TMP/daemon" <<'SH'
#!/bin/sh
while [ "$#" -gt 0 ]; do
 case "$1" in
  -S|-b) shift;;
  -x) program="$2"; shift 2;;
  --) shift; break;;
  *) exit 2;;
 esac
done
"$program" "$@" >/dev/null 2>&1 &
exit 0
SH
cat > "$TMP/catalog" <<'SH'
#!/bin/sh
printf 'fetch\n' >> "$RPC_TEST_COUNT"
sleep 0.3
[ ! -e "$RPC_TEST_FAIL" ] || exit 1
printf '{"schema":1}\n' > "$RPC_TEST_CACHE"
SH
cat > "$TMP/manager" <<'SH'
#!/bin/sh
printf '%s\n' "$1" >> "$RPC_TEST_COUNT"
sleep 0.3
SH
cat > "$TMP/device" <<'SH'
#!/bin/sh
printf '%s:%s\n' "$1" "${2:-}" >> "$RPC_TEST_COUNT"
sleep 0.3
[ ! -e "$RPC_TEST_FAIL" ]
SH
chmod +x "$TMP/daemon" "$TMP/catalog" "$TMP/manager" "$TMP/device"
export SMARTSAFEHUB_RPC_JOBS_RUNTIME="$TMP/run"
export SMARTSAFEHUB_RPC_JOBS_SELF="$HELPER"
export SMARTSAFEHUB_RPC_JOBS_DAEMON="$TMP/daemon"
export SMARTSAFEHUB_RPC_JOBS_CATALOG="$TMP/catalog"
export SMARTSAFEHUB_RPC_JOBS_MANAGER="$TMP/manager"
export SMARTSAFEHUB_RPC_JOBS_DEVICE="$TMP/device"
export RPC_TEST_COUNT="$TMP/count"
export RPC_TEST_FAIL="$TMP/fail"
export RPC_TEST_CACHE="$TMP/apps-catalog.json"
export SMARTSAFEHUB_RPC_JOBS_CATALOG_CACHE="$RPC_TEST_CACHE"
export SMARTSAFEHUB_APPS_ROM_METADATA="$TMP/rom-firmware.json"
export SMARTSAFEHUB_APPS_METADATA="$TMP/overlay-firmware.json"
printf '{"device_code":"iptime-ax3000sm","build_id":"build-A","channel":"stable"}\n' > "$SMARTSAFEHUB_APPS_METADATA"

count_fetches() { grep -c '^fetch$' "$TMP/count"; }
backdate_catalog() {
 sed "s/^updated$(printf '\t')[0-9][0-9]*/updated$(printf '\t')$1/" \
  "$TMP/run/catalog.state" > "$TMP/old-state"
 mv "$TMP/old-state" "$TMP/run/catalog.state"
}
wait_phase() {
 target="$1" phase="$2"
 for _i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
  grep -q "$(printf 'phase\t%s' "$phase")" "$TMP/run/$target.state" 2>/dev/null && return 0
  sleep 0.1
 done
 fail "$target never reached $phase"
}
# Only allow a trusted, enumerated job and a numeric revoke ID.
"$HELPER" ensure '../../etc/shadow' >/dev/null 2>&1 && fail 'arbitrary job admitted'
"$HELPER" request recommended-revoke '7;touch /tmp/pwn' >/dev/null 2>&1 && fail 'shell injection admitted'
"$HELPER" request recommended-revoke 0 >/dev/null 2>&1 && fail 'invalid ID admitted'
# A slow catalog fetch must return immediately and be single-flight.
"$HELPER" ensure catalog
wait_phase catalog running
"$HELPER" ensure catalog
wait_phase catalog success
[ "$(grep -c '^fetch$' "$TMP/count")" -eq 1 ] || fail 'duplicate catalog fetch'
"$HELPER" ensure catalog
[ "$(grep -c '^fetch$' "$TMP/count")" -eq 1 ] || fail 'cached catalog fetched again'
# Explicit actions bypass snapshot TTL and stay detached.
"$HELPER" request catalog
wait_phase catalog running
wait_phase catalog success
[ "$(count_fetches)" -eq 2 ] || fail 'manual refresh did not start'
# A failed fetch must retry after 60 seconds, not after the 10-minute success TTL.
# Even an empty cache must not allow automatic retry storms after a failure.
touch "$RPC_TEST_FAIL"
rm -f "$RPC_TEST_CACHE"
"$HELPER" request catalog
wait_phase catalog failed
[ "$(count_fetches)" -eq 3 ] || fail 'failed fetch was not executed'
"$HELPER" ensure catalog
[ "$(count_fetches)" -eq 3 ] || fail 'failed catalog retried too soon'
backdate_catalog "$(($(date +%s) - 61))"
"$HELPER" ensure catalog
wait_phase catalog failed
[ "$(count_fetches)" -eq 4 ] || fail 'failed catalog did not retry after 60 seconds'
# A successful retry must return to the 600-second cache TTL.
rm -f "$RPC_TEST_FAIL"
backdate_catalog "$(($(date +%s) - 61))"
"$HELPER" ensure catalog
wait_phase catalog success
[ "$(count_fetches)" -eq 5 ] || fail 'failed catalog did not recover'
"$HELPER" ensure catalog
[ "$(count_fetches)" -eq 5 ] || fail 'recovered catalog did not retain 10-minute TTL'
# Changing the firmware bypasses the TTL, including after an earlier failure.
printf '{"device_code":"iptime-ax3000sm","build_id":"build-B","channel":"stable"}\n' > "$SMARTSAFEHUB_APPS_METADATA"
"$HELPER" ensure catalog
wait_phase catalog success
[ "$(count_fetches)" -eq 6 ] || fail 'firmware change did not refresh catalog'
"$HELPER" ensure catalog
[ "$(count_fetches)" -eq 6 ] || fail 'same firmware fetched twice'
# ROM metadata takes precedence over the writable overlay version.
printf '{"device_code":"iptime-ax3000sm","build_id":"rom-A","channel":"stable"}\n' > "$SMARTSAFEHUB_APPS_ROM_METADATA"
"$HELPER" ensure catalog
wait_phase catalog success
[ "$(count_fetches)" -eq 7 ] || fail 'ROM firmware identity not adopted'
printf '{"device_code":"iptime-ax3000sm","build_id":"overlay-C","channel":"stable"}\n' > "$SMARTSAFEHUB_APPS_METADATA"
"$HELPER" ensure catalog
[ "$(count_fetches)" -eq 7 ] || fail 'overlay metadata overrode ROM'
# The cached display snapshot can disappear independently of the job state.
rm -f "$RPC_TEST_CACHE"
"$HELPER" ensure catalog
wait_phase catalog success
[ "$(count_fetches)" -eq 8 ] || fail 'missing catalog cache did not refresh'
# A firmware change during failure backoff must be retried immediately.
touch "$RPC_TEST_FAIL"
"$HELPER" request catalog
wait_phase catalog failed
[ "$(count_fetches)" -eq 9 ] || fail 'failed refresh did not run'
printf '{"device_code":"iptime-ax3000sm","build_id":"rom-B","channel":"stable"}\n' > "$SMARTSAFEHUB_APPS_ROM_METADATA"
rm -f "$RPC_TEST_FAIL"
"$HELPER" ensure catalog
wait_phase catalog success
[ "$(count_fetches)" -eq 10 ] || fail 'firmware change did not bypass failure backoff'
"$HELPER" ensure status
wait_phase status success
"$HELPER" ensure sizes
wait_phase sizes success
# A failed request is not reported as a completed successful revoke.
touch "$RPC_TEST_FAIL"
"$HELPER" request recommended-revoke 42
wait_phase recommended-revoke failed
grep -q "$(printf 'argument\t42')" "$TMP/run/recommended-revoke.state" || fail 'missing target ID'
grep -q "$(printf 'code\tE1')" "$TMP/run/recommended-revoke.state" || fail 'failure code suppressed'
# Conflicting concurrent revocations are rejected rather than replacing the target.
rm -f "$RPC_TEST_FAIL"
"$HELPER" request recommended-revoke 42
wait_phase recommended-revoke running
"$HELPER" request recommended-revoke 43 >/dev/null 2>&1 && fail 'concurrent revoke target replaced'
wait_phase recommended-revoke success
# Four consecutive failures (initial request + 3 retries) impose a 20-minute
# cooldown. Page visits and missing snapshots must not bypass the cooldown.
touch "$RPC_TEST_FAIL"
rm -f "$RPC_TEST_CACHE"
base="$(count_fetches)"
"$HELPER" request catalog
wait_phase catalog failed
[ "$(count_fetches)" -eq "$((base + 1))" ] || fail 'initial attempt missing'
grep -q "$(printf 'failures\t1')" "$TMP/run/catalog.state" || fail 'initial failure counter incorrect'
for retry in 2 3 4; do
 "$HELPER" ensure catalog
 [ "$(count_fetches)" -eq "$((base + retry - 1))" ] || fail 'retry ran before 60 seconds'
 backdate_catalog "$(($(date +%s) - 61))"
 "$HELPER" ensure catalog
 wait_phase catalog failed
 [ "$(count_fetches)" -eq "$((base + retry))" ] || fail '60-second retry missing'
 grep -q "$(printf 'failures\t%s' "$retry")" "$TMP/run/catalog.state" || fail 'failure count not persisted'
done
"$HELPER" ensure catalog
[ "$(count_fetches)" -eq "$((base + 4))" ] || fail 'fifth attempt ran during cooldown'
backdate_catalog "$(($(date +%s) - 1199))"
"$HELPER" ensure catalog
[ "$(count_fetches)" -eq "$((base + 4))" ] || fail '20-minute cooldown bypassed by missing cache'
# An expired cooldown begins a fresh cycle with a first failure, not failure 5.
backdate_catalog "$(($(date +%s) - 1201))"
"$HELPER" ensure catalog
wait_phase catalog failed
[ "$(count_fetches)" -eq "$((base + 5))" ] || fail 'cooldown expiry did not restart refresh'
grep -q "$(printf 'failures\t1')" "$TMP/run/catalog.state" || fail 'new retry cycle was not reset'
# A manual retry bypasses a fresh failure delay and resets the counter.
"$HELPER" request catalog
wait_phase catalog failed
[ "$(count_fetches)" -eq "$((base + 6))" ] || fail 'manual refresh was throttled'
grep -q "$(printf 'failures\t1')" "$TMP/run/catalog.state" || fail 'manual refresh did not reset retry cycle'
# Firmware changes also clear backoff even without a catalog snapshot.
printf '{"device_code":"iptime-ax3000sm","build_id":"rom-C","channel":"stable"}\n' > "$SMARTSAFEHUB_APPS_ROM_METADATA"
"$HELPER" ensure catalog
wait_phase catalog failed
[ "$(count_fetches)" -eq "$((base + 7))" ] || fail 'firmware change was throttled'
grep -q "$(printf 'failures\t1')" "$TMP/run/catalog.state" || fail 'firmware change did not reset counter'
# Success returns to the normal 10-minute refresh interval.
rm -f "$RPC_TEST_FAIL"
backdate_catalog "$(($(date +%s) - 61))"
"$HELPER" ensure catalog
wait_phase catalog success
[ "$(count_fetches)" -eq "$((base + 8))" ] || fail 'recovery attempt missing'
grep -q "$(printf 'failures\t0')" "$TMP/run/catalog.state" || fail 'recovery did not clear failure counter'
"$HELPER" ensure catalog
[ "$(count_fetches)" -eq "$((base + 8))" ] || fail 'successful refresh ignored 10-minute TTL'
# Exhaust another retry cycle and verify that a firmware upgrade bypasses
# the full 20-minute pause, without inheriting the previous failure count.
touch "$RPC_TEST_FAIL"
base="$(count_fetches)"
"$HELPER" request catalog
wait_phase catalog failed
for retry in 1 2 3; do
 backdate_catalog "$(($(date +%s) - 61))"
 "$HELPER" ensure catalog
 wait_phase catalog failed
done
[ "$(count_fetches)" -eq "$((base + 4))" ] || fail 'could not exhaust retry allowance'
grep -q "$(printf 'failures\t4')" "$TMP/run/catalog.state" || fail 'cooldown state was not saved'
printf '{"device_code":"iptime-ax3000sm","build_id":"rom-D","channel":"stable"}\n' > "$SMARTSAFEHUB_APPS_ROM_METADATA"
"$HELPER" ensure catalog
wait_phase catalog failed
[ "$(count_fetches)" -eq "$((base + 5))" ] || fail 'firmware upgrade did not bypass cooldown'
grep -q "$(printf 'failures\t1')" "$TMP/run/catalog.state" || fail 'firmware upgrade inherited exhausted retries'
# Manual refresh must also bypass a full cooldown and start a clean cycle.
for retry in 1 2 3; do
 backdate_catalog "$(($(date +%s) - 61))"
 "$HELPER" ensure catalog
 wait_phase catalog failed
done
grep -q "$(printf 'failures\t4')" "$TMP/run/catalog.state" || fail 'manual-cooldown setup failed'
"$HELPER" request catalog
wait_phase catalog failed
grep -q "$(printf 'failures\t1')" "$TMP/run/catalog.state" || fail 'manual refresh inherited exhausted retries'
sh -n "$HELPER" || fail 'launcher syntax invalid'
echo 'PASS: detached RPC worker, 3 retries, 20-minute cooldown, firmware cache identity and failure states'
