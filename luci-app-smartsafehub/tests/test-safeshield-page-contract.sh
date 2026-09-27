#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
PAGE="$ROOT_DIR/frontend/src/pages/SafeShieldPage.tsx"
PANEL="$ROOT_DIR/frontend/src/components/SafeShieldStatisticsPanel.tsx"
NAVIGATION="$ROOT_DIR/frontend/src/components/ProductNavigation.tsx"
ASSET_JS="$ROOT_DIR/root/www/luci-static/smartsafehub/app.js"
ASSET_CSS="$ROOT_DIR/root/www/luci-static/smartsafehub/app.css"
SOURCE_CSS="$ROOT_DIR/frontend/src/styles/app.css"
ACTIONS="$ROOT_DIR/frontend/src/hooks/useSafeShieldActions.ts"

fail() {
	echo "FAIL: $*" >&2
	exit 1
}

for file in "$PAGE" "$PANEL" "$NAVIGATION" "$ACTIONS" "$ASSET_JS" "$ASSET_CSS" "$SOURCE_CSS"; do
	[ -f "$file" ] || fail "missing SafeShield product UI source: ${file#$ROOT_DIR/}"
done

grep -Fq 'SafeShield 보호 상태' "$PAGE" || \
	fail 'SafeShield page must lead with the protection status'
grep -Fq 'eyebrow="Protection details"' "$PAGE" || \
	fail 'SafeShield page must provide a dedicated protection details section'
grep -Fq 'title="보호 구성"' "$PAGE" || \
	fail 'SafeShield page must group runtime, blocklist, refresh and health details'
grep -Fq 'eyebrow="Settings"' "$PAGE" || \
	fail 'SafeShield page must provide a dedicated settings section'
grep -Fq 'title="SafeShield 설정"' "$PAGE" || \
	fail 'SafeShield settings section must be clearly labeled'
grep -Fq '라이선스' "$PAGE" || fail 'SafeShield settings must retain license management'
grep -Fq 'Custom rules' "$PAGE" || fail 'SafeShield settings must expose product-facing custom rules'
grep -Fq 'href="#rules"' "$PAGE" || fail 'SafeShield settings must link to the user rules page'
if grep -Fq 'data.localOverrides.allowlistPath' "$PAGE" || grep -Fq 'data.localOverrides.blocklistPath' "$PAGE"; then
	fail 'SafeShield product UI must not expose internal local rule file paths'
fi

grep -Fq 'px-5 pb-5 sm:px-6 sm:pb-6' "$PAGE" || \
	fail 'SafeShield summary facts must remain visually inside the protection card'
grep -Fq 'class="bg-white px-5 py-4 sm:px-6"' "$PAGE" || \
	fail 'SafeShield summary fact cells must use the protection card surface color'
grep -Fq 'ssh-safeshield-license-summary' "$PAGE" || \
	fail 'SafeShield settings must render the refined license summary container'
grep -Fq 'ssh-safeshield-license-editor' "$PAGE" || \
	fail 'SafeShield settings must render the refined license editor card'
grep -Fq 'ssh-safeshield-license-input' "$PAGE" || \
	fail 'SafeShield license key field must remain visually recognizable as an input'
grep -Fq 'ssh-safeshield-license-secondary-action' "$PAGE" || \
	fail 'SafeShield current license key action must remain recognizable as a button'
grep -Fq "actionFeedbackTarget === 'license' ? actionError : null" "$PAGE" || \
	fail 'SafeShield license action errors must render inside the license card'
grep -Fq '라이선스를 확인하고 이 기기에 적용하고 있습니다…' "$PAGE" || \
	fail 'SafeShield license card must expose activation progress near the input'
grep -Fq 'border border-teal-700 bg-teal-700' "$PAGE" || \
	fail 'SafeShield custom rules action must remain recognizable as a primary button'

grep -Fq 'const DISPLAY_HOURS = 24;' "$PANEL" || \
	fail 'SafeShield activity must continue to use 24 hourly buckets'
grep -Fq 'const recentTotals = buckets.reduce(' "$PANEL" || \
	fail 'SafeShield activity must derive recent totals from the displayed 24-hour buckets'
grep -Fq '최근 24시간 DNS 요청' "$PANEL" || \
	fail 'SafeShield activity must label recent DNS query totals accurately'
grep -Fq '최근 24시간 차단' "$PANEL" || \
	fail 'SafeShield activity must label recent blocked totals accurately'
grep -Fq '최근 24시간 차단율' "$PANEL" || \
	fail 'SafeShield activity must expose the recent block rate'
