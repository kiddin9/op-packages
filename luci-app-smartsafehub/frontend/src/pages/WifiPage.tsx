import type { JSX } from 'preact';
import { useEffect, useState } from 'preact/hooks';

import { CustomSelect } from '../components/CustomSelect';
import { AlertIcon, CheckCircleIcon, RouterIcon } from '../components/Icons';
import { ErrorPanel, LoadingPanel } from '../components/StatePanels';
import type { WifiFeedback } from '../hooks/useWifi';
import type {
  WifiNetworkSummary,
  WifiSecurityChoice,
  WifiSummary,
  WifiUpdateInput,
} from '../types/wifi';

interface WifiPageProps {
  data: WifiSummary | null;
  error: string | null;
  feedback: WifiFeedback;
  loading: boolean;
  updatingSection: string | null;
  onDismissFeedback: () => void;
  onRetry: () => void;
  onUpdate: (input: WifiUpdateInput) => Promise<boolean>;
}

const SECURITY_OPTIONS: ReadonlyArray<{
  value: Exclude<WifiSecurityChoice, 'keep'>;
  label: string;
}> = [
  { value: 'sae-mixed', label: 'WPA2/WPA3 혼합 (권장)' },
  { value: 'sae', label: 'WPA3-Personal' },
  { value: 'psk2', label: 'WPA2-Personal' },
  { value: 'none', label: '암호화 없음' },
];

function securityLabel(network: WifiNetworkSummary): string {
  switch (network.security) {
    case 'sae-mixed':
      return 'WPA2/WPA3 혼합';
    case 'sae':
      return 'WPA3-Personal';
    case 'psk2':
      return 'WPA2-Personal';
    case 'none':
      return '암호화 없음';
    default:
      return `고급 설정 (${network.securityRaw})`;
  }
}

function isValidPassword(password: string): boolean {
  return (
    (password.length >= 8 && password.length <= 63) ||
    /^[0-9a-fA-F]{64}$/.test(password)
  );
}

