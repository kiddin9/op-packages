import type { HealthStatus } from './health';
import type { SmartSafeHubStatus } from './status';
import type { WifiSummary } from './wifi';

export interface SystemTimeSettings {
  localtime: number;
  zonename: string;
  timezone: string;
  ntpEnabled: boolean;
  timezones: Record<string, string>;
}

export type ScheduledRebootFrequency = 'daily' | 'weekly';
export type ScheduledRebootDayOfWeek =
  | 'mon'
  | 'tue'
  | 'wed'
  | 'thu'
  | 'fri'
  | 'sat'
  | 'sun';

export interface ScheduledRebootSettings {
  enabled: boolean;
  frequency: ScheduledRebootFrequency;
  dayOfWeek: ScheduledRebootDayOfWeek;
  time: string;
  timezone: string;
}

export interface ScheduledRebootSettingsInput {
  enabled: boolean;
  frequency: ScheduledRebootFrequency;
  dayOfWeek: ScheduledRebootDayOfWeek;
  time: string;
}

export interface SafeShieldDiagnosticStatus {
  enabled: boolean | null;
  status: string | null;
  lastResult: string | null;
  validLineCount: number;
  blocklistInstalled: boolean;
  dnsmasqOk: boolean;
}

export interface SystemDiagnostics {
  generatedAt: number;
  health: HealthStatus | null;
  system: SmartSafeHubStatus;
  wifi: WifiSummary;
  safeshield: SafeShieldDiagnosticStatus;
}

export interface SystemTimeSyncResult {
  accepted: boolean;
  requestedAt: number;
}

export interface SystemRebootResult {
  accepted: boolean;
  scheduledAt: number;
}
