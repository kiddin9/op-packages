import type { JSX } from 'preact';
import { useEffect, useMemo, useState } from 'preact/hooks';

import { CustomSelect } from '../components/CustomSelect';
import { Ipv4OctetInput } from '../components/Ipv4OctetInput';
import {
  AlertIcon,
  CheckCircleIcon,
  EyeIcon,
  EyeOffIcon,
  GlobeIcon,
  ReloadIcon,
  RouterIcon,
} from '../components/Icons';
import { ErrorPanel, LoadingPanel } from '../components/StatePanels';
import type { WanFeedback } from '../hooks/useWan';
import type { WanProtocol, WanSettings, WanSettingsInput } from '../types/wan';

interface WanPageProps {
  action: 'saving' | 'reconnecting' | null;
  data: WanSettings | null;
  error: string | null;
  feedback: WanFeedback;
  loading: boolean;
  onDismissFeedback: () => void;
  onReconnect: () => void;
  onRetry: () => void;
  onSave: (input: WanSettingsInput) => Promise<boolean>;
}

interface WanFormState {
  protocol: string;
  pppoeUsername: string;
  pppoePassword: string;
  staticAddress: string;
  staticPrefixLength: number;
  staticGateway: string;
  dnsPrimary: string;
  dnsSecondary: string;
}

const SUPPORTED_PROTOCOLS: readonly WanProtocol[] = ['dhcp', 'pppoe', 'static'];
const DEFAULT_STATIC_SECONDARY_DNS = '1.1.1.1';
const PREFIX_OPTIONS = Array.from({ length: 33 }, (_, index) => index);

function isSupportedProtocol(value: string): value is WanProtocol {
  return SUPPORTED_PROTOCOLS.includes(value as WanProtocol);
}

function protocolLabel(protocol: string | null): string {
  switch (protocol) {
    case 'dhcp':
      return '자동 IP (DHCP)';
    case 'pppoe':
      return 'PPPoE';
    case 'static':
      return '고정 IPv4';
    default:
      return protocol ? protocol.toUpperCase() : '확인 전';
  }
}

function formValues(data: WanSettings): WanFormState {
  return {
    protocol: data.configuration.protocol,
    pppoeUsername: data.configuration.pppoe.username,
    pppoePassword: '',
    staticAddress: data.configuration.static.address ?? '',
    staticPrefixLength: data.configuration.static.prefixLength ?? 24,
    staticGateway: data.configuration.static.gateway ?? '',
    dnsPrimary: data.configuration.static.dns[0] ?? '',
    dnsSecondary: data.configuration.static.dns[1] ?? '',
  };
}

function normalized(value: string): string {
  return value.trim();
}

function formChanged(form: WanFormState, data: WanSettings): boolean {
  const persisted = formValues(data);

  if (form.protocol !== persisted.protocol) {
    return true;
  }
  if (form.protocol === 'dhcp' || !isSupportedProtocol(form.protocol)) {
    return false;
  }
  if (form.protocol === 'pppoe') {
    return (
      normalized(form.pppoeUsername) !== persisted.pppoeUsername ||
      form.pppoePassword.length > 0
    );
  }

  return (
    normalized(form.staticAddress) !== persisted.staticAddress ||
    form.staticPrefixLength !== persisted.staticPrefixLength ||
    normalized(form.staticGateway) !== persisted.staticGateway ||
    normalized(form.dnsPrimary) !== persisted.dnsPrimary ||
    normalized(form.dnsSecondary) !== persisted.dnsSecondary
  );
}

function isIpv4(value: string): boolean {
  const parts = value.trim().split('.');
  if (parts.length !== 4) {
    return false;
  }

  return parts.every((part) => {
    if (!/^(0|[1-9][0-9]{0,2})$/.test(part)) {
      return false;
    }
    const octet = Number(part);
    return octet >= 0 && octet <= 255;
  });
}

function netmaskFromPrefix(prefix: number): string {
  let remaining = prefix;
  const octets = Array.from({ length: 4 }, () => {
    if (remaining >= 8) {
      remaining -= 8;
      return 255;
    }
    if (remaining <= 0) {
      return 0;
    }

    const value = 256 - 2 ** (8 - remaining);
    remaining = 0;
    return value;
  });

  return octets.join('.');
}

function formatUptime(seconds: number): string {
  if (!Number.isFinite(seconds) || seconds <= 0) {
    return '연결 시간 확인 전';
  }

  const days = Math.floor(seconds / 86_400);
  const hours = Math.floor((seconds % 86_400) / 3_600);
  const minutes = Math.floor((seconds % 3_600) / 60);

  if (days > 0) {
    return `${days}일 ${hours}시간 연결됨`;
  }
  if (hours > 0) {
    return `${hours}시간 ${minutes}분 연결됨`;
  }
  return `${Math.max(1, minutes)}분 연결됨`;
}

