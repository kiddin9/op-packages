import type {
  SafeShieldRuleAction,
  SafeShieldRuleMutationResult,
  SafeShieldRules,
} from '../types/rules';
import type {
  SafeShieldEnabledResult,
  SafeShieldLicenseReadResult,
  SafeShieldLicenseUpdateResult,
  SafeShieldRefreshResult,
  SafeShieldStatistics,
  SafeShieldStatisticsEnabledResult,
  SafeShieldStatus,
} from '../types/safeshield';
import { callApi, callRpc, RpcError } from './rpc';

const API_OBJECT = 'safeshield';
const SMARTSAFEHUB_API_OBJECT = 'smartsafehub';

interface RawSafeShieldStatus {
  version?: unknown;
  enabled?: unknown;
  active?: unknown;
  status?: unknown;
  stage?: unknown;
  summary?: Record<string, unknown>;
  runtime?: Record<string, unknown>;
  license?: Record<string, unknown>;
  artifact?: Record<string, unknown>;
  local_overrides?: Record<string, unknown>;
  blocklist?: Record<string, unknown>;
  health?: Record<string, unknown>;
  warnings?: unknown;
  errors?: unknown;
  timestamps?: Record<string, unknown>;
}

interface RawSafeShieldStatistics {
  enabled?: unknown;
  collector_running?: unknown;
  schema?: Record<string, unknown>;
  volatile?: unknown;
  started_at?: unknown;
  updated_at?: unknown;
  retention_hours?: unknown;
  totals?: Record<string, unknown>;
  hourly?: unknown;
  device_limit?: unknown;
  devices_truncated?: unknown;
  devices?: unknown;
}

interface RawSafeShieldConfig {
  values?: Record<string, unknown>;
}

interface SafeShieldRuleConfig {
  enabled: boolean;
  applyLocalOverrides: boolean;
}

interface RawSafeShieldRules {
  ok?: unknown;
  allow?: unknown;
  block?: unknown;
  counts?: Record<string, unknown>;
  error?: unknown;
}

interface RawSafeShieldMutation {
  ok?: unknown;
  changed?: unknown;
  restarted?: unknown;
  accepted?: unknown;
  target_enabled?: unknown;
  reconciled?: unknown;
  reason?: unknown;
  status?: unknown;
  domain?: unknown;
  added?: unknown;
  deleted?: unknown;
  refresh?: unknown;
  license?: unknown;
  error?: unknown;
}

function stringValue(value: unknown, fallback: string | null): string | null {
  return typeof value === 'string' && value.length > 0 ? value : fallback;
}

function plainString(value: unknown): string {
  return typeof value === 'string' ? value : '';
}

function numberValue(value: unknown): number {
  return typeof value === 'number' && Number.isFinite(value) ? value : 0;
}

function boolValue(value: unknown): boolean {
  return value === true;
}

function arrayCount(value: unknown): number {
  return Array.isArray(value) ? value.length : 0;
}

function stringArray(value: unknown): string[] {
  return Array.isArray(value)
    ? value.filter((item): item is string => typeof item === 'string')
    : [];
}

function objectValue(value: unknown): Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : {};
}

function apiError(response: Record<string, unknown>): RpcError {
  const error = objectValue(response.error);
  const code = plainString(error.code) || 'UNKNOWN_ERROR';
  const message =
    plainString(error.message) || 'SafeShield API 요청을 처리하지 못했습니다.';

  return new RpcError(`SAFESHIELD_${code.toUpperCase()}`, message);
}

async function callSafeShield<T>(
  method: string,
  params: Record<string, unknown> = {},
): Promise<T> {
  const response = await callRpc<unknown>(API_OBJECT, method, params);
  const object = objectValue(response);

  if (object.ok === false) {
    throw apiError(object);
  }

  return response as T;
}


async function callManagedSafeShield<T>(
  method: string,
  params: Record<string, unknown>,
  fallbackMethod: string,
  fallbackParams: Record<string, unknown> = params,
): Promise<T> {
  try {
    return await callApi<T>(SMARTSAFEHUB_API_OBJECT, method, params);
  } catch (error) {
    if (
      error instanceof RpcError &&
      ['RPC_PERMISSION_DENIED', 'UBUS_3', 'UBUS_6'].includes(error.code)
    ) {
      return callSafeShield<T>(fallbackMethod, fallbackParams);
    }
    throw error;
  }
}

