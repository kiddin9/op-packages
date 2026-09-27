#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
UPDATES_CARD="$ROOT_DIR/frontend/src/components/SoftwareUpdatesCard.tsx"
FIRMWARE_CARD="$ROOT_DIR/frontend/src/components/FirmwareUpdatesCard.tsx"
FIRMWARE_HOOK="$ROOT_DIR/frontend/src/hooks/useFirmwareUpdates.ts"
FIRMWARE_UPLOAD="$ROOT_DIR/frontend/src/api/firmwareUpload.ts"
FIRMWARE_TYPES="$ROOT_DIR/frontend/src/types/firmware.ts"
FIRMWARE_RPC="$ROOT_DIR/root/usr/share/rpcd/ucode/smartsafehub/firmware.uc"
LUCI_UTIL="$ROOT_DIR/frontend/src/utils/luci.ts"
UPDATE_PAGE="$ROOT_DIR/frontend/src/pages/UpdatePage.tsx"
SETTINGS_PAGE="$ROOT_DIR/frontend/src/pages/SettingsPage.tsx"
UPDATES_HOOK="$ROOT_DIR/frontend/src/hooks/useSoftwareUpdates.ts"
ASYNC_RESOURCE="$ROOT_DIR/frontend/src/hooks/useAsyncResource.ts"
APP_CSS="$ROOT_DIR/frontend/src/styles/app.css"
TIME_SELECT="$ROOT_DIR/frontend/src/components/TimeSelect.tsx"
RUNTIME_APP_JS="$ROOT_DIR/root/www/luci-static/smartsafehub/app.js"
RUNTIME_APP_CSS="$ROOT_DIR/root/www/luci-static/smartsafehub/app.css"
UPDATE_FRESHNESS="$ROOT_DIR/frontend/src/utils/softwareUpdates.ts"

fail() {
	echo "FAIL: $*" >&2
	exit 1
}

for file in "$UPDATES_CARD" "$FIRMWARE_CARD" "$FIRMWARE_HOOK" "$FIRMWARE_UPLOAD" "$FIRMWARE_TYPES" "$FIRMWARE_RPC" "$UPDATE_PAGE" "$SETTINGS_PAGE" "$UPDATES_HOOK" "$ASYNC_RESOURCE" "$APP_CSS" "$TIME_SELECT" "$RUNTIME_APP_JS" "$RUNTIME_APP_CSS" "$UPDATE_FRESHNESS"; do
	[ -f "$file" ] || fail "missing required file: ${file#$ROOT_DIR/}"
done

# Firmware and management software must read as separate update products.
grep -Fq '관리 소프트웨어 업데이트' "$UPDATES_CARD" || \
	fail 'software update card must use the management-software product heading'
grep -Fq 'Management software' "$UPDATES_CARD" || \
	fail 'software update card must use the management-software eyebrow'
if grep -Fq '>SmartSafeHub 업데이트</h2>' "$UPDATES_CARD"; then
	fail 'SmartSafeHub product name must not be used as the software update category heading'
fi
for label in Installed Available 'Last check' 'Auto install'; do
	grep -Fq "$label" "$UPDATES_CARD" || \
		fail "update summary must include $label"
done

grep -Fq '업데이트 확인' "$UPDATES_CARD" || \
	fail 'update card must provide an explicit check action'
grep -Fq 'ReloadIcon class="size-4"' "$UPDATES_CARD" || \
	fail 'update card check actions must use the shared reload icon'
if grep -Fq 'LoaderIcon' "$UPDATES_CARD" || grep -Fq 'RefreshIcon' "$UPDATES_CARD"; then
	fail 'update card must not mix legacy loading or refresh icons'
fi
grep -Fq '업데이트 설치' "$UPDATES_CARD" || \
	fail 'update card must provide an explicit install action'

# Product descriptions should stay compact on desktop instead of leaving a short orphaned line.
grep -Fq '시스템 펌웨어를 확인하고 설치합니다. 온라인·수동 설치는 안전성 검증 후 진행됩니다.' "$FIRMWARE_CARD" || \
	fail 'firmware update card must use the compact customer-facing description'
grep -Fq 'text-slate-500 lg:whitespace-nowrap' "$FIRMWARE_CARD" || \
	fail 'firmware description must stay on one line when the desktop card has enough width'
grep -Fq '새 버전을 확인하고 안전하게 설치합니다.' "$UPDATES_CARD" || \
	fail 'management software card must use the compact customer-facing description'
grep -Fq 'text-slate-500 xl:whitespace-nowrap' "$UPDATES_CARD" || \
	fail 'management software description must stay on one line in the wide two-column layout'
if grep -Fq 'SmartSafeHub 기기의 시스템 펌웨어를 확인하고 설치합니다. 온라인 업데이트와 수동 파일 설치 모두 안전성 검증을 통과한 경우에만 진행할 수 있습니다.' "$FIRMWARE_CARD"; then
	fail 'firmware update card must not keep the long wrapping description'
