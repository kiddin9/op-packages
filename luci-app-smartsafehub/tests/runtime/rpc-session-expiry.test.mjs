// SPDX-License-Identifier: GPL-3.0-or-later

import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const rootDir = fileURLToPath(new URL('../..', import.meta.url));
const rpcSource = readFileSync(`${rootDir}/frontend/src/api/rpc.ts`, 'utf8');

function functionBody(source, signature, nextSignature) {
  const start = source.indexOf(signature);
  assert.notEqual(start, -1, `missing function: ${signature}`);
  const bodyStart = source.indexOf('{', start) + 1;
  const end = source.indexOf(nextSignature, bodyStart);
  assert.notEqual(end, -1, `missing function terminator for: ${signature}`);
  return source.slice(bodyStart, end).replace(/}\s*$/, '');
}

const accessDeniedBody = functionBody(
  rpcSource,
  'function isAccessDenied(error: RpcError): boolean',
  '\n\nfunction currentSessionMatches',
);
const isAccessDenied = new Function('error', `'use strict';\n${accessDeniedBody}`);

for (const error of [
  { code: 'UBUS_6', message: '접근 권한이 없습니다.' },
  { code: 'JSON_RPC_-32002', message: 'Permission denied' },
  { code: 'HTTP_ERROR', message: '장치 API가 HTTP 401 오류를 반환했습니다.' },
  { code: 'HTTP_ERROR', message: '장치 API가 HTTP 403 오류를 반환했습니다.' },
  { code: 'OTHER', message: 'Access denied' },
  { code: 'OTHER', message: 'permission denied' },
  { code: 'OTHER', message: '접근 권한이 없습니다.' },
]) {
  assert.equal(isAccessDenied(error), true, `must recognize access denial: ${error.code} / ${error.message}`);
}

for (const error of [
  { code: 'UBUS_7', message: '요청 시간이 초과되었습니다.' },
  { code: 'HTTP_ERROR', message: '장치 API가 HTTP 500 오류를 반환했습니다.' },
  { code: 'NETWORK_ERROR', message: '공유기와 통신할 수 없습니다.' },
  { code: 'OTHER', message: 'request rejected for another reason' },
]) {
  assert.equal(isAccessDenied(error), false, `must not expire session for unrelated failure: ${error.code}`);
}

assert.match(
  rpcSource,
  /async function probeRpcSessionAccess\([\s\S]*?'system_root_password_status'[\s\S]*?result\[0\] === 0[\s\S]*?return 'active'[\s\S]*?result\[0\] === 6[\s\S]*?return 'expired'/,
  'session verification must probe a long-lived SmartSafeHub RPC and distinguish active from denied sessions',
);
assert.match(
  rpcSource,
  /rpcError\.code === -32002[\s\S]*?return 'expired'/,
  'JSON-RPC access denial during the control probe must mark the session expired',
);
assert.match(
  rpcSource,
  /response\.status === 401 \|\| response\.status === 403/,
  'HTTP authentication denial during the control probe must mark the session expired',
);
assert.equal(
  rpcSource.includes('probeLuciSession'),
  false,
  'RPC recovery must not probe the LuCI session echo endpoint',
);

const expiryBody = functionBody(
  rpcSource,
  'async function sessionExpiryError(',
  '\n\nfunction parseJsonRpcResponse',
);
const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor;

class RpcError extends Error {
  constructor(code, message) {
    super(message);
    this.code = code;
  }
}

async function evaluateExpiry({
  error,
  access,
  requestSessionId = 'session-a',
  currentSessionId = 'session-a',
}) {
  const notifications = [];
  const bootstrap = { sessionId: requestSessionId, rpcUrl: '/ubus' };
  const currentSessionMatches = (sessionId) => sessionId === currentSessionId;
  const probeRpcSessionAccess = async () => access;
  const notifySessionExpired = (sessionId) => notifications.push(sessionId);
  const execute = new AsyncFunction(
    'error',
    'bootstrap',
    'isAccessDenied',
    'currentSessionMatches',
    'probeRpcSessionAccess',
    'notifySessionExpired',
    'RpcError',
    'SESSION_EXPIRED_MESSAGE',
    `'use strict';\n${expiryBody}`,
  );
  const result = await execute(
    error,
    bootstrap,
    isAccessDenied,
    currentSessionMatches,
    probeRpcSessionAccess,
    notifySessionExpired,
    RpcError,
    'expired',
  );
  return { result, notifications };
}

{
  const original = new RpcError('UBUS_6', '접근 권한이 없습니다.');
  const { result, notifications } = await evaluateExpiry({ error: original, access: 'active' });
  assert.equal(result.code, 'RPC_PERMISSION_DENIED');
  assert.match(result.message, /로그아웃 후 다시 로그인/);
  assert.deepEqual(notifications, []);
}

{
  const original = new RpcError('UBUS_6', '접근 권한이 없습니다.');
  const { result, notifications } = await evaluateExpiry({ error: original, access: 'expired' });
  assert.equal(result.code, 'SESSION_EXPIRED');
  assert.deepEqual(notifications, ['session-a']);
}

{
  const original = new RpcError('UBUS_6', '접근 권한이 없습니다.');
  const { result, notifications } = await evaluateExpiry({ error: original, access: 'unknown' });
  assert.equal(result, original, 'an inconclusive control probe must not force logout');
  assert.deepEqual(notifications, []);
}

{
  const original = new RpcError('UBUS_6', '접근 권한이 없습니다.');
  const { result, notifications } = await evaluateExpiry({
    error: original,
    access: 'expired',
    requestSessionId: 'stale-session',
    currentSessionId: 'new-session',
  });
  assert.equal(result, original, 'a late failure from a stale request must not expire the new session');
  assert.deepEqual(notifications, []);
}

{
  const original = new RpcError('NETWORK_ERROR', 'network down');
  const { result, notifications } = await evaluateExpiry({ error: original, access: 'expired' });
  assert.equal(result, original, 'non-authentication failures must stay ordinary RPC errors');
  assert.deepEqual(notifications, []);
}

const callApiStart = rpcSource.indexOf('export async function callApi<T>');
assert.notEqual(callApiStart, -1, 'callApi implementation must exist');
const callApiBody = rpcSource.slice(callApiStart);
assert.equal(
  callApiBody.includes('sessionExpiryError('),
  false,
  'SmartSafeHub domain errors returned after an authorized ubus call must never be reclassified as session expiry',
);
assert.match(
  callApiBody,
  /throw new RpcError\(response\.error\.code, response\.error\.message\)/,
  'SmartSafeHub domain errors must remain ordinary RpcError instances',
);

console.log('PASS: RPC access denial distinguishes stale ACL permissions from an actually expired LuCI session');
