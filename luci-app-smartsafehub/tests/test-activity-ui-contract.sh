#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
RPC_ENTRY="$ROOT_DIR/root/usr/share/rpcd/ucode/smartsafehub.uc"
SYSTEM_RPC="$ROOT_DIR/root/usr/share/rpcd/ucode/smartsafehub/system.uc"
ACTIVITY_RPC="$ROOT_DIR/root/usr/share/rpcd/ucode/smartsafehub/activity.uc"
ACL="$ROOT_DIR/root/usr/share/rpcd/acl.d/luci-app-smartsafehub.json"
APP="$ROOT_DIR/frontend/src/app/App.tsx"
ROUTES="$ROOT_DIR/frontend/src/app/routes.ts"
HASH_ROUTE="$ROOT_DIR/frontend/src/hooks/useHashRoute.ts"
NAVIGATION="$ROOT_DIR/frontend/src/components/ProductNavigation.tsx"
HOME="$ROOT_DIR/frontend/src/pages/HomePage.tsx"
PAGE="$ROOT_DIR/frontend/src/pages/ActivityPage.tsx"
TIMELINE="$ROOT_DIR/frontend/src/components/ActivityTimeline.tsx"
HOOK="$ROOT_DIR/frontend/src/hooks/useActivityHistory.ts"
API="$ROOT_DIR/frontend/src/api/smartsafehub.ts"
EVENTS="$ROOT_DIR/root/usr/libexec/smartsafehub-events"

fail() {
	printf 'FAIL: %s\n' "$*" >&2
	exit 1
}

for file in "$RPC_ENTRY" "$SYSTEM_RPC" "$ACTIVITY_RPC" "$ACL" "$APP" "$ROUTES" "$HASH_ROUTE" "$NAVIGATION" "$HOME" "$PAGE" "$TIMELINE" "$HOOK" "$API" "$EVENTS"; do
	[ -f "$file" ] || fail "missing activity history source: ${file#$ROOT_DIR/}"
done

status_contract="$(sed -n '/^[[:space:]]*status:[[:space:]]*{/,/^[[:space:]]*},/p' "$RPC_ENTRY")"
if printf '%s\n' "$status_contract" | grep -Fq 'args:'; then
	fail 'status RPC must remain argument-free for upgrade/session compatibility'
fi
if grep -Eq '^[[:space:]]*activity_history:[[:space:]]*\{' "$RPC_ENTRY"; then
	fail 'recent activity must not add a standalone RPC method that requires a new session ACL'
fi
if jq -e '."luci-app-smartsafehub".read.ubus.smartsafehub | index("activity_history") != null' "$ACL" >/dev/null; then
	fail 'recent activity must reuse the existing status ACL instead of adding a new ACL method'
fi
grep -Fq "import { read_activity_history } from './activity.uc';" "$SYSTEM_RPC" || \
	fail 'system status module must compose the local activity history'
grep -Fq 'const activity_result = read_activity_history();' "$SYSTEM_RPC" || \
	fail 'status RPC must read bounded recent activity without new request arguments'
grep -Fq 'result.data.activityHistory = activity_result.data;' "$SYSTEM_RPC" || \
	fail 'status RPC must attach recent activity to successful status responses'
if grep -Fq 'include_activity_history' "$SYSTEM_RPC" || grep -Fq 'activity_limit' "$SYSTEM_RPC"; then
	fail 'status implementation must not depend on newly introduced ubus arguments'
fi

grep -Fq "const ACTIVITY_HISTORY_FILE = '/tmp/smartsafehub/activity-history.jsonl';" "$ACTIVITY_RPC" || \
	fail 'RPC must read the dedicated volatile local history'
grep -Fq "const LEGACY_EVENTS_FILE = '/tmp/smartsafehub/events.jsonl';" "$ACTIVITY_RPC" || \
	fail 'RPC must retain an r8 outbox fallback during upgrade'
grep -Fq "scope: 'current_boot'" "$ACTIVITY_RPC" || \
	fail 'RPC must describe the local history as current-boot scope'
grep -Fq 'volatile: true' "$ACTIVITY_RPC" || \
	fail 'RPC must tell the UI that local activity history is volatile'
grep -Fq 'MAX_ACTIVITY_EVENTS = 128' "$ACTIVITY_RPC" || \
	fail 'RPC must cap the local activity response to 128 events'
grep -Fq 'export function read_activity_history()' "$ACTIVITY_RPC" || \
	fail 'status activity history reader must not accept an optional limit that can coerce to one event'
