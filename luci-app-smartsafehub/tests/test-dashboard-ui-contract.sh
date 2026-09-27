#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
APP="$ROOT_DIR/frontend/src/app/App.tsx"
HOME="$ROOT_DIR/frontend/src/pages/HomePage.tsx"
ACTIVITY="$ROOT_DIR/frontend/src/components/DashboardSafeShieldActivity.tsx"
DEVICES_HOOK="$ROOT_DIR/frontend/src/hooks/useConnectedDevices.ts"
STATISTICS_HOOK="$ROOT_DIR/frontend/src/hooks/useSafeShieldStatistics.ts"
FORMAT="$ROOT_DIR/frontend/src/app/format.ts"
HEALTH_HOOK="$ROOT_DIR/frontend/src/hooks/useHealth.ts"
APP_STYLE="$ROOT_DIR/frontend/src/styles/app.css"
UPDATE_FRESHNESS="$ROOT_DIR/frontend/src/utils/softwareUpdates.ts"

fail() {
	echo "FAIL: $*" >&2
	exit 1
}

for file in "$APP" "$HOME" "$ACTIVITY" "$DEVICES_HOOK" "$STATISTICS_HOOK" "$FORMAT" "$HEALTH_HOOK" "$APP_STYLE" "$UPDATE_FRESHNESS"; do
	[ -f "$file" ] || fail "대시보드 소스 파일이 없습니다: ${file#$ROOT_DIR/}"
done

grep -Fq "const dashboardDevices = useConnectedDevices(route === 'home', false);" "$APP" || \
	fail '대시보드 연결 기기 요약은 주기 polling을 사용하지 않아야 합니다'
grep -Fq "const dashboardSafeShield = useSafeShieldStatus(route === 'home');" "$APP" || \
	fail '대시보드는 SafeShield 상태를 불러와야 합니다'
grep -Fq "const dashboardSafeShieldStatistics = useSafeShieldStatistics(route === 'home', false);" "$APP" || \
	fail '대시보드 SafeShield 통계는 주기 polling을 사용하지 않아야 합니다'
grep -Fq "route === 'system' || route === 'home' || route === 'settings'" "$APP" || \
	fail '대시보드와 설정 페이지는 SmartSafeHub 펌웨어 식별 정보를 불러와야 합니다'
grep -Fq 'devices={dashboardDevices.data}' "$APP" || \
	fail '대시보드는 연결 기기 요약 데이터를 전달받아야 합니다'
grep -Fq 'safeshield={dashboardSafeShield.data}' "$APP" || \
	fail '대시보드는 SafeShield 상태를 전달받아야 합니다'
grep -Fq 'statistics={dashboardSafeShieldStatistics.data}' "$APP" || \
	fail '대시보드는 SafeShield 통계를 전달받아야 합니다'
grep -Fq 'firmware={firmware.data}' "$APP" || \
	fail '대시보드는 SmartSafeHub 펌웨어 상태를 전달받아야 합니다'
grep -Fq "const health = useHealth(route === 'home' || route === 'settings');" "$APP" || \
	fail '대시보드와 설정 페이지가 같은 로컬 Health 상태를 조회해야 합니다'
grep -Fq "const lan = useLan(route === 'home' || route === 'lan');" "$APP" || \
	fail '대시보드는 LAN/WAN 대역과 충돌 상태를 함께 조회해야 합니다'
grep -Fq 'health={health.data}' "$APP" || \
	fail '대시보드에 로컬 Health 진단 데이터를 전달해야 합니다'
grep -Fq 'healthError={health.error}' "$APP" || \
	fail '대시보드에 로컬 Health 조회 오류를 전달해야 합니다'
grep -Fq 'healthLoading={health.loading}' "$APP" || \
	fail '대시보드에 로컬 Health 로딩 상태를 전달해야 합니다'
grep -Fq 'lan={lan.data}' "$APP" || \
	fail '대시보드에 LAN/WAN 대역 데이터를 전달해야 합니다'
grep -Fq 'lanError={lan.error}' "$APP" || \
	fail '대시보드에 LAN 대역 조회 오류를 전달해야 합니다'
grep -Fq 'lanLoading={lan.loading}' "$APP" || \
	fail '대시보드에 LAN 대역 조회 로딩 상태를 전달해야 합니다'
grep -Fq 'dashboardDevices.refresh()' "$APP" || \
	fail '대시보드 새로고침은 연결 기기 정보를 갱신해야 합니다'
grep -Fq 'dashboardSafeShield.refresh()' "$APP" || \
	fail '대시보드 새로고침은 SafeShield 정보를 갱신해야 합니다'
