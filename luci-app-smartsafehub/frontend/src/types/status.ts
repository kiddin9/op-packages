export interface DeviceStatus {
  hostname: string;
  model: string;
  boardName: string | null;
}

export interface SoftwareStatus {
  distribution: string;
  version: string;
  revision: string;
  kernel: string;
}

export interface RuntimeMemory {
  total: number;
  free: number;
  shared: number;
  buffered: number;
  available: number;
  cached: number;
}

export interface RuntimeStatus {
  uptime: number;
  localtime: number;
  load: [number, number, number];
  memory: RuntimeMemory;
}

export interface NetworkStatus {
  available: boolean;
  up: boolean;
  protocol: string | null;
  ipv4Address: string | null;
}

export interface SmartSafeHubStatus {
  device: DeviceStatus;
  software: SoftwareStatus;
  runtime: RuntimeStatus;
  network: NetworkStatus;
}

export interface ApiError {
  code: string;
  message: string;
}

export type ApiResponse<T> =
  | { ok: true; data: T; error: null }
  | { ok: false; data: null; error: ApiError };
