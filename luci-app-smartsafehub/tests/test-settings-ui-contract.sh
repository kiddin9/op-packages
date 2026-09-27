#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
APP="$ROOT_DIR/frontend/src/app/App.tsx"
ROUTES="$ROOT_DIR/frontend/src/app/routes.ts"
SETTINGS_PAGE="$ROOT_DIR/frontend/src/pages/SettingsPage.tsx"
APP_STYLES="$ROOT_DIR/frontend/src/styles/app.css"
UPDATE_PAGE="$ROOT_DIR/frontend/src/pages/UpdatePage.tsx"
NAVIGATION="$ROOT_DIR/frontend/src/components/ProductNavigation.tsx"
TIME_HOOK="$ROOT_DIR/frontend/src/hooks/useSystemTimeSettings.ts"
SCHEDULE_HOOK="$ROOT_DIR/frontend/src/hooks/useScheduledRebootSettings.ts"
BACKUP_HOOK="$ROOT_DIR/frontend/src/hooks/useConfigurationBackup.ts"
BACKUP_API="$ROOT_DIR/frontend/src/api/configurationBackup.ts"
HEALTH_HOOK="$ROOT_DIR/frontend/src/hooks/useHealth.ts"

fail() {
	echo "FAIL: $*" >&2
	exit 1
}

for file in "$APP" "$ROUTES" "$SETTINGS_PAGE" "$APP_STYLES" "$UPDATE_PAGE" "$NAVIGATION" "$TIME_HOOK" "$SCHEDULE_HOOK" "$BACKUP_HOOK" "$BACKUP_API" "$HEALTH_HOOK"; do
	[ -f "$file" ] || fail "missing settings split source: ${file#$ROOT_DIR/}"
done

grep -Fq "const status = useStatus(route === 'home' || route === 'settings');" "$APP" || \
	fail 'system status polling must remain active on settings'
grep -Fq "const systemTime = useSystemTimeSettings(route === 'settings');" "$APP" || \
	fail 'settings route must load dedicated timezone settings'
grep -Fq "const scheduledReboot = useScheduledRebootSettings(route === 'settings');" "$APP" || \
	fail 'settings route must load scheduled reboot settings'
grep -Fq "route === 'system' || route === 'home' || route === 'settings'" "$APP" || \
	fail 'settings route must load cached SmartSafeHub firmware identity'
grep -Fq 'firmware={firmware.data}' "$APP" || \
	fail 'settings page must receive SmartSafeHub firmware status'
grep -Fq 'firmwareError={firmware.error}' "$APP" || \
	fail 'settings page must receive firmware status errors'
grep -Fq 'firmwareLoading={firmware.loading}' "$APP" || \
	fail 'settings page must receive firmware loading state'
grep -Fq 'const configurationBackup = useConfigurationBackup();' "$APP" || \
	fail 'settings route must wire configuration backup and restore actions'
grep -Fq "case 'system':" "$APP" || fail 'update route must remain registered in App'
grep -Fq '<UpdatePage' "$APP" || fail 'system/update route must render UpdatePage'
grep -Fq "case 'settings':" "$APP" || fail 'settings route must be registered in App'
grep -Fq '<SettingsPage' "$APP" || fail 'settings route must render SettingsPage'
grep -Fq "if (route === 'system')" "$APP" || fail 'update refresh branch must exist'
grep -Fq 'void Promise.all([updates.refresh(), firmware.refresh()]);' "$APP" || fail 'update refresh must refresh software and firmware updater state together'
grep -Fq "if (route === 'settings')" "$APP" || fail 'settings refresh branch must exist'
grep -Fq 'scheduledReboot.refresh(),' "$APP" || \
	fail 'settings refresh must refresh scheduled reboot settings together with system/time state'
grep -Fq 'firmware.refresh(),' "$APP" || \
	fail 'settings refresh must refresh firmware identity together with system state'

grep -Fq "label: '설정'" "$ROUTES" || fail 'settings route must be visible in product navigation'
grep -Fq "description: '기기의 펌웨어와 관리 소프트웨어 업데이트를 관리합니다.'" "$ROUTES" || \
	fail 'update route description must remain update-only'
grep -Fq "description: '시스템 상태와 시간대를 확인하고 장치 관리 및 진단 기능을 설정합니다.'" "$ROUTES" || \
	fail 'settings route description must describe timezone and device management'

if grep -Fq 'title="업데이트 관리"' "$SETTINGS_PAGE"; then
	fail 'settings page must not duplicate the dedicated update-page navigation card'
fi
if grep -Fq 'href="#system"' "$SETTINGS_PAGE"; then
	fail 'settings page must not retain a redundant update-page shortcut'
fi
grep -Fq 'title="시간 및 시간대"' "$SETTINGS_PAGE" || \
	fail 'settings page must expose time and timezone controls'
grep -Fq "'지금 동기화'" "$SETTINGS_PAGE" || \
	fail 'settings page must expose immediate NTP synchronization'
