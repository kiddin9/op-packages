#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
RPC_ENTRY="$ROOT_DIR/root/usr/share/rpcd/ucode/smartsafehub.uc"
UPDATES_MODULE="$ROOT_DIR/root/usr/share/rpcd/ucode/smartsafehub/updates.uc"
FIRMWARE_MODULE="$ROOT_DIR/root/usr/share/rpcd/ucode/smartsafehub/firmware.uc"
FIRMWARE_HELPER="$ROOT_DIR/root/usr/libexec/smartsafehub-firmware"
BACKUP_MODULE="$ROOT_DIR/root/usr/share/rpcd/ucode/smartsafehub/backup.uc"
BACKUP_HELPER="$ROOT_DIR/root/usr/libexec/smartsafehub-backup"
SECURITY_MODULE="$ROOT_DIR/root/usr/share/rpcd/ucode/smartsafehub/security.uc"
LICENSE_MODULE="$ROOT_DIR/root/usr/share/rpcd/ucode/smartsafehub/license.uc"
LICENSE_HELPER="$ROOT_DIR/root/usr/libexec/smartsafehub-license"
LAN_RPC_ENTRY="$ROOT_DIR/root/usr/share/rpcd/ucode/smartsafehub-network.uc"
LAN_MODULE="$ROOT_DIR/root/usr/share/rpcd/ucode/smartsafehub/network-management.uc"
UPDATER="$ROOT_DIR/root/usr/libexec/smartsafehub-updater"
ACL="$ROOT_DIR/root/usr/share/rpcd/acl.d/luci-app-smartsafehub.json"

fail() {
	echo "FAIL: $*" >&2
	exit 1
}

assert_rpc_method() {
	method="$1"
	grep -Eq "^[[:space:]]*${method}:[[:space:]]*\\{" "$RPC_ENTRY" || \
		fail "rpc method is not registered: $method"
}

assert_acl_method() {
	access="$1"
	method="$2"
	jq -e --arg access "$access" --arg method "$method" \
		'.["luci-app-smartsafehub"][$access].ubus.smartsafehub | index($method) != null' \
		"$ACL" >/dev/null || fail "$method is missing from $access ACL"
}

assert_acl_object_method() {
	access="$1"
	object="$2"
	method="$3"
	jq -e --arg access "$access" --arg object "$object" --arg method "$method" \
		'.["luci-app-smartsafehub"][$access].ubus[$object] | index($method) != null' \
		"$ACL" >/dev/null || fail "$object.$method is missing from $access ACL"
}

for method in system_root_password_status system_root_password_set \
	updates_status updates_check updates_install updates_settings_update \
	firmware_status firmware_check firmware_prepare firmware_validate_upload firmware_install firmware_discard \
	system_time_settings system_timezone_update system_time_sync \
	system_scheduled_reboot_settings system_scheduled_reboot_update \
	health_status health_run health_reporter_update \
	license_status license_activate \
	system_backup_validate system_backup_restore system_backup_discard; do
	assert_rpc_method "$method"
done

jq -e \
	'.["luci-app-smartsafehub"].read.ubus.safeshield | index("statistics") != null' \
	"$ACL" >/dev/null || fail 'safeshield statistics is missing from read ACL'

assert_acl_method read system_root_password_status
assert_acl_method read status
assert_acl_method write system_root_password_set
[ -f "$LAN_RPC_ENTRY" ] || fail 'isolated LAN rpc entry is missing'
[ -f "$LAN_MODULE" ] || fail 'LAN implementation module is missing'
if grep -Eq "network[-_]management\.uc" "$RPC_ENTRY"; then
	fail 'main smartsafehub RPC entry must not directly import LAN implementation'
fi
if grep -Fq 'smartsafehub_network' "$RPC_ENTRY"; then
	fail 'main smartsafehub RPC entry must not synchronously call the LAN rpcd object'
fi
grep -Fq "from './smartsafehub/network-management.uc';" "$LAN_RPC_ENTRY" || \
	fail 'isolated LAN backend must use the canonical LAN implementation module path'
grep -Fq 'return { smartsafehub_network: methods };' "$LAN_RPC_ENTRY" || \
	fail 'isolated LAN backend must register its own ubus object'
