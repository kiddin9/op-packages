import type { JSX } from 'preact';
import { useEffect, useMemo, useState } from 'preact/hooks';

import { CustomSelect } from '../components/CustomSelect';
import type { LanFeedback } from '../hooks/useLan';
import type { LanSettings, LanSettingsInput } from '../types/lan';
import {
  AlertIcon,
  CableIcon,
  CheckCircleIcon,
  GlobeIcon,
  RouterIcon,
} from '../components/Icons';
import { ErrorPanel, LoadingPanel } from '../components/StatePanels';

interface LanPageProps {
  action: 'saving' | 'auto' | null;
  data: LanSettings | null;
  error: string | null;
  feedback: LanFeedback;
  loading: boolean;
  onApplyRecommendation: () => Promise<boolean>;
  onDismissFeedback: () => void;
  onRetry: () => void;
  onSave: (input: LanSettingsInput) => Promise<boolean>;
}

const PREFIX_OPTIONS = [16, 20, 22, 23, 24, 25, 26, 27, 28] as const;
const LEASE_OPTIONS = [
  ['30m', '30분'],
  ['1h', '1시간'],
  ['6h', '6시간'],
  ['12h', '12시간'],
  ['24h', '24시간'],
  ['3d', '3일'],
  ['7d', '7일'],
] as const;

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


function splitIpv4(value: string): [string, string, string, string] {
  const parts = value.split('.');
  return [parts[0] ?? '', parts[1] ?? '', parts[2] ?? '', parts[3] ?? ''];
}

function normalizeOctet(value: string): string {
  return value.replace(/\D/g, '').slice(0, 3);
}

function lanPrefix(value: string): string | null {
  const parts = splitIpv4(value);
  if (parts.slice(0, 3).some((part) => part === '' || Number(part) > 255)) {
    return null;
  }
  return parts.slice(0, 3).join('.');
}

function hostOctet(value: string): string {
  return splitIpv4(value)[3];
}

function lanFormValues(data: LanSettings): LanSettingsInput {
  const prefix = lanPrefix(data.lan.address);
  const startHost = hostOctet(data.dhcp.start ?? '');
  const endHost = hostOctet(data.dhcp.end ?? '');

  return {
    ipAddress: data.lan.address,
    prefixLength: data.lan.prefixLength,
    dhcpEnabled: data.dhcp.enabled,
    dhcpStart: prefix && startHost ? `${prefix}.${startHost}` : (data.dhcp.start ?? ''),
    dhcpEnd: prefix && endHost ? `${prefix}.${endHost}` : (data.dhcp.end ?? ''),
    leaseTime: data.dhcp.leaseTime,
  };
}

function Ipv4OctetInput({
  disabled,
  value,
  onChange,
}: {
  disabled: boolean;
  value: string;
  onChange: (value: string) => void;
}) {
  const octets = splitIpv4(value);

  const updateOctet = (index: number, nextValue: string) => {
    const next = [...octets] as [string, string, string, string];
    next[index] = normalizeOctet(nextValue);
    onChange(next.join('.'));
  };

  return (
    <div class="mt-2 flex min-h-11 items-center gap-1.5" aria-label="IPv4 주소 입력">
      {octets.map((octet, index) => (
        <div class="contents" key={index}>
          {index > 0 ? <span class="text-sm font-black text-slate-400">.</span> : null}
          <input
            aria-label={`IP 주소 ${index + 1}번째 옥텟`}
            autocomplete="off"
            class="min-h-11 min-w-0 flex-1 rounded-xl border-2 border-slate-300 bg-slate-50 px-2 py-2.5 text-center text-sm font-semibold text-slate-950 shadow-inner outline-none transition focus:border-teal-500 focus:bg-white focus:ring-4 focus:ring-teal-100 disabled:cursor-not-allowed disabled:bg-slate-100"
            disabled={disabled}
            inputMode="numeric"
            maxLength={3}
            onInput={(event) => updateOctet(index, event.currentTarget.value)}
            pattern="[0-9]*"
            spellcheck={false}
            value={octet}
          />
        </div>
      ))}
    </div>
  );
}

