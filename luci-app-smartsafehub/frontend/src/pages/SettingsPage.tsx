import type { ComponentChildren } from 'preact';
import { useEffect, useRef, useState } from 'preact/hooks';

import {
  formatBytes,
  formatLoadAverage,
  formatRelativeTime,
  formatTimestampInTimezone,
  formatUptime,
  getMemoryUsage,
} from '../app/format';
import { CustomSelect } from '../components/CustomSelect';
import { TimeSelect } from '../components/TimeSelect';
import {
  AlertIcon,
  CalendarIcon,
  CheckCircleIcon,
  ClockIcon,
  DatabaseIcon,
  DownloadIcon,
  PowerIcon,
  SettingsIcon,
} from '../components/Icons';
import type { ConfigurationBackupAction } from '../hooks/useConfigurationBackup';
import type { SystemAction } from '../hooks/useSystemActions';
import type { ConfigurationBackupValidation } from '../types/backup';
import type { FirmwareStatus } from '../types/firmware';
import type { HealthReporterStatus, HealthSeverity, HealthStatus } from '../types/health';
import type { SmartSafeHubStatus } from '../types/status';
import type {
  ScheduledRebootDayOfWeek,
  ScheduledRebootFrequency,
  ScheduledRebootSettings,
  ScheduledRebootSettingsInput,
  SystemTimeSettings,
} from '../types/system';
import { luciAdminUrl } from '../utils/luci';

interface SettingsPageProps {
  action: SystemAction;
  backupAction: ConfigurationBackupAction;
  backupError: string | null;
  backupMessage: string | null;
  backupRestoreAccepted: boolean;
  backupUploadProgress: number | null;
  backupValidated: ConfigurationBackupValidation | null;
  data: SmartSafeHubStatus | null;
  error: string | null;
  feedbackError: string | null;
  feedbackMessage: string | null;
  firmware: FirmwareStatus | null;
  firmwareError: string | null;
  firmwareLoading: boolean;
  health: HealthStatus | null;
  healthActionError: string | null;
  healthActionMessage: string | null;
  healthError: string | null;
  healthLoading: boolean;
  healthRunning: boolean;
  healthSavingReporter: boolean;
  loading: boolean;
  rebootAccepted: boolean;
  scheduledRebootData: ScheduledRebootSettings | null;
  scheduledRebootError: string | null;
  scheduledRebootLoading: boolean;
  scheduledRebootSaveError: string | null;
  scheduledRebootSaveMessage: string | null;
  scheduledRebootSaving: boolean;
  timeData: SystemTimeSettings | null;
  timeError: string | null;
  timeLoading: boolean;
  timeSaveError: string | null;
  timeSaveMessage: string | null;
  timeSaving: boolean;
  timeSyncing: boolean;
  onBackupDiscard: () => Promise<boolean>;
  onBackupDownload: () => void;
  onBackupRestore: () => Promise<boolean>;
  onBackupUpload: (file: File) => Promise<boolean>;
  onDismissBackupFeedback: () => void;
  onDismissFeedback: () => void;
  onDismissHealthFeedback: () => void;
  onDismissTimeFeedback: () => void;
  onDownloadDiagnostics: () => void;
  onRunHealth: () => void;
  onSetHealthReporter: (enabled: boolean) => void;
  onReboot: () => void;
  onRetry: () => void;
  onDismissScheduledRebootFeedback: () => void;
  onSaveScheduledReboot: (input: ScheduledRebootSettingsInput) => Promise<boolean>;
  onSaveTimezone: (zonename: string) => Promise<boolean>;
  onSyncTime: () => Promise<boolean>;
}

function InfoCard(props: { label: string; value: string; description: string }) {
  return (
    <article class="min-w-0 rounded-2xl border border-slate-200 bg-white p-4 shadow-sm shadow-slate-900/5 sm:p-5">
      <p class="m-0 text-xs font-extrabold uppercase tracking-[0.16em] text-slate-500">
        {props.label}
      </p>
      <p class="mt-3 mb-0 break-words text-2xl font-black tracking-tight text-slate-950">
        {props.value}
      </p>
      <p class="mt-2 mb-0 text-sm leading-6 text-slate-500">{props.description}</p>
    </article>
  );
}

function ActionCard(props: {
  title: string;
  description: string;
  icon: ComponentChildren;
  children?: ComponentChildren;
  className?: string;
}) {
  return (
    <article
      class={`min-w-0 rounded-2xl border border-slate-200 bg-white p-5 shadow-sm shadow-slate-900/5 sm:p-6 ${props.className ?? ''}`}
    >
      <div class="flex min-w-0 items-start gap-4">
        <div
          class="flex size-11 shrink-0 items-center justify-center rounded-xl bg-slate-100 text-slate-600"
        >
          {props.icon}
        </div>
        <div class="min-w-0">
          <h2 class="m-0 text-lg font-black text-slate-950">
            {props.title}
          </h2>
          <p class="mt-1.5 mb-0 text-sm leading-6 text-slate-500">
            {props.description}
          </p>
        </div>
      </div>
      <div class="mt-5">{props.children}</div>
    </article>
  );
}

function browserTimezone(): string | null {
  try {
    return Intl.DateTimeFormat().resolvedOptions().timeZone || null;
  } catch {
    return null;
  }
}

