import type { AppsCatalog, AppsInstallStatus } from '../types/apps';
import type { JarbisStatus } from '../types/jarbis';

/** Do not infer installation from a failed Jarbis RPC: rpcd can be unavailable too. */
export type SmartHomeEntry = 'ready' | 'checking' | 'installing' | 'install' | 'repair' | 'unavailable' | 'service-error' | 'unknown';

export function smartHomeEntry(
  status: JarbisStatus | null,
  rpcError: string | null,
  appsStatus: AppsInstallStatus | null,
  catalog: AppsCatalog | null,
  appsError: string | null,
  catalogError: string | null,
): SmartHomeEntry {
  if (status) return 'ready';
  if (!rpcError) return 'checking';

  // A missing or unready Apps snapshot is not evidence that Jarbis is absent.
  if (appsError) return 'unknown';
  if (!appsStatus || appsStatus.ready === false) return 'checking';
  const installation = appsStatus.installed?.jarbis;
  if (installation?.installed) return 'service-error';
  if (appsStatus.job.appId === 'jarbis' &&
    (appsStatus.job.phase === 'starting' || appsStatus.job.phase === 'running')) return 'installing';
  if (appsStatus.restore?.appId === 'jarbis' &&
    (appsStatus.restore.phase === 'starting' || appsStatus.restore.phase === 'running')) return 'installing';

  if (installation?.managed || installation?.partial) return 'repair';
  // Only the firmware-matched, approved catalog can advertise an installation.
  if (catalogError) return 'unknown';
  if (!catalog || catalog.ready === false) return 'checking';
  return catalog.apps.some(app => app.id === 'jarbis') ? 'install' : 'unavailable';
}
