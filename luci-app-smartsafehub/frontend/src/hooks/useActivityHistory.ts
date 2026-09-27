import { useCallback, useState } from 'preact/hooks';

import { fetchActivityHistory, updateActivityCloudSync } from '../api/smartsafehub';
import { errorMessage } from '../utils/errors';
import { useAsyncResource } from './useAsyncResource';

const ACTIVITY_REFRESH_INTERVAL_MS = 60_000;

interface ActivityMutationState {
  savingCloudSync: boolean;
  actionError: string | null;
  actionMessage: string | null;
}

export function useActivityHistory(active: boolean) {
  const resource = useAsyncResource({
    active,
    fallbackError: '최근 활동을 불러오지 못했습니다.',
    loader: () => fetchActivityHistory(),
    pollInterval: ACTIVITY_REFRESH_INTERVAL_MS,
    refreshOnFocus: true,
  });
  const [mutation, setMutation] = useState<ActivityMutationState>({
    savingCloudSync: false,
    actionError: null,
    actionMessage: null,
  });

  const setCloudSyncEnabled = useCallback(
    async (enabled: boolean): Promise<boolean> => {
      setMutation({
        savingCloudSync: true,
        actionError: null,
        actionMessage: null,
      });

      try {
        const result = await updateActivityCloudSync(enabled);
        resource.replaceData(result);
        setMutation({
          savingCloudSync: false,
          actionError: null,
          actionMessage: enabled
            ? 'Cloud 활동 기록 전송을 켰습니다. 지금부터 발생하는 활동을 Cloud에 전송합니다.'
            : 'Cloud 활동 기록 전송을 껐습니다. 로컬 최근 활동은 계속 기록됩니다.',
        });
        return true;
      } catch (error) {
        setMutation({
          savingCloudSync: false,
          actionError: errorMessage(error, 'Cloud 활동 기록 설정을 변경하지 못했습니다.'),
          actionMessage: null,
        });
        return false;
      }
    },
    [resource.replaceData],
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
    setCloudSyncEnabled,
  };
}
