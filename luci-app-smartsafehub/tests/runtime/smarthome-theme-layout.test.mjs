// SPDX-License-Identifier: GPL-3.0-or-later
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const source = path => readFileSync(new URL(`../../${path}`, import.meta.url), 'utf8');
const page = source('frontend/src/pages/SmartHomePage.tsx');
const sensor = source('frontend/src/components/SmartHomeSensorCard.tsx');
const css = source('frontend/src/styles/app.css');

test('스마트홈은 기기 영역을 2열로 정리하고 검색/고급 설정은 전체 폭에 배치한다', () => {
  assert.match(page, /ssh-smart-home space-y-5/);
  assert.match(page, /ssh-home-device-grid grid gap-5 xl:grid-cols-2/);
  const deviceGrid = page.indexOf('ssh-home-device-grid grid gap-5');
  const gridEnd = page.indexOf('    </div>\n\n    <section ref={discoverySection}', deviceGrid);
  assert.ok(deviceGrid > 0 && gridEnd > deviceGrid);
  assert.ok(page.indexOf('aria-label="등록된 전구"', deviceGrid) < gridEnd);
  assert.ok(page.indexOf('ref={discoverySection}', deviceGrid) > gridEnd);
  assert.doesNotMatch(page, /2xl:grid-cols-\[minmax\(0,1\.55fr\)_360px\]/);
  assert.doesNotMatch(page, /0개 대기/);
});

test('센서의 세 측정값은 0폭 축소 가능한 균등 그리드와 읽기 쉬운 텍스트를 사용한다', () => {
  assert.match(sensor, /ssh-home-sensor-metrics/);
  for (const type of ['temperature', 'humidity', 'battery']) {
    assert.match(sensor, new RegExp(`data-kind="${type}"`));
  }
  assert.match(css, /grid-template-columns: repeat\(3, minmax\(0, 1fr\)\)/);
  assert.match(css, /\.ssh-home-metric-number \{[\s\S]*?white-space: nowrap;/);
  assert.match(css, /@media \(max-width: 520px\)/);
  assert.match(css, /@media \(max-width: 380px\)/);
  assert.match(css, /\.ssh-home-sensor-metric\[data-kind='battery'\] \{[\s\S]*?grid-column: 1 \/ -1;/);
  for (const bad of ['bg-sky-50/80', 'bg-teal-50/80', 'bg-slate-50/90', 'text-white']) {
    assert.ok(!sensor.includes(bad), `unsupported theme utility leaked: ${bad}`);
  }
});

test('센서 온도·습도·배터리와 서비스 요약은 라이트/다크 전용 테마 변수로 표시된다', () => {
  assert.match(css, /\.ssh-smart-home \{[\s\S]*?--home-temperature: #eff6ff;/);
  assert.match(css, /\.ssh-app\[data-theme='dark'\] \.ssh-smart-home \{[\s\S]*?--home-temperature: #112a42;/);
  for (const token of ['--home-temperature', '--home-humidity', '--home-battery', '--home-foreground', '--home-muted', '--home-hero']) {
    const declarations = css.match(new RegExp(`${token}:`, 'g')) ?? [];
    assert.ok(declarations.length >= 2, `light/dark theme mapping missing for ${token}`);
  }
  assert.match(css, /\.ssh-smart-home \.ssh-home-sensor-metric\[data-kind='humidity'\] \{/);
  assert.match(css, /\.ssh-smart-home \.ssh-home-metric-number \{[\s\S]*?color: var\(--home-foreground\);/);
  assert.match(page, /ssh-home-hero/);
  assert.match(page, /ssh-home-overview/);
});
