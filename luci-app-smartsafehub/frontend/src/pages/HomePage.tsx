import type { ComponentChildren } from 'preact';
import { useEffect, useMemo, useState } from 'preact/hooks';

import {
  AlertIcon,
  CheckCircleIcon,
  ClockIcon,
  DevicesIcon,
  GlobeIcon,
  MemoryIcon,
  RouterIcon,
  ShieldIcon,
  UpdateIcon,
} from '../components/Icons';
import { ActivityLoadState, ActivityTimeline } from '../components/ActivityTimeline';
import { DashboardSafeShieldActivity } from '../components/DashboardSafeShieldActivity';
import { ErrorPanel, LoadingPanel } from '../components/StatePanels';
import type { ActivityHistory } from '../types/activity';
import type { ConnectedDevicesSummary } from '../types/devices';
import type { FirmwareStatus } from '../types/firmware';
import type { HealthSeverity, HealthStatus } from '../types/health';
import type { LanSettings } from '../types/lan';
import type { SafeShieldStatistics, SafeShieldStatus } from '../types/safeshield';
import type { SmartSafeHubStatus } from '../types/status';
import type { SoftwareUpdateStatus } from '../types/updates';
import { isSoftwareUpdateCheckStale } from '../utils/softwareUpdates';
import {
  formatBootTime,
  formatBytes,
  formatLoadAverage,
  formatNumber,
  formatRelativeTime,
  formatTimestamp,
  formatUptime,
  getMemoryUsage,
} from '../app/format';

interface HomePageProps {
  activity: ActivityHistory | null;
  activityError: string | null;
  activityLoading: boolean;
  data: SmartSafeHubStatus | null;
  devices: ConnectedDevicesSummary | null;
  devicesError: string | null;
  devicesLoading: boolean;
  error: string | null;
  firmware: FirmwareStatus | null;
  firmwareError: string | null;
  firmwareLoading: boolean;
  health: HealthStatus | null;
  healthError: string | null;
  healthLoading: boolean;
  lan: LanSettings | null;
  lanError: string | null;
  lanLoading: boolean;
  loading: boolean;
  onRetry: () => void;
  safeshield: SafeShieldStatus | null;
  safeshieldError: string | null;
  safeshieldLoading: boolean;
  statistics: SafeShieldStatistics | null;
  statisticsError: string | null;
  statisticsLoading: boolean;
  statisticsRefreshing: boolean;
  updates: SoftwareUpdateStatus | null;
  updatesError: string | null;
  updatesLoading: boolean;
}

type OverviewState = 'healthy' | 'warning' | 'neutral';

interface OverviewCardProps {
  detail: string;
  eyebrow: string;
  href?: string;
  icon: ComponentChildren;
  linkLabel?: string;
  meta?: ComponentChildren;
  metaState?: OverviewState;
  metaWarning?: boolean;
  state?: OverviewState;
  value: string;
}

function stateClasses(state: OverviewState): string {
  if (state === 'healthy') {
    return 'bg-emerald-50 text-emerald-700 ring-emerald-200';
  }
  if (state === 'warning') {
    return 'bg-amber-50 text-amber-800 ring-amber-200';
  }
  return 'bg-slate-100 text-slate-600 ring-slate-200';
}

function OverviewCard({
  detail,
  eyebrow,
  href,
  icon,
  linkLabel = '자세히 보기 →',
  meta,
  metaState,
  metaWarning = false,
  state = 'neutral',
  value,
}: OverviewCardProps) {
  const content = (
    <>
      <div class="flex items-start justify-between gap-4">
        <p class="m-0 text-[0.68rem] font-black uppercase tracking-[0.16em] text-slate-500">
          {eyebrow}
        </p>
        <span
          class={`grid size-10 shrink-0 place-items-center rounded-xl ring-1 ring-inset ${stateClasses(state)}`}
        >
          {icon}
        </span>
      </div>
      <p class="mt-4 mb-0 break-words text-2xl font-black tracking-tight text-slate-950">
        {value}
      </p>
      <p class="mt-2 mb-0 min-h-10 text-sm font-medium leading-5 text-slate-500">
        {detail}
      </p>
      {meta ? (
        <p
          class={`mt-3 mb-0 text-xs font-bold ${
            metaState === 'healthy'
              ? 'text-emerald-700'
              : metaState === 'warning' || metaWarning
                ? 'text-amber-700'
                : 'text-slate-400'
          }`}
        >
          {meta}
        </p>
      ) : null}
      {href ? (
        <span class="mt-4 inline-flex text-xs font-extrabold text-teal-700">{linkLabel}</span>
      ) : null}
    </>
  );

  const className =
    'min-w-0 rounded-2xl border border-slate-200 bg-white p-5 shadow-sm shadow-slate-900/5 transition';

  if (href) {
    return (
      <a
        class={`${className} no-underline hover:border-slate-300 hover:shadow-md`}
        href={href}
      >
        {content}
      </a>
    );
  }

  return <article class={className}>{content}</article>;
}

