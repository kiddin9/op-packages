// SPDX-License-Identifier: GPL-3.0-or-later
import type { JarbisSensorState } from '../types/jarbis';
const STALE_AFTER_SECONDS = 3 * 60 * 60;

/** Avoid displaying stale, impossible, or unverified values as live readings. */
export function sensorReading(value: number | null | undefined, unit: '°C' | '%', min: number, max: number): string {
  if (typeof value !== 'number' || !Number.isFinite(value) || value < min || value > max) return '—';
  return `${unit === '°C' ? value.toFixed(1) : Math.round(value)} ${unit}`;
}

export function sensorReportLabel(lastSeen: number | null | undefined, nowSeconds: number): { label: string; stale: boolean } {
  if (typeof lastSeen !== 'number' || !Number.isSafeInteger(lastSeen) || lastSeen <= 0 || lastSeen > nowSeconds + 60) {
    return { label: '측정 시각 미확인', stale: true };
  }
  const date = new Date(lastSeen * 1000);
  if (Number.isNaN(date.getTime())) return { label: '측정 시각 미확인', stale: true };
  return { label: `마지막 측정 ${date.toLocaleString('ko-KR')}`, stale: nowSeconds - lastSeen > STALE_AFTER_SECONDS };
}

/** A sleeping battery sensor is an expected pairing state, not a network outage. */
export function isSensorWakeRequired(error: unknown): boolean {
  return typeof error === 'object' && error !== null && 'code' in error &&
    (error as { code?: unknown }).code === 'WAKE_REQUIRED';
}

/** Only a recent, validated MQTT report proves that Jarbis is receiving data.
 * An older backup or HTTP-only reading must not be treated as MQTT pairing.
 */
export function hasRecentSensorMqttReading(
  state: JarbisSensorState | null | undefined, id: string, nowSeconds: number,
): boolean {
  if (!state || state.id !== id || !state.observed || state.source !== 'mqtt' ||
    sensorReportLabel(state.lastSeen, nowSeconds).stale) return false;
  return [state.temperatureC, state.humidityPercent, state.batteryPercent].some(value =>
    typeof value === 'number' && Number.isFinite(value));
}
