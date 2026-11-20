import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const read = (path) => readFileSync(resolve(root, path), 'utf8');

test('ArcDrop 실행은 Hub 승인된 로컬 경로와 패키지 이름으로만 허용한다', () => {
  const catalog = read('root/usr/share/rpcd/ucode/smartsafehub/apps.uc');
  const helper = read('frontend/src/utils/appsWebUi.ts');
  assert.match(catalog, /id == 'arcdrop'[\s\S]*?web_ui\?\.path == '\/arcdrop\/'/);
  assert.match(catalog, /web_ui\?\.package == 'smartsafehub-app-arcdrop'/);
  assert.match(helper, /\['\/retro-arcade\/', '\/arcdrop\/'\]/);
  assert.doesNotMatch(helper, /https?:\/\/evil/);
});

test('ArcDrop은 페이지와 CGI 모두 있어야 실행 준비 상태가 된다', () => {
  const manager = read('root/usr/libexec/smartsafehub-apps-manager');
  assert.match(manager, /arcdrop\/index\.html/);
  assert.match(manager, /cgi-bin\/arcdrop/);
  assert.match(manager, /\[ -x "\$\{SMARTSAFEHUB_APPS_WEB_ROOT:-\/www\}\/cgi-bin\/arcdrop" \]/);
});

test('ArcDrop 데모는 승인된 실기기 설치를 흉내 내지 않는다', () => {
  const fixtures = read('frontend/src/demo/data.ts');
  assert.match(fixtures, /id: 'arcdrop',[\s\S]*?publisherType: 'first_party'/);
  assert.match(fixtures, /id: 'arcdrop',[\s\S]*?version: '0\.1\.0-r21'/);
  assert.match(fixtures, /arcdrop: \{[\s\S]*?installedVersion: '0\.1\.0-r21'/);
  assert.doesNotMatch(fixtures, /\/cgi-bin\/arcdrop\?/);
});