grep -Fq 'length(events) < MAX_ACTIVITY_EVENTS' "$ACTIVITY_RPC" || \
	fail 'status activity history reader must return the bounded 128-event history by default'
if grep -Fq 'read_activity_history(limit_value)' "$ACTIVITY_RPC"; then
	fail 'activity history must not derive its UI limit from an omitted RPC argument'
fi
grep -Fq 'function invalid_cloud_sync_state()' "$ACTIVITY_RPC" || \
	fail 'invalid Cloud sync state must use an explicit ucode-compatible fallback helper'
if grep -Eq '^[[:space:]]*throw[[:space:]]' "$ACTIVITY_RPC"; then
	fail 'activity RPC must not use unsupported JavaScript-style throw syntax'
fi
grep -Fq 'for (let index = length(history) - 1;' "$ACTIVITY_RPC" || \
	fail 'RPC must return newest activity first'

grep -Fq 'HISTORY_FILE="${SMARTSAFEHUB_EVENTS_HISTORY_FILE:-$RUNTIME_DIR/activity-history.jsonl}"' "$EVENTS" || \
	fail 'event writer must keep a local history separate from the Cloud outbox'
grep -Fq 'append_bounded_event "$HISTORY_FILE"' "$EVENTS" || \
	fail 'every normalized event must be appended to local history'
grep -Fq 'if cloud_sync_enabled; then' "$EVENTS" || \
	fail 'event writer must gate Cloud outbox writes on the user preference'
grep -Fq 'append_bounded_event "$EVENTS_FILE"' "$EVENTS" || \
	fail 'enabled Cloud transfer must append normalized events to the Cloud outbox'
grep -Fq 'awk -v needle="$needle"' "$EVENTS" || \
	fail 'ack must continue to operate on the Cloud outbox'
if grep -A18 '^ack_event()' "$EVENTS" | grep -Fq '"$HISTORY_FILE"'; then
	fail 'outbox ack must never delete local UI history'
fi

grep -Fq "| 'activity'" "$ROUTES" || fail 'activity route must be part of AppRoute'
grep -Fq "route: 'activity'" "$ROUTES" || fail 'recent activity route must be registered'
grep -Fq "hash: '#activity'" "$ROUTES" || fail 'recent activity route must use #activity'
grep -Fq "'#activity': 'activity'" "$HASH_ROUTE" || fail 'hash router must resolve #activity'
grep -Fq "{ label: 'Overview', routes: ['home', 'activity'] }" "$NAVIGATION" || \
	fail 'recent activity must sit directly below Dashboard in Overview'
grep -Fq "case 'activity':" "$NAVIGATION" || fail 'recent activity navigation item must have its own icon'

grep -Fq "const activity = useActivityHistory(route === 'home' || route === 'activity');" "$APP" || \
	fail 'activity data must load on both Dashboard and the full recent-activity page'
grep -Fq '<ActivityPage' "$APP" || fail 'App must render the full recent-activity page'
grep -Fq 'activity={activity.data}' "$APP" || fail 'Dashboard must receive local activity data'
grep -Fq 'activity.refresh()' "$APP" || fail 'global/dashboard refresh must include recent activity'
grep -Fq 'activity.refreshing ||' "$APP" || fail 'Dashboard refresh indicator must include recent activity'

grep -Fq 'title="최근 활동"' "$HOME" || fail 'Dashboard must expose a recent activity section'
grep -Fq 'href="#activity"' "$HOME" || fail 'Dashboard recent activity must link to the full page'
grep -Fq '<ActivityTimeline compact events={(activity?.events ?? []).slice(0, 3)} />' "$HOME" || \
	fail 'Dashboard must show only the latest three activity entries'
grep -Fq "<div class={compact ? 'space-y-2' : 'space-y-1'}>" "$TIMELINE" || \
	fail 'Dashboard compact activity items must use space-y-2 while the full timeline keeps space-y-1'
grep -Fq '현재 부팅 이후의 최근 활동' "$PAGE" || \
	fail 'full page must clearly describe current-boot scope'
grep -Fq '재부팅하면 초기화됩니다' "$PAGE" || \
	fail 'full page must explain volatile local retention'
grep -Fq '직접 설정을 변경한 작업은 성공 시점에 즉시 기록하고' "$PAGE" || \
	fail 'full page must explain direct mutation event recording'
grep -Fq '외부 상태를 확인해야 하는 항목은 실제 상태 변화가 관찰된 경우에만 추가합니다' "$PAGE" || \
	fail 'full page must explain observer-owned transition recording'
