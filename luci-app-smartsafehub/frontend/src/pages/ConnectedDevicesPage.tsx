import type { ComponentChildren, JSX } from 'preact';
import { useMemo, useState } from 'preact/hooks';

import {
  CableIcon,
  ClockIcon,
  DevicesIcon,
  SearchIcon,
  WifiIcon,
} from '../components/Icons';
import { ErrorPanel, LoadingPanel } from '../components/StatePanels';
import type {
  ConnectedDevice,
  ConnectedDevicesSummary,
  DeviceConnection,
} from '../types/devices';

interface ConnectedDevicesPageProps {
  data: ConnectedDevicesSummary | null;
  error: string | null;
  loading: boolean;
  onRetry: () => void;
}

type DeviceFilter = 'all' | 'online' | 'wifi' | 'ethernet' | 'offline';

const FILTERS: Array<{ value: DeviceFilter; label: string }> = [
  { value: 'all', label: '전체' },
  { value: 'online', label: '현재 연결' },
  { value: 'wifi', label: 'Wi-Fi' },
  { value: 'ethernet', label: '유선/기타' },
  { value: 'offline', label: '최근 기기' },
];

const DEVICE_NAME_COLLATOR = new Intl.Collator('ko');
const LEASE_DATE_FORMATTER = new Intl.DateTimeFormat('ko-KR', {
  month: 'numeric',
  day: 'numeric',
  hour: '2-digit',
  minute: '2-digit',
});

function connectionLabel(connection: DeviceConnection): string {
  switch (connection) {
    case 'wifi':
      return 'Wi-Fi';
    case 'ethernet':
      return '유선/기타';
    default:
      return '연결 방식 미확인';
  }
}

function deviceName(device: ConnectedDevice): string {
  return device.hostname ?? device.ipv4Address ?? '이름 없는 기기';
}

function signalLabel(signal: number | null): string | null {
  if (signal === null) {
    return null;
  }
  if (signal >= -50) {
    return '매우 좋음';
  }
  if (signal >= -60) {
    return '좋음';
  }
  if (signal >= -70) {
    return '보통';
  }
  return '약함';
}

function formatDuration(seconds: number | null): string | null {
  if (seconds === null || seconds < 0) {
    return null;
  }

  const days = Math.floor(seconds / 86_400);
  const hours = Math.floor((seconds % 86_400) / 3_600);
  const minutes = Math.floor((seconds % 3_600) / 60);

  if (days > 0) {
    return `${days}일 ${hours}시간`;
  }
  if (hours > 0) {
    return `${hours}시간 ${minutes}분`;
  }
  return `${Math.max(minutes, 1)}분`;
}

function leaseLabel(device: ConnectedDevice): string | null {
  if (!device.leaseActive) {
    return null;
  }
  if (device.leaseExpiresAt === null) {
    return 'DHCP 임대 활성';
  }

  return `DHCP ${LEASE_DATE_FORMATTER.format(
    new Date(device.leaseExpiresAt * 1000),
  )}까지`;
}

function matchesFilter(device: ConnectedDevice, filter: DeviceFilter): boolean {
  switch (filter) {
    case 'online':
      return device.online;
    case 'wifi':
      return device.online && device.connection === 'wifi';
    case 'ethernet':
      return device.online && device.connection === 'ethernet';
    case 'offline':
      return !device.online;
    default:
      return true;
  }
}

function DeviceStatusBadge({ device }: { device: ConnectedDevice }) {
  return (
    <span
      class={`inline-flex items-center gap-2 rounded-full px-3 py-1.5 text-xs font-extrabold ring-1 ring-inset ${
        device.online
          ? 'bg-emerald-50 text-emerald-700 ring-emerald-200'
          : 'bg-slate-100 text-slate-600 ring-slate-200'
      }`}
    >
      <span
        class={`size-2 rounded-full ${device.online ? 'bg-emerald-500' : 'bg-slate-400'}`}
      />
      {device.online ? '현재 연결' : '최근 임대'}
    </span>
  );
}

