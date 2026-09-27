import { useCallback, useState } from 'preact/hooks';

import {
  fetchSystemTimeSettings,
  requestSystemTimeSync,
  updateSystemTimezone,
} from '../api/smartsafehub';
import { errorMessage } from '../utils/errors';
import { useAsyncResource } from './useAsyncResource';

interface SystemTimeMutationState {
  saving: boolean;
  syncing: boolean;
  saveError: string | null;
  saveMessage: string | null;
}

export function useSystemTimeSettings(active: boolean) {
  const resource = useAsyncResource({
    active,
    fallbackError: '시간대 설정을 불러오지 못했습니다.',
    loader: fetchSystemTimeSettings,
    refreshOnFocus: true,
  });
  const [mutation, setMutation] = useState<SystemTimeMutationState>({
    saving: false,
    syncing: false,
    saveError: null,
    saveMessage: null,
  });

  const saveTimezone = useCallback(
    async (zonename: string): Promise<boolean> => {
      setMutation({
        saving: true,
        syncing: false,
        saveError: null,
        saveMessage: null,
      });

      try {
        const result = await updateSystemTimezone(zonename);
        resource.replaceData(result);
        setMutation({
          saving: false,
          syncing: false,
          saveError: null,
          saveMessage: '시간대를 저장하고 시스템 시간 설정에 적용했습니다.',
        });
        return true;
      } catch (error) {
        setMutation({
          saving: false,
          syncing: false,
          saveError: errorMessage(error, '시간대 설정을 저장하지 못했습니다.'),
          saveMessage: null,
        });
        return false;
      }
    },
    [resource.replaceData],
  );

  const syncTime = useCallback(async (): Promise<boolean> => {
    setMutation({
      saving: false,
      syncing: true,
      saveError: null,
      saveMessage: null,
    });

    try {
      await requestSystemTimeSync();
      await new Promise<void>((resolve) => {
        window.setTimeout(resolve, 1500);
      });
      const result = await fetchSystemTimeSettings();
      resource.replaceData(result);
      setMutation({
        saving: false,
        syncing: false,
        saveError: null,
        saveMessage: 'NTP 시간 동기화를 요청하고 장치 시간을 다시 확인했습니다.',
      });
      return true;
    } catch (error) {
      setMutation({
        saving: false,
        syncing: false,
        saveError: errorMessage(error, '시간을 동기화하지 못했습니다.'),
        saveMessage: null,
      });
      return false;
    }
  }, [resource.replaceData]);

  const dismissSaveFeedback = useCallback(() => {
    setMutation((current) => ({
      ...current,
      saveError: null,
      saveMessage: null,
    }));
  }, []);

  return {
    ...resource,
    ...mutation,
    dismissSaveFeedback,
    saveTimezone,
    syncTime,
  };
}
