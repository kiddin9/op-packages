#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
export SMARTSAFEHUB_COMMON_LIB="$ROOT_DIR/root/usr/lib/smartsafehub/common.sh"
FIRMWARE="$ROOT_DIR/root/usr/libexec/smartsafehub-firmware"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT INT TERM

fail() {
	echo "FAIL: $*" >&2
	exit 1
}

assert_contains() {
	file="$1"
	needle="$2"
	grep -F -- "$needle" "$file" >/dev/null 2>&1 || fail "$file does not contain: $needle"
}

mkdir -p "$TMP/bin" "$TMP/sysinfo" "$TMP/repo"
printf '%s\n' 'iptime,ax3000sm' > "$TMP/sysinfo/board_name"
printf '%s\n' 'https://repo.smartsafehub.com/stable/packages/aarch64_cortex-a53/smartsafehub/packages.adb' > "$TMP/repo/smartsafehub.list"
cat > "$TMP/firmware.json" <<'EOF2'
{
  "schema": 1,
  "device_code": "iptime-ax3000sm",
  "build_id": "current-build",
  "channel": "stable",
  "openwrt_version": "25.12.4"
}
EOF2
printf '%s' 'mock-sysupgrade-image-v1' > "$TMP/server-image.bin"
IMAGE_SIZE="$(wc -c < "$TMP/server-image.bin" | tr -d '[:space:]')"
IMAGE_SHA="$(sha256sum "$TMP/server-image.bin" | awk '{ print $1 }')"

cat > "$TMP/resolve.json" <<EOF2
{
  "schema": 1,
  "device_code": "iptime-ax3000sm",
  "channel": "stable",
  "current_build_id": "current-build",
  "current_version": "1.1.0",
  "update_available": true,
  "release": {
    "id": 21,
    "build_id": "20260913T070000Z-test1234",
    "version": "1.2.0",
    "device_code": "iptime-ax3000sm",
    "channel": "stable",
    "target": "mediatek/filogic",
    "profile": "iptime_ax3000sm",
    "openwrt_version": "25.12.4",
    "published_at": "2026-09-13T07:00:00Z",
    "release_notes": ["Firmware test release"],
    "sysupgrade": {
      "id": 99,
      "filename": "openwrt-iptime-ax3000sm-sysupgrade.bin",
      "size_bytes": $IMAGE_SIZE,
      "sha256": "$IMAGE_SHA",
      "download_url": "https://www.smartsafehub.com/firmware/download/99/"
    }
  }
}
EOF2

cat > "$TMP/bin/uci" <<'EOF2'
#!/bin/sh
set -eu
[ "${1:-}" = '-q' ] && shift
case "${1:-}" in
	get)
		case "${2:-}" in
			smartsafehub.firmware.check_interval_s) echo 21600 ;;
			smartsafehub.firmware.api_base_url) echo 'https://www.smartsafehub.com/api/v1' ;;
			*) exit 1 ;;
		esac
		;;
	set|commit) exit 0 ;;
	*) exit 1 ;;
esac
EOF2
chmod +x "$TMP/bin/uci"

cat > "$TMP/bin/jsonfilter" <<'EOF2'
#!/bin/sh
set -eu
input=''
expression=''
while [ "$#" -gt 0 ]; do
	case "$1" in
		-i) input="$2"; shift 2 ;;
		-e) expression="$2"; shift 2 ;;
		*) shift ;;
	esac
done
[ -n "$input" ] && [ -n "$expression" ] || exit 1
jq_expression="${expression#@}"
jq -r "$jq_expression | if . == null then empty else . end" "$input"
EOF2
chmod +x "$TMP/bin/jsonfilter"

cat > "$TMP/bin/uclient-fetch" <<'EOF2'
#!/bin/sh
set -eu
output=''
body=''
url=''
while [ "$#" -gt 0 ]; do
	case "$1" in
		-q) shift ;;
		-T) shift 2 ;;
		--method=POST) shift ;;
		--body-file=*) body="${1#--body-file=}"; shift ;;
		--header=*) shift ;;
		-O) output="$2"; shift 2 ;;
		*) url="$1"; shift ;;
	esac
