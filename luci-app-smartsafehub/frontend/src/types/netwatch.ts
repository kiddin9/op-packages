export interface NetwatchDevice {
  ip: string;
  connections: number;
  destinations: number;
}

export interface NetwatchStatus {
  schema: 1;
  enabled: boolean;
  phase: 'preparing' | 'ready' | 'unavailable' | 'disabled';
  sampledAt: number;
  intervalSeconds: number;
  source: string;
  ipv4Only: boolean;
  limited: boolean;
  totalConnections: number;
  totalDevices: number;
  devices: NetwatchDevice[];
  alert: NetwatchDevice | null;
}
