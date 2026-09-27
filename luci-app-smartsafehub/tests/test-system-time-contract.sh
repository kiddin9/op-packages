#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
SYSTEM_MODULE="$ROOT_DIR/root/usr/share/rpcd/ucode/smartsafehub/system.uc"
RPC_ENTRY="$ROOT_DIR/root/usr/share/rpcd/ucode/smartsafehub.uc"
ACL="$ROOT_DIR/root/usr/share/rpcd/acl.d/luci-app-smartsafehub.json"
API="$ROOT_DIR/frontend/src/api/smartsafehub.ts"
HOOK="$ROOT_DIR/frontend/src/hooks/useSystemTimeSettings.ts"
SETTINGS_PAGE="$ROOT_DIR/frontend/src/pages/SettingsPage.tsx"
APP_STYLE="$ROOT_DIR/frontend/src/styles/app.css"

fail() {
	echo "FAIL: $*" >&2
	exit 1
}

for file in "$SYSTEM_MODULE" "$RPC_ENTRY" "$ACL" "$API" "$HOOK" "$SETTINGS_PAGE" "$APP_STYLE"; do
	[ -f "$file" ] || fail "missing system time source: ${file#$ROOT_DIR/}"
done

grep -Fq "defer_call('luci', 'getTimezones'" "$SYSTEM_MODULE" || \
	fail 'timezone choices must come from the OpenWrt/LuCI timezone database'
grep -Fq 'localtime: time(),' "$SYSTEM_MODULE" || \
	fail 'time settings must return a fresh router epoch for immediate-sync refreshes'
grep -Fq "ctx.set('system', section_name, 'zonename', requested_zonename)" "$SYSTEM_MODULE" || \
	fail 'timezone update must persist the IANA zonename'
grep -Fq "ctx.set('system', section_name, 'timezone', requested_timezone)" "$SYSTEM_MODULE" || \
	fail 'timezone update must persist the matching POSIX timezone string'
grep -Fq "ctx.commit('system')" "$SYSTEM_MODULE" || \
	fail 'timezone update must commit the system UCI configuration'
grep -Fq "run_command([ '/etc/init.d/system', 'reload' ], 5000)" "$SYSTEM_MODULE" || \
	fail 'timezone update must immediately reload the OpenWrt system timezone'
grep -Fq "SYSTEM_TIMEZONE_UNSUPPORTED" "$SYSTEM_MODULE" || \
	fail 'timezone update must reject names missing from the device timezone database'
grep -Fq "restore_system_time(" "$SYSTEM_MODULE" || \
	fail 'timezone update must restore the previous UCI values when runtime apply fails'

grep -Fq "const AUTO_INSTALL_MARKER = '/tmp/smartsafehub/updater-auto-date';" "$SYSTEM_MODULE" || \
	fail 'timezone changes must know the software auto-install day marker'
grep -Fq "fs.unlink(AUTO_INSTALL_MARKER);" "$SYSTEM_MODULE" || \
	fail 'timezone changes must clear the auto-install day marker'
grep -Fq "fs.unlink(AUTO_RETRY_MARKER);" "$SYSTEM_MODULE" || \
	fail 'timezone changes must clear stale auto-install retry timestamps'
grep -Fq '/etc/init.d/smartsafehub-updater restart' "$SYSTEM_MODULE" || \
	fail 'timezone changes must restart the software updater so schedules use the new local time'
grep -Fq "run_command([ MAINTENANCE_INIT, 'restart' ], 5000);" "$SYSTEM_MODULE" || \
	fail 'timezone changes must restart scheduled reboot maintenance so local-time schedules are recalculated immediately'

grep -Fq "export function sync_time(request)" "$SYSTEM_MODULE" || \
	fail 'system time module must expose an immediate NTP synchronization action'
grep -Fq "SYSTEM_NTP_DISABLED" "$SYSTEM_MODULE" || \
	fail 'immediate synchronization must fail clearly when NTP is disabled'
grep -Fq "run_command([ '/etc/init.d/sysntpd', 'restart' ], 5000)" "$SYSTEM_MODULE" || \
	fail 'immediate synchronization must restart OpenWrt sysntpd to trigger a fresh NTP request'
grep -Fq "SYSTEM_TIME_SYNC_FAILED" "$SYSTEM_MODULE" || \
	fail 'immediate synchronization must surface sysntpd restart failures'