grep -Fq 'dashboardSafeShieldStatistics.refresh()' "$APP" || \
	fail '대시보드 새로고침은 SafeShield 통계를 갱신해야 합니다'
grep -Fq 'updates.refresh()' "$APP" || \
	fail '대시보드 새로고침은 업데이트 정보를 갱신해야 합니다'
grep -Fq 'firmware.refresh()' "$APP" || \
	fail '대시보드 새로고침은 펌웨어 식별 정보를 갱신해야 합니다'
lan_refresh_count="$(grep -Fc 'lan.refresh()' "$APP")"
[ "$lan_refresh_count" -ge 3 ] || \
	fail 'LAN 페이지 재시도와 대시보드 재시도·전역 새로고침에 LAN 대역 조회가 포함되어야 합니다'
home_refresh_count="$(grep -Fc 'health.refresh()' "$APP")"
[ "$home_refresh_count" -ge 3 ] || \
	fail '대시보드 재시도·전역 새로고침과 설정 새로고침에 Health 조회가 포함되어야 합니다'
grep -Fq 'health.refreshing ||' "$APP" || \
	fail '대시보드 전역 새로고침 표시가 Health 갱신 상태를 포함해야 합니다'
grep -Fq 'lan.refreshing)) ||' "$APP" || \
	fail '대시보드 전역 새로고침 표시가 LAN 대역 갱신 상태를 포함해야 합니다'

grep -Fq 'export function useConnectedDevices(active: boolean, polling = true)' "$DEVICES_HOOK" || \
	fail '연결 기기 hook은 대시보드의 단발성 조회를 지원해야 합니다'
grep -Fq '...(polling ? { pollInterval: REFRESH_INTERVAL_MS } : {}),' "$DEVICES_HOOK" || \
	fail '대시보드 연결 기기 조회는 15초 polling을 예약하지 않아야 합니다'

grep -Fq 'export function useConnectedDevices(active: boolean, polling = true)' "$DEVICES_HOOK" || \
	fail '연결 기기 hook은 대시보드의 단발성 조회를 지원해야 합니다'

grep -Fq '...(polling ? { pollInterval: REFRESH_INTERVAL_MS } : {}),' "$DEVICES_HOOK" || \
	fail '대시보드 연결 기기 polling을 끄면 pollInterval을 생략해야 합니다'

grep -Fq 'export function useSafeShieldStatistics(active: boolean, polling = true)' "$STATISTICS_HOOK" || \
	fail 'SafeShield 통계 hook은 대시보드의 단발성 조회를 지원해야 합니다'
grep -Fq '...(polling ? { pollInterval: STATISTICS_REFRESH_INTERVAL_MS } : {}),' "$STATISTICS_HOOK" || \
	fail '대시보드 SafeShield 통계 polling을 끄면 pollInterval을 생략해야 합니다'

for hook in "$DEVICES_HOOK" "$STATISTICS_HOOK"; do
	if grep -Fq 'pollInterval: polling ?' "$hook"; then
		fail "선택적 polling은 null/undefined를 넣지 말고 pollInterval 자체를 생략해야 합니다: ${hook#$ROOT_DIR/}"
	fi
done

grep -Fq 'title="시스템 개요"' "$HOME" || \
	fail '대시보드는 제품 스타일의 시스템 개요 제목을 사용해야 합니다'
grep -Fq 'eyebrow="SafeShield"' "$HOME" || \
	fail '대시보드는 SafeShield 보호 요약을 표시해야 합니다'
grep -Fq 'eyebrow="Connected devices"' "$HOME" || \
	fail '대시보드는 연결 기기 정보를 표시해야 합니다'
grep -Fq 'eyebrow="Software update"' "$HOME" || \
	fail '대시보드는 소프트웨어 업데이트 정보를 표시해야 합니다'
grep -Fq 'const networkConflict = Boolean(lan?.conflict.detected);' "$HOME" || \
	fail 'Internet 개요 카드는 WAN/LAN 대역 충돌 상태를 사용해야 합니다'
grep -Fq 'href="#lan"' "$HOME" || \
	fail 'Internet 개요와 연결 상태 상세는 LAN 설정으로 연결되어야 합니다'
grep -Fq "linkLabel={networkConflict ? '해결하기 →' : '자세히 보기 →'}" "$HOME" || \
	fail 'Internet 개요 카드는 정상 상태에서 다른 개요 카드와 같은 자세히 보기 문구를 사용하고 충돌 시 해결하기를 표시해야 합니다'
grep -Fq "? '⚠ LAN 대역과 충돌합니다'" "$HOME" || \
	fail 'Internet 개요 카드는 대역 충돌을 명확하게 경고해야 합니다'
