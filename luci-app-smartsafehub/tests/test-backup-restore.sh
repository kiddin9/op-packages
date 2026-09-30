#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
HELPER="$ROOT_DIR/root/usr/libexec/smartsafehub-backup"
KEEP_FILE="$ROOT_DIR/root/lib/upgrade/keep.d/smartsafehub"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT INT TERM

fail() {
	printf 'FAIL: %s\n' "$*" >&2
	exit 1
}

make_backup() {
	archive="$1"
	device_code="${2:-iptime-ax3000sm}"
	build_id="${3:-20260901T010203Z-oldbuild}"
	root="$TMP_DIR/archive"
	rm -rf "$root"
	mkdir -p "$root/etc/config" "$root/etc/dropbear"
	printf "config system 'system'\n\toption hostname 'SmartSafeHub'\n" > "$root/etc/config/system"
	cat > "$root/etc/config/smartsafehub" <<EOF_CONFIG
config firmware 'firmware'
	option device_code '$device_code'
	option current_build_id '$build_id'
	option api_base_url 'https://www.smartsafehub.com/api/v1'
EOF_CONFIG
	printf 'root:x:0:0:root:/root:/bin/ash\n' > "$root/etc/passwd"
	tar -czf "$archive" -C "$root" etc
}

make_unverified_backup() {
	archive="$1"
	root="$TMP_DIR/unverified"
	rm -rf "$root"
	mkdir -p "$root/etc/config"
	printf "config system 'system'\n\toption hostname 'Legacy'\n" > "$root/etc/config/system"
	cat > "$root/etc/config/smartsafehub" <<'EOF_CONFIG'
config firmware 'firmware'
	option api_base_url 'https://www.smartsafehub.com/api/v1'
EOF_CONFIG
	tar -czf "$archive" -C "$root" etc
}

run_helper() {
	SMARTSAFEHUB_BACKUP_FILE="$BACKUP_FILE" \
	SMARTSAFEHUB_BACKUP_SYSUPGRADE_BIN="$SYSUPGRADE_BIN" \
	SMARTSAFEHUB_BACKUP_TAR_BIN="$(command -v tar)" \
	SMARTSAFEHUB_BACKUP_REBOOT_BIN="$REBOOT_BIN" \
	SMARTSAFEHUB_BACKUP_REBOOT_DELAY_S=0 \
	SMARTSAFEHUB_BACKUP_UCI_BIN="$UCI_BIN" \
	SMARTSAFEHUB_BACKUP_JSONFILTER_BIN="$JSONFILTER_BIN" \
	SMARTSAFEHUB_BACKUP_FIRMWARE_METADATA_FILE="$FIRMWARE_METADATA_FILE" \
	SMARTSAFEHUB_BACKUP_ROM_FIRMWARE_METADATA_FILE="$ROM_FIRMWARE_METADATA_FILE" \
	SMARTSAFEHUB_BACKUP_BOARD_NAME_FILE="$BOARD_NAME_FILE" \
	SMARTSAFEHUB_BACKUP_UPDATE_STATE_FILE="$UPDATE_STATE_FILE" \
	SMARTSAFEHUB_BACKUP_FIRMWARE_STATE_FILE="$FIRMWARE_STATE_FILE" \
	SMARTSAFEHUB_BACKUP_UPDATE_LOCK_DIR="$UPDATE_LOCK_DIR" \
	SMARTSAFEHUB_BACKUP_FIRMWARE_LOCK_DIR="$FIRMWARE_LOCK_DIR" \
	SMARTSAFEHUB_BACKUP_FIRMWARE_IMAGE_FILE="$FIRMWARE_IMAGE_FILE" \
		"$HELPER" "$1"
}

