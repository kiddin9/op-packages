export type SmartSafeHubLicensePhase =
  | 'unknown'
  | 'unconfigured'
  | 'activating'
  | 'checking'
  | 'active'
  | 'cleared'
  | 'error';

export interface SmartSafeHubLicenseStatus {
  schema: number;
  component: 'license';
  phase: SmartSafeHubLicensePhase | string;
  lastResult: string;
  lastErrorCode: string | null;
  lastAttemptAt: number;
  lastCheckedAt: number;
  lastActivatedAt: number;
  nextCheckAt: number;
  plan: string | null;
  licenseStatus: string | null;
  activationStatus: string | null;
  deviceAction: string | null;
}

export interface SmartSafeHubLicenseActivationAccepted {
  accepted: boolean;
  startedAt: number;
  status: SmartSafeHubLicenseStatus;
}