function unavailableStatistics(): SafeShieldStatistics {
  return {
    enabled: false,
    collectorRunning: false,
    available: false,
    schemaVersion: 0,
    volatile: true,
    startedAt: 0,
    updatedAt: 0,
    retentionHours: 0,
    totals: {
      queries: 0,
      blocked: 0,
    },
    hourly: [],
    deviceLimit: 0,
    devicesTruncated: false,
    devices: [],
  };
}

function normalizeStatistics(sourceValue: RawSafeShieldStatistics): SafeShieldStatistics {
  const source = objectValue(sourceValue);

  if (Object.keys(source).length === 0) {
    return unavailableStatistics();
  }

  const schema = objectValue(source.schema);
  const totals = objectValue(source.totals);
  const hourly = Array.isArray(source.hourly)
    ? source.hourly
        .map((entry) => objectValue(entry))
        .map((entry) => ({
          bucketStart: numberValue(entry.bucket_start),
          queries: numberValue(entry.queries),
          blocked: numberValue(entry.blocked),
        }))
        .filter((entry) => entry.bucketStart > 0)
        .sort((left, right) => left.bucketStart - right.bucketStart)
    : [];

  const devices = Array.isArray(source.devices)
    ? source.devices
        .map((entry) => objectValue(entry))
        .map((entry) => {
          const ip = plainString(entry.ip);
          const mac = plainString(entry.mac);
          const id = plainString(entry.id) || mac || (ip ? `ip:${ip}` : '');

          return {
            id,
            mac,
            ip,
            hostname: plainString(entry.hostname),
            identified: boolValue(entry.identified),
            queries: numberValue(entry.queries),
            blocked: numberValue(entry.blocked),
          };
        })
        .filter((entry) => entry.id.length > 0)
    : [];

  return {
    enabled: boolValue(source.enabled),
    collectorRunning: boolValue(source.collector_running),
    available: source.available !== false,
    schemaVersion: numberValue(schema.version),
    volatile: source.volatile !== false,
    startedAt: numberValue(source.started_at),
    updatedAt: numberValue(source.updated_at),
    retentionHours: numberValue(source.retention_hours),
    totals: {
      queries: numberValue(totals.queries),
      blocked: numberValue(totals.blocked),
    },
    hourly,
    deviceLimit: numberValue(source.device_limit),
    devicesTruncated: boolValue(source.devices_truncated),
    devices,
  };
}

function unavailableStatus(): SafeShieldStatus {
  return {
    available: false,
    version: null,
    enabled: false,
    active: false,
    status: 'unavailable',
    stage: null,
    summary: {
      label: 'Unavailable',
      message: 'SafeShield status API is unavailable',
      severity: 'warning',
    },
    runtime: {
      refreshdRunning: false,
      dnsmasqRunning: false,
      dnsRuntimeOk: false,
      lastResult: null,
      lastErrorCode: null,
    },
    license: {
      configured: false,
      keyMasked: '',
      plan: null,
      status: null,
    },
    artifact: {
      resolved: false,
      tier: null,
      version: null,
      uniqueDomains: 0,
      rules: 0,
    },
    localOverrides: {
      enabled: false,
      allowlistPath: null,
      blocklistPath: null,
    },
    blocklist: {
      installed: false,
      validLineCount: 0,
      fileSizeKb: 0,
      verificationOk: false,
    },
    health: {
      overall: 'unavailable',
    },
    issueCounts: {
      warnings: 0,
      errors: 0,
    },
    timestamps: {
      lastAttempt: 0,
      lastSuccess: 0,
      lastFailure: 0,
      lastLocalApply: 0,
      lastLocalApplyFailure: 0,
      nextRefreshAt: 0,
      refreshIntervalS: 0,
    },
  };
}

