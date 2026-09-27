import { useCallback, useEffect, useRef, useState } from 'preact/hooks';

import {
  fetchFirmwareStatus,
  requestFirmwareCheck,
  requestFirmwareDiscard,
  requestFirmwareInstall,
  requestFirmwarePrepare,
  requestFirmwareUploadValidation,
} from '../api/smartsafehub';
import { uploadFirmwareFile } from '../api/firmwareUpload';
import type { FirmwareStatus } from '../types/firmware';
import { errorMessage } from '../utils/errors';
import { useAsyncResource } from './useAsyncResource';

export type FirmwareAction =
  | 'check'
  | 'prepare'
  | 'upload'
  | 'validate-upload'
  | 'install'
  | 'discard'
  | null;

const BACKGROUND_POLL_INTERVAL_MS = 5 * 60_000;
const ACTIVE_POLL_INTERVAL_MS = 1_000;
const VALIDATION_STATUS_POLL_INTERVAL_MS = 500;
const VALIDATION_STALE_STATE_GRACE_MS = 3_000;
const VALIDATION_STATUS_TIMEOUT_MS = 30_000;
const RECONNECT_INITIAL_DELAY_MS = 15_000;
const RECONNECT_INTERVAL_MS = 5_000;

function sleep(milliseconds: number): Promise<void> {
  return new Promise((resolve) => window.setTimeout(resolve, milliseconds));
}

function isActivePhase(phase: FirmwareStatus['phase'] | undefined): boolean {
  return (
    phase === 'checking' ||
    phase === 'downloading' ||
    phase === 'verifying'
  );
}

