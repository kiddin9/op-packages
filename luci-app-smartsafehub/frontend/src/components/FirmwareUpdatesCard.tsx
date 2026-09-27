import { useEffect, useRef, useState } from 'preact/hooks';

import type { FirmwareAction } from '../hooks/useFirmwareUpdates';
import type { FirmwareStatus } from '../types/firmware';
import {
  AlertIcon,
  CheckCircleIcon,
  ClockIcon,
  DownloadIcon,
  ReloadIcon,
  RouterIcon,
  UpdateIcon,
} from './Icons';

interface FirmwareUpdatesCardProps {
  action: FirmwareAction;
  actionError: string | null;
  data: FirmwareStatus | null;
  error: string | null;
  loading: boolean;
  message: string | null;
  reconnecting: boolean;
  uploadProgress: number | null;
  onCheck: () => void;
  onDiscard: () => Promise<boolean>;
  onDismissFeedback: () => void;
  onInstall: (keepSettings: boolean) => Promise<boolean>;
  onPrepare: () => void;
  onRetry: () => void;
  onUpload: (file: File) => Promise<boolean>;
}

function formatBytes(value: number | null | undefined): string {
  if (!value || value <= 0) {
    return '미확인';
  }
  if (value >= 1024 * 1024) {
    return `${(value / (1024 * 1024)).toFixed(1)} MB`;
  }
  return `${(value / 1024).toFixed(1)} KB`;
}

function formatTimestamp(value: number | null): string {
  if (!value) {
    return '아직 없음';
  }
  return new Date(value * 1000).toLocaleString('ko-KR', {
    dateStyle: 'medium',
    timeStyle: 'short',
  });
}

function phaseLabel(data: FirmwareStatus): string {
  switch (data.phase) {
    case 'checking':
      return '확인 중';
    case 'downloading':
      return '다운로드 중';
    case 'verifying':
      return '검증 중';
    case 'ready':
      return '설치 준비 완료';
    case 'flashing':
      return '설치 중';
    case 'error':
      return '확인 필요';
    default:
      return data.updateAvailable ? '업데이트 가능' : data.lastCheckAt ? '최신 상태' : '확인 전';
  }
}

function phaseClass(data: FirmwareStatus): string {
  if (data.phase === 'error') {
    return 'bg-rose-50 text-rose-700 ring-rose-200';
  }
  if (
    data.phase === 'checking' ||
    data.phase === 'downloading' ||
    data.phase === 'verifying' ||
    data.phase === 'flashing'
  ) {
    return 'bg-sky-50 text-sky-700 ring-sky-200';
  }
  if (data.phase === 'ready' || data.updateAvailable) {
    return 'bg-amber-50 text-amber-800 ring-amber-200';
  }
  if (!data.lastCheckAt) {
    return 'bg-slate-100 text-slate-600 ring-slate-200';
  }
  return 'bg-emerald-50 text-emerald-700 ring-emerald-200';
}

function phaseIcon(data: FirmwareStatus) {
  if (
    data.phase === 'checking' ||
    data.phase === 'downloading' ||
    data.phase === 'verifying' ||
    data.phase === 'flashing'
  ) {
    return <ReloadIcon class="size-3.5 animate-spin" />;
  }
  if (data.phase === 'error') {
    return <AlertIcon class="size-3.5" />;
  }
  if (data.phase === 'ready' || data.updateAvailable) {
    return <DownloadIcon class="size-3.5" />;
  }
  if (!data.lastCheckAt) {
    return <ClockIcon class="size-3.5" />;
  }
  return <CheckCircleIcon class="size-3.5" />;
}

