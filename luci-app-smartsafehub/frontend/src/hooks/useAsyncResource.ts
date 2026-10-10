import { useCallback, useEffect, useRef, useState } from 'preact/hooks';

import { errorMessage } from '../utils/errors';

export interface AsyncResourceState<T> {
  data: T | null;
  error: string | null;
  loading: boolean;
  refreshing: boolean;
}

interface AsyncResourceOptions<T> {
  active?: boolean;
  fallbackError: string;
  loader: () => Promise<T>;
  pollInterval?: number | ((data: T | null) => number | null);
  refreshOnFocus?: boolean;
  refreshOnVisible?: boolean;
  staleTimeMs?: number;
}

export function useAsyncResource<T>({
  active = true,
  fallbackError,
  loader,
  pollInterval,
  refreshOnFocus = false,
  refreshOnVisible = false,
  staleTimeMs = 30_000,
}: AsyncResourceOptions<T>) {
  const [state, setState] = useState<AsyncResourceState<T>>({
    data: null,
    error: null,
    loading: active,
    refreshing: false,
  });
  const requested = useRef(false);
  const mounted = useRef(true);
  const inFlight = useRef<Promise<void> | null>(null);
  const lastAttemptAt = useRef<number | null>(null);
  const lastSuccessAt = useRef<number | null>(null);
  const failureCount = useRef(0);
  const RETRY_BASE_MS = 3_000;
  const RETRY_MAX_MS = 30_000;

  useEffect(() => {
    mounted.current = true;

    return () => {
      mounted.current = false;
    };
  }, []);

  const load = useCallback(
    (refreshing = false): Promise<void> => {
      if (inFlight.current) {
        return inFlight.current;
      }

      if (mounted.current) {
        setState((current) => ({
          ...current,
          error: null,
          loading: current.data === null,
          refreshing,
        }));
      }

      let request: Promise<void>;

      lastAttemptAt.current = Date.now();
      request = loader()
        .then((data) => {
          lastSuccessAt.current = Date.now();
          failureCount.current = 0;
          if (mounted.current) {
            setState({ data, error: null, loading: false, refreshing: false });
          }
        })
        .catch((error: unknown) => {
          failureCount.current += 1;
          if (mounted.current) {
            setState((current) => ({
              ...current,
              error: errorMessage(error, fallbackError),
              loading: false,
              refreshing: false,
            }));
          }
        })
        .finally(() => {
          if (inFlight.current === request) {
            inFlight.current = null;
          }
        });

      inFlight.current = request;
      return request;
    },
    [fallbackError, loader],
  );

  useEffect(() => {
    if (!active) {
      requested.current = false;
      return;
    }

    if (requested.current) {
      return;
    }

    requested.current = true;
    const fresh = state.data !== null && lastSuccessAt.current !== null &&
      Date.now() - lastSuccessAt.current < staleTimeMs;
    if (!fresh) void load();
  }, [active, load, staleTimeMs]);

  const interval =
    typeof pollInterval === 'function' ? pollInterval(state.data) : pollInterval;

  useEffect(() => {
    if (!active || interval == null || interval <= 0) {
      return;
    }

    let cancelled = false;
    let timer: number | null = null;

    const clearTimer = () => {
      if (timer !== null) {
        window.clearTimeout(timer);
        timer = null;
      }
    };

    const millisecondsUntilStale = () => {
      const now = Date.now();
      // Success timestamps determine freshness; failed attempts only throttle
      // retries so an unreachable router cannot cause a tight polling loop.
      if (failureCount.current > 0 && lastAttemptAt.current !== null) {
        const backoff = Math.min(RETRY_MAX_MS, RETRY_BASE_MS * 2 ** Math.min(failureCount.current - 1, 4));
        return Math.max(0, lastAttemptAt.current + backoff - now);
      }
      if (lastSuccessAt.current === null) return 0;
      return Math.max(0, lastSuccessAt.current + interval - now);
    };

    const schedule = () => {
      clearTimer();

      if (cancelled || document.visibilityState === 'hidden') {
        return;
      }

      timer = window.setTimeout(() => {
        timer = null;

        if (cancelled || document.visibilityState === 'hidden') {
          return;
        }

        const remaining = millisecondsUntilStale();
        if (remaining > 0) {
          schedule();
          return;
        }

        void load(false).finally(schedule);
      }, millisecondsUntilStale());
    };

    const refreshIfStale = () => {
      clearTimer();

      if (cancelled || document.visibilityState === 'hidden') {
        return;
      }

      if (millisecondsUntilStale() > 0) {
        schedule();
        return;
      }

      void load(false).finally(schedule);
    };

    const handleVisibilityChange = () => {
      if (document.visibilityState === 'hidden') {
        clearTimer();
        return;
      }

      if (refreshOnVisible) {
        // Reconnect immediately after returning to an update in progress.
        void load(false).finally(schedule);
      } else {
        refreshIfStale();
      }
    };

    const handleFocus = () => {
      refreshIfStale();
    };

    document.addEventListener('visibilitychange', handleVisibilityChange);
    if (refreshOnFocus) {
      window.addEventListener('focus', handleFocus);
    }
    schedule();

    return () => {
      cancelled = true;
      clearTimer();
      document.removeEventListener('visibilitychange', handleVisibilityChange);
      if (refreshOnFocus) {
        window.removeEventListener('focus', handleFocus);
      }
    };
  }, [active, interval, load, refreshOnFocus, refreshOnVisible]);

  const refresh = useCallback(() => load(true), [load]);
  const replaceData = useCallback((data: T) => {
    if (!mounted.current) {
      return;
    }

    lastSuccessAt.current = Date.now();
    failureCount.current = 0;
    setState((current) => ({
      ...current,
      data,
      error: null,
      loading: false,
      refreshing: false,
    }));
  }, []);

  return {
    ...state,
    refresh,
    replaceData,
  };
}
