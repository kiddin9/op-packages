import type { AppsStorage } from '../types/apps';

export interface StorageSummary {
  availablePercent: number;
  availableRatio: number;
  availableText: string;
  usedText: string;
  totalText: string;
  level: 'normal' | 'warning' | 'critical';
}

/** Base-2 units match the BusyBox df -h figures used on OpenWrt. */
export function formatStorageBytes(bytes: number): string {
  if (!Number.isFinite(bytes) || bytes < 0) return '—';
  if (bytes < 1024) return `${Math.round(bytes)} B`;
  if (bytes < 1024 ** 2) return `${(bytes / 1024).toFixed(1)} KB`;
  if (bytes < 1024 ** 3) return `${(bytes / (1024 ** 2)).toFixed(1)} MB`;
  return `${(bytes / (1024 ** 3)).toFixed(1)} GB`;
}

/** Reserved blocks count as unavailable, not as space for APK installation. */
export function summarizeAppsStorage(storage: AppsStorage | null | undefined): StorageSummary | null {
  if (!storage || !Number.isSafeInteger(storage.totalBytes) ||
    !Number.isSafeInteger(storage.availableBytes) || storage.totalBytes <= 0 ||
    storage.availableBytes < 0 || storage.availableBytes > storage.totalBytes ||
    (storage.mount !== '/overlay' && storage.mount !== '/')) return null;
  const availableRatio = storage.availableBytes / storage.totalBytes;
  return {
    availablePercent: Math.round(availableRatio * 100),
    availableRatio,
    availableText: formatStorageBytes(storage.availableBytes),
    // Includes filesystem-reserved space, not only files written by apps.
    usedText: formatStorageBytes(storage.totalBytes - storage.availableBytes),
    totalText: formatStorageBytes(storage.totalBytes),
    level: availableRatio <= 0.1 ? 'critical' : availableRatio <= 0.2 ? 'warning' : 'normal',
  };
}