BACKUP_FILE="$TMP_DIR/backup.tar.gz"
SYSUPGRADE_BIN="$TMP_DIR/sysupgrade"
REBOOT_BIN="$TMP_DIR/reboot"
UCI_BIN="$TMP_DIR/uci"
JSONFILTER_BIN="$TMP_DIR/jsonfilter"
FIRMWARE_METADATA_FILE="$TMP_DIR/overlay/usr/share/smartsafehub/firmware.json"
ROM_FIRMWARE_METADATA_FILE="$TMP_DIR/rom/usr/share/smartsafehub/firmware.json"
BOARD_NAME_FILE="$TMP_DIR/sysinfo/board_name"
UPDATE_STATE_FILE="$TMP_DIR/updates.state"
FIRMWARE_STATE_FILE="$TMP_DIR/firmware.state"
UPDATE_LOCK_DIR="$TMP_DIR/updater.lock"
FIRMWARE_LOCK_DIR="$TMP_DIR/firmware.lock"
FIRMWARE_IMAGE_FILE="$TMP_DIR/firmware.bin"
SYSUPGRADE_LOG="$TMP_DIR/sysupgrade.log"
REBOOT_MARKER="$TMP_DIR/rebooted"
UCI_LOG="$TMP_DIR/uci.log"
CURRENT_BUILD_ID='20260929T071701Z-currentbuild'

mkdir -p "$(dirname "$FIRMWARE_METADATA_FILE")" "$(dirname "$ROM_FIRMWARE_METADATA_FILE")" "$(dirname "$BOARD_NAME_FILE")"
printf '{"schema":1,"device_code":"iptime-ax3000sm","build_id":"20260928T220328Z-stale","channel":"stable"}\n' > "$FIRMWARE_METADATA_FILE"
printf '{"schema":1,"device_code":"iptime-ax3000sm","build_id":"%s","channel":"stable"}\n' \
	"$CURRENT_BUILD_ID" > "$ROM_FIRMWARE_METADATA_FILE"
printf '%s\n' 'iptime,ax3000sm' > "$BOARD_NAME_FILE"

cat > "$SYSUPGRADE_BIN" <<EOF_SYSUPGRADE
#!/bin/sh
printf '%s\n' "\$*" >> "$SYSUPGRADE_LOG"
exit 0
EOF_SYSUPGRADE
cat > "$REBOOT_BIN" <<EOF_REBOOT
#!/bin/sh
touch "$REBOOT_MARKER"
EOF_REBOOT
cat > "$UCI_BIN" <<EOF_UCI
#!/bin/sh
printf '%s\n' "\$*" >> "$UCI_LOG"
exit 0
EOF_UCI
cat > "$JSONFILTER_BIN" <<'EOF_JSONFILTER'
#!/bin/sh
file=''
expr=''
while [ "$#" -gt 0 ]; do
	case "$1" in
		-i) file="$2"; shift 2 ;;
		-e) expr="$2"; shift 2 ;;
		*) shift ;;
	esac
done
[ -f "$file" ] || exit 0
case "$expr" in
	'@.device_code') sed -n 's/.*"device_code"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$file" ;;
	'@.build_id') sed -n 's/.*"build_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$file" ;;
esac
EOF_JSONFILTER
chmod +x "$SYSUPGRADE_BIN" "$REBOOT_BIN" "$UCI_BIN" "$JSONFILTER_BIN"

[ ! -e "$KEEP_FILE" ] || fail 'firmware.json must not be preserved by SmartSafeHub sysupgrade keep.d'

make_backup "$BACKUP_FILE"
if tar -tzf "$BACKUP_FILE" | grep -Fxq 'usr/share/smartsafehub/firmware.json'; then
	fail 'configuration backup must not carry immutable firmware.json'
fi
run_helper validate || fail 'a same-device OpenWrt-style configuration archive must validate'

make_backup "$BACKUP_FILE" 'xiaomi-ax3000t'
set +e
run_helper validate >/dev/null 2>&1
status=$?
set -e
[ "$status" -eq 65 ] || fail 'a backup from another device must fail with device mismatch status 65'

make_unverified_backup "$BACKUP_FILE"
set +e
run_helper validate >/dev/null 2>&1
status=$?
set -e
[ "$status" -eq 66 ] || fail 'a backup without SmartSafeHub device_code must fail closed with status 66'