function DeviceCard({ device }: { device: ConnectedDevice }) {
  const signal = signalLabel(device.signalDbm);
  const connected = formatDuration(device.connectedSeconds);
  const lease = leaseLabel(device);

  return (
    <article class="rounded-2xl border border-slate-200 bg-white p-4 shadow-sm shadow-slate-900/5 sm:p-5">
      <div class="flex min-w-0 flex-col items-start gap-4 sm:flex-row sm:justify-between">
        <div class="flex min-w-0 items-start gap-3">
          <span
            class={`grid size-11 shrink-0 place-items-center rounded-xl ${
              device.connection === 'wifi'
                ? 'bg-teal-50 text-teal-700'
                : device.connection === 'ethernet'
                  ? 'bg-blue-50 text-blue-700'
                  : 'bg-slate-100 text-slate-600'
            }`}
          >
            {device.connection === 'wifi' ? (
              <WifiIcon class="size-6" />
            ) : device.connection === 'ethernet' ? (
              <CableIcon class="size-6" />
            ) : (
              <DevicesIcon class="size-6" />
            )}
          </span>
          <div class="min-w-0">
            <h3 class="m-0 break-words text-base font-extrabold text-slate-950">
              {deviceName(device)}
            </h3>
            <p class="mt-1 mb-0 break-all font-mono text-xs leading-5 text-slate-500">
              {device.mac}
            </p>
          </div>
        </div>
        <span class="shrink-0 self-start"><DeviceStatusBadge device={device} /></span>
      </div>

      <dl class="mt-5 grid gap-3 text-sm sm:grid-cols-2">
        <div class="rounded-xl bg-slate-50 p-3.5">
          <dt class="text-xs font-bold text-slate-500">IP 주소</dt>
          <dd class="mt-1.5 mb-0 ml-0 font-extrabold text-slate-900">
            {device.ipv4Address ?? '확인되지 않음'}
          </dd>
        </div>
        <div class="rounded-xl bg-slate-50 p-3.5">
          <dt class="text-xs font-bold text-slate-500">연결 방식</dt>
          <dd class="mt-1.5 mb-0 ml-0 font-extrabold text-slate-900">
            {connectionLabel(device.connection)}
          </dd>
        </div>
      </dl>

      <div class="mt-4 flex flex-wrap gap-2 text-xs font-bold text-slate-600">
        {device.ssid ? (
          <span class="rounded-full bg-teal-50 px-3 py-1.5 text-teal-800">
            {device.ssid}{device.bandLabel ? ` · ${device.bandLabel}` : ''}
          </span>
        ) : null}
        {signal ? (
          <span class="rounded-full bg-slate-100 px-3 py-1.5">
            신호 {signal} · {device.signalDbm} dBm
          </span>
        ) : null}
        {connected ? (
          <span class="rounded-full bg-slate-100 px-3 py-1.5">
            연결 {connected}
          </span>
        ) : null}
        {lease ? (
          <span class="rounded-full bg-slate-100 px-3 py-1.5">{lease}</span>
        ) : null}
        {device.interface ? (
          <span class="rounded-full bg-slate-100 px-3 py-1.5">
            {device.interface}
          </span>
        ) : null}
      </div>
    </article>
  );
}