grep -Fq "emphasized ? 'text-teal-700' : 'text-slate-950'" "$PANEL" || \
	fail 'SafeShield metric component must support the shared blocked-total emphasis'
grep -Fq '          emphasized' "$PANEL" || \
	fail 'SafeShield recent 24-hour blocked total must enable the shared emphasis'
[ "$(grep -Fxc '          emphasized' "$PANEL")" -eq 1 ] || \
	fail 'SafeShield must emphasize only the recent 24-hour blocked total metric'
grep -Fq '수집 누적 DNS 요청' "$PANEL" || \
	fail 'SafeShield activity must preserve collector lifetime totals as secondary metadata'
grep -Fq "targetEnabled ? 'left-6' : 'left-1'" "$PANEL" || \
	fail 'SafeShield statistics switch thumb must use explicit left positioning for reliable alignment'
grep -Fq 'ssh-switch-control' "$PANEL" || \
	fail 'SafeShield statistics switch must use fixed shared geometry on narrow screens'
grep -Fq 'ssh-switch-thumb' "$PANEL" || \
	fail 'SafeShield statistics switch thumb must use the theme-safe shared circle style'
if grep -Fq "targetEnabled ? 'translate-x-6' : 'translate-x-1'" "$PANEL"; then
	fail 'SafeShield statistics switch thumb must not rely on translate positioning'
fi

REFRESH_MODEL="$ROOT_DIR/frontend/src/utils/safeshieldRefresh.ts"
[ -f "$REFRESH_MODEL" ] || fail 'missing SafeShield refresh presentation model'

grep -Fq "label: '갱신 준비'" "$REFRESH_MODEL" || \
	fail 'SafeShield refresh UI must start with a user-facing preparation step'
grep -Fq "label: '최신 차단 목록 확인'" "$REFRESH_MODEL" || \
	fail 'SafeShield refresh UI must translate resolve_api into a user-facing step'
grep -Fq "label: '차단 목록 다운로드'" "$REFRESH_MODEL" || \
	fail 'SafeShield refresh UI must expose a download step'
grep -Fq "label: '사용자 규칙 적용'" "$REFRESH_MODEL" || \
	fail 'SafeShield refresh UI must expose a custom-rule step'
grep -Fq "label: '보호 규칙 적용'" "$REFRESH_MODEL" || \
	fail 'SafeShield refresh UI must expose an install step'
grep -Fq "label: '보호 상태 확인'" "$REFRESH_MODEL" || \
	fail 'SafeShield refresh UI must end with a protection verification step'
grep -Fq "stages: ['resolve_api']" "$REFRESH_MODEL" || \
	fail 'resolve_api must map to the latest blocklist lookup step'
grep -Fq "stages: ['runtime_check', 'blocklist_verify']" "$REFRESH_MODEL" || \
	fail 'runtime verification stages must map to the final user-facing step'
grep -Fq 'getSafeShieldRefreshErrorMessage' "$REFRESH_MODEL" || \
	fail 'SafeShield refresh failures must have user-facing error explanations'

grep -Fq 'function RefreshDonut' "$PAGE" || \
	fail 'SafeShield page must render compact donut progress for refresh stages'
grep -Fq 'role="progressbar"' "$PAGE" || \
	fail 'SafeShield refresh donut must expose accessible progress semantics'
grep -Fq 'ssh-safeshield-refresh-loader-svg' "$PAGE" || \
	fail 'SafeShield refresh donut must use a single round loading ring while refresh is in progress'
grep -Fq 'ssh-safeshield-refresh-loader-arc' "$PAGE" || \
	fail 'SafeShield refresh donut must render a rounded rotating arc over the loader track'
grep -Fq 'const loaderArcLength = loaderCircumference * 0.22;' "$PAGE" || \
	fail 'SafeShield round loader must keep a compact moving arc so rotation is visually obvious'
grep -Fq 'const loaderTrackWidth = 3;' "$PAGE" || \
	fail 'SafeShield refresh track must stay slim instead of inheriting a heavy ring treatment'
grep -Fq 'const loaderRadius = 17;' "$PAGE" || \
	fail 'SafeShield refresh donut radius must stay slightly compact so the ring does not dominate the card'
grep -Fq 'const loaderArcWidth = 4;' "$PAGE" || \
	fail 'SafeShield refresh active arc must stay compact and only slightly heavier than the track'
grep -Fq 'strokeWidth={loaderTrackWidth}' "$PAGE" || \
	fail 'SafeShield refresh track must use the dedicated slim stroke width'