function TimeSettingsCard(props: {
  data: SystemTimeSettings | null;
  error: string | null;
  loading: boolean;
  saveError: string | null;
  saveMessage: string | null;
  saving: boolean;
  syncing: boolean;
  scheduledRebootData: ScheduledRebootSettings | null;
  scheduledRebootError: string | null;
  scheduledRebootLoading: boolean;
  scheduledRebootSaveError: string | null;
  scheduledRebootSaveMessage: string | null;
  scheduledRebootSaving: boolean;
  onDismissFeedback: () => void;
  onDismissScheduledRebootFeedback: () => void;
  onRetry: () => void;
  onSave: (zonename: string) => Promise<boolean>;
  onSaveScheduledReboot: (input: ScheduledRebootSettingsInput) => Promise<boolean>;
  onSync: () => Promise<boolean>;
}) {
  const [selectedTimezone, setSelectedTimezone] = useState('');
  const [displayedLocaltime, setDisplayedLocaltime] = useState(
    props.data?.localtime ?? 0,
  );
  const detectedBrowserTimezone = browserTimezone();

  useEffect(() => {
    if (props.data?.zonename) {
      setSelectedTimezone(props.data.zonename);
    }
  }, [props.data?.zonename]);

  useEffect(() => {
    const baseLocaltime = props.data?.localtime ?? 0;
    const startedAt = Date.now();
    setDisplayedLocaltime(baseLocaltime);

    if (!Number.isFinite(baseLocaltime) || baseLocaltime <= 0) {
      return;
    }

    const timer = window.setInterval(() => {
      setDisplayedLocaltime(
        baseLocaltime + Math.floor((Date.now() - startedAt) / 1000),
      );
    }, 1000);

    return () => window.clearInterval(timer);
  }, [props.data?.localtime]);

  const zones = props.data
    ? Object.keys(props.data.timezones).sort((left, right) =>
        left.localeCompare(right),
      )
    : [];
  const currentTimezone = props.data?.zonename ?? 'UTC';
  const currentTime = formatTimestampInTimezone(
    displayedLocaltime,
    currentTimezone,
  );
  const browserTimezoneAvailable =
    detectedBrowserTimezone !== null &&
    props.data?.timezones[detectedBrowserTimezone] !== undefined;
  const changed =
    props.data !== null &&
    selectedTimezone.length > 0 &&
    selectedTimezone !== props.data.zonename;

  return (
    <ActionCard
      description="공유기의 기준 시간대를 설정합니다. 로그, 통계, 자동 설치와 예약 재부팅 시각도 이 시간대를 기준으로 동작합니다."
      icon={<ClockIcon class="size-5" />}
      title="시간 및 시간대"
    >
      {(props.saveError || props.saveMessage) && (
        <div
          class={`mb-5 flex min-w-0 items-start justify-between gap-3 rounded-xl border px-4 py-3 text-sm font-bold ${
            props.saveError
              ? 'border-rose-200 bg-rose-50 text-rose-800'
              : 'border-emerald-200 bg-emerald-50 text-emerald-800'
          }`}
        >
          <span class="min-w-0">{props.saveError || props.saveMessage}</span>
          <button
            class="shrink-0 rounded-lg px-2 py-1 text-xs font-extrabold hover:bg-black/5"
            onClick={props.onDismissFeedback}
            type="button"
          >
            닫기
          </button>
        </div>
      )}

      {props.error && !props.data ? (
        <div class="rounded-xl border border-rose-200 bg-rose-50 p-4">
          <p class="m-0 text-sm font-bold text-rose-800">{props.error}</p>
          <button
            class="mt-3 inline-flex min-h-10 items-center rounded-xl border border-rose-300 bg-white px-3 py-2 text-xs font-extrabold text-rose-700 transition hover:bg-rose-100"
            onClick={props.onRetry}
            type="button"
          >
            다시 불러오기
          </button>
        </div>
      ) : (
        <>
          <div class="grid min-w-0 grid-cols-1 gap-3 sm:grid-cols-2">
            <div class="rounded-xl bg-slate-50 p-4">
              <p class="m-0 text-xs font-extrabold uppercase tracking-[0.12em] text-slate-500">
                현재 시간
              </p>
              <p class="mt-2 mb-0 text-sm font-extrabold leading-6 text-slate-900">
                {currentTime}
              </p>
              <p class="mt-1 mb-0 break-words text-xs leading-5 text-slate-500">
                {props.data?.zonename ?? '시간대 확인 중'}
              </p>
            </div>
            <div class="rounded-xl bg-slate-50 p-4">
              <p class="m-0 text-xs font-extrabold uppercase tracking-[0.12em] text-slate-500">
                시간 동기화
              </p>
              <p
                class={`mt-2 mb-0 text-sm font-extrabold ${
                  props.data?.ntpEnabled ? 'text-emerald-700' : 'text-amber-700'
                }`}
              >
                {props.data?.ntpEnabled ? '자동 동기화 설정됨' : '자동 동기화 꺼짐'}
              </p>
              <p class="mt-1 mb-0 text-xs leading-5 text-slate-500">
                장치의 기본 NTP 설정 상태입니다.
              </p>
              <button
                class="mt-3 inline-flex min-h-9 items-center justify-center gap-2 rounded-lg border border-slate-300 bg-white px-3 py-2 text-xs font-extrabold text-slate-700 transition hover:bg-slate-100 disabled:cursor-not-allowed disabled:opacity-50"
                disabled={!props.data?.ntpEnabled || props.saving || props.syncing}
                onClick={() => void props.onSync()}
                type="button"
              >
                {props.syncing ? '동기화 요청 중' : '지금 동기화'}
              </button>
            </div>
          </div>

          <div class="mt-5">
            <label
              class="mb-2 block text-sm font-extrabold text-slate-800"
              for="smartsafehub-timezone"
            >
              시간대
            </label>
            <CustomSelect
              ariaLabel="시간대"
              disabled={props.loading || props.saving || props.syncing || !props.data}
              id="smartsafehub-timezone"
              onChange={setSelectedTimezone}
              options={
                props.data
                  ? zones.map((zone) => ({ value: zone, label: zone }))
                  : [{ value: '', label: '시간대 불러오는 중' }]
              }
              value={selectedTimezone}
            />
            <p class="mt-2 mb-0 text-xs leading-5 text-slate-500">
              시간대를 변경하면 시스템에 즉시 적용되며 자동 설치와 예약 재부팅 일정도 새 기준 시간으로 다시 계산합니다.
            </p>
          </div>

          <div class="mt-4 flex flex-col gap-3 sm:flex-row sm:flex-wrap sm:justify-end">
            {browserTimezoneAvailable &&
              detectedBrowserTimezone !== selectedTimezone && (
                <button
                  class="inline-flex min-h-11 w-full items-center justify-center rounded-xl border border-slate-300 bg-white px-4 py-2.5 text-sm font-extrabold text-slate-700 transition hover:bg-slate-50 disabled:opacity-60 sm:w-auto"
                  disabled={props.saving || props.syncing}
                  onClick={() => setSelectedTimezone(detectedBrowserTimezone)}
                  type="button"
                >
                  브라우저 시간대 사용
                </button>
              )}
            <button
              class="inline-flex min-h-11 w-full items-center justify-center rounded-xl bg-teal-700 px-4 py-2.5 text-sm font-extrabold text-white transition hover:bg-teal-800 disabled:cursor-not-allowed disabled:opacity-50 sm:w-auto"
              disabled={!changed || props.saving || props.syncing}
              onClick={() => void props.onSave(selectedTimezone)}
              type="button"
            >
              {props.saving ? '시간대 저장 중' : '시간대 저장'}
            </button>
          </div>
        </>
      )}

      <ScheduledRebootSection
        data={props.scheduledRebootData}
        error={props.scheduledRebootError}
        loading={props.scheduledRebootLoading}
        onDismissFeedback={props.onDismissScheduledRebootFeedback}
        onRetry={props.onRetry}
        onSave={props.onSaveScheduledReboot}
        saveError={props.scheduledRebootSaveError}
        saveMessage={props.scheduledRebootSaveMessage}
        saving={props.scheduledRebootSaving}
      />
    </ActionCard>
  );
}


function healthTone(status: HealthSeverity): {
  badge: string;
  panel: string;
  label: string;
} {
  if (status === 'initializing') {
    return {
      badge: 'bg-teal-100 text-teal-800',
      panel: 'border-teal-200 bg-teal-50',
      label: '준비 중',
    };
  }
  if (status === 'critical') {
    return {
      badge: 'bg-rose-100 text-rose-800',
      panel: 'border-rose-200 bg-rose-50',
      label: '이상',
    };
  }
  if (status === 'warning') {
    return {
      badge: 'bg-amber-100 text-amber-800',
      panel: 'border-amber-200 bg-amber-50',
      label: '주의',
    };
  }
  if (status === 'unknown') {
    return {
      badge: 'bg-slate-200 text-slate-700',
      panel: 'border-slate-200 bg-slate-50',
      label: '확인 불가',
    };
  }
  return {
    badge: 'bg-emerald-100 text-emerald-800',
    panel: 'border-emerald-200 bg-emerald-50',
    label: '정상',
  };
}

function reporterResultLabel(reporter: HealthReporterStatus): string {
  if (!reporter.enabled) {
    return '보고 중지됨';
  }

  switch (reporter.lastResult) {
    case 'reported':
      return '정상 보고';
    case 'initializing':
      return reporter.lastReportAt > 0 ? '상태 갱신 중' : '첫 보고 진행 중';
    case 'failed':
      return '최근 보고 실패';
    case 'idle':
      return '다음 보고 대기';
    case 'ineligible':
      return '멤버십 확인 필요';
    case 'disabled':
    case 'never':
      return '첫 보고 준비 중';
    default:
      return '보고 준비 중';
  }
}

