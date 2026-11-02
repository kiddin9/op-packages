import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const css = readFileSync(resolve(root, 'frontend/src/styles/app.css'), 'utf8');
const networkWatch = readFileSync(resolve(root, 'frontend/src/pages/NetworkWatchPage.tsx'), 'utf8');
const rulesPage = readFileSync(resolve(root, 'frontend/src/pages/SafeShieldRulesPage.tsx'), 'utf8');
const homePage = readFileSync(resolve(root, 'frontend/src/pages/HomePage.tsx'), 'utf8');
const settingsPage = readFileSync(resolve(root, 'frontend/src/pages/SettingsPage.tsx'), 'utf8');
const firmwareCard = readFileSync(resolve(root, 'frontend/src/components/FirmwareUpdatesCard.tsx'), 'utf8');

// Read the actual declarations, not just a string anywhere in the stylesheet.
// A rule on the parent does not override Tailwind v4's child border-color.
const rules = [...css.matchAll(/([^{}]+)\{([^{}]*)\}/g)].map(([, selector, body]) => ({
  selector: selector.trim(),
  body: body.trim(),
}));

function darkRule(selector, declaration) {
  const found = rules.find((rule) => rule.selector.includes(selector) && rule.body.includes(declaration));
  assert.ok(found, `missing dark rule for ${selector}: ${declaration}`);
  assert.ok(found.selector.includes(".ssh-app[data-theme='dark']"), 'dark override must never affect the light theme');
  return found;
}

test('Network Watch와 사용자 규칙의 구분선은 Tailwind v4의 자식 요소를 직접 지정한다', () => {
  assert.match(networkWatch, /divide-y divide-slate-100/);
  assert.match(rulesPage, /divide-y divide-slate-200/);
  for (const shade of ['100', '200']) {
    const selector = `[class~='divide-slate-${shade}'] > :not(:last-child)`;
    const rule = darkRule(selector, 'border-color: #1e293b;');
    assert.ok(rule.selector.includes(selector), 'do not regress to parent-only border-color');
  }
});

test('심각 상태 배지의 밝은 rose 배경을 다크 모드에서 변환한다', () => {
  assert.match(homePage, /bg-rose-100 text-rose-800/);
  assert.match(settingsPage, /bg-rose-100 text-rose-800/);
  darkRule("[class~='bg-rose-100']", 'background-color: rgb(244 63 94 / 0.12);');
  darkRule("[class~='text-rose-800']", 'color: #fda4af;');
});

test('펌웨어 관리 소프트웨어 카드의 연한 sky 테두리도 다크 색으로 변환한다', () => {
  assert.match(firmwareCard, /border-sky-100/);
  darkRule("[class~='border-sky-100']", 'border-color: #075985;');
});

test('연한 hover 배경만 다크 팔레트로 전환하고 강한 색 버튼은 유지한다', () => {
  const expected = new Map([
    ['slate-100', '#334155'],
    ['teal-50', 'rgb(13 148 136 / 0.24)'],
    ['teal-100', 'rgb(13 148 136 / 0.24)'],
    ['amber-50', 'rgb(245 158 11 / 0.22)'],
    ['amber-100', 'rgb(245 158 11 / 0.22)'],
    ['rose-100', 'rgb(244 63 94 / 0.22)'],
  ]);
  for (const [shade, color] of expected) {
    darkRule(`.hover\\:bg-${shade}:hover`, `background-color: ${color};`);
  }
  // Full-color action buttons are already legible in the dark theme.
  // Their hover utility should not be replaced by a pale-surface override.
  for (const shade of ['teal-800', 'amber-800', 'red-800', 'sky-800']) {
    assert.ok(!rules.some((rule) => rule.selector.includes(`.hover\\:bg-${shade}:hover`)
      && rule.selector.includes(".ssh-app[data-theme='dark']")), `strong action hover must remain untouched: ${shade}`);
  }
});
