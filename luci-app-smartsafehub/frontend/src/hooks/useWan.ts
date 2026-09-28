import { useCallback, useEffect, useRef, useState } from 'preact/hooks';

import {
  fetchWanSettings,
  reconnectWan,
  updateWanSettings,
} from '../api/smartsafehub';
import type { WanSettingsInput } from '../types/wan';
import { errorMessage } from '../utils/errors';
import { useAsyncResource } from './useAsyncResource';

export type WanFeedback =
  | { kind: 'success' | 'warning' | 'error'; message: string }
  | null;

interface WanMutationState {
  action: 'saving' | 'reconnecting' | null;
  feedback: WanFeedback;
}

const RUNTIME_REFRESH_DELAY_MS = 5_000;

export function useWan(active: boolean) {
  const resource = useAsyncResource({
    active,
    fallbackError: '인터넷 연결 설정을 불러오지 못했습니다.',
    loader: fetchWanSettings,
  });
  const activeRef = useRef(active);
  const [mutation, setMutation] = useState<WanMutationState>({
    action: null,
    feedback: null,
  });

  useEffect(() => {
    activeRef.current = active;
  }, [active]);

  const scheduleRefresh = useCallback(() => {
    window.setTimeout(() => {
      if (activeRef.current) {
        void resource.refresh();
      }
    }, RUNTIME_REFRESH_DELAY_MS);
  }, [resource.refresh]);

  const save = useCallback(
    async (input: WanSettingsInput): Promise<boolean> => {
      setMutation({ action: 'saving', feedback: null });

      try {
        const result = await updateWanSettings(input);
        resource.replaceData(result.settings);
        setMutation({
          action: null,
          feedback: {
            kind: result.changed ? 'warning' : 'success',
            message: result.changed
              ? '인터넷 연결 설정을 저장했습니다. WAN을 다시 연결하는 동안 잠시 인터넷이 끊길 수 있습니다.'
              : '변경된 인터넷 연결 설정이 없습니다.',
          },
        });
        if (result.reconnectScheduled) {
          scheduleRefresh();
        }
        return true;
      } catch (error) {
        setMutation({
          action: null,
          feedback: {
            kind: 'error',
            message: errorMessage(error, '인터넷 연결 설정을 저장하지 못했습니다.'),
          },
        });
        return false;
      }
    },
    [resource.replaceData, scheduleRefresh],
  );

  const reconnect = useCallback(async (): Promise<void> => {
    setMutation({ action: 'reconnecting', feedback: null });

    try {
      const result = await reconnectWan();
      resource.replaceData(result.settings);
      setMutation({
        action: null,
        feedback: {
          kind: 'warning',
          message: 'WAN 재연결을 시작했습니다. 인터넷 연결이 다시 올라오면 상태를 자동으로 새로고침합니다.',
        },
      });
      if (result.reconnectScheduled) {
        scheduleRefresh();
      }
    } catch (error) {
      setMutation({
        action: null,
        feedback: {
          kind: 'error',
          message: errorMessage(error, 'WAN 재연결을 시작하지 못했습니다.'),
        },
      });
    }
  }, [resource.replaceData, scheduleRefresh]);

  const dismissFeedback = useCallback(() => {
    setMutation((current) => ({ ...current, feedback: null }));
  }, []);

  return {
    ...resource,
    ...mutation,
    save,
    reconnect,
    dismissFeedback,
  };
}