fi
if grep -Fq 'SmartSafeHub 관리 화면과 관련 소프트웨어의 새 버전을 확인하고 안전하게 설치합니다.' "$UPDATES_CARD"; then
	fail 'management software card must not keep the long wrapping description'
fi

# Manual firmware safety guidance should use the full card width on desktop and avoid an orphaned second line.
grep -Fq 'class="mt-0 mb-4 text-xs leading-5 text-slate-500 lg:whitespace-nowrap"' "$FIRMWARE_CARD" || \
	fail 'manual firmware safety guidance must stay on one line in the desktop layout'
if grep -Fq 'class="mt-0 mb-4 max-w-3xl text-xs leading-5 text-slate-500"' "$FIRMWARE_CARD"; then
	fail 'manual firmware safety guidance must not keep the narrow max-width that forces wrapping'
fi

# Management-software status and automatic settings belong to one responsive card.
grep -Fq 'data-component="management-software-update-card"' "$UPDATES_CARD" || \
	fail 'management software must render as one product card'
grep -Fq 'data-layout="management-software-sections"' "$UPDATES_CARD" || \
	fail 'management software card must declare its responsive status/settings layout'
grep -Fq "xl:grid-cols-[minmax(0,0.95fr)_minmax(0,1.05fr)]" "$UPDATES_CARD" || \
	fail 'management software card must become a two-column layout on wide screens'
grep -Fq 'data-section="software-update-status"' "$UPDATES_CARD" || \
	fail 'management software card must contain a current-status section'
grep -Fq '>현재 상태</h3>' "$UPDATES_CARD" || \
	fail 'management software status section must have a customer-facing title'
grep -Fq 'data-section="software-update-settings"' "$UPDATES_CARD" || \
	fail 'management software card must contain automatic-update settings'
grep -Fq '>자동 업데이트</h3>' "$UPDATES_CARD" || \
	fail 'automatic update can use the short title only inside the management-software card'
if grep -Fq 'data-section="software-update-scope"' "$UPDATES_CARD"; then
	fail 'scope warning should not be needed once automatic update is nested under management software'
fi
if grep -Fq 'SmartSafeHub 자동 업데이트' "$UPDATES_CARD"; then
	fail 'automatic update title must not reuse the SmartSafeHub product name as an update category'
fi
software_status_line="$(grep -n -m1 'data-section="software-update-status"' "$UPDATES_CARD" | cut -d: -f1)"
software_settings_line="$(grep -n -m1 'data-section="software-update-settings"' "$UPDATES_CARD" | cut -d: -f1)"
software_card_close_line="$(grep -n '</article>' "$UPDATES_CARD" | tail -1 | cut -d: -f1)"
[ "$software_status_line" -lt "$software_settings_line" ] || \
	fail 'management software status must precede automatic-update settings'
[ "$software_settings_line" -lt "$software_card_close_line" ] || \
	fail 'automatic-update settings must stay inside the management-software card'
grep -Fq 'data-section="software-update-result"' "$UPDATES_CARD" || \
	fail 'management software card must keep the latest/not-checked result inline'

# Nested automatic-update controls must size from their actual card width on tablet
# landscape. iPadOS browsers all use WebKit, whose localized native time control
# can keep an intrinsic width larger than the card, so product time settings must
# use the shared custom time selector instead of input[type="time"].
grep -Fq 'ssh-software-settings-grid mt-4' "$UPDATES_CARD" || \
	fail 'automatic-update settings must use the container-width responsive grid'
grep -Fq 'ssh-software-settings-channel rounded-xl' "$UPDATES_CARD" || \
	fail 'update channel must span all responsive settings-grid columns'
grep -Fq 'grid-template-columns: repeat(auto-fit, minmax(min(100%, 18rem), 1fr));' "$APP_CSS" || \
	fail 'automatic-update settings grid must wrap according to its own available width'
grep -Fq '.ssh-software-settings-channel {' "$APP_CSS" || \
	fail 'responsive settings grid must preserve the full-width update-channel row'
grep -Fq '<TimeSelect' "$UPDATES_CARD" || \
	fail 'automatic install time must use the shared custom time selector'
grep -Fq 'id="software-update-auto-install-time"' "$UPDATES_CARD" || \
	fail 'automatic install time selector must expose a stable id prefix'
grep -Fq '<TimeSelect' "$SETTINGS_PAGE" || \
	fail 'scheduled reboot time must use the shared custom time selector'
grep -Fq 'id="scheduled-reboot-time"' "$SETTINGS_PAGE" || \
	fail 'scheduled reboot time selector must preserve its stable id prefix'
if grep -Fq 'type="time"' "$UPDATES_CARD" || grep -Fq 'type="time"' "$SETTINGS_PAGE"; then
	fail 'native time inputs must not be reintroduced because iPadOS WebKit can overflow narrow cards'
