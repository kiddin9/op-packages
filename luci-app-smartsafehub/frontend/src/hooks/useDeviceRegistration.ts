import { useCallback, useEffect, useMemo, useRef, useState } from 'preact/hooks';

import {
  fetchDeviceRegistrationStatus,
  refreshDeviceRegistrationStatus,
  requestDevicePairingCode,
  type DeviceRegistrationStatus,
} from '../api/smartsafehub';

const PAIRING_POLL_INTERVAL_MS = 5_000;
const LOCAL_STATUS_POLL_INTERVAL_MS = 5_000;

function pairingStillValid(status: DeviceRegistrationStatus | null): boolean {
  if (!status?.pairingCode || status.accountRegistered === true) {
    return false;
  }

  if (!status.pairingExpiresAt) {
    return true;
  }

  const expiresAt = Date.parse(status.pairingExpiresAt);
  return !Number.isFinite(expiresAt) || expiresAt > Date.now();
}

export function useDeviceRegistration(enabled: boolean) {
  const [data, setData] = useState<DeviceRegistrationStatus | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [syncError, setSyncError] = useState<string | null>(null);
  const [loading, setLoading] = useState(enabled);
  const [refreshing, setRefreshing] = useState(false);
  const [pairingBusy, setPairingBusy] = useState(false);
  const refreshPromiseRef = useRef<Promise<DeviceRegistrationStatus | null> | null>(null);
  const requestGeneration = useRef(0);
  const mounted = useRef(true);
  const commitStatus = useCallback((status: DeviceRegistrationStatus, generation: number) => {
    if (!mounted.current || generation !== requestGeneration.current) return false;
    setData(status);
    setError(null);
    setLoading(false);
    return true;
  }, []);

  const refresh = useCallback((): Promise<DeviceRegistrationStatus | null> => {
    if (!enabled) {
      return Promise.resolve(null);
    }

    if (refreshPromiseRef.current) {
      return refreshPromiseRef.current;
    }

    const generation = ++requestGeneration.current;
    setSyncError(null);
    setRefreshing(true);
    const task = (async () => {
      try {
        const status = await refreshDeviceRegistrationStatus();
        if (commitStatus(status, generation)) setSyncError(null);
        return status;
      }
      catch {
        // Hub synchronization is best-effort for this local page. The device
        // helper may already have persisted a newer account state, so recover
        // that state without blocking or rolling back the visible UI.
        const localStatus = await fetchDeviceRegistrationStatus().catch(() => null);
        if (localStatus) {
          commitStatus(localStatus, generation);
        }
        if (mounted.current && generation === requestGeneration.current)
          setSyncError('SmartSafeHub 서버의 최신 상태 확인이 지연되고 있습니다.');
        return localStatus;
      }
      finally {
        if (mounted.current) setRefreshing(false);
        refreshPromiseRef.current = null;
      }
    })();

    refreshPromiseRef.current = task;
    return task;
  }, [enabled, commitStatus]);

  const requestPairing = useCallback(async () => {
    const generation = ++requestGeneration.current;
    setPairingBusy(true);
    try {
      const status = await requestDevicePairingCode();
      if (commitStatus(status, generation)) setSyncError(null);
      return status;
    }
    finally {
      setPairingBusy(false);
    }
  }, [commitStatus]);

  useEffect(() => {
    if (!enabled) {
      return;
    }

    let active = true;
    mounted.current = true;
    const generation = ++requestGeneration.current;
    setLoading(true);
    setError(null);
    setSyncError(null);

    // Render the router-local state first. Hub availability must not gate the
    // SmartSafeHub account page; the cloud check continues in the background.
    void fetchDeviceRegistrationStatus()
      .then((localStatus) => {
        if (!active) return;
        if (commitStatus(localStatus, generation)) setLoading(false);
        void refresh();
      })
      .catch(() => {
        if (!active) return;
        if (generation === requestGeneration.current) {
          setError('기기 등록 상태를 확인하지 못했습니다.');
          setLoading(false);
        }
        void refresh();
      });

    return () => {
      active = false;
      requestGeneration.current += 1;
    };
  }, [enabled, refresh, commitStatus]);

  useEffect(() => {
    if (!enabled) {
      return;
    }

    let active = true;
    const timer = window.setInterval(() => {
      if (document.visibilityState === 'hidden' || refreshPromiseRef.current) return;
      const generation = ++requestGeneration.current;
      void fetchDeviceRegistrationStatus()
        .then((localStatus) => {
          if (!active) return;
          if (commitStatus(localStatus, generation)) setSyncError(null);
        })
        .catch(() => {
          // The periodic local read is best-effort. The initial load and
          // explicit refresh paths remain responsible for visible errors.
        });
    }, LOCAL_STATUS_POLL_INTERVAL_MS);

    return () => {
      active = false;
      window.clearInterval(timer);
    };
  }, [enabled, commitStatus]);

  useEffect(() => () => { mounted.current = false; }, []);

  const shouldPoll = useMemo(() => pairingStillValid(data), [data]);

  useEffect(() => {
    if (!enabled || !shouldPoll) {
      return;
    }

    let active = true;
    let timer = 0;

    const poll = async () => {
      await refresh();
      if (active) {
        timer = window.setTimeout(() => void poll(), PAIRING_POLL_INTERVAL_MS);
      }
    };

    timer = window.setTimeout(() => void poll(), PAIRING_POLL_INTERVAL_MS);
    return () => {
      active = false;
      window.clearTimeout(timer);
    };
  }, [enabled, refresh, shouldPoll]);

  return {
    data,
    error,
    loading,
    pairingBusy,
    refresh,
    refreshing,
    requestPairing,
    syncError,
  };
}
