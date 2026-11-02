#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Contract: section context sits outside content cards; interactive controls remain with their card.
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
PAGE="$ROOT_DIR/frontend/src/pages"
COMP="$ROOT_DIR/frontend/src/components"
fail() { echo "FAIL: $*" >&2; exit 1; }

[ -f "$COMP/SectionHeading.tsx" ] || fail 'Shared section heading missing'
grep -Fq 'ssh-section-heading mb-4 min-w-0' "$COMP/SectionHeading.tsx" || fail 'Shared section spacing missing'
grep -Fq '<h2 class=' "$COMP/SectionHeading.tsx" || fail 'Accessible section title missing'
grep -Fq '{action ?' "$COMP/SectionHeading.tsx" || fail 'Shared heading action slot missing'

# Tall toggle/status controls must not increase the vertical gap between
# eyebrow, title and description (SafeShield statistics, Network Watch).
grep -Fq "sm:grid-cols-[minmax(0,1fr)_auto]" "$COMP/SectionHeading.tsx" || \
  fail 'SectionHeading must keep the action in a separate desktop grid column'
grep -Fq 'h2 class="mt-2 mb-0' "$COMP/SectionHeading.tsx" || \
  fail 'SectionHeading title must follow the eyebrow without action-driven vertical centering'
grep -Fq 'p class="mt-2 mb-0 text-sm leading-6' "$COMP/SectionHeading.tsx" || \
  fail 'SectionHeading description must keep the same title gap'
grep -Fq 'sm:mt-3 sm:justify-self-end' "$COMP/SectionHeading.tsx" || \
  fail 'SectionHeading action must align independently without stretching the title row'
if grep -Fq 'flex min-w-0 flex-wrap items-center justify-between' "$COMP/SectionHeading.tsx"; then
  fail 'SectionHeading must not vertically center titles against tall actions'
fi

for name in HomePage SafeShieldPage ActivityPage ConnectedDevicesPage WanPage LanPage WifiPage IptvPage SmartSafeHubAccountPage SafeShieldRulesPage UpdatePage SettingsPage; do
  grep -Fq 'SectionHeading' "$PAGE/$name.tsx" || fail "$name does not use common section style"
done

# Core screens follow the same title > card order (no nested section title in card).
for pair in \
  'SafeShieldStatisticsPanel.tsx:최근 24시간 보호 활동' \
  'ActivityPage.tsx:현재 부팅 이후의 최근 활동' \
  'ConnectedDevicesPage.tsx:기기 목록' \
  'WanPage.tsx:인터넷 연결 설정' \
  'LanPage.tsx:LAN 및 DHCP 설정' \
  'IptvPage.tsx:IPTV 동작 상태' \
  'SafeShieldRulesPage.tsx:사용자 도메인 규칙' \
  'SmartSafeHubAccountPage.tsx:기기 계정 연결'; do
  name=${pair%%:*}
  title=${pair#*:}
  file="$PAGE/$name"
  [ "$name" = 'SafeShieldStatisticsPanel.tsx' ] && file="$COMP/$name"
  grep -Fq "title=\"$title\"" "$file" || fail "Section heading missing: $name/$title"
done

# The two desktop summary cards should have equal height without forcing a
# fixed height on mobile or while asynchronous status text changes.
grep -Fq 'gap-5 xl:items-stretch xl:grid-cols-[minmax(0,1.2fr)_minmax(18rem,0.8fr)]' "$PAGE/SmartSafeHubAccountPage.tsx" || \
  fail 'Account connection and status cards must stretch to equal height at desktop widths'
grep -Fq 'gap-4 xl:grid-cols-[minmax(0,1.08fr)_minmax(0,0.92fr)] xl:items-stretch' "$PAGE/SafeShieldPage.tsx" || \
  fail 'SafeShield protection summary and protection data cards must stretch to equal height'

# Explicitly fill the stretched row for both cards, even as status text
# changes asynchronously. Only use this at desktop widths.
[ "$(grep -Fc 'bg-white p-5 shadow-sm shadow-slate-900/5 sm:p-6 xl:h-full' "$PAGE/SafeShieldPage.tsx")" -ge 2 ] || \
  fail 'Both SafeShield summary cards must fill their desktop grid row'
[ "$(grep -Fc 'bg-white p-5 shadow-sm shadow-slate-900/5 sm:p-6 xl:h-full' "$PAGE/SmartSafeHubAccountPage.tsx")" -eq 2 ] || \
  fail 'Account connection and status cards must fill their desktop grid row'

# Protection controls and their current status must stay together in a functional card.
grep -Fq 'SafeShield 보호 상태' "$PAGE/SafeShieldPage.tsx" || fail 'Protection card heading removed'
grep -Fq 'aria-label={targetEnabled ?' "$COMP/SafeShieldStatisticsPanel.tsx" || fail 'Statistics collection switch removed'
grep -Fq 'role="switch"' "$PAGE/IptvPage.tsx" || fail 'IPTV switch removed'
grep -Fq '저장되지 않음' "$PAGE/WanPage.tsx" || fail 'WAN dirty state removed'
grep -Fq '저장되지 않음' "$PAGE/LanPage.tsx" || fail 'LAN dirty state removed'
grep -Fq 'id="diagnostics-panel"' "$PAGE/SettingsPage.tsx" || fail 'Settings diagnostics panel missing'
grep -Fq 'id="time-panel"' "$PAGE/SettingsPage.tsx" || fail 'Settings time panel missing'
grep -Fq 'id="management-panel"' "$PAGE/SettingsPage.tsx" || fail 'Settings management panel missing'

# Same section headings must be kept in production and demo: only shared source is modified.

echo 'PASS: common section-first layout contract'