grep -Fq 'title="진단 및 지원"' "$SETTINGS_PAGE" || \
	fail 'diagnostic download must be grouped as diagnostic and support functionality'
grep -Fq '원격 상태 보고' "$SETTINGS_PAGE" || \
	fail 'settings diagnostics must expose paid/trial remote health reporting'
grep -Fq '기본값은 꺼짐이며 언제든지 다시 끌 수 있습니다.' "$SETTINGS_PAGE" || \
	fail 'remote health reporting must be explicit opt-in with opt-out copy'
grep -Fq "const health = useHealth(route === 'home' || route === 'settings');" "$APP" || \
	fail '설정 페이지와 대시보드가 같은 로컬 Health 리소스를 불러와야 합니다'
grep -Fq 'title="설정 백업 및 복원"' "$SETTINGS_PAGE" || \
	fail 'settings page must expose first-class configuration backup and restore management'
grep -Fq '설정 백업 다운로드' "$SETTINGS_PAGE" || \
	fail 'settings page must expose native configuration backup download'
grep -Fq '업로드 및 검증' "$SETTINGS_PAGE" || \
	fail 'restore flow must upload and validate an archive before confirmation'
grep -Fq '설정 복원 및 재부팅' "$SETTINGS_PAGE" || \
	fail 'restore flow must clearly communicate the reboot side effect'
grep -Fq 'Wi-Fi 비밀번호, 관리자 설정, VPN 키나 라이선스 정보' "$SETTINGS_PAGE" || \
	fail 'backup UI must warn that preserved configuration can contain secrets'
grep -Fq 'function ScheduledRebootSection(props:' "$SETTINGS_PAGE" || \
	fail 'settings page must expose scheduled reboot management as an embedded section'
grep -Fq 'aria-labelledby="scheduled-reboot-heading"' "$SETTINGS_PAGE" || \
	fail 'scheduled reboot section must expose an accessible section label'
if ! sed -n '/^function TimeSettingsCard/,/^function healthTone/p' "$SETTINGS_PAGE" | grep -F '<ScheduledRebootSection' >/dev/null; then
	fail 'scheduled reboot controls must be grouped inside the time and timezone card'
fi
grep -Fq 'scheduledRebootData={scheduledRebootData}' "$SETTINGS_PAGE" || \
	fail 'time settings card must receive scheduled reboot state'
if grep -Fq '<ScheduledRebootCard' "$SETTINGS_PAGE"; then
	fail 'scheduled reboot must not remain as a standalone system-management card'
fi
grep -Fq ".ssh-app[data-theme='dark'] [class~='bg-slate-50']" "$APP_STYLES" || \
	fail 'scheduled reboot inset background must retain a dark-theme mapping'
grep -Fq ".ssh-app[data-theme='dark'] [class~='bg-slate-100']" "$APP_STYLES" || \
	fail 'scheduled reboot section icon background must retain a dark-theme mapping'
grep -Fq "[class~='border-slate-200']" "$APP_STYLES" || \
	fail 'scheduled reboot divider must retain a dark-theme border mapping'
grep -Fq "[class~='text-slate-500']" "$APP_STYLES" || \
	fail 'scheduled reboot secondary text must retain dark-theme contrast mapping'
grep -Fq '저장되지 않음' "$SETTINGS_PAGE" || \
	fail 'scheduled reboot must visibly mark unsaved local changes'
grep -Fq 'role="status"' "$SETTINGS_PAGE" || \
	fail 'scheduled reboot unsaved marker must expose status semantics'
grep -Fq 'aria-live="polite"' "$SETTINGS_PAGE" || \
	fail 'scheduled reboot unsaved marker must announce state changes without interrupting the user'
grep -Fq 'border-amber-200 bg-amber-50' "$SETTINGS_PAGE" || \
	fail 'scheduled reboot unsaved marker must use warning styling rather than error styling'
grep -Fq ".ssh-app[data-theme='dark'] [class~='bg-amber-50']" "$APP_STYLES" || \
	fail 'scheduled reboot unsaved marker background must retain a dark-theme mapping'
grep -Fq "[class~='text-amber-800']" "$APP_STYLES" || \
	fail 'scheduled reboot unsaved marker text must retain dark-theme contrast mapping'
grep -Fq 'function SystemToolsCard(props:' "$SETTINGS_PAGE" || \
	fail 'reboot and advanced actions must be grouped into one compact system tools card'
grep -Fq 'title="시스템 도구"' "$SETTINGS_PAGE" || \
	fail 'system management must expose the combined system tools card'
grep -Fq 'aria-labelledby="router-reboot-heading"' "$SETTINGS_PAGE" || \
	fail 'router reboot must remain an accessible first-class action inside system tools'
grep -Fq 'id="advanced-tools-heading"' "$SETTINGS_PAGE" || \
	fail 'advanced tools must remain clearly labeled inside system tools'
grep -Fq '고급 도구' "$SETTINGS_PAGE" || \
	fail 'advanced LuCI and log actions must remain visible inside system tools'
