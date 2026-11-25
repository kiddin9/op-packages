// SPDX-License-Identifier: GPL-3.0-or-later
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
const root = new URL('../../', import.meta.url);
const read = path => readFileSync(new URL(path, root), 'utf8');
const page = read('frontend/src/pages/SmartHomePage.tsx');
const card = read('frontend/src/components/SmartHomeSensorCard.tsx');
const api = read('frontend/src/api/jarbis.ts');
const types = read('frontend/src/types/jarbis.ts');
const notes = read('CHANGELOG.md');

test('Shelly 연결 도우미는 백엔드 capability를 확인하고 기존 버전과 호환된다', () => {
  assert.match(types, /shellyQuickPair\?: boolean/);
  assert.match(page, /supportsShellyQuickPair = status\?\.features\?\.shellyQuickPair === true && status\?\.brokerMode === 'managed'/);
  assert.match(page, /if \(supportsShellyQuickPair\) await pairSensor\(id\)/);
  assert.match(page, /기존 Jarbis에서는 MQTT 연결 정보를 수동으로 설정/);
});
test('사용자 승인과 다른 MQTT 서버 변경 승인 없이는 센서 설정을 변경하지 않는다', () => {
  assert.match(page, /window\.confirm\(isSensor \?/);
  assert.match(page, /window\.confirm\('센서가 다른 MQTT 서버를 사용합니다/);
  assert.match(page, /await pairSensor\(id, true\)/);
  assert.match(api, /'device_pair'/);
  assert.doesNotMatch(page, /getJarbisCredentials\(\)[\s\S]{0,100}pairSensor/);
});
test('절전/최초 측정 대기 시 재시도 UI가 나오고 5분마다 캐시만 조회한다', () => {
  assert.match(card, /첫 측정 대기/);
  assert.match(card, /연결 다시 시도/);
  assert.match(card, /onClick=\{onConnect\}/);
  assert.match(page, /largeHome \? 30000 : 300000/);
  assert.match(api, /getJarbisSensorState.*\n[\s\S]*'sensor_state'/);
});
test('RPC 비밀번호는 프론트엔드가 읽지 않고 자동 설정에 전달하지 않는다', () => {
  assert.match(api, /device_pair.*admin_password:/);
  assert.match(page, /pairJarbisDevice\(id, '', replace\)/);
  assert.match(page, /getJarbisCredentials\(\)/); // 고급 수동 진단만
  assert.match(notes, /0\.2\.34-r7/);
  // Package revision consistency is checked by test-package-contract.sh.
});
