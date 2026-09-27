import { useCallback, useEffect, useRef, useState } from 'preact/hooks';

import {
  applyRecommendedLanSubnet,
  fetchLanSettings,
  updateLanSettings,
} from '../api/smartsafehub';
import type { LanSettingsInput, LanUpdateResult } from '../types/lan';
import { errorMessage } from '../utils/errors';
import { useAsyncResource } from './useAsyncResource';

export type LanFeedback =
  | { kind: 'success' | 'warning' | 'error'; message: string; newAddress?: string | null }
  | null;

interface LanMutationState {
  action: 'saving' | 'auto' | null;
  feedback: LanFeedback;
}

const RUNTIME_REFRESH_DELAY_MS = 4_000;

export function useLan(active: boolean) {
  const resource = useAsyncResource({
    active,
    fallbackError: '내부 네트워크 설정을 불러오지 못했습니다.',
    loader: fetchLanSettings,
  });
  const activeRef = useRef(active);
  const [mutation, setMutation] = useState<LanMutationState>({
    action: null,
    feedback: null,
  });

  useEffect(() => {
    activeRef.current = active;
  }, [active]);

  const finishUpdate = useCallback(
    (result: LanUpdateResult, auto: boolean) => {
      resource.replaceData(result.settings);

      if (!result.changed) {
        setMutation({
          action: null,
          feedback: { kind: 'success', message: '변경된 내부 네트워크 설정이 없습니다.' },
        });
        return;
      }

      if (result.addressChanged) {
        setMutation({
          action: null,
          feedback: {
            kind: 'warning',
            message: auto
              ? `추천 대역 ${result.settings.lan.subnet}을 저장했습니다. 네트워크가 다시 적용되면 새 공유기 주소로 다시 연결해 주세요.`
              : '내부 네트워크 주소를 저장했습니다. 네트워크가 다시 적용되면 새 공유기 주소로 다시 연결해 주세요.',
            newAddress: result.newAddress ?? result.settings.lan.address,
          },
        });
        return;
      }

      setMutation({
        action: null,
        feedback: {
          kind: 'success',
          message: auto
            ? '추천 내부 네트워크 설정을 적용했습니다.'
            : '내부 네트워크 설정을 저장했습니다.',
        },
      });

      if (result.reloadScheduled) {
        window.setTimeout(() => {
          if (activeRef.current) {
            void resource.refresh();
          }
        }, RUNTIME_REFRESH_DELAY_MS);
      }
    },
    [resource.refresh, resource.replaceData],
  );

  const save = useCallback(
    async (input: LanSettingsInput): Promise<boolean> => {
      setMutation({ action: 'saving', feedback: null });

      try {
        const result = await updateLanSettings(input);
        finishUpdate(result, false);
        return true;
      } catch (error) {
        setMutation({
          action: null,
          feedback: {
            kind: 'error',
            message: errorMessage(error, '내부 네트워크 설정을 저장하지 못했습니다.'),
          },
        });
        return false;
      }
    },
    [finishUpdate],
  );

  const applyRecommendation = useCallback(async (): Promise<boolean> => {
    setMutation({ action: 'auto', feedback: null });

    try {
      const result = await applyRecommendedLanSubnet();
      finishUpdate(result, true);
      return true;
    } catch (error) {
      setMutation({
        action: null,
        feedback: {
          kind: 'error',
          message: errorMessage(error, '추천 내부 네트워크를 적용하지 못했습니다.'),
        },
      });
      return false;
    }
  }, [finishUpdate]);

  const dismissFeedback = useCallback(() => {
    setMutation((current) => ({ ...current, feedback: null }));
  }, []);

  return {
    ...resource,
    ...mutation,
    save,
    applyRecommendation,
    dismissFeedback,
  };
}
