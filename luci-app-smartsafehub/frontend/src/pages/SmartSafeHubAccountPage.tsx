import { useEffect, useState } from 'preact/hooks';

import { formatRelativeTime } from '../app/format';
import { CheckCircleIcon, ClockIcon, CopyIcon, KeyIcon, ReloadIcon } from '../components/Icons';
import { ErrorPanel, LoadingPanel } from '../components/StatePanels';
import type { DeviceRegistrationStatus } from '../api/smartsafehub';

const DEVICE_CONSOLE_URL = 'https://www.smartsafehub.com/dashboard/devices/';

async function copyTextToClipboard(value: string): Promise<void> {
  if (navigator.clipboard?.writeText) {
    try {
      await navigator.clipboard.writeText(value);
      return;
    }
    catch {
      // Local router pages can run outside a secure context.
    }
  }

  const textarea = document.createElement('textarea');
  textarea.value = value;
  textarea.setAttribute('readonly', '');
  textarea.style.position = 'fixed';
  textarea.style.inset = '0 auto auto -9999px';
  textarea.style.opacity = '0';
  document.body.appendChild(textarea);
  textarea.select();
  textarea.setSelectionRange(0, value.length);
  const copied = document.execCommand('copy');
  textarea.remove();
  if (!copied) throw new Error('clipboard_copy_failed');
}

type AccountPlanTone = 'free' | 'pro' | 'ultimate' | 'paid';

function planLabel(plan: string | null): string {
  return (plan || 'free').toUpperCase();
}

function planTone(plan: string): AccountPlanTone {
  if (plan === 'FREE') return 'free';
  if (plan === 'PRO') return 'pro';
  if (plan === 'ULTIMATE') return 'ultimate';
  return 'paid';
}

function AccountPlanBadge({ plan }: { plan: string }) {
  const tone = planTone(plan);
  const paid = tone !== 'free';

  return (
    <span
      class="ssh-safeshield-plan-badge"
      data-compact="false"
      data-tier={tone}
      title={paid ? `${plan} 멤버십` : '무료 플랜'}
    >
      <span aria-hidden="true" class="ssh-safeshield-plan-badge-mark">
        {paid ? '✦' : '•'}
      </span>
      <span>{plan}</span>
    </span>
  );
}

function pairingExpired(status: DeviceRegistrationStatus): boolean {
  if (!status.pairingCode || !status.pairingExpiresAt) return false;
  const expiresAt = Date.parse(status.pairingExpiresAt);
  return Number.isFinite(expiresAt) && expiresAt <= Date.now();
}

interface SmartSafeHubAccountPageProps {
  data: DeviceRegistrationStatus | null;
  error: string | null;
  loading: boolean;
  pairingBusy: boolean;
  refreshing: boolean;
  syncError: string | null;
  onRequestPairing: () => Promise<DeviceRegistrationStatus | null>;
  onRetry: () => void;
}

