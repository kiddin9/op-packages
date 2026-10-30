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
sleep 1
[ ! -e "$RPC_TEST_FAIL" ]
SH
cat > "$TMP/manager" <<'SH'
#!/bin/sh
printf '%s\n' "$1" >> "$RPC_TEST_COUNT"
sleep 1
SH
cat > "$TMP/device" <<'SH'
#!/bin/sh
printf '%s:%s\n' "$1" "${2:-}" >> "$RPC_TEST_COUNT"
sleep 1
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
wait_phase() {
 target="$1" phase="$2"
 for _i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
  grep -q "$(printf 'phase\t%s' "$phase")" "$TMP/run/$target.state" 2>/dev/null && return 0
  sleep 0.2
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
[ "$(grep -c '^fetch$' "$TMP/count")" -eq 2 ] || fail 'manual refresh did not start'
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
sh -n "$HELPER" || fail 'launcher syntax invalid'
echo 'PASS: detached RPC worker, cache TTL, single-flight, validation and failure states'
