// SPDX-License-Identifier: GPL-3.0-or-later
import type { JarbisDevice, JarbisSensorState } from '../types/jarbis';
import { sensorReading, sensorReportLabel } from './shellySensor.ts';

export interface FeaturedSensorView {
  id: string;
  name: string;
  temperature: string;
  humidity: string;
  measuredAt: string;
  stale: boolean;
}

/** Stable order comes from Jarbis; only explicitly enabled sensors qualify. */
export function selectFeaturedSensor(devices: readonly JarbisDevice[] | null | undefined,
  preferredId: string | null | undefined): JarbisDevice | null {
  const enabled = (devices ?? []).filter(device => device.protocol === 'shelly_htg3' && device.enabled);
  return enabled.find(device => device.id === preferredId) ?? enabled[0] ?? null;
}

/** Do not display an unverified, wrong-device, future-dated or impossible reading. */
export function featuredSensorView(device: JarbisDevice | null,
  state: JarbisSensorState | null | undefined, nowSeconds: number): FeaturedSensorView | null {
  if (!device || !state || !state.observed || state.id !== device.id) return null;
  const last = sensorReportLabel(state.lastSeen, nowSeconds);
  if (last.label === '측정 시각 미확인') return null;
  const temperature = sensorReading(state.temperatureC, '°C', -40, 125);
  const humidity = sensorReading(state.humidityPercent, '%', 0, 100);
  if (temperature === '—' && humidity === '—') return null;
  return { id: device.id, name: device.name, temperature, humidity,
    measuredAt: last.label, stale: last.stale };
}
