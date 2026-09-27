export type WifiSecurity = 'none' | 'psk2' | 'sae-mixed' | 'sae' | 'custom';
export type WifiSecurityChoice = Exclude<WifiSecurity, 'custom'> | 'keep';

export interface WifiNetworkSummary {
  section: string;
  device: string;
  band: '2g' | '5g' | '6g' | 'unknown';
  bandLabel: string;
  ssid: string;
  enabled: boolean;
  runtimeUp: boolean;
  security: WifiSecurity;
  securityRaw: string;
  passwordConfigured: boolean;
  channel: string | null;
  networks: string[];
  clientCount: number;
}

export interface WifiSummary {
  networks: WifiNetworkSummary[];
  totalClients: number;
}

export interface WifiUpdateInput {
  section: string;
  ssid: string;
  security: WifiSecurityChoice;
  password: string;
  enabled: boolean;
}

export interface WifiUpdateResult {
  changed: boolean;
  reloaded: boolean;
  summary: WifiSummary;
}
