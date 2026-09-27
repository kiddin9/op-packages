import type { FirmwareUploadReply } from '../types/firmware';
import { RpcError } from './rpc';
import { cgiUrl } from '../utils/luci';

const FIRMWARE_UPLOAD_PATH = '/tmp/smartsafehub/firmware.bin';
const FIRMWARE_UPLOAD_ENDPOINT = '/cgi-upload';

export function uploadFirmwareFile(
  file: File,
  onProgress?: (percent: number) => void,
): Promise<FirmwareUploadReply> {
  const bootstrap = window.__SMARTHUB_BOOTSTRAP__;
  if (!bootstrap?.sessionId) {
    return Promise.reject(
      new RpcError('BOOTSTRAP_MISSING', 'LuCI 세션 정보를 찾을 수 없습니다.'),
    );
  }

  return new Promise((resolve, reject) => {
    const request = new XMLHttpRequest();
    const data = new FormData();

    data.append('sessionid', bootstrap.sessionId);
    data.append('filename', FIRMWARE_UPLOAD_PATH);
    data.append('filedata', file);

    const uploadUrl = cgiUrl(FIRMWARE_UPLOAD_ENDPOINT);

    request.open('POST', uploadUrl);
    request.timeout = 0;

    request.upload.addEventListener('progress', (event) => {
      if (!event.lengthComputable || event.total <= 0) {
        return;
      }
      onProgress?.(Math.min(100, Math.max(0, (event.loaded / event.total) * 100)));
    });

    request.addEventListener('error', () => {
      console.error('[SmartSafeHub] firmware upload network error', {
        endpoint: uploadUrl,
        destination: FIRMWARE_UPLOAD_PATH,
        fileName: file.name,
        fileSize: file.size,
        readyState: request.readyState,
        status: request.status,
      });
      reject(
        new RpcError(
          'FIRMWARE_UPLOAD_FAILED',
          `펌웨어 파일 업로드에 실패했습니다. (${uploadUrl}, 네트워크 오류)`,
        ),
      );
    });

    request.addEventListener('load', () => {
      if (request.status < 200 || request.status >= 300) {
        console.error('[SmartSafeHub] firmware upload HTTP error', {
          endpoint: uploadUrl,
          destination: FIRMWARE_UPLOAD_PATH,
          fileName: file.name,
          fileSize: file.size,
          readyState: request.readyState,
          status: request.status,
          response: request.responseText,
        });
        reject(
          new RpcError(
            'FIRMWARE_UPLOAD_HTTP_ERROR',
            `펌웨어 업로드가 HTTP ${request.status} 오류를 반환했습니다. (${uploadUrl})`,
          ),
        );
        return;
      }

      let reply: FirmwareUploadReply;
      try {
        reply = JSON.parse(request.responseText) as FirmwareUploadReply;
      } catch {
        console.error('[SmartSafeHub] firmware upload returned invalid JSON', {
          endpoint: uploadUrl,
          destination: FIRMWARE_UPLOAD_PATH,
          fileName: file.name,
          fileSize: file.size,
          readyState: request.readyState,
          status: request.status,
          response: request.responseText,
        });
        reject(
          new RpcError(
            'FIRMWARE_UPLOAD_INVALID_RESPONSE',
            `펌웨어 업로드 응답을 확인하지 못했습니다. (${uploadUrl})`,
          ),
        );
        return;
      }

      if (reply.failure) {
        reject(
          new RpcError(
            reply.failure,
            reply.message || '펌웨어 파일 업로드가 거부되었습니다.',
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
