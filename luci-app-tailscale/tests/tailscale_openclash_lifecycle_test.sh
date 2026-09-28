#!/bin/sh

set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
INIT_SCRIPT="$ROOT_DIR/root/etc/init.d/tailscale-openclash-bypass"
UCI_CONFIG="$ROOT_DIR/root/etc/config/tailscale_openclash"
TMP_DIR="${TMPDIR:-/tmp}/tailscale-openclash-lifecycle-test.$$"

cleanup() {
	rm -rf "$TMP_DIR"
}
trap cleanup EXIT

fail() {
	echo "FAIL: $*" >&2
	exit 1
}

[ -f "$INIT_SCRIPT" ] || fail "missing OpenClash bypass init script"
[ -f "$UCI_CONFIG" ] || fail "missing OpenClash bypass UCI config"
grep -qx "config openclash 'settings'" "$UCI_CONFIG" || \
	fail 'OpenClash bypass UCI config must use the openclash section type'

mkdir -p "$TMP_DIR"

cat >"$TMP_DIR/fake-helper" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >>"${FAKE_HELPER_LOG:?}"
SH
chmod +x "$TMP_DIR/fake-helper"

run_service() {
	service_entrypoint="$1"
	script_path="${2:-$INIT_SCRIPT}"
	FAKE_HELPER_LOG="$TMP_DIR/helper.log"
	: >"$FAKE_HELPER_LOG"
	export FAKE_HELPER_LOG

	rc=0
	(
		. "$script_path"
		PROG="$TMP_DIR/fake-helper"

		config_load() {
			fail 'procd lifecycle must leave UCI reads to the locked helper sync command'
		}

		config_foreach() {
			fail 'procd lifecycle must not split helper sync by UCI section'
		}

		config_get_bool() {
			fail 'procd lifecycle must not decide enabled state outside the helper lock'
		}

		"$service_entrypoint"
	) || rc=$?
	[ "$rc" -eq 0 ] || return "$rc"

	cat "$FAKE_HELPER_LOG"
}

enabled_start_log="$(run_service start_service)"
[ "$enabled_start_log" = "sync" ] || fail "start must reconcile under one helper lock"

enabled_reload_log="$(run_service reload_service)"
[ "$enabled_reload_log" = "sync" ] || fail "reload must reconcile under one helper lock"

stop_log="$(run_service stop_service)"
[ "$stop_log" = "cleanup" ] || fail "stop must remove only owned state"

[ "$(grep -Fc '"$PROG" sync' "$INIT_SCRIPT")" -eq 1 ] || \
	fail 'procd lifecycle must contain exactly one helper sync invocation'
grep -E 'config_(load|foreach|get_bool)' "$INIT_SCRIPT" >/dev/null && \
	fail 'OpenClash lifecycle must not read UCI outside the helper lock'

grep -F 'procd_add_reload_trigger "tailscale_openclash"' "$INIT_SCRIPT" >/dev/null || \
	fail 'OpenClash lifecycle needs its own UCI reload trigger'
grep -F 'procd_add_reload_trigger "tailscale"' "$INIT_SCRIPT" >/dev/null && \
	fail 'OpenClash lifecycle must not subscribe to the core Tailscale UCI package'
grep -E '/etc/init.d/(tailscale|firewall|openclash)|fw4 (reload|restart)' "$INIT_SCRIPT" >/dev/null && \
	fail 'OpenClash lifecycle must not manage Tailscale, firewall4, or OpenClash services'

echo "tailscale OpenClash lifecycle tests passed"