done
printf '%s\n' "$url" >> "${MOCK_FETCH_LOG:?}"
case "$url" in
	*/api/v1/firmware/resolve)
		[ -n "$body" ] || exit 1
		[ "${MOCK_FAIL_RESOLVE:-0}" = '1' ] && exit 1
		cp "$body" "${MOCK_REQUEST_CAPTURE:?}"
		cp "${MOCK_RESOLVE_FILE:?}" "$output"
		;;
	*/firmware/download/99/)
		cp "${MOCK_SERVER_IMAGE:?}" "$output"
		;;
	*) exit 1 ;;
esac
EOF2
chmod +x "$TMP/bin/uclient-fetch"

cat > "$TMP/bin/ubus" <<'EOF2'
#!/bin/sh
set -eu
printf '%s\n' "$*" >> "${MOCK_UBUS_LOG:?}"
printf '%s\n' '{"valid":true,"allow_backup":true}'
EOF2
chmod +x "$TMP/bin/ubus"

cat > "$TMP/bin/sysupgrade" <<'EOF2'
#!/bin/sh
set -eu
printf '%s\n' "$*" >> "${MOCK_SYSUPGRADE_LOG:?}"
[ "${1:-}" = '--test' ] || exit 99
[ -s "${2:-}" ]
EOF2
chmod +x "$TMP/bin/sysupgrade"

export MOCK_FETCH_LOG="$TMP/fetch.log"
export MOCK_REQUEST_CAPTURE="$TMP/request.json"
export MOCK_RESOLVE_FILE="$TMP/resolve.json"
export MOCK_SERVER_IMAGE="$TMP/server-image.bin"
export MOCK_UBUS_LOG="$TMP/ubus.log"
export MOCK_SYSUPGRADE_LOG="$TMP/sysupgrade.log"
export SMARTSAFEHUB_FIRMWARE_STATE_FILE="$TMP/firmware.state"
export SMARTSAFEHUB_FIRMWARE_RESOLVE_FILE="$TMP/resolved.json"
export SMARTSAFEHUB_FIRMWARE_IMAGE_FILE="$TMP/firmware.bin"
export SMARTSAFEHUB_FIRMWARE_LOCK_DIR="$TMP/firmware.lock"
export SMARTSAFEHUB_FIRMWARE_METADATA_FILE="$TMP/firmware.json"
export SMARTSAFEHUB_FIRMWARE_BOARD_NAME_FILE="$TMP/sysinfo/board_name"
export SMARTSAFEHUB_FIRMWARE_UCI_BIN="$TMP/bin/uci"
export SMARTSAFEHUB_FIRMWARE_UCLIENT_FETCH_BIN="$TMP/bin/uclient-fetch"
export SMARTSAFEHUB_FIRMWARE_JSONFILTER_BIN="$TMP/bin/jsonfilter"
export SMARTSAFEHUB_FIRMWARE_SHA256SUM_BIN="$(command -v sha256sum)"
export SMARTSAFEHUB_FIRMWARE_UBUS_BIN="$TMP/bin/ubus"
export SMARTSAFEHUB_FIRMWARE_SYSUPGRADE_BIN="$TMP/bin/sysupgrade"

"$FIRMWARE" check
jq -e '.schema == 1 and .device_code == "iptime-ax3000sm" and .channel == "stable" and .current_build_id == "current-build"' "$TMP/request.json" >/dev/null || \
	fail 'resolve request must contain schema, exact device code, channel and immutable current build id'
assert_contains "$TMP/fetch.log" 'https://www.smartsafehub.com/api/v1/firmware/resolve'
printf '%s
' 'https://repo.smartsafehub.com/beta/packages/aarch64_cortex-a53/smartsafehub/packages.adb' > "$TMP/repo/smartsafehub.list"
"$FIRMWARE" check
jq -e '.channel == "stable"' "$TMP/request.json" >/dev/null || 	fail 'firmware resolve must keep the installed firmware channel even when the package repository channel differs'
jq -e '.current_version == "1.1.0" and .release.version == "1.2.0"' "$TMP/resolved.json" >/dev/null || \
	fail 'resolved firmware must preserve server-assigned current and available release versions'
