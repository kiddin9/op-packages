#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
#
# Runtime configuration-transaction tests.
#
# These cover the pieces init.d/homeproxy relies on so that a bad
# configuration cannot leave the router without a working service:
#
#   * the known-good copy recorded after a configuration passed check
#   * the fallback to that copy when a regeneration produces nothing
#   * the rollback after a reload that comes up unhealthy
#   * the health probe that decides whether a rollback is needed
#
# The helpers are pure shell on purpose (see scripts/runtime/), so this runs
# anywhere, without ucode, procd or a router.
#
# Usage: sh tests/runtime/test_config_transaction.sh <repo-root>

ROOT="${1:-.}"
ROOT="$(cd "$ROOT" && pwd)"
RUNTIME="$ROOT/root/etc/homeproxy/scripts/runtime"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/hp-runtime.XXXXXX")" || exit 1
trap 'rm -rf "$WORK"' EXIT INT TERM

FAILED=0
CHECKS=0
FAILURES=0

expect() {
	# expect <name> <actual> <expected>
	CHECKS=$((CHECKS + 1))
	if [ "$2" = "$3" ]; then
		echo "PASS: $1"
	else
		echo "FAIL: $1 (expected '$3', got '$2')"
		FAILED=1
		FAILURES=$((FAILURES + 1))
	fi
}

if [ ! -f "$RUNTIME/config.sh" ] || [ ! -f "$RUNTIME/health.sh" ]; then
	echo "FAIL: runtime helpers are missing under $RUNTIME"
	exit 1
fi

# shellcheck source=/dev/null
. "$RUNTIME/config.sh"
# shellcheck source=/dev/null
. "$RUNTIME/health.sh"

LIVE="$WORK/run/sing-box-c.json"
GOOD="$WORK/run/known-good/sing-box-c.json"

echo "== config transaction =="

# Nothing generated yet and no fallback: unusable.
hp_ensure_live "$LIVE" "$GOOD"
expect "ensure_live: nothing usable" "$?" "2"

# A configuration that passed check becomes the known-good copy.
mkdir -p "$WORK/run"
printf 'v1\n' > "$LIVE"
hp_known_good "$LIVE" "$GOOD"
expect "known_good: recorded" "$?" "0"
expect "known_good: content" "$(cat "$GOOD")" "v1"

# Live file present -> ensure_live leaves it alone.
hp_ensure_live "$LIVE" "$GOOD"
expect "ensure_live: keeps the live file" "$?" "0"

# Generation failed and removed the live file -> restore the fallback.  This
# is the start-up path: without it a failed generation left the router with
# no configuration at all.
rm -f "$LIVE"
hp_ensure_live "$LIVE" "$GOOD"
expect "ensure_live: restores the fallback" "$?" "1"
expect "ensure_live: restored content" "$(cat "$LIVE")" "v1"

# A new configuration that passes check but is not yet proven: the fallback
# still holds the previous one.
printf 'v2\n' > "$LIVE"
hp_same_file "$LIVE" "$GOOD"
expect "same_file: different configs" "$?" "1"
hp_rollback "$LIVE" "$GOOD"
expect "rollback: applied" "$?" "0"
expect "rollback: previous content restored" "$(cat "$LIVE")" "v1"
hp_same_file "$LIVE" "$GOOD"
expect "same_file: identical configs" "$?" "0"

# Nothing to roll back to must be reported, not silently ignored.
rm -f "$GOOD"
hp_rollback "$LIVE" "$GOOD"
expect "rollback: refuses without a fallback" "$?" "1"
hp_same_file "$LIVE" "$GOOD"
expect "same_file: missing file is not equal" "$?" "1"

echo "== health probe =="

# Deterministic stubs so the probe's control flow is tested rather than the
# host's process table or a real service.
#
# The gate asks procd first (ubus + jsonfilter) and only falls back to a
# process scan when procd cannot be asked at all.  That order is the fix for
# the P0: with the process scan
# first, a STALE sing-box process left over from an earlier run kept answering
# "alive" while procd restarted a crashing instance, so a dead service was
# accepted and recorded as the new known-good.  The first case below pins
# exactly that.
BIN="$WORK/bin"
mkdir -p "$BIN"

# One sample == one ubus call, so the counter indexes the health pattern.
cat > "$BIN/ubus" <<'STUB'
#!/bin/sh
n=$(cat "$HP_FAKE_COUNTER" 2>/dev/null || echo 0)
n=$((n + 1))
echo "$n" > "$HP_FAKE_COUNTER"
echo 'procd-state'
STUB
cat > "$BIN/pgrep" <<'STUB'
#!/bin/sh
[ "${HP_FAKE_STALE_PROC:-0}" = "1" ] && exit 0
exit 1
STUB
cat > "$BIN/jsonfilter" <<'STUB'
#!/bin/sh
# HP_FAKE_PATTERN is a string of 1/0, one character per sample.
n=$(cat "$HP_FAKE_COUNTER" 2>/dev/null || echo 1)
[ "$n" -ge 1 ] || n=1
ch=$(printf '%s' "${HP_FAKE_PATTERN:-1}" | cut -c "$n")
[ -n "$ch" ] || ch=$(printf '%s' "${HP_FAKE_PATTERN:-1}" | cut -c 1)
up=no
[ "$ch" = "1" ] && up=yes
case "$*" in
*".instances["*)
	if [ "$up" = "yes" ]; then
		printf '{"running":true}\n'
	else
		printf '{"running":false,"exit_code":1}\n'
	fi
	;;
