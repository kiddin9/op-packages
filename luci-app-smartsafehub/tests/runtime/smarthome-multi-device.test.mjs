// SPDX-License-Identifier: GPL-3.0-or-later
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import { groupHomeDevices, homeRoomLabel, nextHomePollBatch, normalizeHomeRoom } from '../../frontend/src/utils/smartHomeGroups.ts';

const read = path => readFileSync(new URL(`../../${path}`, import.meta.url), 'utf8');
const page = read('frontend/src/pages/SmartHomePage.tsx');
const sensorCard = read('frontend/src/components/SmartHomeSensorCard.tsx');
const roomPicker = read('frontend/src/components/SmartHomeRoomPicker.tsx');
const api = read('frontend/src/api/jarbis.ts');
const styles = read('frontend/src/styles/app.css');
const acl = JSON.parse(read('root/usr/share/rpcd/acl.d/luci-app-smartsafehub.json'));

test('등록 기기 24대도 누락 없이 2대씩 순환 조회한다', () => {
  const ids = Array.from({ length: 24 }, (_, i) => `bulb_${i}`);
  const seen = [];
  let cursor = 0;
  for (let tick = 0; tick < 12; tick++) {
    const batch = nextHomePollBatch(ids, cursor, 2);
    assert.equal(batch.ids.length, 2);
    seen.push(...batch.ids);
    cursor = batch.nextCursor;
  }
  assert.deepEqual(seen, ids);
  assert.equal(cursor, 0);
  assert.deepEqual(nextHomePollBatch(ids, 23, 2).ids, ['bulb_23', 'bulb_0']);
  assert.deepEqual(nextHomePollBatch(['sensor'], 0, 2).ids, ['sensor']);
  assert.deepEqual(nextHomePollBatch([], 100, 2).ids, []);
  assert.deepEqual(nextHomePollBatch(ids, NaN, 0).ids, []);
});

test('기기 미지정·잘못된 공간은 안전한 기본 그룹으로 모은다', () => {
  const entries = [
    { name: '가', room: 'bedroom' },
    { name: '나', room: 'living' },
    { name: '다' },
    { name: '라', room: '../../etc/passwd' },
  ];
  assert.equal(normalizeHomeRoom(undefined), 'unassigned');
  assert.equal(normalizeHomeRoom(entries[3].room), 'unassigned');
  assert.equal(homeRoomLabel('living'), '거실');
  const groups = groupHomeDevices(entries);
  assert.deepEqual(groups.flatMap(group => group.devices.map(device => device.name)).sort(), ['가','나','다','라']);
  assert.deepEqual(groups.find(group => group.room === 'unassigned')?.devices.map(device => device.name), ['다','라']);
});

test('다중 기기 화면은 자동 간편 보기와 공간 분류를 공유기 RPC로 저장한다', () => {
  assert.match(page, /devices\.length >= 5/);
  assert.match(page, /aria-label="기기 카드 보기 방식"/);
  assert.match(page, /ariaLabel="공간별 기기 필터"/);
  assert.match(page, /groupHomeDevices\(filteredSensors\)/);
  assert.match(page, /groupHomeDevices\(filteredLights\)/);
  assert.match(page, /setJarbisDeviceRoom\(device\.id, room\)/);
  assert.match(page, /supportsRooms = status\?\.features\?\.rooms === true/);
  assert.match(page, /nextHomePollBatch\(ids, cursor, 2\)/);
  assert.match(page, /largeHome \? 30000 : 300000/);
  assert.doesNotMatch(page, /slice\(0, 6\)/);
  assert.doesNotMatch(page, /localStorage|sessionStorage/);
  assert.match(sensorCard, /data-density=\{compact \? 'compact' : 'detail'\}/);
  assert.match(api, /'device_room_set', \{ id, room \}/);
  assert.ok(acl['luci-app-smartsafehub'].write.ubus.jarbis.includes('device_room_set'));
  assert.ok(!acl['luci-app-smartsafehub'].read.ubus.jarbis.includes('device_room_set'));
});

test('간결 카드와 공간 선택은 라이트·다크 공통 의미 색상만 사용한다', () => {
  assert.match(styles, /\.ssh-smart-home \.ssh-home-light-compact/);
  assert.match(styles, /\.ssh-smart-home \.ssh-home-room-picker \.ssh-custom-select-trigger/);
  assert.match(styles, /background: var\(--home-surface\)/);
  assert.match(styles, /color: var\(--home-foreground\)/);
  assert.match(styles, /button\[aria-pressed='true'\]/);
});


test('공간 선택과 필터는 브라우저 기본 select 대신 공통 CustomSelect를 쓴다', () => {
  assert.match(page, /import \{ CustomSelect \} from '..\/components\/CustomSelect'/);
  assert.match(roomPicker, /import \{ CustomSelect \} from '.\/CustomSelect'/);
  assert.match(page, /ariaLabel="공간별 기기 필터"/);
  assert.match(roomPicker, /ariaLabel="기기 공간 변경"/);
  assert.match(page, /options=\{ROOM_FILTER_OPTIONS\}/);
  assert.match(roomPicker, /options=\{ROOM_OPTIONS\}/);
  assert.doesNotMatch(page, /<select\b|<option\b/);
  assert.doesNotMatch(roomPicker, /<select\b|<option\b/);
  assert.doesNotMatch(styles, /\.ssh-home-room-(?:filter|picker) select/);
});