fi
grep -Fq 'const HOUR_OPTIONS = Array.from({ length: 24 }' "$TIME_SELECT" || \
	fail 'shared time selector must provide every hour'
grep -Fq 'const MINUTE_OPTIONS = Array.from({ length: 60 }' "$TIME_SELECT" || \
	fail 'shared time selector must preserve minute-level scheduling precision'
grep -Fq 'grid-template-columns: repeat(2, minmax(0, 1fr));' "$APP_CSS" || \
	fail 'shared time selector tracks must remain shrinkable inside narrow cards'
grep -Fq '.ssh-time-select .ssh-custom-select-trigger {' "$APP_CSS" || \
	fail 'shared time selector must bound its custom dropdown triggers'
grep -Fq 'ssh-software-settings-grid' "$RUNTIME_APP_JS" || \
	fail 'production app.js must include the responsive software settings markup'
grep -Fq 'software-update-auto-install-time' "$RUNTIME_APP_JS" || \
	fail 'production app.js must include the custom automatic-install time selector'
# The production bundle is minified, so local variable names such as `id` are not a
# stable contract. Verify the derived trigger id in the source component instead.
grep -Fq 'id={`${id}-hour`}' "$TIME_SELECT" || \
	fail 'shared time selector must derive a stable hour trigger id'
grep -Fq 'scheduled-reboot-time-hour' "$RUNTIME_APP_JS" || \
	fail 'production app.js must include the custom scheduled-reboot hour selector'
grep -Fq '.ssh-software-settings-grid' "$RUNTIME_APP_CSS" || \
	fail 'production app.css must include the responsive software settings grid'
grep -Fq '.ssh-time-select' "$RUNTIME_APP_CSS" || \
	fail 'production app.css must include the shared custom time-selector layout'
if grep -Fq 'ssh-software-update-time-input' "$RUNTIME_APP_JS" || grep -Fq 'ssh-software-update-time-input' "$RUNTIME_APP_CSS"; then
	fail 'obsolete native software-update time-input workaround must not remain in production assets'
fi
if grep -Fq 'class="mt-4 grid gap-4 lg:grid-cols-2"' "$UPDATES_CARD"; then
	fail 'automatic-update nested grid must not use a viewport-only two-column breakpoint'
fi

# Busy update work should have persistent visual feedback rather than relying on hover text.
grep -Fq "const installing = action === 'install' || data?.phase === 'installing';" "$UPDATES_CARD" || \
	fail 'update card must track installing state explicitly'
grep -Fq 'function updatePhaseIcon(data: SoftwareUpdateStatus, stale: boolean)' "$UPDATES_CARD" || \
	fail 'update card must provide an explicit status icon for each update phase and stale state'
grep -Fq 'ReloadIcon class="size-3.5 shrink-0 animate-spin"' "$UPDATES_CARD" || \
	fail 'checking/installing status badge must spin the shared reload icon'
grep -Fq "{installing ? '설치 중...' : '업데이트 설치'}" "$UPDATES_CARD" || \
	fail 'install button must expose an installing label'
grep -Fq 'aria-busy="true"' "$UPDATES_CARD" || \
	fail 'installing update panel must expose busy state to assistive technology'
grep -Fq 'ssh-update-progress-track' "$UPDATES_CARD" || \
	fail 'installing update panel must include indeterminate progress feedback'
grep -Fq '설치가 완료되면 이 화면이 자동으로 갱신됩니다.' "$UPDATES_CARD" || \
	fail 'installing copy must explain automatic status refresh'
grep -Fq '@keyframes ssh-update-progress' "$APP_CSS" || \
	fail 'update progress indicator must define an indeterminate animation'
if grep -Fq '완료 후 화면을 새로고침해 주세요.' "$UPDATES_HOOK"; then
	fail 'install start feedback must not ask the user to refresh manually'
fi

# Repository and install failures should show product-friendly summaries while preserving raw details.
grep -Fq "error.code === 'UPDATES_INDEX_REFRESH_FAILED'" "$UPDATES_CARD" || \
	fail 'repository refresh errors must have a dedicated product summary'
grep -Fq '패키지 저장소를 확인하지 못했습니다.' "$UPDATES_CARD" || \
	fail 'repository errors must render a user-facing summary'
grep -Fq '상세 정보 보기' "$UPDATES_CARD" || \
	fail 'raw updater failure details must stay available behind a disclosure'
grep -Fq 'phase, lastError: null' "$UPDATES_HOOK" || \
	fail 'starting a new update action must clear stale failure feedback immediately'
grep -Fq '{data.lastError.message}' "$UPDATES_CARD" || \
	fail 'raw updater error must remain available in the details disclosure'

# An unchecked repository state must stay neutral and must not be presented as current.
grep -Fq "return data.lastCheckAt ? '최신 상태' : '확인 전';" "$UPDATES_CARD" || \
	fail 'update badge must distinguish unchecked state from current state'
