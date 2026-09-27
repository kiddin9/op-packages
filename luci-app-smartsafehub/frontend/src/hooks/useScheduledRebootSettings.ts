import { useCallback, useState } from 'preact/hooks';

import {
  fetchScheduledRebootSettings,
  updateScheduledRebootSettings,
} from '../api/smartsafehub';
import type { ScheduledRebootSettingsInput } from '../types/system';
import { errorMessage } from '../utils/errors';
import { useAsyncResource } from './useAsyncResource';

interface ScheduledRebootMutationState {
  saving: boolean;
  saveError: string | null;
  saveMessage: string | null;
}

export function useScheduledRebootSettings(active: boolean) {
  const resource = useAsyncResource({
    active,
    fallbackError: '예약 재부팅 설정을 불러오지 못했습니다.',
    loader: fetchScheduledRebootSettings,
    refreshOnFocus: true,
  });
  const [mutation, setMutation] = useState<ScheduledRebootMutationState>({
    saving: false,
    saveError: null,
    saveMessage: null,
  });

  const saveSettings = useCallback(
    async (input: ScheduledRebootSettingsInput): Promise<boolean> => {
      setMutation({ saving: true, saveError: null, saveMessage: null });

      try {
        const result = await updateScheduledRebootSettings(input);
        resource.replaceData(result);
        setMutation({
          saving: false,
          saveError: null,
          saveMessage: input.enabled
            ? '예약 재부팅 일정을 저장했습니다.'
            : '예약 재부팅을 껐습니다.',
        });
        return true;
      } catch (error) {
        setMutation({
          saving: false,
          saveError: errorMessage(error, '예약 재부팅 설정을 저장하지 못했습니다.'),
          saveMessage: null,
        });
        return false;
      }
    },
    [resource.replaceData],
  );

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
    saveSettings,
  };
}
