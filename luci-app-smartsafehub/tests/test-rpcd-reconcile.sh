#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
HELPER="$ROOT_DIR/root/usr/libexec/smartsafehub-rpcd-reconcile"
MAKEFILE="$ROOT_DIR/Makefile"

fail() {
	echo "FAIL: $*" >&2
	exit 1
}

[ -x "$HELPER" ] || fail 'rpcd reconcile helper must exist and be executable'
grep -Fq '/bin/sh /usr/libexec/smartsafehub-rpcd-reconcile' "$MAKEFILE" || \
	fail 'package postinst must run the rpcd reconcile helper after installing RPC files'
grep -Fq '"$RPCD_INIT" reload' "$HELPER" || fail 'rpcd reconcile must try graceful reload first'
grep -Fq '"$RPCD_INIT" restart' "$HELPER" || fail 'rpcd reconcile must fall back to restart'
grep -Fq 'list "$RPC_OBJECT"' "$HELPER" || fail 'rpcd reconcile must verify the SmartSafeHub ubus object, not only the rpcd process'

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT INT TERM
mkdir -p "$TMP_DIR/bin"
STATE_FILE="$TMP_DIR/rpc.state"
RELOAD_COUNT="$TMP_DIR/reload.count"
RESTART_COUNT="$TMP_DIR/restart.count"
SLEEP_COUNT="$TMP_DIR/sleep.count"

cat > "$TMP_DIR/rpcd" <<'STUB'
#!/bin/sh
set -eu
: "${SMARTSAFEHUB_TEST_STATE:?}"
: "${SMARTSAFEHUB_TEST_RELOAD_COUNT:?}"
: "${SMARTSAFEHUB_TEST_RESTART_COUNT:?}"
: "${SMARTSAFEHUB_TEST_SCENARIO:?}"

increment() {
	file="$1"
	count="$(cat "$file" 2>/dev/null || printf '0')"
	printf '%s\n' "$((count + 1))" > "$file"
}

case "${1:-}" in
	reload)
		increment "$SMARTSAFEHUB_TEST_RELOAD_COUNT"
		case "$SMARTSAFEHUB_TEST_SCENARIO" in
			healthy)
				printf '%s\n' ready > "$SMARTSAFEHUB_TEST_STATE"
				;;
			missing-after-reload|restart-no-recovery)
				printf '%s\n' missing > "$SMARTSAFEHUB_TEST_STATE"
				;;
			reload-fails)
				printf '%s\n' missing > "$SMARTSAFEHUB_TEST_STATE"
				exit 1
				;;
			*) exit 2 ;;
		esac
		;;
	restart)
		increment "$SMARTSAFEHUB_TEST_RESTART_COUNT"
		case "$SMARTSAFEHUB_TEST_SCENARIO" in
			restart-no-recovery)
				printf '%s\n' missing > "$SMARTSAFEHUB_TEST_STATE"
				;;
			*)
				printf '%s\n' ready > "$SMARTSAFEHUB_TEST_STATE"
				;;
		esac
		;;
	*) exit 2 ;;
esac
STUB
chmod +x "$TMP_DIR/rpcd"

cat > "$TMP_DIR/ubus" <<'STUB'
#!/bin/sh
set -eu
: "${SMARTSAFEHUB_TEST_STATE:?}"
[ "${1:-}" = 'list' ] || exit 2
[ "${2:-}" = 'smartsafehub' ] || exit 2
if [ "$(cat "$SMARTSAFEHUB_TEST_STATE" 2>/dev/null || true)" = 'ready' ]; then
	printf '%s\n' 'smartsafehub'
fi
STUB
chmod +x "$TMP_DIR/ubus"

cat > "$TMP_DIR/sleep" <<'STUB'
#!/bin/sh
set -eu
: "${SMARTSAFEHUB_TEST_SLEEP_COUNT:?}"
count="$(cat "$SMARTSAFEHUB_TEST_SLEEP_COUNT" 2>/dev/null || printf '0')"
printf '%s\n' "$((count + 1))" > "$SMARTSAFEHUB_TEST_SLEEP_COUNT"
STUB
chmod +x "$TMP_DIR/sleep"

