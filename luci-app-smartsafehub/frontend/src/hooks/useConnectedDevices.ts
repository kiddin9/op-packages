import { fetchConnectedDevices } from '../api/smartsafehub';
import { useAsyncResource } from './useAsyncResource';

const REFRESH_INTERVAL_MS = 15_000;

export function useConnectedDevices(active: boolean, polling = true) {
  return useAsyncResource({
    active,
    fallbackError: '연결된 기기 목록을 불러오지 못했습니다.',
    loader: fetchConnectedDevices,
    ...(polling ? { pollInterval: REFRESH_INTERVAL_MS } : {}),
  });
}
