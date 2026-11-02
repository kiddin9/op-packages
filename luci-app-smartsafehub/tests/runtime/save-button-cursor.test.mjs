import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';

import { saveButtonCursor } from '../../frontend/src/utils/saveButtonCursor.ts';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '../..');

function source(path) {
  return readFileSync(resolve(root, path), 'utf8');
}

test('설정 변경이 없어서 저장이 비활성화된 경우 로딩 커서를 사용하지 않는다', () => {
  assert.equal(saveButtonCursor(false), 'disabled:cursor-not-allowed');
  assert.equal(saveButtonCursor(true), 'disabled:cursor-wait');
});

test('WAN, LAN, 기본 Wi-Fi, 게스트 Wi-Fi 저장 버튼은 실제 작업 중에만 로딩 커서를 사용한다', () => {
  for (const [path, dirty] of [
    ['frontend/src/pages/WanPage.tsx', 'settingsDirty'],
    ['frontend/src/pages/LanPage.tsx', 'settingsDirty'],
    ['frontend/src/pages/WifiPage.tsx', 'settingsDirty'],
    ['frontend/src/components/GuestWifiCard.tsx', 'dirty'],
  ]) {
    const page = source(path);
    // Check the actual save button, not just an unused import or a helper elsewhere.
    const save = [...page.matchAll(/<button\b[\s\S]*?<\/button>/g)]
      .map(([markup]) => markup)
      .find(markup => markup.includes(`disabled={busy || !${dirty}}`) && markup.includes('type="submit"'));
    assert.ok(save, `저장 버튼을 찾을 수 없음: ${path}`);
    assert.match(save, /\$\{saveButtonCursor\(busy\)\}/, `상태별 커서 선택이 누락됨: ${path}`);
    assert.doesNotMatch(save, /(?<!\$\{)disabled:cursor-wait/, `변경 없는 상태에도 대기 커서가 적용됨: ${path}`);
  }
});

test('조건별 커서 유틸리티는 Tailwind가 정적 추출할 수 있는 완전한 클래스명이다', () => {
  const helper = source('frontend/src/utils/saveButtonCursor.ts');
  assert.match(helper, /'disabled:cursor-wait'/);
  assert.match(helper, /'disabled:cursor-not-allowed'/);
  assert.doesNotMatch(helper, /`disabled:cursor-\$\{/);
});
