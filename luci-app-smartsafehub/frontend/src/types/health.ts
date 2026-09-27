export type HealthSeverity = 'ok' | 'initializing' | 'warning' | 'critical' | 'unknown';

export interface HealthCheck {
  id: string;
  label: string;
  status: HealthSeverity;
  code: string | null;
  message: string;
  value: number | string | null;
  unit: string | null;
}

export interface HealthSummary {
  message: string;
  total: number;
  ok: number;
  warning: number;
  critical: number;
  unknown: number;
}

export interface HealthMetrics {
  memoryAvailablePercent: number;
  load1m: number;
  overlayAvailablePercent: number;
}

export interface HealthReporterStatus {
  enabled: boolean;
  eligible: boolean;
  plan: string | null;
  licenseStatus: string | null;
  lastReportAt: number;
  nextReportAt: number;
  lastResult: string;
  lastErrorCode: string | null;
}

export interface HealthStatus {
  schema: number;
  generatedAt: number;
  overall: HealthSeverity;
  summary: HealthSummary;
  metrics: HealthMetrics;
  checks: HealthCheck[];
  reporter: HealthReporterStatus;
}

export interface HealthAccepted {
  accepted: boolean;
}
