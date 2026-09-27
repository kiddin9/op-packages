import { useEffect, useState } from 'preact/hooks';

import { CustomSelect } from './CustomSelect';
import { TimeSelect } from './TimeSelect';
import type { SoftwareUpdateAction } from '../hooks/useSoftwareUpdates';
import type {
  SoftwareUpdateChannel,
  SoftwareUpdateError,
  SoftwareUpdateSettingsInput,
  SoftwareUpdateStatus,
} from '../types/updates';
import { isSoftwareUpdateCheckStale } from '../utils/softwareUpdates';
import {
  AlertIcon,
  CheckCircleIcon,
  ClockIcon,
  DownloadIcon,
  ReloadIcon,
  SettingsIcon,
  UpdateIcon,
} from './Icons';

interface SoftwareUpdatesCardProps {
  action: SoftwareUpdateAction;
  actionError: string | null;
  data: SoftwareUpdateStatus | null;
  error: string | null;
  loading: boolean;
  message: string | null;
  onCheck: () => void;
  onDismissFeedback: () => void;
  onInstall: () => void;
  onRetry: () => void;
  onSaveSettings: (input: SoftwareUpdateSettingsInput) => Promise<boolean>;
}

const INTERVAL_OPTIONS = [
  { value: 3600, label: '1시간마다' },
  { value: 21600, label: '6시간마다' },
  { value: 43200, label: '12시간마다' },
  { value: 86400, label: '24시간마다' },
] as const;

const UPDATE_PACKAGE = 'luci-app-smartsafehub';

function formatTimestamp(value: number | null): string {
  if (!value) {
    return '아직 없음';
  }

  return new Date(value * 1000).toLocaleString('ko-KR', {
    dateStyle: 'medium',
    timeStyle: 'short',
  });
}

function updateChannelLabel(channel: SoftwareUpdateChannel): string {
  if (channel === 'stable') {
    return 'Stable';
  }
  if (channel === 'beta') {
    return 'Beta';
  }
  return '미확인';
}

function updateChannelClass(channel: SoftwareUpdateChannel): string {
  if (channel === 'stable') {
    return 'bg-emerald-50 text-emerald-700 ring-emerald-200';
  }
  if (channel === 'beta') {
    return 'bg-amber-50 text-amber-700 ring-amber-200';
  }
  return 'bg-slate-100 text-slate-600 ring-slate-200';
}

function updateErrorSummary(error: SoftwareUpdateError): { title: string; description: string } {
  if (error.code === 'UPDATES_INDEX_REFRESH_FAILED') {
    return {
      title: '패키지 저장소를 확인하지 못했습니다.',
      description:
        'OpenWrt 패키지 저장소 동기화 또는 네트워크 상태가 일시적으로 불안정할 수 있습니다. 잠시 후 업데이트 확인을 다시 실행해 주세요.',
    };
  }

  if (error.code === 'UPDATES_INSTALL_FAILED') {
    return {
      title: '관리 소프트웨어 업데이트 설치에 실패했습니다.',
      description:
        '패키지 설치가 완료되지 않았습니다. 네트워크 연결과 저장 공간을 확인한 뒤 다시 시도해 주세요.',
    };
  }

  return {
    title: '최근 업데이트 작업을 완료하지 못했습니다.',
    description: '잠시 후 다시 시도해 주세요. 문제가 반복되면 상세 정보를 확인해 주세요.',
  };
}

function phaseLabel(data: SoftwareUpdateStatus, stale: boolean): string {
  if (data.phase === 'checking') {
    return '업데이트 확인 중';
  }
  if (data.phase === 'installing') {
    return '업데이트 설치 중';
  }
  if (data.phase === 'error') {
    return '확인 필요';
  }
  if (data.updateCount > 0) {
    return '업데이트 가능';
  }
  if (stale) {
    return '업데이트 확인 지연';
  }
  return data.lastCheckAt ? '최신 상태' : '확인 전';
}

