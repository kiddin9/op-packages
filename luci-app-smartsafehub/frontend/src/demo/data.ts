// Entirely fictional values. Never use a real router address, MAC, credential or token.
import type { ActivityHistory } from '../types/activity';
import type { ConnectedDevicesSummary } from '../types/devices';
import type { FirmwareStatus } from '../types/firmware';
import type { WanSettings } from '../types/wan';
import type { WifiSummary, WifiQrCredentials } from '../types/wifi';
import type { SafeShieldRules } from '../types/rules';
import type { HealthStatus } from '../types/health';
import type { LanSettings } from '../types/lan';
import type { SafeShieldStatistics, SafeShieldStatus } from '../types/safeshield';
import type { SmartSafeHubStatus } from '../types/status';
import type { SoftwareUpdateStatus } from '../types/updates';
import type { DeviceRegistrationStatus } from '../api/smartsafehub';
import type { AppsCatalog, AppsInstallStatus, AppsMetrics } from '../types/apps';

const now = Math.floor(Date.now() / 1000);
const hour = 3600;

// Demo-only account status: no user, device credential, pairing token or live Hub session.
export const demoAccount: DeviceRegistrationStatus = {
  schema: 1,
  component: 'device',
  phase: 'registered',
  lastResult: 'success',
  lastErrorCode: null,
  accountRegistered: true,
  plan: 'free',
  pairingCode: null,
  pairingExpiresAt: null,
  nextSyncAt: 0,
  lastSuccessAt: now - 300,
};

// Demo-only catalog. No APK URLs or authenticated API responses are used.
export const demoApps: AppsCatalog = {
  schema: 1,
  deviceCode: 'iptime-ax3000sm',
  firmwareBuildId: 'demo-build',
  channel: 'stable',
  apps: [
    {
      id: 'retro-arcade',
      name: '레트로 아케이드',
      summary: '브라우저에서 레트로 게임을 즐기는 엔터테인먼트 앱입니다.',
      description: '사용자가 직접 준비한 게임 파일로 즐기는 레트로 아케이드입니다.',
      category: 'entertainment',
      version: '1.1.0-r5',
      webUi: { type: 'static', path: '/retro-arcade/' },
    },
    {
      id: 'network-usage-monitor',
      name: '네트워크 사용량 모니터',
      summary: '기기별 네트워크 사용량과 통계를 확인하는 앱입니다.',
      description: '네트워크 트래픽을 모니터링합니다.',
      category: 'network',
      version: '2025.06.02~29236be6-r1',
      webUi: null,
    },
    {
      id: 'wake-on-lan',
      name: 'Wake-on-LAN',
      summary: '공유기에서 PC와 홈서버의 전원을 켤 수 있는 도구입니다.',
      description: 'Wake-on-LAN 지원 컴퓨터를 네트워크에서 깨우는 앱입니다.',
      category: 'utilities',
      version: '26.288.56989~75a306d',
      webUi: null, // Public demo must never link to an actual LuCI control page.
    },
  ],
};

export const demoAppsStatus: AppsInstallStatus = {
  job: { phase: 'idle', action: '', appId: '', code: 'NONE' },
  installed: {
    'retro-arcade': {
      installed: true,
      partial: false,
      managed: true,
      updateAvailable: true,
      installedVersion: '1.0.0-r1',
      webUiReady: true,
    },
    'network-usage-monitor': {
      installed: true,
      partial: false,
      managed: true,
      updateAvailable: false,
      installedVersion: '2025.06.02~29236be6-r1',
      webUiReady: false,
    },
    'wake-on-lan': {
      installed: false,
      partial: false,
      managed: false,
      updateAvailable: false,
      installedVersion: null,
      webUiReady: false,
    },
  },
};

export const demoAppsMetrics: AppsMetrics = {
  storage: { mount: '/overlay', totalBytes: 256 * 1024 * 1024, availableBytes: 185 * 1024 * 1024 },
  // Installed APK metadata; neither app cache nor runtime data is included.
  installedSizes: { 'retro-arcade': 1394688, 'network-usage-monitor': 117760 },
};