grep -Fq "import { root_password_configured } from './smartsafehub/security.uc';" "$LAN_RPC_ENTRY" || \
	fail 'isolated LAN backend must enforce the root password gate itself'
for method in lan_settings lan_update lan_auto_subnet; do
	grep -Eq "^[[:space:]]*${method}:[[:space:]]*\\{" "$LAN_RPC_ENTRY" || \
		fail "isolated LAN rpc method is not registered: $method"
	if grep -Eq "^[[:space:]]*${method}:[[:space:]]*\\{" "$RPC_ENTRY"; then
		fail "LAN rpc method must not be duplicated in the main object: $method"
	fi
done
assert_acl_object_method read smartsafehub_network lan_settings
assert_acl_object_method write smartsafehub_network lan_update
assert_acl_object_method write smartsafehub_network lan_auto_subnet
assert_acl_method read updates_status
assert_acl_method write updates_check
assert_acl_method write updates_install
assert_acl_method write updates_settings_update
assert_acl_method read firmware_status
for method in firmware_check firmware_prepare firmware_validate_upload firmware_install firmware_discard; do
	assert_acl_method write "$method"
done
assert_acl_method read system_time_settings
assert_acl_method write system_timezone_update
assert_acl_method write system_time_sync
assert_acl_method read system_scheduled_reboot_settings
assert_acl_method write system_scheduled_reboot_update
assert_acl_method read health_status
assert_acl_method write health_run
assert_acl_method write health_reporter_update
assert_acl_method read license_status
assert_acl_method write license_activate
for method in system_backup_validate system_backup_restore system_backup_discard; do
	assert_acl_method write "$method"
done

jq -e '."luci-app-smartsafehub".read."cgi-io" | index("backup") != null' "$ACL" >/dev/null || \
	fail 'configuration backup download must be allowed through cgi-io backup ACL'
jq -e '."luci-app-smartsafehub".write."cgi-io" | index("upload") != null' "$ACL" >/dev/null || \
	fail 'firmware and configuration backup uploads must be allowed through cgi-io upload ACL'
jq -e '."luci-app-smartsafehub".write.file["/tmp/smartsafehub/firmware.bin"] | index("write") != null' "$ACL" >/dev/null || \
	fail 'firmware upload ACL must grant write access to the dedicated temporary image path'
jq -e '."luci-app-smartsafehub".write.file["/tmp/smartsafehub/config-backup.tar.gz"] | index("write") != null' "$ACL" >/dev/null || \
	fail 'configuration restore upload ACL must grant write access only to the dedicated temporary backup path'

jq -e \
	'.["luci-app-smartsafehub"].write.ubus.smartsafehub | index("updates_status") == null' \
	"$ACL" >/dev/null || fail 'updates_status should remain read-only'

grep -Fq "const UPDATE_PACKAGE = 'luci-app-smartsafehub';" "$UPDATES_MODULE" || \
	fail 'ucode updater target must be luci-app-smartsafehub'
grep -Fq 'UPDATE_PACKAGE="luci-app-smartsafehub"' "$UPDATER" || \
	fail 'shell updater target must be luci-app-smartsafehub'
grep -Fq 'SAFESHIELD_PACKAGE="safeshield"' "$UPDATER" || \
	fail 'shell updater must manage SafeShield dependency identity pins'
grep -Fq "const RELEASE_NOTES_FILE = '/tmp/smartsafehub/release-notes.json';" "$UPDATES_MODULE" || \
	fail 'rpc update status must read the release-note bundle cache'
grep -Fq 'state.releaseNotes = release_notes.notes;' "$UPDATES_MODULE" || \
	fail 'updates_status must expose validated release note metadata'
grep -Fq 'state.releaseNotesComplete = release_notes.complete;' "$UPDATES_MODULE" || \
	fail 'updates_status must expose release-note completeness'
grep -Fq "const UPDATE_REPOSITORY_FILE = '/etc/apk/repositories.d/smartsafehub.list';" "$UPDATES_MODULE" || \
	fail 'updates_status must read the SmartSafeHub repository file for channel metadata'
grep -Fq 'channel: channel,' "$UPDATES_MODULE" || \
	fail 'updates_status must expose the current SmartSafeHub update channel'