function phaseClass(data: SoftwareUpdateStatus, stale: boolean): string {
  if (data.phase === 'error') {
    return 'bg-rose-50 text-rose-700 ring-rose-200';
  }
  if (data.phase === 'checking' || data.phase === 'installing') {
    return 'bg-sky-50 text-sky-700 ring-sky-200';
  }
  if (data.updateCount > 0 || stale) {
    return 'bg-amber-50 text-amber-800 ring-amber-200';
  }
  if (!data.lastCheckAt) {
    return 'bg-slate-100 text-slate-600 ring-slate-200';
  }
  return 'bg-emerald-50 text-emerald-700 ring-emerald-200';
}

function updatePhaseIcon(data: SoftwareUpdateStatus, stale: boolean) {
  if (data.phase === 'checking' || data.phase === 'installing') {
    return <ReloadIcon class="size-3.5 shrink-0 animate-spin" />;
  }
  if (data.phase === 'error') {
    return <AlertIcon class="size-3.5 shrink-0" />;
  }
  if (data.updateCount > 0) {
    return <DownloadIcon class="size-3.5 shrink-0" />;
  }
  if (stale) {
    return <AlertIcon class="size-3.5 shrink-0" />;
  }
  if (!data.lastCheckAt) {
    return <ClockIcon class="size-3.5 shrink-0" />;
  }
  return <CheckCircleIcon class="size-3.5 shrink-0" />;
}

function SettingSwitch({
  checked,
  disabled = false,
  label,
  onChange,
}: {
  checked: boolean;
  disabled?: boolean;
  label: string;
  onChange: (checked: boolean) => void;
}) {
  return (
    <button
      aria-checked={checked}
      aria-label={label}
      class={`ssh-switch-control relative inline-flex shrink-0 rounded-full border transition focus:outline-none focus-visible:ring-4 focus-visible:ring-teal-100 disabled:cursor-not-allowed disabled:opacity-50 ${
        checked ? 'border-teal-600 bg-teal-600' : 'border-slate-300 bg-slate-200'
      }`}
      disabled={disabled}
      onClick={() => onChange(!checked)}
      role="switch"
      type="button"
    >
      <span
        aria-hidden="true"
        class={`ssh-switch-thumb absolute top-1 shadow-sm transition-[left] ${
          checked ? 'left-6' : 'left-1'
        }`}
      />
    </button>
  );
}

