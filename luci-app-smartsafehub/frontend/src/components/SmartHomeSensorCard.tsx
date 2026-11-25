// SPDX-License-Identifier: GPL-3.0-or-later
import { AlertIcon, ReloadIcon, ThermometerIcon } from './Icons';
import { SmartHomeRoomPicker } from './SmartHomeRoomPicker';
import type { HomeRoom } from '../utils/smartHomeGroups';
import type { JarbisDevice, JarbisSensorState } from '../types/jarbis';
import { sensorReading, sensorReportLabel } from '../utils/shellySensor';

const secondaryButton = 'inline-flex min-h-10 items-center justify-center gap-2 rounded-xl border border-slate-200 bg-white px-3 py-2 text-sm font-bold text-slate-700 transition hover:bg-slate-50 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-teal-600 disabled:cursor-not-allowed disabled:opacity-50';
const dangerButton = 'inline-flex min-h-10 items-center justify-center rounded-xl border border-rose-200 px-3 py-2 text-sm font-bold text-rose-700 transition hover:bg-rose-50 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-rose-600 disabled:cursor-not-allowed disabled:opacity-50';

interface Props {
  device: JarbisDevice;
  state: JarbisSensorState | undefined;
  checking: boolean;
  busy: boolean;
  supported: boolean;
  quickPair: boolean;
  compact?: boolean;
  roomsSupported?: boolean;
  onRoomChange?: (room: HomeRoom) => void;
  featured?: boolean;
  onMakeFeatured?: () => void;
  onManageMenuRef: (element: HTMLDetailsElement | null) => void;
  onConnect: () => void;
  onRefresh: () => void;
  onToggle: () => void;
  onRemove: () => void;
}

export function SmartHomeSensorCard({ device, state, checking, busy, supported, quickPair, compact = false, roomsSupported = false, onRoomChange, featured = false, onMakeFeatured, onManageMenuRef, onConnect, onRefresh, onToggle, onRemove }: Props) {
  const report = sensorReportLabel(state?.lastSeen, Math.floor(Date.now() / 1000));
  const observed = state?.observed === true && state.id === device.id && !report.label.includes('미확인');
  const stateLabel = !device.enabled ? '사용 중지' : !supported ? 'Jarbis 업데이트 필요' : !observed ? '첫 측정 대기'
    : report.stale ? '오래된 측정값' : '최근 측정값';
  const stateTone = !device.enabled || !supported ? 'inactive' : observed && !report.stale ? 'recent' : 'pending';

  return <article class="ssh-home-device-card ssh-home-sensor" data-density={compact ? 'compact' : 'detail'} aria-label={`${device.name} 온습도 센서`}>
    <div class="ssh-home-sensor-header">
      <span class="ssh-home-device-icon" aria-hidden="true"><ThermometerIcon class="size-5" /></span>
      <div class="min-w-0 flex-1">
        <div class="flex min-w-0 flex-wrap items-center gap-2">
          <h3 class="ssh-home-device-title" title={device.name}>{device.name}</h3>
          <span class="ssh-home-status-pill" data-tone={stateTone}>{stateLabel}</span>
        </div>
        <p class="ssh-home-device-subtitle">Wi-Fi 온습도 센서</p>
      </div>
    </div>

    <div class="ssh-home-sensor-body">
      <div class="ssh-home-sensor-metrics" aria-label="최근 측정 정보">
        <div class="ssh-home-sensor-metric" data-kind="temperature">
          <span class="ssh-home-metric-label">온도</span>
          <strong class="ssh-home-metric-number">{observed ? sensorReading(state?.temperatureC, '°C', -40, 125) : '—'}</strong>
        </div>
        <div class="ssh-home-sensor-metric" data-kind="humidity">
          <span class="ssh-home-metric-label">습도</span>
          <strong class="ssh-home-metric-number">{observed ? sensorReading(state?.humidityPercent, '%', 0, 100) : '—'}</strong>
        </div>
        <div class="ssh-home-sensor-metric" data-kind="battery">
          <span class="ssh-home-metric-label">배터리</span>
          <strong class="ssh-home-metric-number">{observed ? sensorReading(state?.batteryPercent, '%', 0, 100) : '—'}</strong>
        </div>
      </div>
      <div class="ssh-home-sensor-last-seen">
        <span class="ssh-home-sensor-dot" aria-hidden="true" />
        <span>{observed ? report.label : '아직 첫 측정값을 받지 못했습니다.'}{observed && report.stale ? ' · 최신 값이 아닙니다' : ''}</span>
      </div>

      {!observed && supported && quickPair && device.enabled ? <div class="ssh-home-sensor-help">
        <div class="flex items-start gap-2">
          <AlertIcon class="mt-0.5 size-4 shrink-0" />
          <div><strong class="block text-sm">연결을 마무리해 주세요.</strong>
            센서 버튼을 짧게 누른 후 <strong>연결 다시 시도</strong>를 선택하면 첫 측정값을 확인할 수 있습니다.
          </div>
        </div>
        <button class={`${secondaryButton} mt-3`} type="button" disabled={busy} onClick={onConnect}>연결 다시 시도</button>
      </div> : null}
      {!compact ? <p class="ssh-home-sensor-note">배터리 센서는 측정 후 절전합니다. 마지막 수신값을 표시하며 새로고침으로 센서를 깨우지는 않습니다.</p> : null}
      {!supported ? <p class="ssh-home-sensor-help">설치된 Jarbis에 Shelly 센서 상태 조회 기능이 없습니다. 지원 버전으로 업데이트해 주세요.</p> : null}

      <div class="ssh-home-card-actions">
        <button class={secondaryButton} type="button" disabled={busy || checking || !device.enabled || !supported} onClick={onRefresh}>
          <ReloadIcon class="size-4" />{checking ? '확인 중…' : '측정값 다시 확인'}
        </button>
        <details ref={onManageMenuRef} class="relative z-20 min-w-0 text-sm text-slate-600">
          <summary class={`${secondaryButton} cursor-pointer list-none [&::-webkit-details-marker]:hidden`}>관리</summary>
          <div class="absolute left-0 top-full z-30 mt-2 flex w-64 max-w-[calc(100vw-3rem)] flex-col gap-2 rounded-xl border border-slate-200 bg-white p-3 shadow-xl">
            <p class="m-0 break-all text-xs text-slate-500">기기 ID: {device.id}</p>
            <SmartHomeRoomPicker room={device.room} supported={roomsSupported} disabled={busy} onChange={room => onRoomChange?.(room)} />
            {onMakeFeatured && device.enabled ? <button class={secondaryButton} type="button"
              aria-pressed={featured} disabled={busy || featured} onClick={onMakeFeatured}>
              {featured ? '헤더에 표시 중' : '대표 센서로 지정'}
            </button> : null}
            <button class={secondaryButton} type="button" disabled={busy} onClick={onToggle}>{device.enabled ? '기기 사용 중지' : '기기 다시 사용'}</button>
            <button class={dangerButton} type="button" disabled={busy} onClick={onRemove}>기기 삭제</button>
          </div>
        </details>
      </div>
    </div>
  </article>;
}