function SectionHeading({
  description,
  eyebrow,
  id,
  title,
}: {
  description: string;
  eyebrow: string;
  id: string;
  title: string;
}) {
  return (
    <div class="mb-4">
      <p class="m-0 text-[0.68rem] font-black uppercase tracking-[0.18em] text-teal-700">
        {eyebrow}
      </p>
      <h2 class="mt-2 mb-0 text-xl font-black tracking-tight text-slate-950" id={id}>
        {title}
      </h2>
      <p class="mt-2 mb-0 text-sm leading-6 text-slate-500">{description}</p>
    </div>
  );
}

const RELATIVE_TIME_TICK_MS = 60_000;

function elapsedSeconds(timestamp: number | null | undefined, nowTimestamp: number): number | null {
  if (!timestamp || !Number.isFinite(timestamp) || timestamp <= 0) {
    return null;
  }

  return Math.max(0, nowTimestamp - timestamp);
}

function freshnessMeta(
  label: string,
  timestamp: number | null | undefined,
  nowTimestamp: number,
  fallback: string,
): ComponentChildren {
  if (!timestamp || timestamp <= 0) {
    return `${label}: ${fallback}`;
  }

  return (
    <span title={formatTimestamp(timestamp)}>
      {label}: {formatRelativeTime(timestamp, nowTimestamp)}
    </span>
  );
}

function networkProtocolLabel(protocol: string | null): string | null {
  if (!protocol) {
    return null;
  }

  switch (protocol.toLowerCase()) {
    case 'dhcp':
      return 'DHCP';
    case 'static':
      return 'Static';
    case 'pppoe':
      return 'PPPoE';
    default:
      return protocol.toUpperCase();
  }
}

function isPrivateIpv4(address: string | null): boolean {
  if (!address) {
    return false;
  }

  const octets = address.split('.').map((value) => Number(value));
  if (
    octets.length !== 4 ||
    octets.some((value) => !Number.isInteger(value) || value < 0 || value > 255)
  ) {
    return false;
  }

  const [firstOctet, secondOctet] = octets;
  if (firstOctet === undefined || secondOctet === undefined) {
    return false;
  }

  return (
    firstOctet === 10 ||
    (firstOctet === 172 && secondOctet >= 16 && secondOctet <= 31) ||
    (firstOctet === 192 && secondOctet === 168)
  );
}

function DetailRow({ label, value }: { label: string; value: ComponentChildren }) {
  return (
    <div class="flex min-w-0 items-start justify-between gap-4 border-b border-slate-100 py-3 last:border-b-0">
      <dt class="text-sm font-semibold text-slate-500">{label}</dt>
      <dd class="m-0 min-w-0 max-w-[68%] break-words text-right text-sm font-extrabold text-slate-950">
        {value}
      </dd>
    </div>
  );
}

function dashboardHealthTone(status: HealthSeverity): {
  badge: string;
  icon: string;
  label: string;
  panel: string;
} {
  if (status === 'initializing') {
    return {
      badge: 'bg-teal-100 text-teal-800',
      icon: 'text-teal-700',
      label: '준비 중',
      panel: 'border-teal-200 bg-teal-50',
    };
  }
  if (status === 'critical') {
    return {
      badge: 'bg-rose-100 text-rose-800',
      icon: 'text-rose-700',
      label: '이상',
      panel: 'border-rose-200 bg-rose-50/70',
    };
  }
  if (status === 'warning') {
    return {
      badge: 'bg-amber-100 text-amber-800',
      icon: 'text-amber-700',
      label: '주의',
      panel: 'border-amber-200 bg-amber-50/70',
    };
  }
  if (status === 'unknown') {
    return {
      badge: 'bg-slate-200 text-slate-700',
      icon: 'text-slate-500',
      label: '확인 불가',
      panel: 'border-slate-200 bg-slate-50',
    };
  }
  return {
    badge: 'bg-emerald-100 text-emerald-800',
    icon: 'text-emerald-700',
    label: '정상',
    panel: 'border-emerald-200 bg-emerald-50/70',
  };
}