function reporterLastReportLabel(reporter: HealthReporterStatus): string {
  if (reporter.lastReportAt > 0) {
    return formatRelativeTime(reporter.lastReportAt);
  }
  return reporter.enabled ? '첫 보고 대기 중' : '보고 기록 없음';
}

function reporterMembershipLabel(reporter: HealthReporterStatus | undefined): string {
  const plan = reporter?.plan?.trim().toUpperCase();
  const licenseStatus = reporter?.licenseStatus?.trim().toLowerCase();

  if (plan && (licenseStatus === 'trial' || licenseStatus === 'trialing')) {
    return `${plan} · 체험`;
  }
  return plan || '유료 · Trial';
}

function HealthDiagnosticCard(props: {
  actionError: string | null;
  actionMessage: string | null;
  data: HealthStatus | null;
  error: string | null;
  loading: boolean;
  running: boolean;
  savingReporter: boolean;
  downloadBusy: boolean;
  onDismissFeedback: () => void;
  onDownload: () => void;
  onRetry: () => void;
  onRun: () => void;
  onSetReporter: (enabled: boolean) => void;
}) {
  const data = props.data;
  const tone = healthTone(data?.overall ?? 'unknown');
  const noteworthy = data?.checks.filter((check) => check.status !== 'ok') ?? [];
  const visibleChecks = noteworthy.length > 0
    ? noteworthy.slice(0, 4)
    : data?.checks.filter((check) =>
        ['system.memory', 'network.wan', 'service.dnsmasq', 'safeshield.runtime'].includes(check.id),
      ) ?? [];
  const reporter = data?.reporter;
  const reporterEnabled = reporter?.enabled === true;
  const canToggleReporter = reporter?.eligible === true || reporterEnabled;
  const reporterStateTitle = props.savingReporter
    ? reporterEnabled
      ? '원격 상태 보고를 켜고 있습니다.'
      : '원격 상태 보고를 끄고 있습니다.'
    : reporterEnabled
      ? '원격 상태 보고가 켜져 있습니다.'
      : '원격 상태 보고가 꺼져 있습니다.';
  const reporterStateDescription = reporterEnabled
    ? '장치 상태가 바뀌면 즉시 보고하고, 정상 상태에서도 주기적으로 SmartSafeHub 서버에 보고합니다.'
    : '로컬 진단은 계속 동작하지만 장치 상태는 SmartSafeHub 서버에 자동으로 전송되지 않습니다.';

  return (
    <ActionCard
      description="SmartSafeHub가 장치 상태를 직접 점검하고 이상 항목을 알려줍니다. 로컬 진단은 멤버십과 관계없이 사용할 수 있습니다."
      icon={<DownloadIcon class="size-5" />}
      title="진단 및 지원"
    >
      {(props.actionError || props.actionMessage) && (
        <div
          class={`mb-4 flex items-start justify-between gap-3 rounded-xl border px-4 py-3 text-sm font-bold ${
            props.actionError
              ? 'border-rose-200 bg-rose-50 text-rose-800'
              : 'border-emerald-200 bg-emerald-50 text-emerald-800'
          }`}
        >
          <span>{props.actionError || props.actionMessage}</span>
          <button
            class="shrink-0 rounded-lg px-2 py-1 text-xs font-extrabold hover:bg-black/5"
            onClick={props.onDismissFeedback}
            type="button"
          >
            닫기
          </button>
        </div>
      )}

      {props.error && !data ? (
        <div class="rounded-xl border border-rose-200 bg-rose-50 p-4">
          <p class="m-0 text-sm font-bold text-rose-800">{props.error}</p>
          <button
            class="mt-3 inline-flex min-h-10 items-center rounded-xl border border-rose-300 bg-white px-3 py-2 text-xs font-extrabold text-rose-700 transition hover:bg-rose-100"
            onClick={props.onRetry}
            type="button"
          >
            다시 불러오기
          </button>
        </div>
      ) : (
        <>
          <div class={`rounded-xl border p-4 ${tone.panel}`}>
            <div class="flex flex-wrap items-start justify-between gap-3">
              <div class="flex min-w-0 items-start gap-3">
                <span class="mt-0.5 shrink-0">
                  {data?.overall === 'ok' ? (
                    <CheckCircleIcon class="size-5 text-emerald-700" />
                  ) : data?.overall === 'initializing' ? (
                    <ClockIcon class="size-5 text-teal-700" />
                  ) : (
                    <AlertIcon class="size-5 text-amber-700" />
                  )}
                </span>
                <div class="min-w-0">
                  <p class="m-0 text-sm font-black text-slate-950">
                    {data?.summary.message ?? '장치 상태를 확인하고 있습니다.'}
                  </p>
                  <p class="mt-1 mb-0 text-xs leading-5 text-slate-600">
                    마지막 진단 : {data ? formatRelativeTime(data.generatedAt) : '확인 중'}
                  </p>
                </div>
              </div>
              <span class={`rounded-full px-2.5 py-1 text-xs font-extrabold ${tone.badge}`}>
                {tone.label}
              </span>
            </div>
          </div>

          {data && (
            <div class="mt-4 grid grid-cols-3 gap-2">
              <div class="rounded-xl bg-slate-50 p-3">
                <p class="m-0 text-[11px] font-extrabold text-slate-500">진단 항목</p>
                <p class="mt-1 mb-0 text-lg font-black text-slate-950">{data.summary.total}</p>
              </div>
              <div class="rounded-xl bg-slate-50 p-3">
                <p class="m-0 text-[11px] font-extrabold text-slate-500">주의</p>
                <p class="mt-1 mb-0 text-lg font-black text-amber-700">{data.summary.warning}</p>
              </div>
              <div class="rounded-xl bg-slate-50 p-3">
                <p class="m-0 text-[11px] font-extrabold text-slate-500">이상</p>
                <p class="mt-1 mb-0 text-lg font-black text-rose-700">{data.summary.critical}</p>
              </div>
            </div>
          )}

          {visibleChecks.length > 0 && (
            <div class="mt-4 space-y-2">
              {visibleChecks.map((check) => {
                const checkTone = healthTone(check.status);
                return (
                  <div class="flex min-w-0 items-start justify-between gap-3 rounded-xl border border-slate-200 px-3 py-2.5" key={check.id}>
                    <div class="min-w-0">
                      <p class="m-0 text-xs font-extrabold text-slate-900">{check.label}</p>
                      <p class="mt-1 mb-0 text-xs leading-5 text-slate-500">{check.message}</p>
                    </div>
                    <span class={`shrink-0 rounded-full px-2 py-1 text-[11px] font-extrabold ${checkTone.badge}`}>
                      {checkTone.label}
                    </span>
                  </div>
                );
              })}
            </div>
          )}

          <div class="mt-4 flex flex-col gap-2 sm:flex-row">
            <button
              class="inline-flex min-h-11 w-full items-center justify-center rounded-xl bg-teal-700 px-4 py-2.5 text-sm font-extrabold text-white transition hover:bg-teal-800 disabled:cursor-wait disabled:opacity-60 sm:w-auto"
              disabled={props.running || props.loading}
              onClick={props.onRun}
              type="button"
            >
              {props.running ? '진단 중' : '지금 진단'}
            </button>
            <button
              class="inline-flex min-h-11 w-full items-center justify-center rounded-xl border border-slate-300 bg-white px-4 py-2.5 text-sm font-extrabold text-slate-800 transition hover:bg-slate-50 disabled:cursor-wait disabled:opacity-60 sm:w-auto"
              disabled={props.downloadBusy}
              onClick={props.onDownload}
              type="button"
            >
              {props.downloadBusy ? '진단 정보 생성 중' : '진단 정보 다운로드'}
            </button>
          </div>
          <p class="mt-3 mb-0 text-xs leading-5 text-slate-500">
            다운로드 파일에는 호스트명, WAN IP와 Wi-Fi SSID 같은 네트워크 식별 정보가 포함될 수 있으므로 외부 전달 전에 내용을 확인해 주세요.
          </p>

          <div class="mt-5 border-t border-slate-200 pt-5">
            <div class="flex min-w-0 items-start justify-between gap-4">
              <div class="min-w-0">
                <div class="flex flex-wrap items-center gap-2">
                  <p class="m-0 text-sm font-black text-slate-950">원격 상태 보고</p>
                  <span class="rounded-full bg-slate-100 px-2 py-1 text-[10px] font-extrabold uppercase tracking-[0.08em] text-slate-600">
                    {reporterMembershipLabel(reporter)}
                  </span>
                </div>
                <p class="mt-1 mb-0 text-xs leading-5 text-slate-500">
                  장치의 최소 상태 정보와 이상 코드만 SmartSafeHub 서버에 전송합니다. 기본값은 꺼짐이며 언제든지 다시 끌 수 있습니다.
                </p>
              </div>
              <button
                aria-checked={reporter?.enabled === true}
                aria-label="원격 상태 보고 사용"
                class={`ssh-switch-control relative inline-flex shrink-0 rounded-full border transition focus:outline-none focus-visible:ring-4 focus-visible:ring-teal-100 disabled:cursor-not-allowed disabled:opacity-50 ${
                  reporter?.enabled
                    ? 'border-teal-600 bg-teal-600'
                    : 'border-slate-300 bg-slate-200'
                }`}
                disabled={!data || props.savingReporter || !canToggleReporter}
                onClick={() => props.onSetReporter(!(reporter?.enabled ?? false))}
                role="switch"
                type="button"
              >
                <span
                  aria-hidden="true"
                  class={`ssh-switch-thumb absolute top-1 shadow-sm transition-[left] ${
                    reporter?.enabled ? 'left-6' : 'left-1'
                  }`}
                />
              </button>
            </div>

            {reporter?.eligible ? (
              <div class="mt-4 rounded-xl bg-slate-50 p-4">
                <div
                  class={`mb-4 flex items-start gap-3 rounded-xl border p-3 ${
                    reporterEnabled
                      ? 'border-emerald-200 bg-emerald-50'
                      : 'border-slate-200 bg-white'
                  }`}
                >
                  <span class="mt-0.5 shrink-0">
                    {reporterEnabled ? (
                      <CheckCircleIcon class="size-5 text-emerald-700" />
                    ) : (
                      <PowerIcon class="size-5 text-slate-500" />
                    )}
                  </span>
                  <div class="min-w-0 flex-1">
                    <div class="flex flex-wrap items-center gap-2">
                      <p class="m-0 text-sm font-black text-slate-950">{reporterStateTitle}</p>
                      <span
                        class={`rounded-full px-2 py-0.5 text-[10px] font-extrabold ${
                          props.savingReporter
                            ? 'bg-slate-200 text-slate-700'
                            : reporterEnabled
                              ? 'bg-emerald-100 text-emerald-800'
                              : 'bg-slate-200 text-slate-700'
                        }`}
                      >
                        {props.savingReporter ? '설정 중' : reporterEnabled ? '켜짐' : '꺼짐'}
                      </span>
                    </div>
                    <p class="mt-1 mb-0 text-xs leading-5 text-slate-600">
                      {reporterStateDescription}
                    </p>
                  </div>
                </div>

                <div class="grid grid-cols-1 gap-3 sm:grid-cols-2">
                  <div>
                    <p class="m-0 text-[11px] font-extrabold text-slate-500">최근 전송 상태</p>
                    <p class="mt-1 mb-0 text-sm font-black text-slate-900">
                      {props.savingReporter ? '설정 반영 중' : reporterResultLabel(reporter)}
                    </p>
                  </div>
                  <div>
                    <p class="m-0 text-[11px] font-extrabold text-slate-500">마지막 서버 보고</p>
                    <p class="mt-1 mb-0 text-sm font-black text-slate-900">
                      {reporterLastReportLabel(reporter)}
                    </p>
                  </div>
                </div>
                {reporter.enabled && reporter.lastErrorCode && (
                  <p class="mt-3 mb-0 text-xs font-bold text-rose-700">
                    최근 보고 오류 : {reporter.lastErrorCode}
                  </p>
                )}
              </div>
            ) : (
              <div class="mt-4 rounded-xl border border-slate-200 bg-slate-50 p-4">
                <p class="m-0 text-sm font-extrabold text-slate-900">
                  원격 상태 보고는 유료 멤버십 또는 체험 기간에 사용할 수 있습니다.
                </p>
                <a
                  class="mt-3 inline-flex text-xs font-extrabold text-teal-700 hover:text-teal-800"
                  href="https://www.smartsafehub.com/pricing/"
                  rel="noopener noreferrer"
                  target="_blank"
                >
                  멤버십 알아보기
                </a>
              </div>
            )}

            <div class="mt-4 grid grid-cols-1 gap-3 text-xs leading-5 text-slate-500 sm:grid-cols-2">
              <div class="rounded-xl border border-slate-200 p-3">
                <p class="m-0 font-extrabold text-slate-700">전송되는 정보</p>
                <p class="mt-1 mb-0">메모리·부하·저장 공간 수치, 진단 상태, 이상 코드와 보고 시각</p>
              </div>
              <div class="rounded-xl border border-slate-200 p-3">
                <p class="m-0 font-extrabold text-slate-700">전송하지 않는 정보</p>
                <p class="mt-1 mb-0">호스트명, WAN IP, Wi-Fi SSID/MAC, DNS 요청 내용, 시스템 로그 원문</p>
              </div>
            </div>
          </div>
        </>
      )}
    </ActionCard>
  );
}

