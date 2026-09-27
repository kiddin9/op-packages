import { useCallback, useState } from 'preact/hooks';

import {
  downloadConfigurationBackup,
  uploadConfigurationBackup,
} from '../api/configurationBackup';
import {
  requestConfigurationBackupDiscard,
  requestConfigurationBackupRestore,
  requestConfigurationBackupValidation,
} from '../api/smartsafehub';
import type { ConfigurationBackupValidation } from '../types/backup';
import { errorMessage } from '../utils/errors';

const MAX_BACKUP_BYTES = 16 * 1024 * 1024;

export type ConfigurationBackupAction =
  | 'download'
  | 'upload'
  | 'validate'
  | 'restore'
  | 'discard'
  | null;

export function useConfigurationBackup() {
  const [action, setAction] = useState<ConfigurationBackupAction>(null);
  const [error, setError] = useState<string | null>(null);
  const [message, setMessage] = useState<string | null>(null);
  const [validated, setValidated] = useState<ConfigurationBackupValidation | null>(null);
  const [uploadProgress, setUploadProgress] = useState<number | null>(null);
  const [restoreAccepted, setRestoreAccepted] = useState(false);

  const download = useCallback(async () => {
    setAction('download');
    setError(null);
    setMessage(null);
    try {
      await downloadConfigurationBackup();
      setMessage('현재 설정 백업을 다운로드했습니다.');
    } catch (cause) {
      setError(errorMessage(cause, '설정 백업을 다운로드하지 못했습니다.'));
    } finally {
      setAction(null);
    }
  }, []);

  const upload = useCallback(async (file: File): Promise<boolean> => {
    setError(null);
    setMessage(null);
    setValidated(null);
    setRestoreAccepted(false);

    if (file.size <= 0 || file.size > MAX_BACKUP_BYTES) {
      setError('설정 백업 파일은 16MB 이하여야 합니다.');
      return false;
    }

    try {
      setAction('upload');
      setUploadProgress(0);
      await uploadConfigurationBackup(file, setUploadProgress);
      setAction('validate');
      const result = await requestConfigurationBackupValidation(file.name);
      setValidated(result);
      setMessage('백업 파일 검증이 완료되었습니다. 복원 내용을 확인해 주세요.');
      return true;
    } catch (cause) {
      setError(errorMessage(cause, '설정 백업 파일을 검증하지 못했습니다.'));
      return false;
    } finally {
      setAction(null);
      setUploadProgress(null);
    }
  }, []);

  const discard = useCallback(async (): Promise<boolean> => {
    setAction('discard');
    setError(null);
    setMessage(null);
    try {
      await requestConfigurationBackupDiscard();
      setValidated(null);
      setRestoreAccepted(false);
      setMessage('업로드한 백업 파일을 삭제했습니다.');
      return true;
    } catch (cause) {
      setError(errorMessage(cause, '업로드한 백업 파일을 삭제하지 못했습니다.'));
      return false;
    } finally {
      setAction(null);
    }
  }, []);

  const restore = useCallback(async (): Promise<boolean> => {
    if (!validated) {
      setError('먼저 복원할 백업 파일을 업로드하고 검증해 주세요.');
      return false;
    }

    setAction('restore');
    setError(null);
    setMessage(null);
    try {
      const result = await requestConfigurationBackupRestore();
      setRestoreAccepted(result.accepted && result.rebooting);
      setValidated(null);
      setMessage(
        result.accepted
          ? '설정을 복원했습니다. 공유기가 재부팅되며 네트워크 설정에 따라 다시 연결해야 할 수 있습니다.'
          : '설정 복원 요청이 접수되지 않았습니다.',
      );
      return result.accepted;
    } catch (cause) {
      setError(errorMessage(cause, '설정 백업을 복원하지 못했습니다.'));
      return false;
    } finally {
      setAction(null);
    }
  }, [validated]);

  const dismissFeedback = useCallback(() => {
    setError(null);
    setMessage(null);
  }, []);

  return {
    action,
    discard,
    dismissFeedback,
    download,
    error,
    message,
    restore,
    restoreAccepted,
    upload,
    uploadProgress,
    validated,
  };
}