function DashboardHealthSummary({
  data,
  error,
  loading,
  nowTimestamp,
}: {
  data: HealthStatus | null;
  error: string | null;
  loading: boolean;
  nowTimestamp: number;
}) {
  const hasDiagnostic = Boolean(data && data.generatedAt > 0);
  const tone = dashboardHealthTone(
    hasDiagnostic && data ? data.overall : 'unknown',
  );
  const noteworthy = hasDiagnostic && data
    ? data.checks.filter((check) => check.status !== 'ok')
    : [];
  const visibleIssues = noteworthy.slice(0, 2);
  const hiddenIssueCount = Math.max(0, noteworthy.length - visibleIssues.length);

  return (
    <div class="mt-5 border-t border-slate-200 pt-5">
      <div class="flex flex-wrap items-center justify-between gap-3">
        <div class="flex items-center gap-2">
          <p class="m-0 text-sm font-black text-slate-950">장치 진단</p>
          {hasDiagnostic ? (
            <span
              class={`rounded-full px-2.5 py-1 text-[11px] font-extrabold ${tone.badge}`}
            >
              {tone.label}
            </span>
          ) : null}
        </div>
        <a
          class="text-xs font-extrabold text-teal-700 no-underline hover:text-teal-900"
          href="#settings"
        >
          상세 보기 →
        </a>
      </div>

      {error && !hasDiagnostic ? (
        <div class="mt-3 rounded-xl border border-amber-200 bg-amber-50/70 px-4 py-3">
          <div class="flex items-start gap-2">
            <AlertIcon class="mt-0.5 size-4 shrink-0 text-amber-700" />
            <div class="min-w-0">
              <p class="m-0 text-sm font-extrabold text-slate-900">
                진단 상태를 확인하지 못했습니다.
              </p>
              <p class="mt-1 mb-0 text-xs leading-5 text-slate-500">
                설정에서 장치 진단 상태를 다시 확인해 주세요.
              </p>
            </div>
          </div>
        </div>
      ) : hasDiagnostic && data ? (
        <div class={`mt-3 rounded-xl border px-4 py-3 ${tone.panel}`}>
          <div class="flex min-w-0 items-start gap-3">
            {data.overall === 'ok' ? (
              <CheckCircleIcon class={`mt-0.5 size-5 shrink-0 ${tone.icon}`} />
            ) : data.overall === 'initializing' ? (
              <ClockIcon class={`mt-0.5 size-5 shrink-0 ${tone.icon}`} />
            ) : (
              <AlertIcon class={`mt-0.5 size-5 shrink-0 ${tone.icon}`} />
            )}
            <div class="min-w-0 flex-1">
              <p class="m-0 text-sm font-black text-slate-950">
                {data.summary.message}
              </p>
              <p class="mt-1 mb-0 text-xs font-semibold leading-5 text-slate-500">
                마지막 진단: {formatRelativeTime(data.generatedAt, nowTimestamp)} · 검사 항목:{' '}
                {data.summary.total}개
              </p>
            </div>
          </div>

          {visibleIssues.length > 0 ? (
            <div class="mt-3 grid gap-2 sm:grid-cols-2">
              {visibleIssues.map((check) => (
                <div
                  class="min-w-0 rounded-lg border border-white/80 bg-white/70 px-3 py-2"
                  key={check.id}
                >
                  <p class="m-0 text-xs font-extrabold text-slate-900">
                    {check.label}
                  </p>
                  <p class="mt-1 mb-0 line-clamp-2 text-xs leading-5 text-slate-500">
                    {check.message}
                  </p>
                </div>
              ))}
            </div>
          ) : null}
          {hiddenIssueCount > 0 ? (
            <p class="mt-2 mb-0 text-xs font-extrabold text-slate-600">
              외 {hiddenIssueCount}건의 확인 항목이 있습니다.
            </p>
          ) : null}
        </div>
      ) : (
        <div class="mt-3 rounded-xl border border-slate-200 bg-slate-50 px-4 py-3">
          <p class="m-0 text-sm font-extrabold text-slate-900">
            {loading
              ? '진단 상태를 확인하고 있습니다.'
              : '아직 생성된 진단 결과가 없습니다.'}
          </p>
          <p class="mt-1 mb-0 text-xs leading-5 text-slate-500">
            진단 결과가 생성되면 현재 장치 상태를 이곳에 요약해서 표시합니다.
          </p>
        </div>
      )}
    </div>
  );
}