function ConfigurationBackupCard(props: {
  action: ConfigurationBackupAction;
  error: string | null;
  message: string | null;
  restoreAccepted: boolean;
  uploadProgress: number | null;
  validated: ConfigurationBackupValidation | null;
  onDiscard: () => Promise<boolean>;
  onDismissFeedback: () => void;
  onDownload: () => void;
  onRestore: () => Promise<boolean>;
  onUpload: (file: File) => Promise<boolean>;
}) {
  const inputRef = useRef<HTMLInputElement>(null);
  const [selectedFile, setSelectedFile] = useState<File | null>(null);
  const [confirmingRestore, setConfirmingRestore] = useState(false);
  const busy = props.action !== null;

  useEffect(() => {
    if (!props.validated) {
      setConfirmingRestore(false);
    }
  }, [props.validated]);

  const chooseFile = () => {
    if (!busy && !props.restoreAccepted) {
      inputRef.current?.click();
    }
  };

  const uploadSelectedFile = async () => {
    if (!selectedFile) {
      return;
    }
    if (await props.onUpload(selectedFile)) {
      setSelectedFile(null);
      if (inputRef.current) {
        inputRef.current.value = '';
      }
    }
  };

  return (
    <ActionCard
      description="펌웨어 업데이트나 복구 전에 현재 OpenWrt 설정을 표준 백업 파일로 저장하고, 필요할 때 검증 후 복원합니다."
      icon={<DatabaseIcon class="size-5" />}
      title="설정 백업 및 복원"
    >
      {(props.error || props.message) && (
        <div
          class={`mb-5 flex min-w-0 items-start justify-between gap-3 rounded-xl border px-4 py-3 text-sm font-bold ${
            props.error
              ? 'border-rose-200 bg-rose-50 text-rose-800'
              : 'border-emerald-200 bg-emerald-50 text-emerald-800'
          }`}
        >
          <span class="min-w-0">{props.error || props.message}</span>
          {!props.restoreAccepted && (
            <button
              class="shrink-0 rounded-lg px-2 py-1 text-xs font-extrabold hover:bg-black/5"
              onClick={props.onDismissFeedback}
              type="button"
            >
              닫기
            </button>
          )}
        </div>
      )}

      <div class="grid min-w-0 grid-cols-1 gap-3">
        <div class="rounded-xl border border-slate-200 bg-slate-50 p-4 sm:p-5">
          <p class="m-0 text-sm font-black text-slate-900">현재 설정 백업</p>
          <p class="mt-2 mb-0 text-xs leading-5 text-slate-600">
            네트워크, Wi-Fi, SmartSafeHub와 SafeShield 등 OpenWrt가 관리하는 설정을 표준 백업 파일로 저장합니다.
          </p>
          <button
            class="mt-4 inline-flex min-h-11 w-full items-center justify-center gap-2 rounded-xl bg-teal-700 px-4 py-2.5 text-sm font-extrabold text-white transition hover:bg-teal-800 disabled:cursor-wait disabled:opacity-60 sm:w-auto"
            disabled={busy || props.restoreAccepted}
            onClick={props.onDownload}
            type="button"
          >
            <DownloadIcon class="size-4" />
            {props.action === 'download' ? '백업 생성 중' : '설정 백업 다운로드'}
          </button>
          <p class="mt-3 mb-0 text-xs font-bold leading-5 text-amber-700">
            백업에는 Wi-Fi 비밀번호, 관리자 설정, VPN 키나 라이선스 정보 같은 민감한 값이 포함될 수 있으므로 안전한 위치에 보관해 주세요.
          </p>
        </div>

        <div class="rounded-xl border border-slate-200 bg-white p-4 sm:p-5">
          <p class="m-0 text-sm font-black text-slate-900">설정 복원</p>
          <p class="mt-2 mb-0 text-xs leading-5 text-slate-600">
            SmartSafeHub 또는 OpenWrt 백업을 업로드하고 검증한 뒤 복원합니다. 최대 16MB까지 사용할 수 있습니다.
          </p>

          {!props.validated ? (
            <>
              <input
                accept=".tar.gz,.tgz,application/gzip,application/x-gzip"
                class="sr-only"
                disabled={busy || props.restoreAccepted}
                onChange={(event) =>
                  setSelectedFile(event.currentTarget.files?.[0] ?? null)
                }
                ref={inputRef}
                type="file"
              />
              <button
                class="mt-4 flex min-h-11 w-full items-center justify-between gap-3 rounded-xl border border-dashed border-slate-300 bg-slate-50 px-4 py-3 text-left text-sm font-bold text-slate-700 transition hover:border-teal-400 hover:bg-teal-50 disabled:cursor-wait disabled:opacity-60"
                disabled={busy || props.restoreAccepted}
                onClick={chooseFile}
                type="button"
              >
                <span class="min-w-0 truncate">
                  {selectedFile?.name ?? '복원할 백업 파일 선택'}
                </span>
                <span class="shrink-0 text-xs font-extrabold text-teal-700">찾아보기</span>
              </button>
              {selectedFile && (
                <div class="mt-3 flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
                  <span class="text-xs font-bold text-slate-500">
                    {formatBytes(selectedFile.size)}
                  </span>
                  <button
                    class="inline-flex min-h-10 w-full items-center justify-center rounded-xl border border-teal-300 bg-white px-4 py-2 text-sm font-extrabold text-teal-800 transition hover:bg-teal-50 disabled:cursor-wait disabled:opacity-60 sm:w-auto"
                    disabled={busy || props.restoreAccepted}
                    onClick={() => void uploadSelectedFile()}
                    type="button"
                  >
                    {props.action === 'upload'
                      ? `업로드 중 ${Math.round(props.uploadProgress ?? 0)}%`
                      : props.action === 'validate'
                        ? '백업 검증 중'
                        : '업로드 및 검증'}
                  </button>
                </div>
              )}
            </>
          ) : (
            <div class="mt-4 rounded-xl border border-emerald-200 bg-emerald-50 p-4">
              <div class="flex min-w-0 flex-col gap-1 sm:flex-row sm:items-center sm:justify-between">
                <div class="min-w-0">
                  <p class="m-0 break-words text-sm font-extrabold text-emerald-900">
                    {props.validated.filename}
                  </p>
                  <p class="mt-1 mb-0 text-xs font-bold text-emerald-700">
                    {formatBytes(props.validated.sizeBytes)} · 검증 완료
                  </p>
                </div>
              </div>

              {!confirmingRestore ? (
                <div class="mt-4 flex flex-col gap-3 sm:flex-row sm:flex-wrap">
                  <button
                    class="inline-flex min-h-10 w-full items-center justify-center rounded-xl border border-slate-300 bg-white px-4 py-2 text-sm font-extrabold text-slate-700 transition hover:bg-slate-50 disabled:opacity-60 sm:w-auto"
                    disabled={busy || props.restoreAccepted}
                    onClick={() => void props.onDiscard()}
                    type="button"
                  >
                    {props.action === 'discard' ? '파일 삭제 중' : '파일 삭제'}
                  </button>
                  <button
                    class="inline-flex min-h-10 w-full items-center justify-center rounded-xl bg-amber-600 px-4 py-2 text-sm font-extrabold text-white transition hover:bg-amber-700 disabled:opacity-60 sm:w-auto"
                    disabled={busy || props.restoreAccepted}
                    onClick={() => setConfirmingRestore(true)}
                    type="button"
                  >
                    복원 준비
                  </button>
                </div>
              ) : (
                <div class="mt-4 rounded-xl border border-rose-200 bg-white p-4">
                  <p class="m-0 text-sm font-black text-rose-900">
                    현재 설정을 백업 파일의 내용으로 덮어쓰시겠습니까?
                  </p>
                  <p class="mt-2 mb-0 text-xs leading-5 text-rose-700">
                    LAN 주소, Wi-Fi, 관리자 접속 정보가 바뀌어 현재 연결이 끊길 수 있습니다. 복원 직후 공유기가 자동으로 재부팅됩니다. 같은 장치와 호환되는 백업만 사용해 주세요.
                  </p>
                  <div class="mt-4 flex flex-col gap-3 sm:flex-row sm:flex-wrap">
                    <button
                      class="inline-flex min-h-10 w-full items-center justify-center rounded-xl border border-slate-300 bg-white px-4 py-2 text-sm font-extrabold text-slate-700 transition hover:bg-slate-50 disabled:opacity-60 sm:w-auto"
                      disabled={busy}
                      onClick={() => setConfirmingRestore(false)}
                      type="button"
                    >
                      취소
                    </button>
                    <button
                      class="inline-flex min-h-10 w-full items-center justify-center rounded-xl bg-rose-700 px-4 py-2 text-sm font-extrabold text-white transition hover:bg-rose-800 disabled:cursor-wait disabled:opacity-60 sm:w-auto"
                      disabled={busy}
                      onClick={() => void props.onRestore()}
                      type="button"
                    >
                      {props.action === 'restore' ? '설정 복원 중' : '설정 복원 및 재부팅'}
                    </button>
                  </div>
                </div>
              )}
            </div>
          )}
        </div>
      </div>
    </ActionCard>
  );
}