grep -Fq "if (stale)" "$UPDATES_CARD" || \
	fail 'stale management-software checks must override the green current-state badge'
grep -Fq "return '업데이트 확인 지연';" "$UPDATES_CARD" || \
	fail 'stale management-software checks must be labeled as delayed'
grep -Fq 'isSoftwareUpdateCheckStale(data)' "$UPDATES_CARD" || \
	fail 'update page must use the shared software-update freshness rule'
grep -Fq 'data.settings.checkIntervalSeconds * 2' "$UPDATE_FRESHNESS" || \
	fail 'software-update freshness helper must use twice the configured check interval'
grep -Fq 'MINIMUM_STALE_THRESHOLD_SECONDS = 7_200' "$UPDATE_FRESHNESS" || \
	fail 'software-update freshness helper must preserve the two-hour minimum stale threshold'
grep -Fq '업데이트 확인이 지연되고 있습니다.' "$UPDATES_CARD" || \
	fail 'stale update page must explain that automatic checking is delayed'
grep -Fq "? '확인 필요'" "$UPDATES_CARD" || \
	fail 'stale available-version summary must not claim the repository is current'
grep -Fq "if (!data.lastCheckAt)" "$UPDATES_CARD" || \
	fail 'unchecked update badge must use a dedicated neutral style'
grep -Fq "? '미확인'" "$UPDATES_CARD" || \
	fail 'available version must remain unknown before the first successful check'
grep -Fq "data.lastError?.code === 'UPDATES_INDEX_REFRESH_FAILED'" "$UPDATES_CARD" || \
	fail 'repository refresh failure must keep unavailable version information explicitly unknown'
grep -Fq "repositoryCheckFailed && !currentPackage?.updateAvailable" "$UPDATES_CARD" || \
	fail 'failed repository refresh must not present an unknown available version as current'
grep -Fq 'data && data.updateCount === 0 && data.lastCheckAt ? (' "$UPDATES_CARD" || \
	fail 'current-version success notice must require a completed update check'
grep -Fq '업데이트 상태를 아직 확인하지 않았습니다.' "$UPDATES_CARD" || \
	fail 'unchecked update state must render a neutral explanatory notice'
grep -Fq 'ReloadIcon class="size-5"' "$UPDATES_CARD" || \
	fail 'unchecked update state notice must use the shared reload icon'
grep -Fq '지금 확인' "$UPDATES_CARD" || \
	fail 'unchecked update state must offer an explicit check action'

# Scheduled update controls use the shared emphasized SmartSafeHub form surface.
grep -Fq '<CustomSelect' "$UPDATES_CARD" || \
	fail 'update interval must use the shared custom dropdown'
grep -Fq 'id="software-update-check-interval"' "$UPDATES_CARD" || \
	fail 'update interval custom dropdown must expose a stable control id'
grep -Fq 'variant="emphasized"' "$UPDATES_CARD" || \
	fail 'update interval custom dropdown must use the emphasized form-control surface'
grep -Fq 'ariaLabel="자동 업데이트 설치 시각"' "$UPDATES_CARD" || \
	fail 'auto-install time selector must expose an accessible product label'
grep -Fq 'variant="emphasized"' "$UPDATES_CARD" || \
	fail 'auto-install time selector must use the emphasized custom-select surface'

# Unsaved automatic-update edits must be visible and reversible before saving.
grep -Fq 'const hasSettingsChanges = (next: Partial<SoftwareUpdateSettingsInput> = {}) =>' "$UPDATES_CARD" || \
	fail 'automatic update settings must compare edited values with persisted settings'
grep -Fq 'if (!data || settingsDirty)' "$UPDATES_CARD" || \
	fail 'background update status refresh must not overwrite unsaved automatic-update edits'
grep -Fq 'setSettingsDirty(hasSettingsChanges({ checkEnabled: checked }))' "$UPDATES_CARD" || \
	fail 'automatic update switch changes must derive dirty state from persisted values'
grep -Fq 'hasSettingsChanges({ autoInstallTime: nextAutoInstallTime })' "$UPDATES_CARD" || \
	fail 'automatic update time changes must derive dirty state from persisted values'
grep -Fq '{settingsDirty ? (' "$UPDATES_CARD" || \
	fail 'automatic update settings must render an unsaved marker only while edited'
grep -Fq '저장되지 않음' "$UPDATES_CARD" || \
	fail 'automatic update settings must warn when local changes have not been saved'
grep -Fq '<AlertIcon aria-hidden="true" class="size-3.5 shrink-0" />' "$UPDATES_CARD" || \
	fail 'automatic update unsaved state must include a warning icon'
grep -Fq 'aria-live="polite"' "$UPDATES_CARD" || \
	fail 'automatic update unsaved state must announce state changes without interrupting the user'
