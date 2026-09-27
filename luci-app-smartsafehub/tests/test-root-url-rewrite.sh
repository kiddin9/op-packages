#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
HANDLER="$ROOT_DIR/root/etc/uhttpd/smartsafehub-root.json"
HELPER="$ROOT_DIR/root/usr/libexec/smartsafehub-root-entry"
UCI_DEFAULT="$ROOT_DIR/root/etc/uci-defaults/99-smartsafehub-root-entry"
MAKEFILE="$ROOT_DIR/Makefile"

fail() {
	echo "FAIL: $*" >&2
	exit 1
}

[ -f "$HANDLER" ] || fail 'missing uHTTPd root rewrite handler'
[ -f "$HELPER" ] || fail 'missing root entry helper'
[ -x "$UCI_DEFAULT" ] || fail 'root entry uci-default must be executable'

jq -e '
  .request == [
    ["if", ["eq", "REQUEST_URI", "/"], ["rewrite", "/cgi-bin/luci/"]]
  ]
' "$HANDLER" >/dev/null || \
	fail 'uHTTPd handler must rewrite only the exact root request to /cgi-bin/luci/'

if grep -R -F 'uhttpd.main.index_page' "$HELPER" "$UCI_DEFAULT" "$MAKEFILE" >/dev/null 2>&1; then
	fail 'SmartSafeHub root entry must not modify the global uHTTPd index_page setting'
fi
if [ -e "$ROOT_DIR/root/www/index.html" ]; then
	fail 'SmartSafeHub package must not replace /www/index.html owned by the base web UI'
fi

grep -Fq '/bin/sh /usr/libexec/smartsafehub-root-entry --install --reconcile' "$MAKEFILE" || \
	fail 'runtime package install must register and reconcile the root rewrite via /bin/sh'
grep -Fq '/bin/sh /usr/libexec/smartsafehub-root-entry --remove --reconcile' "$MAKEFILE" || \
	fail 'package removal must unregister and reconcile only the SmartSafeHub root rewrite via /bin/sh'
grep -Fq '/bin/sh /usr/libexec/smartsafehub-root-entry --install' "$UCI_DEFAULT" || \
	fail 'firmware first boot must register the root rewrite handler via /bin/sh'
if grep -Fq -- '--reconcile' "$UCI_DEFAULT"; then
	fail 'uci-default must not restart uHTTPd during first-boot configuration'
fi
if grep -Fq '"$UHTTPD_INIT" reload' "$HELPER"; then
	fail 'runtime reconciliation must not rely on uHTTPd reload for command-line -H changes'
fi
grep -Fq '"$UHTTPD_INIT" restart' "$HELPER" || \
	fail 'runtime reconciliation must restart uHTTPd when the configured -H handler is missing or stale'

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT INT TERM
mkdir -p "$TMP_DIR/bin" "$TMP_DIR/proc/4242"
STATE_FILE="$TMP_DIR/json-script.state"
LOG_FILE="$TMP_DIR/uci.log"
COMMIT_FILE="$TMP_DIR/commit.count"
RESTART_FILE="$TMP_DIR/restart.count"
CMDLINE_FILE="$TMP_DIR/proc/4242/cmdline"

cat > "$TMP_DIR/bin/uci" <<'STUB'
#!/bin/sh
set -eu
: "${SMARTSAFEHUB_TEST_STATE:?}"
: "${SMARTSAFEHUB_TEST_LOG:?}"
: "${SMARTSAFEHUB_TEST_COMMIT:?}"

printf '%s\n' "$*" >> "$SMARTSAFEHUB_TEST_LOG"
[ "${1:-}" = '-q' ] && shift
cmd="${1:-}"
[ "$#" -gt 0 ] && shift

case "$cmd" in
	show)
		[ "${1:-}" = 'uhttpd.main' ] || exit 1
		exit 0
		;;
	get)
		[ "${1:-}" = 'uhttpd.main.json_script' ] || exit 1
		[ -s "$SMARTSAFEHUB_TEST_STATE" ] || exit 1
		cat "$SMARTSAFEHUB_TEST_STATE"
		;;
	add_list)
		value="${1#uhttpd.main.json_script=}"
		current="$(cat "$SMARTSAFEHUB_TEST_STATE" 2>/dev/null || true)"
		if [ -n "$current" ]; then
			printf '%s %s\n' "$current" "$value" > "$SMARTSAFEHUB_TEST_STATE"
		else
			printf '%s\n' "$value" > "$SMARTSAFEHUB_TEST_STATE"
		fi
		;;
	del_list)
		value="${1#uhttpd.main.json_script=}"
		current="$(cat "$SMARTSAFEHUB_TEST_STATE" 2>/dev/null || true)"
		result=''
		for item in $current; do
			[ "$item" = "$value" ] && continue
			result="${result:+$result }$item"
		done
		printf '%s\n' "$result" > "$SMARTSAFEHUB_TEST_STATE"
		;;
	commit)
		[ "${1:-}" = 'uhttpd' ] || exit 1
		count="$(cat "$SMARTSAFEHUB_TEST_COMMIT" 2>/dev/null || printf '0')"
		printf '%s\n' "$((count + 1))" > "$SMARTSAFEHUB_TEST_COMMIT"
		;;
	*)
		exit 1
		;;
esac
STUB
chmod +x "$TMP_DIR/bin/uci"

cat > "$TMP_DIR/bin/pidof" <<'STUB'
#!/bin/sh
set -eu
[ "${1:-}" = 'uhttpd' ] || exit 1
printf '%s\n' '4242'
STUB
chmod +x "$TMP_DIR/bin/pidof"

