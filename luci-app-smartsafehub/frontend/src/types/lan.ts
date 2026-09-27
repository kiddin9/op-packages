export interface LanAddressSettings {
  address: string;
  prefixLength: number;
  netmask: string;
  subnet: string;
}

export interface LanDhcpSettings {
  enabled: boolean;
  start: string | null;
  end: string | null;
  leaseTime: string;
}

export interface LanWanSettings {
  connected: boolean;
  protocol: string | null;
  address: string | null;
  prefixLength: number | null;
  subnet: string | null;
}

export interface LanConflictStatus {
  detected: boolean;
  wanSubnet: string | null;
}

export interface LanRecommendation {
  address: string;
  prefixLength: number;
  netmask: string;
  subnet: string;
  dhcpStart: string;
  dhcpEnd: string;
}

export interface LanSettings {
  lan: LanAddressSettings;
  dhcp: LanDhcpSettings;
  wan: LanWanSettings;
  conflict: LanConflictStatus;
  recommendation: LanRecommendation | null;
}

export interface LanSettingsInput {
  ipAddress: string;
  prefixLength: number;
  dhcpEnabled: boolean;
  dhcpStart: string;
  dhcpEnd: string;
  leaseTime: string;
}

export interface LanUpdateResult {
  changed: boolean;
  reloadScheduled: boolean;
  addressChanged: boolean;
  previousAddress?: string | null;
  newAddress?: string | null;
  settings: LanSettings;
}
