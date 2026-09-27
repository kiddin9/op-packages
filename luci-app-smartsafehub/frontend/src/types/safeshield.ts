export type SafeShieldSeverity = 'info' | 'notice' | 'warning' | 'error';

export interface SafeShieldSummary {
  label: string;
  message: string;
  severity: SafeShieldSeverity | string;
}

export interface SafeShieldStatus {
  available: boolean;
  version: string | null;
  enabled: boolean;
  active: boolean;
  status: string;
  stage: string | null;
  summary: SafeShieldSummary;
  runtime: {
    refreshdRunning: boolean;
    dnsmasqRunning: boolean;
    dnsRuntimeOk: boolean;
    lastResult: string | null;
    lastErrorCode: string | null;
  };
  license: {
    configured: boolean;
    keyMasked: string;
    plan: string | null;
    status: string | null;
  };
  artifact: {
    resolved: boolean;
    tier: string | null;
    version: string | null;
    uniqueDomains: number;
    rules: number;
  };
  localOverrides: {
    enabled: boolean;
    allowlistPath: string | null;
    blocklistPath: string | null;
  };
  blocklist: {
    installed: boolean;
    validLineCount: number;
    fileSizeKb: number;
    verificationOk: boolean;
  };
  health: {
    overall: string;
  };
  issueCounts: {
    warnings: number;
    errors: number;
  };
  timestamps: {
    lastAttempt: number;
    lastSuccess: number;
    lastFailure: number;
    lastLocalApply: number;
    lastLocalApplyFailure: number;
    nextRefreshAt: number;
    refreshIntervalS: number;
  };
}

export interface SafeShieldEnabledResult {
  changed: boolean;
  accepted: boolean;
  targetEnabled: boolean;
  reconciled: boolean;
}

export interface SafeShieldStatisticsEnabledResult {
  changed: boolean;
  enabled: boolean;
  restarted: boolean;
  reconciled: boolean;
}

export interface SafeShieldRefreshResult {
  accepted: boolean;
  reason: string;
  status: SafeShieldStatus;
}

export interface SafeShieldLicenseReadResult {
  configured: boolean;
  key: string;
}

export interface SafeShieldLicenseUpdateResult {
  changed: boolean;
  license: {
    configured: boolean;
    keyMasked: string;
  };
  refresh: {
    requested: boolean;
    accepted: boolean;
    reason: string;
  };
}

export interface SafeShieldStatisticsBucket {
  bucketStart: number;
  queries: number;
  blocked: number;
}

export interface SafeShieldDeviceStatistics {
  id: string;
  mac: string;
  ip: string;
  hostname: string;
  identified: boolean;
  queries: number;
  blocked: number;
}

export interface SafeShieldStatistics {
  enabled: boolean;
  collectorRunning: boolean;
  available: boolean;
  schemaVersion: number;
  volatile: boolean;
  startedAt: number;
  updatedAt: number;
  retentionHours: number;
  totals: {
    queries: number;
    blocked: number;
  };
  hourly: SafeShieldStatisticsBucket[];
  deviceLimit: number;
  devicesTruncated: boolean;
  devices: SafeShieldDeviceStatistics[];
}