export SMARTSAFEHUB_TEST_STATE="$STATE_FILE"
export SMARTSAFEHUB_TEST_RELOAD_COUNT="$RELOAD_COUNT"
export SMARTSAFEHUB_TEST_RESTART_COUNT="$RESTART_COUNT"
export SMARTSAFEHUB_TEST_SLEEP_COUNT="$SLEEP_COUNT"
export SMARTSAFEHUB_RPCD_INIT="$TMP_DIR/rpcd"
export SMARTSAFEHUB_UBUS_BIN="$TMP_DIR/ubus"
export SMARTSAFEHUB_SLEEP_BIN="$TMP_DIR/sleep"
export SMARTSAFEHUB_RPCD_PROBE_ATTEMPTS=3
export SMARTSAFEHUB_RPCD_PROBE_DELAY_S=0
export SMARTSAFEHUB_RPCD_REQUIRED_READY_PROBES=2

reset_case() {
	printf '%s\n' ready > "$STATE_FILE"
	printf '0\n' > "$RELOAD_COUNT"
	printf '0\n' > "$RESTART_COUNT"
	printf '0\n' > "$SLEEP_COUNT"
}

# Normal case: reload successfully re-registers the core object, so active
# sessions are preserved and restart is not used.
reset_case
export SMARTSAFEHUB_TEST_SCENARIO=healthy
sh "$HELPER" || fail 'healthy rpcd reload must succeed'
[ "$(cat "$RELOAD_COUNT")" = '1' ] || fail 'healthy path must reload rpcd exactly once'
[ "$(cat "$RESTART_COUNT")" = '0' ] || fail 'healthy path must not restart rpcd'
[ "$(cat "$SLEEP_COUNT")" -ge 2 ] || fail 'helper must require stable consecutive probes before accepting the reloaded object'

# Field regression from 2026-09-20: rpcd reload returned success, but only
# smartsafehub_network was present and the core smartsafehub object vanished.
# The post-install reconciliation must detect the missing object and self-heal
# with a restart.
reset_case
export SMARTSAFEHUB_TEST_SCENARIO=missing-after-reload
sh "$HELPER" || fail 'missing core object after reload must be repaired by restart'
[ "$(cat "$RELOAD_COUNT")" = '1' ] || fail 'field regression path must still try reload first'
[ "$(cat "$RESTART_COUNT")" = '1' ] || fail 'missing core ubus object must trigger exactly one rpcd restart'
[ "$(cat "$STATE_FILE")" = 'ready' ] || fail 'rpcd restart must restore the SmartSafeHub core ubus object'

# If reload itself fails, restart is the fallback rather than leaving package
# installation with a broken login RPC.
reset_case
export SMARTSAFEHUB_TEST_SCENARIO=reload-fails
sh "$HELPER" || fail 'reload failure must be repaired by restart'
[ "$(cat "$RELOAD_COUNT")" = '1' ] || fail 'reload failure path must attempt reload once'
[ "$(cat "$RESTART_COUNT")" = '1' ] || fail 'reload failure must trigger rpcd restart'
[ "$(cat "$STATE_FILE")" = 'ready' ] || fail 'restart fallback must restore the core ubus object'

# Do not report success when even restart failed to restore the object. The
# package hook may choose to continue installation, but the helper result must
# remain observable and truthful for diagnostics/tests.
reset_case
export SMARTSAFEHUB_TEST_SCENARIO=restart-no-recovery
if sh "$HELPER"; then
	fail 'helper must fail when the core ubus object is still missing after restart'
fi
[ "$(cat "$RESTART_COUNT")" = '1' ] || fail 'non-recovery path must attempt one rpcd restart'

printf '%s\n' 'PASS: rpcd post-install reconciliation detects the missing smartsafehub ubus object and self-heals with restart'