function DhcpHostInput({
  disabled,
  label,
  lanAddress,
  value,
  onChange,
}: {
  disabled: boolean;
  label: string;
  lanAddress: string;
  value: string;
  onChange: (value: string) => void;
}) {
  const prefix = lanPrefix(lanAddress);
  const prefixParts = prefix?.split('.') ?? ['', '', ''];
  const host = hostOctet(value);

  const updateHost = (nextValue: string) => {
    const normalized = normalizeOctet(nextValue);
    onChange(prefix && normalized !== '' ? `${prefix}.${normalized}` : normalized);
  };

  return (
    <label class="block">
      <span class="text-sm font-extrabold text-slate-800">{label}</span>
      <div class="mt-2 flex min-h-11 items-center gap-1.5" aria-label={`${label} 입력`}>
        {prefixParts.map((part, index) => (
          <div class="contents" key={index}>
            {index > 0 ? <span class="text-sm font-black text-slate-400">.</span> : null}
            <span class="grid min-h-11 min-w-0 flex-1 place-items-center rounded-xl border border-slate-200 bg-slate-100 px-2 py-2.5 text-center text-sm font-bold text-slate-500">
              {part || '—'}
            </span>
          </div>
        ))}
        <span class="text-sm font-black text-slate-400">.</span>
        <input
          aria-label={`${label} 마지막 옥텟`}
          autocomplete="off"
          class="min-h-11 min-w-0 flex-1 rounded-xl border-2 border-slate-300 bg-slate-50 px-2 py-2.5 text-center text-sm font-semibold text-slate-950 shadow-inner outline-none transition focus:border-teal-500 focus:bg-white focus:ring-4 focus:ring-teal-100 disabled:cursor-not-allowed disabled:bg-slate-100"
          disabled={disabled || !prefix}
          inputMode="numeric"
          maxLength={3}
          onInput={(event) => updateHost(event.currentTarget.value)}
          pattern="[0-9]*"
          spellcheck={false}
          value={host}
        />
      </div>
      <span class="mt-2 block text-xs text-slate-500">
        앞 3개 주소는 공유기 IP 주소와 동일하게 유지됩니다.
      </span>
    </label>
  );
}

function managementUrl(address: string): string {
  return `${window.location.protocol}//${address}${window.location.pathname}${window.location.search}${window.location.hash}`;
}

function FeedbackPanel({
  feedback,
  onDismiss,
}: {
  feedback: Exclude<LanFeedback, null>;
  onDismiss: () => void;
}) {
  const classes =
    feedback.kind === 'success'
      ? 'border-emerald-200 bg-emerald-50 text-emerald-900'
      : feedback.kind === 'warning'
        ? 'border-amber-200 bg-amber-50 text-amber-950'
        : 'border-red-200 bg-red-50 text-red-900';

  return (
    <div
      aria-live="polite"
      class={`mb-5 rounded-2xl border px-4 py-4 text-sm ${classes}`}
    >
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
      {feedback.newAddress ? (
        <a
          class="mt-3 inline-flex min-h-10 items-center rounded-lg border border-current px-3 py-2 font-extrabold underline underline-offset-2"
          href={managementUrl(feedback.newAddress)}
        >
          새 공유기 주소 {feedback.newAddress}로 연결
        </a>
      ) : null}
    </div>
  );
}