export function SmartSafeHubAccountPage({
  data,
  error,
  loading,
  pairingBusy,
  refreshing,
  syncError,
  onRequestPairing,
  onRetry,
}: SmartSafeHubAccountPageProps) {
  const [pairingError, setPairingError] = useState<string | null>(null);
  const [pairingCopied, setPairingCopied] = useState(false);

  useEffect(() => {
    if (!pairingCopied) return;
    const timeout = window.setTimeout(() => setPairingCopied(false), 1800);
    return () => window.clearTimeout(timeout);
  }, [pairingCopied]);

  if (loading && !data) return <LoadingPanel />;
  if (error && !data) return <ErrorPanel message={error} onRetry={onRetry} />;

  const status = data;
  const connected = status?.accountRegistered === true;
  const currentPlan = planLabel(status?.plan ?? null);
  const expired = status ? pairingExpired(status) : false;
  const pairingCode = !connected && !expired ? status?.pairingCode : null;

  async function requestPairing(): Promise<void> {
    setPairingError(null);
    setPairingCopied(false);
    try {
      await onRequestPairing();
    }
    catch {
      setPairingError('계정 연결 코드를 발급하지 못했습니다. 잠시 후 다시 시도해 주세요.');
    }
  }

  async function copyPairingCode(): Promise<void> {
    if (!pairingCode) return;
    try {
      await copyTextToClipboard(pairingCode);
      setPairingError(null);
      setPairingCopied(true);
    }
    catch {
      setPairingCopied(false);
      setPairingError('연결 코드를 복사하지 못했습니다. 코드를 직접 선택해 복사해 주세요.');
    }
  }

  return (
    <div class="grid gap-5 xl:grid-cols-[minmax(0,1.2fr)_minmax(18rem,0.8fr)]">
      <section class="rounded-2xl border border-slate-200 bg-white p-5 shadow-sm shadow-slate-900/5 sm:p-6">
        <div class="flex items-start justify-between gap-4">
          <div>
            <p class="m-0 text-[0.68rem] font-black uppercase tracking-[0.16em] text-teal-700">Account connection</p>
            <h2 class="mt-2 mb-0 text-xl font-black tracking-tight text-slate-950">기기 계정 연결</h2>
            <p class="mt-2 mb-0 max-w-2xl text-sm leading-6 text-slate-500">
              계정에 연결하면 웹사이트에서 기기를 관리하고 Cloud 기능과 구독 권한을 사용할 수 있습니다.
            </p>
          </div>
          <span class="grid size-11 shrink-0 place-items-center rounded-xl bg-teal-50 text-teal-700">
            <KeyIcon class="size-5" />
          </span>
        </div>

        {connected ? (
          <div class="mt-6 rounded-2xl border border-emerald-200 bg-emerald-50 p-5">
            <div class="flex items-center gap-3">
              <span class="grid size-10 shrink-0 place-items-center rounded-full bg-emerald-100 text-emerald-700">
                <CheckCircleIcon class="size-5" />
              </span>
              <div>
                <p class="m-0 text-sm font-black text-emerald-900">SmartSafeHub 계정에 연결됨</p>
                <p class="mt-1 mb-0 text-sm leading-5 text-emerald-800">연결 코드는 더 이상 필요하지 않으며 새 코드도 발급하지 않습니다.</p>
              </div>
            </div>
            <a
              class="mt-5 inline-flex min-h-11 items-center justify-center rounded-xl border border-emerald-700 bg-emerald-700 px-4 py-2 text-sm font-extrabold text-white no-underline transition hover:bg-emerald-800 focus:outline-none focus-visible:ring-4 focus-visible:ring-emerald-100"
              href={DEVICE_CONSOLE_URL}
              rel="noopener noreferrer"
              target="_blank"
            >
              웹사이트에서 기기 관리
            </a>
            <p class="mt-3 mb-0 text-xs font-semibold leading-5 text-emerald-800">
              웹사이트에서 기기 등록을 해제하면 공유기도 다음 계정 상태 동기화에서 자동으로 연결 해제를 반영합니다.
            </p>
          </div>
        ) : (
          <div class="mt-6 rounded-2xl border border-slate-200 bg-slate-50 p-4 sm:p-5">
            <div>
              <div class="flex flex-wrap items-center justify-between gap-2">
                <p class="m-0 text-sm font-black text-slate-900">계정 연결 코드</p>
                <span class="inline-flex items-center gap-1.5 rounded-full border border-amber-200 bg-amber-50 px-2.5 py-1 text-[0.7rem] font-black text-amber-800">
                  <ClockIcon class="size-3.5" />
                  10분 동안 유효
                </span>
              </div>
              <p class="mt-1 mb-0 text-sm leading-6 text-slate-500">
                코드를 발급한 뒤 smartsafehub.com에 로그인하여 기기를 연결하세요.
              </p>
            </div>

            {pairingCode ? (
              <div class="mt-4 flex flex-col gap-3 rounded-2xl border border-teal-200 bg-teal-50 p-4 sm:flex-row sm:items-center sm:justify-between" role="group" aria-label="계정 연결 코드">
                <div class="min-w-0">
                  <span class="block text-[0.7rem] font-black text-teal-700">연결 코드</span>
                  <code class="mt-1 block select-all break-all font-mono text-2xl font-black tracking-[0.14em] text-slate-950">{pairingCode}</code>
                </div>
                <button
                  aria-label="계정 연결 코드 복사"
                  class="inline-flex min-h-11 shrink-0 items-center justify-center gap-2 rounded-xl border border-teal-300 bg-white px-4 text-sm font-black text-teal-800 transition hover:bg-teal-100 focus:outline-none focus-visible:ring-4 focus-visible:ring-teal-100"
                  onClick={() => void copyPairingCode()}
                  type="button"
                >
                  {pairingCopied ? <CheckCircleIcon class="size-4" /> : <CopyIcon class="size-4" />}
                  <span aria-live="polite">{pairingCopied ? '복사됨' : '복사'}</span>
                </button>
              </div>
            ) : expired ? (
              <p class="mt-4 mb-0 rounded-xl border border-amber-200 bg-amber-50 px-4 py-3 text-sm font-bold text-amber-800">
                이전 연결 코드가 만료되었습니다. 새 코드를 발급해 주세요.
              </p>
            ) : null}

            <button
              class="mt-4 inline-flex min-h-11 w-full items-center justify-center gap-2 rounded-xl border border-teal-700 bg-teal-700 px-4 py-2 text-sm font-black text-white transition hover:bg-teal-800 focus:outline-none focus-visible:ring-4 focus-visible:ring-teal-100 disabled:cursor-not-allowed disabled:opacity-50"
              disabled={pairingBusy}
              onClick={() => void requestPairing()}
              type="button"
            >
              {pairingBusy ? <ReloadIcon class="size-4 animate-spin" /> : null}
              {pairingBusy ? '발급 중…' : pairingCode ? '새 코드 발급' : '연결 코드 발급'}
            </button>
            {pairingError ? <p class="mt-3 mb-0 text-sm font-semibold text-red-700">{pairingError}</p> : null}
          </div>
        )}
      </section>

      <aside class="rounded-2xl border border-slate-200 bg-white p-5 shadow-sm shadow-slate-900/5 sm:p-6">
        <p class="m-0 text-[0.68rem] font-black uppercase tracking-[0.16em] text-slate-400">Device status</p>
        <h2 class="mt-2 mb-0 text-lg font-black tracking-tight text-slate-950">연결 상태</h2>
        <dl class="mt-5 mb-0 grid gap-4">
          <div class="flex items-center justify-between gap-4 border-b border-slate-100 pb-4">
            <dt class="text-sm font-bold text-slate-500">계정</dt>
            <dd class={`m-0 text-sm font-black ${connected ? 'text-emerald-700' : 'text-slate-700'}`}>{connected ? '연결됨' : '연결 필요'}</dd>
          </div>
          <div class="flex items-center justify-between gap-4 border-b border-slate-100 pb-4">
            <dt class="text-sm font-bold text-slate-500">요금제</dt>
            <dd class="m-0 flex min-w-0 flex-wrap items-center justify-end gap-2">
              <AccountPlanBadge plan={currentPlan} />
              {currentPlan === 'FREE' ? <span class="ssh-safeshield-plan-caption">기본 플랜</span> : null}
            </dd>
          </div>
          <div class="flex items-center justify-between gap-4">
            <dt class="text-sm font-bold text-slate-500">마지막 확인</dt>
            <dd class="m-0 text-sm font-black text-slate-700">{formatRelativeTime(status?.lastSuccessAt ?? 0)}</dd>
          </div>
        </dl>
        {refreshing ? <p class="mt-5 mb-0 text-xs font-bold text-teal-700">최신 상태를 확인하고 있습니다…</p> : null}
        {syncError ? (
          connected ? (
            <p class="mt-5 mb-0 text-xs font-semibold leading-5 text-slate-500">
              최신 상태 확인이 지연되고 있습니다. 마지막으로 확인된 연결 상태를 표시합니다.
            </p>
          ) : (
            <p class="mt-5 mb-0 rounded-xl border border-amber-200 bg-amber-50 px-3 py-2 text-xs font-bold leading-5 text-amber-800">
              {syncError} 로컬에 저장된 마지막 상태를 표시합니다.
            </p>
          )
        ) : null}
      </aside>
    </div>
  );
}
