export type ActivityEventSeverity = 'info' | 'success' | 'warning' | 'error';

export interface ActivityEvent {
  schema: 1;
  eventId: string;
  eventType: string;
  severity: ActivityEventSeverity;
  occurredAt: number;
  deviceUuid: string | null;
  source: string;
  metadata: Record<string, unknown>;
}

export interface ActivityCloudSync {
  enabled: boolean;
  phase: string;
  eligible: boolean | null;
  plan: string | null;
  retentionDays: number;
  pendingEvents: number;
  lastAttemptAt: number;
  lastSuccessAt: number;
  lastUploadedCount: number;
  lastErrorCode: string | null;
  nextSyncAt: number;
}

export interface ActivityHistory {
  schema: 1;
  scope: 'current_boot';
  volatile: boolean;
  maxEvents: number;
  cloud: ActivityCloudSync;
  events: ActivityEvent[];
}
