// SPDX-License-Identifier: GPL-3.0-or-later

import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const rootDir = fileURLToPath(new URL('../..', import.meta.url));
const sessionSource = readFileSync(
  `${rootDir}/frontend/src/auth/session.ts`,
  'utf8',
);

function extractBody(source, startMarker, endMarker) {
  const start = source.indexOf(startMarker);
  assert.notEqual(start, -1, `missing source marker: ${startMarker}`);
  const bodyStart = source.indexOf('{', start) + 1;
  const end = source.indexOf(endMarker, bodyStart);
  assert.notEqual(end, -1, `missing source terminator after: ${startMarker}`);
  return source.slice(bodyStart, end).replace(/}\s*$/, '');
}

const sessionBody = extractBody(
  sessionSource,
  'async function sessionIdFromResponse(response: Response): Promise<string | null>',
  '\n\nasync function fetchSession',
);
const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor;
const parseSessionResponse = new AsyncFunction(
  'response',
  'SESSION_ID_PATTERN',
  'loginRequired',
  `'use strict';\n${sessionBody}`,
);
const sessionIdPattern = /^[0-9a-f]{32}$/i;
const loginRequired = (response) =>
  response.headers.get('X-LuCI-Login-Required') === 'yes';

function response({
  status = 200,
  body = '',
  redirected = false,
  loginRequiredHeader = null,
} = {}) {
  return {
    status,
    ok: status >= 200 && status < 300,
    redirected,
    headers: {
      get(name) {
        return name === 'X-LuCI-Login-Required' ? loginRequiredHeader : null;
      },
    },
    async text() {
      return body;
    },
  };
}

async function parse(options) {
  return parseSessionResponse(
    response(options),
    sessionIdPattern,
    loginRequired,
  );
}

assert.equal(
  await parse({ body: '0123456789abcdef0123456789abcdef' }),
  '0123456789abcdef0123456789abcdef',
  'a valid LuCI session id must remain authenticated',
);
assert.equal(await parse({ status: 401 }), null, 'HTTP 401 must require login');
assert.equal(await parse({ status: 403 }), null, 'HTTP 403 must require login');
assert.equal(
  await parse({ loginRequiredHeader: 'yes' }),
  null,
  'X-LuCI-Login-Required must require login even on HTTP 200',
);

for (const body of [
  'Access denied',
  'Access denied.',
  'permission denied',
  ' Permission Denied. ',
  '<!doctype html><html><body>login</body></html>',
  '<html><body>login</body></html>',
]) {
  assert.equal(
    await parse({ body }),
    null,
    `unauthenticated response body must require login: ${body}`,
  );
}

assert.equal(
  await parse({ body: 'not-a-session', redirected: true }),
  null,
  'a followed redirect with a non-session body must require login',
);

await assert.rejects(
  () => parse({ status: 500 }),
  /LuCI session endpoint returned HTTP 500/,
  'server failures must not be misreported as an authenticated or expired session',
);
await assert.rejects(
  () => parse({ body: 'unexpected payload' }),
  /invalid session id/,
  'unexpected HTTP 200 payloads must not silently authenticate',
);

console.log('PASS: LuCI session responses distinguish valid sessions, expiry signals, and invalid failures');