cat > "$TMP_DIR/uhttpd" <<'STUB'
#!/bin/sh
set -eu
: "${SMARTSAFEHUB_TEST_RESTART:?}"
: "${SMARTSAFEHUB_TEST_STATE:?}"
: "${SMARTSAFEHUB_TEST_HANDLER:?}"
: "${SMARTSAFEHUB_TEST_CMDLINE:?}"
[ "${1:-}" = 'restart' ] || exit 1
count="$(cat "$SMARTSAFEHUB_TEST_RESTART" 2>/dev/null || printf '0')"
printf '%s\n' "$((count + 1))" > "$SMARTSAFEHUB_TEST_RESTART"

has_handler=0
for item in $(cat "$SMARTSAFEHUB_TEST_STATE" 2>/dev/null || true); do
	if [ "$item" = "$SMARTSAFEHUB_TEST_HANDLER" ]; then
		has_handler=1
		break
	fi
done

if [ "$has_handler" -eq 1 ]; then
	printf '/usr/sbin/uhttpd\0-f\0-H\0%s\0' "$SMARTSAFEHUB_TEST_HANDLER" > "$SMARTSAFEHUB_TEST_CMDLINE"
else
	printf '/usr/sbin/uhttpd\0-f\0' > "$SMARTSAFEHUB_TEST_CMDLINE"
fi
STUB
chmod +x "$TMP_DIR/uhttpd"

existing_a='/etc/uhttpd/existing-a.json'
existing_b='/etc/uhttpd/existing-b.json'
printf '%s %s\n' "$existing_a" "$existing_b" > "$STATE_FILE"
printf '0\n' > "$COMMIT_FILE"
printf '0\n' > "$RESTART_FILE"
printf '/usr/sbin/uhttpd\0-f\0' > "$CMDLINE_FILE"
: > "$LOG_FILE"

export SMARTSAFEHUB_TEST_STATE="$STATE_FILE"
export SMARTSAFEHUB_TEST_LOG="$LOG_FILE"
export SMARTSAFEHUB_TEST_COMMIT="$COMMIT_FILE"
export SMARTSAFEHUB_TEST_RESTART="$RESTART_FILE"
export SMARTSAFEHUB_TEST_HANDLER="$HANDLER"
export SMARTSAFEHUB_TEST_CMDLINE="$CMDLINE_FILE"
export SMARTSAFEHUB_ROOT_HANDLER="$HANDLER"
export SMARTSAFEHUB_UHTTPD_INIT="$TMP_DIR/uhttpd"
export SMARTSAFEHUB_PROC_ROOT="$TMP_DIR/proc"
PATH="$TMP_DIR/bin:$PATH"
export PATH

sh "$HELPER" --install --reconcile
expected="$existing_a $existing_b $HANDLER"
[ "$(cat "$STATE_FILE")" = "$expected" ] || \
	fail 'install must append the SmartSafeHub handler without replacing existing json_script handlers'
[ "$(cat "$COMMIT_FILE")" = '1' ] || fail 'first install must commit uhttpd once'
[ "$(cat "$RESTART_FILE")" = '1' ] || fail 'runtime install must restart uhttpd when -H is missing'
tr '\000' '\n' < "$CMDLINE_FILE" | grep -Fxq "$HANDLER" || \
	fail 'restart must make the SmartSafeHub -H handler visible in the runtime command line'

sh "$HELPER" --install --reconcile
[ "$(cat "$STATE_FILE")" = "$expected" ] || fail 'repeated install must preserve configured handlers'
[ "$(cat "$COMMIT_FILE")" = '1' ] || fail 'idempotent install must not commit again'
[ "$(cat "$RESTART_FILE")" = '1' ] || fail 'synchronized runtime install must not restart uhttpd again'

# Reproduce the field failure: UCI already contains the handler, but the running
# process was started without -H. The helper must heal runtime without another commit.
printf '/usr/sbin/uhttpd\0-f\0' > "$CMDLINE_FILE"
sh "$HELPER" --install --reconcile
[ "$(cat "$STATE_FILE")" = "$expected" ] || fail 'runtime repair must not alter configured handlers'
[ "$(cat "$COMMIT_FILE")" = '1' ] || fail 'runtime-only repair must not commit unchanged uhttpd config'
[ "$(cat "$RESTART_FILE")" = '2' ] || fail 'runtime-only repair must restart uhttpd when configured -H is absent'
tr '\000' '\n' < "$CMDLINE_FILE" | grep -Fxq "$HANDLER" || \
	fail 'runtime-only repair must restore the configured -H handler'

sh "$HELPER" --remove --reconcile
expected="$existing_a $existing_b"
[ "$(cat "$STATE_FILE")" = "$expected" ] || \
	fail 'remove must preserve all json_script handlers owned by other packages'
[ "$(cat "$COMMIT_FILE")" = '2' ] || fail 'remove must commit uhttpd once'
[ "$(cat "$RESTART_FILE")" = '3' ] || fail 'runtime remove must restart uhttpd while stale -H is still active'
if tr '\000' '\n' < "$CMDLINE_FILE" | grep -Fxq "$HANDLER"; then
	fail 'runtime remove must clear the SmartSafeHub -H handler'
fi

sh "$HELPER" --remove --reconcile
[ "$(cat "$STATE_FILE")" = "$expected" ] || fail 'repeated remove must be idempotent'
[ "$(cat "$COMMIT_FILE")" = '2' ] || fail 'idempotent remove must not commit again'
[ "$(cat "$RESTART_FILE")" = '3' ] || fail 'synchronized repeated remove must not restart uhttpd again'

if grep -Fq 'index_page' "$LOG_FILE"; then
	fail 'root entry helper must never read or write index_page'
fi

echo 'PASS: exact-root rewrite preserves other handlers and self-heals uHTTPd runtime -H state'
