import assert from 'node:assert/strict';
import test from 'node:test';
import {
  filterRuleGroups,
  filterRecommendedAssignments,
  sameRecommendationContent,
} from '../../frontend/src/utils/ruleLists.ts';
import {
  recordRpcTiming,
  resetRpcDiagnostics,
  snapshotRpcDiagnostics,
} from '../../frontend/src/api/rpcDiagnostics.ts';

test('규칙 검색은 한 번만 분류하고 웹사이트 관리 규칙을 직접 삭제 가능한 그룹에서 분리한다', () => {
  const rules = ['ads.example.com', 'manual.example.org', 'tv.example.net'];
  const ownership = new Set(['ads.example.com', 'tv.example.net']);
  const result = filterRuleGroups(rules, '', true, ownership);
  assert.equal(result.filteredRules, rules, 'no search preserves source array');
  assert.deepEqual(result.managedRules, ['ads.example.com', 'tv.example.net']);
  assert.deepEqual(result.manualRules, ['manual.example.org']);
  assert.deepEqual(filterRuleGroups(rules, 'example.org', true, ownership).manualRules, ['manual.example.org']);
  assert.deepEqual(filterRuleGroups(rules, 'no-match', true, ownership).managedRules, []);
  assert.equal(filterRuleGroups(rules, '', false, ownership).manualRules, rules);
});

test('추천 규칙 검색은 제목 또는 도메인과 일치하고 빈 검색어에서 원래 목록을 유지한다', () => {
  const rules = [
    { id: 1, title: 'Samsung TV', domains: ['ads.its-newid.net'] },
    { id: 2, title: 'Other', domains: ['example.org'] },
  ];
  assert.equal(filterRecommendedAssignments(rules, ''), rules);
  assert.deepEqual(filterRecommendedAssignments(rules, 'samsung'), [rules[0]]);
  assert.deepEqual(filterRecommendedAssignments(rules, 'its-newid'), [rules[0]]);
});

test('백그라운드 상태 갱신에서는 동일한 목록 참조를 재사용하되 실제 변경은 반영한다', () => {
  const previous = {
    revision: 'r1', domains: ['ads.its-newid.net'],
    rules: [{ id: 2, title: 'TV', domains: ['ads.its-newid.net'] }],
    lastCheckedAt: 1, syncStatus: 'pending',
  };
  const progress = {
    ...previous,
    domains: ['ads.its-newid.net'],
    rules: [{ id: 2, title: 'TV', domains: ['ads.its-newid.net'] }],
    lastCheckedAt: 2,
    syncStatus: 'confirmed',
  };
  const stable = sameRecommendationContent(previous, progress);
  assert.equal(stable.domains, previous.domains);
  assert.equal(stable.rules, previous.rules);
  assert.equal(progress.syncStatus, 'confirmed', 'status transitions still flow to the parent');
  const changed = sameRecommendationContent(previous, {
    ...progress, domains: ['new.example.org'],
    rules: [{ id: 2, title: 'TV updated', domains: ['new.example.org'] }],
  });
  assert.notEqual(changed.domains, previous.domains);
  assert.notEqual(changed.rules, previous.rules);
});

test('운영 환경 RPC 진단은 느린/실패 요청을 제한된 메모리에만 기록한다', () => {
  resetRpcDiagnostics();
  recordRpcTiming({ object: 'safeshield', method: 'rules_list', elapsedMs: 12, responseMs: 10, decodeMs: 2, result: 'ok' });
  assert.equal(snapshotRpcDiagnostics().recent.length, 0);
  assert.equal(recordRpcTiming({ object: 'safeshield', method: 'rules_list', elapsedMs: 1501, responseMs: 1490, decodeMs: 11, result: 'ok' }), true);
  recordRpcTiming({ object: 'smartsafehub', method: 'device_recommended_rules_status', elapsedMs: 28, responseMs: 24, decodeMs: 4, result: 'RPC_TIMEOUT' });
  const snapshot = snapshotRpcDiagnostics();
  assert.deepEqual(snapshot.summary[0], { method: 'safeshield.rules_list', calls: 2, slow: 1, errors: 0, lastMs: 1501, maxMs: 1501, averageMs: 757 });
  assert.equal(snapshot.recent.length, 2);
  assert.equal(snapshot.recent[1].result, 'RPC_TIMEOUT');
  assert.equal('params' in snapshot.recent[0], false);
  assert.equal('sessionId' in snapshot.recent[0], false);
  for (let i = 0; i < 70; i++) {
    recordRpcTiming({ object: 'safeshield', method: 'rules_list', elapsedMs: 2000, responseMs: null, decodeMs: null, result: 'RPC_TIMEOUT' });
  }
  assert.equal(snapshotRpcDiagnostics().recent.length, 60);
  resetRpcDiagnostics();
  assert.deepEqual(snapshotRpcDiagnostics().summary, []);
});