grep -Eq '^[[:space:]]*system_time_settings:[[:space:]]*\{' "$RPC_ENTRY" || \
	fail 'system_time_settings RPC must be registered'
grep -Eq '^[[:space:]]*system_timezone_update:[[:space:]]*\{' "$RPC_ENTRY" || \
	fail 'system_timezone_update RPC must be registered'
grep -Eq '^[[:space:]]*system_time_sync:[[:space:]]*\{' "$RPC_ENTRY" || \
	fail 'system_time_sync RPC must be registered'
jq -e '."luci-app-smartsafehub".read.ubus.smartsafehub | index("system_time_settings") != null' "$ACL" >/dev/null || \
	fail 'system_time_settings must be granted read ACL access'
jq -e '."luci-app-smartsafehub".write.ubus.smartsafehub | index("system_timezone_update") != null' "$ACL" >/dev/null || \
	fail 'system_timezone_update must be granted write ACL access'
jq -e '."luci-app-smartsafehub".write.ubus.smartsafehub | index("system_time_sync") != null' "$ACL" >/dev/null || \
	fail 'system_time_sync must be granted write ACL access'

grep -Fq "callApi(API_OBJECT, 'system_time_settings')" "$API" || \
	fail 'frontend must read timezone settings through the SmartSafeHub RPC API'
grep -Fq "callApi(API_OBJECT, 'system_timezone_update', { zonename })" "$API" || \
	fail 'frontend must update timezone through the SmartSafeHub RPC API'
grep -Fq "callApi(API_OBJECT, 'system_time_sync')" "$API" || \
	fail 'frontend must request immediate NTP synchronization through SmartSafeHub RPC'
grep -Fq 'export function useSystemTimeSettings(active: boolean)' "$HOOK" || \
	fail 'timezone settings need a dedicated frontend resource hook'
grep -Fq 'resource.replaceData(result);' "$HOOK" || \
	fail 'successful timezone writes must refresh local timezone state without a page reload'
grep -Fq 'await requestSystemTimeSync();' "$HOOK" || \
	fail 'system time hook must expose immediate NTP synchronization'
grep -Fq 'window.setTimeout(resolve, 1500);' "$HOOK" || \
	fail 'system time hook must allow the restarted NTP client time to refresh the clock before rereading it'
grep -Fq 'const result = await fetchSystemTimeSettings();' "$HOOK" || \
	fail 'immediate synchronization must reread the router clock after the NTP request'

grep -Fq 'title="시간 및 시간대"' "$SETTINGS_PAGE" || \
	fail 'settings UI must expose a dedicated time and timezone card'
grep -Fq 'ariaLabel="시간대"' "$SETTINGS_PAGE" || \
	fail 'timezone custom dropdown must have an accessible label'
grep -Fq '브라우저 시간대 사용' "$SETTINGS_PAGE" || \
	fail 'settings UI must offer the matching browser timezone as a convenience'
grep -Fq '자동 설치와 예약 재부팅 일정도 새 기준 시간으로 다시 계산합니다.' "$SETTINGS_PAGE" || \
	fail 'timezone UI must explain the effect on scheduled software updates'
grep -Fq "props.data?.ntpEnabled ? '자동 동기화 설정됨' : '자동 동기화 꺼짐'" "$SETTINGS_PAGE" || \
	fail 'timezone UI must surface NTP synchronization state'
grep -Fq "{props.syncing ? '동기화 요청 중' : '지금 동기화'}" "$SETTINGS_PAGE" || \
	fail 'timezone UI must expose an explicit immediate synchronization action'
grep -Fq 'disabled={!props.data?.ntpEnabled || props.saving || props.syncing}' "$SETTINGS_PAGE" || \
	fail 'immediate synchronization must be unavailable when NTP is disabled or another time mutation is active'

grep -Fq '<CustomSelect' "$SETTINGS_PAGE" || \
	fail 'timezone settings must use the shared SmartSafeHub custom dropdown'
grep -Fq 'id="smartsafehub-timezone"' "$SETTINGS_PAGE" || \
	fail 'timezone custom dropdown must preserve its stable control id'
grep -Fq "zones.map((zone) => ({ value: zone, label: zone }))" "$SETTINGS_PAGE" || \
	fail 'timezone custom dropdown must expose every supported timezone option'

echo 'PASS: timezone selection, immediate NTP sync, custom dropdown and scheduled-update recalculation contracts are consistent'
