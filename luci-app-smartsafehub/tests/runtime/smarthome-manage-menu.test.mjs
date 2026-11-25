// SPDX-License-Identifier: GPL-3.0-or-later
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const read = path => readFileSync(new URL(`../../${path}`, import.meta.url), 'utf8');
const page = read('frontend/src/pages/SmartHomePage.tsx');
const sensor = read('frontend/src/components/SmartHomeSensorCard.tsx');

test('온습도 센서 관리 메뉴도 전구와 동일한 메뉴 등록 목록을 사용한다', () => {
  assert.match(sensor, /onManageMenuRef: \(element: HTMLDetailsElement \| null\) => void/);
  assert.match(sensor, /<details ref=\{onManageMenuRef\}/);
  assert.match(page, /<SmartHomeSensorCard[\s\S]*?onManageMenuRef=\{element => \{ manageMenus\.current\[device\.id\] = element; \}\}/);
  // Detailed and compact bulb controls must both use the same menu registry.
  assert.equal((page.match(/<details ref=\{element => \{ manageMenus\.current\[device\.id\] = element; \}\}/g) ?? []).length, 2);
});

test('메뉴 바깥 클릭과 Esc 키는 센서와 전구에 모두 적용된다', () => {
  assert.match(page, /const onOutside = \(event: PointerEvent\) => dismiss\(event\.composedPath\(\)\)/);
  assert.match(page, /if \(path\?\.includes\(menu\)\) continue/);
  assert.match(page, /if \(event\.key === 'Escape'\) dismiss\(null\)/);
  assert.match(page, /document\.addEventListener\('pointerdown', onOutside\)/);
  assert.match(page, /document\.removeEventListener\('pointerdown', onOutside\)/);
  assert.match(page, /document\.addEventListener\('keydown', onEscape\)/);
  assert.match(page, /document\.removeEventListener\('keydown', onEscape\)/);
});

test('공간 선택 목록은 외부 포털로 렌더링되어도 부모 관리 메뉴가 닫히지 않는다', () => {
  assert.match(page, /target\.classList\.contains\('ssh-custom-select-menu'\)/);
  assert.match(page, /trigger\.getAttribute\('aria-controls'\) === selectMenu\.id/);
  assert.match(page, /if \(selectMenu instanceof HTMLElement/);
});

test('센서 관리 작업 시 메뉴를 닫고, 기존 권한 및 API 동작을 유지한다', () => {
  assert.match(page, /onToggle=\{\(\) => \{ closeManageMenu\(device\.id\); void run\(`/);
  assert.match(page, /onRemove=\{\(\) => \{ closeManageMenu\(device\.id\); void remove\(device\); \}\}/);
  assert.match(page, /onRoomChange=\{room => void changeRoom\(device, room\)\}/);
  assert.match(sensor, /<SmartHomeRoomPicker room=\{device\.room\}/);
  assert.match(sensor, /onClick=\{onToggle\}/);
  assert.match(sensor, /onClick=\{onRemove\}/);
});
