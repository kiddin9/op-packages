import type { ActivityHistory } from '../types/activity';
import type {
  ConfigurationBackupDiscardResult,
  ConfigurationBackupRestoreResult,
  ConfigurationBackupValidation,
} from '../types/backup';
import type { ConnectedDevicesSummary } from '../types/devices';
import type { HealthAccepted, HealthStatus } from '../types/health';
import type { IptvSettings, IptvSettingsInput, IptvUpdateResult } from '../types/iptv';
import type { LanSettings, LanSettingsInput, LanUpdateResult } from '../types/lan';
import type {
  SmartSafeHubLicenseActivationAccepted,
  SmartSafeHubLicenseStatus,
} from '../types/license';
import type {
  FirmwareAccepted,
  FirmwareStatus,
} from '../types/firmware';
import type { SmartSafeHubStatus } from '../types/status';
import type {
  ScheduledRebootSettings,
  ScheduledRebootSettingsInput,
  SystemRebootResult,
  SystemTimeSettings,
  SystemTimeSyncResult,
} from '../types/system';
import type {
  SoftwareUpdateAccepted,
  SoftwareUpdateSettings,
  SoftwareUpdateSettingsInput,
  SoftwareUpdateStatus,
} from '../types/updates';
import type {
  WifiSummary,
  WifiUpdateInput,
  WifiUpdateResult,
} from '../types/wifi';
import { callApi } from './rpc';

const API_OBJECT = 'smartsafehub';
const LAN_API_OBJECT = 'smartsafehub_network';

export function fetchConnectedDevices(): Promise<ConnectedDevicesSummary> {
  return callApi(API_OBJECT, 'connected_devices');
}

interface SmartSafeHubStatusWithActivity extends SmartSafeHubStatus {
  activityHistory?: ActivityHistory;
}

function emptyActivityHistory(): ActivityHistory {
  return {
    schema: 1,
    scope: 'current_boot',
    volatile: true,
    maxEvents: 128,
    cloud: {
      enabled: false,
      phase: 'preparing',
      eligible: null,
      plan: null,
      retentionDays: 0,
      pendingEvents: 0,
      lastAttemptAt: 0,
      lastSuccessAt: 0,
      lastUploadedCount: 0,
      lastErrorCode: null,
      nextSyncAt: 0,
    },
    events: [],
  };
}

export async function fetchActivityHistory(): Promise<ActivityHistory> {
  const status = await callApi<SmartSafeHubStatusWithActivity>(API_OBJECT, 'status');
  const activity = status.activityHistory ?? emptyActivityHistory();

  return {
    ...activity,
    cloud: {
      ...activity.cloud,
      // Pre-r19 RPC responses have no explicit toggle and always used Cloud
      // sync when eligible. Preserve that behavior during rolling upgrades.
      enabled: activity.cloud.enabled ?? true,
    },
  };
}

export function updateActivityCloudSync(enabled: boolean): Promise<ActivityHistory> {
  return callApi(API_OBJECT, 'activity_cloud_sync_update', { enabled });
}

export function fetchStatus(): Promise<SmartSafeHubStatus> {
  return callApi(API_OBJECT, 'status');
}

export function fetchSmartSafeHubLicenseStatus(): Promise<SmartSafeHubLicenseStatus> {
  return callApi(API_OBJECT, 'license_status', {}, { timeoutMs: 5000 });
}

export function requestSmartSafeHubLicenseActivation(
  licenseKey: string,
): Promise<SmartSafeHubLicenseActivationAccepted> {
  return callApi(API_OBJECT, 'license_activate', { license_key: licenseKey });
}

export function fetchHealthStatus(): Promise<HealthStatus> {
  return callApi(API_OBJECT, 'health_status');
}

export function requestHealthRun(): Promise<HealthAccepted> {
  return callApi(API_OBJECT, 'health_run');
}

export function updateHealthReporter(enabled: boolean): Promise<HealthStatus> {
  return callApi(API_OBJECT, 'health_reporter_update', { enabled });
}

export function fetchSoftwareUpdates(): Promise<SoftwareUpdateStatus> {
  return callApi(API_OBJECT, 'updates_status');
}

export function fetchFirmwareStatus(): Promise<FirmwareStatus> {
  return callApi(API_OBJECT, 'firmware_status');
}

export function requestFirmwareCheck(): Promise<FirmwareAccepted> {
  return callApi(API_OBJECT, 'firmware_check');
}

export function requestFirmwarePrepare(): Promise<FirmwareAccepted> {
  return callApi(API_OBJECT, 'firmware_prepare');
}

export function requestFirmwareUploadValidation(
  filename: string,
): Promise<FirmwareAccepted> {
  return callApi(API_OBJECT, 'firmware_validate_upload', { filename });
}

