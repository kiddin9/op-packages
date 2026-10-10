#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
PAGE="$ROOT_DIR/frontend/src/pages/SmartSafeHubAccountPage.tsx"
HOOK="$ROOT_DIR/frontend/src/hooks/useDeviceRegistration.ts"
APP="$ROOT_DIR/frontend/src/app/App.tsx"
API="$ROOT_DIR/frontend/src/api/smartsafehub.ts"
RPC="$ROOT_DIR/root/usr/share/rpcd/ucode/smartsafehub/device-registration.uc"
ACL="$ROOT_DIR/root/usr/share/rpcd/acl.d/luci-app-smartsafehub.json"

fail() { echo "FAIL: $*" >&2; exit 1; }

for file in "$PAGE" "$HOOK" "$APP" "$API" "$RPC" "$ACL"; do
	[ -f "$file" ] || fail "missing account source: ${file#$ROOT_DIR/}"
done

grep -Fq '<SmartSafeHubAccountPage' "$APP" || fail 'App must render the dedicated SmartSafeHub account page'
grep -Fq "route === 'account'" "$APP" || fail 'account data hook must only be enabled on the account route'
grep -Fq "callApi(API_OBJECT, 'device_registration_refresh'" "$API" || fail 'frontend must expose explicit account status synchronization'
grep -Fq 'refresh_device_registration_status' "$RPC" || fail 'rpcd must execute device status-sync for fresh account state'
grep -Fq '"device_registration_refresh"' "$ACL" || fail 'ACL must allow authenticated account status refresh'
grep -Fq 'const PAIRING_POLL_INTERVAL_MS = 5_000;' "$HOOK" || fail 'pairing status must poll every five seconds while waiting'
grep -Fq 'const LOCAL_STATUS_POLL_INTERVAL_MS = 5_000;' "$HOOK" || fail 'account page must watch router-local registration state while open'
grep -Fq 'window.setInterval' "$HOOK" || fail 'account page must periodically reread local registration state'
grep -Fq 'pairingStillValid(data)' "$HOOK" || fail 'polling must only run while a pairing session is active'
grep -Fq 'const refreshPromiseRef = useRef<Promise<DeviceRegistrationStatus | null> | null>(null);' "$HOOK" || fail 'account refresh must reuse one in-flight synchronization request'
grep -Fq 'if (refreshPromiseRef.current)' "$HOOK" || fail 'account refresh must prevent duplicate cloud synchronization requests'
grep -Fq 'setLoading(false);' "$HOOK" || fail 'local account state must finish initial loading before cloud synchronization completes'
grep -Fq 'void refresh();' "$HOOK" || fail 'page entry must refresh Hub state in the background after local state is rendered'
grep -Fq 'if (loading && !data) return <LoadingPanel />;' "$PAGE" || fail 'account page must render cached local state without waiting for Hub'
grep -Fq '최신 상태 확인이 지연되고 있습니다. 마지막으로 확인된 연결 상태를 표시합니다.' "$PAGE" || fail 'connected devices must present cloud delay as freshness information, not a connection warning'
grep -Fq '>마지막 확인</dt>' "$PAGE" || fail 'account status must label the timestamp as the last confirmed state'
grep -Fq "timeoutMs: 30000" "$API" || fail 'background account synchronization must allow the router helper enough time to complete'
grep -Fq "status-sync' ], 25000" "$RPC" || fail 'rpcd must allow status-sync to finish before the frontend timeout'

grep -Fq 'const connected = status?.accountRegistered === true;' "$PAGE" || fail 'page must derive explicit account connection state'
grep -Fq 'const pairingCode = !connected && !expired ? status?.pairingCode : null;' "$PAGE" || fail 'connected devices must never display a stale pairing code'
grep -Fq 'SmartSafeHub 계정에 연결됨' "$PAGE" || fail 'connected state must be clearly communicated'
grep -Fq '계정에 연결하면 웹사이트에서 기기를 관리하고 Cloud 기능과 구독 권한을 사용할 수 있습니다.' "$PAGE" || fail 'account introduction must stay concise enough for the account card'
grep -Fq '웹사이트에서 기기 등록을 해제하면 공유기도 다음 계정 상태 동기화에서 자동으로 연결 해제를 반영합니다.' "$PAGE" || fail 'connected account UI must explain automatic website-side device removal sync'
grep -Fq '10분 동안 유효' "$PAGE" || fail 'pairing code lifetime must be displayed as a prominent standalone label'
grep -Fq '<ClockIcon class="size-3.5" />' "$PAGE" || fail 'pairing code lifetime must have a recognizable time icon'
grep -Fq 'class="ssh-safeshield-plan-badge"' "$PAGE" || fail 'account plan must reuse the SafeShield membership badge presentation'
grep -Fq 'data-tier={tone}' "$PAGE" || fail 'account plan badge must preserve tier-specific SafeShield styling'
grep -Fq "currentPlan === 'FREE' ? <span class=\"ssh-safeshield-plan-caption\">기본 플랜</span> : null" "$PAGE" || fail 'FREE account plan must match the SafeShield basic-plan caption'
grep -Fq '계정 연결 코드 복사' "$PAGE" || fail 'pairing code must keep an accessible copy action'
grep -Fq "navigator.clipboard?.writeText" "$PAGE" || fail 'pairing copy must use the modern clipboard API when available'
grep -Fq "document.execCommand('copy')" "$PAGE" || fail 'pairing copy must keep an HTTP-router fallback'
grep -Fq '웹사이트에서 기기 관리' "$PAGE" || fail 'connected devices must link to website device management'

echo 'PASS: SmartSafeHub account UI contract is present'
