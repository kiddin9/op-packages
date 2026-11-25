// SPDX-License-Identifier: GPL-3.0-or-later
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import { safeAppIconUrl, safeDeveloperUrl } from '../../frontend/src/utils/appsDeveloper.ts';

const file = path => readFileSync(new URL(`../../${path}`, import.meta.url), 'utf8');

test('Apps 카드는 개발자 정보를 설치 버전보다 먼저 보여준다', () => {
  const card = file('frontend/src/pages/AppsPage.tsx');
  const start = card.indexOf('<AppsArtwork app={app}');
  const developer = card.indexOf('개발자 <strong', start);
  const installedVersion = card.indexOf('설치 v${installedVersion}', start);
  assert.ok(start >= 0 && developer > start && installedVersion > developer,
    '개발자 정보가 설치 버전보다 위에 있어야 합니다.');
  assert.match(card, /<AppsArtwork app=\{app\}/);
  assert.match(card, /<span class="text-xs text-slate-500" title=\{installed/);
});

test('Apps 개발자 및 이미지 URL은 HTTPS 공개 호스트만 사용한다', () => {
  assert.equal(safeDeveloperUrl('https://example.org/dev'), 'https://example.org/dev');
  assert.equal(safeAppIconUrl('https://www.smartsafehub.com/media/app-icons/' + 'a'.repeat(32) + '.png'), 'https://www.smartsafehub.com/media/app-icons/' + 'a'.repeat(32) + '.png');
  for (const unsafe of ['http://cdn.example.org/icon.png', '//cdn.example.org/icon.png',
    'https://localhost/x.png', 'https://10.0.0.1/x.png', 'https://cdn.example.org/a.svg',
    'https://user:pass@cdn.example.org/a.png', 'https://cdn.example.org:8443/a.png',
    'javascript:alert(1)', 'data:image/png;base64,AA==',
    'https://cdn.example.org/icon.png', 'https://www.smartsafehub.com/media/app-icons/icon.png',
    'https://www.smartsafehub.com/media/app-icons/' + 'a'.repeat(32) + '.png?from=other']) {
    assert.equal(safeAppIconUrl(unsafe), null, unsafe);
  }
});

test('Hub 필드는 RPC로 전달되지만 앱 설치 실행 정보와 섞이지 않는다', () => {
  const rpc = file('root/usr/share/rpcd/ucode/smartsafehub/apps.uc');
  const types = file('frontend/src/types/apps.ts');
  const card = file('frontend/src/pages/AppsPage.tsx');
  const icon = file('frontend/src/components/AppsArtwork.tsx');
  assert.match(rpc, /developerName: text\(item\?\.developer\?\.name, 200\)/);
  assert.match(rpc, /developerWebsiteUrl: public_https_url/);
  assert.match(rpc, /iconImageUrl: public_https_url/);
  assert.match(types, /developerName\?: string/);
  assert.match(card, /개발자 <strong/);
  assert.match(card, /홈페이지 ↗/);
  assert.match(icon, /referrerPolicy="no-referrer"/);
  assert.match(icon, /onError=\{\(\) => setFailed\(true\)\}/);
  assert.match(icon, /AppsCategoryIcon/);
});


test('Apps 카테고리 필터는 앱 아이콘 분리 후에도 분류 함수를 가져온다', () => {
  const page = file('frontend/src/pages/AppsPage.tsx');
  const category = file('frontend/src/components/AppsCategoryIcon.tsx');
  assert.match(page, /import\s*\{[^}]*\bappsCategoryOf\b[^}]*\}\s*from ['\"]\.\.\/components\/AppsCategoryIcon['\"]/);
  assert.match(page, /appsCategoryOf\(app\.category\) === category/);
  assert.match(category, /export function appsCategoryOf\(/);
});
