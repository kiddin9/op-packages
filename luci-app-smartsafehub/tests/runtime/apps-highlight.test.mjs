// SPDX-License-Identifier: GPL-3.0-or-later
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import { appsHighlightFromHash } from '../../frontend/src/utils/appsHighlight.ts';

const read = (path) => readFileSync(new URL(`../../${path}`, import.meta.url), 'utf8');

test('Apps 강조 링크는 Jarbis와 레거시 링크만 유효하며 임의 앱을 활성화하지 않는다', () => {
  assert.equal(appsHighlightFromHash('#apps?highlight=jarbis'), 'jarbis');
  assert.equal(appsHighlightFromHash('#apps?foo=bar&highlight=jarbis'), 'jarbis');
  assert.equal(appsHighlightFromHash('#apps/jarbis'), 'jarbis');
  for (const hash of ['#apps', '#apps?highlight=', '#apps?highlight=retro-arcade',
    '#apps?highlight=jarbis-other', '#apps?highlight=jarbis%2Fother', '#other?highlight=jarbis',
    '#apps/jarbis/unknown', '#apps?highlight=%3Cscript%3E']) {
    assert.equal(appsHighlightFromHash(hash), null, hash);
  }
});

test('Apps 라우터는 강조 쿼리를 전체 Apps 화면으로 매핑하고 구형 주소도 유지한다', () => {
  const hook = read('frontend/src/hooks/useHashRoute.ts');
  assert.match(hook, /'#apps': 'apps'/);
  assert.match(hook, /'#apps\/jarbis': 'apps'/);
  assert.match(hook, /hash.startsWith\('#apps\?'\) \? '#apps' : hash/);
  const welcome = read('frontend/src/components/SmartHomeWelcome.tsx');
  assert.match(welcome, /href="#apps\?highlight=jarbis"/);
});

test('Apps 강조는 전체 카탈로그를 유지하며 설치 확인 로직을 변경하지 않는다', () => {
  const page = read('frontend/src/pages/AppsPage.tsx');
  assert.match(page, /const \[query, setQuery\] = useState\(''\)/);
  assert.match(page, /const \[category, setCategory\] = useState<AppsCategory>\('all'\)/);
  assert.match(page, /const filtered = useMemo\(\(\) => apps.filter\(\(app\) =>/);
  assert.doesNotMatch(page, /setQuery\(focused \? 'Jarbis' : ''\)/);
  assert.match(page, /const isHighlighted = app.id === highlightedAppId/);
  assert.match(page, /data-highlighted=\{isHighlighted \? 'true' : undefined\}/);
  // exactOptionalPropertyTypes: JSX ref must not receive undefined.
  assert.match(page, /ref=\{isHighlighted \? highlightedCardRef : null\}/);
  assert.doesNotMatch(page, /ref=\{isHighlighted \? highlightedCardRef : undefined\}/);
  assert.match(page, /scrolledHighlightRef.current === highlightedAppId/);
  assert.match(page, /card.scrollIntoView\(\{ behavior: reducedMotion \? 'auto' : 'smooth'/);
  assert.match(page, /href="#smarthome">스마트홈으로 돌아가기/);
  assert.match(page, /requestOperation\(app, managed \? 'repair' : 'install'\)/);
  assert.doesNotMatch(page, /window.location.hash === '#apps\/jarbis'/);
});

test('강조 효과는 다크모드 및 움직임 줄이기를 지원하고 자동 설치를 실행하지 않는다', () => {
  const css = read('frontend/src/styles/app.css');
  const page = read('frontend/src/pages/AppsPage.tsx');
  const welcome = read('frontend/src/components/SmartHomeWelcome.tsx');
  assert.match(css, /\.ssh-apps-highlight-card \{/);
  assert.match(css, /\.ssh-app\[data-theme='dark'\] \.ssh-apps-highlight-card/);
  assert.match(css, /@media \(prefers-reduced-motion: reduce\) \{\s*\.ssh-apps-highlight-card \{ animation: none;/);
  assert.match(page, /window.matchMedia\?\.\('\(prefers-reduced-motion: reduce\)'\)/);
  assert.doesNotMatch(welcome, /installVerifiedApp|repairVerifiedApp|callApi/);
});
