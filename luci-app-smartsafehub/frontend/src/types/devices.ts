export type DeviceConnection = 'wifi' | 'ethernet' | 'unknown';

export interface ConnectedDevice {
  id: string;
  hostname: string | null;
  mac: string;
  ipv4Address: string | null;
  connection: DeviceConnection;
  online: boolean;
  leaseActive: boolean;
  leaseExpiresAt: number | null;
  interface: string | null;
  ssid: string | null;
  radio: string | null;
  band: string | null;
  bandLabel: string | null;
  signalDbm: number | null;
  inactiveMs: number | null;
  connectedSeconds: number | null;
}

export interface ConnectedDeviceTotals {
  known: number;
  online: number;
  wireless: number;
  ethernet: number;
  offline: number;
}

export interface ConnectedDevicesSummary {
  generatedAt: number;
  devices: ConnectedDevice[];
  totals: ConnectedDeviceTotals;
}