function safeShieldOverview(
  data: SafeShieldStatus | null,
  loading: boolean,
  error: string | null,
): { detail: string; state: OverviewState; value: string } {
  if (loading && !data) {
    return { detail: '보호 상태를 확인하고 있습니다.', state: 'neutral', value: '확인 중' };
  }

  if (error && !data) {
    return { detail: 'SafeShield 상태를 불러오지 못했습니다.', state: 'warning', value: '확인 필요' };
  }

  if (!data || !data.available) {
    return { detail: 'SafeShield 서비스를 사용할 수 없습니다.', state: 'warning', value: '사용 불가' };
  }

  if (!data.enabled || data.status === 'disabled') {
    return { detail: 'DNS 보호가 비활성화되어 있습니다.', state: 'neutral', value: '꺼짐' };
  }

  if (data.status === 'running') {
    return { detail: '차단 목록을 갱신하고 있습니다.', state: 'neutral', value: '갱신 중' };
  }

  const healthy =
    data.active &&
    data.runtime.dnsmasqRunning &&
    data.runtime.dnsRuntimeOk &&
    data.health.overall !== 'error' &&
    data.issueCounts.errors === 0;

  if (!healthy) {
    return {
      detail: data.runtime.lastErrorCode
        ? `최근 오류: ${data.runtime.lastErrorCode}`
        : 'DNS 보호 상태를 확인해 주세요.',
      state: 'warning',
      value: '확인 필요',
    };
  }

  const plan = data.license.plan?.trim();
  const ruleDetail =
    data.blocklist.validLineCount > 0
      ? `${formatNumber(data.blocklist.validLineCount)}개 차단 규칙`
      : '차단 목록 적용됨';

  return {
    detail: plan ? `${ruleDetail} · ${plan.toUpperCase()}` : ruleDetail,
    state: 'healthy',
    value: '보호 중',
  };
}

