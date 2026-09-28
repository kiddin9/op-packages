#!/bin/sh

set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
INIT_SCRIPT="$ROOT_DIR/root/etc/init.d/tailscale-policy-routing"
HOTPLUG_SCRIPT="$ROOT_DIR/root/etc/hotplug.d/iface/98-tailscale-policy-routing"
UCI_CONFIG="$ROOT_DIR/root/etc/config/tailscale_policy_routing"
TMP_DIR="${TMPDIR:-/tmp}/tailscale-policy-routing-lifecycle-test.$$"

cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT HUP INT TERM

fail() {
	echo "FAIL: $*" >&2
	exit 1
}

[ -x "$INIT_SCRIPT" ] || fail "missing policy-routing init script"
[ -x "$HOTPLUG_SCRIPT" ] || fail "missing policy-routing hotplug script"
[ -f "$UCI_CONFIG" ] || fail "missing policy-routing UCI config"
grep -qx "config settings 'settings'" "$UCI_CONFIG" || fail 'policy-routing UCI config must use a settings section'

mkdir -p "$TMP_DIR"
cat >"$TMP_DIR/fake-helper" <<'SH'
#!/bin/sh
case "${1:-}" in
sync|monitor) printf '%s\n' "$*" >>"${FAKE_HELPER_LOG:?}" ;;
enabled)
	printf '%s\n' "$*" >>"${FAKE_HELPER_LOG:?}"
	[ "${FAKE_HELPER_ENABLED:-1}" = 1 ]
	;;
*) exit 2 ;;
esac
SH
chmod +x "$TMP_DIR/fake-helper"

run_service() {
	entrypoint="$1"
	FAKE_HELPER_LOG="$TMP_DIR/helper.log"
	FAKE_PROCD_LOG="$TMP_DIR/procd.log"
	: >"$FAKE_HELPER_LOG"
	: >"$FAKE_PROCD_LOG"
	export FAKE_HELPER_LOG FAKE_PROCD_LOG
	(
		procd_open_instance() { printf 'open %s\n' "${1:-default}" >>"$FAKE_PROCD_LOG"; }
		procd_set_param() { printf 'set %s\n' "$*" >>"$FAKE_PROCD_LOG"; }
		procd_close_instance() { printf '%s\n' 'close' >>"$FAKE_PROCD_LOG"; }
		. "$INIT_SCRIPT"
		PROG="$TMP_DIR/fake-helper"
		"$entrypoint"
	)
	cat "$FAKE_HELPER_LOG" "$FAKE_PROCD_LOG"
}

expected_start="sync
enabled
open monitor
set command $TMP_DIR/fake-helper monitor
set respawn
close"
[ "$(run_service start_service)" = "$expected_start" ] || fail 'start must synchronize and monitor policy routing'
[ "$(run_service reload_service)" = "$expected_start" ] || fail 'reload must recreate the policy-routing monitor'
FAKE_HELPER_ENABLED=0
export FAKE_HELPER_ENABLED
disabled_start="$(run_service start_service)"
[ "$disabled_start" = "sync
enabled" ] || fail 'disabled policy routing must not create a monitor instance'
unset FAKE_HELPER_ENABLED
[ -z "$(run_service stop_service)" ] || fail 'ordinary stop must preserve persistent policy-routing configuration'

grep -F 'procd_add_reload_trigger "tailscale_policy_routing"' "$INIT_SCRIPT" >/dev/null || \
	fail 'policy-routing service needs its own UCI reload trigger'
grep -E '/etc/init.d/(tailscale|firewall|mwan3|openclash)|fw4 (reload|restart)|mwan3 restart' "$INIT_SCRIPT" "$HOTPLUG_SCRIPT" >/dev/null && \
	fail 'policy-routing lifecycle must not manage Tailscale, firewall, mwan3, or OpenClash services'
grep -F 'procd_set_param command "$PROG" monitor' "$INIT_SCRIPT" >/dev/null || \
	fail 'policy-routing service must continuously reconcile Tailscale route changes'

echo 'tailscale policy-routing lifecycle tests passed'
