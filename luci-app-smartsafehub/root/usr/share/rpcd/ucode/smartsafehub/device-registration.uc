// SPDX-License-Identifier: GPL-3.0-or-later
'use strict';
import * as fs from 'fs';
import { failure, success } from './core.uc';
import { ensure_job, job_state, request_job } from './rpc-jobs.uc';
const STATE_FILE = '/tmp/smartsafehub/device.json';
const HELPER = '/usr/libexec/smartsafehub-device';
function read_state() {
 const raw = fs.readfile(STATE_FILE);
 if (raw == null || length(raw) == 0) return { schema:1, component:'device', phase:'pending', lastResult:'never', lastErrorCode:null, accountRegistered:null, plan:null, pairingCode:null, pairingExpiresAt:null, protectionRefreshPending:false, nextSyncAt:0, lastSuccessAt:0 };
 try { return json(raw); } catch (e) { return null; }
}
// Local state only: the hub owns the list of recommended rules, while
// the router exposes the domains actually owned by the reconciler.
const RECOMMENDED_FILE = '/etc/smartsafehub/recommended-rules.state';
const RECOMMENDED_RECEIPT = '/tmp/smartsafehub/recommended-rules.receipt.json';
const RECOMMENDED_CATALOG = '/tmp/smartsafehub/recommended-rules.catalog.json';
const RECOMMENDED_SYNC_STATUS = '/tmp/smartsafehub/recommended-rules.sync.json';
function read_json_file(path) {
 const raw = fs.readfile(path);
 if (raw == null || length(raw) == 0) return null;
 try { return json(raw); } catch (e) { return null; }
}
export function read_recommended_rules_status(request) {
 const raw = fs.readfile(RECOMMENDED_FILE);
 let revision = null;
 let domains = [];
 if (raw != null && length(raw) > 0) {
  const lines = split(raw, '\n');
  const saved = lines[0];
  if (saved != '-' && match(saved, /^[0-9a-f]{64}$/) == null) return failure('RECOMMENDED_STATE_INVALID', '추천 규칙 상태가 올바르지 않습니다.');
  revision = saved == '-' ? null : saved;
  for (let i = 1; i < length(lines); i++) {
   let domain = lines[i];
   if (domain == '') continue;
   if (match(domain, /^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$/) == null) return failure('RECOMMENDED_STATE_INVALID', '추천 규칙 상태가 올바르지 않습니다.');
   push(domains, domain);
  }
 }
 const receipt = read_json_file(RECOMMENDED_RECEIPT);
 const sync = read_json_file(RECOMMENDED_SYNC_STATUS);
 const catalog = read_json_file(RECOMMENDED_CATALOG);
 const rules = catalog?.revision == revision && type(catalog?.rules) == 'array' ? catalog.rules : [];
 const device = read_state();
 const confirmed = revision != null && receipt?.status == 'confirmed' && receipt?.revision == revision;
 // The receipt records SafeShield's verified allow list. A transient Hub poll
 // failure does not undo that local confirmation, nor does an unrelated 5-minute
 // device/account sync failure. Failed reconciliation removes the receipt.
 // A busy SafeShield refresh is pending work, not an application failure.
 // Keep an older verified receipt for its revision without treating a newer
 // in-progress operation as already complete.
 const syncOperation = job_state('recommended-sync');
 const revokeOperation = job_state('recommended-revoke');
 const operationRunning = syncOperation.phase == 'starting' || syncOperation.phase == 'running' ||
  revokeOperation.phase == 'starting' || revokeOperation.phase == 'running';
 const syncStatus = operationRunning || sync?.status == 'pending' ? 'pending' :
  confirmed ? 'confirmed' : sync?.status == 'delayed' ? 'delayed' :
  sync?.status == 'failed' ? 'failed' : 'pending';
 const syncWarning = confirmed && (sync?.status == 'failed' || sync?.status == 'delayed');
 const confirmedDomains = confirmed && type(receipt?.domains) == 'array' ? receipt.domains : [];
 return success({
  revision: revision,
  domains: domains,
  rules: rules,
  confirmedDomains: confirmedDomains,
  syncStatus: syncStatus,
  syncWarning: syncWarning,
  syncStage: operationRunning ? 'server_sync' : (sync?.stage ?? null),
  syncReason: sync?.reason ?? null,
  lastCheckedAt: sync?.checkedAt ?? 0,
  lastDeviceSyncAt: device?.lastSuccessAt ?? 0,
  nextDeviceSyncAt: device?.nextSyncAt ?? 0,
  accountRegistered: device?.accountRegistered ?? false,
  operation: syncOperation,
  revokeOperation: revokeOperation
 });
};
// A request means "accepted", never "the remote rule has been applied".
// The local receipt and operation phase remain separate authoritative fields.
export function refresh_recommended_rules_status(request) {
 if (!request_job('recommended-sync'))
  return failure('RECOMMENDED_SYNC_BUSY', '이미 다른 추천 규칙 동기화 작업이 진행 중입니다.');
 return read_recommended_rules_status(request);
};
export function revoke_recommended_rule(request) {
 const rule_id = request?.args?.rule_id;
 if (rule_id == null || match(sprintf('%s', rule_id), /^[1-9][0-9]{0,9}$/) == null)
  return failure('INVALID_RULE_ID', '적용 해제할 추천 규칙을 선택해 주세요.');
 if (!request_job('recommended-revoke', rule_id))
  return failure('RECOMMENDED_REVOKE_BUSY', '이미 추천 규칙 해제 작업이 진행 중입니다.');
 return read_recommended_rules_status(request);
};
export function read_device_registration_status(request) {
 const state = read_state();
 if (state == null) return failure('DEVICE_STATE_INVALID', '기기 등록 상태를 읽지 못했습니다.');
 state.operation = job_state('device-sync');
 state.pairingOperation = job_state('pairing');
 return success(state);
};
export function refresh_device_registration_status(request) {
 if (!ensure_job('device-sync'))
  return failure('DEVICE_SYNC_LAUNCH_FAILED', '서버 상태 확인을 시작하지 못했습니다.');
 return read_device_registration_status(request);
};
export function refresh_device_pairing(request) {
 if (!request_job('pairing'))
  return failure('DEVICE_PAIRING_BUSY', '연결 코드 발급을 시작하지 못했습니다. 잠시 후 다시 시도해 주세요.');
 return read_device_registration_status(request);
};
