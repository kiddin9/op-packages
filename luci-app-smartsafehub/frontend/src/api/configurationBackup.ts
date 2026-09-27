import type { ConfigurationBackupUploadReply } from '../types/backup';
import { cgiUrl } from '../utils/luci';
import { RpcError } from './rpc';

const BACKUP_UPLOAD_PATH = '/tmp/smartsafehub/config-backup.tar.gz';
const BACKUP_DOWNLOAD_ENDPOINT = '/cgi-backup';
const BACKUP_UPLOAD_ENDPOINT = '/cgi-upload';

function sessionId(): string {
  const value = window.__SMARTHUB_BOOTSTRAP__?.sessionId;
  if (!value) {
    throw new RpcError('BOOTSTRAP_MISSING', 'LuCI 세션 정보를 찾을 수 없습니다.');
  }
  return value;
}

function responseFilename(value: string | null): string {
  const match = value?.match(/filename="?([^";]+)"?/i);
  const filename = match?.[1]?.trim();

  return filename || 'backup-openwrt.tar.gz';
}

function downloadBlob(filename: string, blob: Blob): void {
  const url = URL.createObjectURL(blob);
  const anchor = document.createElement('a');

  anchor.href = url;
  anchor.download = filename;
  anchor.style.display = 'none';
  (document.body ?? document.documentElement).appendChild(anchor);
  anchor.click();
  anchor.remove();
  window.setTimeout(() => URL.revokeObjectURL(url), 1000);
}

export async function downloadConfigurationBackup(): Promise<void> {
  const endpoint = cgiUrl(BACKUP_DOWNLOAD_ENDPOINT);
  const response = await fetch(endpoint, {
    method: 'POST',
    credentials: 'same-origin',
    headers: {
      'Content-Type': 'application/x-www-form-urlencoded;charset=UTF-8',
    },
    body: new URLSearchParams({ sessionid: sessionId() }).toString(),
  });

  if (!response.ok) {
    throw new RpcError(
      'SYSTEM_BACKUP_DOWNLOAD_FAILED',
      `설정 백업 생성에 실패했습니다. (HTTP ${response.status})`,
    );
  }

  const blob = await response.blob();
  if (blob.size <= 0) {
    throw new RpcError(
      'SYSTEM_BACKUP_DOWNLOAD_EMPTY',
      '설정 백업 파일이 비어 있습니다.',
    );
  }

  downloadBlob(
    responseFilename(response.headers.get('Content-Disposition')),
    blob,
  );
}

export function uploadConfigurationBackup(
  file: File,
  onProgress?: (percent: number) => void,
): Promise<ConfigurationBackupUploadReply> {
  let sid: string;
  try {
    sid = sessionId();
  } catch (error) {
    return Promise.reject(error);
  }

  return new Promise((resolve, reject) => {
    const request = new XMLHttpRequest();
    const data = new FormData();

    data.append('sessionid', sid);
    data.append('filename', BACKUP_UPLOAD_PATH);
    data.append('filedata', file);

    request.open('POST', cgiUrl(BACKUP_UPLOAD_ENDPOINT));
    request.timeout = 0;

    request.upload.addEventListener('progress', (event) => {
      if (!event.lengthComputable || event.total <= 0) {
        return;
      }
      onProgress?.(Math.min(100, Math.max(0, (event.loaded / event.total) * 100)));
    });

    request.addEventListener('error', () => {
      reject(
        new RpcError(
          'SYSTEM_BACKUP_UPLOAD_FAILED',
          '설정 백업 파일을 공유기에 업로드하지 못했습니다.',
        ),
      );
    });

    request.addEventListener('load', () => {
      if (request.status < 200 || request.status >= 300) {
        reject(
          new RpcError(
            'SYSTEM_BACKUP_UPLOAD_HTTP_ERROR',
            `설정 백업 업로드가 HTTP ${request.status} 오류를 반환했습니다.`,
          ),
        );
        return;
      }

      let reply: ConfigurationBackupUploadReply;
      try {
        reply = JSON.parse(request.responseText) as ConfigurationBackupUploadReply;
      } catch {
        reject(
          new RpcError(
            'SYSTEM_BACKUP_UPLOAD_INVALID_RESPONSE',
            '설정 백업 업로드 응답을 확인하지 못했습니다.',
          ),
        );
        return;
      }

      if (reply.failure) {
        reject(
          new RpcError(
            reply.failure,
            reply.message || '설정 백업 파일 업로드가 거부되었습니다.',
          ),
        );
        return;
      }

      onProgress?.(100);
      resolve({ ...reply, name: file.name });
    });

    request.send(data);
  });
}