function NetworkStatus({ data }: { data: LanSettings }) {
  const conflict = data.conflict.detected;

  return (
    <section class="grid gap-4 lg:grid-cols-3" aria-label="내부 네트워크 상태">
      <article class="rounded-2xl border border-slate-200 bg-white p-5 shadow-sm shadow-slate-900/5">
        <span class="grid size-10 place-items-center rounded-xl bg-teal-50 text-teal-700">
          <RouterIcon class="size-5" />
        </span>
        <p class="mt-4 mb-0 text-xs font-extrabold uppercase tracking-[0.14em] text-slate-500">
          SmartSafeHub LAN
        </p>
        <p class="mt-2 mb-0 text-xl font-black text-slate-950">{data.lan.subnet}</p>
        <p class="mt-1 mb-0 text-sm font-semibold text-slate-600">
          공유기 주소 {data.lan.address}
        </p>
      </article>

      <article class="rounded-2xl border border-slate-200 bg-white p-5 shadow-sm shadow-slate-900/5">
        <span class="grid size-10 place-items-center rounded-xl bg-slate-100 text-slate-700">
          <GlobeIcon class="size-5" />
        </span>
        <p class="mt-4 mb-0 text-xs font-extrabold uppercase tracking-[0.14em] text-slate-500">
          상위 네트워크
        </p>
        <p class="mt-2 mb-0 text-xl font-black text-slate-950">
          {data.wan.subnet ?? '확인 전'}
        </p>
        <p class="mt-1 mb-0 text-sm font-semibold text-slate-600">
          {data.wan.connected
            ? `WAN ${data.wan.address ?? '주소 확인 중'}`
            : 'WAN 연결 후 자동으로 확인합니다.'}
        </p>
      </article>

      <article
        class={`rounded-2xl border p-5 shadow-sm shadow-slate-900/5 ${
          conflict
            ? 'border-red-200 bg-red-50 text-red-950'
            : 'border-emerald-200 bg-emerald-50 text-emerald-950'
        }`}
      >
        <span
          class={`grid size-10 place-items-center rounded-xl ${
            conflict ? 'bg-red-100 text-red-700' : 'bg-emerald-100 text-emerald-700'
          }`}
        >
          {conflict ? <AlertIcon class="size-5" /> : <CheckCircleIcon class="size-5" />}
        </span>
        <p class="mt-4 mb-0 text-xs font-extrabold uppercase tracking-[0.14em] opacity-70">
          대역 충돌
        </p>
        <p class="mt-2 mb-0 text-lg font-black">
          {conflict ? '주소 대역이 겹칩니다' : '충돌이 감지되지 않았습니다'}
        </p>
        <p class="mt-1 mb-0 text-sm font-semibold leading-6 opacity-80">
          {conflict
            ? `상위 네트워크 ${data.conflict.wanSubnet ?? ''}와 다른 LAN 대역이 필요합니다.`
            : data.wan.connected
              ? '현재 WAN과 LAN이 서로 다른 IPv4 대역을 사용합니다.'
              : 'WAN이 연결되면 상위 네트워크와의 충돌 여부를 확인합니다.'}
        </p>
      </article>
    </section>
  );
}