grep -Fq "autoInstall: boolean_option(section?.auto_install, channel == 'stable')" "$UPDATES_MODULE" || \
	fail 'new stable installations must default software auto-install on while beta defaults off'
grep -Fq 'AUTO_INSTALL="$(default_auto_install)"' "$UPDATER" || \
	fail 'shell updater must use the channel-aware auto-install default when UCI has no explicit choice'
grep -Fq 'refresh_release_notes "$packages_file"' "$UPDATER" || \
	fail 'updater must refresh display-only release notes after package checks'
grep -Fq 'collect_packages_with_live_installed "$packages_file"' "$UPDATER" || \
	fail 'failed APK index refresh must reconcile live installed state before reusing cached update metadata'
grep -Fq 'preserve_release_notes_cache_or_remove' "$UPDATER" || \
	fail 'temporary release-note failures must preserve a matching last-known-good cache'
grep -Fq '/releases/${UPDATE_PACKAGE}/index.json' "$UPDATER" || \
	fail 'updater must consult the release index before selecting skipped releases'

grep -Fq "const FIRMWARE_HELPER = '/usr/libexec/smartsafehub-firmware';" "$FIRMWARE_MODULE" || \
	fail 'firmware RPC must delegate privileged firmware work to the dedicated helper'
grep -Fq "FIRMWARE_HELPER + ' check" "$FIRMWARE_MODULE" || \
	fail 'firmware check RPC must start the firmware helper'
grep -Fq "request.args.confirm != 'install'" "$FIRMWARE_MODULE" || \
	fail 'firmware installation RPC must require an explicit confirmation token'
grep -Fq 'validate_firmware_image' "$FIRMWARE_HELPER" || \
	fail 'firmware helper must validate images with OpenWrt before flashing'
grep -Fq '"$SYSUPGRADE_BIN" --test "$IMAGE_FILE"' "$FIRMWARE_HELPER" || \
	fail 'firmware helper must run sysupgrade --test before flashing'
grep -Fq '/firmware/resolve' "$FIRMWARE_HELPER" || \
	fail 'firmware helper must use the Hub firmware resolve API'
grep -Fq "function read_firmware_channel() {" "$FIRMWARE_MODULE" || \
	fail 'firmware RPC must derive firmware channel independently from the package repository'
if grep -Fq 'UPDATE_REPOSITORY_FILE' "$FIRMWARE_MODULE"; then
	fail 'firmware RPC must not derive firmware channel from the SmartSafeHub package repository'
fi
grep -Fq '@.channel' "$FIRMWARE_HELPER" || \
	fail 'firmware helper must derive firmware channel from installed firmware metadata first'
if grep -Fq 'SMARTSAFEHUB_FIRMWARE_REPOSITORY_FILE' "$FIRMWARE_HELPER"; then
	fail 'firmware helper must not derive firmware channel from the package repository file'
fi
if grep -Eq '(--force|-F)[[:space:]]+"?\$IMAGE_FILE' "$FIRMWARE_HELPER"; then
	fail 'SmartSafeHub firmware updater must not expose forced sysupgrade'
fi


grep -Fq "const SHADOW_FILE = '/etc/shadow';" "$SECURITY_MODULE" || \
	fail 'initial security setup must inspect the root shadow password state'
grep -Fq "defer_call('luci', 'setPassword'" "$SECURITY_MODULE" || \
	fail 'initial security setup must delegate password writes to LuCI'
if grep -Fq 'oldpassword:' "$SECURITY_MODULE" || grep -Fq 'rpcd:' "$SECURITY_MODULE"; then
	fail 'initial security setup must use the OpenWrt 25.12 username/password-only luci.setPassword contract'
fi
grep -Fq "defer_call('session', 'destroy'" "$SECURITY_MODULE" || \
	fail 'initial security setup must invalidate the bootstrap session after setting a password'
grep -Fq "'SYSTEM_ROOT_PASSWORD_REQUIRED'" "$RPC_ENTRY" || \
	fail 'normal SmartSafeHub RPC methods must enforce the root password setup gate'