grep -Fq "? '✓ 네트워크 충돌 없음'" "$HOME" || \
	fail 'Internet 개요 카드는 정상 대역 상태를 간결하게 표시해야 합니다'
grep -Fq 'label="상위 네트워크"' "$HOME" || \
	fail '연결 상태 상세에 상위 WAN 네트워크 대역을 표시해야 합니다'
grep -Fq 'label="LAN 네트워크"' "$HOME" || \
	fail '연결 상태 상세에 SmartSafeHub LAN 네트워크 대역을 표시해야 합니다'
grep -Fq 'label="대역 충돌"' "$HOME" || \
	fail '연결 상태 상세에 WAN/LAN 대역 충돌 결과를 표시해야 합니다'
grep -Fq '? `${data.network.ipv4Address} · 사설 네트워크`' "$HOME" || \
	fail '사설 WAN 주소는 상위 NAT 환경임을 구분할 수 있어야 합니다'
grep -Fq 'const [firstOctet, secondOctet] = octets;' "$HOME" || \
	fail '사설 WAN 판별은 strict indexed access에서 안전한 octet 변수를 사용해야 합니다'
grep -Fq 'firstOctet === undefined || secondOctet === undefined' "$HOME" || \
	fail '사설 WAN 판별은 배열 인덱스가 undefined일 가능성을 명시적으로 차단해야 합니다'
if grep -Eq 'octets\[1\][[:space:]]*(>=|<=|===|==|>|<)' "$HOME"; then
	fail '사설 WAN 판별에서 noUncheckedIndexedAccess를 우회하는 직접 배열 비교를 사용하면 안 됩니다'
fi
grep -Fq 'LAN 설정 보기' "$HOME" || \
	fail '연결 상태 상세 카드의 주 동작은 LAN 설정으로 이동해야 합니다'
grep -Fq 'title="네트워크 보호 활동"' "$HOME" || \
	fail '대시보드는 네트워크 보호 활동 영역을 표시해야 합니다'
grep -Fq '<DashboardSafeShieldActivity' "$HOME" || \
	fail '대시보드는 SafeShield 활동 시각화를 렌더링해야 합니다'
grep -Fq 'title="시스템 상태"' "$HOME" || \
	fail '대시보드는 시스템 상태 영역을 표시해야 합니다'
grep -Fq 'function DashboardHealthSummary({' "$HOME" || \
	fail '대시보드 시스템 상태에 로컬 장치 진단 요약 컴포넌트가 있어야 합니다'
grep -Fq '>장치 진단</p>' "$HOME" || \
	fail '대시보드 리소스 카드에서 장치 진단 제목을 표시해야 합니다'
grep -Fq '마지막 진단: {formatRelativeTime(data.generatedAt, nowTimestamp)} · 검사 항목:' "$HOME" || \
	fail '장치 진단 요약은 마지막 진단 시각과 검사 항목 수를 표시해야 합니다'
grep -Fq '{data.summary.total}개' "$HOME" || \
	fail '장치 진단 요약은 전체 검사 항목 수를 표시해야 합니다'
grep -Fq 'const visibleIssues = noteworthy.slice(0, 2);' "$HOME" || \
	fail '대시보드에서는 비정상 진단 항목을 최대 2건까지만 표시해야 합니다'
grep -Fq '외 {hiddenIssueCount}건의 확인 항목이 있습니다.' "$HOME" || \
	fail '표시하지 못한 비정상 진단 항목 수를 요약해야 합니다'
grep -Fq 'href="#settings"' "$HOME" || \
	fail '장치 진단의 상세 보기는 설정 페이지로 연결되어야 합니다'
grep -Fq '아직 생성된 진단 결과가 없습니다.' "$HOME" || \
	fail '진단 결과가 아직 없을 때 대기 상태를 표시해야 합니다'
grep -Fq "status === 'initializing'" "$HOME" || \
	fail '대시보드 장치 진단은 부팅 초기화 상태를 별도 준비 중 톤으로 표시해야 합니다'
grep -Fq "label: '준비 중'" "$HOME" || \
	fail '대시보드 장치 진단의 initializing 상태 라벨은 준비 중이어야 합니다'
grep -Fq "data.overall === 'initializing'" "$HOME" || \
	fail '대시보드 장치 진단은 initializing 상태에 경고 아이콘 대신 대기 아이콘을 사용해야 합니다'
grep -Fq '진단 상태를 확인하지 못했습니다.' "$HOME" || \
	fail '진단 조회 실패 시 확인 필요 상태를 표시해야 합니다'
