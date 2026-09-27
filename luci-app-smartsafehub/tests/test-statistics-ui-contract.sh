#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
set -eu

ROOT_DIR="$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)"
MAKEFILE="$ROOT_DIR/Makefile"
ACL="$ROOT_DIR/root/usr/share/rpcd/acl.d/luci-app-smartsafehub.json"
API="$ROOT_DIR/frontend/src/api/safeshield.ts"
HOOK="$ROOT_DIR/frontend/src/hooks/useSafeShieldStatistics.ts"
APP="$ROOT_DIR/frontend/src/app/App.tsx"
PANEL="$ROOT_DIR/frontend/src/components/SafeShieldStatisticsPanel.tsx"
CHART="$ROOT_DIR/frontend/src/components/SafeShieldBlockedBarChart.tsx"
DEVICE_LIST="$ROOT_DIR/frontend/src/components/SafeShieldDeviceStatisticsList.tsx"
PACKAGE_JSON="$ROOT_DIR/frontend/package.json"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

jq -e \
  '.["luci-app-smartsafehub"].read.ubus.safeshield | index("statistics") != null' \
  "$ACL" >/dev/null || fail 'statistics must be allowed by the SafeShield read ACL'

grep -Fq 'LUCI_EXTRA_DEPENDS:=safeshield (>=0.3.24)' "$MAKEFILE" || \
  fail 'SmartSafeHub must require safeshield 0.3.24 or later'
grep -Fq "callSafeShield<RawSafeShieldStatistics>('statistics')" "$API" || \
  fail 'frontend API must call the safeshield statistics RPC'
grep -Fq 'const STATISTICS_REFRESH_INTERVAL_MS = 60_000;' "$HOOK" || \
  fail 'statistics polling interval must remain 60 seconds'
grep -Fq "useSafeShieldStatistics(route === 'safeshield')" "$APP" || \
  fail 'statistics resource must only be active on the SafeShield route'
grep -Fq 'const DISPLAY_HOURS = 24;' "$PANEL" || \
  fail 'statistics chart must display the latest 24 hourly buckets'
grep -Fq 'DNS 요청 원본은 저장하지 않고 숫자만 로컬 메모리에 집계합니다.' "$PANEL" || \
  fail 'statistics UI must explain local aggregate-only behavior'
grep -Fq '<SafeShieldBlockedBarChart buckets={buckets} />' "$PANEL" || \
  fail 'statistics panel must render the Chart.js bar chart component'
grep -Fq 'deviceLimit: numberValue(source.device_limit)' "$API" || \
  fail 'statistics API must normalize the per-device tracking limit'
grep -Fq 'devicesTruncated: boolValue(source.devices_truncated)' "$API" || \
  fail 'statistics API must normalize the device truncation flag'
grep -Fq 'devices,' "$API" || \
  fail 'statistics API must expose normalized per-device statistics'
grep -Fq '<SafeShieldDeviceStatisticsList' "$PANEL" || \
  fail 'statistics panel must render the per-device statistics list'
grep -Fq '기기별 통계' "$DEVICE_LIST" || \
  fail 'device statistics list must label the per-device section'
grep -Fq 'DHCP 식별' "$DEVICE_LIST" || \
  fail 'device statistics list must show DHCP identification state'
grep -Fq 'IP 임시 식별' "$DEVICE_LIST" || \
  fail 'device statistics list must show temporary IP identification state'
grep -Fq 'device.blocked' "$DEVICE_LIST" || \
  fail 'device statistics list must render blocked request counts'
grep -Fq 'const DEVICE_PREVIEW_COUNT = 3;' "$DEVICE_LIST" || \
  fail 'device statistics list must preview three devices by default'
grep -Fq 'const [expanded, setExpanded] = useState(false);' "$DEVICE_LIST" || \
  fail 'device statistics list must start in compact preview mode'
grep -Fq '차단 TOP 3' "$DEVICE_LIST" || \
  fail 'compact device statistics mode must visibly label the top-three preview'
grep -Fq '전체 {formatNumber(orderedDevices.length)}개 기기 중 차단 수 기준 상위 {DEVICE_PREVIEW_COUNT}개를 표시하고 있습니다.' "$DEVICE_LIST" || \
  fail 'compact device statistics mode must explain that the preview is ranked by blocked requests'
grep -Fq ': orderedDevices.slice(0, DEVICE_PREVIEW_COUNT);' "$DEVICE_LIST" || \
  fail 'compact device statistics mode must render only the top three devices'
grep -Fq 'aria-expanded={expanded}' "$DEVICE_LIST" || \
  fail 'device statistics expand control must expose its expanded state'
grep -Fq 'aria-controls="safeshield-device-statistics-list"' "$DEVICE_LIST" || \
  fail 'device statistics expand control must identify the controlled list'
grep -Fq '전체 ${formatNumber(orderedDevices.length)}개 기기 보기 ↓' "$DEVICE_LIST" || \
  fail 'compact device statistics mode must provide an explicit full-list control'
grep -Fq "'간단히 보기 ↑'" "$DEVICE_LIST" || \
  fail 'expanded device statistics mode must provide a compact-view control'
grep -Fq 'const DEVICES_PER_PAGE = 10;' "$DEVICE_LIST" || \
  fail 'expanded device statistics list must paginate ten devices at a time'
grep -Fq 'orderedDevices.slice(pageStart, pageEnd)' "$DEVICE_LIST" || \
  fail 'expanded device statistics list must render only the current page slice'