function FeedbackPanel({
  feedback,
  onDismiss,
}: {
  feedback: Exclude<WanFeedback, null>;
  onDismiss: () => void;
}) {
  const classes =
    feedback.kind === 'success'
      ? 'border-emerald-200 bg-emerald-50 text-emerald-900'
      : feedback.kind === 'warning'
        ? 'border-amber-200 bg-amber-50 text-amber-950'
        : 'border-red-200 bg-red-50 text-red-900';

  return (
    <div aria-live="polite" class={`mb-5 rounded-2xl border px-4 py-4 text-sm ${classes}`}>
      <div class="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <p class="m-0 font-bold leading-6">{feedback.message}</p>
        <button
          class="min-h-10 shrink-0 rounded-lg border border-current bg-transparent px-3 py-1.5 text-xs font-extrabold"
          onClick={onDismiss}
          type="button"
        >
          닫기
        </button>
      </div>
    </div>
  );
}

function WanStatusCards({
  data,
  busy,
  onReconnect,
}: {
  data: WanSettings;
  busy: boolean;
  onReconnect: () => void;
}) {
  const status = data.status;
  const connected = status.connected;

  return (
    <section class="grid gap-4 lg:grid-cols-3" aria-label="인터넷 연결 상태">
      <article
        class={`rounded-2xl border p-5 shadow-sm shadow-slate-900/5 ${
          connected
            ? 'border-emerald-200 bg-emerald-50 text-emerald-950'
            : 'border-amber-200 bg-amber-50 text-amber-950'
        }`}
      >
        <div class="flex items-start justify-between gap-3">
          <span
            class={`grid size-10 place-items-center rounded-xl ${
              connected ? 'bg-emerald-100 text-emerald-700' : 'bg-amber-100 text-amber-700'
            }`}
          >
            {connected ? <CheckCircleIcon class="size-5" /> : <AlertIcon class="size-5" />}
          </span>
          <button
            class="inline-flex min-h-10 items-center justify-center gap-2 rounded-xl border border-current bg-transparent px-3 py-2 text-xs font-extrabold transition disabled:cursor-wait disabled:opacity-60"
            disabled={busy}
            onClick={onReconnect}
            type="button"
          >
            <ReloadIcon class={`size-4 ${busy ? 'animate-spin' : ''}`} />
            재연결
          </button>
        </div>
        <p class="mt-4 mb-0 text-xs font-extrabold uppercase tracking-[0.14em] opacity-70">
          인터넷 상태
        </p>
        <p class="mt-2 mb-0 text-xl font-black">
          {status.pending ? '연결 중' : connected ? '연결됨' : '연결 안 됨'}
        </p>
        <p class="mt-1 mb-0 text-sm font-semibold leading-6 opacity-80">
          {protocolLabel(status.protocol ?? data.configuration.protocol)} · {formatUptime(status.uptimeSeconds)}
        </p>
      </article>

      <article class="rounded-2xl border border-slate-200 bg-white p-5 shadow-sm shadow-slate-900/5">
        <span class="grid size-10 place-items-center rounded-xl bg-teal-50 text-teal-700">
          <GlobeIcon class="size-5" />
        </span>
        <p class="mt-4 mb-0 text-xs font-extrabold uppercase tracking-[0.14em] text-slate-500">
          WAN IPv4
        </p>
        <p class="mt-2 mb-0 break-all text-xl font-black text-slate-950">
          {status.address
            ? `${status.address}${status.prefixLength === null ? '' : `/${status.prefixLength}`}`
            : '주소 없음'}
        </p>
        <p class="mt-1 mb-0 text-sm font-semibold text-slate-600">
          {status.device ? `인터페이스 ${status.device}` : '인터페이스 확인 전'}
        </p>
      </article>

      <article class="rounded-2xl border border-slate-200 bg-white p-5 shadow-sm shadow-slate-900/5">
        <span class="grid size-10 place-items-center rounded-xl bg-slate-100 text-slate-700">
          <RouterIcon class="size-5" />
        </span>
        <p class="mt-4 mb-0 text-xs font-extrabold uppercase tracking-[0.14em] text-slate-500">
          Gateway · DNS
        </p>
        <p class="mt-2 mb-0 break-all text-base font-black text-slate-950">
          {status.gateway ?? 'Gateway 확인 전'}
        </p>
        <p class="mt-1 mb-0 break-all text-sm font-semibold leading-6 text-slate-600">
          {status.dns.length > 0 ? status.dns.join(' · ') : 'DNS 확인 전'}
        </p>
      </article>
    </section>
  );
}