grep -Fq "const LICENSE_HELPER = '/usr/libexec/smartsafehub-license';" "$LICENSE_MODULE" || \
	fail 'license RPC must delegate Hub activation to the dedicated helper'
if grep -Fq "safe_call('safeshield', 'status'" "$LICENSE_MODULE"; then
	fail 'license activation RPC must not synchronously call SafeShield inside rpcd'
fi
grep -Fq 'write_private_request(license_key)' "$LICENSE_MODULE" || \
	fail 'license activation RPC must persist only the key to the private helper request'
grep -Fq 'build_activation_body()' "$LICENSE_HELPER" || \
	fail 'license helper must build the Hub activate device payload outside rpcd'
grep -Fq "'@.device.physical_fingerprint'" "$LICENSE_HELPER" || \
	fail 'license helper must reuse SafeShield authoritative physical fingerprint'
grep -Fq "LICENSE_HELPER + ' activate --request-file" "$LICENSE_MODULE" || \
	fail 'license activation RPC must launch the helper with a request file instead of a key argument'
grep -Fq 'activation_in_progress && return 0' "$LICENSE_HELPER" || \
	fail 'periodic license status sync must not race an explicit activation'
grep -Fq 'const ACTIVATION_STALE_S = 60;' "$LICENSE_MODULE" || \
	fail 'license RPC must recover abandoned activation locks after a bounded interval'
grep -Fq 'LICENSE_LOCAL_READ_FAILED' "$LICENSE_HELPER" || \
	fail 'SafeShield license read failures must be distinguishable from an unconfigured license'

grep -Fq "const BACKUP_HELPER = '/usr/libexec/smartsafehub-backup';" "$BACKUP_MODULE" || \
	fail 'configuration restore RPC must delegate privileged work to the dedicated backup helper'
grep -Fq "request.args.confirm != 'restore'" "$BACKUP_MODULE" || \
	fail 'configuration restore RPC must require an explicit confirmation token'
grep -Fq "status == 75" "$BACKUP_MODULE" || \
	fail 'configuration restore RPC must expose update/firmware busy state separately'
grep -Fq '"$SYSUPGRADE_BIN" --restore-backup "$BACKUP_FILE"' "$BACKUP_HELPER" || \
	fail 'configuration restore helper must use the OpenWrt sysupgrade restore path'
grep -Fq 'restore_is_busy && return 75' "$BACKUP_HELPER" || \
	fail 'configuration restore must not run while firmware or management update work is active'
grep -Fq 'current_build_id="$build_id"' "$BACKUP_HELPER" || \
	fail 'configuration restore must re-sync current firmware identity after applying an older backup'

grep -Fq "case 'iptime-a3004t':" "$FIRMWARE_MODULE" || \
	fail 'firmware RPC must accept iptime-a3004t as a supported device code'
grep -Fq "case 'iptime-ax3000se':" "$FIRMWARE_MODULE" || \
	fail 'firmware RPC must accept iptime-ax3000se as a supported device code'
grep -Fq "case 'iptime,a3004t':" "$FIRMWARE_MODULE" || \
	fail 'firmware RPC must map the A3004T OpenWrt board name'
grep -Fq "case 'iptime,ax3000se':" "$FIRMWARE_MODULE" || \
	fail 'firmware RPC must map the AX3000SE OpenWrt board name'
grep -Fq "return 'iptime-a3004t';" "$FIRMWARE_MODULE" || \
	fail 'firmware RPC must normalize A3004T to iptime-a3004t'
grep -Fq "return 'iptime-ax3000se';" "$FIRMWARE_MODULE" || \
	fail 'firmware RPC must normalize AX3000SE to iptime-ax3000se'

if grep -Eq '^[[:space:]]*(apk|"\$APK_BIN"|\$APK_BIN)[[:space:]]+upgrade([[:space:]]|$)' "$UPDATER"; then
	fail 'full-system apk upgrade must not be used by SmartSafeHub updater'
fi

grep -Fq '"$APK_BIN" upgrade "$UPDATE_PACKAGE"' "$UPDATER" || \
	fail 'updater must use targeted apk upgrade for luci-app-smartsafehub'

echo 'PASS: rpc registration, ACL permissions, backup restore and targeted package update contracts are consistent'