function SystemToolsCard(props: {
  action: SystemAction;
  advancedSystemUrl: string;
  confirmingReboot: boolean;
  logsUrl: string;
  rebootAccepted: boolean;
  onCancelReboot: () => void;
  onConfirmReboot: () => void;
  onReboot: () => void;
}) {
  return (
    <ActionCard
      description="공유기 재부팅과 SmartSafeHub에서 제공하지 않는 고급 관리 도구를 한곳에서 제공합니다."
      icon={<SettingsIcon class="size-5" />}
      title="시스템 도구"
    >
      <div class="space-y-3">
        <section
          aria-labelledby="router-reboot-heading"
          class="rounded-xl border border-slate-200 bg-slate-50 p-4"
        >
          <div class="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
            <div class="flex min-w-0 items-start gap-3">
              <span class="flex size-9 shrink-0 items-center justify-center rounded-lg bg-rose-50 text-rose-700">
                <PowerIcon class="size-4" />
              </span>
              <div class="min-w-0">
                <p
                  class="m-0 text-sm font-black text-rose-950"
                  id="router-reboot-heading"
                >
                  공유기 재부팅
                </p>
                <p class="mt-1 mb-0 text-xs leading-5 text-slate-500">
                  재부팅 중에는 인터넷과 Wi-Fi 연결이 잠시 중단됩니다.
                </p>
              </div>
            </div>
            {!props.confirmingReboot && (
              <button
                class="inline-flex min-h-10 w-full shrink-0 items-center justify-center rounded-xl border border-rose-300 bg-white px-3 py-2 text-xs font-extrabold text-rose-700 transition hover:bg-rose-50 disabled:opacity-60 sm:w-auto"
                disabled={props.action !== null || props.rebootAccepted}
                onClick={props.onConfirmReboot}
                type="button"
              >
                재부팅
              </button>
            )}
          </div>

          {props.confirmingReboot && (
            <div class="mt-3 rounded-xl border border-rose-200 bg-rose-50 p-3">
              <p class="m-0 text-xs font-extrabold leading-5 text-rose-900">
                지금 공유기를 재부팅하시겠습니까? 저장되지 않은 LuCI 설정이 있다면 먼저 저장해 주세요.
              </p>
              <div class="mt-3 flex flex-col gap-2 sm:flex-row sm:flex-wrap">
                <button
                  class="inline-flex min-h-10 w-full items-center justify-center rounded-xl border border-slate-300 bg-white px-3 py-2 text-xs font-extrabold text-slate-700 transition hover:bg-slate-50 sm:w-auto"
                  disabled={props.action !== null}
                  onClick={props.onCancelReboot}
                  type="button"
                >
                  취소
                </button>
                <button
                  class="inline-flex min-h-10 w-full items-center justify-center rounded-xl bg-rose-700 px-3 py-2 text-xs font-extrabold text-white transition hover:bg-rose-800 disabled:cursor-wait disabled:opacity-60 sm:w-auto"
                  disabled={props.action !== null}
                  onClick={props.onReboot}
                  type="button"
                >
                  {props.action === 'reboot' ? '재부팅 요청 중' : '지금 재부팅'}
                </button>
              </div>
            </div>
          )}
        </section>

        <section
          aria-labelledby="advanced-tools-heading"
          class="rounded-xl border border-slate-200 bg-slate-50 p-4"
        >
          <div class="min-w-0">
            <p
              class="m-0 text-sm font-black text-slate-900"
              id="advanced-tools-heading"
            >
              고급 도구
            </p>
            <p class="mt-1 mb-0 text-xs leading-5 text-slate-500">
              SmartSafeHub에서 아직 제공하지 않는 상세 시스템 설정이나 원본 로그가 필요할 때 사용합니다.
            </p>
          </div>
          <div class="mt-3 flex flex-col gap-2 sm:flex-row sm:flex-wrap">
            <a
              class="inline-flex min-h-10 w-full items-center justify-center rounded-xl border border-slate-300 bg-white px-3 py-2 text-xs font-extrabold text-slate-800 no-underline transition hover:bg-slate-50 sm:w-auto"
              href={props.advancedSystemUrl}
            >
              LuCI 고급 설정 열기
            </a>
            <a
              class="inline-flex min-h-10 w-full items-center justify-center rounded-xl border border-slate-300 bg-white px-3 py-2 text-xs font-extrabold text-slate-800 no-underline transition hover:bg-slate-50 sm:w-auto"
              href={props.logsUrl}
            >
              시스템 로그 열기
            </a>
          </div>
        </section>
      </div>
    </ActionCard>
  );
}


