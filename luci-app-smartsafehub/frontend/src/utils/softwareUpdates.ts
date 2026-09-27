import type { SoftwareUpdateStatus } from '../types/updates';

const MINIMUM_STALE_THRESHOLD_SECONDS = 7_200;

export function isSoftwareUpdateCheckStale(
  data: SoftwareUpdateStatus | null | undefined,
  nowSeconds = Math.floor(Date.now() / 1000),
): boolean {
  if (
    !data ||
    !data.settings.checkEnabled ||
    data.phase === 'checking' ||
    !data.lastCheckAt
  ) {
    return false;
  }

  const ageSeconds = Math.max(0, nowSeconds - data.lastCheckAt);
  const staleThresholdSeconds = Math.max(
    data.settings.checkIntervalSeconds * 2,
    MINIMUM_STALE_THRESHOLD_SECONDS,
  );

  return ageSeconds > staleThresholdSeconds;
}
