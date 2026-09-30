#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
FIRMWARE="$ROOT_DIR/root/usr/libexec/smartsafehub-firmware"
RPC_MODULE="$ROOT_DIR/root/usr/share/rpcd/ucode/smartsafehub/firmware.uc"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT INT TERM

fail() {
	printf 'FAIL: %s\n' "$*" >&2
	exit 1
}

mkdir -p "$TMP/bin" "$TMP/sysinfo"
OVERLAY_METADATA="$TMP/firmware-overlay.json"
ROM_METADATA="$TMP/firmware-rom.json"
UCI_LOG="$TMP/uci.log"
RESOLVE_FILE="$TMP/firmware-resolve.json"

cat > "$OVERLAY_METADATA" <<'EOF_OVERLAY'
{"schema":1,"device_code":"iptime-ax3000sm","build_id":"20260928T220328Z-stale","channel":"beta"}
EOF_OVERLAY
cat > "$ROM_METADATA" <<'EOF_ROM'
{"schema":1,"device_code":"iptime-ax3000sm","build_id":"20260929T071701Z-current","channel":"stable"}
EOF_ROM
printf '%s\n' 'iptime,ax3000sm' > "$TMP/sysinfo/board_name"
printf '%s\n' '{"schema":1,"device_code":"iptime-ax3000sm","channel":"stable","current_build_id":"20260928T220328Z-stale","update_available":true}' > "$RESOLVE_FILE"

cat > "$TMP/bin/uci" <<EOF_UCI
#!/bin/sh
[ "\${1:-}" = '-q' ] && shift
case "\${1:-}" in
	get)
		exit 1
		;;
	set|commit)
		printf '%s\n' "\$*" >> "$UCI_LOG"
		exit 0
		;;
	*) exit 1 ;;
esac
EOF_UCI
cat > "$TMP/bin/jsonfilter" <<'EOF_JSONFILTER'
#!/bin/sh
input=''
expression=''
while [ "$#" -gt 0 ]; do
	case "$1" in
		-i) input="$2"; shift 2 ;;
		-e) expression="$2"; shift 2 ;;
		*) shift ;;
	esac
done
[ -f "$input" ] || exit 0
case "$expression" in
	'@.device_code') sed -n 's/.*"device_code":"\([^"]*\)".*/\1/p' "$input" ;;
	'@.build_id') sed -n 's/.*"build_id":"\([^"]*\)".*/\1/p' "$input" ;;
	'@.channel') sed -n 's/.*"channel":"\([^"]*\)".*/\1/p' "$input" ;;
esac
EOF_JSONFILTER
chmod +x "$TMP/bin/uci" "$TMP/bin/jsonfilter"

SMARTSAFEHUB_FIRMWARE_STATE_FILE="$TMP/state" \
SMARTSAFEHUB_FIRMWARE_RESOLVE_FILE="$RESOLVE_FILE" \
SMARTSAFEHUB_FIRMWARE_IMAGE_FILE="$TMP/firmware.bin" \
SMARTSAFEHUB_FIRMWARE_LOCK_DIR="$TMP/lock" \
SMARTSAFEHUB_FIRMWARE_METADATA_FILE="$OVERLAY_METADATA" \
SMARTSAFEHUB_FIRMWARE_ROM_METADATA_FILE="$ROM_METADATA" \
SMARTSAFEHUB_FIRMWARE_BOARD_NAME_FILE="$TMP/sysinfo/board_name" \
SMARTSAFEHUB_FIRMWARE_UCI_BIN="$TMP/bin/uci" \
SMARTSAFEHUB_FIRMWARE_JSONFILTER_BIN="$TMP/bin/jsonfilter" \
	"$FIRMWARE" sync-identity

grep -Fq 'set smartsafehub.firmware.device_code=iptime-ax3000sm' "$UCI_LOG" || \
	fail 'sync-identity must persist the current ROM device code'
grep -Fq 'set smartsafehub.firmware.current_build_id=20260929T071701Z-current' "$UCI_LOG" || \
	fail 'sync-identity must prefer the current ROM build id over stale overlay metadata'
if grep -Fq '20260928T220328Z-stale' "$UCI_LOG"; then
	fail 'sync-identity must never persist the stale overlay build id when ROM metadata exists'
fi
[ ! -e "$RESOLVE_FILE" ] || fail 'identity changes must invalidate a resolve response created for the old build'

grep -Fq "const ROM_FIRMWARE_METADATA_FILE = '/rom/usr/share/smartsafehub/firmware.json';" "$RPC_MODULE" || \
	fail 'firmware RPC must read immutable ROM metadata before overlay metadata'
grep -Fq 'read_json_file(ROM_FIRMWARE_METADATA_FILE, 65536)' "$RPC_MODULE" || \
	fail 'firmware RPC metadata reader must prefer the ROM file'
grep -Fq 'resolved_build_id != current.buildId' "$RPC_MODULE" || \
	fail 'firmware RPC must reject resolve data generated for a different installed build'

echo 'PASS: firmware identity prefers immutable ROM metadata and invalidates stale update state'