grep -Fq 'role="status"' "$UPDATES_CARD" || \
	fail 'automatic update unsaved marker must expose status semantics'
grep -Fq "disabled={!settingsDirty || action === 'settings' || busy}" "$UPDATES_CARD" || \
	fail 'automatic update save action must remain disabled until settings change'
grep -Fq ".ssh-app[data-theme='dark'] [class~='bg-amber-50']" "$APP_CSS" || \
	fail 'automatic update unsaved marker background must retain a dark-theme mapping'
grep -Fq "[class~='text-amber-800']" "$APP_CSS" || \
	fail 'automatic update unsaved marker text must retain dark-theme contrast mapping'

# Switches should have an explicit right/left thumb position rather than a browser checkbox.
grep -Fq 'role="switch"' "$UPDATES_CARD" || \
	fail 'automatic update settings must use switch controls'
grep -Fq "checked ? 'left-6' : 'left-1'" "$UPDATES_CARD" || \
	fail 'update switch thumb must use explicit left positioning'
grep -Fq 'ssh-switch-control' "$UPDATES_CARD" || \
	fail 'update switches must use fixed shared geometry on narrow screens'
grep -Fq 'ssh-switch-thumb' "$UPDATES_CARD" || \
	fail 'update switch thumbs must use the theme-safe shared circle style'
if grep -Fq 'type="checkbox"' "$UPDATES_CARD"; then
	fail 'legacy checkbox controls must not remain in the update settings panel'
fi

# The current update channel should be visible without exposing repository implementation details.
grep -Fq '업데이트 채널' "$UPDATES_CARD" || \
	fail 'update settings must show the current update channel'
grep -Fq 'updateChannelLabel(data.settings.channel)' "$UPDATES_CARD" || \
	fail 'update channel display must use the channel returned by updates_status'
grep -Fq "return 'Stable';" "$UPDATES_CARD" || \
	fail 'stable update channel must have a product label'
grep -Fq "return 'Beta';" "$UPDATES_CARD" || \
	fail 'beta update channel must have a product label'

# Internal package/repository implementation details should not be rendered as product UI text.
if grep -Fq '저장소:' "$UPDATES_CARD"; then
	fail 'repository host must not be exposed in the product update UI'
fi
if grep -Fq '<p class="mt-1 mb-0 break-all text-xs text-slate-500">{item.name}</p>' "$UPDATES_CARD"; then
	fail 'internal package name must not be rendered in the product update UI'
fi


# Update status polling should be conservative while idle, pause in hidden tabs,
# refresh when the UI becomes active again, and poll active checks/installations until they finish.
grep -Fq 'const BACKGROUND_POLL_INTERVAL_MS = 5 * 60_000;' "$UPDATES_HOOK" || \
	fail 'software update background polling must use a five-minute interval'
grep -Fq 'const CHECK_POLL_INTERVAL_MS = 1_000;' "$UPDATES_HOOK" || \
	fail 'software update checking polling must use a one-second interval'
grep -Fq 'const INSTALL_POLL_INTERVAL_MS = 3_000;' "$UPDATES_HOOK" || \
	fail 'software update installation polling must use a three-second interval'
grep -Fq "if (data?.phase === 'checking')" "$UPDATES_HOOK" || \
	fail 'software update checking must use active polling until the phase changes'
grep -Fq 'return CHECK_POLL_INTERVAL_MS;' "$UPDATES_HOOK" || \
	fail 'software update checking must return the short checking poll interval'
grep -Fq "data?.phase === 'installing'" "$UPDATES_HOOK" || \
	fail 'software update installation must keep using active polling until completion'
grep -Fq 'refreshOnFocus: true' "$UPDATES_HOOK" || \
	fail 'software updates must refresh when the browser window regains focus'
grep -Fq "document.addEventListener('visibilitychange', handleVisibilityChange);" "$ASYNC_RESOURCE" || \
	fail 'async polling must react to document visibility changes'
grep -Fq "window.addEventListener('focus', handleFocus);" "$ASYNC_RESOURCE" || \
	fail 'async polling must support focus-based refresh'
grep -Fq "window.removeEventListener('focus', handleFocus);" "$ASYNC_RESOURCE" || \
	fail 'focus refresh listener must be removed during cleanup'
grep -Fq "document.visibilityState === 'hidden'" "$ASYNC_RESOURCE" || \
	fail 'async polling must avoid scheduling requests while the document is hidden'
grep -Fq 'const millisecondsUntilStale = () =>' "$ASYNC_RESOURCE" || \
	fail 'visibility/focus refresh must be gated by the polling staleness interval'
grep -Fq 'if (millisecondsUntilStale() > 0)' "$ASYNC_RESOURCE" || \
	fail 'focus refresh must reschedule instead of reloading fresh data'
if grep -Fq "resource.error?.trim().toLowerCase() === 'access denied'" "$UPDATES_HOOK"; then
	fail 'update polling must rely on global session-expiry handling instead of page reload loops'
