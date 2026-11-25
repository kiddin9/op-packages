// SPDX-License-Identifier: GPL-3.0-or-later
import { useCallback, useEffect, useRef, useState } from 'preact/hooks';

import { fetchFeaturedSensorSettings, saveFeaturedSensorSettings } from '../api/smartsafehub';
import { getJarbisSensorState } from '../api/jarbis';
import type { JarbisDevice, JarbisSensorState } from '../types/jarbis';
import { featuredSensorView, selectFeaturedSensor } from '../utils/featuredSensor';
import { useAsyncResource } from './useAsyncResource';

const SENSOR_CACHE_POLL_MS = 300_000;

export function useFeaturedSensor(devices: readonly JarbisDevice[] | null,
  smartHomeVisible: boolean) {
  // If the user has no active sensor, there are zero preference RPCs, zero
  // sensor RPCs and zero sensor timers. The device list itself is read once.
  const fallback = selectFeaturedSensor(devices, null);
  const settings = useAsyncResource({
    active: fallback !== null,
    fallbackError: '대표 센서 설정을 확인하지 못했습니다.',
    loader: fetchFeaturedSensorSettings,
    staleTimeMs: 300_000,
  });
  // Avoid briefly displaying the wrong sensor while its saved choice loads.
  const selected = fallback && !settings.data && !settings.error
    ? null : selectFeaturedSensor(devices, settings.data?.sensorId);
  const selectedId = selected?.id ?? null;
  const [readings, setReadings] = useState<Record<string, JarbisSensorState>>({});
  const checkedAt = useRef<Record<string, number>>({});

  const acceptReading = useCallback((reading: JarbisSensorState) => {
    if (!reading || typeof reading.id !== 'string' || !reading.observed) return;
    checkedAt.current[reading.id] = Date.now();
    setReadings(previous => ({ ...previous, [reading.id]: reading }));
  }, []);

  useEffect(() => {
    if (!selectedId || smartHomeVisible) return;
    let cancelled = false;
    let running = false;
    let timer: number | null = null;

    const clear = () => {
      if (timer !== null) window.clearTimeout(timer);
      timer = null;
    };
    const check = () => {
      clear();
      if (cancelled || document.visibilityState === 'hidden' || running) return;
      const remaining = Math.max(0, (checkedAt.current[selectedId] ?? 0) + SENSOR_CACHE_POLL_MS - Date.now());
      if (remaining) {
        timer = window.setTimeout(check, remaining);
        return;
      }
      running = true;
      void getJarbisSensorState(selectedId, 'low').then(reading => {
        if (!cancelled && reading.id === selectedId) acceptReading(reading);
      }).catch(() => {
        // Retain the last verified reading. A sleeping sensor is not offline.
      }).finally(() => {
        running = false;
        // Also back off on errors; an unreachable broker must not spin.
        if (!cancelled) {
          checkedAt.current[selectedId] = Date.now();
          check();
        }
      });
    };
    const visibility = () => {
      if (document.visibilityState === 'hidden') clear();
      else check();
    };
    check();
    document.addEventListener('visibilitychange', visibility);
    return () => {
      cancelled = true;
      clear();
      document.removeEventListener('visibilitychange', visibility);
    };
  }, [selectedId, smartHomeVisible, acceptReading]);

  const select = useCallback(async (id: string) => {
    if (!selectFeaturedSensor(devices, id) || selectFeaturedSensor(devices, id)?.id !== id) {
      throw new Error('대표 센서로 사용할 수 없는 기기입니다.');
    }
    const saved = await saveFeaturedSensorSettings(id);
    if (saved.sensorId !== id) throw new Error('대표 센서 저장 결과를 확인할 수 없습니다.');
    settings.replaceData(saved);
  }, [devices, settings.replaceData]);

  // Deleting or disabling the selected sensor falls back immediately; the
  // persisted preference is repaired once rather than on each page render.
  useEffect(() => {
    if (!settings.data || !selectedId || !settings.data.sensorId || settings.data.sensorId === selectedId) return;
    let cancelled = false;
    void saveFeaturedSensorSettings(selectedId).then(result => {
      if (!cancelled && result.sensorId === selectedId) settings.replaceData(result);
    }).catch(() => {});
    return () => { cancelled = true; };
  }, [selectedId, settings.data?.sensorId, settings.replaceData]);

  return {
    selectedId,
    view: featuredSensorView(selected, selectedId ? readings[selectedId] : null, Math.floor(Date.now() / 1000)),
    acceptReading,
    select,
  };
}