if jq -e 'has("release_version")' "$TMP/firmware.json" >/dev/null; then
	fail 'immutable firmware metadata must not embed an administrator-assigned release version'
fi
TAB="$(printf '\t')"
assert_contains "$TMP/firmware.state" "phase${TAB}idle"

# A resolved release for another model/channel must never be prepared.
jq '.release.device_code = "xiaomi-ax3000t"' "$TMP/resolved.json" > "$TMP/resolved-mismatch.json"
mv "$TMP/resolved-mismatch.json" "$TMP/resolved.json"
if "$FIRMWARE" prepare; then
	fail 'resolved firmware for another device must be rejected'
fi
assert_contains "$TMP/firmware.state" "error_code${TAB}FIRMWARE_RELEASE_MISMATCH"

# A failed refresh must invalidate the previous resolve document so a stale
# release cannot still be prepared after a server/network failure.
cp "$TMP/resolve.json" "$TMP/resolved.json"
export MOCK_FAIL_RESOLVE=1
if "$FIRMWARE" check; then
	fail 'failed resolve refresh must return an error'
fi
[ ! -e "$TMP/resolved.json" ] || fail 'failed resolve refresh must remove the stale resolve document'
unset MOCK_FAIL_RESOLVE

# Refresh restores the authoritative response before the normal prepare flow.
"$FIRMWARE" check
"$FIRMWARE" prepare
cmp -s "$TMP/server-image.bin" "$TMP/firmware.bin" || fail 'prepared firmware differs from downloaded image'
assert_contains "$TMP/firmware.state" "phase${TAB}ready"
assert_contains "$TMP/firmware.state" "source${TAB}online"
assert_contains "$TMP/firmware.state" "prepared_sha256${TAB}$IMAGE_SHA"
assert_contains "$TMP/firmware.state" "allow_backup${TAB}1"
assert_contains "$TMP/firmware.state" "target_build_id${TAB}20260913T070000Z-test1234"
assert_contains "$TMP/ubus.log" 'call system validate_firmware_image'
assert_contains "$TMP/sysupgrade.log" "--test $TMP/firmware.bin"

# Installation re-checks the SHA-256 before starting sysupgrade.
printf 'tampered' >> "$TMP/firmware.bin"
if "$FIRMWARE" install 1; then
	fail 'tampered prepared image must be rejected before flashing'
fi
assert_contains "$TMP/firmware.state" "error_code${TAB}FIRMWARE_CHECKSUM_MISMATCH"

# Manual uploads use the same OpenWrt validation and sysupgrade --test path.
cp "$TMP/server-image.bin" "$TMP/firmware.bin"
"$FIRMWARE" validate-upload 'manual-test.bin'
assert_contains "$TMP/firmware.state" "phase${TAB}ready"
assert_contains "$TMP/firmware.state" "source${TAB}manual"
assert_contains "$TMP/firmware.state" "filename${TAB}manual-test.bin"
assert_contains "$TMP/firmware.state" "allow_backup${TAB}1"

# Cleaning a prepared image must remove the temporary binary and return to idle.
"$FIRMWARE" clean
[ ! -e "$TMP/firmware.bin" ] || fail 'clean must remove the prepared firmware image'
assert_contains "$TMP/firmware.state" "phase${TAB}idle"

# Policy contract: firmware update checks are always enabled. The firmware helper
# must not depend on an enable/disable UCI flag. Management-software update
# check_enabled is intentionally separate and remains user-configurable.
if grep -Fq 'check_enabled' "$FIRMWARE"; then
	fail 'firmware helper must not depend on check_enabled'
fi

# Safety contract: SmartSafeHub never enables forced sysupgrade.
if grep -Eq '"\$SYSUPGRADE_BIN"[^\n]*(--force|-F)' "$FIRMWARE"; then
	fail 'firmware helper must not offer forced sysupgrade'