export function HomePage({
  activity,
  activityError,
  activityLoading,
  data,
  devices,
  devicesError,
  devicesLoading,
  error,
  firmware,
  firmwareError,
  firmwareLoading,
  health,
  healthError,
  healthLoading,
  lan,
  lanError,
  lanLoading,
  loading,
  onRetry,
  safeshield,
  safeshieldError,
  safeshieldLoading,
  statistics,
  statisticsError,
  statisticsLoading,
  statisticsRefreshing,
  updates,
  updatesError,
  updatesLoading,
}: HomePageProps) {
  const memory = useMemo(() => (data ? getMemoryUsage(data.runtime.memory) : null), [data]);
  const [relativeNow, setRelativeNow] = useState(() => Math.floor(Date.now() / 1000));

  useEffect(() => {
    const timer = window.setInterval(() => {
      setRelativeNow(Math.floor(Date.now() / 1000));
    }, RELATIVE_TIME_TICK_MS);

    return () => window.clearInterval(timer);
  }, []);

  if (loading) {
    return <LoadingPanel />;
  }

  if (error) {
    return <ErrorPanel message={error} onRetry={onRetry} />;
  }

  if (!data) {
    return null;
  }

  const memoryPercent = memory ? Math.round(memory.percent) : 0;
  const safeShieldSummary = safeShieldOverview(
    safeshield,
    safeshieldLoading,
    safeshieldError,
  );
  const updatePackage =
    updates?.packages.find((item) => item.name === 'luci-app-smartsafehub') ??
    updates?.packages[0] ??
    null;
  const updateAvailable = Boolean(updates && updates.updateCount > 0);
  const updateValue = updates
    ? updateAvailable
      ? `${updates.updateCount}개 업데이트`
      : updates.lastCheckAt
        ? '최신 상태'
        : '확인 전'
    : updatesError
      ? '확인 필요'
      : '확인 중';
  const updateDetail = updatePackage
    ? updateAvailable && updatePackage.availableVersion
      ? `${updatePackage.installedVersion} → ${updatePackage.availableVersion}`
      : `설치 버전 ${updatePackage.installedVersion}`
    : updatesError
      ? '업데이트 상태를 불러오지 못했습니다.'
      : updatesLoading
        ? '업데이트 상태를 확인하고 있습니다.'
        : '업데이트 상태를 확인할 수 없습니다.';
  const devicesValue = devices
    ? `${formatNumber(devices.totals.online)}대`
    : devicesLoading
      ? '확인 중'
      : '확인 필요';
  const devicesDetail = devices
    ? `Wi-Fi ${formatNumber(devices.totals.wireless)}대 · 유선/기타 ${formatNumber(devices.totals.ethernet)}대`
    : devicesError || '연결 기기 요약을 불러오고 있습니다.';
  const wanProtocol = networkProtocolLabel(data.network.protocol);
  const wanDetail = data.network.available
    ? data.network.ipv4Address
      ? `WAN ${data.network.ipv4Address}${wanProtocol ? ` · ${wanProtocol}` : ''}`
      : wanProtocol
        ? `${wanProtocol} · WAN 주소를 받지 못했습니다.`
        : 'WAN 주소를 받지 못했습니다.'
    : 'WAN 인터페이스를 찾을 수 없습니다.';
  const networkConflict = Boolean(lan?.conflict.detected);
  const internetState: OverviewState =
    !data.network.up || networkConflict || (lanError !== null && !lan)
      ? 'warning'
      : lan
        ? 'healthy'
        : 'neutral';
  const internetValue = networkConflict
    ? '네트워크 충돌'
    : data.network.up
      ? '정상 연결'
      : '연결 확인';
  const internetMeta = !data.network.up
    ? 'WAN 연결 상태를 확인해 주세요.'
    : networkConflict
      ? '⚠ LAN 대역과 충돌합니다'
      : lanLoading && !lan
        ? '네트워크 대역 확인 중'
        : lanError && !lan
          ? '네트워크 대역을 확인하지 못했습니다.'
          : lan
            ? '✓ 네트워크 충돌 없음'
            : '네트워크 대역 확인 필요';
  const internetMetaState: OverviewState =
    !data.network.up || networkConflict || (lanError !== null && !lan)
      ? 'warning'
      : lan
        ? 'healthy'
        : 'neutral';
  const wanAddressDetail = data.network.ipv4Address
    ? isPrivateIpv4(data.network.ipv4Address)
      ? `${data.network.ipv4Address} · 사설 네트워크`
      : data.network.ipv4Address
    : '할당되지 않음';
  const safeShieldRefreshAge = elapsedSeconds(
    safeshield?.timestamps.lastSuccess,
    relativeNow,
  );
  const safeShieldStaleThreshold = safeshield
    ? Math.max(safeshield.timestamps.refreshIntervalS * 2, 86_400)
    : null;
  const safeShieldStale = Boolean(
    safeshield?.enabled &&
      safeshield.status !== 'running' &&
      safeShieldRefreshAge !== null &&
      safeShieldStaleThreshold !== null &&
      safeShieldRefreshAge > safeShieldStaleThreshold,
  );
  const updatesStale = isSoftwareUpdateCheckStale(updates, relativeNow);
  const customFirmwareAvailable = Boolean(firmware?.current.metadataAvailable);
  const deviceFirmware =
    firmwareLoading && !firmware
      ? '확인 중'
      : firmwareError && !firmware
        ? '확인 필요'
        : customFirmwareAvailable
          ? firmware?.current.releaseVersion
            ? `SmartSafeHub ${firmware.current.releaseVersion}`
            : 'SmartSafeHub 펌웨어'
          : `${data.software.distribution} ${data.software.version}`;
  const deviceRevision =
    firmwareLoading && !firmware
      ? '확인 중'
      : firmwareError && !firmware
        ? '확인 필요'
        : customFirmwareAvailable
          ? firmware?.current.buildId || data.software.revision
          : data.software.revision;
  const deviceRevisionLabel = customFirmwareAvailable ? '빌드 ID' : '리비전';

  return (
    <div class="min-w-0 space-y-6">
      <section aria-labelledby="dashboard-overview-title">
        <SectionHeading
          description="인터넷, SafeShield, 연결 기기와 소프트웨어 상태를 한눈에 확인합니다."
          eyebrow="Overview"
          id="dashboard-overview-title"
          title="시스템 개요"
        />
        <div class="grid min-w-0 gap-4 sm:grid-cols-2 xl:grid-cols-4">
          <OverviewCard
            detail={wanDetail}
            eyebrow="Internet"
            href="#lan"
            icon={<GlobeIcon class="size-5" />}
            linkLabel={networkConflict ? '해결하기 →' : '자세히 보기 →'}
            meta={internetMeta}
            metaState={internetMetaState}
            state={internetState}
            value={internetValue}
          />
          <OverviewCard
            detail={safeShieldSummary.detail}
            eyebrow="SafeShield"
            href="#safeshield"
            icon={<ShieldIcon class="size-5" />}
            meta={freshnessMeta(
              safeShieldStale ? '차단 목록 갱신 지연' : '차단 목록 갱신',
              safeshield?.timestamps.lastSuccess,
              relativeNow,
              safeshieldLoading ? '확인 중' : '기록 없음',
            )}
            metaWarning={safeShieldStale}
            state={
              safeShieldSummary.state === 'healthy' && safeShieldStale
                ? 'warning'
                : safeShieldSummary.state
            }
            value={safeShieldSummary.value}
          />
          <OverviewCard
            detail={devicesDetail}
            eyebrow="Connected devices"
            href="#devices"
            icon={<DevicesIcon class="size-5" />}
            meta={freshnessMeta(
              '목록 확인',
              devices?.generatedAt,
              relativeNow,
              devicesLoading ? '확인 중' : '기록 없음',
            )}
            state={devices ? 'healthy' : devicesError ? 'warning' : 'neutral'}
            value={devicesValue}
          />
          <OverviewCard
            detail={updateDetail}
            eyebrow="Software update"
            href="#system"
            icon={<UpdateIcon class="size-5" />}
            meta={
              updates && !updates.settings.checkEnabled
                ? freshnessMeta(
                    '자동 확인 꺼짐 · 마지막 확인',
                    updates.lastCheckAt,
                    relativeNow,
                    '확인 기록 없음',
                  )
                : freshnessMeta(
                    updatesStale ? '업데이트 확인 지연' : '마지막 확인',
                    updates?.lastCheckAt,
                    relativeNow,
                    updatesLoading ? '확인 중' : '아직 없음',
                  )
            }
            metaWarning={updatesStale}
            state={
              updatesError || updatesStale
                ? 'warning'
                : updateAvailable
                  ? 'warning'
                  : updates?.lastCheckAt
                    ? 'healthy'
                    : 'neutral'
            }
            value={updateValue}
          />
        </div>
      </section>

      <section aria-labelledby="dashboard-activity-title">
        <SectionHeading
          description="최근 SafeShield 차단 활동과 현재 네트워크 연결 구성을 함께 확인합니다."
          eyebrow="Activity"
          id="dashboard-activity-title"
          title="네트워크 보호 활동"
        />
        <div class="grid min-w-0 gap-4 xl:grid-cols-[minmax(0,1.55fr)_minmax(18rem,0.65fr)]">
          <DashboardSafeShieldActivity
            data={statistics}
            error={statisticsError}
            loading={statisticsLoading}
            refreshing={statisticsRefreshing}
          />

          <article class="min-w-0 rounded-2xl border border-slate-200 bg-white p-5 shadow-sm shadow-slate-900/5 sm:p-6">
            <div class="flex items-start justify-between gap-4">
              <div>
                <p class="m-0 text-xs font-extrabold uppercase tracking-[0.16em] text-slate-500">
                  Network
                </p>
                <h3 class="mt-2 mb-0 text-xl font-black text-slate-950">연결 상태</h3>
              </div>
              <span
                class={`grid size-10 shrink-0 place-items-center rounded-xl ${
                  data.network.up && !networkConflict
                    ? 'bg-emerald-50 text-emerald-700'
                    : 'bg-amber-50 text-amber-800'
                }`}
              >
                <GlobeIcon class="size-5" />
              </span>
            </div>

            <dl class="mt-4 mb-0">
              <DetailRow
                label="인터넷"
                value={
                  networkConflict
                    ? '네트워크 충돌'
                    : data.network.up
                      ? '정상 연결'
                      : '연결 확인'
                }
              />
              <DetailRow label="WAN IP" value={wanAddressDetail} />
              <DetailRow
                label="프로토콜"
                value={wanProtocol || '확인되지 않음'}
              />
              <DetailRow
                label="상위 네트워크"
                value={
                  lan?.wan.subnet ||
                  (lanLoading ? '확인 중' : lanError ? '확인 필요' : '확인되지 않음')
                }
              />
              <DetailRow
                label="LAN 네트워크"
                value={
                  lan?.lan.subnet ||
                  (lanLoading ? '확인 중' : lanError ? '확인 필요' : '확인되지 않음')
                }
              />
              <DetailRow
                label="대역 충돌"
                value={
                  lan ? (
                    <span
                      class={lan.conflict.detected ? 'text-amber-700' : 'text-emerald-700'}
                    >
                      {lan.conflict.detected ? '충돌 감지' : '없음'}
                    </span>
                  ) : lanLoading ? (
                    '확인 중'
                  ) : (
                    '확인 필요'
                  )
                }
              />
            </dl>

            <a
              class="mt-5 inline-flex min-h-10 w-full items-center justify-center rounded-xl border border-slate-200 bg-slate-50 px-4 py-2 text-sm font-extrabold text-slate-700 no-underline transition hover:border-teal-200 hover:bg-teal-50 hover:text-teal-800"
              href="#lan"
            >
              LAN 설정 보기
            </a>
          </article>
        </div>
      </section>

      <section aria-labelledby="dashboard-recent-activity-title">
        <div class="mb-4 flex flex-wrap items-end justify-between gap-3">
          <SectionHeading
            description="인터넷, 보호, 업데이트와 진단에서 실제 상태가 바뀐 시점을 확인합니다."
            eyebrow="History"
            id="dashboard-recent-activity-title"
            title="최근 활동"
          />
          <a
            class="mb-4 inline-flex text-xs font-extrabold text-teal-700 no-underline hover:text-teal-900"
            href="#activity"
          >
            전체 보기 →
          </a>
        </div>
        <article class="min-w-0 rounded-2xl border border-slate-200 bg-white p-5 shadow-sm shadow-slate-900/5 sm:p-6">
          {activityLoading || (activityError && !activity) ? (
            <ActivityLoadState error={activityError} loading={activityLoading} />
          ) : (
            <ActivityTimeline compact events={(activity?.events ?? []).slice(0, 3)} />
          )}
        </article>
      </section>

      <section aria-labelledby="dashboard-system-title">
        <SectionHeading
          description="메모리, 시스템 부하와 장치 정보를 빠르게 점검합니다."
          eyebrow="System"
          id="dashboard-system-title"
          title="시스템 상태"
        />
        <div class="grid min-w-0 gap-4 xl:grid-cols-[minmax(0,1.45fr)_minmax(20rem,0.75fr)]">
          <article class="min-w-0 rounded-2xl border border-slate-200 bg-white p-5 shadow-sm shadow-slate-900/5 sm:p-6">
            <div class="flex flex-wrap items-start justify-between gap-4">
              <div>
                <p class="m-0 text-xs font-extrabold uppercase tracking-[0.16em] text-slate-500">
                  Runtime
                </p>
                <h3 class="mt-2 mb-0 text-xl font-black text-slate-950">리소스 사용량</h3>
              </div>
              <span
                class={`inline-flex items-center gap-2 rounded-full px-3 py-1.5 text-xs font-black ring-1 ring-inset ${
                  memoryPercent >= 90
                    ? 'bg-amber-50 text-amber-800 ring-amber-200'
                    : 'bg-emerald-50 text-emerald-700 ring-emerald-200'
                }`}
              >
                <span
                  class={`size-2 rounded-full ${memoryPercent >= 90 ? 'bg-amber-500' : 'bg-emerald-500'}`}
                />
                {memoryPercent >= 90 ? '메모리 확인' : '정상 실행'}
              </span>
            </div>

            <div class="mt-5 grid gap-3 sm:grid-cols-3">
              <div class="rounded-xl border border-slate-200 bg-slate-50 p-4">
                <div class="flex items-center gap-2 text-slate-500">
                  <MemoryIcon class="size-4" />
                  <span class="text-xs font-extrabold">메모리</span>
                </div>
                <p class="mt-2 mb-0 text-xl font-black text-slate-950">{memoryPercent}%</p>
                <p class="mt-1 mb-0 text-xs font-semibold text-slate-500">
                  {memory ? formatBytes(memory.used) : '-'} /{' '}
                  {formatBytes(data.runtime.memory.total)}
                </p>
                <div
                  aria-label={`메모리 사용률 ${memoryPercent}%`}
                  class="mt-3 h-1.5 overflow-hidden rounded-full bg-slate-200"
                  role="progressbar"
                  aria-valuemin={0}
                  aria-valuemax={100}
                  aria-valuenow={memoryPercent}
                >
                  <div
                    class={`h-full rounded-full transition-[width] duration-300 ${
                      memoryPercent >= 90 ? 'bg-amber-500' : 'bg-teal-600'
                    }`}
                    style={{ width: `${Math.min(100, memoryPercent)}%` }}
                  />
                </div>
              </div>
              <div class="rounded-xl border border-slate-200 bg-slate-50 p-4">
                <div class="flex items-center gap-2 text-slate-500">
                  <RouterIcon class="size-4" />
                  <span class="text-xs font-extrabold">시스템 부하</span>
                </div>
                <p class="mt-2 mb-0 text-xl font-black text-slate-950">
                  {formatLoadAverage(data.runtime.load[0])}
                </p>
                <p class="mt-1 mb-0 text-xs font-semibold text-slate-500">
                  5분 {formatLoadAverage(data.runtime.load[1])} · 15분{' '}
                  {formatLoadAverage(data.runtime.load[2])}
                </p>
              </div>
              <div class="rounded-xl border border-slate-200 bg-slate-50 p-4">
                <div class="flex items-center gap-2 text-slate-500">
                  <ClockIcon class="size-4" />
                  <span class="text-xs font-extrabold">실행 시간</span>
                </div>
                <p class="mt-2 mb-0 text-xl font-black text-slate-950">
                  {formatUptime(data.runtime.uptime)}
                </p>
                <p class="mt-1 mb-0 text-xs font-semibold text-slate-500">
                  부팅 {formatBootTime(data.runtime.localtime, data.runtime.uptime)}
                </p>
              </div>
            </div>

            <DashboardHealthSummary
              data={health}
              error={healthError}
              loading={healthLoading}
              nowTimestamp={relativeNow}
            />
          </article>

          <article class="min-w-0 rounded-2xl border border-slate-200 bg-white p-5 shadow-sm shadow-slate-900/5 sm:p-6">
            <div class="flex items-start justify-between gap-4">
              <div>
                <p class="m-0 text-xs font-extrabold uppercase tracking-[0.16em] text-slate-500">
                  Device
                </p>
                <h3 class="mt-2 mb-0 text-xl font-black text-slate-950">장치 정보</h3>
              </div>
              <span class="grid size-10 shrink-0 place-items-center rounded-xl bg-teal-50 text-teal-700">
                <RouterIcon class="size-5" />
              </span>
            </div>
            <dl class="mt-4 mb-0">
              <DetailRow label="모델" value={data.device.model} />
              <DetailRow label="호스트 이름" value={data.device.hostname} />
              <DetailRow
                label="펌웨어"
                value={
                  <span
                    title={
                      customFirmwareAvailable
                        ? firmware?.current.releaseVersion
                          ? `SmartSafeHub 펌웨어 ${firmware.current.releaseVersion}`
                          : 'SmartSafeHub 커스텀 펌웨어'
                        : firmwareError || undefined
                    }
                  >
                    {deviceFirmware}
                  </span>
                }
              />
              <DetailRow label={deviceRevisionLabel} value={deviceRevision} />
              <DetailRow label="커널" value={data.software.kernel} />
              <DetailRow
                label="WAN IP"
                value={data.network.ipv4Address || '할당되지 않음'}
              />
            </dl>
          </article>
        </div>
      </section>

    </div>
  );
}