grep -Fq '<ActivityTimeline events={data?.events ?? []} />' "$PAGE" || \
	fail 'full page must render the complete local activity response'

for event_type in \
	system.booted \
	network.internet.disconnected \
	network.internet.recovered \
	safeshield.protection.enabled \
	safeshield.protection.disabled \
	safeshield.blocklist.updated \
	safeshield.blocklist.update_failed \
	software.update.completed \
	software.update.failed \
	firmware.update.started \
	firmware.update.failed \
	license.activated \
	license.changed \
	license.cleared \
	health.issue.started \
	health.issue.changed \
	health.issue.resolved; do
	grep -Fq "case '$event_type':" "$TIMELINE" || fail "UI renderer missing event type: $event_type"
done

# 사용자에게 원인이나 정확도를 과도하게 단정하지 않는 최근 활동 문구를 유지합니다.
grep -Fq "title: '공유기 부팅 감지'" "$TIMELINE" || \
	fail 'boot activity must distinguish a detected boot from a generic router start'
grep -Fq "description: '공유기가 켜지거나 재시작된 것을 확인했습니다.'" "$TIMELINE" || \
	fail 'boot activity must explain both power-on and restart without exposing boot-session jargon'
grep -Fq "title: '인터넷 연결 끊김 감지'" "$TIMELINE" || \
	fail 'internet disconnect activity must be framed as an observation'
grep -Fq "description: '공유기에서 인터넷 연결을 확인할 수 없었습니다.'" "$TIMELINE" || \
	fail 'internet disconnect activity must not claim a specific upstream failure cause'
grep -Fq '약 ${formatDuration(downtime)} 동안 인터넷 연결이 확인되지 않았습니다.' "$TIMELINE" || \
	fail 'observed internet downtime must be qualified as approximate and observation-based'
grep -Fq "title: 'SafeShield 보호 활성화'" "$TIMELINE" || \
	fail 'SafeShield enabled activity must use explicit activation wording'
grep -Fq "title: 'SafeShield 보호 비활성화'" "$TIMELINE" || \
	fail 'SafeShield disabled activity must use explicit deactivation wording'
grep -Fq "title: '라이선스 연결 해제'" "$TIMELINE" || \
	fail 'license clear activity must describe the router-license link instead of implying license deletion'
grep -Fq "title: '확인이 필요한 장치 상태 발견'" "$TIMELINE" || \
	fail 'health issue activity must use user-facing device-state wording'
grep -Fq "title: '확인이 필요한 장치 상태 변경'" "$TIMELINE" || \
	fail 'health change activity must avoid diagnostic jargon'
grep -Fq "title: '장치 상태 정상으로 복구'" "$TIMELINE" || \
	fail 'health resolved activity must clearly describe recovery'
grep -Fq "function failureDescription(event: ActivityEvent, message: string): string" "$TIMELINE" || \
	fail 'failed activities must share a user-facing description before diagnostic error codes'
grep -Fq 'return errorCode ? `${message} (오류 코드: ${errorCode})` : message;' "$TIMELINE" || \
	fail 'failed activities must keep error codes as secondary diagnostic information'

for ambiguous_copy in \
	"title: '공유기 시작'" \
	"상위 네트워크 연결이 끊어졌습니다." \
	'동안 연결이 중단되었습니다.' \
	"title: 'SafeShield 보호 꺼짐'" \
	"title: '라이선스 해제'" \
	"title: '장치 진단 정상화'"; do
	if grep -Fq "$ambiguous_copy" "$TIMELINE"; then
		fail "ambiguous recent-activity copy must not return: $ambiguous_copy"
	fi
done

grep -Fq "title: 'SmartSafeHub 활동'" "$TIMELINE" || \
	fail 'unknown future event types must keep a safe UI fallback'
grep -Fq 'formatNumber(domainCount)' "$TIMELINE" || \
	fail 'SafeShield domain counts must use the shared locale number formatter'
grep -Fq "bg-rose-50 text-rose-700 ring-rose-200" "$TIMELINE" || \
	fail 'error events must use the shared rose dark/light theme tokens'
grep -Fq "bg-amber-50 text-amber-800 ring-amber-200" "$TIMELINE" || \
	fail 'warning events must use the shared amber dark/light theme tokens'
grep -Fq "bg-emerald-50 text-emerald-700 ring-emerald-200" "$TIMELINE" || \
	fail 'success events must use the shared emerald dark/light theme tokens'
grep -Fq "bg-slate-100 text-slate-600 ring-slate-200" "$TIMELINE" || \
	fail 'info events must use the shared neutral dark/light theme tokens'