grep -Fq 'strokeWidth={loaderArcWidth}' "$PAGE" || \
	fail 'SafeShield refresh arc must use the dedicated slim stroke width'
grep -Fq 'width: 3.35rem;' "$SOURCE_CSS" || \
	fail 'SafeShield refresh donut container must remain slightly smaller than the original oversized treatment'

grep -Fq 'min-width: 3.35rem;' "$SOURCE_CSS" || \
	fail 'SafeShield refresh donut min-width must match the compact container size'

grep -Fq 'height: 3.35rem;' "$SOURCE_CSS" || \
	fail 'SafeShield refresh donut height must match the compact container size'
grep -Fq 'filter: drop-shadow(0 0 0.06rem rgb(15 23 42 / 0.28));' "$SOURCE_CSS" || \
	fail 'SafeShield light refresh arc glow must remain subtle so the ring does not look thicker than its stroke'
grep -Fq 'filter: drop-shadow(0 0 0.08rem rgb(255 255 255 / 0.55));' "$SOURCE_CSS" || \
	fail 'SafeShield dark refresh arc glow must remain subtle so the ring does not look thicker than its stroke'
if grep -Fq 'ssh-safeshield-refresh-donut-spinner-' "$PAGE"; then
	fail 'SafeShield refresh progress must not reintroduce the abandoned nested activity ring'
fi
if grep -Fq 'ssh-safeshield-refresh-donut-value' "$PAGE"; then
	fail 'SafeShield refresh progress must not combine determinate and indeterminate rings'
fi
grep -Fq 'function RefreshProgress' "$PAGE" || \
	fail 'SafeShield page must render the current user-facing refresh step'
grep -Fq '<RefreshProgress data={data} />' "$PAGE" || \
	fail 'SafeShield protection summary must include refresh progress'
grep -Fq '<SummaryBadge data={data} />' "$PAGE" || \
	fail 'SafeShield summary must keep the top status badge for fast protection-state recognition'
grep -Fq "<SummaryFact label=\"SafeShield\" value={data.version ?? '확인되지 않음'} />" "$PAGE" || \
	fail 'SafeShield summary facts must expose the installed SafeShield version instead of duplicating protection status'
grep -Fq 'function PlanSummary' "$PAGE" || \
	fail 'SafeShield summary must render the plan through the dedicated membership presentation'
grep -Fq 'function PlanBadge' "$PAGE" || \
	fail 'SafeShield paid plans must use the shared premium membership badge'
grep -Fq 'data-tier={tone}' "$PAGE" || \
	fail 'SafeShield plan badges must expose a tier-specific visual treatment'
grep -Fq '{free ? <span class="ssh-safeshield-plan-caption">기본 플랜</span> : null}' "$PAGE" || \
	fail 'SafeShield FREE plan may keep its basic-plan caption while paid plans rely on the premium badge alone'
if grep -Fq "'멤버십 활성'" "$PAGE"; then
	fail 'SafeShield paid plan summary must not duplicate active status beside the premium badge'
fi
grep -Fq "planName === 'FREE' ? <FreePlanUpgrade /> : null" "$PAGE" || \
	fail 'SafeShield pricing CTA must be shown only for the FREE plan'
grep -Fq 'https://www.smartsafehub.com/pricing/' "$PAGE" || \
	fail 'SafeShield FREE plan CTA must link to the SmartSafeHub pricing page'
grep -Fq '라이선스 미설정' "$PAGE" || \
	fail 'SafeShield license summary must provide a localized unconfigured label'
if grep -Fq 'data.license.status ||' "$PAGE"; then
	fail 'SafeShield license summary must not expose raw backend status strings directly'
fi
grep -Fq 'rel="noopener noreferrer"' "$PAGE" || \
	fail 'SafeShield pricing link must isolate the new browsing context'
grep -Fq 'target="_blank"' "$PAGE" || \
	fail 'SafeShield pricing link must open without replacing the router management UI'
if grep -Fq '<SummaryFact label="Plan"' "$PAGE"; then
	fail 'SafeShield plan must not fall back to a plain summary text cell'
fi
if grep -Fq '<SummaryFact label="Protection" value={getProtectionSummaryLabel(data)} />' "$PAGE"; then
	fail 'SafeShield summary facts must not duplicate the protection state already shown in the top badge'
fi
if grep -Fq "SafeShield {data.version ?? 'unknown'}" "$PAGE"; then
	fail 'SafeShield version must not remain as a small duplicate line beneath the protection description'