fi
grep -Fq 'installedVersion !== loadedAssetVersion' "$UPDATES_HOOK" || \
	fail 'completed self-updates must detect when the browser is running stale assets'
grep -Fq 'window.location.reload();' "$UPDATES_HOOK" || \
	fail 'self-update completion must reload the SmartSafeHub entry once for fresh assets'
grep -Fq 'const lastObservedInstallAt = useRef<number | null | undefined>(undefined);' "$UPDATES_HOOK" || \
	fail 'self-update reload must track the install completion timestamp per mounted page'
grep -Fq 'if (reloadRequested.current || !resource.data)' "$UPDATES_HOOK" || \
	fail 'empty initial update data must not seed the self-update reload baseline'
grep -Fq 'const lastInstallAt = resource.data.lastInstallAt ?? null;' "$UPDATES_HOOK" || \
	fail 'self-update baseline must be derived only from a real update-status response'
grep -Fq 'if (previousLastInstallAt === undefined)' "$UPDATES_HOOK" || \
	fail 'the first real update state must establish a baseline without reloading'
grep -Fq 'lastObservedInstallAt.current = lastInstallAt;' "$UPDATES_HOOK" || \
	fail 'self-update reload must remember the latest observed install timestamp'
grep -Fq 'lastInstallAt === previousLastInstallAt' "$UPDATES_HOOK" || \
	fail 'unchanged install timestamps must not trigger another automatic reload'
grep -Fq "resource.data.phase !== 'idle'" "$UPDATES_HOOK" || \
	fail 'asset reload must only happen after the updater returns to idle'
if grep -Fq 'resource.data?.lastInstallAt ?? null' "$UPDATES_HOOK"; then
	fail 'data=null must not be converted into a fake lastInstallAt baseline'
fi

# Firmware is the primary update experience and manual install stays inside the same card.
grep -Fq '<SoftwareUpdatesCard' "$UPDATE_PAGE" || \
	fail 'update page must render the software update experience'
grep -Fq '<FirmwareUpdatesCard' "$UPDATE_PAGE" || \
	fail 'update page must render the firmware update experience'
firmware_line="$(grep -n -m1 '<FirmwareUpdatesCard' "$UPDATE_PAGE" | cut -d: -f1)"
software_line="$(grep -n -m1 '<SoftwareUpdatesCard' "$UPDATE_PAGE" | cut -d: -f1)"
[ "$firmware_line" -lt "$software_line" ] || \
	fail 'firmware update must be shown before SmartSafeHub software updates'
grep -Fq '>펌웨어 업데이트</h2>' "$FIRMWARE_CARD" || \
	fail 'firmware card must use the customer-facing firmware-update heading'
grep -Fq 'releaseVersion: string | null;' "$FIRMWARE_TYPES" || \
	fail 'firmware status must expose the Hub-resolved current release version separately from build metadata'
grep -Fq 'const current_version = limited_string(document?.current_version, 32);' "$FIRMWARE_RPC" || \
	fail 'firmware RPC must sanitize current_version returned by the Hub resolve API'
grep -Fq 'current.releaseVersion = resolved.currentVersion;' "$FIRMWARE_RPC" || \
	fail 'firmware RPC must attach the Hub-resolved release version to the current firmware status'
grep -Fq "{data.current.releaseVersion || '미확인'}" "$FIRMWARE_CARD" || \
	fail 'firmware UI must display the product release version as the current version'
grep -Fq '빌드 ID {data.current.buildId}' "$FIRMWARE_CARD" || \
	fail 'firmware UI must keep build_id as secondary diagnostic identity'
grep -Fq 'data.release?.version' "$FIRMWARE_CARD" || \
	fail 'firmware UI must use the Hub release version for the available firmware version'
grep -Fq "펌웨어 {data.release.version || '미확인'} · OpenWrt" "$FIRMWARE_CARD" || \
	fail 'available firmware details must distinguish product firmware version from the OpenWrt base version'
grep -Fq "(data.release.channel || data.settings.channel) === 'beta' ? 'Beta' : 'Stable'" "$FIRMWARE_CARD" || 	fail 'available firmware details must prefer the release firmware channel over package update settings'
grep -Fq "[class~='bg-sky-50']" "$APP_CSS" || 	fail 'dark mode must define a sky surface override for the firmware update panel'
grep -Fq "[class~='text-sky-700']" "$APP_CSS" || 	fail 'dark mode must define a sky text override for the firmware update panel'
grep -Fq "[class~='ring-sky-200']" "$APP_CSS" || 	fail 'dark mode must define a sky ring override for the firmware update panel'
if grep -Fq 'metadata?.release_version' "$FIRMWARE_RPC"; then
	fail 'firmware release version must not be read from immutable firmware.json build metadata'
