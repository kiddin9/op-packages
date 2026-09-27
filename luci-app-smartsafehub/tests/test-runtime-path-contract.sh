#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
RUNTIME_DIR='/tmp/smartsafehub'

fail() {
	printf 'FAIL: %s\n' "$*" >&2
	exit 1
}

# Production SmartSafeHub runtime data must not be scattered in /tmp as
# /tmp/smartsafehub-* files. Keep one product-owned directory only.
if grep -R -n -F --exclude='app.js' --exclude='app.css' '/tmp/smartsafehub-' \
	"$ROOT_DIR/root" "$ROOT_DIR/frontend/src" >/dev/null 2>&1; then
	grep -R -n -F --exclude='app.js' --exclude='app.css' '/tmp/smartsafehub-' "$ROOT_DIR/root" "$ROOT_DIR/frontend/src" >&2 || true
	fail 'production runtime paths must live under /tmp/smartsafehub/'
fi

for file in \
	"$ROOT_DIR/root/usr/libexec/smartsafehub-updater" \
	"$ROOT_DIR/root/usr/libexec/smartsafehub-firmware" \
	"$ROOT_DIR/root/usr/libexec/smartsafehub-maintenance" \
	"$ROOT_DIR/root/usr/libexec/smartsafehub-backup"
do
	grep -Fq 'SMARTSAFEHUB_RUNTIME_DIR:-/tmp/smartsafehub' "$file" || \
		fail "${file#$ROOT_DIR/} must use the shared SmartSafeHub runtime directory"
	grep -Fq 'mkdir -p "$RUNTIME_DIR" || exit 1' "$file" || \
		fail "${file#$ROOT_DIR/} must create its runtime directory before use"
done

for file in \
	"$ROOT_DIR/root/etc/init.d/smartsafehub-updater" \
	"$ROOT_DIR/root/etc/init.d/smartsafehub-firmware" \
	"$ROOT_DIR/root/etc/init.d/smartsafehub-maintenance"
do
	grep -Fq 'RUNTIME_DIR=/tmp/smartsafehub' "$file" || \
		fail "${file#$ROOT_DIR/} must declare the shared runtime directory"
	grep -Fq 'mkdir -p "$RUNTIME_DIR" || return 1' "$file" || \
		fail "${file#$ROOT_DIR/} must recreate the runtime directory after boot"
done

check_path() {
	file="$1"
	path="$2"
	grep -Fq "$path" "$file" || fail "${file#$ROOT_DIR/} must reference $path"
}

check_path "$ROOT_DIR/root/usr/share/rpcd/ucode/smartsafehub/updates.uc" "$RUNTIME_DIR/updates.state"
check_path "$ROOT_DIR/root/usr/share/rpcd/ucode/smartsafehub/updates.uc" "$RUNTIME_DIR/release-notes.json"
check_path "$ROOT_DIR/root/usr/share/rpcd/ucode/smartsafehub/firmware.uc" "$RUNTIME_DIR/firmware.state"
check_path "$ROOT_DIR/root/usr/share/rpcd/ucode/smartsafehub/firmware.uc" "$RUNTIME_DIR/firmware-resolve.json"
check_path "$ROOT_DIR/root/usr/share/rpcd/ucode/smartsafehub/backup.uc" "$RUNTIME_DIR/config-backup.tar.gz"
check_path "$ROOT_DIR/root/usr/share/rpcd/ucode/smartsafehub/network-management.uc" "$RUNTIME_DIR/lan-update.lock"
check_path "$ROOT_DIR/root/usr/share/rpcd/ucode/smartsafehub/wifi-management.uc" "$RUNTIME_DIR/wifi-update.lock"
check_path "$ROOT_DIR/frontend/src/api/firmwareUpload.ts" "$RUNTIME_DIR/firmware.bin"
check_path "$ROOT_DIR/frontend/src/api/configurationBackup.ts" "$RUNTIME_DIR/config-backup.tar.gz"

jq -e --arg path "$RUNTIME_DIR/firmware.bin" \
	'."luci-app-smartsafehub".write.file[$path] | index("write") != null' \
	"$ROOT_DIR/root/usr/share/rpcd/acl.d/luci-app-smartsafehub.json" >/dev/null || \
	fail 'firmware upload ACL must use the shared runtime directory'
jq -e --arg path "$RUNTIME_DIR/config-backup.tar.gz" \
	'."luci-app-smartsafehub".write.file[$path] | index("write") != null' \
	"$ROOT_DIR/root/usr/share/rpcd/acl.d/luci-app-smartsafehub.json" >/dev/null || \
	fail 'backup upload ACL must use the shared runtime directory'

# Helpers must also be able to create an overridden runtime directory on their
# own, which keeps direct/manual invocations safe even before a procd restart.
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT INT TERM
FIRMWARE_RUNTIME="$TMP/firmware-runtime"
SMARTSAFEHUB_RUNTIME_DIR="$FIRMWARE_RUNTIME" \
	SMARTSAFEHUB_FIRMWARE_METADATA_FILE="$TMP/missing-firmware.json" \
	"$ROOT_DIR/root/usr/libexec/smartsafehub-firmware" clean >/dev/null 2>&1 || \
	fail 'firmware helper must create an overridden runtime directory'
[ -d "$FIRMWARE_RUNTIME" ] || fail 'firmware helper did not create overridden runtime directory'
[ -f "$FIRMWARE_RUNTIME/firmware.state" ] || fail 'firmware helper did not write state below overridden runtime directory'

BACKUP_RUNTIME="$TMP/backup-runtime"
SMARTSAFEHUB_RUNTIME_DIR="$BACKUP_RUNTIME" \
	"$ROOT_DIR/root/usr/libexec/smartsafehub-backup" discard >/dev/null 2>&1 || \
	fail 'backup helper must create an overridden runtime directory'
[ -d "$BACKUP_RUNTIME" ] || fail 'backup helper did not create overridden runtime directory'

echo 'PASS: SmartSafeHub runtime files are consolidated under /tmp/smartsafehub/'
