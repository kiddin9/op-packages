import {
  notifySessionExpired,
  SESSION_EXPIRED_MESSAGE,
} from '../auth/sessionEvents';
import type { SmartSafeHubBootstrap } from '../types/bootstrap';
import type { ApiResponse } from '../types/status';

const UBUS_STATUS_TEXT: Readonly<Record<number, string>> = {
  1: '잘못된 명령입니다.',
  2: '요청 인자가 올바르지 않습니다.',
  3: '요청한 메서드를 찾을 수 없습니다.',
  4: '요청한 리소스를 찾을 수 없습니다.',
  5: '응답 데이터가 없습니다.',
  6: '접근 권한이 없습니다.',
  7: '요청 시간이 초과되었습니다.',
  8: '지원하지 않는 기능입니다.',
  9: '장치에서 알 수 없는 오류가 발생했습니다.',
  10: '장치 연결이 끊어졌습니다.',
};

const DEFAULT_TIMEOUT_MS = 20_000;
const SESSION_ACCESS_PROBE_TIMEOUT_MS = 3_000;
const MIN_TIMEOUT_MS = 1_000;
const MAX_TIMEOUT_MS = 60_000;

let requestId = 1;

export interface RpcCallOptions {
  timeoutMs?: number;
}

export class RpcError extends Error {
  readonly code: string;

  constructor(code: string, message: string) {
    super(message);
    this.name = 'RpcError';
    this.code = code;
  }
}

function getBootstrap(): SmartSafeHubBootstrap {
  const bootstrap = window.__SMARTHUB_BOOTSTRAP__;

  if (!bootstrap?.sessionId || !bootstrap.rpcUrl) {
    throw new RpcError(
      'BOOTSTRAP_MISSING',
      'LuCI 세션 정보를 찾을 수 없습니다. 페이지를 새로고침해 주세요.',
    );
  }

  return bootstrap;
}

function isObject(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function invalidResponse(): RpcError {
  return new RpcError(
    'INVALID_RESPONSE',
    '장치 API가 올바르지 않은 응답을 반환했습니다.',
  );
}

function normalizedTimeout(value: number | undefined): number {
  if (typeof value !== 'number' || !Number.isFinite(value)) {
    return DEFAULT_TIMEOUT_MS;
  }

  return Math.min(
    MAX_TIMEOUT_MS,
    Math.max(MIN_TIMEOUT_MS, Math.trunc(value)),
  );
}

function isAccessDenied(error: RpcError): boolean {
  const message = error.message.trim().toLowerCase();

  return (
    error.code === 'UBUS_6' ||
    error.code === 'JSON_RPC_-32002' ||
    (error.code === 'HTTP_ERROR' && /HTTP (401|403)\b/.test(error.message)) ||
    message.includes('access denied') ||
    message.includes('permission denied') ||
    message.includes('접근 권한')
  );
}

function currentSessionMatches(sessionId: string): boolean {
  return window.__SMARTHUB_BOOTSTRAP__?.sessionId === sessionId;
}

type SessionAccessProbeResult = 'active' | 'expired' | 'unknown';

async function probeRpcSessionAccess(
  bootstrap: SmartSafeHubBootstrap,
): Promise<SessionAccessProbeResult> {
  const id = requestId++;
  const controller = new AbortController();
  const timeout = window.setTimeout(
    () => controller.abort(),
    SESSION_ACCESS_PROBE_TIMEOUT_MS,
  );

  try {
    const response = await fetch(bootstrap.rpcUrl, {
      method: 'POST',
      credentials: 'same-origin',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        jsonrpc: '2.0',
        id,
        method: 'call',
        params: [
          bootstrap.sessionId,
          'smartsafehub',
          'system_root_password_status',
          {},
        ],
      }),
      signal: controller.signal,
    });

    if (response.status === 401 || response.status === 403) {
      return 'expired';
    }
    if (!response.ok) {
      return 'unknown';
    }

    const payload: unknown = await response.json();
    if (!isObject(payload) || payload.jsonrpc !== '2.0' || payload.id !== id) {
      return 'unknown';
    }

    if ('error' in payload) {
      const rpcError = payload.error;
      if (
        isObject(rpcError) &&
        typeof rpcError.code === 'number' &&
        rpcError.code === -32002
      ) {
        return 'expired';
      }
      return 'unknown';
    }

    const result = payload.result;
    if (!Array.isArray(result) || result.length < 1) {
      return 'unknown';
    }

    if (result[0] === 0) {
      return 'active';
    }
    if (result[0] === 6) {
      return 'expired';
    }

    return 'unknown';
  } catch {
    return 'unknown';
  } finally {
    window.clearTimeout(timeout);
  }
}