function KeepSettingsSwitch({
  checked,
  disabled,
  onChange,
}: {
  checked: boolean;
  disabled: boolean;
  onChange: (value: boolean) => void;
}) {
  return (
    <button
      aria-checked={checked}
      aria-label="현재 설정 유지"
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

export function FirmwareUpdatesCard({
  action,
  actionError,
  data,
  error,
  loading,
  message,
  reconnecting,
  uploadProgress,
  onCheck,
  onDiscard,
  onDismissFeedback,
  onInstall,
  onPrepare,
  onRetry,
  onUpload,
}: FirmwareUpdatesCardProps) {
  const fileInput = useRef<HTMLInputElement>(null);
  const [selectedFile, setSelectedFile] = useState<File | null>(null);
  const [keepSettings, setKeepSettings] = useState(true);
  const [confirmingInstall, setConfirmingInstall] = useState(false);

  useEffect(() => {
    if (data?.prepared) {
      setKeepSettings(data.prepared.allowBackup);
    }
  }, [data?.prepared]);

  const busy =
    action !== null ||
    data?.phase === 'checking' ||
    data?.phase === 'downloading' ||
    data?.phase === 'verifying' ||
    data?.phase === 'flashing';
  const prepared = data?.phase === 'ready' ? data.prepared : null;
  const checking = action === 'check' || data?.phase === 'checking';
  const preparing = action === 'prepare' || data?.phase === 'downloading' || data?.phase === 'verifying';
  const uploading = action === 'upload' || action === 'validate-upload';

  const uploadSelected = async () => {
    if (!selectedFile) {
      return;
    }
    const accepted = await onUpload(selectedFile);
    if (accepted) {
      setSelectedFile(null);
      if (fileInput.current) {
        fileInput.current.value = '';
      }
    }
  };

  return (
    <article
      class="min-w-0 overflow-hidden rounded-2xl border border-slate-200 bg-white shadow-sm shadow-slate-900/5"
      data-component="firmware-update-card"
    >
      <div class="p-5 sm:p-6">
        <div class="flex flex-col gap-5 lg:flex-row lg:items-start lg:justify-between">
          <div class="flex min-w-0 gap-4">
            <span class="grid size-12 shrink-0 place-items-center rounded-2xl bg-sky-50 text-sky-700">
              <RouterIcon class="size-6" />
            </span>
            <div class="min-w-0">
              <p class="m-0 text-xs font-extrabold uppercase tracking-[0.16em] text-sky-700">
                Firmware update
              </p>
              <h2 class="mt-2 mb-0 text-xl font-black text-slate-950 sm:text-2xl">펌웨어 업데이트</h2>
              <p class="mt-2 mb-0 text-sm leading-6 text-slate-500 lg:whitespace-nowrap">
                시스템 펌웨어를 확인하고 설치합니다. 온라인·수동 설치는 안전성 검증 후 진행됩니다.
              </p>
            </div>
          </div>

          {data ? (
            <div class="flex shrink-0 flex-col gap-2 sm:flex-row lg:justify-end">
              <span
                class={`inline-flex min-h-11 items-center justify-center gap-1.5 rounded-xl px-3 py-2 text-xs font-extrabold ring-1 ring-inset ${phaseClass(data)}`}
              >
                {phaseIcon(data)}
                {phaseLabel(data)}
              </span>
              <button
                class="inline-flex min-h-11 items-center justify-center gap-2 rounded-xl border border-slate-300 bg-white px-4 py-2.5 text-sm font-extrabold text-slate-800 transition hover:bg-slate-50 disabled:cursor-wait disabled:opacity-60"
                disabled={busy || prepared !== null}
                onClick={onCheck}
                type="button"
              >
                <ReloadIcon class={`size-4 ${checking ? 'animate-spin' : ''}`} />
                {checking ? '확인 중...' : '펌웨어 확인'}
              </button>

              {data.updateAvailable && !prepared ? (
                <button
                  class="inline-flex min-h-11 items-center justify-center gap-2 rounded-xl bg-sky-700 px-4 py-2.5 text-sm font-extrabold text-white transition hover:bg-sky-800 disabled:cursor-wait disabled:opacity-60"
                  disabled={busy}
                  onClick={onPrepare}
                  type="button"
                >
                  {preparing ? (
                    <ReloadIcon class="size-4 animate-spin" />
                  ) : (
                    <DownloadIcon class="size-4" />
                  )}
                  {preparing ? '준비 중...' : '다운로드 및 검증'}
                </button>
              ) : null}
            </div>
          ) : null}
        </div>

        {(actionError || message) ? (
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
        ) : null}

        {reconnecting || data?.phase === 'flashing' ? (
          <div class="mt-5 rounded-xl border border-amber-200 bg-amber-50 p-4 sm:p-5" role="status">
            <div class="flex gap-3">
              <span class="grid size-10 shrink-0 place-items-center rounded-xl bg-white text-amber-700 ring-1 ring-inset ring-amber-200">
                <ReloadIcon class="size-5 animate-spin" />
              </span>
              <div>
                <strong class="block text-sm font-black text-amber-950">펌웨어를 설치하고 재부팅하고 있습니다.</strong>
                <p class="mt-1 mb-0 text-sm leading-6 text-amber-800">
                  전원을 끄지 마세요. 현재 주소에서 공유기가 다시 응답하면 SmartSafeHub가 자동으로 새로고침됩니다.
                </p>
              </div>
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
            <ReloadIcon class="size-4 animate-spin" />
            펌웨어 상태를 확인하고 있습니다.
          </div>
        ) : data ? (
          <>
            {data.lastError ? (
              <div class="mt-5 rounded-xl border border-rose-200 bg-rose-50 p-4 sm:p-5">
                <div class="flex gap-3">
                  <span class="grid size-10 shrink-0 place-items-center rounded-xl bg-white text-rose-700 ring-1 ring-inset ring-rose-200">
                    <AlertIcon class="size-5" />
                  </span>
                  <div class="min-w-0 flex-1">
                    <strong class="block text-sm font-black text-rose-950">펌웨어 작업을 완료하지 못했습니다.</strong>
                    <p class="mt-1 mb-0 text-sm leading-6 text-rose-800">{data.lastError.message}</p>
                    <details class="mt-3 rounded-lg border border-rose-200 bg-white p-3">
                      <summary class="cursor-pointer text-xs font-extrabold text-rose-800">상세 정보 보기</summary>
                      <p class="mt-2 mb-0 break-all font-mono text-[11px] text-slate-600">{data.lastError.code}</p>
                    </details>
                  </div>
                </div>
              </div>
            ) : null}

            {!data.current.metadataAvailable ? (
              <div class="mt-5 rounded-xl border border-amber-200 bg-amber-50 px-4 py-3 text-xs leading-5 text-amber-900">
                <strong class="block font-extrabold">현재 펌웨어의 버전 정보를 완전히 확인할 수 없습니다.</strong>
                <span class="mt-1 block text-amber-800">
                  새 펌웨어를 설치하면 이후부터 정확한 설치 버전을 자동으로 확인할 수 있습니다.
                </span>
                <details class="mt-2">
                  <summary class="cursor-pointer font-extrabold text-amber-800">기술 상세 보기</summary>
                  <p class="mt-2 mb-0 break-all font-mono text-[11px] leading-5 text-amber-800">
                    SmartSafeHub build ID metadata is missing. Future images should include /usr/share/smartsafehub/firmware.json.
                  </p>
                </details>
              </div>
            ) : null}

            <dl class="mt-5 grid overflow-hidden rounded-xl border border-slate-200 bg-slate-200 sm:grid-cols-2 xl:grid-cols-4">
              <div class="bg-white p-4">
                <dt class="text-[11px] font-black uppercase tracking-[0.16em] text-slate-400">Device</dt>
                <dd class="mt-2 mb-0 ml-0 break-all text-sm font-black text-slate-950">
                  {data.current.deviceCode || data.current.boardName || '미확인'}
                </dd>
              </div>
              <div class="bg-white p-4">
                <dt class="text-[11px] font-black uppercase tracking-[0.16em] text-slate-400">Current version</dt>
                <dd class="mt-2 mb-0 ml-0 break-all text-sm font-black text-slate-950">
                  {data.current.releaseVersion || '미확인'}
                </dd>
                {data.current.buildId ? (
                  <span class="mt-1 block break-all text-[11px] leading-5 text-slate-400">
                    빌드 ID {data.current.buildId}
                  </span>
                ) : data.current.openwrtVersion ? (
                  <span class="mt-1 block text-[11px] leading-5 text-slate-400">
                    OpenWrt {data.current.openwrtVersion}
                  </span>
                ) : null}
              </div>
              <div class="bg-white p-4">
                <dt class="text-[11px] font-black uppercase tracking-[0.16em] text-slate-400">Available version</dt>
                <dd class={`mt-2 mb-0 ml-0 break-all text-sm font-black ${data.updateAvailable ? 'text-amber-700' : 'text-slate-950'}`}>
                  {!data.lastCheckAt
                    ? '미확인'
                    : data.release?.version
                      ? `${data.release.version}${data.updateAvailable ? '' : ' · 최신'}`
                      : data.updateAvailable
                        ? '새 펌웨어'
                        : '최신 버전'}
                </dd>
              </div>
              <div class="bg-white p-4">
                <dt class="text-[11px] font-black uppercase tracking-[0.16em] text-slate-400">Last check</dt>
                <dd class="mt-2 mb-0 ml-0 text-sm font-black text-slate-950">{formatTimestamp(data.lastCheckAt)}</dd>
              </div>
            </dl>
          </>
        ) : null}

        {data?.updateAvailable && data.release ? (
          <section class="mt-5 rounded-xl border border-sky-200 bg-sky-50/60 p-4 sm:p-5" data-section="available-firmware">
            <div class="flex flex-col gap-2 sm:flex-row sm:items-start sm:justify-between sm:gap-4">
              <div>
                <p class="m-0 text-xs font-extrabold uppercase tracking-[0.16em] text-sky-700">Available firmware</p>
                <h3 class="mt-2 mb-0 text-lg font-black text-slate-950">새 펌웨어가 있습니다.</h3>
                <p class="mt-2 mb-0 text-sm leading-6 text-slate-600">
                  펌웨어 {data.release.version || '미확인'} · OpenWrt {data.release.openwrtVersion || '미확인'} · {formatBytes(data.release.sysupgrade.sizeBytes)} · {(data.release.channel || data.settings.channel) === 'beta' ? 'Beta' : 'Stable'}
                </p>
              </div>
              <span class="shrink-0 rounded-full bg-white px-3 py-1.5 text-xs font-extrabold text-sky-700 ring-1 ring-inset ring-sky-200">
                {data.release.version || 'Latest'}
              </span>
            </div>
            {data.release.releaseNotes.length ? (
              <ul class="mt-4 mb-0 space-y-2 rounded-xl bg-white p-4 pl-9 text-sm leading-6 text-slate-700 ring-1 ring-inset ring-sky-100">
                {data.release.releaseNotes.map((note, index) => (
                  <li key={`${index}-${note}`}>{note}</li>
                ))}
              </ul>
            ) : null}
          </section>
        ) : null}

        {prepared ? (
          <section class="mt-5 rounded-xl border border-amber-200 bg-amber-50 p-4 sm:p-5" data-section="prepared-firmware">
            <div class="flex gap-4">
              <span class="grid size-11 shrink-0 place-items-center rounded-xl bg-white text-amber-700 ring-1 ring-inset ring-amber-200">
                <CheckCircleIcon class="size-5" />
              </span>
              <div class="min-w-0 flex-1">
                <p class="m-0 text-xs font-extrabold uppercase tracking-[0.16em] text-amber-700">Verified image</p>
                <h3 class="mt-2 mb-0 text-lg font-black text-amber-950">설치할 펌웨어가 준비되었습니다.</h3>
                <p class="mt-2 mb-0 break-all text-sm leading-6 text-amber-900">
                  {prepared.filename || 'firmware.bin'} · {formatBytes(prepared.sizeBytes)}
                </p>
                {prepared.sha256 ? (
                  <p class="mt-2 mb-0 break-all font-mono text-[11px] leading-5 text-amber-800">SHA-256 {prepared.sha256}</p>
                ) : null}

                <div class="mt-5 flex items-start justify-between gap-4 rounded-xl border border-amber-200 bg-white p-4">
                  <div>
                    <strong class="block text-sm font-black text-slate-950">현재 설정 유지</strong>
                    <span class="mt-1 block text-xs leading-5 text-slate-500">
                      Wi-Fi, SafeShield, SmartSafeHub 설정을 유지합니다.
                    </span>
                    {!prepared.allowBackup ? (
                      <span class="mt-2 block text-xs font-bold text-rose-700">이 이미지는 설정 유지 업그레이드를 지원하지 않습니다.</span>
                    ) : null}
                  </div>
                  <KeepSettingsSwitch
                    checked={keepSettings}
                    disabled={!prepared.allowBackup}
                    onChange={setKeepSettings}
                  />
                </div>

                {confirmingInstall ? (
                  <div class="mt-4 rounded-xl border border-rose-200 bg-rose-50 p-4">
                    <strong class="block text-sm font-black text-rose-950">펌웨어 설치를 시작할까요?</strong>
                    <p class="mt-1 mb-0 text-xs leading-5 text-rose-800">
                      설치 중 전원을 끄면 장치가 복구 불가능한 상태가 될 수 있습니다. 이미지 검증은 설치 직전에 다시 수행됩니다.
                    </p>
                    <div class="mt-4 flex flex-wrap justify-end gap-2">
                      <button
                        class="min-h-10 rounded-lg border border-slate-300 bg-white px-3 py-2 text-xs font-extrabold text-slate-700"
                        onClick={() => setConfirmingInstall(false)}
                        type="button"
                      >
                        취소
                      </button>
                      <button
                        class="min-h-10 rounded-lg bg-rose-700 px-3 py-2 text-xs font-extrabold text-white"
                        onClick={() => {
                          setConfirmingInstall(false);
                          void onInstall(keepSettings);
                        }}
                        type="button"
                      >
                        설치 시작
                      </button>
                    </div>
                  </div>
                ) : (
                  <div class="mt-4 flex flex-wrap justify-end gap-2">
                    <button
                      class="min-h-10 rounded-lg border border-slate-300 bg-white px-3 py-2 text-xs font-extrabold text-slate-700"
                      disabled={action === 'discard'}
                      onClick={() => void onDiscard()}
                      type="button"
                    >
                      파일 삭제
                    </button>
                    <button
                      class="inline-flex min-h-10 items-center gap-2 rounded-lg bg-rose-700 px-4 py-2 text-xs font-extrabold text-white"
                      onClick={() => setConfirmingInstall(true)}
                      type="button"
                    >
                      <UpdateIcon class="size-4" />
                      펌웨어 설치
                    </button>
                  </div>
                )}
              </div>
            </div>
          </section>
        ) : null}
      </div>

      <details
        class="group mx-5 mb-5 rounded-xl border border-slate-200 bg-slate-50/70 sm:mx-6 sm:mb-6"
        data-layout="firmware-card-subsection"
        data-section="manual-firmware"
      >
        <summary class="flex cursor-pointer list-none items-center justify-between gap-4 px-4 py-4 sm:px-5 [&::-webkit-details-marker]:hidden">
          <div class="flex min-w-0 items-center gap-3">
            <span class="grid size-10 shrink-0 place-items-center rounded-xl bg-white text-slate-600 ring-1 ring-inset ring-slate-200">
              <DownloadIcon class="size-5 rotate-180" />
            </span>
            <div class="min-w-0">
              <strong class="block text-sm font-black text-slate-950">수동 펌웨어 설치</strong>
              <span class="mt-1 block text-xs leading-5 text-slate-500">
                펌웨어 파일(.bin)을 직접 업로드하여 검증한 뒤 설치합니다.
              </span>
            </div>
          </div>
          <span class="shrink-0 rounded-full bg-white px-3 py-1.5 text-[11px] font-extrabold text-slate-600 ring-1 ring-inset ring-slate-200 group-open:hidden">
            열기
          </span>
          <span class="hidden shrink-0 rounded-full bg-white px-3 py-1.5 text-[11px] font-extrabold text-slate-600 ring-1 ring-inset ring-slate-200 group-open:inline-flex">
            닫기
          </span>
        </summary>

        <div class="border-t border-slate-200 px-5 pb-5 pt-3 sm:px-6">
          <p class="mt-0 mb-4 text-xs leading-5 text-slate-500 lg:whitespace-nowrap">
            이 장치에 맞는 Sysupgrade 이미지(.bin)만 사용하세요. 업로드한 파일은 이미지 검증과 `sysupgrade --test`를 모두 통과해야 설치할 수 있으며 강제 설치는 제공하지 않습니다.
          </p>
          <div
            class="rounded-xl border border-slate-200 bg-white p-4 sm:p-5"
            data-layout="firmware-file-picker"
          >
            <input
              accept=".bin,application/octet-stream"
              aria-label="펌웨어 파일 선택"
              class="sr-only"
              disabled={busy || prepared !== null}
              onChange={(event) => setSelectedFile(event.currentTarget.files?.[0] ?? null)}
              ref={fileInput}
              type="file"
            />

            <div class="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
              <div class="flex min-w-0 items-center gap-3">
                <span class="grid size-10 shrink-0 place-items-center rounded-xl bg-slate-50 text-slate-500 ring-1 ring-inset ring-slate-200">
                  <DownloadIcon class="size-5 rotate-180" />
                </span>
                <div class="min-w-0">
                  <strong class="block truncate text-sm font-black text-slate-900">
                    {selectedFile ? selectedFile.name : '펌웨어 파일을 선택하세요'}
                  </strong>
                  <span class="mt-1 block text-xs leading-5 text-slate-500">
                    {selectedFile
                      ? `${formatBytes(selectedFile.size)} · Sysupgrade 이미지 (.bin)`
                      : '이 장치에 맞는 Sysupgrade 이미지 (.bin)를 선택합니다.'}
                  </span>
                </div>
              </div>

              <div class="flex shrink-0 flex-wrap gap-2 sm:justify-end">
                <button
                  class="inline-flex min-h-10 items-center justify-center rounded-lg border border-slate-300 bg-white px-3.5 py-2 text-xs font-extrabold text-slate-700 transition hover:bg-slate-50 disabled:cursor-not-allowed disabled:opacity-50"
                  disabled={busy || prepared !== null}
                  onClick={() => fileInput.current?.click()}
                  type="button"
                >
                  {selectedFile ? '다른 파일 선택' : '파일 선택'}
                </button>
                <button
                  class="inline-flex min-h-10 items-center justify-center gap-2 rounded-lg bg-slate-900 px-3.5 py-2 text-xs font-extrabold text-white transition hover:bg-slate-800 disabled:cursor-not-allowed disabled:opacity-50"
                  disabled={!selectedFile || busy || prepared !== null}
                  onClick={() => void uploadSelected()}
                  type="button"
                >
                  {uploading ? <ReloadIcon class="size-4 animate-spin" /> : <DownloadIcon class="size-4 rotate-180" />}
                  {uploading ? '처리 중...' : '업로드 및 검증'}
                </button>
              </div>
            </div>

            {uploadProgress !== null ? (
              <div class="mt-4 border-t border-slate-100 pt-4">
                <div class="mb-2 flex items-center justify-between gap-3 text-xs font-bold text-slate-600">
                  <span>업로드 중</span>
                  <span>{uploadProgress}%</span>
                </div>
                <div class="h-2 overflow-hidden rounded-full bg-slate-200">
                  <div
                    class="h-full rounded-full bg-sky-600 transition-[width]"
                    style={{ width: `${Math.max(0, Math.min(100, uploadProgress))}%` }}
                  />
                </div>
              </div>
            ) : null}
          </div>
        </div>
      </details>
    </article>
  );
}