export function WanPage({
  action,
  data,
  error,
  feedback,
  loading,
  onDismissFeedback,
  onReconnect,
  onRetry,
  onSave,
}: WanPageProps) {
  const [form, setForm] = useState<WanFormState>({
    protocol: 'dhcp',
    pppoeUsername: '',
    pppoePassword: '',
    staticAddress: '',
    staticPrefixLength: 24,
    staticGateway: '',
    dnsPrimary: '',
    dnsSecondary: '',
  });
  const [settingsDirty, setSettingsDirty] = useState(false);
  const [showPassword, setShowPassword] = useState(false);
  const [validationError, setValidationError] = useState<string | null>(null);

  useEffect(() => {
    if (!data || settingsDirty) {
      return;
    }
    setForm(formValues(data));
    setValidationError(null);
  }, [data, settingsDirty]);

  const protocolOptions = useMemo(() => {
    const options = [
      { value: 'dhcp', label: '자동 IP (DHCP)' },
      { value: 'pppoe', label: 'PPPoE' },
      { value: 'static', label: '고정 IPv4' },
    ];

    if (data && !data.configuration.supported) {
      options.unshift({
        value: data.configuration.protocol,
        label: `현재 설정 (${data.configuration.protocol})`,
      });
    }
    return options;
  }, [data]);

  if (loading) {
    return <LoadingPanel />;
  }
  if (error) {
    return <ErrorPanel message={error} onRetry={onRetry} />;
  }
  if (!data) {
    return null;
  }

  const busy = action !== null;

  const updateForm = (patch: Partial<WanFormState>) => {
    setForm((current) => {
      const next = { ...current, ...patch };
      setSettingsDirty(formChanged(next, data));
      return next;
    });
    setValidationError(null);
  };

  const submit = async (event: JSX.TargetedSubmitEvent<HTMLFormElement>) => {
    event.preventDefault();

    if (!isSupportedProtocol(form.protocol)) {
      setValidationError('DHCP, PPPoE 또는 고정 IPv4 중 하나를 선택해 주세요.');
      return;
    }

    if (form.protocol === 'pppoe') {
      if (!normalized(form.pppoeUsername)) {
        setValidationError('PPPoE 사용자명을 입력해 주세요.');
        return;
      }
      const passwordRequired =
        data.configuration.protocol !== 'pppoe' ||
        !data.configuration.pppoe.passwordConfigured;
      if (passwordRequired && form.pppoePassword.length === 0) {
        setValidationError('PPPoE 연결을 시작하려면 비밀번호를 입력해 주세요.');
        return;
      }
    }

    if (form.protocol === 'static') {
      if (!isIpv4(form.staticAddress)) {
        setValidationError('고정 IPv4 주소를 올바르게 입력해 주세요.');
        return;
      }
      if (!isIpv4(form.staticGateway)) {
        setValidationError('기본 게이트웨이를 올바르게 입력해 주세요.');
        return;
      }
      if (!isIpv4(form.dnsPrimary)) {
        setValidationError('기본 DNS 서버를 올바르게 입력해 주세요.');
        return;
      }
      if (normalized(form.dnsSecondary) && !isIpv4(form.dnsSecondary)) {
        setValidationError('보조 DNS 서버를 올바르게 입력해 주세요.');
        return;
      }
    }

    if (
      !window.confirm(
        '인터넷 연결 설정을 적용하면 WAN 연결이 다시 시작되어 인터넷이 잠시 끊길 수 있습니다. 계속하시겠습니까?',
      )
    ) {
      return;
    }

    const saved = await onSave({
      protocol: form.protocol,
      pppoeUsername: normalized(form.pppoeUsername),
      pppoePassword: form.pppoePassword,
      pppoePasswordChanged: form.pppoePassword.length > 0,
      staticAddress: normalized(form.staticAddress),
      staticPrefixLength: form.staticPrefixLength,
      staticGateway: normalized(form.staticGateway),
      dnsPrimary: normalized(form.dnsPrimary),
      dnsSecondary: normalized(form.dnsSecondary),
    });
    if (saved) {
      setForm((current) => ({ ...current, pppoePassword: '' }));
      setSettingsDirty(false);
    }
  };

  const reconnect = () => {
    if (
      window.confirm(
        'WAN 연결을 다시 시작합니다. 인터넷이 잠시 끊길 수 있습니다. 계속하시겠습니까?',
      )
    ) {
      onReconnect();
    }
  };

  return (
    <>
      {feedback ? <FeedbackPanel feedback={feedback} onDismiss={onDismissFeedback} /> : null}

      <WanStatusCards data={data} busy={busy} onReconnect={reconnect} />

      {!data.configuration.supported ? (
        <section class="mt-5 rounded-2xl border border-amber-200 bg-amber-50 p-5 text-amber-950 sm:p-6">
          <div class="flex items-start gap-3">
            <AlertIcon class="mt-0.5 size-5 shrink-0 text-amber-700" />
            <div>
              <h2 class="m-0 text-base font-black">현재 WAN 방식은 직접 관리하지 않습니다</h2>
              <p class="mt-2 mb-0 text-sm font-semibold leading-6 text-amber-900/80">
                현재 설정은 {data.configuration.protocol}입니다. 아래에서 DHCP, PPPoE 또는 고정 IPv4를 선택해 저장하면 해당 방식으로 전환합니다.
              </p>
            </div>
          </div>
        </section>
      ) : null}

      <form
        class="mt-5 rounded-2xl border border-slate-200 bg-white p-5 shadow-sm shadow-slate-900/5 sm:p-6"
        onSubmit={(event) => void submit(event)}
      >
        <div class="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
          <div class="flex min-w-0 items-start gap-3">
            <span class="grid size-11 shrink-0 place-items-center rounded-xl bg-teal-50 text-teal-700">
              <GlobeIcon class="size-6" />
            </span>
            <div class="min-w-0">
              <p class="m-0 text-xs font-extrabold uppercase tracking-[0.16em] text-slate-500">
                Internet
              </p>
              <h2 class="mt-2 mb-0 text-xl font-black text-slate-950">인터넷 연결 설정</h2>
              <p class="mt-2 mb-0 text-sm font-semibold leading-6 text-slate-600">
                통신사 또는 상위 네트워크 환경에 맞는 WAN 연결 방식을 선택합니다.
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

        <div class="mt-6">
          <span class="text-sm font-extrabold text-slate-800">연결 방식</span>
          <CustomSelect
            ariaLabel="WAN 연결 방식"
            className="mt-2 max-w-xl"
            disabled={busy}
            id="wan-protocol"
            onChange={(value) =>
              updateForm(
                value === 'static' && !normalized(form.dnsSecondary)
                  ? { protocol: value, dnsSecondary: DEFAULT_STATIC_SECONDARY_DNS }
                  : { protocol: value },
              )
            }
            options={protocolOptions}
            value={form.protocol}
            variant="emphasized"
          />
          <span class="mt-2 block text-xs font-semibold leading-5 text-slate-500">
            대부분의 가정용 인터넷과 상위 공유기 연결은 자동 IP(DHCP)를 사용합니다.
          </span>
        </div>

        {form.protocol === 'pppoe' ? (
          <div class="mt-6 grid gap-5 lg:grid-cols-2">
            <label class="block">
              <span class="text-sm font-extrabold text-slate-800">PPPoE 사용자명</span>
              <input
                autocomplete="username"
                class="mt-2 min-h-11 w-full rounded-xl border-2 border-slate-300 bg-slate-50 px-4 py-2.5 text-sm font-semibold text-slate-950 shadow-inner outline-none transition focus:border-teal-500 focus:bg-white focus:ring-4 focus:ring-teal-100 disabled:cursor-not-allowed disabled:bg-slate-100"
                disabled={busy}
                onInput={(event) => updateForm({ pppoeUsername: event.currentTarget.value })}
                spellcheck={false}
                value={form.pppoeUsername}
              />
            </label>

            <label class="block">
              <span class="text-sm font-extrabold text-slate-800">PPPoE 비밀번호</span>
              <span class="relative mt-2 block">
                <input
                  autocomplete="new-password"
                  class="min-h-11 w-full rounded-xl border-2 border-slate-300 bg-slate-50 px-4 py-2.5 pr-12 text-sm font-semibold text-slate-950 shadow-inner outline-none transition focus:border-teal-500 focus:bg-white focus:ring-4 focus:ring-teal-100 disabled:cursor-not-allowed disabled:bg-slate-100"
                  disabled={busy}
                  onInput={(event) => updateForm({ pppoePassword: event.currentTarget.value })}
                  placeholder={
                    data.configuration.protocol === 'pppoe' && data.configuration.pppoe.passwordConfigured
                      ? '변경할 때만 입력'
                      : 'PPPoE 비밀번호'
                  }
                  type={showPassword ? 'text' : 'password'}
                  value={form.pppoePassword}
                />
                <button
                  aria-label={showPassword ? '비밀번호 숨기기' : '비밀번호 표시'}
                  class="absolute inset-y-0 right-1 grid w-10 place-items-center rounded-lg border-0 bg-transparent text-slate-500"
                  disabled={busy}
                  onClick={() => setShowPassword((visible) => !visible)}
                  type="button"
                >
                  {showPassword ? <EyeOffIcon class="size-5" /> : <EyeIcon class="size-5" />}
                </button>
              </span>
              <span class="mt-2 block text-xs text-slate-500">
                {data.configuration.protocol === 'pppoe' && data.configuration.pppoe.passwordConfigured
                  ? '비워 두면 현재 저장된 비밀번호를 그대로 사용합니다.'
                  : '통신사에서 제공한 PPPoE 비밀번호를 입력해 주세요.'}
              </span>
            </label>
          </div>
        ) : null}

        {form.protocol === 'static' ? (
          <div class="mt-6 grid gap-5 lg:grid-cols-2">
            <label class="block">
              <span class="text-sm font-extrabold text-slate-800">IPv4 주소</span>
              <Ipv4OctetInput
                disabled={busy}
                label="IPv4 주소"
                onChange={(value) => updateForm({ staticAddress: value })}
                value={form.staticAddress}
              />
            </label>

            <div class="block">
              <span class="text-sm font-extrabold text-slate-800">서브넷 마스크</span>
              <CustomSelect
                ariaLabel="WAN 서브넷 마스크"
                className="mt-2"
                disabled={busy}
                id="wan-static-prefix-length"
                onChange={(value) => updateForm({ staticPrefixLength: Number(value) })}
                options={PREFIX_OPTIONS.map((prefix) => ({
                  value: String(prefix),
                  label: `/${prefix} · ${netmaskFromPrefix(prefix)}`,
                }))}
                value={String(form.staticPrefixLength)}
                variant="emphasized"
              />
            </div>

            <label class="block">
              <span class="text-sm font-extrabold text-slate-800">기본 게이트웨이</span>
              <Ipv4OctetInput
                disabled={busy}
                label="기본 게이트웨이"
                onChange={(value) => updateForm({ staticGateway: value })}
                value={form.staticGateway}
              />
            </label>

            <label class="block">
              <span class="text-sm font-extrabold text-slate-800">기본 DNS</span>
              <Ipv4OctetInput
                disabled={busy}
                label="기본 DNS"
                onChange={(value) => updateForm({ dnsPrimary: value })}
                value={form.dnsPrimary}
              />
            </label>

            <label class="block lg:col-start-2">
              <span class="text-sm font-extrabold text-slate-800">보조 DNS (선택)</span>
              <Ipv4OctetInput
                disabled={busy}
                label="보조 DNS"
                onChange={(value) => updateForm({ dnsSecondary: value })}
                value={form.dnsSecondary}
              />
            </label>
          </div>
        ) : null}

        {form.protocol === 'dhcp' ? (
          <div class="mt-6 rounded-xl border border-slate-200 bg-slate-50 px-4 py-4 text-sm font-semibold leading-6 text-slate-600">
            상위 공유기 또는 통신사 장비에서 IP 주소, 기본 게이트웨이와 DNS 정보를 자동으로 받습니다. 별도의 계정이나 고정 주소가 없다면 이 방식을 사용하세요.
          </div>
        ) : null}

        {validationError ? (
          <p class="mt-5 mb-0 rounded-xl bg-red-50 px-4 py-3 text-sm font-bold text-red-800">
            {validationError}
          </p>
        ) : null}

        <div class="mt-6 flex flex-col gap-3 border-t border-slate-200 pt-5 sm:flex-row sm:items-center sm:justify-between">
          <p class="m-0 text-xs font-semibold leading-5 text-slate-500">
            설정 저장 후 WAN만 다시 연결하며 LAN 관리 페이지와 내부 네트워크 설정은 유지됩니다.
          </p>
          <button
            class="inline-flex min-h-11 w-full shrink-0 items-center justify-center gap-2 rounded-xl border-0 bg-teal-700 px-5 py-2.5 text-sm font-extrabold text-white shadow-sm transition hover:bg-teal-800 focus:outline-none focus-visible:ring-4 focus-visible:ring-teal-200 disabled:cursor-wait disabled:opacity-60 sm:w-auto"
            disabled={busy || !settingsDirty}
            type="submit"
          >
            <CheckCircleIcon class={`size-5 ${action === 'saving' ? 'animate-pulse' : ''}`} />
            {action === 'saving' ? '저장 중' : '설정 저장'}
          </button>
        </div>
      </form>
    </>
  );
}
