import { fetchSafeShieldStatus } from '../api/safeshield';
import type { SafeShieldStatus } from '../types/safeshield';
import { isSafeShieldRefreshTransition } from '../utils/safeshieldRefresh';
import { useAsyncResource } from './useAsyncResource';

const TRANSITION_REFRESH_INTERVAL_MS = 3_000;

function isTransitioning(data: SafeShieldStatus | null): boolean {
  if (!data) {
    return false;
  }

  return isSafeShieldRefreshTransition(data.status, data.stage);
}

export function useSafeShieldStatus(active: boolean) {
  return useAsyncResource({
    active,
    fallbackError: 'SafeShield 상태를 불러오지 못했습니다.',
    loader: fetchSafeShieldStatus,
    pollInterval: (data) =>
      isTransitioning(data) ? TRANSITION_REFRESH_INTERVAL_MS : null,
  });
}
