// SPDX-License-Identifier: GPL-3.0-or-later
import type { FeaturedSensorView } from '../utils/featuredSensor';

interface Props { value: FeaturedSensorView | null }

/** Compact, read-only header view; never triggers a sensor wake-up or an RPC. */
export function FeaturedSensorIndicator({ value }: Props) {
  if (!value) return null;
  return <a class="ssh-header-sensor" data-stale={value.stale ? 'true' : 'false'}
    href="#smarthome" title={`${value.name} · ${value.measuredAt}${value.stale ? ' · 오래된 측정값' : ''}`}
    aria-label={`${value.name}: 온도 ${value.temperature}, 습도 ${value.humidity}. ${value.measuredAt}${value.stale ? ', 오래된 측정값' : ''}`}>
    <svg class="ssh-header-sensor-icon" aria-hidden="true" viewBox="0 0 24 24" fill="none"
      stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
      <path d="M14 14V5a3 3 0 0 0-6 0v9a5 5 0 1 0 6 0Z" />
      <path d="M11 11v7" />
    </svg>
    <span class="ssh-header-sensor-number">{value.temperature}</span>
    <span class="ssh-header-sensor-divider" aria-hidden="true" />
    <svg class="ssh-header-sensor-icon" aria-hidden="true" viewBox="0 0 24 24" fill="none"
      stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
      <path d="M12 3C9 7 6 10.4 6 14a6 6 0 0 0 12 0c0-3.6-3-7-6-11Z" />
    </svg>
    <span class="ssh-header-sensor-number">{value.humidity}</span>
  </a>;
}