if grep -Fq 'title="공유기 재부팅"' "$SETTINGS_PAGE"; then
	fail 'router reboot must not remain as a separate full ActionCard'
fi
if grep -Fq 'title="고급 설정"' "$SETTINGS_PAGE"; then
	fail 'advanced settings must not remain as a separate full ActionCard'
fi
grep -Fq "luciAdminUrl('/admin/system')" "$SETTINGS_PAGE" || \
	fail 'SettingsPage must retain the LuCI advanced-settings fallback'
grep -Fq 'LuCI 고급 설정 열기' "$SETTINGS_PAGE" || \
	fail 'LuCI fallback must be explicitly presented as an advanced action'
grep -Fq 'SmartSafeHub에서 아직 제공하지 않는 상세 시스템 설정이나 원본 로그' "$SETTINGS_PAGE" || \
	fail 'settings page must explain why LuCI fallback still exists'
if grep -Fq '설정 백업·복원 등 아직 SmartSafeHub에서 제공하지 않는' "$SETTINGS_PAGE"; then
	fail 'settings page must not send backup and restore users back to stock LuCI'
fi
if grep -Fq "luciAdminUrl('/admin/system/flash')" "$SETTINGS_PAGE"; then
	fail 'settings page must not send firmware upgrades to the stock LuCI flash page'
fi
if grep -Fq '고급 설정' "$NAVIGATION"; then
	fail 'navigation chrome must not keep the old standalone advanced-settings menu'
fi
if grep -Fq 'SoftwareUpdatesCard' "$SETTINGS_PAGE"; then
	fail 'settings page must not embed the software update experience'
fi

grep -Fq "const customFirmwareAvailable = Boolean(firmware?.current.metadataAvailable);" "$SETTINGS_PAGE" || \
	fail 'settings system status must detect SmartSafeHub custom firmware metadata'
grep -Fq '`SmartSafeHub ${firmware.current.releaseVersion}`' "$SETTINGS_PAGE" || \
	fail 'settings system status must prefer the SmartSafeHub product firmware version'
grep -Fq '`빌드 ID ${firmware.current.buildId}`' "$SETTINGS_PAGE" || \
	fail 'settings system status must show the immutable SmartSafeHub build ID'
grep -Fq '`${data.software.distribution} ${data.software.version}`' "$SETTINGS_PAGE" || \
	fail 'settings system status must retain OpenWrt firmware fallback for legacy images'
grep -Fq '`리비전 ${data.software.revision}`' "$SETTINGS_PAGE" || \
	fail 'settings system status must retain OpenWrt revision fallback for legacy images'
grep -Fq '`커널 ${data.software.kernel}`' "$SETTINGS_PAGE" || \
	fail 'settings system status must keep the actual running kernel version'
grep -Fq 'Device settings' "$SETTINGS_PAGE" || \
	fail 'settings page must visually separate device settings from system management'
grep -Fq '시간 기준과 예약 재부팅, 진단 정보를 SmartSafeHub에서 직접 관리합니다.' "$SETTINGS_PAGE" || \
	fail 'device settings description must include scheduled reboot after regrouping'
grep -Fq 'System management' "$SETTINGS_PAGE" || \
	fail 'settings page must retain a dedicated system management section'
grep -Fq 'grid min-w-0 grid-cols-1 gap-4 lg:grid-cols-2' "$SETTINGS_PAGE" || \
	fail 'settings action groups must use responsive two-column layout on desktop'
if sed -n '/^function ConfigurationBackupCard/,/^function SystemToolsCard/p' "$SETTINGS_PAGE" | grep -F 'className="lg:col-span-2"' >/dev/null; then
	fail 'configuration backup must share the desktop row instead of spanning both columns'
fi
sed -n '/^function ConfigurationBackupCard/,/^function SystemToolsCard/p' "$SETTINGS_PAGE" | grep -F 'grid min-w-0 grid-cols-1 gap-3' >/dev/null || \
	fail 'configuration backup internals must use a compact vertical layout at half-row width'
grep -Fq '<SystemToolsCard' "$SETTINGS_PAGE" || \
	fail 'system management must render the combined system tools card beside backup/restore'

grep -Fq "const BACKUP_DOWNLOAD_ENDPOINT = '/cgi-backup';" "$BACKUP_API" || \
	fail 'backup downloads must use the authenticated cgi-backup endpoint'
grep -Fq "const BACKUP_UPLOAD_PATH = '/tmp/smartsafehub/config-backup.tar.gz';" "$BACKUP_API" || \
	fail 'restore uploads must target the dedicated temporary archive path'
grep -Fq 'await requestConfigurationBackupValidation(file.name);' "$BACKUP_HOOK" || \
	fail 'uploaded backups must be validated by the backend before restore is enabled'
grep -Fq 'if (!validated)' "$BACKUP_HOOK" || \
	fail 'restore hook must reject attempts without a validated archive'

echo 'PASS: settings page keeps backup/restore, timezone and device management with safe system controls'