grep -Fq '{expanded && orderedDevices.length > DEVICES_PER_PAGE ? (' "$DEVICE_LIST" || \
  fail 'device statistics pagination must only be visible in expanded mode'
grep -Fq 'aria-label="기기별 통계 페이지"' "$DEVICE_LIST" || \
  fail 'device statistics pagination must expose an accessible navigation label'
grep -Fq 'setPage((current) => Math.min(current, pageCount));' "$DEVICE_LIST" || \
  fail 'device statistics pagination must clamp the current page after refreshes'
grep -Fq '                setPage(1);' "$DEVICE_LIST" || \
  fail 'device statistics view toggle must reset pagination to the first page'
grep -Fq '              이전' "$DEVICE_LIST" || \
  fail 'device statistics pagination must provide a previous-page control'
grep -Fq '              다음' "$DEVICE_LIST" || \
  fail 'device statistics pagination must provide a next-page control'
jq -e '.dependencies["chart.js"] == "4.5.1"' "$PACKAGE_JSON" >/dev/null || \
  fail 'frontend must pin Chart.js 4.5.1'
grep -Fq "from 'chart.js';" "$CHART" || \
  fail 'statistics chart must import Chart.js modules directly'
grep -Fq 'BarController' "$CHART" || fail 'statistics chart must register BarController'
grep -Fq 'BarElement' "$CHART" || fail 'statistics chart must register BarElement'
grep -Fq 'CategoryScale' "$CHART" || fail 'statistics chart must register CategoryScale'
grep -Fq 'LinearScale' "$CHART" || fail 'statistics chart must register LinearScale'
grep -Fq 'Tooltip' "$CHART" || fail 'statistics chart must register Tooltip'
if grep -Fq "chart.js/auto" "$CHART"; then
  fail 'statistics chart must not use chart.js/auto'
fi
grep -Fq 'prefers-reduced-motion: reduce' "$CHART" || \
  fail 'statistics chart must respect reduced-motion preferences'

jq -e \
  '.["luci-app-smartsafehub"].write.ubus.safeshield | index("config_update") != null' \
  "$ACL" >/dev/null || fail 'statistics toggle requires config_update write ACL'
grep -Fq "'safeshield_statistics_update'" "$API" || \
  fail 'statistics toggle must use the SmartSafeHub managed SafeShield mutation adapter'
grep -Fq "'config_update'" "$API" || \
  fail 'statistics toggle must retain direct SafeShield config_update as an upgrade-session fallback'
grep -Fq 'statistics_enabled: enabled' "$API" || \
  fail 'statistics fallback must only update statistics_enabled'
grep -Fq 'collectorRunning: boolValue(source.collector_running)' "$API" || \
  fail 'statistics API must expose collector runtime state'
grep -Fq 'role="switch"' "$PANEL" || \
  fail 'statistics panel must expose an accessible enable switch'
grep -Fq 'onSetEnabled(!data.enabled)' "$PANEL" || \
  fail 'statistics switch must toggle the current enabled state'

grep -Fq 'reconciled: boolValue(response.reconciled)' "$API" || \
  fail 'statistics toggle must normalize backend reconciliation state'
grep -Fq "action === 'statistics-enable' || action === 'statistics-disable'" "$PANEL" || \
  fail 'statistics panel must expose a dedicated busy state for toggle actions'
grep -Fq 'animate-spin' "$PANEL" || \
  fail 'statistics switch must show a spinner while the setting is being reconciled'
grep -Fq '<ReloadIcon aria-hidden="true" class="size-3 animate-spin text-teal-600" />' "$PANEL" || \
  fail 'statistics switch spinner must use the shared reload icon'
grep -Fq '.ssh-app button.ssh-switch-control {' "$ROOT_DIR/frontend/src/styles/app.css" || \
  fail 'switch geometry must override the mobile button touch-target rule'
grep -Fq '.ssh-switch-thumb {' "$ROOT_DIR/frontend/src/styles/app.css" || \
  fail 'shared switch thumb style must be defined in app styles'
grep -Fq 'max-height: 1.75rem;' "$ROOT_DIR/frontend/src/styles/app.css" || \
  fail 'switch track height must stay fixed on narrow screens'
grep -Fq 'max-width: 1.25rem;' "$ROOT_DIR/frontend/src/styles/app.css" || \
  fail 'switch thumb width must stay circular on narrow screens'
grep -Fq 'max-height: 1.25rem;' "$ROOT_DIR/frontend/src/styles/app.css" || \
  fail 'switch thumb height must stay circular on narrow screens'
grep -Fq 'background-color: #fff;' "$ROOT_DIR/frontend/src/styles/app.css" || \
  fail 'shared switch thumb must stay white under the dark-theme utility remap'
grep -Fq 'cursor-wait' "$PANEL" || \
  fail 'statistics panel must show a wait cursor while the setting is being reconciled'
grep -Fq '활성화하는 중…' "$PANEL" || \
  fail 'statistics panel must show an enabling state label'
grep -Fq '비활성화하는 중…' "$PANEL" || \
  fail 'statistics panel must show a disabling state label'
grep -Fq 'scheduleStatisticsRefreshes([500, 1500]);' "$ROOT_DIR/frontend/src/hooks/useSafeShieldActions.ts" || \
  fail 'statistics toggle must use short statistics-only follow-up refreshes'

echo 'PASS: SafeShield statistics API, ACL, toggle, polling and Chart.js 24-hour UI contracts are consistent'
