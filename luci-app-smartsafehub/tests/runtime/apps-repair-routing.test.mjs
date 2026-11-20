import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const root = new URL('../../', import.meta.url);
const source = (relative) => readFileSync(new URL(relative, root), 'utf8');

test('재설치와 설치 마무리는 복원 API로 연결하고 신규 설치와 분리한다', () => {
  const page = source('frontend/src/pages/AppsPage.tsx');
  const api = source('frontend/src/api/smartsafehub.ts');
  const shell = source('frontend/src/app/App.tsx');
  assert.match(page, /requestOperation\(app, managed \? 'repair' : 'install'\)/);
  assert.match(page, /requestOperation\(app, 'repair'\)/);
  assert.match(page, /if \(action === 'install'\) await onInstall\(app\.id\)/);
  assert.match(page, /else if \(action === 'repair'\) await onRepair\(app\.id\)/);
  assert.match(api, /'apps_repair', \{ app_id: appId \}/);
  assert.match(shell, /onRepair=\{async \(id\) => \{/);
  assert.match(shell, /await repairVerifiedApp\(id\)/);
});

test('복원 권한은 소유 기록을 요구하며 설치 검사와 관리자 인증을 우회하지 않는다', () => {
  const adapter = source('root/usr/share/rpcd/ucode/smartsafehub/apps-manager.uc');
  const router = source('root/usr/share/rpcd/ucode/smartsafehub.uc');
  const manager = source('root/usr/libexec/smartsafehub-apps-manager');
  assert.match(router, /apps_repair:\s*\{\s*args: \{ app_id: '' \},\s*call: require_root_password/);
  assert.match(adapter, /\[ MANAGER, 'start', 'install', app_id, 'restore' \]/);
  assert.match(manager, /if \[ "\$source" = restore \]; then/);
  assert.match(manager, /\[ -f "\$manifest" \] && \[ ! -L "\$manifest" \] && \[ -s "\$manifest" \] \|\| return 28/);
  assert.match(manager, /preflight_install \|\| return \$\?/);
});
