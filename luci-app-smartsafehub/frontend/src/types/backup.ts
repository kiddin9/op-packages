export interface ConfigurationBackupValidation {
  validated: boolean;
  filename: string;
  sizeBytes: number;
}

export interface ConfigurationBackupRestoreResult {
  accepted: boolean;
  rebooting: boolean;
}

export interface ConfigurationBackupDiscardResult {
  discarded: boolean;
}

export interface ConfigurationBackupUploadReply {
  failure?: string;
  message?: string;
  name?: string;
}