function normalizeStatus(sourceValue: RawSafeShieldStatus): SafeShieldStatus {
  const source = objectValue(sourceValue);

  if (Object.keys(source).length === 0) {
    return unavailableStatus();
  }

  const summary = objectValue(source.summary);
  const runtime = objectValue(source.runtime);
  const license = objectValue(source.license);
  const artifact = objectValue(source.artifact);
  const localOverrides = objectValue(source.local_overrides);
  const blocklist = objectValue(source.blocklist);
  const health = objectValue(source.health);
  const timestamps = objectValue(source.timestamps);

  return {
    available: true,
    version: stringValue(source.version, null),
    enabled: boolValue(source.enabled),
    active: boolValue(source.active),
    status: stringValue(source.status, 'unknown') ?? 'unknown',
    stage: stringValue(source.stage, null),
    summary: {
      label: stringValue(summary.label, 'Unknown') ?? 'Unknown',
      message:
        stringValue(summary.message, 'SafeShield status is unknown') ??
        'SafeShield status is unknown',
      severity: stringValue(summary.severity, 'warning') ?? 'warning',
    },
    runtime: {
      refreshdRunning: boolValue(runtime.refreshd_running),
      dnsmasqRunning: boolValue(runtime.dnsmasq_running),
      dnsRuntimeOk: boolValue(runtime.dns_runtime_ok),
      lastResult: stringValue(runtime.last_result, null),
      lastErrorCode: stringValue(runtime.last_error_code, null),
    },
    license: {
      configured: boolValue(license.configured),
      keyMasked: plainString(license.key_masked),
      plan: stringValue(license.plan, null),
      status: stringValue(license.status, null),
    },
    artifact: {
      resolved: boolValue(artifact.resolved),
      tier: stringValue(artifact.tier, null),
      version: stringValue(artifact.version, null),
      uniqueDomains: numberValue(artifact.unique_domains),
      rules: numberValue(artifact.rules),
    },
    localOverrides: {
      enabled: boolValue(localOverrides.enabled),
      allowlistPath: stringValue(localOverrides.allowlist_path, null),
      blocklistPath: stringValue(localOverrides.blocklist_path, null),
    },
    blocklist: {
      installed: boolValue(blocklist.installed),
      validLineCount: numberValue(blocklist.valid_line_count),
      fileSizeKb: numberValue(blocklist.file_size_kb),
      verificationOk: boolValue(blocklist.verification_ok),
    },
    health: {
      overall: stringValue(health.overall, 'unknown') ?? 'unknown',
    },
    issueCounts: {
      warnings: arrayCount(source.warnings),
      errors: arrayCount(source.errors),
    },
    timestamps: {
      lastAttempt: numberValue(timestamps.last_attempt),
      lastSuccess: numberValue(timestamps.last_success),
      lastFailure: numberValue(timestamps.last_failure),
      lastLocalApply: numberValue(timestamps.last_local_apply),
      lastLocalApplyFailure: numberValue(timestamps.last_local_apply_failure),
      nextRefreshAt: numberValue(timestamps.next_refresh_at),
      refreshIntervalS: numberValue(timestamps.refresh_interval_s),
    },
  };
}

function normalizeRuleConfig(sourceValue: RawSafeShieldConfig): SafeShieldRuleConfig {
  const values = objectValue(objectValue(sourceValue).values);

  return {
    enabled: boolValue(values.enabled),
    applyLocalOverrides: boolValue(values.apply_local_overrides),
  };
}

function normalizeRefresh(source: unknown): {
  requested: boolean;
  accepted: boolean;
  reason: string;
} {
  const refresh = objectValue(source);

  return {
    requested: boolValue(refresh.requested),
    accepted: boolValue(refresh.accepted),
    reason: plainString(refresh.reason),
  };
}

export async function fetchSafeShieldStatistics(): Promise<SafeShieldStatistics> {
  try {
    const response = await callSafeShield<RawSafeShieldStatistics>('statistics');
    return normalizeStatistics(response);
  } catch (error) {
    if (
      error instanceof RpcError &&
      ['UBUS_3', 'UBUS_4', 'UBUS_5'].includes(error.code)
    ) {
      return unavailableStatistics();
    }

    throw error;
  }
}

export async function setSafeShieldStatisticsEnabled(
  enabled: boolean,
): Promise<SafeShieldStatisticsEnabledResult> {
  const response = await callManagedSafeShield<RawSafeShieldMutation>(
    'safeshield_statistics_update',
    { enabled },
    'config_update',
    { values: { statistics_enabled: enabled } },
  );

  const changed = Array.isArray(response.changed)
    ? response.changed.some((name) => name === 'statistics_enabled')
    : false;

  return {
    changed,
    enabled,
    restarted: boolValue(response.restarted),
    reconciled: boolValue(response.reconciled),
  };
}