fi

# The firmware daemon performs one early boot check, retries transient failures at most
# three times, and then falls back to the normal configured interval.
assert_contains "$FIRMWARE" 'DAEMON_INITIAL_DELAY_S=10'
assert_contains "$FIRMWARE" 'BOOT_CHECK_RETRY_S=60'
assert_contains "$FIRMWARE" 'BOOT_CHECK_MAX_ATTEMPTS=3'
assert_contains "$FIRMWARE" 'boot_check_with_retry || true'

sed '/^case "${1:-}" in$/,$d' "$FIRMWARE" > "$TMP/firmware-lib.sh"
# shellcheck disable=SC1090
. "$TMP/firmware-lib.sh"

# Supported-device contract: new ipTIME models must be accepted from immutable
# firmware metadata and must still be discoverable from OpenWrt board_name when
# older images do not contain SmartSafeHub metadata.
cat > "$TMP/firmware.json" <<'EOF2'
{"device_code":"iptime-a3004t"}
EOF2
[ "$(firmware_device_code)" = 'iptime-a3004t' ] || \
	fail 'A3004T firmware metadata must resolve to iptime-a3004t'

cat > "$TMP/firmware.json" <<'EOF2'
{"device_code":"iptime-ax3000se"}
EOF2
[ "$(firmware_device_code)" = 'iptime-ax3000se' ] || \
	fail 'AX3000SE firmware metadata must resolve to iptime-ax3000se'

cat > "$TMP/firmware.json" <<'EOF2'
{"device_code":"unsupported-device"}
EOF2
printf '%s\n' 'iptime,a3004t' > "$TMP/sysinfo/board_name"
[ "$(firmware_device_code)" = 'iptime-a3004t' ] || \
	fail 'A3004T board_name fallback must resolve to iptime-a3004t'

printf '%s\n' 'iptime,ax3000se' > "$TMP/sysinfo/board_name"
[ "$(firmware_device_code)" = 'iptime-ax3000se' ] || \
	fail 'AX3000SE board_name fallback must resolve to iptime-ax3000se'

MOCK_BOOT_CHECK_CALLS=0
MOCK_BOOT_CHECK_SUCCESS_AT=2
MOCK_BOOT_SLEEP_LOG="$TMP/firmware-boot-sleep.log"
: > "$MOCK_BOOT_SLEEP_LOG"

load_daemon_settings() {
	CHECK_ENABLED=1
}

execute_check() {
	MOCK_BOOT_CHECK_CALLS=$((MOCK_BOOT_CHECK_CALLS + 1))
	[ "$MOCK_BOOT_CHECK_CALLS" -ge "$MOCK_BOOT_CHECK_SUCCESS_AT" ]
}

sleep() {
	printf '%s\n' "$1" >> "$MOCK_BOOT_SLEEP_LOG"
}

log_message() {
	:
}

boot_check_with_retry
[ "$MOCK_BOOT_CHECK_CALLS" -eq 2 ] || fail 'firmware boot check did not stop after the first successful retry'
[ "$(wc -l < "$MOCK_BOOT_SLEEP_LOG" | tr -d '[:space:]')" -eq 1 ] || fail 'firmware boot check must sleep only between failed attempts'
assert_contains "$MOCK_BOOT_SLEEP_LOG" '60'

MOCK_BOOT_CHECK_CALLS=0
MOCK_BOOT_CHECK_SUCCESS_AT=99
: > "$MOCK_BOOT_SLEEP_LOG"
if boot_check_with_retry; then
	fail 'firmware boot check must report failure after exhausting retries'
fi
[ "$MOCK_BOOT_CHECK_CALLS" -eq 3 ] || fail 'firmware boot check must stop after three failed attempts'
[ "$(wc -l < "$MOCK_BOOT_SLEEP_LOG" | tr -d '[:space:]')" -eq 2 ] || fail 'firmware boot retry must wait only between the three attempts'

echo 'PASS: firmware resolve, download integrity, OpenWrt validation, boot retry and cleanup paths are safe'