export const demoDevices: ConnectedDevicesSummary = {
  generatedAt: now,
  devices: [
    { id: 'demo-phone', hostname: '거실 스마트폰', mac: '02:00:00:00:00:01', ipv4Address: '192.0.2.101', connection: 'wifi', online: true, leaseActive: true, leaseExpiresAt: now + 6 * hour, interface: 'wlan0', ssid: 'SmartSafeHub', radio: 'radio0', band: '5g', bandLabel: '5 GHz', signalDbm: -43, inactiveMs: 250, connectedSeconds: 8300 },
    { id: 'demo-laptop', hostname: '작업용 노트북', mac: '02:00:00:00:00:02', ipv4Address: '192.0.2.102', connection: 'wifi', online: true, leaseActive: true, leaseExpiresAt: now + 8 * hour, interface: 'wlan0', ssid: 'SmartSafeHub', radio: 'radio0', band: '5g', bandLabel: '5 GHz', signalDbm: -57, inactiveMs: 720, connectedSeconds: 29200 },
    { id: 'demo-tv', hostname: '거실 TV', mac: '02:00:00:00:00:03', ipv4Address: '192.0.2.103', connection: 'ethernet', online: true, leaseActive: true, leaseExpiresAt: now + 12 * hour, interface: 'lan1', ssid: null, radio: null, band: null, bandLabel: null, signalDbm: null, inactiveMs: null, connectedSeconds: 140000 },
    { id: 'demo-tablet', hostname: '태블릿', mac: '02:00:00:00:00:04', ipv4Address: '192.0.2.104', connection: 'wifi', online: false, leaseActive: false, leaseExpiresAt: null, interface: null, ssid: 'SmartSafeHub', radio: 'radio1', band: '2g', bandLabel: '2.4 GHz', signalDbm: null, inactiveMs: null, connectedSeconds: null },
  ],
  totals: { known: 4, online: 3, wireless: 2, ethernet: 1, offline: 1 },
};

export const demoActivity: ActivityHistory = {
  schema: 1, scope: 'current_boot', volatile: true, maxEvents: 100,
  cloud: { enabled: false, phase: 'disabled', eligible: false, plan: 'free', retentionDays: 0, pendingEvents: 0, lastAttemptAt: 0, lastSuccessAt: 0, lastUploadedCount: 0, lastErrorCode: null, nextSyncAt: 0 },
  events: [
    { schema: 1, eventId: 'demo-event-1', eventType: 'safeshield.blocklist.updated', severity: 'success', occurredAt: now - 7200, deviceUuid: null, source: 'safeshield', metadata: {} },
    { schema: 1, eventId: 'demo-event-2', eventType: 'system.boot', severity: 'info', occurredAt: now - 86400, deviceUuid: null, source: 'system', metadata: {} },
  ],
};

export const demoStatus: SmartSafeHubStatus = {
  device: { hostname: 'SmartRouter', model: 'ipTIME AX3000SM', boardName: 'iptime,ax3000sm' },
  software: { distribution: 'OpenWrt', version: '25.12', revision: 'demo', kernel: '6.12' },
  runtime: { uptime: 86400, localtime: now, load: [0.08, 0.12, 0.05], memory: { total: 268435456, free: 83886080, shared: 4194304, buffered: 41943040, available: 171966464, cached: 41943040 }, storage: demoAppsMetrics.storage },
  network: { available: true, up: true, protocol: 'dhcp', ipv4Address: '198.51.100.20' },
  activityHistory: demoActivity,
};

export const demoLan: LanSettings = {
  lan: { address: '192.168.1.1', prefixLength: 24, netmask: '255.255.255.0', subnet: '192.168.1.0/24' },
  dhcp: { enabled: true, start: '192.168.1.100', end: '192.168.1.249', leaseTime: '12h' },
  wan: { connected: true, protocol: 'dhcp', address: '198.51.100.20', prefixLength: 24, subnet: '198.51.100.0/24' },
  conflict: { detected: false, wanSubnet: null }, recommendation: null,
};