grep -Fq "export async function fetchActivityHistory(): Promise<ActivityHistory>" "$API" || \
	fail 'frontend API must expose local Recent Activity'
grep -Fq "callApi<SmartSafeHubStatusWithActivity>(API_OBJECT, 'status');" "$API" || \
	fail 'frontend activity API must call the long-lived status RPC without new arguments'
if grep -Fq 'include_activity_history' "$API" || grep -Fq 'activity_limit' "$API"; then
	fail 'frontend activity request must not send upgrade-incompatible status arguments'
fi
grep -Fq 'activityHistory?: ActivityHistory;' "$API" || \
	fail 'frontend must tolerate a pre-reload status response without activityHistory'
grep -Fq 'const activity = status.activityHistory ?? emptyActivityHistory();' "$API" || \
	fail 'frontend must render an empty activity state while an older in-memory RPC handler is draining'
grep -Fq 'enabled: activity.cloud.enabled ?? true' "$API" || \
	fail 'pre-r19 activity responses must retain the legacy always-enabled Cloud behavior during rolling upgrades'
grep -Fq 'const ACTIVITY_REFRESH_INTERVAL_MS = 60_000;' "$HOOK" || \
	fail 'recent activity may refresh at a lightweight one-minute interval'
grep -Fq 'refreshOnFocus: true' "$HOOK" || \
	fail 'recent activity must refresh when the user returns to the page'

grep -Fq 'Cloud 활동 기록' "$PAGE" || \
	fail 'activity page must expose Cloud activity synchronization controls'
grep -Fq 'aria-label="Cloud 활동 기록 전송 사용"' "$PAGE" || \
	fail 'Cloud activity card must expose an accessible ON/OFF switch'
grep -Fq 'Cloud 전송 꺼짐' "$PAGE" || \
	fail 'Cloud activity card must clearly explain the disabled state'
grep -Fq '다시 켠 뒤 새로 발생한 활동부터 Cloud에 전송합니다.' "$PAGE" || \
	fail 'Cloud activity opt-out copy must explain that disabled-period events are not uploaded later'
grep -Fq 'Pro / Ultimate 전용' "$PAGE" || \
	fail 'Cloud activity UI must clearly identify the paid entitlement boundary'
grep -Fq '전송 대기' "$PAGE" || \
	fail 'Cloud activity UI must show the pending outbox count'
grep -Fq '마지막 동기화' "$PAGE" || \
	fail 'Cloud activity UI must show the last successful synchronization time'
grep -Fq 'Cloud 보관' "$PAGE" || \
	fail 'Cloud activity UI must show server retention when eligible'
grep -Fq 'cloud: read_cloud_sync()' "$ACTIVITY_RPC" || \
	fail 'local activity RPC must expose activity Cloud sync state without a new read RPC method'
grep -Fq 'export function update_activity_cloud_sync(request)' "$ACTIVITY_RPC" || \
	fail 'activity RPC must expose an explicit Cloud transfer preference mutation'
grep -Fq "ctx.set('smartsafehub', 'activity', 'cloud_sync_enabled'" "$ACTIVITY_RPC" || \
	fail 'Cloud transfer preference must persist in UCI'
grep -Fq "'ACTIVITY_CLOUD_SYNC_NOT_ELIGIBLE'" "$ACTIVITY_RPC" || \
	fail 'enabling Cloud activity must enforce paid entitlement on the router'
grep -Fq 'activity_cloud_sync_update' "$RPC_ENTRY" || \
	fail 'top-level RPC must expose the Cloud activity toggle mutation'
jq -e '."luci-app-smartsafehub".write.ubus.smartsafehub | index("activity_cloud_sync_update") != null' "$ACL" >/dev/null || \
	fail 'Cloud activity toggle RPC must be covered by the SmartSafeHub write ACL'
grep -Fq 'export function updateActivityCloudSync(enabled: boolean)' "$API" || \
	fail 'frontend API must expose the Cloud activity toggle mutation'
grep -Fq 'setCloudSyncEnabled' "$HOOK" || \
	fail 'activity hook must own Cloud activity toggle mutation state'
for event_type in settings.activity_cloud_sync.enabled settings.activity_cloud_sync.disabled; do
	grep -Fq "case '$event_type':" "$TIMELINE" || fail "UI renderer missing Cloud activity setting event: $event_type"
done

printf '%s\n' 'PASS: local recent activity, direct/observed copy, paid Cloud sync ON/OFF and argument-free status RPC contracts are valid'