export function requestFirmwareInstall(
  keepSettings: boolean,
): Promise<FirmwareAccepted> {
  return callApi(API_OBJECT, 'firmware_install', {
    confirm: 'install',
    keep_settings: keepSettings,
  });
}

export function requestFirmwareDiscard(): Promise<FirmwareAccepted> {
  return callApi(API_OBJECT, 'firmware_discard');
}

export function requestSoftwareUpdateCheck(): Promise<SoftwareUpdateAccepted> {
  return callApi(API_OBJECT, 'updates_check');
}

export function requestSoftwareUpdateInstall(): Promise<SoftwareUpdateAccepted> {
  return callApi(API_OBJECT, 'updates_install', { confirm: 'install' });
}

export function updateSoftwareUpdateSettings(
  input: SoftwareUpdateSettingsInput,
): Promise<SoftwareUpdateSettings> {
  return callApi(API_OBJECT, 'updates_settings_update', {
    check_enabled: input.checkEnabled,
    check_interval_s: input.checkIntervalSeconds,
    auto_install: input.autoInstall,
    auto_install_time: input.autoInstallTime,
  });
}

export function fetchSystemTimeSettings(): Promise<SystemTimeSettings> {
  return callApi(API_OBJECT, 'system_time_settings');
}

export function updateSystemTimezone(
  zonename: string,
): Promise<SystemTimeSettings> {
  return callApi(API_OBJECT, 'system_timezone_update', { zonename });
}

export function requestSystemTimeSync(): Promise<SystemTimeSyncResult> {
  return callApi(API_OBJECT, 'system_time_sync');
}

export function fetchScheduledRebootSettings(): Promise<ScheduledRebootSettings> {
  return callApi(API_OBJECT, 'system_scheduled_reboot_settings');
}

export function updateScheduledRebootSettings(
  input: ScheduledRebootSettingsInput,
): Promise<ScheduledRebootSettings> {
  return callApi(API_OBJECT, 'system_scheduled_reboot_update', {
    enabled: input.enabled,
    frequency: input.frequency,
    day_of_week: input.dayOfWeek,
    time: input.time,
  });
}

export function requestConfigurationBackupValidation(
  filename: string,
): Promise<ConfigurationBackupValidation> {
  return callApi(API_OBJECT, 'system_backup_validate', { filename });
}

export function requestConfigurationBackupRestore(): Promise<ConfigurationBackupRestoreResult> {
  return callApi(
    API_OBJECT,
    'system_backup_restore',
    { confirm: 'restore' },
    { timeoutMs: 35_000 },
  );
}

export function requestConfigurationBackupDiscard(): Promise<ConfigurationBackupDiscardResult> {
  return callApi(API_OBJECT, 'system_backup_discard');
}

export function requestSystemReboot(): Promise<SystemRebootResult> {
  return callApi(API_OBJECT, 'system_reboot', { confirm: 'reboot' });
}

export function fetchLanSettings(): Promise<LanSettings> {
  return callApi(LAN_API_OBJECT, 'lan_settings');
}

export function updateLanSettings(
  input: LanSettingsInput,
): Promise<LanUpdateResult> {
  return callApi(
    LAN_API_OBJECT,
    'lan_update',
    {
      ip_address: input.ipAddress,
      prefix_length: input.prefixLength,
      dhcp_enabled: input.dhcpEnabled,
      dhcp_start: input.dhcpStart,
      dhcp_end: input.dhcpEnd,
      lease_time: input.leaseTime,
      confirm: 'apply',
    },
    { timeoutMs: 10_000 },
  );
}

export function applyRecommendedLanSubnet(): Promise<LanUpdateResult> {
  return callApi(
    LAN_API_OBJECT,
    'lan_auto_subnet',
    { confirm: 'apply' },
    { timeoutMs: 10_000 },
  );
}

export function fetchIptvSettings(): Promise<IptvSettings> {
  return callApi(LAN_API_OBJECT, 'iptv_settings');
}

export function updateIptvSettings(
  input: IptvSettingsInput,
): Promise<IptvUpdateResult> {
  return callApi(
    LAN_API_OBJECT,
    'iptv_update',
    {
      enabled: input.enabled,
      provider: input.provider,
      confirm: 'apply',
    },
    { timeoutMs: 20_000 },
  );
}

export function fetchWifiSummary(): Promise<WifiSummary> {
  return callApi(API_OBJECT, 'wifi_summary');
}

export function updateWifiNetwork(
  input: WifiUpdateInput,
): Promise<WifiUpdateResult> {
  return callApi(
    API_OBJECT,
    'wifi_update',
    { ...input },
    { timeoutMs: 35_000 },
  );
}