export function useFirmwareUpdates(active = true) {
  const resource = useAsyncResource({
    active,
    fallbackError: '펌웨어 업데이트 상태를 불러오지 못했습니다.',
    loader: fetchFirmwareStatus,
    pollInterval: (data: FirmwareStatus | null) =>
      isActivePhase(data?.phase)
        ? ACTIVE_POLL_INTERVAL_MS
        : BACKGROUND_POLL_INTERVAL_MS,
    refreshOnFocus: true,
  });
  const [action, setAction] = useState<FirmwareAction>(null);
  const [actionError, setActionError] = useState<string | null>(null);
  const [message, setMessage] = useState<string | null>(null);
  const [uploadProgress, setUploadProgress] = useState<number | null>(null);
  const [reconnecting, setReconnecting] = useState(false);
  const reconnectTimer = useRef<number | null>(null);

  useEffect(
    () => () => {
      if (reconnectTimer.current !== null) {
        window.clearTimeout(reconnectTimer.current);
      }
    },
    [],
  );

  const markPhase = useCallback(
    (phase: FirmwareStatus['phase']) => {
      if (!resource.data) {
        return;
      }
      resource.replaceData({ ...resource.data, phase, lastError: null });
    },
    [resource],
  );

  const startAcceptedAction = useCallback(
    async (
      actionName: Exclude<FirmwareAction, 'upload' | 'validate-upload' | 'install' | 'discard' | null>,
      phase: FirmwareStatus['phase'],
      request: () => Promise<{ accepted: boolean }>,
      fallbackError: string,
    ) => {
      setAction(actionName);
      setActionError(null);
      setMessage(null);
      try {
        const result = await request();
        if (!result.accepted) {
          throw new Error('펌웨어 작업 요청이 접수되지 않았습니다.');
        }
        markPhase(phase);
        setAction(null);
        window.setTimeout(() => void resource.refresh(), 400);
      } catch (error) {
        setAction(null);
        setActionError(errorMessage(error, fallbackError));
      }
    },
    [markPhase, resource],
  );

  const check = useCallback(
    () =>
      startAcceptedAction(
        'check',
        'checking',
        requestFirmwareCheck,
        '펌웨어 업데이트 확인을 시작하지 못했습니다.',
      ),
    [startAcceptedAction],
  );

  const prepare = useCallback(
    () =>
      startAcceptedAction(
        'prepare',
        'downloading',
        requestFirmwarePrepare,
        '펌웨어 다운로드를 시작하지 못했습니다.',
      ),
    [startAcceptedAction],
  );

  const waitForUploadValidation = useCallback(async (): Promise<FirmwareStatus> => {
    const startedAt = Date.now();
    let lastFetchError: unknown = null;

    while (Date.now() - startedAt < VALIDATION_STATUS_TIMEOUT_MS) {
      await sleep(VALIDATION_STATUS_POLL_INTERVAL_MS);

      try {
        const status = await fetchFirmwareStatus();
        const elapsed = Date.now() - startedAt;

        if (status.phase === 'ready') {
          resource.replaceData(status);
          return status;
        }

        if (status.phase === 'verifying') {
          resource.replaceData(status);
          continue;
        }

        if (status.phase === 'error') {
          // The background validator is started asynchronously. Immediately after
          // accepting the request the state file may still contain the previous
          // terminal error for a short time. Do not let that stale snapshot replace
          // the optimistic `verifying` state and stop active polling.
          if (elapsed < VALIDATION_STALE_STATE_GRACE_MS) {
            continue;
          }

          resource.replaceData(status);
          return status;
        }

        // idle/checking/downloading can be a snapshot from the previous operation
        // before the validator has written its first state. Keep the optimistic
        // validating UI until the validator acknowledges the new request.
      } catch (error) {
        lastFetchError = error;
      }
    }

    if (lastFetchError) {
      throw lastFetchError;
    }
    throw new Error('펌웨어 검증 상태 확인 시간이 초과되었습니다. 다시 시도해 주세요.');
  }, [resource]);

  const upload = useCallback(
    async (file: File): Promise<boolean> => {
      setAction('upload');
      setActionError(null);
      setMessage(null);
      setUploadProgress(0);

      try {
        await uploadFirmwareFile(file, setUploadProgress);
        setAction('validate-upload');
        const result = await requestFirmwareUploadValidation(file.name);
        if (!result.accepted) {
          throw new Error('업로드한 펌웨어 검증 요청이 접수되지 않았습니다.');
        }
        markPhase('verifying');
        setUploadProgress(null);

        const status = await waitForUploadValidation();
        setAction(null);
        if (status.phase === 'error') {
          return false;
        }
        if (!status.prepared) {
          throw new Error('검증된 펌웨어의 설치 준비 정보를 확인하지 못했습니다. 다시 시도해 주세요.');
        }

        setMessage('펌웨어 검증이 완료되었습니다. 설치 옵션을 확인해 주세요.');
        return true;
      } catch (error) {
        setAction(null);
        setUploadProgress(null);
        setActionError(errorMessage(error, '펌웨어 파일을 업로드하지 못했습니다.'));
        return false;
      }
    },
    [markPhase, waitForUploadValidation],
  );

  const scheduleReconnect = useCallback(() => {
    setReconnecting(true);

    const probe = async () => {
      try {
        const response = await fetch(window.location.pathname, {
          cache: 'no-store',
          credentials: 'same-origin',
        });
        if (response.ok) {
          window.location.reload();
          return;
        }
      } catch {
        // The router is expected to be unavailable while sysupgrade reboots it.
      }
      reconnectTimer.current = window.setTimeout(probe, RECONNECT_INTERVAL_MS);
    };

    reconnectTimer.current = window.setTimeout(probe, RECONNECT_INITIAL_DELAY_MS);
  }, []);

  const install = useCallback(
    async (keepSettings: boolean): Promise<boolean> => {
      setAction('install');
      setActionError(null);
      setMessage(null);

      try {
        const result = await requestFirmwareInstall(keepSettings);
        if (!result.accepted) {
          throw new Error('펌웨어 설치 요청이 접수되지 않았습니다.');
        }
        markPhase('flashing');
        setAction(null);
        scheduleReconnect();
        return true;
      } catch (error) {
        setAction(null);
        setActionError(errorMessage(error, '펌웨어 설치를 시작하지 못했습니다.'));
        return false;
      }
    },
    [markPhase, scheduleReconnect],
  );

  const discard = useCallback(async (): Promise<boolean> => {
    setAction('discard');
    setActionError(null);
    setMessage(null);
    try {
      const result = await requestFirmwareDiscard();
      if (!result.accepted) {
        throw new Error('준비된 펌웨어 정리 요청이 접수되지 않았습니다.');
      }
      setAction(null);
      setMessage('준비된 펌웨어 파일을 삭제했습니다.');
      await resource.refresh();
      return true;
    } catch (error) {
      setAction(null);
      setActionError(errorMessage(error, '준비된 펌웨어를 정리하지 못했습니다.'));
      return false;
    }
  }, [resource]);

  const dismissFeedback = useCallback(() => {
    setActionError(null);
    setMessage(null);
  }, []);

  return {
    ...resource,
    action,
    actionError,
    message,
    uploadProgress,
    reconnecting,
    check,
    prepare,
    upload,
    install,
    discard,
    dismissFeedback,
  };
}
