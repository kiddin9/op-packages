#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Network Watch screen contract: reuse existing APIs; no collector or polling proliferation.
set -eu
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
PAGE="$ROOT/frontend/src/pages/NetworkWatchPage.tsx"
APP="$ROOT/frontend/src/app/App.tsx"
DEMO="$ROOT/frontend/src/demo/main.tsx"
DATA="$ROOT/frontend/src/demo/data.ts"
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
for file in "$PAGE" "$APP" "$DEMO" "$DATA"; do [ -f "$file" ] || fail "missing $file"; done
for str in 'role="switch"' 'aria-checked={enabled}' 'ssh-switch-control' 'ssh-switch-thumb' 'setTimeout(() => setNotice(null), 3500)' 'formatTimestamp(data.sampledAt)' '관찰 상태' '정상 범위' '변화 관찰' '학습 중' '이상 증가 감지' '판단 보류' '기기 이름을 확인할 수 없으면 IP만 표시합니다' 'recentWarnings(activity)' '최근 감지 이벤트' '관찰 범위 안내' 'list-disc'; do
    grep -Fq "$str" "$PAGE" || fail "화면 설정 및 표시 계약 누락: $str"
done
# One unified responsive summary card must include the training status, without a separate
# full-width training section or three standalone metric cards.
for str in 'Network Watch 관찰 요약과 학습' 'grid-cols-1 gap-4 sm:grid-cols-3 xl:grid-cols-5' 'sm:col-span-3 xl:col-span-2' '최장 학습 기기 기준' '정상 통신 패턴 학습' 'aria-valuemax={trainingTarget}' 'aria-valuenow={trainingDays}' '7일 · 기준 형성' '{trainingTarget}일 · 안정화' '기준 확보' '현재 관찰 기기 기준' '관찰된 IPv4 외부 연결' '외부 통신 기기'; do
    grep -Fq "$str" "$PAGE" || fail "통합 관찰 상태 카드의 배치·접근성 계약 누락: $str"
done
for str in 'sortObservedDevices' 'visibleDevices.map' 'lg:hidden' 'lg:block' 'TrafficMetric' 'data.limited ? null : (device.baselineConnections ?? null)' 'data.limited ? null : (device.baselineDestinations ?? null)'; do
    grep -Fq "$str" "$PAGE" || fail "기기별 정렬·모바일·평소 기준 표시 누락: $str"
done
! grep -Fq 'max-w-xs' "$PAGE" || fail '학습 진행률 너비가 다시 좁아지면 안 됨'
! grep -Fq 'grid gap-3 sm:grid-cols-3' "$PAGE" || fail '분리된 요약 카드가 남아 있음'
[ "$(grep -Fc '기기별 정상 패턴 학습' "$PAGE" || true)" -eq 0 ] || fail '기존 독립 학습 카드가 남아 있음'
# Match SafeShield's compact SectionHeading action instead of a full-width settings card.
for str in 'action={' 'NetworkNodesIcon class="size-5"' '관찰 수집' '사용 중 · 관찰 중' '사용 중 · 수집 불가' '상태 확인 불가' 'aria-busy={saving}'; do
    grep -Fq "$str" "$PAGE" || fail "Network Watch 상단 상태·토글 계약 누락: $str"
done
! grep -Fq '<h2 class="text-base font-extrabold text-slate-900">네트워크 이상 감지</h2>' "$PAGE" || fail '상단의 기존 전체 너비 설정 카드가 남아 있음'
# A warning is never an automatic security verdict; the count threshold is only a label.
grep -Fq "return { label: '관찰 중'" "$PAGE" || fail '정상·안전 확정 배지를 추가하면 안 됨'
grep -Fq 'event.eventType === '\''network_watch.anomaly.warning'\''' "$PAGE" || fail '무관한 최근 활동을 감지 이벤트로 표시하면 안 됨'
grep -Fq 'event.source === '\''network_watch'\''' "$PAGE" || fail '이벤트 출처 필터 누락'
grep -Fq '.slice(0, 3)' "$PAGE" || fail '최근 이벤트 3개 제한 누락'
grep -Fq "const devices = useConnectedDevices(route === 'devices' || route === 'netwatch', route === 'devices');" "$APP" || fail '기존 기기 조회를 재사용하고 기기 화면에만 15초 polling 유지해야 함'
grep -Fq 'loader: fetchActivityHistory,' "$APP" || fail '기존 최근 활동 API를 재사용해야 함'
grep -Fq 'active: route === '\''netwatch'\''' "$APP" || fail 'Netwatch에서만 추가 활동 정보를 조회해야 함'
grep -Fq 'devices={devices.data}' "$APP" || fail '기기명 데이터 전달 누락'
grep -Fq 'activity={netwatchActivity.data}' "$APP" || fail '최근 이벤트 전달 누락'
grep -Fq 'devices={demoDevices} activity={demoActivity}' "$DEMO" || fail '데모 페이지에 신규 UI 데이터 반영 누락'
grep -Fq "eventType: 'network_watch.anomaly.warning'" "$DATA" || fail '데모 이벤트 예시 누락'
! grep -Eq 'conntrack|/proc/net|nlbwmon' "$APP" || fail '프론트엔드에서 연결 관찰기를 실행하면 안 됨'
printf 'PASS: Network Watch 화면·데모·기존 API 재사용 계약\n'
