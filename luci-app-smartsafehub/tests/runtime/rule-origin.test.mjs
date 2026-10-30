import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const page = readFileSync(resolve(root, 'frontend/src/pages/SafeShieldRulesPage.tsx'), 'utf8');
const rpc = readFileSync(resolve(root, 'root/usr/share/rpcd/ucode/smartsafehub/device-registration.uc'), 'utf8');
const helper = readFileSync(resolve(root, 'root/usr/libexec/smartsafehub-recommended-rules'), 'utf8');

test('추천 규칙 영역에서 웹사이트의 추천 목록으로 이동할 수 있다', () => {
  assert.match(page, /aria-label="추천 사용자 규칙"/);
  assert.match(page, /추천 규칙 보기/);
  assert.match(page, /https:\/\/www\.smartsafehub\.com\/dashboard\/recommended-rules\//);
});

test('허용 목록의 수동 규칙과 추천 규칙을 로컬 소유 정보로 구분한다', () => {
  assert.match(rpc, /recommended-rules\.state/);
  assert.match(rpc, /domains: domains/);
  assert.match(helper, /grep -Fxq "\$domain" "\$OWNED"/);
  assert.match(page, /const cloudManaged = isAllow && recommendedKnown && recommendedDomainSet\.has\(domain\);/);
  assert.match(page, /cloudManaged \? '추천 규칙' : '직접 추가'/);
  assert.match(page, /disabled=\{busy \|\| cloudManaged\}/);
});

test('허용 규칙 출처를 조회하지 못하면 직접 추가로 단정하지 않는다', () => {
  assert.match(page, /const ruleOrigin = !isAllow \|\| recommendedKnown/);
  assert.match(page, /: null;/);
  assert.match(page, /recommendedKnown=\{recommendedKnown\}/g);
  assert.match(page, /!onLoadRecommendedRulesStatus\) return;/);
  assert.doesNotMatch(page, /from ['"]\.\.\/api\//);
});


test('추천 규칙 수동 동기화와 적용 확인 상태는 데모 API를 사용하지 않는다', () => {
  const app = readFileSync(resolve(root, 'frontend/src/app/App.tsx'), 'utf8');
  const api = readFileSync(resolve(root, 'frontend/src/api/smartsafehub.ts'), 'utf8');
  const main = readFileSync(resolve(root, 'root/usr/share/rpcd/ucode/smartsafehub.uc'), 'utf8');
  const acl = readFileSync(resolve(root, 'root/usr/share/rpcd/acl.d/luci-app-smartsafehub.json'), 'utf8');
  const device = readFileSync(resolve(root, 'root/usr/libexec/smartsafehub-device'), 'utf8');
  assert.match(page, /onSyncRecommendedRules\?: \(\) => Promise<RecommendedRulesStatus>/);
  assert.match(page, /지금 동기화/);
  assert.match(page, /SafeShield 차단 목록 갱신과 별개/);
  assert.match(page, /status\.syncStatus === 'confirmed'/);
  assert.match(page, /recommendedStatus\.confirmedDomains\.length/);
  assert.match(app, /onSyncRecommendedRules=\{refreshRecommendedRulesStatus\}/);
  assert.match(api, /callApi\(API_OBJECT, 'device_recommended_rules_refresh'/);
  assert.match(main, /device_recommended_rules_refresh/);
  assert.match(acl, /"device_recommended_rules_refresh"/);
  assert.match(device, /write_recommended_sync_status failed/);
  assert.match(device, /write_recommended_sync_status confirmed/);
  assert.match(rpc, /const syncStatus = operationRunning \|\| sync\?\.status == 'pending'/);
  assert.match(rpc, /const syncWarning = confirmed &&/);
  assert.match(rpc, /const confirmed = revision != null && receipt\?\.status == 'confirmed'/);
  assert.doesNotMatch(page, /from ['"]\.\.\/api\//);
});


test('추천 규칙의 로컬 적용 확인과 일시적 서버 동기화 실패를 구분한다', () => {
  const type = readFileSync(resolve(root, 'frontend/src/types/rules.ts'), 'utf8');
  assert.match(rpc, /confirmed \? 'confirmed' : sync\?\.status == 'delayed'/);
  assert.doesNotMatch(rpc, /device\?\.lastResult == 'failed' \|\| sync\?\.status == 'failed'/);
  assert.match(rpc, /syncWarning: syncWarning/);
  assert.match(type, /syncWarning: boolean/);
  assert.match(page, /recommendedStatus\?\.syncWarning/);
  assert.match(page, /이미 확인한 허용 규칙은 유지되며 자동으로 다시 시도합니다/);
});

test('추천 규칙 상태는 화면을 새로고침하지 않아도 주기적으로 다시 조회한다', () => {
  assert.match(page, /window\.setInterval\(updateStatus, 15_000\)/);
  assert.match(page, /window\.clearInterval\(timer\)/);
  assert.match(page, /if \(inFlight \|\| syncing \|\| revokeBusy\) return;/);
  assert.match(page, /const loadStatus = onLoadRecommendedRulesStatus;/);
  assert.doesNotMatch(page, /from ['"]\.\.\/api\//);
});


test('갱신 실패 후에도 추천 규칙의 소유권을 유지하고 확인서가 없으면 재조회한다', () => {
  const device = readFileSync(resolve(root, 'root/usr/libexec/smartsafehub-device'), 'utf8');
  assert.match(helper, /Retire ownership only after final verification/);
  assert.match(helper, /persist "\$revision"/);
  assert.match(helper, /Record intent before rule_add/);
  assert.match(device, /A state revision alone is not proof that SafeShield applied the rules/);
  assert.match(device, /json_value "\$RECOMMENDED_RECEIPT" '@\.revision'/);
});

test('추천 규칙 해제 중에는 스피너와 진행 커서를 표시한다', () => {
  assert.match(page, /aria-busy=\{revokeBusy\}/);
  assert.match(page, /class="size-4 animate-spin"/);
  assert.match(page, /disabled:cursor-progress/);
  assert.match(page, /\{revokeBusy \? '해제 중…' : '적용 해제'\}/);
});

test('해제 요청 시간 초과 후에도 로컬 적용 확인을 반복하고 오래된 오류를 지운다', () => {
  assert.match(page, /pendingRevokeId\.current = ruleId/);
  assert.match(page, /status\.syncStatus === 'confirmed'/);
  assert.match(page, /!status\.rules\.some\(\(rule\) => rule\.id === pendingRevokeId\.current\)/);
  assert.match(page, /setSyncError\(null\)/);
  assert.match(page, /적용 해제 결과를 아직 확인하지 못했습니다/);
  assert.match(page, /acceptRecommendedStatus\(status\)/);
});

test('백그라운드 규칙 변경을 감지하면 SafeShield 목록을 다시 읽는다', () => {
  assert.match(page, /previousStatusSignature\.current !== null/);
  assert.match(page, /onRetryRef\.current\(\)/);
  assert.match(page, /window\.setInterval\(updateStatus, 15_000\)/);
  assert.match(page, /window\.addEventListener\('focus', onFocus\)/);
  assert.match(page, /document\.addEventListener\('visibilitychange', onVisible\)/);
});

test('적용 해제 확인이 길어지면 안내하고 확인을 계속한다', () => {
  assert.match(page, /setRevokeConfirmationDelayed\(true\), 60_000/);
  assert.match(page, /적용 해제 확인이 지연되고 있습니다/);
  assert.match(page, /setRevokeConfirmationDelayed\(false\)/);
});
