import { useCallback, useEffect, useRef, useState } from 'preact/hooks';

import {
  fetchSoftwareUpdates,
  requestSoftwareUpdateCheck,
  requestSoftwareUpdateInstall,
  updateSoftwareUpdateSettings,
} from '../api/smartsafehub';
import type {
  SoftwareUpdateSettingsInput,
  SoftwareUpdateStatus,
} from '../types/updates';
import { errorMessage } from '../utils/errors';
import { useAsyncResource } from './useAsyncResource';

export type SoftwareUpdateAction = 'check' | 'install' | 'settings' | null;

const BACKGROUND_POLL_INTERVAL_MS = 5 * 60_000;
const CHECK_POLL_INTERVAL_MS = 1_000;
const INSTALL_POLL_INTERVAL_MS = 3_000;
const UPDATE_PACKAGE = 'luci-app-smartsafehub';

export function useSoftwareUpdates(active = true) {
  const resource = useAsyncResource({
    active,
    fallbackError: '소프트웨어 업데이트 상태를 불러오지 못했습니다.',
    loader: fetchSoftwareUpdates,
    pollInterval: (data: SoftwareUpdateStatus | null) => {
      if (data?.phase === 'checking') {
        return CHECK_POLL_INTERVAL_MS;
      }

      return data?.phase === 'installing'
        ? INSTALL_POLL_INTERVAL_MS
        : BACKGROUND_POLL_INTERVAL_MS;
    },
    refreshOnFocus: true,
  });
  const [action, setAction] = useState<SoftwareUpdateAction>(null);
  const [actionError, setActionError] = useState<string | null>(null);
  const [message, setMessage] = useState<string | null>(null);
  const reloadRequested = useRef(false);
  const lastObservedInstallAt = useRef<number | null | undefined>(undefined);

  useEffect(() => {
    if (reloadRequested.current || !resource.data) {
      return;
    }

    const lastInstallAt = resource.data.lastInstallAt ?? null;
    const previousLastInstallAt = lastObservedInstallAt.current;

    // The resource starts with data=null. Do not treat that empty render as an
    // update-state baseline: otherwise the first real state (which may contain
    // an old lastInstallAt from a previous installation) looks like a newly
    // completed install on every page load and causes an endless reload loop.
    if (previousLastInstallAt === undefined) {
      lastObservedInstallAt.current = lastInstallAt;
      return;
    }

    lastObservedInstallAt.current = lastInstallAt;

    // Version information in /tmp/smartsafehub/updates.state can be stale after
    // a manual APK install or while LuCI is still serving a cached entry
    // template. A raw version mismatch must therefore never reload by itself.
    // Reload only when this mounted page observes a newly completed updater
    // installation. After the reload, the first real update state establishes
    // a fresh baseline and cannot trigger another reload by itself.
    if (
      lastInstallAt === null ||
      lastInstallAt === previousLastInstallAt ||
      resource.data.phase !== 'idle'
    ) {
      return;
    }

    const installedVersion = resource.data.packages.find(
      (item) => item.name === UPDATE_PACKAGE,
    )?.installedVersion;
    const loadedAssetVersion = window.__SMARTHUB_BOOTSTRAP__?.assetVersion;

    if (
      installedVersion &&
      loadedAssetVersion &&
      installedVersion !== loadedAssetVersion
    ) {
      reloadRequested.current = true;
      window.location.reload();
    }
  }, [resource.data]);

  const markPhase = useCallback(
    (phase: SoftwareUpdateStatus['phase']) => {
      if (!resource.data) {
        return;
      }

      resource.replaceData({ ...resource.data, phase, lastError: null });
    },
    [resource],
  );

  const check = useCallback(async () => {
    setAction('check');
    setActionError(null);
    setMessage(null);

    try {
      const result = await requestSoftwareUpdateCheck();
      if (!result.accepted) {
        throw new Error('업데이트 확인 요청이 접수되지 않았습니다.');
      }
      markPhase('checking');
      setAction(null);
      window.setTimeout(() => void resource.refresh(), 500);
    } catch (error) {
      setAction(null);
      setActionError(errorMessage(error, '업데이트 확인을 시작하지 못했습니다.'));
    }
  }, [markPhase, resource]);

  const install = useCallback(async () => {
    setAction('install');
    setActionError(null);
    setMessage(null);

    try {
      const result = await requestSoftwareUpdateInstall();
      if (!result.accepted) {
        throw new Error('업데이트 설치 요청이 접수되지 않았습니다.');
      }
      markPhase('installing');
      setAction(null);
      window.setTimeout(() => void resource.refresh(), 750);
    } catch (error) {
      setAction(null);
      setActionError(errorMessage(error, '업데이트 설치를 시작하지 못했습니다.'));
    }
  }, [markPhase, resource]);

  const saveSettings = useCallback(
    async (input: SoftwareUpdateSettingsInput): Promise<boolean> => {
      setAction('settings');
      setActionError(null);
      setMessage(null);

      try {
        const settings = await updateSoftwareUpdateSettings(input);
        if (resource.data) {
          resource.replaceData({ ...resource.data, settings });
        }
        setAction(null);
        setMessage('자동 업데이트 설정을 저장했습니다.');
        return true;
      } catch (error) {
        setAction(null);
        setActionError(errorMessage(error, '자동 업데이트 설정을 저장하지 못했습니다.'));
        return false;
      }
    },
    [resource],
  );

  const dismissFeedback = useCallback(() => {
    setActionError(null);
    setMessage(null);
  }, []);

  return {
    ...resource,
    action,
    actionError,
    message,
    check,
    dismissFeedback,
    install,
    saveSettings,
  };
}