const scheduledRebootDays: Array<{
  value: ScheduledRebootDayOfWeek;
  label: string;
}> = [
  { value: 'mon', label: '월요일' },
  { value: 'tue', label: '화요일' },
  { value: 'wed', label: '수요일' },
  { value: 'thu', label: '목요일' },
  { value: 'fri', label: '금요일' },
  { value: 'sat', label: '토요일' },
  { value: 'sun', label: '일요일' },
];

function ScheduledRebootSection(props: {
  data: ScheduledRebootSettings | null;
  error: string | null;
  loading: boolean;
  saveError: string | null;
  saveMessage: string | null;
  saving: boolean;
  onDismissFeedback: () => void;
  onRetry: () => void;
  onSave: (input: ScheduledRebootSettingsInput) => Promise<boolean>;
}) {
  const [enabled, setEnabled] = useState(false);
  const [frequency, setFrequency] = useState<ScheduledRebootFrequency>('weekly');
  const [dayOfWeek, setDayOfWeek] = useState<ScheduledRebootDayOfWeek>('sun');
  const [rebootTime, setRebootTime] = useState('04:00');

  useEffect(() => {
    if (!props.data) {
      return;
    }
    setEnabled(props.data.enabled);
    setFrequency(props.data.frequency);
    setDayOfWeek(props.data.dayOfWeek);
    setRebootTime(props.data.time);
  }, [
    props.data?.dayOfWeek,
    props.data?.enabled,
    props.data?.frequency,
    props.data?.time,
  ]);

  const changed =
    props.data !== null &&
    (enabled !== props.data.enabled ||
      frequency !== props.data.frequency ||
      dayOfWeek !== props.data.dayOfWeek ||
      rebootTime !== props.data.time);
  const selectedDay = scheduledRebootDays.find((item) => item.value === dayOfWeek);
  const scheduleSummary = enabled
    ? frequency === 'daily'
      ? `매일 ${rebootTime}`
      : `매주 ${selectedDay?.label ?? '일요일'} ${rebootTime}`
    : '예약 재부팅 꺼짐';

  return (
    <section
      aria-labelledby="scheduled-reboot-heading"
      class="mt-6 border-t border-slate-200 pt-6"
    >
      <div class="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
        <div class="flex min-w-0 items-start gap-3">
          <span class="flex size-10 shrink-0 items-center justify-center rounded-xl bg-slate-100 text-slate-600">
            <CalendarIcon class="size-5" />
          </span>
          <div class="min-w-0">
            <h3 class="m-0 text-base font-black text-slate-950" id="scheduled-reboot-heading">
              예약 재부팅
            </h3>
            <p class="mt-1.5 mb-0 text-xs leading-5 text-slate-500">
              공유기를 정해진 시간에 자동으로 재부팅합니다. 기본값은 꺼짐이며 필요한 장치에서만 사용하세요.
            </p>
          </div>
        </div>
        <div class="flex shrink-0 flex-wrap items-center justify-between gap-3 sm:justify-end">
          {changed && (
            <span
              aria-live="polite"
              class="inline-flex items-center gap-1.5 rounded-full border border-amber-200 bg-amber-50 px-2.5 py-1 text-xs font-extrabold text-amber-800"
              role="status"
            >
              <AlertIcon aria-hidden="true" class="size-3.5 shrink-0" />
              저장되지 않음
            </span>
          )}
          <span class="text-xs font-extrabold text-slate-500">
            {enabled ? '사용 중' : '꺼짐'}
          </span>
          <button
            aria-checked={enabled}
            aria-label="예약 재부팅 사용"
            class={`ssh-switch-control relative inline-flex shrink-0 rounded-full border transition focus:outline-none focus-visible:ring-4 focus-visible:ring-teal-100 disabled:cursor-not-allowed disabled:opacity-50 ${
              enabled
                ? 'border-teal-600 bg-teal-600'
                : 'border-slate-300 bg-slate-200'
            }`}
            disabled={props.loading || props.saving || !props.data}
            onClick={() => setEnabled((current) => !current)}
            role="switch"
            type="button"
          >
            <span
              aria-hidden="true"
              class={`ssh-switch-thumb absolute top-1 shadow-sm transition-[left] ${
                enabled ? 'left-6' : 'left-1'
              }`}
            />
          </button>
        </div>
      </div>

      {(props.saveError || props.saveMessage) && (
        <div
          class={`mt-4 flex min-w-0 items-start justify-between gap-3 rounded-xl border px-4 py-3 text-sm font-bold ${
            props.saveError
              ? 'border-rose-200 bg-rose-50 text-rose-800'
              : 'border-emerald-200 bg-emerald-50 text-emerald-800'
          }`}
        >
          <span class="min-w-0">{props.saveError || props.saveMessage}</span>
          <button
            class="shrink-0 rounded-lg px-2 py-1 text-xs font-extrabold hover:bg-black/5"
            onClick={props.onDismissFeedback}
            type="button"
          >
            닫기
          </button>
        </div>
      )}

      {props.error && !props.data ? (
        <div class="mt-4 rounded-xl border border-rose-200 bg-rose-50 p-4">
          <p class="m-0 text-sm font-bold text-rose-800">{props.error}</p>
          <button
            class="mt-3 inline-flex min-h-10 items-center rounded-xl border border-rose-300 bg-white px-3 py-2 text-xs font-extrabold text-rose-700 transition hover:bg-rose-100"
            onClick={props.onRetry}
            type="button"
          >
            다시 불러오기
          </button>
        </div>
      ) : (
        <>
          <div class="mt-4 grid min-w-0 grid-cols-1 gap-4 md:grid-cols-3">
            <div>
              <label class="mb-2 block text-sm font-extrabold text-slate-800" for="scheduled-reboot-frequency">
                주기
              </label>
              <CustomSelect
                ariaLabel="예약 재부팅 주기"
                disabled={!enabled || props.saving || !props.data}
                id="scheduled-reboot-frequency"
                onChange={(nextValue) =>
                  setFrequency(nextValue as ScheduledRebootFrequency)
                }
                options={[
                  { value: 'weekly', label: '매주' },
                  { value: 'daily', label: '매일' },
                ]}
                value={frequency}
              />
            </div>

            <div>
              <label class="mb-2 block text-sm font-extrabold text-slate-800" for="scheduled-reboot-day">
                요일
              </label>
              <CustomSelect
                ariaLabel="예약 재부팅 요일"
                disabled={!enabled || frequency !== 'weekly' || props.saving || !props.data}
                id="scheduled-reboot-day"
                onChange={(nextValue) =>
                  setDayOfWeek(nextValue as ScheduledRebootDayOfWeek)
                }
                options={scheduledRebootDays.map((day) => ({
                  value: day.value,
                  label: day.label,
                }))}
                value={dayOfWeek}
              />
            </div>

            <div>
              <label class="mb-2 block text-sm font-extrabold text-slate-800" for="scheduled-reboot-time-hour">
                재부팅 시간
              </label>
              <TimeSelect
                ariaLabel="예약 재부팅 시간"
                disabled={!enabled || props.saving || !props.data}
                id="scheduled-reboot-time"
                onChange={setRebootTime}
                value={rebootTime}
              />
            </div>
          </div>

          <div class="mt-4 flex flex-col gap-3 rounded-xl bg-slate-50 p-4 sm:flex-row sm:items-end sm:justify-between">
            <div class="min-w-0">
              <p class="m-0 text-xs font-extrabold uppercase tracking-[0.12em] text-slate-500">
                예약 일정
              </p>
              <p class="mt-1.5 mb-0 text-sm font-extrabold text-slate-900">
                {scheduleSummary}
              </p>
              <p class="mt-1 mb-0 text-xs leading-5 text-slate-500">
                {props.data?.timezone ?? '장치 시간대'} 기준 · 업데이트 작업 중이면 15분 단위로 최대 2시간 연기합니다.
              </p>
            </div>
            <button
              class="inline-flex min-h-11 w-full shrink-0 items-center justify-center rounded-xl bg-teal-700 px-4 py-2.5 text-sm font-extrabold text-white transition hover:bg-teal-800 disabled:cursor-not-allowed disabled:opacity-50 sm:w-auto"
              disabled={!changed || props.saving || !props.data}
              onClick={() =>
                void props.onSave({
                  enabled,
                  frequency,
                  dayOfWeek,
                  time: rebootTime,
                })
              }
              type="button"
            >
              {props.saving ? '예약 저장 중' : '예약 저장'}
            </button>
          </div>
        </>
      )}
    </section>
  );
}