async function sessionExpiryError(
  error: RpcError,
  bootstrap: SmartSafeHubBootstrap,
): Promise<RpcError> {
  if (!isAccessDenied(error) || !currentSessionMatches(bootstrap.sessionId)) {
    return error;
  }

  // A newly installed RPC method may return UBUS_STATUS_PERMISSION_DENIED to
  // an existing LuCI session because rpcd expands ACL groups at login time.
  // Verify the same session against a long-lived SmartSafeHub method before
  // deciding that the session itself has expired. This avoids ejecting the
  // user from Settings merely because the current session predates a new ACL.
  const access = await probeRpcSessionAccess(bootstrap);

  if (!currentSessionMatches(bootstrap.sessionId)) {
    return error;
  }

  if (access === 'active') {
    return new RpcError(
      'RPC_PERMISSION_DENIED',
      '현재 로그인 세션에 이 기능 권한이 없습니다. SmartSafeHub 업데이트 직후라면 로그아웃 후 다시 로그인해 주세요.',
    );
  }
  if (access !== 'expired') {
    return error;
  }

  notifySessionExpired(bootstrap.sessionId);
  return new RpcError('SESSION_EXPIRED', SESSION_EXPIRED_MESSAGE);
}

function parseJsonRpcResponse<T>(payload: unknown, requestIdentifier: number): T {
  if (
    !isObject(payload) ||
    payload.jsonrpc !== '2.0' ||
    payload.id !== requestIdentifier
  ) {
    throw invalidResponse();
  }

  if ('error' in payload) {
    const error = payload.error;

    if (!isObject(error) || typeof error.code !== 'number') {
      throw invalidResponse();
    }

    throw new RpcError(
      `JSON_RPC_${error.code}`,
      typeof error.message === 'string' && error.message.length > 0
        ? error.message
        : 'JSON-RPC 요청에 실패했습니다.',
    );
  }

  const result = payload.result;

  if (!Array.isArray(result) || result.length < 1 || result.length > 2) {
    throw invalidResponse();
  }

  const status = result[0];

  if (typeof status !== 'number' || !Number.isInteger(status)) {
    throw invalidResponse();
  }

  if (status !== 0) {
    throw new RpcError(
      `UBUS_${status}`,
      UBUS_STATUS_TEXT[status] ?? `ubus 오류 코드 ${status}가 반환되었습니다.`,
    );
  }

  if (result.length < 2 || result[1] === undefined) {
    throw new RpcError('EMPTY_RESPONSE', '장치 API 응답이 비어 있습니다.');
  }

  return result[1] as T;
}

export async function callRpc<T>(
  object: string,
  method: string,
  params: Record<string, unknown> = {},
  options: RpcCallOptions = {},
): Promise<T> {
  const bootstrap = getBootstrap();
  const id = requestId++;
  const controller = new AbortController();
  const timeout = window.setTimeout(
    () => controller.abort(),
    normalizedTimeout(options.timeoutMs),
  );

  try {
    const response = await fetch(bootstrap.rpcUrl, {
      method: 'POST',
      credentials: 'same-origin',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        jsonrpc: '2.0',
        id,
        method: 'call',
        params: [bootstrap.sessionId, object, method, params],
      }),
      signal: controller.signal,
    });

    if (!response.ok) {
      throw new RpcError(
        'HTTP_ERROR',
        `장치 API가 HTTP ${response.status} 오류를 반환했습니다.`,
      );
    }

    let payload: unknown;

    try {
      payload = await response.json();
    } catch {
      throw invalidResponse();
    }

    return parseJsonRpcResponse<T>(payload, id);
  } catch (error) {
    if (controller.signal.aborted) {
      throw new RpcError(
        'RPC_TIMEOUT',
        '장치 응답 시간이 초과되었습니다. 잠시 후 다시 시도해 주세요.',
      );
    }

    if (error instanceof RpcError) {
      throw await sessionExpiryError(error, bootstrap);
    }

    throw new RpcError(
      'NETWORK_ERROR',
      '공유기와 통신할 수 없습니다. 네트워크 연결을 확인해 주세요.',
    );
  } finally {
    window.clearTimeout(timeout);
  }
}

export async function callApi<T>(
  object: string,
  method: string,
  params: Record<string, unknown> = {},
  options: RpcCallOptions = {},
): Promise<T> {
  const response = await callRpc<ApiResponse<T>>(object, method, params, options);

  // Reaching the SmartSafeHub API envelope means ubus already authorized and
  // executed the method. Domain errors must therefore stay ordinary API
  // errors instead of being mistaken for an expired LuCI session.
  if (!response.ok) {
    throw new RpcError(response.error.code, response.error.message);
  }

  return response.data;
}
