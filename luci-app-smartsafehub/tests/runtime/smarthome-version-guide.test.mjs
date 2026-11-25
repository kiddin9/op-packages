// SPDX-License-Identifier: GPL-3.0-or-later
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import { assessJarbisCompatibility, compareJarbisVersions, JARBIS_FULL_FEATURE_VERSION, JARBIS_REQUIREMENTS } from '../../frontend/src/utils/jarbisCompatibility.ts';

const read = path => readFileSync(new URL(`../../${path}`, import.meta.url), 'utf8');
const ready = (version, features) => ({ version, features, enabled: true, brokerMode: 'managed' });
const all = { shellyHtg3: true, shellyQuickPair: true, rooms: true };

test('Jarbis 버전 비교는 0.2.4와 APK revision의 경계를 정확히 구분한다', () => {
  assert.equal(compareJarbisVersions('0.2.3-r999', '0.2.4'), -1);
  assert.equal(compareJarbisVersions('0.2.4', '0.2.4'), 0);
  assert.equal(compareJarbisVersions('0.2.4-r1', '0.2.4'), 1);
  assert.equal(compareJarbisVersions('0.2.5-r1', '0.2.4'), 1);
  assert.equal(compareJarbisVersions('0.3.0-r1', '0.2.4'), 1);
  assert.equal(compareJarbisVersions('0.2.4-r10', '0.2.4-r9'), 1);
  assert.equal(compareJarbisVersions('unknown', '0.2.4'), null);
  assert.equal(compareJarbisVersions('0.2.4-r1-rc', '0.2.4'), null);
  assert.equal(compareJarbisVersions('0.2.4-r1-nope', '0.2.4'), null);
});

test('센서·자동 연결·공간 관리의 공통 최소 버전은 0.2.4이다', () => {
  assert.equal(JARBIS_FULL_FEATURE_VERSION, '0.2.4');
  assert.deepEqual(JARBIS_REQUIREMENTS.map(x => x.minimum), ['0.2.4', '0.2.4', '0.2.4']);
  assert.equal(assessJarbisCompatibility(ready('0.2.4', all)).needsAttention, false);
  assert.equal(assessJarbisCompatibility(ready('0.2.4-r1', all)).needsAttention, false);
  assert.deepEqual(assessJarbisCompatibility(ready('0.2.3-r5', all)).issues.map(x => x.reason), ['version', 'version', 'version']);
  assert.deepEqual(assessJarbisCompatibility(ready('0.2.3-r1', {})).issues.map(x => x.key), ['shellyHtg3', 'shellyQuickPair', 'rooms']);
  assert.equal(assessJarbisCompatibility(ready('0.2.3-r999', all)).needsUpgrade, true);
  assert.equal(assessJarbisCompatibility(null).needsAttention, false);
});

test('0.2.4 이상이라도 실제 기능 flag가 없으면 지원 완료로 간주하지 않는다', () => {
  const mismatch = assessJarbisCompatibility(ready('0.2.4-r1', { shellyHtg3: true }));
  assert.deepEqual(mismatch.issues.map(x => x.reason), ['capability', 'capability']);
  assert.equal(mismatch.needsUpgrade, false);
  const unknown = assessJarbisCompatibility(ready('development', {}));
  assert.equal(unknown.needsUpgrade, false);
  assert.deepEqual(unknown.issues.map(x => x.reason), ['unknown', 'unknown', 'unknown']);
});

test('스마트홈은 승인된 Apps로만 안내하고 자동 설치하지 않는다', () => {
  const notice = read('frontend/src/components/SmartHomeVersionNotice.tsx');
  const page = read('frontend/src/pages/SmartHomePage.tsx');
  const app = read('frontend/src/app/App.tsx');
  const apps = read('frontend/src/pages/AppsPage.tsx');
  assert.match(page, /<SmartHomeVersionNotice status=\{status\}/);
  assert.match(notice, /href="#apps\?highlight=jarbis"/);
  assert.match(notice, /compareJarbisVersions\(offered\.version, JARBIS_FULL_FEATURE_VERSION\)/);
  assert.match(notice, /!hasApprovedCompatible/);
  assert.match(notice, /사용자 승인 후에만 설치합니다/);
  assert.doesNotMatch(notice, /installVerifiedApp|onUpdate|callRpc|fetch\(/);
  assert.match(app, /jarbisNeedsUpgrade = route === 'smarthome'/);
  assert.match(app, /\|\| jarbisNeedsUpgrade/);
  assert.match(app, /jarbisNeedsUpgrade \? null :/);
  assert.match(apps, /window\.confirm\(`\$\{app\.name\} 앱을 최신 승인 버전으로 업데이트/);
  assert.match(apps, /guidedState\.updateAvailable/);
  assert.match(apps, /해당 배포 채널의 업데이트를 기다려 주세요/);
});

test('기기 종류는 센서와 전구에 동일한 규칙을 사용하고, 이름은 그대로 유지한다', () => {
  const sensor = read('frontend/src/components/SmartHomeSensorCard.tsx');
  const page = read('frontend/src/pages/SmartHomePage.tsx');
  const demo = read('frontend/src/demo/data.ts');
  assert.match(sensor, /<h3[^>]+>\{device\.name\}<\/h3>/);
  assert.match(sensor, /ssh-home-device-subtitle">Wi-Fi 온습도 센서/);
  assert.match(sensor, /ThermometerIcon class=\"size-5\"/);
  assert.doesNotMatch(sensor, /DevicesIcon class=\"size-5\"/);
  assert.match(page, /Wi-Fi 스마트 전구<\/p>/);
  assert.match(page, /온습도 센서의 측정값/);
  assert.doesNotMatch(page, /Shelly H&T Gen3의 온도·습도/);
  assert.match(demo, /version: '0\.2\.4-r1'/);
  assert.match(demo, /features: \{ shellyHtg3: true, shellyQuickPair: true, rooms: true \}/);
});
