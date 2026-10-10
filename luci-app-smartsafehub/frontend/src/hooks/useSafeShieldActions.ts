import { useCallback, useEffect, useRef, useState } from 'preact/hooks';

import {
  requestSafeShieldRefresh,
  setSafeShieldEnabled,
  setSafeShieldStatisticsEnabled,
} from '../api/safeshield';
import { errorMessage } from '../utils/errors';

export type SafeShieldAction =
  | 'enable'
  | 'disable'
  | 'refresh'
  | 'statistics-enable'
  | 'statistics-disable';

interface SafeShieldActionState {
  action: SafeShieldAction | null;
  error: string | null;
  message: string | null;
}

const SUCCESS_FEEDBACK_TIMEOUT_MS = 4500;

export function useSafeShieldActions(
  refreshStatus: () => Promise<void>,
  refreshStatistics: () => Promise<void>,
) {
  const [state, setState] = useState<SafeShieldActionState>({
    action: null,
    error: null,
    message: null,
  });
  const statusTimers = useRef<number[]>([]);
  const statisticsTimers = useRef<number[]>([]);
  const feedbackTimer = useRef<number | null>(null);

  const clearStatusTimers = useCallback(() => {
    for (const timer of statusTimers.current) {
      window.clearTimeout(timer);
    }

    statusTimers.current = [];
  }, []);

  const clearStatisticsTimers = useCallback(() => {
    for (const timer of statisticsTimers.current) {
      window.clearTimeout(timer);
    }

    statisticsTimers.current = [];
  }, []);

  const clearFeedbackTimer = useCallback(() => {
    if (feedbackTimer.current !== null) {
      window.clearTimeout(feedbackTimer.current);
      feedbackTimer.current = null;
    }
  }, []);

  const beginAction = useCallback(
    (action: SafeShieldAction) => {
      clearFeedbackTimer();
      setState({ action, error: null, message: null });
    },
    [clearFeedbackTimer],
  );

  const showSuccessMessage = useCallback(
    (message: string) => {
      clearFeedbackTimer();
      setState({ action: null, error: null, message });
      feedbackTimer.current = window.setTimeout(() => {
        feedbackTimer.current = null;
        setState((current) =>
          current.error !== null || current.action !== null
            ? current
            : { ...current, message: null },
        );
      }, SUCCESS_FEEDBACK_TIMEOUT_MS);
    },
    [clearFeedbackTimer],
  );

  const scheduleRefreshes = useCallback(
    (delays: number[]) => {
      clearStatusTimers();

      statusTimers.current = delays.map((delay) =>
        window.setTimeout(() => {
          void refreshStatus();
        }, delay),
      );
    },
    [clearStatusTimers, refreshStatus],
  );

  const scheduleStatisticsRefreshes = useCallback(
    (delays: number[]) => {
      clearStatisticsTimers();

      statisticsTimers.current = delays.map((delay) =>
        window.setTimeout(() => {
          void refreshStatistics();
        }, delay),
      );
    },
    [clearStatisticsTimers, refreshStatistics],
  );

  useEffect(
    () => () => {
      clearStatusTimers();
      clearStatisticsTimers();
      clearFeedbackTimer();
    },
    [clearFeedbackTimer, clearStatisticsTimers, clearStatusTimers],
  );

  const setEnabled = useCallback(
    async (enabled: boolean) => {
      const action: SafeShieldAction = enabled ? 'enable' : 'disable';
      beginAction(action);

      try {
        const result = await setSafeShieldEnabled(enabled);
        showSuccessMessage(
          result.changed
            ? enabled
              ? 'SafeShield 보호 활성화 요청을 적용했습니다.'
              : 'SafeShield 보호 비활성화 요청을 적용했습니다.'
            : enabled
              ? 'SafeShield 보호가 이미 활성화 상태입니다.'
              : 'SafeShield 보호가 이미 비활성화 상태입니다.',
        );
        await refreshStatus();
        scheduleRefreshes([800, 2000, 5000]);
      } catch (error) {
        setState({
          action: null,
          error: errorMessage(error, 'SafeShield 작업을 수행하지 못했습니다.'),
          message: null,
        });
      }
    },
    [beginAction, refreshStatus, scheduleRefreshes, showSuccessMessage],
  );

  const setStatisticsEnabled = useCallback(
    async (enabled: boolean) => {
      const action: SafeShieldAction = enabled
        ? 'statistics-enable'
        : 'statistics-disable';
      beginAction(action);

      try {
        const result = await setSafeShieldStatisticsEnabled(enabled);

        await refreshStatistics();

        showSuccessMessage(
          result.changed
            ? result.reconciled
              ? enabled
                ? '차단 통계 수집을 활성화했습니다.'
                : '차단 통계 수집을 비활성화했습니다.'
              : '차단 통계 설정을 저장했습니다.'
            : enabled
              ? '차단 통계 수집이 이미 활성화되어 있습니다.'
              : '차단 통계 수집이 이미 비활성화되어 있습니다.',
        );

        if (result.changed) {
          scheduleStatisticsRefreshes([500, 1500]);
        }
      } catch (error) {
        setState({
          action: null,
          error: errorMessage(error, '차단 통계 설정을 변경하지 못했습니다.'),
          message: null,
        });
      }
    },
    [beginAction, refreshStatistics, scheduleStatisticsRefreshes, showSuccessMessage],
  );

  const refreshBlocklist = useCallback(async () => {
    beginAction('refresh');

    try {
      await requestSafeShieldRefresh();
      setState({ action: null, error: null, message: null });
      scheduleRefreshes([700, 2500, 6000, 12000]);
    } catch (error) {
      setState({
        action: null,
        error: errorMessage(error, 'SafeShield 작업을 수행하지 못했습니다.'),
        message: null,
      });
    }
  }, [beginAction, scheduleRefreshes]);

  const dismissFeedback = useCallback(() => {
    clearFeedbackTimer();
    setState((current) => ({
      ...current,
      error: null,
      message: null,
    }));
  }, [clearFeedbackTimer]);

  return {
    ...state,
    dismissFeedback,
    refreshBlocklist,
    setEnabled,
    setStatisticsEnabled,
  };
}