*"@.running"*) [ "$up" = "yes" ] && echo true || echo false ;;
*"@.exit_code"*) [ "$up" = "yes" ] || echo 1 ;;
esac
exit 0
STUB
cat > "$BIN/netstat" <<'STUB'
#!/bin/sh
echo "Proto Recv-Q Send-Q Local Address  Foreign Address  State  PID/Program name"
if [ "${HP_FAKE_NO_OWNER:-0}" = "1" ]; then
	printf 'tcp 0 0 :::%s :::* LISTEN\n' "${HP_FAKE_PORT:-5330}"
elif [ -n "${HP_FAKE_PORT:-}" ]; then
	printf 'tcp 0 0 :::%s :::* LISTEN 42/%s\n' "$HP_FAKE_PORT" "${HP_FAKE_PORT_OWNER:-sing-box}"
fi
exit 0
STUB
# The health budget is measured in samples, not wall-clock seconds; sleeping
# for real would make each case take the whole budget in seconds.
cat > "$BIN/sleep" <<'STUB'
#!/bin/sh
exit 0
STUB
chmod +x "$BIN/pgrep" "$BIN/ubus" "$BIN/jsonfilter" "$BIN/netstat" "$BIN/sleep"
PATH="$BIN:$PATH"
export PATH

CFG="$WORK/run/sing-box-c.json"
: > "$CFG"
COUNTER="$WORK/sample-count"
HP_FAKE_COUNTER="$COUNTER"
export HP_FAKE_COUNTER

reset_samples() {
	echo 0 > "$COUNTER"
}

# 1. procd says down while a stale process still matches the scan.
HP_FAKE_PATTERN=0 HP_FAKE_STALE_PROC=1
export HP_FAKE_PATTERN HP_FAKE_STALE_PROC
reset_samples
hp_instance_running "sing-box-c" "$CFG"
expect "instance_running: a stale process does not override procd" "$?" "1"

# 2. procd says running and reports no failed exit code.
HP_FAKE_PATTERN=1 HP_FAKE_STALE_PROC=0
export HP_FAKE_PATTERN HP_FAKE_STALE_PROC
reset_samples
hp_instance_running "sing-box-c" "$CFG"
expect "instance_running: reports up" "$?" "0"

# 3. hp_wait_service needs the instance healthy for several CONSECUTIVE
#    samples: one lucky poll must not be enough (that is what let a
#    crash-restart loop pass the old gate).
HP_FAKE_PATTERN=101010
export HP_FAKE_PATTERN
reset_samples
hp_wait_service "sing-box-c" "$CFG" 6 3
expect "wait_service: alternating samples never reach the stability window" "$?" "1"

# 4. A bad sample early in the window resets the count, and a later healthy run
#    still succeeds.
HP_FAKE_PATTERN=110111
export HP_FAKE_PATTERN
reset_samples
hp_wait_service "sing-box-c" "$CFG" 6 3
expect "wait_service: recovers after a bad sample" "$?" "0"

# 5. Listener attribution.  "The port is in the listen table" is not enough: in
#    the failure this gate exists for, the port was listening but owned by the
#    process that had taken it.
HP_FAKE_PORT=5330 HP_FAKE_PORT_OWNER=sing-box
export HP_FAKE_PORT HP_FAKE_PORT_OWNER
hp_listener_owned "sing-box" 5330
expect "listener: owned by sing-box" "$?" "0"

HP_FAKE_PORT_OWNER=socat
export HP_FAKE_PORT_OWNER
hp_listener_owned "sing-box" 5330
expect "listener: listening but owned by another process fails" "$?" "1"

HP_FAKE_NO_OWNER=1
export HP_FAKE_NO_OWNER
hp_listener_owned "sing-box" 5330
expect "listener: no owner column is reported as unavailable" "$?" "2"
unset HP_FAKE_NO_OWNER

HP_FAKE_PORT=5330 HP_FAKE_PORT_OWNER=sing-box
export HP_FAKE_PORT HP_FAKE_PORT_OWNER
hp_listener_owned "sing-box" 5330 5399
expect "listener: a missing port fails" "$?" "1"

# 6. The whole sample: procd up and the listeners owned.
HP_FAKE_PATTERN=1
export HP_FAKE_PATTERN
reset_samples
hp_service_healthy "sing-box-c" "$CFG" 5330
expect "service_healthy: procd up and listeners owned" "$?" "0"

HP_FAKE_PORT_OWNER=socat
export HP_FAKE_PORT_OWNER
reset_samples
hp_service_healthy "sing-box-c" "$CFG" 5330
expect "service_healthy: procd up but the listener was taken by another process" "$?" "1"

# 7. hp_wait_instance is kept for compatibility.
HP_FAKE_PORT_OWNER=sing-box HP_FAKE_PATTERN=1
export HP_FAKE_PORT_OWNER HP_FAKE_PATTERN
reset_samples
hp_wait_instance "sing-box-c" "$CFG" 1
expect "wait_instance (compat): succeeds while running" "$?" "0"

HP_FAKE_PATTERN=0
export HP_FAKE_PATTERN
reset_samples
hp_wait_instance "sing-box-c" "$CFG" 1
expect "wait_instance (compat): times out when down" "$?" "1"

printf '%d checks, %d failures\n' "$CHECKS" "$FAILURES"
exit $FAILED
