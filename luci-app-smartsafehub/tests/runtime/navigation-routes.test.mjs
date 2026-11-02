// SPDX-License-Identifier: GPL-3.0-or-later
// Execute the real route registry rather than matching its source formatting.
import assert from 'node:assert/strict';
import test from 'node:test';
import { DEMO_ROUTES, ROUTE_BY_NAME, ROUTES } from '../../frontend/src/app/routes.ts';

test('네트워크 설정은 WAN과 LAN을 하나의 화면으로 제공한다', () => {
  assert.equal(ROUTE_BY_NAME.network.route, 'network');
  assert.equal(ROUTE_BY_NAME.network.hash, '#network');
  assert.equal(ROUTE_BY_NAME.network.label, '네트워크');
  assert.ok(!('wan' in ROUTE_BY_NAME), 'WAN must not be exposed as a separate route');
  assert.ok(!('lan' in ROUTE_BY_NAME), 'LAN must not be exposed as a separate route');
});

test('라우팅 이름과 URL 해시는 유일하고 데모 링크는 실제 화면만 사용한다', () => {
  const names = ROUTES.map(({ route }) => route);
  const hashes = ROUTES.map(({ hash }) => hash);
  assert.equal(new Set(names).size, ROUTES.length, 'route names must be unique');
  assert.equal(new Set(hashes).size, ROUTES.length, 'hash URLs must be unique');
  for (const definition of ROUTES) {
    assert.strictEqual(ROUTE_BY_NAME[definition.route], definition);
    assert.ok(definition.hash.startsWith('#'));
  }
  for (const demoRoute of DEMO_ROUTES) {
    assert.ok(ROUTE_BY_NAME[demoRoute], `unknown demo route: ${demoRoute}`);
  }
});
