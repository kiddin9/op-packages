import { useCallback, useEffect, useRef, useState } from 'preact/hooks';

import {
  fetchSafeShieldLicense,
  requestSafeShieldRefresh,
  setSafeShieldEnabled,
  setSafeShieldStatisticsEnabled,
  updateSafeShieldLicense,
} from '../api/safeshield';
import {
  fetchSmartSafeHubLicenseStatus,
  requestSmartSafeHubLicenseActivation,
} from '../api/smartsafehub';
import { RpcError } from '../api/rpc';
import { errorMessage } from '../utils/errors';

export type SafeShieldFeedbackTarget = 'global' | 'license';

export type SafeShieldAction =
  | 'enable'
  | 'disable'
  | 'refresh'
  | 'statistics-enable'
  | 'statistics-disable'
  | 'license-read'
  | 'license-update'
  | 'license-remove';

interface SafeShieldActionState {
  action: SafeShieldAction | null;
  error: string | null;
  feedbackTarget: SafeShieldFeedbackTarget | null;
  message: string | null;
}

const SUCCESS_FEEDBACK_TIMEOUT_MS = 4500;
const LICENSE_ACTIVATION_POLL_INTERVAL_MS = 1000;
const LICENSE_ACTIVATION_MAX_POLLS = 30;
const LICENSE_ACTIVATION_MAX_TRANSIENT_ERRORS = 2;

function licenseActivationErrorMessage(code: string | null): string {
  switch (code) {
    case 'license_invalid':
      return '유효하지 않은 라이선스 키입니다.';
    case 'safeshield_upgrade_required':
      return '라이선스를 등록하려면 SafeShield를 먼저 업데이트해 주세요.';
    case 'LICENSE_DEVICE_IDENTITY_UNAVAILABLE':
    case 'LICENSE_DEVICE_PROFILE_UNAVAILABLE':
      return '라이선스 등록에 필요한 장치 정보를 확인하지 못했습니다.';
    case 'LICENSE_LOCAL_UPDATE_FAILED':
      return '서버 등록은 완료했지만 이 기기에 라이선스 키를 적용하지 못했습니다.';
    case 'LICENSE_ACTIVATE_HTTP_FAILED':
      return '라이선스 서버에 연결하지 못했습니다.';
    default:
      return '라이선스 등록을 완료하지 못했습니다.';
  }
}

function wait(milliseconds: number): Promise<void> {
  return new Promise((resolve) => window.setTimeout(resolve, milliseconds));
}

function feedbackTargetForAction(action: SafeShieldAction): SafeShieldFeedbackTarget {
  return action.startsWith('license-') ? 'license' : 'global';
}

function isTransientLicenseStatusError(error: unknown): boolean {
  return (
    error instanceof RpcError &&
    ['RPC_TIMEOUT', 'NETWORK_ERROR', 'UBUS_10'].includes(error.code)
  );
}

