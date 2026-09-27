import { fetchStatus } from '../api/smartsafehub';
import { useAsyncResource } from './useAsyncResource';

const STATUS_REFRESH_INTERVAL_MS = 60_000;

export function useStatus(active: boolean) {
  return useAsyncResource({
    active,
    fallbackError: '장치 상태를 불러오지 못했습니다.',
    loader: fetchStatus,
    pollInterval: STATUS_REFRESH_INTERVAL_MS,
  });
}