export function SettingsPage({
  action,
  backupAction,
  backupError,
  backupMessage,
  backupRestoreAccepted,
  backupUploadProgress,
  backupValidated,
  data,
  error,
  feedbackError,
  feedbackMessage,
  firmware,
  firmwareError,
  firmwareLoading,
  health,
  healthActionError,
  healthActionMessage,
  healthError,
  healthLoading,
  healthRunning,
  healthSavingReporter,
  loading,
  rebootAccepted,
  scheduledRebootData,
  scheduledRebootError,
  scheduledRebootLoading,
  scheduledRebootSaveError,
  scheduledRebootSaveMessage,
  scheduledRebootSaving,
  timeData,
  timeError,
  timeLoading,
  timeSaveError,
  timeSaveMessage,
  timeSaving,
  timeSyncing,
  onBackupDiscard,
  onBackupDownload,
  onBackupRestore,
  onBackupUpload,
  onDismissBackupFeedback,
  onDismissFeedback,
  onDismissHealthFeedback,
  onDismissTimeFeedback,
  onDownloadDiagnostics,
  onRunHealth,
  onSetHealthReporter,
  onReboot,
  onRetry,
  onDismissScheduledRebootFeedback,
  onSaveScheduledReboot,
  onSaveTimezone,
  onSyncTime,
}: SettingsPageProps) {
  const [confirmingReboot, setConfirmingReboot] = useState(false);

  if (loading && !data) {
    return (
      <div class="rounded-2xl border border-slate-200 bg-white p-8 text-center shadow-sm shadow-slate-900/5">
        <p class="m-0 text-sm font-bold text-slate-500">시스템 정보를 확인하고 있습니다.</p>
      </div>
    );
  }

  if (error && !data) {
    return (
      <div class="rounded-2xl border border-rose-200 bg-rose-50 p-6">
        <h2 class="m-0 text-lg font-black text-rose-900">
          시스템 정보를 불러오지 못했습니다.
        </h2>
        <p class="mt-2 mb-0 text-sm leading-6 text-rose-700">{error}</p>
        <button
          class="mt-4 inline-flex min-h-10 items-center rounded-xl bg-rose-700 px-4 py-2 text-sm font-extrabold text-white transition hover:bg-rose-800"
          onClick={onRetry}
          type="button"
        >
          다시 시도
        </button>
      </div>
    );
  }

  const memory = data?.runtime.memory;
  const totalMemory = memory?.total ?? 0;
  const memoryUsage = memory ? getMemoryUsage(memory) : null;
  const usedMemory = memoryUsage?.used ?? 0;
  const memoryPercent = Math.round(memoryUsage?.percent ?? 0);
  const advancedSystemUrl = luciAdminUrl('/admin/system');
  const logsUrl = luciAdminUrl('/admin/status/logs');
  const customFirmwareAvailable = Boolean(firmware?.current.metadataAvailable);
  const firmwareValue = !data
    ? '미확인'
    : firmwareLoading && !firmware
      ? '확인 중'
      : firmwareError && !firmware
        ? '확인 필요'
        : customFirmwareAvailable
          ? firmware?.current.releaseVersion
            ? `SmartSafeHub ${firmware.current.releaseVersion}`
            : 'SmartSafeHub 펌웨어'
          : `${data.software.distribution} ${data.software.version}`;
  const firmwareDescription = !data
    ? '버전 정보를 확인할 수 없습니다.'
    : firmwareLoading && !firmware
      ? '펌웨어 정보를 확인하고 있습니다.'
      : firmwareError && !firmware
        ? firmwareError
        : customFirmwareAvailable
          ? firmware?.current.buildId
            ? `빌드 ID ${firmware.current.buildId}`
            : '빌드 ID를 확인할 수 없습니다.'
          : `리비전 ${data.software.revision}`;

  return (
    <section class="min-w-0 space-y-7">
      {(feedbackError || feedbackMessage) && (
        <div
          class={`flex min-w-0 flex-col gap-3 rounded-xl border px-4 py-3 text-sm font-bold sm:flex-row sm:items-center sm:justify-between ${
            feedbackError
              ? 'border-rose-200 bg-rose-50 text-rose-800'
              : 'border-emerald-200 bg-emerald-50 text-emerald-800'
          }`}
        >
          <span class="min-w-0">{feedbackError || feedbackMessage}</span>
          {!rebootAccepted && (
            <button
              class="shrink-0 self-start rounded-lg px-3 py-1.5 text-xs font-extrabold hover:bg-black/5 sm:self-auto"
              onClick={onDismissFeedback}
              type="button"
            >
              닫기
            </button>
          )}
        </div>
      )}

      <section class="min-w-0">
        <div class="mb-4">
          <p class="m-0 text-xs font-extrabold uppercase tracking-[0.16em] text-teal-700">
            System
          </p>
          <h2 class="mt-2 mb-0 text-xl font-black text-slate-950">시스템 상태</h2>
          <p class="mt-2 mb-0 text-sm leading-6 text-slate-500">
            장치의 펌웨어, 실행 시간, 메모리와 시스템 부하를 확인합니다.
          </p>
        </div>
        <div class="grid min-w-0 grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-4">
          <InfoCard
            label="Firmware"
            value={firmwareValue}
            description={firmwareDescription}
          />
          <InfoCard
            label="Uptime"
            value={data ? formatUptime(data.runtime.uptime) : '미확인'}
            description={
              data ? `커널 ${data.software.kernel}` : '실행 시간을 확인할 수 없습니다.'
            }
          />
          <InfoCard
            label="Memory"
            value={`${memoryPercent}%`}
            description={`${formatBytes(usedMemory)} / ${formatBytes(totalMemory)} 사용`}
          />
          <InfoCard
            label="Load"
            value={data ? formatLoadAverage(data.runtime.load[0]) : '0.00'}
            description={
              data
                ? `5분 ${formatLoadAverage(data.runtime.load[1])} · 15분 ${formatLoadAverage(data.runtime.load[2])}`
                : '시스템 부하를 확인할 수 없습니다.'
            }
          />
        </div>
      </section>

      <section class="min-w-0">
        <div class="mb-4">
          <p class="m-0 text-xs font-extrabold uppercase tracking-[0.16em] text-teal-700">
            Device settings
          </p>
          <h2 class="mt-2 mb-0 text-xl font-black text-slate-950">장치 설정</h2>
          <p class="mt-2 mb-0 text-sm leading-6 text-slate-500">
            시간 기준과 예약 재부팅, 진단 정보를 SmartSafeHub에서 직접 관리합니다.
          </p>
        </div>
        <div class="grid min-w-0 grid-cols-1 gap-4 lg:grid-cols-2">
          <TimeSettingsCard
            data={timeData}
            error={timeError}
            loading={timeLoading}
            onDismissFeedback={onDismissTimeFeedback}
            onDismissScheduledRebootFeedback={onDismissScheduledRebootFeedback}
            onRetry={onRetry}
            onSave={onSaveTimezone}
            onSaveScheduledReboot={onSaveScheduledReboot}
            onSync={onSyncTime}
            saveError={timeSaveError}
            saveMessage={timeSaveMessage}
            saving={timeSaving}
            scheduledRebootData={scheduledRebootData}
            scheduledRebootError={scheduledRebootError}
            scheduledRebootLoading={scheduledRebootLoading}
            scheduledRebootSaveError={scheduledRebootSaveError}
            scheduledRebootSaveMessage={scheduledRebootSaveMessage}
            scheduledRebootSaving={scheduledRebootSaving}
            syncing={timeSyncing}
          />

          <HealthDiagnosticCard
            actionError={healthActionError}
            actionMessage={healthActionMessage}
            data={health}
            downloadBusy={action === 'diagnostics'}
            error={healthError}
            loading={healthLoading}
            onDismissFeedback={onDismissHealthFeedback}
            onDownload={onDownloadDiagnostics}
            onRetry={onRetry}
            onRun={onRunHealth}
            onSetReporter={onSetHealthReporter}
            running={healthRunning}
            savingReporter={healthSavingReporter}
          />
        </div>
      </section>

      <section class="min-w-0">
        <div class="mb-4">
          <p class="m-0 text-xs font-extrabold uppercase tracking-[0.16em] text-teal-700">
            System management
          </p>
          <h2 class="mt-2 mb-0 text-xl font-black text-slate-950">시스템 관리</h2>
          <p class="mt-2 mb-0 text-sm leading-6 text-slate-500">
            설정 백업·복원, 공유기 재부팅과 고급 시스템 도구를 한곳에서 관리합니다.
          </p>
        </div>
        <div class="grid min-w-0 grid-cols-1 gap-4 lg:grid-cols-2">
          <ConfigurationBackupCard
            action={backupAction}
            error={backupError}
            message={backupMessage}
            onDiscard={onBackupDiscard}
            onDismissFeedback={onDismissBackupFeedback}
            onDownload={onBackupDownload}
            onRestore={onBackupRestore}
            onUpload={onBackupUpload}
            restoreAccepted={backupRestoreAccepted}
            uploadProgress={backupUploadProgress}
            validated={backupValidated}
          />


          <SystemToolsCard
            action={action}
            advancedSystemUrl={advancedSystemUrl}
            confirmingReboot={confirmingReboot}
            logsUrl={logsUrl}
            onCancelReboot={() => setConfirmingReboot(false)}
            onConfirmReboot={() => setConfirmingReboot(true)}
            onReboot={onReboot}
            rebootAccepted={rebootAccepted}
          />
        </div>
      </section>
    </section>
  );
}
