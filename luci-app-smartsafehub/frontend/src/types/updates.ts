export type SoftwareUpdatePhase = 'idle' | 'checking' | 'installing' | 'error';
export type SoftwareUpdateChannel = 'stable' | 'beta' | 'unknown';

export interface SoftwareUpdatePackage {
  name: string;
  installedVersion: string;
  availableVersion: string | null;
  updateAvailable: boolean;
}

export interface SoftwareReleaseNoteSection {
  title: string;
  items: string[];
}

export interface SoftwareReleaseNote {
  schemaVersion: number;
  package: string;
  version: string;
  date: string | null;
  summary: string | null;
  sections: SoftwareReleaseNoteSection[];
}

export interface SoftwareUpdateError {
  code: string;
  message: string;
  at: number | null;
}

export interface SoftwareUpdateSettings {
  channel: SoftwareUpdateChannel;
  checkEnabled: boolean;
  checkIntervalSeconds: number;
  autoInstall: boolean;
  autoInstallTime: string;
  repositoryHost: string;
  updatePackage: string;
}

export interface SoftwareUpdateStatus {
  phase: SoftwareUpdatePhase;
  updateCount: number;
  packages: SoftwareUpdatePackage[];
  lastCheckAt: number | null;
  lastInstallAt: number | null;
  lastError: SoftwareUpdateError | null;
  releaseNotes: SoftwareReleaseNote[];
  releaseNotesComplete: boolean;
  settings: SoftwareUpdateSettings;
}

export interface SoftwareUpdateSettingsInput {
  checkEnabled: boolean;
  checkIntervalSeconds: number;
  autoInstall: boolean;
  autoInstallTime: string;
}

export interface SoftwareUpdateAccepted {
  accepted: boolean;
}