export function useSafeShieldActions(
  refreshStatus: () => Promise<void>,
  refreshStatistics: () => Promise<void>,
) {
  const [state, setState] = useState<SafeShieldActionState>({
    action: null,
    error: null,
    feedbackTarget: null,
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
      setState({
        action,
        error: null,
        feedbackTarget: feedbackTargetForAction(action),
        message: null,
      });
    },
    [clearFeedbackTimer],
  );

  const showSuccessMessage = useCallback(
    (message: string, feedbackTarget: SafeShieldFeedbackTarget = 'global') => {
      clearFeedbackTimer();
      setState({ action: null, error: null, feedbackTarget, message });
      feedbackTimer.current = window.setTimeout(() => {
        feedbackTimer.current = null;
        setState((current) =>
          current.error !== null || current.action !== null
            ? current
            : { ...current, feedbackTarget: null, message: null },
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
          feedbackTarget: 'global',
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

        // Statistics-only configuration changes are reconciled synchronously,
        // so keep the busy indicator visible until the first statistics refresh
        // has observed the new runtime state.
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
          feedbackTarget: 'global',
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
      setState({ action: null, error: null, feedbackTarget: null, message: null });
      scheduleRefreshes([700, 2500, 6000, 12000]);
    } catch (error) {
      setState({
        action: null,
        error: errorMessage(error, 'SafeShield 작업을 수행하지 못했습니다.'),
        feedbackTarget: 'global',
        message: null,
      });
    }
  }, [beginAction, scheduleRefreshes]);

  const updateLicense = useCallback(
    async (licenseKey: string): Promise<boolean> => {
      const normalizedKey = licenseKey.trim();

      if (!normalizedKey) {
        clearFeedbackTimer();
        setState({
          action: null,
          error: '라이선스 키를 입력해 주세요.',
          feedbackTarget: 'license',
          message: null,
        });
        return false;
      }

      beginAction('license-update');

      try {
        const activation = await requestSmartSafeHubLicenseActivation(normalizedKey);
        if (!activation.accepted) {
          throw new Error('라이선스 등록 요청을 시작하지 못했습니다.');
        }

        let completed = false;
        let transientErrors = 0;
        for (let attempt = 0; attempt < LICENSE_ACTIVATION_MAX_POLLS; attempt += 1) {
          await wait(LICENSE_ACTIVATION_POLL_INTERVAL_MS);

          let status: Awaited<ReturnType<typeof fetchSmartSafeHubLicenseStatus>>;
          try {
            status = await fetchSmartSafeHubLicenseStatus();
          } catch (error) {
            if (
              isTransientLicenseStatusError(error) &&
              transientErrors < LICENSE_ACTIVATION_MAX_TRANSIENT_ERRORS
            ) {
              transientErrors += 1;
              continue;
            }
            throw error;
          }

          if (
            status.phase === 'active' &&
            status.lastActivatedAt >= activation.startedAt
          ) {
            completed = true;
            break;
          }

          if (
            status.phase === 'error' &&
            status.lastAttemptAt >= activation.startedAt
          ) {
            throw new Error(licenseActivationErrorMessage(status.lastErrorCode));
          }
        }

        if (!completed) {
          throw new Error(
            '라이선스 등록 결과 확인이 지연되고 있습니다. 잠시 후 상태를 다시 확인해 주세요.',
          );
        }

        showSuccessMessage('라이선스를 서버에 등록하고 이 기기에 적용했습니다.', 'license');
        await refreshStatus();
        scheduleRefreshes([800, 2500, 6000, 12000]);
        return true;
      } catch (error) {
        setState({
          action: null,
          error: errorMessage(error, '라이선스를 등록하지 못했습니다.'),
          feedbackTarget: 'license',
          message: null,
        });
        return false;
      }
    },
    [beginAction, clearFeedbackTimer, refreshStatus, scheduleRefreshes, showSuccessMessage],
  );

  const readLicense = useCallback(async (): Promise<string | null> => {
    beginAction('license-read');

    try {
      const result = await fetchSafeShieldLicense();
      setState({ action: null, error: null, feedbackTarget: null, message: null });
      return result.key;
    } catch (error) {
      setState({
        action: null,
        error: errorMessage(error, '라이선스 키를 불러오지 못했습니다.'),
        feedbackTarget: 'license',
        message: null,
      });
      return null;
    }
  }, [beginAction]);

  const removeLicense = useCallback(async (): Promise<boolean> => {
    beginAction('license-remove');

    try {
      const result = await updateSafeShieldLicense('');
      showSuccessMessage(
        result.changed ? '라이선스 키를 제거했습니다.' : '설정된 라이선스 키가 없습니다.',
        'license',
      );
      await refreshStatus();

      if (result.refresh.requested) {
        scheduleRefreshes([800, 2500, 6000, 12000]);
      }

      return true;
    } catch (error) {
      setState({
        action: null,
        error: errorMessage(error, '라이선스 키를 제거하지 못했습니다.'),
        feedbackTarget: 'license',
        message: null,
      });
      return false;
    }
  }, [beginAction, refreshStatus, scheduleRefreshes, showSuccessMessage]);

  const dismissFeedback = useCallback(() => {
    clearFeedbackTimer();
    setState((current) => ({
      ...current,
      error: null,
      feedbackTarget: null,
      message: null,
    }));
  }, [clearFeedbackTimer]);

  return {
    ...state,
    dismissFeedback,
    readLicense,
    refreshBlocklist,
    removeLicense,
    setEnabled,
    setStatisticsEnabled,
    updateLicense,
  };
}
