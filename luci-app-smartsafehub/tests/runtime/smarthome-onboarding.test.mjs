// SPDX-License-Identifier: GPL-3.0-or-later
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import { smartHomeEntry } from '../../frontend/src/utils/smartHomeEntry.ts';

const source = (path) => readFileSync(new URL(`../../${path}`, import.meta.url), 'utf8');
const catalog = { schema: 1, deviceCode: 'test', firmwareBuildId: 'build', channel: 'stable',
  ready: true, apps: [{ id: 'jarbis', name: 'Jarbis' }] };
const unapprovedCatalog = { ...catalog, apps: [] };
const status = (jarbis, overrides = {}) => ({ ready: true, installed: jarbis ? { jarbis } : {},
  job: { phase: 'idle', action: '', appId: '', code: '' }, ...overrides });
const entry = (apps, approved = catalog, appsError = null, catalogError = null) =>
  smartHomeEntry(null, 'UBUS_3', apps, approved, appsError, catalogError);

test('Jarbis 미설치·승인 확인 시에만 설치 안내를 보여준다', () => {
  assert.equal(entry(status(null)), 'install');
  assert.equal(entry(status(null), unapprovedCatalog), 'unavailable');
  assert.equal(entry(status(null), null), 'checking');
  assert.equal(entry(status(null), null, null, '목록 실패'), 'unknown');
  assert.equal(entry(null), 'checking');
  assert.equal(entry(status(null, { ready: false })), 'checking');
  assert.equal(entry(null, catalog, '상태 실패'), 'unknown');
});

test('설치된 Jarbis RPC 장애는 미설치로 오인하지 않는다', () => {
  assert.equal(entry(status({ installed: true, managed: true })), 'service-error');
  assert.equal(entry(status({ installed: false, managed: true })), 'repair');
  assert.equal(entry(status({ installed: false, partial: true, managed: false })), 'repair');
  assert.equal(smartHomeEntry(null, null, status(null), catalog, null, null), 'checking');
  assert.equal(smartHomeEntry({ enabled: true }, 'UBUS_3', null, null, '실패', '실패'), 'ready');
});

test('설치·복원 진행 중에는 설치를 다시 안내하지 않는다', () => {
  for (const phase of ['starting', 'running']) {
    assert.equal(entry(status(null, { job: { phase, appId: 'jarbis' } })), 'installing');
    assert.equal(entry(status(null, { restore: { phase, appId: 'jarbis' } })), 'installing');
  }
  assert.equal(entry(status(null, { job: { phase: 'running', appId: 'retro-arcade' } })), 'install');
});

test('스마트홈 설치 안내는 승인된 Apps 화면만 연결하고 자동 설치하지 않는다', () => {
  const page = source('frontend/src/pages/SmartHomePage.tsx');
  const welcome = source('frontend/src/components/SmartHomeWelcome.tsx');
  const app = source('frontend/src/app/App.tsx');
  const appsPage = source('frontend/src/pages/AppsPage.tsx');
  const routes = source('frontend/src/hooks/useHashRoute.ts');
  assert.match(page, /smartHomeEntry\(status, statusResource.error, appsStatus, appsCatalog/);
  assert.match(welcome, /href="#apps\?highlight=jarbis"/);
  assert.match(welcome, /Jarbis 설치하기/);
  assert.match(routes, /'#apps\/jarbis': 'apps'/);
  assert.match(app, /appsStatus=\{appsStatus.data\} appsCatalog=\{apps.data\}/);
  assert.match(app, /route === 'apps' \|\| \(route === 'smarthome' && !jarbisStatus.data/);
  assert.match(appsPage, /appsHighlightFromHash\(window.location.hash\)/);
  assert.match(appsPage, /href="#smarthome">스마트홈 시작하기/);
  assert.match(appsPage, /requestOperation\(app, managed \? 'repair' : 'install'\)/);
  assert.doesNotMatch(welcome, /installVerifiedApp|repairVerifiedApp|callApi/);
});

test('Jarbis 설치 후 전구가 없는 경우만 첫 기기 안내를 표시한다', () => {
  const page = source('frontend/src/pages/SmartHomePage.tsx');
  assert.match(page, /status && deviceData && devices.length === 0/);
  assert.match(page, /첫 번째 스마트 전구를 연결해 보세요/);
  assert.match(page, /discoverySection.current\?\.scrollIntoView/);
  assert.match(page, /aria-label="새 전구 찾기"/);
  assert.match(page, /전구 찾으러 가기/);
});
