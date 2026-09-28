export type WanProtocol = 'dhcp' | 'pppoe' | 'static';

export interface WanPppoeConfiguration {
  username: string;
  passwordConfigured: boolean;
}

export interface WanStaticConfiguration {
  address: string | null;
  prefixLength: number | null;
  netmask: string | null;
  gateway: string | null;
  dns: string[];
}

export interface WanConfiguration {
  protocol: string;
  supported: boolean;
  pppoe: WanPppoeConfiguration;
  static: WanStaticConfiguration;
}

export interface WanRuntimeStatus {
  connected: boolean;
  pending: boolean;
  protocol: string | null;
  device: string | null;
  address: string | null;
  prefixLength: number | null;
  gateway: string | null;
  dns: string[];
  uptimeSeconds: number;
}

export interface WanSettings {
  configuration: WanConfiguration;
  status: WanRuntimeStatus;
}

export interface WanSettingsInput {
  protocol: WanProtocol;
  pppoeUsername: string;
  pppoePassword: string;
  pppoePasswordChanged: boolean;
  staticAddress: string;
  staticPrefixLength: number;
  staticGateway: string;
  dnsPrimary: string;
  dnsSecondary: string;
}

export interface WanUpdateResult {
  changed: boolean;
  reconnectScheduled: boolean;
  settings: WanSettings;
}

export interface WanReconnectResult {
  accepted: boolean;
  reconnectScheduled: boolean;
  settings: WanSettings;
}