if grep -Fq 'reporter.enabled' "$HOME" || grep -Fq '원격 상태 보고' "$HOME"; then
	fail '대시보드는 원격 Health Reporter 설정을 노출하지 않고 로컬 진단 요약만 표시해야 합니다'
fi

grep -Fq "[class~='bg-emerald-50/70']" "$APP_STYLE" || \
	fail '다크 모드에서 정상 장치 진단 배경을 어두운 emerald 톤으로 재매핑해야 합니다'
grep -Fq "[class~='bg-amber-50/70']" "$APP_STYLE" || \
	fail '다크 모드에서 주의 장치 진단 배경을 어두운 amber 톤으로 재매핑해야 합니다'
grep -Fq "[class~='bg-rose-50/70']" "$APP_STYLE" || \
	fail '다크 모드에서 이상 장치 진단 배경을 어두운 rose 톤으로 재매핑해야 합니다'
grep -Fq "[class~='bg-white/70']" "$APP_STYLE" || \
	fail '다크 모드에서 장치 진단 세부 항목의 반투명 흰 배경을 어두운 배경으로 재매핑해야 합니다'
grep -Fq "[class~='border-white/80']" "$APP_STYLE" || \
	fail '다크 모드에서 장치 진단 세부 항목의 흰 테두리를 어두운 테두리로 재매핑해야 합니다'
if grep -Fq 'title="최근 상태 확인"' "$HOME" || grep -Fq 'dashboard-freshness-title' "$HOME"; then
	fail '대시보드는 별도의 최근 상태 확인 영역을 다시 추가하지 않아야 합니다'
fi
grep -Fq 'formatRelativeTime(timestamp, nowTimestamp)' "$HOME" || \
	fail '대시보드 개요 카드는 최근 확인 시각을 상대 시간으로 표시해야 합니다'
grep -Fq "safeShieldStale ? '차단 목록 갱신 지연' : '차단 목록 갱신'" "$HOME" || \
	fail 'SafeShield 개요 카드가 최근 갱신 정보와 지연 경고를 직접 표시해야 합니다'
grep -Fq "'목록 확인'," "$HOME" || \
	fail '연결 기기 개요 카드는 마지막 목록 확인 시각을 정보성 메타데이터로 표시해야 합니다'
if grep -Fq 'devicesStale' "$HOME" || grep -Fq 'DEVICE_SUMMARY_STALE_AFTER_S' "$HOME"; then
	fail '연결 기기 목록 확인 시각이 오래되었다는 이유만으로 주의 상태를 만들면 안 됩니다'
fi
if grep -Fq 'metaWarning={devicesStale}' "$HOME"; then
	fail '연결 기기 목록 확인 시각은 노란색 경고 메타데이터로 표시하면 안 됩니다'
fi
grep -Fq "state={devices ? 'healthy' : devicesError ? 'warning' : 'neutral'}" "$HOME" || \
	fail '연결 기기 데이터가 있으면 목록 확인 시각과 관계없이 정상 상태를 유지해야 합니다'
grep -Fq "updatesStale ? '업데이트 확인 지연' : '마지막 확인'" "$HOME" || \
	fail '소프트웨어 업데이트 개요 카드가 최근 확인 정보와 지연 경고를 직접 표시해야 합니다'
grep -Fq 'const updatesStale = isSoftwareUpdateCheckStale(updates, relativeNow);' "$HOME" || \
	fail '대시보드와 업데이트 페이지는 같은 관리 소프트웨어 지연 기준을 사용해야 합니다'
grep -Fq "import { isSoftwareUpdateCheckStale } from '../utils/softwareUpdates';" "$HOME" || \
	fail '대시보드는 공통 관리 소프트웨어 freshness helper를 사용해야 합니다'
grep -Fq '{label}: {formatRelativeTime(timestamp, nowTimestamp)}' "$HOME" || \
	fail '대시보드 최근 확인 문구는 항목과 상대 시간을 콜론으로 구분해야 합니다'
grep -Fq "updates && !updates.settings.checkEnabled" "$HOME" || \
	fail '소프트웨어 자동 확인이 꺼져 있으면 지연 상태로 표시하지 않아야 합니다'
grep -Fq 'const RELATIVE_TIME_TICK_MS = 60_000;' "$HOME" || \
	fail '대시보드 상대 시간 문구는 백엔드 polling 없이 1분마다 갱신되어야 합니다'
grep -Fq "return '방금 전';" "$FORMAT" || \
	fail '상대 시간 formatter는 방금 전 상태를 지원해야 합니다'
grep -Fq 'Math.floor(elapsedSeconds / 60)}분 전' "$FORMAT" || \
	fail '상대 시간 formatter는 분 단위를 지원해야 합니다'