function WifiNetworkCard({
  network,
  busy,
  saving,
  onUpdate,
}: {
  network: WifiNetworkSummary;
  busy: boolean;
  saving: boolean;
  onUpdate: (input: WifiUpdateInput) => Promise<boolean>;
}) {
  const [ssid, setSsid] = useState(network.ssid);
  const [enabled, setEnabled] = useState(network.enabled);
  const [security, setSecurity] = useState<WifiSecurityChoice>(
    network.security === 'custom' ? 'keep' : network.security,
  );
  const [password, setPassword] = useState('');
  const [validationError, setValidationError] = useState<string | null>(null);

  useEffect(() => {
    setSsid(network.ssid);
    setEnabled(network.enabled);
    setSecurity(network.security === 'custom' ? 'keep' : network.security);
    setPassword('');
    setValidationError(null);
  }, [network]);

  const keepsCustomSecurity =
    network.security === 'custom' && security === 'keep';
  const securityRequiresPassword =
    security === 'psk2' || security === 'sae-mixed' || security === 'sae';
  const savedSecurity: WifiSecurityChoice =
    network.security === 'custom' ? 'keep' : network.security;
  const settingsDirty =
    ssid.trim() !== network.ssid ||
    enabled !== network.enabled ||
    security !== savedSecurity ||
    password.length > 0;
  const securityOptions = [
    ...(network.security === 'custom'
      ? [
          {
            value: 'keep',
            label: `현재 고급 설정 유지 (${network.securityRaw})`,
          },
        ]
      : []),
    ...SECURITY_OPTIONS,
  ];

  const submit = async (
    event: JSX.TargetedSubmitEvent<HTMLFormElement>,
  ) => {
    event.preventDefault();
    const normalizedSsid = ssid.trim();
    const ssidBytes = new TextEncoder().encode(normalizedSsid).length;

    if (ssidBytes < 1 || ssidBytes > 32) {
      setValidationError('SSID는 UTF-8 기준 1~32바이트로 입력해 주세요.');
      return;
    }

    if (password && !isValidPassword(password)) {
      setValidationError('비밀번호는 8~63자 또는 64자리 16진수여야 합니다.');
      return;
    }

    if (
      securityRequiresPassword &&
      !network.passwordConfigured &&
      password.length === 0
    ) {
      setValidationError('보안 Wi-Fi를 사용하려면 비밀번호를 입력해 주세요.');
      return;
    }

    if (
      !window.confirm(
        'Wi-Fi 설정을 적용하면 현재 무선 연결이 잠시 끊어질 수 있습니다. 계속하시겠습니까?',
      )
    ) {
      return;
    }

    setValidationError(null);
    const updated = await onUpdate({
      section: network.section,
      ssid: normalizedSsid,
      security,
      password,
      enabled,
    });

    if (updated) {
      setPassword('');
    }
  };

  return (
    <form
      class="rounded-2xl border border-slate-200 bg-white p-4 shadow-sm shadow-slate-900/5 sm:p-6"
      onSubmit={(event) => void submit(event)}
    >
      <div class="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
        <div class="flex min-w-0 items-start gap-3">
          <span class="grid size-11 shrink-0 place-items-center rounded-xl bg-teal-50 text-teal-700">
            <RouterIcon class="size-6" />
          </span>
          <div class="min-w-0">
            <p class="m-0 text-xs font-extrabold uppercase tracking-[0.16em] text-slate-500">
              {network.bandLabel}
            </p>
            <h2 class="mt-2 mb-0 break-words text-xl font-extrabold tracking-tight text-slate-950">
              {network.ssid || '이름 없는 Wi-Fi'}
            </h2>
            <p class="mt-2 mb-0 text-sm text-slate-600">
              채널 {network.channel ?? '자동'} · 연결 기기 {network.clientCount}대
            </p>
          </div>
        </div>
        <div class="flex flex-wrap items-center gap-2 sm:justify-end">
          {settingsDirty ? (
            <span
              aria-live="polite"
              class="inline-flex shrink-0 items-center gap-1.5 rounded-full border border-amber-200 bg-amber-50 px-2.5 py-1 text-xs font-extrabold text-amber-800"
              role="status"
            >
              <AlertIcon aria-hidden="true" class="size-3.5 shrink-0" />
              저장되지 않음
            </span>
          ) : null}
          <span
            class={`inline-flex w-fit items-center gap-2 rounded-full px-3 py-1.5 text-xs font-extrabold ring-1 ring-inset ${
              network.runtimeUp
                ? 'bg-emerald-50 text-emerald-700 ring-emerald-200'
                : 'bg-slate-100 text-slate-600 ring-slate-200'
            }`}
          >
            <span
              class={`size-2 rounded-full ${network.runtimeUp ? 'bg-emerald-500' : 'bg-slate-400'}`}
            />
            {network.runtimeUp ? '동작 중' : network.enabled ? '시작 대기' : '꺼짐'}
          </span>
        </div>
      </div>

      <div class="mt-6 grid gap-5 lg:grid-cols-2">
        <label class="block">
          <span class="text-sm font-extrabold text-slate-800">Wi-Fi 이름 (SSID)</span>
          <input
            autocomplete="off"
            class="mt-2 min-h-11 w-full rounded-xl border-2 border-slate-300 bg-slate-50 px-4 py-2.5 text-sm font-semibold text-slate-950 shadow-inner outline-none transition placeholder:text-slate-400 focus:border-teal-500 focus:bg-white focus:ring-4 focus:ring-teal-100 disabled:cursor-not-allowed disabled:bg-slate-100"
            disabled={busy}
            maxLength={32}
            onInput={(event) => setSsid(event.currentTarget.value)}
            value={ssid}
          />
        </label>

        <div class="block">
          <span class="text-sm font-extrabold text-slate-800">보안 방식</span>
          <CustomSelect
            ariaLabel={`${network.bandLabel} Wi-Fi 보안 방식`}
            className="mt-2"
            disabled={busy}
            id={`wifi-security-${network.section}`}
            onChange={(nextValue) => {
              const next = nextValue as WifiSecurityChoice;
              setSecurity(next);
              if (next === 'none' || next === 'keep') {
                setPassword('');
              }
            }}
            options={securityOptions}
            value={security}
            variant="emphasized"
          />
          <span class="mt-2 block text-xs text-slate-500">
            현재: {securityLabel(network)}
          </span>
        </div>

        <label class="block lg:col-span-2">
          <span class="text-sm font-extrabold text-slate-800">새 비밀번호</span>
          <input
            autocomplete="new-password"
            class="mt-2 min-h-11 w-full rounded-xl border-2 border-slate-300 bg-slate-50 px-4 py-2.5 text-sm font-semibold text-slate-950 shadow-inner outline-none transition placeholder:text-slate-400 focus:border-teal-500 focus:bg-white focus:ring-4 focus:ring-teal-100 disabled:cursor-not-allowed disabled:bg-slate-100"
            disabled={busy || security === 'none' || keepsCustomSecurity}
            onInput={(event) => setPassword(event.currentTarget.value)}
            placeholder={
              keepsCustomSecurity
                ? '고급 보안 설정은 기존 LuCI에서 변경합니다'
                : network.passwordConfigured
                  ? '비워 두면 기존 비밀번호를 유지합니다'
                  : '8자 이상의 비밀번호를 입력하세요'
            }
            type="password"
            value={password}
          />
          <span class="mt-2 block text-xs text-slate-500">
            저장된 비밀번호는 화면이나 API로 다시 노출하지 않습니다.
          </span>
        </label>
      </div>

      <div class="mt-6 flex flex-col gap-4 border-t border-slate-200 pt-5 sm:flex-row sm:items-center sm:justify-between">
        <label class="inline-flex min-h-11 items-center gap-3 text-sm font-extrabold text-slate-800">
          <input
            checked={enabled}
            class="size-5 accent-teal-700"
            disabled={busy}
            onChange={(event) => setEnabled(event.currentTarget.checked)}
            type="checkbox"
          />
          이 Wi-Fi 사용
        </label>
        <button
          class="inline-flex min-h-11 w-full items-center justify-center gap-2 rounded-xl border-0 bg-teal-700 px-5 sm:w-auto py-2.5 text-sm font-extrabold text-white shadow-sm transition hover:bg-teal-800 focus:outline-none focus-visible:ring-4 focus-visible:ring-teal-200 disabled:cursor-wait disabled:opacity-60"
          disabled={busy || !settingsDirty}
          type="submit"
        >
          <CheckCircleIcon class={`size-5 ${saving ? 'animate-pulse' : ''}`} />
          {saving ? '적용 중' : '설정 저장'}
        </button>
      </div>

      {validationError ? (
        <p class="mt-4 mb-0 rounded-xl bg-red-50 px-4 py-3 text-sm font-bold text-red-800">
          {validationError}
        </p>
      ) : null}
    </form>
  );
}

