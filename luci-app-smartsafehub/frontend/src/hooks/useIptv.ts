import { useCallback, useState } from 'preact/hooks';

import { fetchIptvSettings, updateIptvSettings } from '../api/smartsafehub';
import type { IptvSettingsInput } from '../types/iptv';
import { errorMessage } from '../utils/errors';
import { useAsyncResource } from './useAsyncResource';

export type IptvFeedback =
  | { kind: 'success' | 'error'; message: string }
  | null;

export function useIptv(active: boolean) {
  const resource = useAsyncResource({
    active,
    fallbackError: 'IPTV 설정을 불러오지 못했습니다.',
    loader: fetchIptvSettings,
    refreshOnFocus: true,
  });
  const [saving, setSaving] = useState(false);
  const [feedback, setFeedback] = useState<IptvFeedback>(null);

  const save = useCallback(
    async (input: IptvSettingsInput): Promise<boolean> => {
      setSaving(true);
      setFeedback(null);

      try {
        const result = await updateIptvSettings(input);
        resource.replaceData(result.settings);
        setSaving(false);
        setFeedback({
          kind: 'success',
          message: input.enabled
            ? result.changed
              ? 'IPTV 설정을 적용했습니다.'
              : 'IPTV 설정을 다시 적용했습니다.'
            : 'IPTV 기능을 껐습니다.',
        });
        return true;
      } catch (error) {
        setSaving(false);
        setFeedback({
          kind: 'error',
          message: errorMessage(error, 'IPTV 설정을 적용하지 못했습니다.'),
        });
        return false;
      }
    },
    [resource.replaceData],
  );

  const dismissFeedback = useCallback(() => setFeedback(null), []);

  return {
    ...resource,
    saving,
    feedback,
    save,
    dismissFeedback,
  };
}