grep -Fq 'Math.floor(elapsedSeconds / 3_600)}시간 전' "$FORMAT" || \
	fail '상대 시간 formatter는 시간 단위를 지원해야 합니다'
grep -Fq 'Math.floor(elapsedSeconds / 86_400)}일 전' "$FORMAT" || \
	fail '상대 시간 formatter는 일 단위를 지원해야 합니다'
grep -Fq 'formatLoadAverage(data.runtime.load[1])' "$HOME" || \
	fail '대시보드는 5분 시스템 부하를 표시해야 합니다'
grep -Fq 'formatLoadAverage(data.runtime.load[2])' "$HOME" || \
	fail '대시보드는 15분 시스템 부하를 표시해야 합니다'
grep -Fq "const customFirmwareAvailable = Boolean(firmware?.current.metadataAvailable);" "$HOME" || \
	fail '대시보드 장치 정보는 SmartSafeHub 커스텀 펌웨어 메타데이터를 감지해야 합니다'
grep -Fq '`SmartSafeHub ${firmware.current.releaseVersion}`' "$HOME" || \
	fail '대시보드 장치 정보는 SmartSafeHub 제품 펌웨어 버전을 우선 표시해야 합니다'
grep -Fq "firmware?.current.buildId || data.software.revision" "$HOME" || \
	fail '대시보드 장치 정보는 immutable SmartSafeHub build ID를 우선 표시해야 합니다'
grep -Fq "const deviceRevisionLabel = customFirmwareAvailable ? '빌드 ID' : '리비전';" "$HOME" || \
	fail '대시보드는 커스텀 펌웨어 식별자를 빌드 ID로 표시하고 OpenWrt 리비전 fallback을 유지해야 합니다'
grep -Fq '`${data.software.distribution} ${data.software.version}`' "$HOME" || \
	fail '대시보드 장치 정보는 기존 이미지용 OpenWrt 펌웨어 fallback을 유지해야 합니다'
grep -Fq '<DetailRow label="커널" value={data.software.kernel} />' "$HOME" || \
	fail '대시보드 장치 정보는 실제 실행 중인 커널 버전을 유지해야 합니다'
grep -Fq 'value={data.network.ipv4Address || '\''할당되지 않음'\''}' "$HOME" || \
	fail '대시보드 장치 정보는 WAN 주소를 포함해야 합니다'

grep -Fq 'aria-label={`메모리 사용률 ${memoryPercent}%`}' "$HOME" || \
	fail '대시보드 메모리 카드에 사용률 진행 막대가 있어야 합니다'
grep -Fq 'class="mt-3 h-1.5 overflow-hidden rounded-full bg-slate-200"' "$HOME" || \
	fail '대시보드 메모리 진행 막대는 메모리 카드 안에 유지되어야 합니다'
if grep -Fq '<span>메모리 사용률</span>' "$HOME"; then
	fail '대시보드는 메모리 사용률을 별도 블록으로 중복 표시하지 않아야 합니다'
fi

grep -Fq "import { SafeShieldBlockedBarChart } from './SafeShieldBlockedBarChart';" "$ACTIVITY" || \
	fail '대시보드는 기존 SafeShield Chart.js 막대 차트를 재사용해야 합니다'
grep -Fq 'const DISPLAY_HOURS = 24;' "$ACTIVITY" || \
	fail '대시보드 SafeShield 활동은 24시간 범위를 사용해야 합니다'
grep -Fq '<SafeShieldBlockedBarChart buckets={buckets} />' "$ACTIVITY" || \
	fail '대시보드는 시간별 차단 요청을 차트로 표시해야 합니다'
grep -Fq 'DNS 요청' "$ACTIVITY" || \
	fail '대시보드 SafeShield 활동은 DNS 요청 합계를 표시해야 합니다'
grep -Fq '차단율' "$ACTIVITY" || \
	fail '대시보드 SafeShield 활동은 차단율을 표시해야 합니다'
grep -Fq 'class="mt-1 mb-0 ml-0 text-lg font-black text-teal-700"' "$ACTIVITY" || \
	fail '대시보드 SafeShield 활동은 최근 24시간 차단 수를 teal로 강조해야 합니다'
[ "$(grep -Fc 'text-lg font-black text-teal-700' "$ACTIVITY")" -eq 1 ] || \
	fail '대시보드 SafeShield 활동은 차단 수만 teal로 강조해야 합니다'

echo 'PASS: 대시보드 개요, SafeShield 활동 차트, 로컬 진단 요약과 단발성 상태 조회 계약이 정상입니다'
