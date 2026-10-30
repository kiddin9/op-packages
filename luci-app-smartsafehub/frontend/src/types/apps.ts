/** Read-only SmartSafeHub Apps catalog schema 1 from the local router. */
export interface VerifiedApp {
  id: string;
  name: string;
  summary: string;
  description: string;
  category: string;
  version: string;
  /** Approved same-origin LuCI page or first-party static app; never a remote URL. */
  webUi?: { type: 'luci' | 'static'; path: string } | null;
}

export interface AppsCatalog {
  schema: 1;
  deviceCode: string;
  firmwareBuildId: string;
  channel: string;
  apps: VerifiedApp[];
  /** False until the first immutable, firmware-matched snapshot is available. */
  ready?: boolean;
  refreshing?: boolean;
  refreshFailed?: boolean;
}

/** Writable filesystem used for installing APKs (not RAM or squashfs). */
export interface AppsStorage {
  mount: '/overlay' | '/';
  totalBytes: number;
  availableBytes: number;
}

/** Optional metrics, independent from installation and removal state. */
export interface AppsMetrics {
  storage: AppsStorage | null;
  installedSizes: Record<string, number>;
  ready?: boolean;
  refreshing?: boolean;
}

/** Local APK adapter state, independent from the future IoT / AI runtimes. */
export interface AppsInstallStatus {
  job: {
    phase: 'idle' | 'starting' | 'running' | 'success' | 'failed';
    action: 'install' | 'update' | 'remove' | '';
    appId: string;
    code: string;
    operationId?: string;
  };
  restore?: {
    phase: 'idle' | 'starting' | 'running' | 'success' | 'failed';
    appId: string;
    code: string;
  };
  ready?: boolean;
  refreshing?: boolean;
  refreshFailed?: boolean;
  installed: Record<string, {
    installed: boolean;
    partial: boolean;
    managed: boolean;
    /** Verified by a local Apps-owned manifest, not inferred by comparing asynchronous RPC replies. */
    retired?: boolean;
    updateAvailable?: boolean;
    /** Actual installed version of the first approved APK; not the catalog version. */
    installedVersion?: string | null;
    webUiReady?: boolean;
  }>;
}

export interface AppsOperationAccepted {
  accepted: boolean;
  appId: string;
  action: 'install' | 'update' | 'remove';
}