fi
if grep -Fq '현재 단계: ${data.stage}' "$PAGE" || grep -Fq '· ${data.stage}' "$PAGE"; then
	fail 'SafeShield summary must not expose internal refresh stage names'
fi

grep -Fq 'lastKnownBlocklistCount' "$PAGE" || \
	fail 'SafeShield summary must retain the last known blocklist count during transient refresh data'

grep -Fq 'ssh-safeshield-refresh-donut' "$ASSET_JS" || \
	fail 'checked-in app.js must include SafeShield donut refresh progress'
grep -Fq '최신 차단 목록 확인' "$ASSET_JS" || \
	fail 'checked-in app.js must include user-facing SafeShield refresh stage labels'
grep -Fq '.ssh-safeshield-refresh-donut' "$ASSET_CSS" || \
	fail 'checked-in app.css must include SafeShield donut refresh styles'
grep -Fq 'ssh-safeshield-plan-badge' "$ASSET_JS" || \
	fail 'checked-in app.js must include SafeShield membership badges'
grep -Fq 'https://www.smartsafehub.com/pricing/' "$ASSET_JS" || \
	fail 'checked-in app.js must include the FREE plan pricing CTA'
grep -Fq ".ssh-safeshield-plan-badge[data-tier='ultimate']" "$SOURCE_CSS" || \
	fail 'source styles must include the ULTIMATE membership badge treatment'
grep -Fq 'background: linear-gradient(135deg, #78350f 0%, #92400e 58%, #b45309 100%);' "$SOURCE_CSS" || \
	fail 'light-theme ULTIMATE badge must use the restrained bronze surface'
grep -Fq '0 1px 2px rgb(120 53 15 / 0.18)' "$SOURCE_CSS" || \
	fail 'light-theme ULTIMATE badge must keep only a shallow neutral depth shadow'
grep -Fq "background: linear-gradient(135deg, #115e59 0%, #0f766e 62%, #0d9488 100%);" "$SOURCE_CSS" || \
	fail 'PRO badge must use the restrained teal membership surface'
grep -Fq "background: linear-gradient(135deg, #0c4a6e 0%, #075985 58%, #0369a1 100%);" "$SOURCE_CSS" || \
	fail 'other paid tiers such as PLUS must use the restrained blue membership surface'
if grep -Fq '@keyframes ssh-safeshield-premium-shine' "$SOURCE_CSS" || \
	grep -Fq 'ssh-safeshield-premium-shine' "$SOURCE_CSS"; then
	fail 'membership badges must not use promotional shine animation'
fi
if grep -Fq '0 9px 24px rgb(217 119 6 / 0.36)' "$SOURCE_CSS" || \
	grep -Fq '0 0 18px rgb(251 191 36 / 0.22)' "$SOURCE_CSS"; then
	fail 'ULTIMATE badge must not keep the light-theme amber glow below the chip'