fi
if grep -Fq 'OpenWrt 펌웨어' "$FIRMWARE_CARD"; then
	fail 'firmware card must not expose OpenWrt as the customer-facing firmware product name'
fi
grep -Fq 'data-component="firmware-update-card"' "$FIRMWARE_CARD" || \
	fail 'firmware update must have one primary product card'
grep -Fq 'data-section="manual-firmware"' "$FIRMWARE_CARD" || \
	fail 'manual firmware install must be grouped into the primary firmware card'
manual_line="$(grep -n -m1 'data-section="manual-firmware"' "$FIRMWARE_CARD" | cut -d: -f1)"
card_close_line="$(grep -n '</article>' "$FIRMWARE_CARD" | tail -1 | cut -d: -f1)"
[ "$manual_line" -lt "$card_close_line" ] || \
	fail 'manual firmware install must stay inside the primary firmware card'
grep -Fq '수동 펌웨어 설치' "$FIRMWARE_CARD" || \
	fail 'firmware card must expose a clear manual install fallback'
grep -Fq 'group mx-5 mb-5 rounded-xl border border-slate-200 bg-slate-50/70 sm:mx-6 sm:mb-6' "$FIRMWARE_CARD" || \
	fail 'manual firmware fallback must render as an inset panel inside the firmware card'
grep -Fq 'data-layout="firmware-card-subsection"' "$FIRMWARE_CARD" || \
	fail 'manual firmware fallback must declare its firmware-card subsection layout'
grep -Fq 'class="border-t border-slate-200 px-5 pb-5 pt-3 sm:px-6"' "$FIRMWARE_CARD" || \
	fail 'expanded manual firmware body must keep compact top spacing'
grep -Fq 'data-layout="firmware-file-picker"' "$FIRMWARE_CARD" || \
	fail 'manual firmware upload must use the SmartSafeHub file-picker layout'
grep -Fq 'aria-label="펌웨어 파일 선택"' "$FIRMWARE_CARD" || \
	fail 'manual firmware file input must retain an accessible Korean label'
grep -Fq 'class="sr-only"' "$FIRMWARE_CARD" || \
	fail 'native browser file input must be visually hidden behind the custom file picker'
grep -Fq "{selectedFile ? '다른 파일 선택' : '파일 선택'}" "$FIRMWARE_CARD" || \
	fail 'custom firmware file picker must expose localized select and reselect actions'
grep -Fq "{selectedFile ? selectedFile.name : '펌웨어 파일을 선택하세요'}" "$FIRMWARE_CARD" || \
	fail 'custom firmware file picker must show a localized empty state and selected filename'
grep -Fq 'onClick={() => fileInput.current?.click()}' "$FIRMWARE_CARD" || \
	fail 'custom firmware file-picker button must activate the hidden input'
if grep -Fq 'file:mr-4' "$FIRMWARE_CARD" || grep -Fq 'file:cursor-pointer' "$FIRMWARE_CARD"; then
	fail 'manual firmware upload must not rely on browser-native file input chrome'
fi
if grep -Fq 'group border-t border-slate-200 bg-slate-50/70' "$FIRMWARE_CARD"; then
	fail 'manual firmware fallback must not look like a full-width card continuation outside the firmware surface'
fi
grep -Fq '현재 펌웨어의 버전 정보를 완전히 확인할 수 없습니다.' "$FIRMWARE_CARD" || \
	fail 'missing build metadata must use customer-friendly warning copy'
grep -Fq '기술 상세 보기' "$FIRMWARE_CARD" || \
	fail 'technical firmware metadata details must stay behind a disclosure'
grep -Fq '다운로드 및 검증' "$FIRMWARE_CARD" || \
	fail 'online firmware updates must download and verify before installation'
grep -Fq '현재 설정 유지' "$FIRMWARE_CARD" || \
	fail 'firmware install confirmation must expose the keep-settings choice'
grep -Fq '강제 설치는 제공하지 않습니다.' "$FIRMWARE_CARD" || \
	fail 'firmware UI must clearly avoid force-upgrade behavior'
grep -Fq "const FIRMWARE_UPLOAD_PATH = '/tmp/smartsafehub/firmware.bin';" "$FIRMWARE_UPLOAD" || \
	fail 'manual firmware upload must use the dedicated temporary image path'
grep -Fq "const FIRMWARE_UPLOAD_ENDPOINT = '/cgi-upload';" "$FIRMWARE_UPLOAD" || \
	fail 'manual firmware upload must declare the raw cgi-upload endpoint'
grep -Fq "const DEFAULT_CGI_BASE = '/cgi-bin';" "$LUCI_UTIL" || \
	fail 'LuCI URL utilities must declare the CGI base separately from the LuCI dispatcher'
grep -Fq 'return luciBase.slice(0, -suffix.length);' "$LUCI_UTIL" || \
	fail 'CGI URL resolution must preserve any deployment prefix while removing the /luci dispatcher suffix'
