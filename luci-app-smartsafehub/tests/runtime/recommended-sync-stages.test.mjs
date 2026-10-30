import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const source = (path) => readFileSync(resolve(root, path), 'utf8');

test('SafeShield 갱신 중에는 추천 규칙을 보류하고 자동 재시도한다', () => {
  const helper = source('root/usr/libexec/smartsafehub-recommended-rules');
  const device = source('root/usr/libexec/smartsafehub-device');
  assert.match(helper, /safeshield_refreshing\(\)/);
  assert.match(helper, /\[ "\$status_value" = running \]/);
  assert.match(helper, /phase safeshield_refreshing\s+exit 75/);
  assert.match(helper, /persist '-'/); // retain ownership across partial operations
  assert.match(device, /75\) return 0/); // deferred, not failed
  assert.match(device, /RECOMMENDED_POLL_INTERVAL_S=30/);
  assert.match(device, /write_recommended_sync_status delayed hub_unavailable/);
});

test('추천 규칙 상태를 단계별로 보여주고 UI의 오류를 중복 표시하지 않는다', () => {
  const rpc = source('root/usr/share/rpcd/ucode/smartsafehub/device-registration.uc');
  const page = source('frontend/src/pages/SafeShieldRulesPage.tsx');
  const types = source('frontend/src/types/rules.ts');
  assert.match(rpc, /syncStage: operationRunning \? 'server_sync' : \(sync\?\.stage/);
  assert.match(rpc, /syncReason: sync\?\.reason/);
  assert.match(types, /syncStage: string \| null/);
  for (const stage of ['server_sync', 'safeshield_refreshing', 'applying', 'verifying']) {
    assert.ok(page.includes(`syncStage === '${stage}'`), stage);
  }
  assert.match(page, /const currentNotice =/);
  assert.match(page, /\{currentNotice \? \(/);
  assert.match(page, /window\.setInterval\(updateStatus, 15_000\)/);
  assert.doesNotMatch(page, /\{syncError \? <p/);
});