fi
[ "$(grep -Fc ".ssh-app[data-theme='dark'] .ssh-safeshield-plan-badge[data-tier='ultimate'] {" "$SOURCE_CSS")" -eq 1 ] || \
	fail 'dark-theme ULTIMATE treatment must be defined exactly once'
grep -Fq 'background: linear-gradient(135deg, #451a03 0%, #78350f 100%);' "$SOURCE_CSS" || \
	fail 'dark-theme ULTIMATE badge must use a static deep-bronze surface'
if grep -Fq '.ssh-safeshield-plan-caption[data-tier=' "$ASSET_CSS"; then
	fail 'checked-in app.css must not retain paid membership status-caption styling'
fi
if grep -Fq '멤버십 활성' "$ASSET_JS"; then
	fail 'checked-in app.js must not render the redundant paid membership active label'
fi
grep -Fq '.ssh-safeshield-upgrade-card' "$ASSET_CSS" || \
	fail 'checked-in app.css must include the FREE upgrade CTA treatment'
grep -Fq '.ssh-safeshield-license-summary' "$ASSET_CSS" || \
	fail 'checked-in app.css must include the refined SafeShield license summary styles'
grep -Fq 'ssh-safeshield-license-editor' "$ASSET_JS" || \
	fail 'checked-in app.js must include the refined SafeShield license editor markup'
grep -Fq '.ssh-safeshield-refresh-loader-svg' "$ASSET_CSS" || \
	fail 'checked-in app.css must include the SafeShield round loader styles'
grep -Fq '@keyframes ssh-safeshield-refresh-loader-rotate' "$ASSET_CSS" || \
	fail 'checked-in app.css must include the SafeShield round loader rotation animation'
grep -Fq '.ssh-safeshield-refresh-loader-track{color:#cbd5e1;stroke:#cbd5e1}' "$ASSET_CSS" || \
	fail 'light-theme SafeShield loader track must use a clearly visible neutral ring'
grep -Fq '.ssh-safeshield-refresh-loader-arc{color:#0f172a;stroke:#0f172a' "$ASSET_CSS" || \
	fail 'light-theme SafeShield loader arc must use an explicit near-black stroke for maximum contrast'
grep -Fq '.ssh-app[data-theme=dark] .ssh-safeshield-refresh-loader-arc{color:#fff;stroke:#fff' "$ASSET_CSS" || \
	fail 'dark-theme SafeShield loader arc must use an explicit white stroke for maximum contrast'
grep -Fq '.ssh-app[data-theme=dark] .ssh-safeshield-refresh-donut-label{color:#5eead4}' "$ASSET_CSS" || \
	fail 'dark-theme SafeShield loader step label must remain legible inside the ring'
grep -Fq 'prefers-reduced-motion:reduce' "$ASSET_CSS" || \
	fail 'checked-in app.css must preserve reduced-motion handling for the SafeShield round loader'

if grep -Fq '차단 목록 갱신 작업을 시작했습니다.' "$ACTIONS" || \
	grep -Fq '차단 목록을 이미 갱신하고 있습니다.' "$ACTIONS" || \
	grep -Fq '차단 목록 갱신 요청을 처리했습니다.' "$ACTIONS"; then
	fail 'SafeShield manual refresh must not leave transient progress feedback in the persistent action banner'
fi
grep -Fq 'await requestSafeShieldRefresh();' "$ACTIONS" || \
	fail 'SafeShield manual refresh must still request the backend refresh operation'
grep -Fq 'setState({ action: null, error: null, feedbackTarget: null, message: null });' "$ACTIONS" || \
	fail 'SafeShield manual refresh must clear action feedback after the request is accepted'
if grep -Fq '차단 목록 갱신 작업을 시작했습니다.' "$ASSET_JS" || \
	grep -Fq '차단 목록을 이미 갱신하고 있습니다.' "$ASSET_JS" || \
	grep -Fq '차단 목록 갱신 요청을 처리했습니다.' "$ASSET_JS"; then
	fail 'checked-in app.js must not retain transient SafeShield manual refresh feedback'
fi

grep -Fq 'const statusTimers = useRef<number[]>([]);' "$ACTIONS" || \
	fail 'SafeShield status follow-up refreshes must use their own timer list'
grep -Fq 'const statisticsTimers = useRef<number[]>([]);' "$ACTIONS" || \
	fail 'SafeShield statistics follow-up refreshes must use their own timer list'
if grep -Fq 'const timers = useRef<number[]>([]);' "$ACTIONS"; then
	fail 'SafeShield status and statistics follow-up refreshes must not share one timer list'
fi
grep -Fq 'statusTimers.current = delays.map' "$ACTIONS" || \
	fail 'SafeShield status refresh scheduling must write only to the status timer list'
grep -Fq 'statisticsTimers.current = delays.map' "$ACTIONS" || \
	fail 'SafeShield statistics refresh scheduling must write only to the statistics timer list'

grep -Fq 'const SUCCESS_FEEDBACK_TIMEOUT_MS = 4500;' "$ACTIONS" || \
	fail 'SafeShield success feedback must use the 4.5-second auto-dismiss policy'
grep -Fq 'const feedbackTimer = useRef<number | null>(null);' "$ACTIONS" || \
	fail 'SafeShield success feedback must manage its own dismiss timer'
grep -Fq 'const showSuccessMessage = useCallback(' "$ACTIONS" || \
	fail 'SafeShield action success messages must use the shared auto-dismiss helper'
grep -Fq 'current.error !== null || current.action !== null' "$ACTIONS" || \
	fail 'SafeShield success auto-dismiss must never clear an active action or persistent error'
grep -Fq 'clearFeedbackTimer();' "$ACTIONS" || \
	fail 'SafeShield actions must clear stale success-feedback timers before lifecycle changes'

if ! grep -Eq '(^|[^0-9])4500([^0-9]|$)' "$ASSET_JS" && \
	! grep -Fq '45e2' "$ASSET_JS"; then
	fail 'checked-in app.js must include the 4.5-second SafeShield success-feedback timeout policy'
fi

echo 'PASS: SafeShield product page hierarchy, refresh progress and switch contracts are present'