export async function fetchSafeShieldStatus(): Promise<SafeShieldStatus> {
  try {
    const response = await callSafeShield<RawSafeShieldStatus>('status');
    return normalizeStatus(response);
  } catch (error) {
    if (
      error instanceof RpcError &&
      ['UBUS_3', 'UBUS_4', 'UBUS_5'].includes(error.code)
    ) {
      return unavailableStatus();
    }

    throw error;
  }
}

async function fetchSafeShieldRuleConfig(): Promise<SafeShieldRuleConfig> {
  const response = await callSafeShield<RawSafeShieldConfig>('config');
  return normalizeRuleConfig(response);
}

export async function setSafeShieldEnabled(
  enabled: boolean,
): Promise<SafeShieldEnabledResult> {
  const response = await callManagedSafeShield<RawSafeShieldMutation>(
    'safeshield_set_enabled',
    { enabled },
    'set_enabled',
  );

  return {
    changed: boolValue(response.changed),
    accepted: boolValue(response.accepted),
    targetEnabled: boolValue(response.target_enabled),
    reconciled: boolValue(response.reconciled),
  };
}

export async function requestSafeShieldRefresh(): Promise<SafeShieldRefreshResult> {
  const response = await callManagedSafeShield<RawSafeShieldMutation>(
    'safeshield_refresh',
    {},
    'refresh',
  );

  return {
    accepted: boolValue(response.accepted),
    reason: plainString(response.reason),
    status: normalizeStatus(response.status as RawSafeShieldStatus),
  };
}

export async function fetchSafeShieldRules(): Promise<SafeShieldRules> {
  const [rulesResponse, config] = await Promise.all([
    callSafeShield<RawSafeShieldRules>('rules_list'),
    fetchSafeShieldRuleConfig(),
  ]);
  const allow = stringArray(rulesResponse.allow);
  const block = stringArray(rulesResponse.block);

  return {
    allow,
    block,
    counts: {
      allow: allow.length,
      block: block.length,
      total: allow.length + block.length,
    },
    safeshieldEnabled: config.enabled,
    applyLocalOverrides: config.applyLocalOverrides,
  };
}

async function mutateSafeShieldRule(
  method: 'rule_add' | 'rule_delete',
  action: SafeShieldRuleAction,
  domain: string,
  refresh = true,
): Promise<SafeShieldRuleMutationResult> {
  const response = await callManagedSafeShield<RawSafeShieldMutation>(
    method === 'rule_add' ? 'safeshield_rule_add' : 'safeshield_rule_delete',
    { action, domain, refresh },
    method,
  );
  const changed = method === 'rule_add'
    ? boolValue(response.added)
    : boolValue(response.deleted);

  return {
    action,
    domain: plainString(response.domain) || domain,
    changed,
    refresh: normalizeRefresh(response.refresh),
    rules: await fetchSafeShieldRules(),
  };
}

export function addSafeShieldRule(
  action: SafeShieldRuleAction,
  domain: string,
  refresh = true,
): Promise<SafeShieldRuleMutationResult> {
  return mutateSafeShieldRule('rule_add', action, domain, refresh);
}

export function deleteSafeShieldRule(
  action: SafeShieldRuleAction,
  domain: string,
  refresh = true,
): Promise<SafeShieldRuleMutationResult> {
  return mutateSafeShieldRule('rule_delete', action, domain, refresh);
}

export async function fetchSafeShieldLicense(): Promise<SafeShieldLicenseReadResult> {
  const response = await callSafeShield<RawSafeShieldMutation>('license_get');
  const license = objectValue(response.license);

  return {
    configured: boolValue(license.configured),
    key: plainString(license.key),
  };
}

export async function updateSafeShieldLicense(
  licenseKey: string,
): Promise<SafeShieldLicenseUpdateResult> {
  const response = await callManagedSafeShield<RawSafeShieldMutation>(
    'safeshield_license_update',
    { license_key: licenseKey },
    'license_update',
  );
  const license = objectValue(response.license);

  return {
    changed: boolValue(response.changed),
    license: {
      configured: boolValue(license.configured),
      keyMasked: plainString(license.key_masked),
    },
    refresh: normalizeRefresh(response.refresh),
  };
}