export function SoftwareUpdatesCard({
  action,
  actionError,
  data,
  error,
  loading,
  message,
  onCheck,
  onDismissFeedback,
  onInstall,
  onRetry,
  onSaveSettings,
}: SoftwareUpdatesCardProps) {
  const [checkEnabled, setCheckEnabled] = useState(true);
  const [checkIntervalSeconds, setCheckIntervalSeconds] = useState(21600);
  const [autoInstall, setAutoInstall] = useState(false);
  const [autoInstallTime, setAutoInstallTime] = useState('03:00');
  const [settingsDirty, setSettingsDirty] = useState(false);
  const [confirmingInstall, setConfirmingInstall] = useState(false);

  useEffect(() => {
    if (!data || settingsDirty) {
      return;
    }

    setCheckEnabled(data.settings.checkEnabled);
    setCheckIntervalSeconds(data.settings.checkIntervalSeconds);
    setAutoInstall(data.settings.autoInstall);
    setAutoInstallTime(data.settings.autoInstallTime);
  }, [data, settingsDirty]);

  const checking = action === 'check' || data?.phase === 'checking';
  const installing = action === 'install' || data?.phase === 'installing';
  const busy = checking || installing;
  const updateCheckStale = isSoftwareUpdateCheckStale(data);
  const repositoryCheckFailed =
    data?.phase === 'error' && data.lastError?.code === 'UPDATES_INDEX_REFRESH_FAILED';
  const lastErrorSummary = data?.lastError ? updateErrorSummary(data.lastError) : null;

  const currentPackage = data?.packages.find((item) => item.name === UPDATE_PACKAGE) ??
    data?.packages[0] ??
    null;

  const hasSettingsChanges = (next: Partial<SoftwareUpdateSettingsInput> = {}) => {
    if (!data) {
      return false;
    }

    return (
      (next.checkEnabled ?? checkEnabled) !== data.settings.checkEnabled ||
      (next.checkIntervalSeconds ?? checkIntervalSeconds) !== data.settings.checkIntervalSeconds ||
      (next.autoInstall ?? autoInstall) !== data.settings.autoInstall ||
      (next.autoInstallTime ?? autoInstallTime) !== data.settings.autoInstallTime
    );
  };

  const saveSettings = async () => {
    const saved = await onSaveSettings({
      checkEnabled,
      checkIntervalSeconds,
      autoInstall,
      autoInstallTime,
    });
    if (saved) {
      setSettingsDirty(false);
    }
  };

  return (
    <article
      class={`min-w-0 overflow-hidden rounded-2xl border border-slate-200 bg-white shadow-sm shadow-slate-900/5 ${data ? 'grid xl:grid-cols-[minmax(0,0.95fr)_minmax(0,1.05fr)]' : ''}`}
      data-component="management-software-update-card"
      data-layout="management-software-sections"
    >
      <section class="min-w-0 xl:col-start-1 xl:row-start-1" data-section="software-update-status">
        <div class="p-5 sm:p-6">
          <div class="flex flex-col gap-5 lg:flex-row lg:items-start lg:justify-between">
            <div class="flex min-w-0 gap-4">
              <span class="grid size-12 shrink-0 place-items-center rounded-2xl bg-teal-50 text-teal-700">
                <UpdateIcon class="size-6" />
              </span>
              <div class="min-w-0">
                <div class="flex flex-wrap items-center gap-2">
                  <p class="m-0 text-xs font-extrabold uppercase tracking-[0.16em] text-teal-700">
                    Management software
                  </p>
                  {data ? (
                    <span
                      class={`inline-flex items-center gap-1.5 rounded-full px-2.5 py-1 text-[11px] font-extrabold ring-1 ring-inset ${phaseClass(data, updateCheckStale)}`}
                    >
                      <span aria-hidden="true" class="flex items-center justify-center">{updatePhaseIcon(data, updateCheckStale)}</span>
                      {phaseLabel(data, updateCheckStale)}
                    </span>
                  ) : null}
                </div>
                <h2 class="mt-2 mb-0 text-xl font-black text-slate-950 sm:text-2xl">
                  관리 소프트웨어 업데이트
                </h2>
                <p class="mt-2 mb-0 text-sm leading-6 text-slate-500 xl:whitespace-nowrap">
                  새 버전을 확인하고 안전하게 설치합니다.
                </p>
              </div>
            </div>

            {data ? (
              <div class="flex shrink-0 flex-col gap-2 sm:flex-row lg:justify-end">
                <button
                  class="inline-flex min-h-11 items-center justify-center gap-2 rounded-xl border border-slate-300 bg-white px-4 py-2.5 text-sm font-extrabold text-slate-800 transition hover:bg-slate-50 disabled:cursor-wait disabled:opacity-60"
                  disabled={busy}
                  onClick={onCheck}
                  type="button"
                >
                  <ReloadIcon class={`size-4 ${checking ? 'animate-spin' : ''}`} />
                  {checking ? '확인 중...' : '업데이트 확인'}
                </button>

                {data.updateCount > 0 && !confirmingInstall ? (
                  <button
                    class="inline-flex min-h-11 items-center justify-center gap-2 rounded-xl bg-teal-700 px-4 py-2.5 text-sm font-extrabold text-white transition hover:bg-teal-800 disabled:cursor-wait disabled:opacity-60"
                    disabled={busy}
                    onClick={() => setConfirmingInstall(true)}
                    type="button"
                  >
                    {installing ? (
                      <ReloadIcon class="size-4 animate-spin" />
                    ) : (
                      <DownloadIcon class="size-4" />
                    )}
                    {installing ? '설치 중...' : '업데이트 설치'}
                  </button>
                ) : null}
              </div>
            ) : null}
          </div>

          {(actionError || message) && (
            <div
              class={`mt-5 flex flex-col gap-3 rounded-xl border px-4 py-3 text-sm font-bold sm:flex-row sm:items-center sm:justify-between ${
                actionError
                  ? 'border-rose-200 bg-rose-50 text-rose-800'
                  : 'border-emerald-200 bg-emerald-50 text-emerald-800'
              }`}
            >
              <span>{actionError || message}</span>
              <button
                class="shrink-0 self-start rounded-lg px-3 py-1.5 text-xs font-extrabold hover:bg-black/5 sm:self-auto"
                onClick={onDismissFeedback}
                type="button"
              >
                닫기
              </button>
            </div>
          )}

          {installing ? (
            <div
              aria-busy="true"
              aria-live="polite"
              class="mt-5 rounded-xl border border-sky-200 bg-sky-50 p-4 sm:p-5"
            >
              <div class="flex items-start gap-3">
                <span class="grid size-10 shrink-0 place-items-center rounded-xl bg-white text-sky-700 ring-1 ring-inset ring-sky-200">
                  <ReloadIcon aria-hidden="true" class="size-5 animate-spin" />
                </span>
                <div class="min-w-0">
                  <h3 class="m-0 text-sm font-black text-sky-950">
                    관리 소프트웨어를 업데이트하고 있습니다.
                  </h3>
                  <p class="mt-1 mb-0 text-sm leading-6 text-sky-800">
                    설치가 완료되면 이 화면이 자동으로 갱신됩니다. 작업 중에는 웹 연결이 잠시 끊길 수 있습니다.
                  </p>
                </div>
              </div>
              <div
                aria-hidden="true"
                class="ssh-update-progress-track mt-4"
              >
                <span class="ssh-update-progress-bar" />
              </div>
            </div>
          ) : null}

          {error && !data ? (
            <div class="mt-5 rounded-xl border border-rose-200 bg-rose-50 p-4 text-sm text-rose-800">
              <p class="m-0 font-bold">{error}</p>
              <button
                class="mt-3 rounded-lg border border-rose-300 bg-white px-3 py-2 text-xs font-extrabold text-rose-700"
                onClick={onRetry}
                type="button"
              >
                다시 시도
              </button>
            </div>
          ) : loading && !data ? (
            <div class="mt-5 flex items-center gap-3 rounded-xl bg-slate-50 p-4 text-sm font-bold text-slate-500">
              <span class="grid size-9 shrink-0 place-items-center rounded-xl bg-white text-teal-700 ring-1 ring-inset ring-slate-200">
                <ReloadIcon aria-hidden="true" class="size-4 animate-spin" />
              </span>
              <span>관리 소프트웨어 업데이트 상태를 확인하고 있습니다.</span>
            </div>
          ) : data ? (
            <>
              {data.lastError && lastErrorSummary ? (
                <div class="mt-5 rounded-xl border border-rose-200 bg-rose-50 p-4 sm:p-5">
                  <div class="flex items-start gap-3">
                    <span class="grid size-10 shrink-0 place-items-center rounded-xl bg-white text-rose-700 ring-1 ring-inset ring-rose-200">
                      <AlertIcon class="size-5" />
                    </span>
                    <div class="min-w-0 flex-1">
                      <p class="m-0 text-sm font-extrabold text-rose-950">
                        {lastErrorSummary.title}
                      </p>
                      <p class="mt-1 mb-0 text-sm leading-6 text-rose-800">
                        {lastErrorSummary.description}
                      </p>
                      {data.lastError.at ? (
                        <p class="mt-2 mb-0 text-xs font-bold text-rose-700">
                          발생 시각 {formatTimestamp(data.lastError.at)}
                        </p>
                      ) : null}

                      <details class="mt-3 rounded-lg border border-rose-200 bg-white p-3">
                        <summary class="cursor-pointer text-xs font-extrabold text-rose-800">
                          상세 정보 보기
                        </summary>
                        <div class="mt-3 grid gap-2 text-xs leading-5 text-slate-600">
                          <p class="m-0">
                            오류 코드 <strong class="font-black text-slate-900">{data.lastError.code}</strong>
                          </p>
                          <pre class="m-0 max-h-40 overflow-auto whitespace-pre-wrap break-words rounded-lg bg-slate-50 p-3 font-mono text-[11px] leading-5 text-slate-700">
                            {data.lastError.message}
                          </pre>
                        </div>
                      </details>
                    </div>
                  </div>
                </div>
              ) : null}

              {confirmingInstall ? (
                <div class="mt-5 flex flex-col gap-3 rounded-xl border border-amber-200 bg-amber-50 p-4 sm:flex-row sm:items-center sm:justify-between">
                  <div class="min-w-0">
                    <strong class="block text-sm font-black text-amber-900">
                      관리 소프트웨어를 지금 업데이트할까요?
                    </strong>
                    <span class="mt-1 block text-xs leading-5 text-amber-800">
                      설치 중 SmartSafeHub 웹 화면 연결이 잠시 끊길 수 있습니다.
                    </span>
                  </div>
                  <div class="flex shrink-0 gap-2">
                    <button
                      class="min-h-10 rounded-lg border border-slate-300 bg-white px-3 py-2 text-xs font-extrabold text-slate-700"
                      disabled={busy}
                      onClick={() => setConfirmingInstall(false)}
                      type="button"
                    >
                      취소
                    </button>
                    <button
                      class="min-h-10 rounded-lg bg-amber-700 px-3 py-2 text-xs font-extrabold text-white disabled:opacity-60"
                      disabled={busy}
                      onClick={() => {
                        setConfirmingInstall(false);
                        onInstall();
                      }}
                      type="button"
                    >
                      설치 시작
                    </button>
                  </div>
                </div>
              ) : null}
            </>
          ) : null}
        </div>

        {data ? (
          <div class="px-5 pb-5 sm:px-6 sm:pb-6">
            <h3 class="mb-3 text-sm font-black text-slate-950">현재 상태</h3>
            <dl class="grid overflow-hidden rounded-xl border border-slate-200 bg-slate-200 sm:grid-cols-2">
              <div class="bg-white p-4">
                <dt class="text-[11px] font-black uppercase tracking-[0.16em] text-slate-400">
                  Installed
                </dt>
                <dd class="mt-2 mb-0 ml-0 break-all text-sm font-black text-slate-950">
                  {currentPackage?.installedVersion || '미확인'}
                </dd>
              </div>
              <div class="bg-white p-4">
                <dt class="text-[11px] font-black uppercase tracking-[0.16em] text-slate-400">
                  Available
                </dt>
                <dd class={`mt-2 mb-0 ml-0 break-all text-sm font-black ${
                  currentPackage?.updateAvailable || updateCheckStale
                    ? 'text-amber-700'
                    : 'text-slate-950'
                }`}>
                  {!data.lastCheckAt || (repositoryCheckFailed && !currentPackage?.updateAvailable)
                    ? '미확인'
                    : currentPackage?.updateAvailable && currentPackage.availableVersion
                      ? currentPackage.availableVersion
                      : updateCheckStale
                        ? '확인 필요'
                        : '최신 버전'}
                </dd>
              </div>
              <div class="bg-white p-4">
                <dt class="text-[11px] font-black uppercase tracking-[0.16em] text-slate-400">
                  Last check
                </dt>
                <dd class="mt-2 mb-0 ml-0 text-sm font-black text-slate-950">
                  {formatTimestamp(data.lastCheckAt)}
                </dd>
              </div>
              <div class="bg-white p-4">
                <dt class="text-[11px] font-black uppercase tracking-[0.16em] text-slate-400">
                  Auto install
                </dt>
                <dd class="mt-2 mb-0 ml-0 text-sm font-black text-slate-950">
                  {data.settings.autoInstall ? `켜짐 · ${data.settings.autoInstallTime}` : '꺼짐'}
                </dd>
              </div>
            </dl>
          </div>
        ) : null}
        {data && data.updateCount === 0 && data.lastCheckAt ? (
          updateCheckStale ? (
            <section
              class="mx-5 mb-5 rounded-xl border border-amber-200 bg-amber-50 p-4 sm:mx-6 sm:mb-6 sm:p-5"
              data-section="software-update-result"
            >
              <div class="flex gap-3">
                <span class="grid size-10 shrink-0 place-items-center rounded-xl bg-white text-amber-700 ring-1 ring-inset ring-amber-200">
                  <AlertIcon class="size-5" />
                </span>
                <div>
                  <h3 class="m-0 text-base font-black text-amber-950">업데이트 확인이 지연되고 있습니다.</h3>
                  <p class="mt-1 mb-0 text-sm leading-6 text-amber-800">
                    마지막 확인은 {formatTimestamp(data.lastCheckAt)}에 완료되었습니다. 자동 확인 상태를 점검하거나 업데이트 확인을 실행해 주세요.
                  </p>
                </div>
              </div>
            </section>
          ) : (
            <section
              class="mx-5 mb-5 rounded-xl border border-emerald-200 bg-emerald-50 p-4 sm:mx-6 sm:mb-6 sm:p-5"
              data-section="software-update-result"
            >
              <div class="flex gap-3">
                <span class="grid size-10 shrink-0 place-items-center rounded-xl bg-white text-emerald-700">
                  <CheckCircleIcon class="size-5" />
                </span>
                <div>
                  <h3 class="m-0 text-base font-black text-emerald-950">최신 버전을 사용 중입니다.</h3>
                  <p class="mt-1 mb-0 text-sm leading-6 text-emerald-800">
                    마지막 확인은 {formatTimestamp(data.lastCheckAt)}에 완료되었습니다.
                  </p>
                </div>
              </div>
            </section>
          )
        ) : null}

        {data && data.updateCount === 0 && !data.lastCheckAt ? (
          <section
            class="mx-5 mb-5 rounded-xl border border-slate-200 bg-slate-50 p-4 sm:mx-6 sm:mb-6 sm:p-5"
            data-section="software-update-result"
          >
            <div class="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
              <div class="flex min-w-0 gap-3">
                <span class="grid size-10 shrink-0 place-items-center rounded-xl bg-white text-slate-500 ring-1 ring-inset ring-slate-200">
                  <ReloadIcon class="size-5" />
                </span>
                <div class="min-w-0">
                  <h3 class="m-0 text-base font-black text-slate-900">업데이트 상태를 아직 확인하지 않았습니다.</h3>
                  <p class="mt-1 mb-0 text-sm leading-6 text-slate-600">
                    업데이트 확인을 실행하면 현재 설치 버전과 사용 가능한 최신 버전을 확인합니다.
                  </p>
                </div>
              </div>
              <button
                class="inline-flex min-h-10 shrink-0 items-center justify-center gap-2 rounded-xl border border-slate-300 bg-white px-4 py-2 text-sm font-extrabold text-slate-800 transition hover:border-teal-300 hover:text-teal-700 disabled:cursor-wait disabled:opacity-60"
                disabled={busy}
                onClick={onCheck}
                type="button"
              >
                <ReloadIcon class="size-4" />
                지금 확인
              </button>
            </div>
          </section>
        ) : null}
      </section>

      {data ? (
        <>
          <section
            class="min-w-0 border-t border-slate-200 p-5 sm:p-6 xl:col-start-2 xl:row-start-1 xl:row-span-2 xl:self-stretch xl:border-t-0 xl:border-l"
            data-section="software-update-settings"
          >
            <div class="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
              <div class="flex min-w-0 gap-4">
                <span class="grid size-11 shrink-0 place-items-center rounded-xl bg-slate-100 text-slate-600">
                  <SettingsIcon class="size-5" />
                </span>
                <div class="min-w-0">
                  <p class="m-0 text-xs font-extrabold uppercase tracking-[0.16em] text-slate-500">
                    Settings
                  </p>
                  <h3 class="mt-2 mb-0 text-lg font-black text-slate-950">자동 업데이트</h3>
                  <p class="mt-2 mb-0 max-w-3xl text-sm leading-6 text-slate-500">
                    관리 소프트웨어의 자동 확인과 자동 설치를 설정합니다.
                  </p>
                </div>
              </div>
              {settingsDirty ? (
                <span
                  aria-live="polite"
                  class="inline-flex shrink-0 self-start items-center gap-1.5 rounded-full border border-amber-200 bg-amber-50 px-2.5 py-1 text-xs font-extrabold text-amber-800"
                  role="status"
                >
                  <AlertIcon aria-hidden="true" class="size-3.5 shrink-0" />
                  저장되지 않음
                </span>
              ) : null}
            </div>

            <div class="ssh-software-settings-grid mt-4">
              <div class="ssh-software-settings-channel rounded-xl border border-slate-200 p-4 sm:p-5">
                <div class="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
                  <div class="min-w-0">
                    <strong class="block text-sm font-black text-slate-950">업데이트 채널</strong>
                    <span class="mt-1 block text-xs leading-5 text-slate-500">
                      현재 관리 소프트웨어 업데이트를 확인하는 배포 채널입니다.
                    </span>
                  </div>
                  <span
                    class={`inline-flex min-h-9 shrink-0 items-center justify-center rounded-full px-3 py-1.5 text-xs font-extrabold ring-1 ring-inset ${updateChannelClass(data.settings.channel)}`}
                    title="현재 업데이트 확인 채널"
                  >
                    {updateChannelLabel(data.settings.channel)}
                  </span>
                </div>
              </div>

              <div class="min-w-0 overflow-hidden rounded-xl border border-slate-200 p-4 sm:p-5">
                <div class="flex min-w-0 items-start justify-between gap-4">
                  <div class="min-w-0">
                    <strong class="block text-sm font-black text-slate-950">자동으로 업데이트 확인</strong>
                    <span class="mt-1 block text-xs leading-5 text-slate-500">
                      선택한 주기에 새 관리 소프트웨어 버전을 확인합니다.
                    </span>
                  </div>
                  <SettingSwitch
                    checked={checkEnabled}
                    label="자동 업데이트 확인"
                    onChange={(checked) => {
                      setCheckEnabled(checked);
                      setSettingsDirty(hasSettingsChanges({ checkEnabled: checked }));
                    }}
                  />
                </div>

                <div class="mt-4 block">
                  <span class="text-xs font-extrabold text-slate-700">확인 주기</span>
                  <CustomSelect
                    ariaLabel="업데이트 확인 주기"
                    className="mt-2"
                    disabled={!checkEnabled}
                    id="software-update-check-interval"
                    onChange={(nextValue) => {
                      const nextIntervalSeconds = Number(nextValue);
                      setCheckIntervalSeconds(nextIntervalSeconds);
                      setSettingsDirty(
                        hasSettingsChanges({ checkIntervalSeconds: nextIntervalSeconds }),
                      );
                    }}
                    options={INTERVAL_OPTIONS.map((option) => ({
                      value: String(option.value),
                      label: option.label,
                    }))}
                    value={String(checkIntervalSeconds)}
                    variant="emphasized"
                  />
                </div>
              </div>

              <div class="min-w-0 overflow-hidden rounded-xl border border-slate-200 p-4 sm:p-5">
                <div class="flex min-w-0 items-start justify-between gap-4">
                  <div class="min-w-0">
                    <strong class="block text-sm font-black text-slate-950">자동으로 업데이트 설치</strong>
                    <span class="mt-1 block text-xs leading-5 text-slate-500">
                      새 버전이 있으면 지정한 시각에 자동으로 설치합니다.
                    </span>
                  </div>
                  <SettingSwitch
                    checked={autoInstall}
                    label="자동 업데이트 설치"
                    onChange={(checked) => {
                      setAutoInstall(checked);
                      setSettingsDirty(hasSettingsChanges({ autoInstall: checked }));
                    }}
                  />
                </div>

                <div class="mt-4 min-w-0">
                  <span class="text-xs font-extrabold text-slate-700">설치 시각</span>
                  <TimeSelect
                    ariaLabel="자동 업데이트 설치 시각"
                    className="mt-2"
                    disabled={!autoInstall}
                    id="software-update-auto-install-time"
                    onChange={(nextAutoInstallTime) => {
                      setAutoInstallTime(nextAutoInstallTime);
                      setSettingsDirty(
                        hasSettingsChanges({ autoInstallTime: nextAutoInstallTime }),
                      );
                    }}
                    value={autoInstallTime}
                    variant="emphasized"
                  />
                </div>
              </div>
            </div>

            {autoInstall ? (
              <p class="mt-4 mb-0 rounded-xl bg-amber-50 px-4 py-3 text-xs font-bold leading-5 text-amber-800">
                자동 설치 중에는 SmartSafeHub 웹 화면 연결이 잠시 끊길 수 있습니다.
              </p>
            ) : null}

            <div class="mt-5 flex flex-col gap-3 border-t border-slate-100 pt-5 sm:flex-row sm:items-center sm:justify-between">
              <p class="m-0 text-xs leading-5 text-slate-500">
                마지막 설치: {formatTimestamp(data.lastInstallAt)}
              </p>
              <button
                class="inline-flex min-h-11 items-center justify-center rounded-xl bg-slate-900 px-4 py-2.5 text-sm font-extrabold text-white transition hover:bg-slate-800 disabled:cursor-not-allowed disabled:opacity-50"
                disabled={!settingsDirty || action === 'settings' || busy}
                onClick={() => void saveSettings()}
                type="button"
              >
                {action === 'settings' ? '저장 중' : '자동 업데이트 설정 저장'}
              </button>
            </div>
          </section>

          {data.updateCount > 0 ? (
            <section
              class="border-t border-slate-200 p-5 sm:p-6 xl:col-start-1 xl:row-start-2"
              data-section="software-update-release-notes"
            >
              <div class="flex flex-col gap-2 sm:flex-row sm:items-start sm:justify-between sm:gap-4">
                <div>
                  <p class="m-0 text-xs font-extrabold uppercase tracking-[0.16em] text-teal-700">
                    Release notes
                  </p>
                  <h3 class="mt-2 mb-0 text-lg font-black text-slate-950">업데이트 내용</h3>
                  <p class="mt-2 mb-0 text-sm leading-6 text-slate-500">
                    현재 설치된 버전 이후 포함되는 주요 변경 사항입니다.
                  </p>
                </div>
                {data.releaseNotes.length ? (
                  <span class="shrink-0 rounded-full bg-slate-100 px-3 py-1.5 text-xs font-extrabold text-slate-600">
                    {data.releaseNotes.length === 1
                      ? '1개 릴리즈'
                      : `${data.releaseNotes.length}개 릴리즈`}
                  </span>
                ) : null}
              </div>

              {data.releaseNotes.length ? (
                <div class="mt-5 grid gap-3">
                  {data.releaseNotes.map((releaseNote) => (
                    <article
                      class="rounded-xl border border-slate-200 bg-slate-50 p-4 sm:p-5"
                      key={releaseNote.version}
                    >
                      <div class="flex flex-col gap-1 sm:flex-row sm:items-center sm:justify-between sm:gap-4">
                        <strong class="break-all text-sm font-black text-slate-950">
                          {releaseNote.version}
                        </strong>
                        {releaseNote.date ? (
                          <span class="text-xs font-bold text-slate-500">
                            {releaseNote.date}
                          </span>
                        ) : null}
                      </div>

                      {releaseNote.summary ? (
                        <p class="mt-3 mb-0 text-sm leading-6 text-slate-700">
                          {releaseNote.summary}
                        </p>
                      ) : null}

                      {releaseNote.sections.length ? (
                        <details
                          class="mt-4 rounded-lg border border-slate-200 bg-white p-3"
                          open={data.releaseNotes.length === 1}
                        >
                          <summary class="cursor-pointer text-xs font-extrabold text-slate-800">
                            자세한 변경 사항
                          </summary>
                          <div class="mt-3 grid gap-4">
                            {releaseNote.sections.map((section) => (
                              <section key={`${releaseNote.version}-${section.title}`}>
                                <h4 class="m-0 text-xs font-extrabold text-slate-700">
                                  {section.title}
                                </h4>
                                <ul class="mt-2 mb-0 space-y-1.5 pl-5 text-xs leading-5 text-slate-600">
                                  {section.items.map((item, index) => (
                                    <li key={`${releaseNote.version}-${section.title}-${index}`}>
                                      {item}
                                    </li>
                                  ))}
                                </ul>
                              </section>
                            ))}
                          </div>
                        </details>
                      ) : null}
                    </article>
                  ))}

                  {!data.releaseNotesComplete ? (
                    <p class="m-0 rounded-xl bg-amber-50 px-4 py-3 text-xs font-bold leading-5 text-amber-800">
                      일부 릴리즈 노트를 불러오지 못했습니다. 업데이트 확인과 설치는 계속 사용할 수 있습니다.
                    </p>
                  ) : null}
                </div>
              ) : (
                <p class="mt-4 mb-0 rounded-xl bg-slate-50 px-4 py-3 text-sm text-slate-500">
                  릴리즈 노트를 불러오지 못했습니다. 업데이트 확인과 설치는 계속 사용할 수 있습니다.
                </p>
              )}
            </section>
          ) : null}

        </>
      ) : null}
    </article>
  );
}
