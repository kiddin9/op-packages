import type { AppsInstallStatus } from '../types/apps';

const STORAGE_KEY = 'smartsafehub:apps:dismissed-operation:v1';

type AppsJob = AppsInstallStatus['job'];

/** A job ID is preserved through running/success/failure on the router. */
export function appsJobNoticeKey(job: AppsJob | null | undefined): string {
  if (!job || job.phase === 'idle') return '';
  // Backwards compatibility while router frontend and RPC versions differ.
  return job.operationId
    ? `operation:${job.operationId}`
    : `legacy:${job.phase}:${job.action}:${job.appId}:${job.code}`;
}

/** Browser storage is optional (private browsing or hardened browsers). */
export function readDismissedAppsJob(): string | null {
  try {
    return typeof window === 'undefined' ? null : window.localStorage.getItem(STORAGE_KEY);
  } catch {
    return null;
  }
}

export function saveDismissedAppsJob(key: string): void {
  if (!key) return;
  try {
    if (typeof window !== 'undefined') window.localStorage.setItem(STORAGE_KEY, key);
  } catch {
    // In-memory dismissal remains usable if storage is blocked.
  }
}