export const demoSafeShield: SafeShieldStatus = {
  available: true, version: '0.3.25', enabled: true, active: true, status: 'idle', stage: null,
  summary: { label: '보호 중', message: 'DNS 보호가 정상적으로 동작하고 있습니다.', severity: 'info' },
  runtime: { refreshdRunning: true, dnsmasqRunning: true, dnsRuntimeOk: true, lastResult: 'success', lastErrorCode: null },
  entitlement: { plan: 'free', status: 'active' },
  artifact: { resolved: true, tier: 'light', version: '20261010T010000Z', uniqueDomains: 48000, rules: 48000 },
  localOverrides: { enabled: true, allowlistPath: '/etc/safeshield/allowlist', blocklistPath: '/etc/safeshield/blocklist' },
  blocklist: { installed: true, validLineCount: 48000, fileSizeKb: 4700, verificationOk: true },
  health: { overall: 'ok' }, issueCounts: { warnings: 0, errors: 0 },
  timestamps: { lastAttempt: now - 2 * hour, lastSuccess: now - 2 * hour, lastFailure: 0, lastLocalApply: now - 2 * hour, lastLocalApplyFailure: 0, nextRefreshAt: now + 21 * hour, refreshIntervalS: 82800 },
};

const latestHourBucket = Math.floor(now / hour) * hour;

const hourlyProfiles = [
  { queries: 351, blocked: 18 },
  { queries: 297, blocked: 15 },
  { queries: 243, blocked: 11 },
  { queries: 216, blocked: 9 },
  { queries: 203, blocked: 8 },
  { queries: 230, blocked: 10 },
  { queries: 324, blocked: 17 },
  { queries: 567, blocked: 35 },
  { queries: 783, blocked: 54 },
  { queries: 864, blocked: 61 },
  { queries: 756, blocked: 50 },
  { queries: 702, blocked: 43 },
  { queries: 635, blocked: 36 },
  { queries: 580, blocked: 30 },
  { queries: 608, blocked: 33 },
  { queries: 689, blocked: 40 },
  { queries: 837, blocked: 54 },
  { queries: 1026, blocked: 73 },
  { queries: 1256, blocked: 99 },
  { queries: 1458, blocked: 125 },
  { queries: 1512, blocked: 135 },
  { queries: 1323, blocked: 111 },
  { queries: 1026, blocked: 75 },
  { queries: 648, blocked: 39 },
] as const;

const hourly = Array.from({ length: 24 }, (_, i) => {
  const bucketStart = latestHourBucket - (23 - i) * hour;
  const hourOfDay = new Date(bucketStart * 1_000).getHours();
  const profile = hourlyProfiles[hourOfDay]!;

  return {
    bucketStart,
    queries: profile.queries,
    blocked: profile.blocked,
  };
});
export const demoStatistics: SafeShieldStatistics = {
  enabled: true, collectorRunning: true, available: true, schemaVersion: 1, volatile: true,
  startedAt: now - 7 * 86400, updatedAt: now - 30, retentionHours: 168,
  totals: { queries: hourly.reduce((sum, item) => sum + item.queries, 0), blocked: hourly.reduce((sum, item) => sum + item.blocked, 0) },
  hourly, deviceLimit: 128, devicesTruncated: false,
  devices: [
    { id: 'demo-phone', mac: '02:00:00:00:00:01', ip: '192.0.2.101', hostname: '거실 스마트폰', identified: true, queries: 3400, blocked: 470 },
    { id: 'demo-laptop', mac: '02:00:00:00:00:02', ip: '192.0.2.102', hostname: '작업용 노트북', identified: true, queries: 2900, blocked: 345 },
    { id: 'demo-tv', mac: '02:00:00:00:00:03', ip: '192.0.2.103', hostname: '거실 TV', identified: true, queries: 1200, blocked: 185 },
  ],
};

