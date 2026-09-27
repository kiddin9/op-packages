export type IptvProvider = 'skb' | 'lgu';

export interface IptvSettings {
  enabled: boolean;
  provider: IptvProvider;
  beta: boolean;
  available: boolean;
  running: boolean;
  upstreamNetwork: string;
  downstreamNetwork: string;
  lanBridge: string | null;
  igmpSnooping: boolean;
}

export interface IptvSettingsInput {
  enabled: boolean;
  provider: IptvProvider;
}

export interface IptvUpdateResult {
  changed: boolean;
  settings: IptvSettings;
}