function FeedbackPanel({
  feedback,
  onDismiss,
}: {
  feedback: Exclude<WifiFeedback, null>;
  onDismiss: () => void;
}) {
  const classes =
    feedback.kind === 'success'
      ? 'border-emerald-200 bg-emerald-50 text-emerald-900'
      : feedback.kind === 'warning'
        ? 'border-amber-200 bg-amber-50 text-amber-900'
        : 'border-red-200 bg-red-50 text-red-900';

  return (
    <div
      aria-live="polite"
      class={`mb-5 flex flex-col gap-3 rounded-2xl border px-4 py-3 text-sm sm:flex-row sm:items-center sm:justify-between ${classes}`}
    >
      <p class="m-0 font-bold leading-6">{feedback.message}</p>
      <button
        class="min-h-11 w-full shrink-0 rounded-lg border border-current bg-transparent sm:min-h-9 sm:w-auto px-3 py-1.5 text-xs font-extrabold"
        onClick={onDismiss}
        type="button"
      >
        닫기
      </button>
    </div>
  );
}

export function WifiPage({
  data,
  error,
  feedback,
  loading,
  updatingSection,
  onDismissFeedback,
  onRetry,
  onUpdate,
}: WifiPageProps) {
  if (loading) {
    return <LoadingPanel />;
  }

  if (error) {
    return <ErrorPanel message={error} onRetry={onRetry} />;
  }

  if (!data) {
    return null;
  }

  return (
    <>
      {feedback ? (
        <FeedbackPanel feedback={feedback} onDismiss={onDismissFeedback} />
      ) : null}

      <section class="mb-5 rounded-2xl border border-amber-200 bg-amber-50 p-5 text-amber-950 sm:p-6">
        <p class="m-0 text-xs font-extrabold uppercase tracking-[0.16em] text-amber-700">
          연결 주의
        </p>
        <h2 class="mt-2 mb-0 text-lg font-extrabold">
          Wi-Fi 이름이나 비밀번호를 바꾸면 현재 연결이 끊어집니다
        </h2>
        <p class="mt-2 mb-0 text-sm leading-6 text-amber-900/80">
          변경한 Wi-Fi 이름과 비밀번호로 다시 연결하면 SmartSafeHub를 계속 사용할 수
          있습니다. VLAN, 게스트 네트워크와 고급 무선 옵션은 기존 LuCI에서 관리합니다.
        </p>
      </section>

      {data.networks.length ? (
        <section aria-label="기본 Wi-Fi 설정" class="grid gap-5 xl:grid-cols-2">
          {data.networks.map((network) => (
            <WifiNetworkCard
              key={network.section}
              busy={updatingSection !== null}
              network={network}
              onUpdate={onUpdate}
              saving={updatingSection === network.section}
            />
          ))}
        </section>
      ) : (
        <section class="rounded-2xl border border-slate-200 bg-white p-5 text-center shadow-sm shadow-slate-900/5 sm:p-8">
          <RouterIcon class="mx-auto size-10 text-slate-400" />
          <h2 class="mt-4 mb-0 text-lg font-extrabold text-slate-950">
            관리할 기본 Wi-Fi를 찾지 못했습니다
          </h2>
          <p class="mt-2 mb-0 text-sm leading-6 text-slate-600">
            기존 LuCI에서 AP 모드의 무선 네트워크를 먼저 구성해 주세요.
          </p>
        </section>
      )}
    </>
  );
}