export const demoHealth: HealthStatus = {
  schema: 1, generatedAt: now, overall: 'ok',
  summary: { message: '모든 주요 항목이 정상입니다.', total: 3, ok: 3, warning: 0, critical: 0, unknown: 0 },
  metrics: { memoryAvailablePercent: 64, load1m: 0.08, overlayAvailablePercent: 80 },
  checks: [],
  reporter: { enabled: false, eligible: false, plan: 'free', entitlementStatus: 'active', lastReportAt: 0, nextReportAt: 0, lastResult: '', lastErrorCode: null },
};

export const demoUpdates: SoftwareUpdateStatus = {
  phase: 'idle', updateCount: 0, packages: [], lastCheckAt: now - hour, lastInstallAt: null, lastError: null,
  releaseNotes: [], releaseNotesComplete: true,
  settings: { channel: 'stable', checkEnabled: true, checkIntervalSeconds: 21600, autoInstall: true, autoInstallTime: '03:00', repositoryHost: 'example.invalid', updatePackage: 'luci-app-smartsafehub' },
};

export const demoFirmware: FirmwareStatus = {
  phase: 'idle', source: null, lastCheckAt: now - hour, lastPrepareAt: null, lastError: null, prepared: null,
  current: { deviceCode: 'iptime-ax3000sm', boardName: 'iptime,ax3000sm', buildId: 'demo', releaseVersion: '1.0.2', openwrtVersion: '25.12', metadataAvailable: true },
  updateAvailable: false, release: null,
  settings: { channel: 'stable', apiBaseUrl: 'https://www.smartsafehub.com', checkIntervalSeconds: 21600, autoInstall: false },
};

// The interactive demo deliberately uses only invented, RFC 5737 addresses.
export const demoWan: WanSettings = {
  configuration: {
    protocol: 'dhcp', supported: true,
    pppoe: { username: '', passwordConfigured: false },
    static: { address: null, prefixLength: null, netmask: null, gateway: null, dns: [] },
  },
  status: {
    connected: true, pending: false, protocol: 'dhcp', device: 'wan',
    address: '198.51.100.20', prefixLength: 24, gateway: '198.51.100.1',
    dns: ['1.1.1.1', '8.8.8.8'], uptimeSeconds: 86400,
  },
};

export const demoWifi: WifiSummary = {
  networks: [
    { section: 'demo_5g', device: 'radio0', band: '5g', bandLabel: '5 GHz',
      ssid: 'SmartSafeHub', enabled: true, runtimeUp: true, security: 'sae-mixed',
      securityRaw: 'sae-mixed', passwordConfigured: true, channel: '36',
      networks: ['lan'], clientCount: 2 },
    { section: 'demo_2g', device: 'radio1', band: '2g', bandLabel: '2.4 GHz',
      ssid: 'SmartSafeHub-2G', enabled: true, runtimeUp: true, security: 'sae-mixed',
      securityRaw: 'sae-mixed', passwordConfigured: true, channel: '6',
      networks: ['lan'], clientCount: 0 },
  ],
  totalClients: 2,
  guest: { supported: true, configured: true, enabled: true,
    ssid: 'SmartSafeHub-Guest', passwordConfigured: true,
    subnet: '192.0.2.0/24', radio: 'radio1' },
};

export const demoRules: SafeShieldRules = {
  allow: ['trusted.example', 'updates.example'],
  block: ['ads.example', 'tracker.example'],
  counts: { allow: 2, block: 2, total: 4 },
  safeshieldEnabled: true, applyLocalOverrides: true,
};

// The QR dialog uses an injected demo-only data provider, never the router RPC.
export const demoWifiQr = async (section: string): Promise<WifiQrCredentials> => ({
  ssid: demoWifi.networks.find((network) => network.section === section)?.ssid ?? 'SmartSafeHub',
  security: 'sae-mixed', password: 'demo-only-2026',
});
export const demoGuestWifiQr = async (): Promise<WifiQrCredentials> => ({
  ssid: 'SmartSafeHub-Guest', security: 'sae-mixed', password: 'guest-demo-only-2026',
});
