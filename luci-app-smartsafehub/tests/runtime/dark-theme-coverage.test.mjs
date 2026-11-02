import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import { dirname, join, relative, resolve } from 'node:path';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';
import { auditDarkTheme, collectColorUtilities } from '../support/dark-theme-audit.mjs';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const styles = readFileSync(resolve(root, 'frontend/src/styles/app.css'), 'utf8');
const exceptions = JSON.parse(readFileSync(resolve(root, 'tests/support/dark-theme-exceptions.json'), 'utf8'));

function readTsx(path, found = {}) {
  for (const item of readdirSync(path, { withFileTypes: true })) {
    const full = join(path, item.name);
    if (item.isDirectory()) readTsx(full, found);
    else if (item.name.endsWith('.tsx')) found[relative(root, full)] = readFileSync(full, 'utf8');
  }
  return found;
}

const sources = readTsx(resolve(root, 'frontend/src'));

test('모든 TSX의 밝은 Tailwind 유틸리티는 다크 모드 대응 또는 명시적 예외가 있다', () => {
  const report = auditDarkTheme({ sources, css: styles, exceptions });
  assert.ok(Object.keys(sources).length > 20, 'TSX search accidentally disabled');
  assert.ok(report.checked > 50, 'class scanner unexpectedly skipped most colors');
  assert.deepEqual(report.problems, [], report.problems.join('\n'));
});

test('템플릿/조건부 클래스와 새 구분선·배경·테두리·hover 누락을 감지한다', () => {
  const fixture = { 'NewPage.tsx': `
    const badge = ok ? 'bg-violet-50 border-violet-200' : 'bg-violet-100';
    return <ul class={\`divide-y divide-violet-300 hover:bg-violet-100 \${badge}\`}/>;
  ` };
  const names = [...collectColorUtilities(fixture).keys()];
  for (const expected of ['bg-violet-50', 'bg-violet-100', 'border-violet-200', 'divide-violet-300', 'hover:bg-violet-100']) {
    assert.ok(names.includes(expected), `failed to scan ${expected}`);
  }
  const report = auditDarkTheme({ sources: fixture, css: styles });
  for (const expected of names) assert.ok(report.problems.some(p => p.includes(expected)), `missed ${expected}`);
});

test('부모만 지정한 divide 규칙·속성 누락·밝은 선언도 실패한다', () => {
  const sources = { 'NewPage.tsx': '<ul class="divide-y divide-slate-100 bg-rose-100" />' };
  const good = auditDarkTheme({ sources, css: styles });
  assert.deepEqual(good.problems, [], good.problems.join('\n'));
  const wrongParent = styles.replace(/\[class~='divide-slate-100'\] > :not\(:last-child\)/g, "[class~='divide-slate-100']");
  assert.ok(auditDarkTheme({ sources, css: wrongParent }).problems.some(p => p.includes('divide-slate-100')));
  const missingValue = styles.replace("[class~='bg-rose-100'],", '');
  assert.ok(auditDarkTheme({ sources, css: missingValue }).problems.some(p => p.includes('bg-rose-100')));
  const paleValue = styles.replace('background-color: rgb(244 63 94 / 0.12);', 'background-color: #ffffff;');
  assert.ok(auditDarkTheme({ sources, css: paleValue }).problems.some(p => p.includes('bg-rose-100')));
  const darkText = styles.replace(/(\[class~='text-teal-950'\] \{\s*color: )#5eead4;/, '$1#000000;');
  assert.ok(auditDarkTheme({ sources: { 'NewPage.tsx': '<span class="text-teal-800" />' }, css: darkText }).problems.some(p => p.includes('text-teal-800')));
});

test('예외는 특정 클래스를 지정하고 사유가 충분해야 하며 미사용·중복 예외는 거부한다', () => {
  const fixture = { 'NewPage.tsx': '<div class="bg-violet-50" />' };
  const valid = [{ file: 'NewPage.tsx', utility: 'bg-violet-50', reason: '이 색상은 테마와 독립된 브랜드 미리보기 요소로 사용합니다.' }];
  assert.deepEqual(auditDarkTheme({ sources: fixture, css: styles, exceptions: valid }).problems, []);
  const anotherFile = { ...fixture, 'AnotherPage.tsx': '<div class="bg-violet-50" />' };
  assert.ok(auditDarkTheme({ sources: anotherFile, css: styles, exceptions: valid }).problems.some(p => p.includes('AnotherPage.tsx')));
  for (const bad of [
    [{ ...valid[0], reason: '의도적' }],
    [{ ...valid[0], glob: '*' }],
    [{ ...valid[0], utility: 'bg-violet-100' }],
    [valid[0], valid[0]],
    [{ ...valid[0], file: '*.tsx' }],
  ]) {
    assert.ok(auditDarkTheme({ sources: fixture, css: styles, exceptions: bad }).problems.length > 0);
  }
});

test('hover/focus 선택자·다크 테마 범위를 실제 스타일과 정확히 대조한다', () => {
  const sources = { 'NewPage.tsx': '<div class="hover:bg-rose-100 focus-visible:ring-teal-100" />' };
  assert.deepEqual(auditDarkTheme({ sources, css: styles }).problems, []);
  const onlyLight = styles.replace('.ssh-app[data-theme=\'dark\'] .hover\\:bg-rose-100:hover', '.ssh-app[data-theme=\'light\'] .hover\\:bg-rose-100:hover');
  assert.ok(auditDarkTheme({ sources, css: onlyLight }).problems.some(p => p.includes('hover:bg-rose-100')));
  const noFocus = styles.replace('.focus-visible\\:ring-teal-100:focus-visible', '.focus-visible\\:ring-teal-100:hover');
  assert.ok(auditDarkTheme({ sources, css: noFocus }).problems.some(p => p.includes('focus-visible:ring-teal-100')));
});
