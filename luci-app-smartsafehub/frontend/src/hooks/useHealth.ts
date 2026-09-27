import { useCallback, useRef, useState } from 'preact/hooks';

import {
  fetchHealthStatus,
  requestHealthRun,
  updateHealthReporter,
} from '../api/smartsafehub';
import { errorMessage } from '../utils/errors';
import { useAsyncResource } from './useAsyncResource';

const HEALTH_REFRESH_INTERVAL_MS = 60_000;
const HEALTH_PENDING_REFRESH_INTERVAL_MS = 1_000;
const HEALTH_RUN_POLL_DELAYS_MS = [400, 800, 1_200, 1_600] as const;
const HEALTH_REPORTER_CONFIRM_DELAYS_MS = [400, 800, 1_200, 2_000, 4_000] as const;

interface HealthMutationState {
  running: boolean;
  savingReporter: boolean;
  actionError: string | null;
  actionMessage: string | null;
}

function sleep(milliseconds: number): Promise<void> {
  return new Promise((resolve) => window.setTimeout(resolve, milliseconds));
}

export function useHealth(active: boolean) {
  const resource = useAsyncResource({
    active,
    fallbackError: '장치 진단 상태를 불러오지 못했습니다.',
    loader: fetchHealthStatus,
    pollInterval: (data) =>
      data?.generatedAt
        ? HEALTH_REFRESH_INTERVAL_MS
        : HEALTH_PENDING_REFRESH_INTERVAL_MS,
    refreshOnFocus: true,
  });
  const reporterMutationSequence = useRef(0);
  const [mutation, setMutation] = useState<HealthMutationState>({
    running: false,
    savingReporter: false,
    actionError: null,
    actionMessage: null,
  });

  const runDiagnostic = useCallback(async (): Promise<boolean> => {
    setMutation({
      running: true,
      savingReporter: false,
      actionError: null,
      actionMessage: null,
    });

    try {
      const previousGeneratedAt = resource.data?.generatedAt ?? 0;
      const accepted = await requestHealthRun();
      if (!accepted.accepted) {
        throw new Error('장치가 진단 요청을 접수하지 않았습니다.');
      }

      let latest = resource.data;
      for (const delay of HEALTH_RUN_POLL_DELAYS_MS) {
        await sleep(delay);
        latest = await fetchHealthStatus();
        if (latest.generatedAt > 0 && latest.generatedAt !== previousGeneratedAt) {
          break;
        }
      }

      if (latest) {
        resource.replaceData(latest);
      }
      setMutation({
        running: false,
        savingReporter: false,
        actionError: null,
        actionMessage: '장치 상태를 다시 진단했습니다.',
      });
      return true;
    } catch (error) {
      setMutation({
        running: false,
        savingReporter: false,
        actionError: errorMessage(error, '장치 상태 진단을 실행하지 못했습니다.'),
        actionMessage: null,
      });
      return false;
    }
  }, [resource.data, resource.replaceData]);

  const confirmReporterState = useCallback(
    async (enabled: boolean, sequence: number): Promise<void> => {
      for (const delay of HEALTH_REPORTER_CONFIRM_DELAYS_MS) {
        await sleep(delay);
        if (reporterMutationSequence.current !== sequence) {
          return;
        }

        try {
          const latest = await fetchHealthStatus();
          if (reporterMutationSequence.current !== sequence) {
            return;
          }
          resource.replaceData(latest);

          if (latest.reporter.enabled !== enabled) {
            continue;
          }
          if (!enabled || !['disabled', 'never', 'initializing'].includes(latest.reporter.lastResult)) {
            return;
          }
        } catch {
          // The regular Health polling remains the fallback if a short
          // post-toggle confirmation request temporarily fails.
        }
      }
    },
    [resource.replaceData],
  );

  const setReporterEnabled = useCallback(
    async (enabled: boolean): Promise<boolean> => {
      const sequence = reporterMutationSequence.current + 1;
      reporterMutationSequence.current = sequence;
      const previousData = resource.data;

      if (previousData) {
        resource.replaceData({
          ...previousData,
          reporter: {
            ...previousData.reporter,
            enabled,
            lastResult: enabled ? 'initializing' : 'disabled',
            lastErrorCode: null,
            nextReportAt: enabled ? previousData.reporter.nextReportAt : 0,
          },
        });
      }

      setMutation({
        running: false,
        savingReporter: true,
        actionError: null,
        actionMessage: null,
      });

      try {
        const result = await updateHealthReporter(enabled);
        if (reporterMutationSequence.current !== sequence) {
          return true;
        }
        resource.replaceData(result);
        setMutation({
          running: false,
          savingReporter: false,
          actionError: null,
          actionMessage: enabled
            ? '원격 상태 보고를 켰습니다. 첫 서버 보고를 준비합니다.'
            : '원격 상태 보고를 껐습니다. 로컬 진단은 계속 동작합니다.',
        });
        void confirmReporterState(enabled, sequence);
        return true;
      } catch (error) {
        if (reporterMutationSequence.current === sequence) {
          if (previousData) {
            resource.replaceData(previousData);
          }
          setMutation({
            running: false,
            savingReporter: false,
            actionError: errorMessage(error, '원격 상태 보고 설정을 변경하지 못했습니다.'),
            actionMessage: null,
          });
        }
        return false;
      }
    },
    [confirmReporterState, resource.data, resource.replaceData],
  );

  const dismissActionFeedback = useCallback(() => {
    setMutation((current) => ({
      ...current,
      actionError: null,
      actionMessage: null,
    }));
  }, []);

  return {
    ...resource,
    ...mutation,
    dismissActionFeedback,
    runDiagnostic,
    setReporterEnabled,
  };
}