printf 'not-a-gzip' > "$BACKUP_FILE"
if run_helper validate >/dev/null 2>&1; then
	fail 'non-gzip input must be rejected'
fi

mkdir -p "$TMP_DIR/no-config/etc"
printf 'invalid\n' > "$TMP_DIR/no-config/etc/banner"
tar -czf "$BACKUP_FILE" -C "$TMP_DIR/no-config" etc
if run_helper validate >/dev/null 2>&1; then
	fail 'an archive without /etc/config content must be rejected'
fi

mkdir -p "$TMP_DIR/empty-config/etc/config"
tar -czf "$BACKUP_FILE" -C "$TMP_DIR/empty-config" etc
if run_helper validate >/dev/null 2>&1; then
	fail 'an archive with only an empty /etc/config directory must be rejected'
fi

make_backup "$BACKUP_FILE" 'iptime-ax3000sm' '20260901T010203Z-oldbuild'
run_helper restore || fail 'validated same-device backup must restore successfully'
grep -Fxq -- "--restore-backup $BACKUP_FILE" "$SYSUPGRADE_LOG" || \
	fail 'restore must delegate to sysupgrade --restore-backup'
[ ! -e "$BACKUP_FILE" ] || fail 'successful restore must delete the uploaded archive'
grep -Fq 'set smartsafehub.firmware.device_code=iptime-ax3000sm' "$UCI_LOG" || \
	fail 'restore must re-sync the current device code after applying the backup'
grep -Fq "set smartsafehub.firmware.current_build_id=$CURRENT_BUILD_ID" "$UCI_LOG" || \
	fail 'restore must re-sync firmware build identity from the currently booted ROM metadata'
grep -Fq 'commit smartsafehub' "$UCI_LOG" || \
	fail 'firmware identity re-sync must be committed'
grep -Fq '20260928T220328Z-stale' "$FIRMWARE_METADATA_FILE" || \
	fail 'restore must not rewrite the overlay firmware metadata file'
grep -Fq "$CURRENT_BUILD_ID" "$ROM_FIRMWARE_METADATA_FILE" || \
	fail 'restore must not modify immutable ROM firmware metadata'

for _ in 1 2 3 4 5 6 7 8 9 10; do
	[ -e "$REBOOT_MARKER" ] && break
	sleep 0.05
done
[ -e "$REBOOT_MARKER" ] || fail 'successful restore must schedule a reboot'

: > "$SYSUPGRADE_LOG"
rm -f "$REBOOT_MARKER"
make_backup "$BACKUP_FILE"
touch "$FIRMWARE_IMAGE_FILE"
set +e
run_helper restore >/dev/null 2>&1
status=$?
set -e
[ "$status" -eq 75 ] || fail 'restore must return busy status 75 while firmware work is pending'
[ -s "$SYSUPGRADE_LOG" ] && fail 'busy restore must not invoke sysupgrade'
[ -e "$BACKUP_FILE" ] || fail 'busy restore must keep the validated archive for retry'
rm -f "$FIRMWARE_IMAGE_FILE"

cat > "$SYSUPGRADE_BIN" <<'EOF_SYSUPGRADE_FAIL'
#!/bin/sh
exit 1
EOF_SYSUPGRADE_FAIL
chmod +x "$SYSUPGRADE_BIN"
set +e
run_helper restore >/dev/null 2>&1
status=$?
set -e
[ "$status" -ne 0 ] || fail 'sysupgrade restore failure must propagate as an error'
[ -e "$BACKUP_FILE" ] || fail 'failed restore must keep the archive for inspection or retry'
[ ! -e "$REBOOT_MARKER" ] || fail 'failed restore must never reboot the device'

run_helper discard || fail 'discard command must succeed'
[ ! -e "$BACKUP_FILE" ] || fail 'discard must remove the uploaded archive'

grep -Fq '/* | .. | ../* | */.. | */../*' "$HELPER" || \
	fail 'backup validation must reject path traversal entries before restore'

echo 'PASS: configuration backup validation uses UCI device identity without preserving firmware.json'