export function ConnectedDevicesPage({
  data,
  error,
  loading,
  onRetry,
}: ConnectedDevicesPageProps) {
  const [query, setQuery] = useState('');
  const [filter, setFilter] = useState<DeviceFilter>('all');

  const devices = useMemo(() => {
    if (!data) {
      return [];
    }

    const normalized = query.trim().toLocaleLowerCase();
    return [...data.devices]
      .filter((device) => matchesFilter(device, filter))
      .filter((device) => {
        if (!normalized) {
          return true;
        }

        return [device.hostname, device.ipv4Address, device.mac, device.ssid]
          .filter((value): value is string => Boolean(value))
          .some((value) => value.toLocaleLowerCase().includes(normalized));
      })
      .sort((left, right) => {
        if (left.online !== right.online) {
          return left.online ? -1 : 1;
        }
        if (left.connection !== right.connection) {
          return left.connection === 'wifi' ? -1 : 1;
        }
        return DEVICE_NAME_COLLATOR.compare(deviceName(left), deviceName(right));
      });
  }, [data, filter, query]);

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
      <section aria-label="연결 기기 요약" class="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <SummaryCard
          description={`${data.totals.offline}대는 최근 DHCP 임대에서 확인`}
          icon={<DevicesIcon class="size-6" />}
          label="확인된 기기"
          value={data.totals.known}
        />
        <SummaryCard
          description="Wi-Fi 또는 ARP에서 현재 확인됨"
          icon={<ClockIcon class="size-6" />}
          label="현재 연결"
          value={data.totals.online}
        />
        <SummaryCard
          description="무선 AP에 연결된 기기"
          icon={<WifiIcon class="size-6" />}
          label="Wi-Fi"
          value={data.totals.wireless}
        />
        <SummaryCard
          description="LAN ARP에서 확인된 비무선 기기"
          icon={<CableIcon class="size-6" />}
          label="유선/기타"
          value={data.totals.ethernet}
        />
      </section>

      <section class="mt-5 rounded-2xl border border-slate-200 bg-white p-4 shadow-sm shadow-slate-900/5 sm:p-5">
        <div class="flex flex-col gap-4 lg:flex-row lg:items-center lg:justify-between">
          <div>
            <p class="m-0 text-xs font-bold uppercase tracking-[0.16em] text-slate-500">
              Device inventory
            </p>
            <h2 class="mt-2 mb-0 text-xl font-extrabold text-slate-950">
              기기 목록
            </h2>
          </div>
          <label class="relative block w-full lg:max-w-sm">
            <span class="sr-only">기기 검색</span>
            <span class="pointer-events-none absolute inset-y-0 left-0 flex w-11 items-center justify-center text-slate-400">
              <SearchIcon class="size-5" />
            </span>
            <input
              class="min-h-11 w-full rounded-xl border-2 border-slate-300 bg-slate-50 py-2.5 pr-4 pl-11 text-sm font-semibold text-slate-950 shadow-inner outline-none transition placeholder:text-slate-400 focus:border-teal-500 focus:bg-white focus:ring-4 focus:ring-teal-100"
              onInput={(event: JSX.TargetedEvent<HTMLInputElement>) =>
                setQuery(event.currentTarget.value)
              }
              placeholder="이름, IP, MAC 또는 SSID 검색"
              type="search"
              value={query}
            />
          </label>
        </div>

        <div class="ssh-touch-scroll mt-4 flex gap-2 overflow-x-auto pb-1" role="group" aria-label="기기 필터">
          {FILTERS.map((item) => (
            <button
              aria-pressed={filter === item.value}
              class={`min-h-10 shrink-0 rounded-xl border px-4 py-2 text-sm font-extrabold transition ${
                filter === item.value
                  ? 'border-teal-700 bg-teal-700 text-white'
                  : 'border-slate-200 bg-white text-slate-600 hover:bg-slate-50 hover:text-slate-950'
              }`}
              key={item.value}
              onClick={() => setFilter(item.value)}
              type="button"
            >
              {item.label}
            </button>
          ))}
        </div>
      </section>

      {devices.length ? (
        <section aria-live="polite" class="mt-5 grid gap-4 lg:grid-cols-2">
          {devices.map((device) => (
            <DeviceCard device={device} key={device.id} />
          ))}
        </section>
      ) : (
        <section class="mt-5 rounded-2xl border border-dashed border-slate-300 bg-white p-5 text-center sm:p-8">
          <DevicesIcon class="mx-auto size-10 text-slate-400" />
          <h2 class="mt-4 mb-0 text-lg font-extrabold text-slate-950">
            조건에 맞는 기기가 없습니다
          </h2>
          <p class="mt-2 mb-0 text-sm text-slate-600">
            검색어 또는 필터를 변경해 주세요.
          </p>
        </section>
      )}

      <p class="mt-5 mb-0 rounded-xl bg-slate-100 px-4 py-3 text-xs leading-5 text-slate-600">
        유선/기타 상태는 ARP 테이블을 기준으로 하며, 최근 DHCP 임대는 기기가 연결 해제된 뒤에도 일정 시간 남을 수 있습니다.
      </p>
    </>
  );
}

function SummaryCard({
  description,
  icon,
  label,
  value,
}: {
  description: string;
  icon: ComponentChildren;
  label: string;
  value: number;
}) {
  return (
    <article class="rounded-2xl border border-slate-200 bg-white p-4 shadow-sm shadow-slate-900/5 sm:p-5">
      <div class="flex items-start justify-between gap-4">
        <div>
          <p class="m-0 text-xs font-bold uppercase tracking-[0.14em] text-slate-500">
            {label}
          </p>
          <p class="mt-3 mb-0 text-3xl font-black tracking-tight text-slate-950">
            {value}
          </p>
        </div>
        <span class="grid size-11 shrink-0 place-items-center rounded-xl bg-teal-50 text-teal-700">
          {icon}
        </span>
      </div>
      <p class="mt-3 mb-0 text-xs leading-5 text-slate-500">{description}</p>
    </article>
  );
}
