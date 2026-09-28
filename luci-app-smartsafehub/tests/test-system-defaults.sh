#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
DEFAULTS="$ROOT_DIR/root/etc/uci-defaults/90-smartsafehub-system-defaults"

fail() {
	echo "FAIL: $*" >&2
	exit 1
}

[ -x "$DEFAULTS" ] || fail 'SmartSafeHub system defaults must be executable'

grep -Fq "uci -q set system.@system[0].hostname='SmartRouter'" "$DEFAULTS" || \
	fail 'system defaults must set the SmartSafeHub hostname'
grep -Fq "uci -q set system.@system[0].zonename='Asia/Seoul'" "$DEFAULTS" || \
	fail 'system defaults must set the IANA timezone name'
grep -Fq "uci -q set system.@system[0].timezone='UTC+9'" "$DEFAULTS" || \
	fail 'system defaults must keep the existing SmartSafeHub POSIX timezone default'
grep -Fq "uci -q set system.@system[0].log_size='64'" "$DEFAULTS" || \
	fail 'system defaults must keep the configured log size'
grep -Fq "uci -q set system.ntp='timeserver'" "$DEFAULTS" || \
	fail 'system defaults must create the named NTP section when it is missing'
grep -Fq "uci -q add_list system.ntp.server='3.openwrt.pool.ntp.org'" "$DEFAULTS" || \
	fail 'system defaults must configure the OpenWrt NTP pool'
grep -Fq 'uci -q commit system' "$DEFAULTS" || \
	fail 'system defaults must commit the system UCI package'

if grep -Eq '(^|[[:space:]])uci[[:space:]].*(delete|revert)[[:space:]]+system\.@system\[0\]([[:space:]]|$)' "$DEFAULTS"; then
	fail 'system defaults must never delete or replace the OpenWrt-generated system section'
fi
if grep -Eq 'uci[[:space:]].*(set|delete).*compat_version' "$DEFAULTS"; then
	fail 'system defaults must leave OpenWrt compat_version under platform control'
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT INT TERM

cat > "$TMP_DIR/uci" <<'MOCK'
#!/bin/sh
printf '%s\n' "$*" >> "$MOCK_UCI_LOG"
case "$*" in
	'-q get system.@system[0]') exit "${MOCK_SYSTEM_GET_RC:-0}" ;;
	'-q get system.ntp') exit "${MOCK_NTP_GET_RC:-0}" ;;
esac
exit 0
MOCK
chmod +x "$TMP_DIR/uci"

LOG_EXISTING="$TMP_DIR/existing.log"
PATH="$TMP_DIR:$PATH" \
MOCK_UCI_LOG="$LOG_EXISTING" \
MOCK_SYSTEM_GET_RC=0 \
MOCK_NTP_GET_RC=0 \
	/bin/sh "$DEFAULTS"

if grep -Fq -- '-q add system system' "$LOG_EXISTING"; then
	fail 'existing OpenWrt system section must not be recreated'
fi
if grep -Fq -- '-q set system.ntp=timeserver' "$LOG_EXISTING"; then
	fail 'existing NTP section must not be recreated'
fi
if grep -Fq 'compat_version' "$LOG_EXISTING"; then
	fail 'runtime defaults must not mutate compat_version'
fi

LOG_MISSING="$TMP_DIR/missing.log"
PATH="$TMP_DIR:$PATH" \
MOCK_UCI_LOG="$LOG_MISSING" \
MOCK_SYSTEM_GET_RC=1 \
MOCK_NTP_GET_RC=1 \
	/bin/sh "$DEFAULTS"

grep -Fq -- '-q add system system' "$LOG_MISSING" || \
	fail 'missing system section must be created defensively'
grep -Fq -- '-q set system.ntp=timeserver' "$LOG_MISSING" || \
	fail 'missing NTP section must be created defensively'

echo 'PASS: SmartSafeHub system defaults preserve OpenWrt compatibility metadata'
