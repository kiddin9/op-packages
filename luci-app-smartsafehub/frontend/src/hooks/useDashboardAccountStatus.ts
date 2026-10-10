import { useEffect, useRef, useState } from 'preact/hooks';
import { fetchDeviceRegistrationStatus } from '../api/smartsafehub';

const ACCOUNT_STATUS_INTERVAL_MS = 60_000;

// Router-local status only; never contact Hub from the dashboard/sidebar.
export function useDashboardAccountStatus(
  accountRoute: boolean,
  accountPageRegistered: boolean | null,
): boolean | null {
  const [registered, setRegistered] = useState<boolean | null>(null);
  const generation = useRef(0);

  // The account page has fresher, locally confirmed state (5s polling or a
  // pairing/refresh result). Reflect it immediately instead of waiting up to
  // 60 seconds for the navigation's independent poll.
  useEffect(() => {
    if (accountRoute && accountPageRegistered !== null) {
      generation.current += 1;
      setRegistered(accountPageRegistered);
    }
  }, [accountRoute, accountPageRegistered]);

  useEffect(() => {
    if (accountRoute) return; // Account page owns the fresh local status.

    let cancelled = false;
    let timer: number | null = null;
    let inFlight = false;
    let lastAttempt = 0;

    const check = async (force = false) => {
      if (cancelled || document.visibilityState === 'hidden' || inFlight ||
          (!force && Date.now() - lastAttempt < ACCOUNT_STATUS_INTERVAL_MS)) return;
      inFlight = true;
      const requestGeneration = ++generation.current;
      lastAttempt = Date.now();
      try {
        const status = await fetchDeviceRegistrationStatus();
        if (!cancelled && generation.current === requestGeneration) setRegistered(status.accountRegistered);
      } catch {
        // Unknown is not disconnected: retain last known state if available.
        if (!cancelled && generation.current === requestGeneration) setRegistered((previous) => previous ?? null);
      } finally {
        inFlight = false;
      }
    };

    const onVisibility = () => {
      if (document.visibilityState === 'visible') void check();
    };
    const onFocus = () => void check();
    void check(true);
    timer = window.setInterval(() => void check(), ACCOUNT_STATUS_INTERVAL_MS);
    document.addEventListener('visibilitychange', onVisibility);
    window.addEventListener('focus', onFocus);
    return () => {
      cancelled = true;
      generation.current += 1;
      if (timer !== null) window.clearInterval(timer);
      document.removeEventListener('visibilitychange', onVisibility);
      window.removeEventListener('focus', onFocus);
    };
  }, [accountRoute]);

  return registered;
}
