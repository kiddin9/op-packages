export type FirmwarePhase =
  | 'idle'
  | 'checking'
  | 'downloading'
  | 'verifying'
  | 'ready'
  | 'flashing'
  | 'error';

export type FirmwareSource = 'online' | 'manual' | null;
export type FirmwareChannel = 'stable' | 'beta';

export interface FirmwareError {
  code: string;
  message: string;
}

export interface FirmwareCurrent {
  deviceCode: string | null;
  boardName: string | null;
  buildId: string | null;
  releaseVersion: string | null;
  openwrtVersion: string | null;
  metadataAvailable: boolean;
}

export interface FirmwareImage {
  id: number;
  filename: string | null;
  sizeBytes: number | null;
  sha256: string | null;
}

export interface FirmwareRelease {
  id: number;
  buildId: string | null;
  version: string | null;
  deviceCode: string | null;
  channel: string | null;
  target: string | null;
  profile: string | null;
  openwrtVersion: string | null;
  publishedAt: string | null;
  releaseNotes: string[];
  sysupgrade: FirmwareImage;
}

export interface PreparedFirmware {
  source: FirmwareSource;
  filename: string | null;
  sizeBytes: number | null;
  sha256: string | null;
  allowBackup: boolean;
  targetBuildId: string | null;
}

export interface FirmwareSettings {
  channel: FirmwareChannel;
  apiBaseUrl: string;
  checkIntervalSeconds: number;
  autoInstall: false;
}

export interface FirmwareStatus {
  phase: FirmwarePhase;
  source: FirmwareSource;
  lastCheckAt: number | null;
  lastPrepareAt: number | null;
  lastError: FirmwareError | null;
  prepared: PreparedFirmware | null;
  current: FirmwareCurrent;
  updateAvailable: boolean;
  release: FirmwareRelease | null;
  settings: FirmwareSettings;
}

export interface FirmwareAccepted {
  accepted: boolean;
}

export interface FirmwareUploadReply {
  name?: string;
  size?: number;
  checksum?: string;
  sha256sum?: string;
  failure?: string;
  message?: string;
}
