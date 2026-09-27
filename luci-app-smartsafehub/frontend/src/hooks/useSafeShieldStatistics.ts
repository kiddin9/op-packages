import { fetchSafeShieldStatistics } from '../api/safeshield';
import { useAsyncResource } from './useAsyncResource';

const STATISTICS_REFRESH_INTERVAL_MS = 60_000;

export function useSafeShieldStatistics(active: boolean, polling = true) {
  return useAsyncResource({
    active,
    fallbackError: 'SafeShield 통계를 불러오지 못했습니다.',
    loader: fetchSafeShieldStatistics,
    ...(polling ? { pollInterval: STATISTICS_REFRESH_INTERVAL_MS } : {}),
  });
}