grep -Fq 'return `${cgiBaseUrl()}${normalizedRoute}`;' "$LUCI_UTIL" || \
	fail 'CGI URL resolution must build routes from /cgi-bin rather than /cgi-bin/luci'
grep -Fq "const uploadUrl = cgiUrl(FIRMWARE_UPLOAD_ENDPOINT);" "$FIRMWARE_UPLOAD" || \
	fail 'manual firmware upload must resolve cgi-upload outside the LuCI dispatcher prefix'
grep -Fq "request.open('POST', uploadUrl);" "$FIRMWARE_UPLOAD" || \
	fail 'manual firmware upload must POST to the resolved CGI endpoint'
if grep -Fq "luciUrl('/cgi-upload')" "$FIRMWARE_UPLOAD"; then
	fail 'manual firmware upload must not route cgi-upload through /cgi-bin/luci'
fi
grep -Fq "firmware upload network error" "$FIRMWARE_UPLOAD" || \
	fail 'manual firmware upload failures must log network diagnostics'
grep -Fq "firmware upload HTTP error" "$FIRMWARE_UPLOAD" || \
	fail 'manual firmware upload failures must log HTTP diagnostics'
grep -Fq "firmware upload returned invalid JSON" "$FIRMWARE_UPLOAD" || \
	fail 'manual firmware upload failures must log invalid-response diagnostics'
grep -Fq 'const ACTIVE_POLL_INTERVAL_MS = 1_000;' "$FIRMWARE_HOOK" || \
	fail 'firmware check/download/validation phases must be actively polled'
grep -Fq 'const VALIDATION_STATUS_POLL_INTERVAL_MS = 500;' "$FIRMWARE_HOOK" || \
	fail 'manual firmware validation must use a short dedicated status polling interval'
grep -Fq 'const VALIDATION_STALE_STATE_GRACE_MS = 3_000;' "$FIRMWARE_HOOK" || \
	fail 'manual firmware validation must tolerate the previous terminal state while the helper starts'
grep -Fq 'const VALIDATION_STATUS_TIMEOUT_MS = 30_000;' "$FIRMWARE_HOOK" || \
	fail 'manual firmware validation polling must have a bounded timeout'
grep -Fq 'const waitForUploadValidation = useCallback(async (): Promise<FirmwareStatus>' "$FIRMWARE_HOOK" || \
	fail 'manual firmware upload must track the asynchronous backend validation result'
grep -Fq "if (status.phase === 'ready')" "$FIRMWARE_HOOK" || \
	fail 'manual firmware validation must explicitly recognize the ready terminal state'
grep -Fq "if (status.phase === 'error')" "$FIRMWARE_HOOK" || \
	fail 'manual firmware validation must explicitly recognize the error terminal state'
grep -Fq 'if (elapsed < VALIDATION_STALE_STATE_GRACE_MS)' "$FIRMWARE_HOOK" || \
	fail 'manual firmware validation must not replace optimistic validation state with an immediate stale error'
grep -Fq 'const status = await waitForUploadValidation();' "$FIRMWARE_HOOK" || \
	fail 'manual firmware upload must await backend validation instead of scheduling a single delayed refresh'
grep -Fq "setMessage('펌웨어 검증이 완료되었습니다. 설치 옵션을 확인해 주세요.');" "$FIRMWARE_HOOK" || \
	fail 'successful manual validation must surface install-ready feedback'
grep -Fq "throw new Error('검증된 펌웨어의 설치 준비 정보를 확인하지 못했습니다. 다시 시도해 주세요.');" "$FIRMWARE_HOOK" || \
	fail 'ready validation without prepared metadata must fail closed'
grep -Fq 'data-section="prepared-firmware"' "$FIRMWARE_CARD" || \
	fail 'ready firmware state must render a dedicated install-preparation panel'
grep -Fq 'onClick={() => setConfirmingInstall(true)}' "$FIRMWARE_CARD" || \
	fail 'prepared firmware panel must expose the firmware install confirmation action'
grep -Fq 'const RECONNECT_INITIAL_DELAY_MS = 15_000;' "$FIRMWARE_HOOK" || \
	fail 'firmware install must wait for sysupgrade reboot before probing the router'
grep -Fq 'window.location.reload();' "$FIRMWARE_HOOK" || \
	fail 'firmware install must reload the UI after the router becomes reachable again'
if grep -Fq '시스템 상태' "$UPDATE_PAGE" || grep -Fq '시스템 관리' "$UPDATE_PAGE"; then
	fail 'update page must not mix system status or management controls'
fi
grep -Fq '시스템 상태' "$SETTINGS_PAGE" || \
	fail 'settings page must own system status'
grep -Fq '시스템 관리' "$SETTINGS_PAGE" || \
	fail 'settings page must own system management actions'

echo 'PASS: product update summary, actions, form controls, switches and page separation are consistent'