export function LanPage({
  action,
  data,
  error,
  feedback,
  loading,
  onApplyRecommendation,
  onDismissFeedback,
  onRetry,
  onSave,
}: LanPageProps) {
  const [ipAddress, setIpAddress] = useState('');
  const [prefixLength, setPrefixLength] = useState(24);
  const [dhcpEnabled, setDhcpEnabled] = useState(true);
  const [dhcpStart, setDhcpStart] = useState('');
  const [dhcpEnd, setDhcpEnd] = useState('');
  const [leaseTime, setLeaseTime] = useState('12h');
  const [settingsDirty, setSettingsDirty] = useState(false);
  const [validationError, setValidationError] = useState<string | null>(null);

  const hasSettingsChanges = (next: Partial<LanSettingsInput> = {}) => {
    if (!data) {
      return false;
    }

    const persisted = lanFormValues(data);
    return (
      (next.ipAddress ?? ipAddress).trim() !== persisted.ipAddress ||
      (next.prefixLength ?? prefixLength) !== persisted.prefixLength ||
      (next.dhcpEnabled ?? dhcpEnabled) !== persisted.dhcpEnabled ||
      (next.dhcpStart ?? dhcpStart).trim() !== persisted.dhcpStart ||
      (next.dhcpEnd ?? dhcpEnd).trim() !== persisted.dhcpEnd ||
      (next.leaseTime ?? leaseTime) !== persisted.leaseTime
    );
  };

  const updateIpAddress = (nextAddress: string) => {
    const nextPrefix = lanPrefix(nextAddress);
    setIpAddress(nextAddress);

    if (!nextPrefix) {
      setSettingsDirty(hasSettingsChanges({ ipAddress: nextAddress }));
      return;
    }

    const startHost = hostOctet(dhcpStart);
    const endHost = hostOctet(dhcpEnd);
    const nextDhcpStart = startHost ? `${nextPrefix}.${startHost}` : '';
    const nextDhcpEnd = endHost ? `${nextPrefix}.${endHost}` : '';
    setDhcpStart(nextDhcpStart);
    setDhcpEnd(nextDhcpEnd);
    setSettingsDirty(
      hasSettingsChanges({
        ipAddress: nextAddress,
        dhcpStart: nextDhcpStart,
        dhcpEnd: nextDhcpEnd,
      }),
    );
  };

  const updateDhcpStart = (nextDhcpStart: string) => {
    setDhcpStart(nextDhcpStart);
    setSettingsDirty(hasSettingsChanges({ dhcpStart: nextDhcpStart }));
  };

  const updateDhcpEnd = (nextDhcpEnd: string) => {
    setDhcpEnd(nextDhcpEnd);
    setSettingsDirty(hasSettingsChanges({ dhcpEnd: nextDhcpEnd }));
  };

  const updatePrefixLength = (nextPrefixLength: number) => {
    setPrefixLength(nextPrefixLength);
    setSettingsDirty(hasSettingsChanges({ prefixLength: nextPrefixLength }));
  };

  const updateLeaseTime = (nextLeaseTime: string) => {
    setLeaseTime(nextLeaseTime);
    setSettingsDirty(hasSettingsChanges({ leaseTime: nextLeaseTime }));
  };

  const updateDhcpEnabled = (nextDhcpEnabled: boolean) => {
    setDhcpEnabled(nextDhcpEnabled);
    setSettingsDirty(hasSettingsChanges({ dhcpEnabled: nextDhcpEnabled }));
  };

  useEffect(() => {
    if (!data || settingsDirty) {
      return;
    }

    const persisted = lanFormValues(data);
    setIpAddress(persisted.ipAddress);
    setPrefixLength(persisted.prefixLength);
    setDhcpEnabled(persisted.dhcpEnabled);
    setDhcpStart(persisted.dhcpStart);
    setDhcpEnd(persisted.dhcpEnd);
    setLeaseTime(persisted.leaseTime);
    setValidationError(null);
  }, [data, settingsDirty]);

  const prefixOptions = useMemo(() => {
    const options = [...PREFIX_OPTIONS];
    if (!options.includes(prefixLength as (typeof PREFIX_OPTIONS)[number])) {
      options.push(prefixLength as (typeof PREFIX_OPTIONS)[number]);
      options.sort((a, b) => a - b);
    }
    return options;
  }, [prefixLength]);

  const leaseOptions = useMemo(() => {
    const options: Array<readonly [string, string]> = [...LEASE_OPTIONS];
    if (!options.some(([value]) => value === leaseTime)) {
      options.push([leaseTime, `현재 설정 (${leaseTime})`]);
    }
    return options;
  }, [leaseTime]);

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

  const submit = async (event: JSX.TargetedSubmitEvent<HTMLFormElement>) => {
    event.preventDefault();

    if (!isIpv4(ipAddress)) {
      setValidationError('공유기 주소를 올바른 IPv4 형식으로 입력해 주세요.');
      return;
    }
    if (!isIpv4(dhcpStart) || !isIpv4(dhcpEnd)) {
      setValidationError('DHCP 시작/종료 주소를 올바른 IPv4 형식으로 입력해 주세요.');
      return;
    }
    if (
      !window.confirm(
        '내부 네트워크 설정을 적용하면 연결된 기기가 새 DHCP 정보를 받는 동안 잠시 연결이 끊길 수 있습니다. 계속하시겠습니까?',
      )
    ) {
      return;
    }

    setValidationError(null);
    const saved = await onSave({
      ipAddress: ipAddress.trim(),
      prefixLength,
      dhcpEnabled,
      dhcpStart: dhcpStart.trim(),
      dhcpEnd: dhcpEnd.trim(),
      leaseTime,
    });
    if (saved) {
      setSettingsDirty(false);
    }
  };

  const applyRecommendation = async () => {
    if (!data.recommendation) {
      return;
    }
    if (
      !window.confirm(
        `상위 네트워크와 겹치지 않는 ${data.recommendation.subnet} 대역으로 자동 변경합니다. 현재 연결이 잠시 끊길 수 있습니다. 계속하시겠습니까?`,
      )
    ) {
      return;
    }

    setValidationError(null);
    const applied = await onApplyRecommendation();
    if (applied) {
      setSettingsDirty(false);
    }
  };

  return (
    <>
      {feedback ? (
        <FeedbackPanel feedback={feedback} onDismiss={onDismissFeedback} />
      ) : null}

      <NetworkStatus data={data} />

      {data.conflict.detected ? (
        <section class="mt-5 rounded-2xl border border-amber-200 bg-amber-50 p-5 text-amber-950 sm:p-6">
          <div class="flex flex-col gap-4 lg:flex-row lg:items-center lg:justify-between">
            <div class="min-w-0">
              <p class="m-0 text-xs font-extrabold uppercase tracking-[0.16em] text-amber-700">
                자동 충돌 해결
              </p>
              <h2 class="mt-2 mb-0 text-lg font-black">안전한 LAN 대역으로 변경할 수 있습니다</h2>
              <p class="mt-2 mb-0 text-sm font-semibold leading-6 text-amber-900/80">
                {data.recommendation
                  ? `${data.recommendation.subnet} · DHCP ${data.recommendation.dhcpStart} ~ ${data.recommendation.dhcpEnd}`
                  : '현재 활성 네트워크와 겹치지 않는 추천 대역을 찾지 못했습니다. 아래에서 직접 설정해 주세요.'}
              </p>
            </div>
            {data.recommendation ? (
              <button
                class="inline-flex min-h-11 shrink-0 items-center justify-center gap-2 rounded-xl border-0 bg-amber-700 px-5 py-2.5 text-sm font-extrabold text-white transition hover:bg-amber-800 focus:outline-none focus-visible:ring-4 focus-visible:ring-amber-200 disabled:cursor-wait disabled:opacity-60"
                disabled={busy}
                onClick={() => void applyRecommendation()}
                type="button"
              >
                <CheckCircleIcon class={`size-5 ${action === 'auto' ? 'animate-pulse' : ''}`} />
                {action === 'auto' ? '변경 중' : '추천 대역으로 자동 변경'}
              </button>
            ) : null}
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
              <CableIcon class="size-6" />
            </span>
            <div class="min-w-0">
              <p class="m-0 text-xs font-extrabold uppercase tracking-[0.16em] text-slate-500">
                내부 네트워크
              </p>
              <h2 class="mt-2 mb-0 text-xl font-black text-slate-950">LAN 및 DHCP 설정</h2>
              <p class="mt-2 mb-0 text-sm font-semibold leading-6 text-slate-600">
                상위 공유기와 다른 주소 대역을 사용해야 안정적으로 라우팅할 수 있습니다.
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

        <div class="mt-6 grid gap-5 lg:grid-cols-2">
          <div class="block">
            <span class="text-sm font-extrabold text-slate-800">공유기 IP 주소</span>
            <Ipv4OctetInput disabled={busy} onChange={updateIpAddress} value={ipAddress} />
          </div>

          <div class="block">
            <span class="text-sm font-extrabold text-slate-800">현재 LAN 대역</span>
            <div class="mt-2 min-h-11 rounded-xl border border-slate-200 bg-slate-50 px-4 py-3 text-sm font-bold text-slate-700">
              {data.lan.subnet}
            </div>
            <span class="mt-2 block text-xs text-slate-500">
              서브넷 마스크는 아래 고급 설정에서 변경할 수 있습니다.
            </span>
          </div>

          <DhcpHostInput
            disabled={busy}
            label="DHCP 시작 주소"
            lanAddress={ipAddress}
            onChange={updateDhcpStart}
            value={dhcpStart}
          />

          <DhcpHostInput
            disabled={busy}
            label="DHCP 종료 주소"
            lanAddress={ipAddress}
            onChange={updateDhcpEnd}
            value={dhcpEnd}
          />
        </div>

        <details class="mt-6 rounded-xl border border-slate-200 bg-slate-50 p-4">
          <summary class="cursor-pointer text-sm font-black text-slate-900">
            고급 DHCP 설정
          </summary>
          <div class="mt-5 grid gap-5 lg:grid-cols-2">
            <div class="block">
              <span class="text-sm font-extrabold text-slate-800">서브넷 마스크</span>
              <CustomSelect
                ariaLabel="서브넷 마스크"
                className="mt-2"
                disabled={busy}
                id="lan-prefix-length"
                onChange={(nextValue) => updatePrefixLength(Number(nextValue))}
                options={prefixOptions.map((prefix) => ({
                  value: String(prefix),
                  label: `/${prefix} · ${
                    prefix === data.lan.prefixLength
                      ? data.lan.netmask
                      : `CIDR /${prefix}`
                  }`,
                }))}
                value={String(prefixLength)}
                variant="emphasized"
              />
              <span class="mt-2 block text-xs text-slate-500">
                일반 가정용 네트워크는 /24 사용을 권장합니다.
              </span>
            </div>

            <div class="block">
              <span class="text-sm font-extrabold text-slate-800">DHCP 임대 시간</span>
              <CustomSelect
                ariaLabel="DHCP 임대 시간"
                className="mt-2"
                disabled={busy}
                id="lan-dhcp-lease-time"
                onChange={updateLeaseTime}
                options={leaseOptions.map(([value, label]) => ({ value, label }))}
                value={leaseTime}
                variant="emphasized"
              />
            </div>

            <label class="inline-flex min-h-11 items-center gap-3 text-sm font-extrabold text-slate-800 lg:col-span-2">
              <input
                checked={dhcpEnabled}
                class="size-5 accent-teal-700"
                disabled={busy}
                onChange={(event) => updateDhcpEnabled(event.currentTarget.checked)}
                type="checkbox"
              />
              SmartSafeHub DHCP 서버 사용
            </label>
            <p class="m-0 text-xs font-semibold leading-5 text-slate-500 lg:col-span-2">
              DHCP를 끄면 SmartSafeHub에 연결되는 장치에 IP 주소를 자동으로 할당하지 않습니다.
              별도의 DHCP 서버를 사용하는 고급 구성에서만 비활성화하세요.
            </p>
          </div>
        </details>

        {validationError ? (
          <p class="mt-5 mb-0 rounded-xl bg-red-50 px-4 py-3 text-sm font-bold text-red-800">
            {validationError}
          </p>
        ) : null}

        <div class="mt-6 flex flex-col gap-3 border-t border-slate-200 pt-5 sm:flex-row sm:items-center sm:justify-between">
          <p class="m-0 text-xs font-semibold leading-5 text-slate-500">
            주소가 바뀌면 현재 관리 페이지 연결이 종료되며 새 IP를 받아 다시 접속해야 합니다.
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
