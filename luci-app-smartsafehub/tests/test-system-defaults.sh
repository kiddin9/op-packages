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
	fail 'system defaults must set the SmartSafeHub hostname on fresh OpenWrt defaults'
grep -Fq "uci -q set system.@system[0].zonename='Asia/Seoul'" "$DEFAULTS" || \
	fail 'system defaults must set the IANA timezone name on fresh OpenWrt defaults'
grep -Fq "uci -q set system.@system[0].timezone='UTC+9'" "$DEFAULTS" || \
	fail 'system defaults must keep the existing SmartSafeHub POSIX timezone default'
grep -Fq "set_if_missing system.@system[0].log_size '64'" "$DEFAULTS" || \
	fail 'system defaults must only fill a missing log size'
grep -Fq "uci -q set system.ntp='timeserver'" "$DEFAULTS" || \
	fail 'system defaults must create the named NTP section when it is missing'
grep -Fq "uci -q add_list system.ntp.server='3.openwrt.pool.ntp.org'" "$DEFAULTS" || \
	fail 'system defaults must configure the OpenWrt NTP pool only when no server list exists'
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

mock_value() {
	value="$1"
	[ "$value" != '__MISSING__' ] || return 1
	printf '%s\n' "$value"
}

case "$*" in
	'-q get system.@system[0]') exit "${MOCK_SYSTEM_GET_RC:-0}" ;;
	'-q get system.ntp') exit "${MOCK_NTP_GET_RC:-0}" ;;
	'-q get system.@system[0].hostname') mock_value "${MOCK_HOSTNAME:-__MISSING__}" ;;
	'-q get system.@system[0].zonename') mock_value "${MOCK_ZONENAME:-__MISSING__}" ;;
	'-q get system.@system[0].timezone') mock_value "${MOCK_TIMEZONE:-__MISSING__}" ;;
	'-q get system.@system[0].ttylogin') mock_value "${MOCK_TTYLOGIN:-__MISSING__}" ;;
	'-q get system.@system[0].log_size') mock_value "${MOCK_LOG_SIZE:-__MISSING__}" ;;
	'-q get system.@system[0].urandom_seed') mock_value "${MOCK_URANDOM_SEED:-__MISSING__}" ;;
	'-q get system.ntp.enabled') mock_value "${MOCK_NTP_ENABLED:-__MISSING__}" ;;
	'-q get system.ntp.enable_server') mock_value "${MOCK_NTP_ENABLE_SERVER:-__MISSING__}" ;;
	'-q get system.ntp.server') mock_value "${MOCK_NTP_SERVERS:-__MISSING__}" ;;
esac
exit 0
MOCK
chmod +x "$TMP_DIR/uci"

LOG_EXISTING="$TMP_DIR/existing.log"
PATH="$TMP_DIR:$PATH" \
MOCK_UCI_LOG="$LOG_EXISTING" \
MOCK_SYSTEM_GET_RC=0 \
MOCK_NTP_GET_RC=0 \
MOCK_HOSTNAME='HomeGateway' \
MOCK_ZONENAME='America/New_York' \
MOCK_TIMEZONE='EST5EDT,M3.2.0,M11.1.0' \
MOCK_TTYLOGIN='1' \
MOCK_LOG_SIZE='128' \
MOCK_URANDOM_SEED='1' \
MOCK_NTP_ENABLED='0' \
MOCK_NTP_ENABLE_SERVER='1' \
MOCK_NTP_SERVERS='time.example.net' \
	/bin/sh "$DEFAULTS"

if grep -Fq -- '-q add system system' "$LOG_EXISTING"; then
	fail 'existing OpenWrt system section must not be recreated'
fi
if grep -Fq -- '-q set system.ntp=timeserver' "$LOG_EXISTING"; then
	fail 'existing NTP section must not be recreated'
fi
for forbidden in \
	'-q set system.@system[0].hostname=' \
	'-q set system.@system[0].zonename=' \
	'-q set system.@system[0].timezone=' \
	'-q set system.@system[0].ttylogin=' \
	'-q set system.@system[0].log_size=' \
	'-q set system.@system[0].urandom_seed=' \
	'-q set system.ntp.enabled=' \
	'-q set system.ntp.enable_server=' \
	'-q add_list system.ntp.server='; do
	if grep -Fq -- "$forbidden" "$LOG_EXISTING"; then
		fail "existing user setting must be preserved: $forbidden"
	fi
done
if grep -Fq 'compat_version' "$LOG_EXISTING"; then
	fail 'runtime defaults must not mutate compat_version'
fi

LOG_FRESH="$TMP_DIR/fresh.log"
PATH="$TMP_DIR:$PATH" \
MOCK_UCI_LOG="$LOG_FRESH" \
MOCK_SYSTEM_GET_RC=0 \
MOCK_NTP_GET_RC=0 \
MOCK_HOSTNAME='OpenWrt' \
MOCK_ZONENAME='UTC' \
MOCK_TIMEZONE='UTC0' \
MOCK_TTYLOGIN='__MISSING__' \
MOCK_LOG_SIZE='__MISSING__' \
MOCK_URANDOM_SEED='__MISSING__' \
MOCK_NTP_ENABLED='__MISSING__' \
MOCK_NTP_ENABLE_SERVER='__MISSING__' \
MOCK_NTP_SERVERS='__MISSING__' \
	/bin/sh "$DEFAULTS"

grep -Fq -- '-q set system.@system[0].hostname=SmartRouter' "$LOG_FRESH" || \
	fail 'fresh OpenWrt hostname must receive the SmartSafeHub default'
grep -Fq -- '-q set system.@system[0].zonename=Asia/Seoul' "$LOG_FRESH" || \
	fail 'fresh OpenWrt timezone must receive the SmartSafeHub zonename default'
grep -Fq -- '-q set system.@system[0].timezone=UTC+9' "$LOG_FRESH" || \
	fail 'fresh OpenWrt timezone must receive the SmartSafeHub POSIX timezone default'
grep -Fq -- '-q add_list system.ntp.server=0.openwrt.pool.ntp.org' "$LOG_FRESH" || \
	fail 'fresh OpenWrt NTP configuration must receive the default server list'

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

echo 'PASS: SmartSafeHub defaults preserve OpenWrt metadata and existing user system settings'
