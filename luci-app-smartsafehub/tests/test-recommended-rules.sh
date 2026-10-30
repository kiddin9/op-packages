#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
set -eu
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
HELPER="$ROOT/root/usr/libexec/smartsafehub-recommended-rules"
DEVICE="$ROOT/root/usr/libexec/smartsafehub-device"
PAGE="$ROOT/frontend/src/pages/SafeShieldRulesPage.tsx"
RPC="$ROOT/root/usr/share/rpcd/ucode/smartsafehub.uc"
TMP="$(mktemp -d)"
# Print the current scenario on assertion failure. ShellSpec otherwise receives
# only an empty stdout/stderr when `set -e` stops on an unlabelled assertion.
TEST_STAGE='초기화'
cleanup() {
  rc=$?
  if [ "$rc" -ne 0 ]; then
    printf 'FAIL: 추천 규칙 테스트 단계: %s (exit=%s)\n' "$TEST_STAGE" "$rc" >&2
    if [ -f "$TMP/run/recommended-rules.sync.json" ]; then
      printf '  last sync status: ' >&2
      cat "$TMP/run/recommended-rules.sync.json" >&2
    fi
  fi
  rm -rf "$TMP"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
mkdir -p "$TMP/bin" "$TMP/run" "$TMP/etc"
cat > "$TMP/bin/jsonfilter" <<'JS'
#!/usr/bin/env node
const fs=require('fs'), args=process.argv.slice(2);
let obj=JSON.parse(fs.readFileSync(args[args.indexOf('-i')+1]));
const typeMode=args.includes('-t');
const expression=args[args.indexOf(typeMode ? '-t' : '-e')+1];
const expr=expression.replace(/^@\./,'').replace(/\[\*\]$/,'');
for (const key of expr.split('.')) obj=obj && !Array.isArray(obj) ? obj[key] : undefined;
if (obj === undefined || obj === null) process.exit(1);
if (typeMode) {
  console.log(Array.isArray(obj) ? 'array' : typeof obj);
} else if (Array.isArray(obj)) {
  if (!obj.length) process.exit(1); // OpenWrt jsonfilter: [*] has no match
  for (const item of obj) console.log(item);
} else {
  console.log(typeof obj === 'object' ? JSON.stringify(obj) : obj);
}
JS
cat > "$TMP/bin/ubus" <<'JS'
#!/usr/bin/env node
const fs=require('fs'),path=require('path');
const dir=process.env.MOCK_RECOMMENDED_DIR, method=process.argv[4], file=path.join(dir,'rules.json');
let rules=JSON.parse(fs.readFileSync(file,'utf8'));
if (method==='status') {
  console.log(JSON.stringify({status:process.env.MOCK_SAFE_REFRESHING === '1' ? 'running' : 'ready'}));
  process.exit(0);
}
if (method==='rules_list') {
  fs.appendFileSync(path.join(dir,'lists.log'),'rules_list\n');
  console.log(process.env.BROKEN_LIST==='1' ? '{"ok":true}' : JSON.stringify({ok:true,allow:rules,block:[]}));
  process.exit(0);
}
if (process.env.FAIL_METHOD === method) { console.log('{"ok":false}'); process.exit(1); }
let domain='';
if (method==='rule_add'||method==='rule_delete') {
  const data=JSON.parse(process.argv[5]);
  if (data.action!=='allow'||data.refresh!==false) process.exit(1);
  domain=data.domain;
  if (method==='rule_add' && !rules.includes(domain)) rules.push(domain);
  if (method==='rule_delete') rules=rules.filter(v=>v!==domain);
  fs.writeFileSync(file,JSON.stringify(rules));
}
fs.appendFileSync(path.join(dir,'calls.log'),method+' '+domain+'\n');
console.log('{"ok":true}');
JS
chmod +x "$TMP/bin/ubus" "$TMP/bin/jsonfilter"
printf '[]' > "$TMP/rules.json"
export MOCK_RECOMMENDED_DIR="$TMP"
export SMARTSAFEHUB_RECOMMENDED_STATE_FILE="$TMP/etc/state"
export SMARTSAFEHUB_RECOMMENDED_RECEIPT_FILE="$TMP/etc/receipt.json"
export SMARTSAFEHUB_DEVICE_JSONFILTER_BIN="$TMP/bin/jsonfilter"
export SMARTSAFEHUB_DEVICE_UBUS_BIN="$TMP/bin/ubus"
export SMARTSAFEHUB_DEVICE_RUNTIME_DIR="$TMP/run"
export SMARTSAFEHUB_RECOMMENDED_SYNC_STATUS_FILE="$TMP/run/recommended-rules.sync.json"
response() {
  python3 - "$TMP/response.json" "$1" <<'PY'
import sys,json,hashlib
items=json.loads(sys.argv[2]); h=hashlib.sha256('\n'.join(sorted(set(items))).encode()).hexdigest()
json.dump({'recommended_rules':{'revision':h,'domains':items}},open(sys.argv[1],'w'))
PY
}
assert_rules() {
  python3 - "$TMP/rules.json" "$1" <<'PY'
import json,sys
assert sorted(json.load(open(sys.argv[1])))==sorted(json.loads(sys.argv[2]))
PY
}
TEST_STAGE='SafeShield 갱신 중 동기화 보류'
# An empty SafeShield allow list is normal on a newly configured router.
# OpenWrt jsonfilter returns 1 for @.allow[*] when there are no entries.
response '["tv.example.org"]'
# The SafeShield blocklist refresh can take minutes. Do not report an error,
# modify rule ownership, or run rule_add while it reports status=running.
if MOCK_SAFE_REFRESHING=1 "$HELPER" "$TMP/response.json"; then
  echo 'FAIL: busy SafeShield refresh should defer work' >&2; exit 1
else
  [ "$?" -eq 75 ] || { echo 'FAIL: busy refresh should use deferred exit 75' >&2; exit 1; }
fi
assert_rules '[]'
[ ! -f "$TMP/etc/state" ]
python3 - "$TMP/run/recommended-rules.sync.json" <<'PY_STAGE'
import json,sys
s=json.load(open(sys.argv[1]))
assert s['status']=='pending' and s['stage']=='safeshield_refreshing',s
PY_STAGE
"$HELPER" "$TMP/response.json"
assert_rules '["tv.example.org"]'
[ -f "$TMP/etc/state" ]
TEST_STAGE='추천 규칙 메타데이터 저장'
# Server-assigned IDs and titles are stored only after SafeShield confirms the rules.
python3 - "$TMP/response.json" <<'PY_RULES'
import hashlib,json,sys
path=sys.argv[1]
entry={'id':42,'title':'TV 테스트 규칙','domains':['tv.example.org']}
obj=json.load(open(path))
obj['recommended_rules'].update(rules=[entry],rules_revision=hashlib.sha256(b'test-rule-metadata').hexdigest())
json.dump(obj,open(path,'w'))
PY_RULES
"$HELPER" "$TMP/response.json"
python3 - "$TMP/run/recommended-rules.catalog.json" <<'PY_CATALOG'
import json,sys
obj=json.load(open(sys.argv[1]))
assert obj['rules'][0]['id'] == 42
assert obj['rules'][0]['domains'] == ['tv.example.org']
PY_CATALOG
TEST_STAGE='SafeShield refresh 실패 후 소유 정보 보존'
# 회귀: 삭제 후 SafeShield refresh가 실패하면 추천 소유 정보를 잃으면 안 됩니다.
# 그 사이 허용 목록에 도메인이 남거나 다시 나타나더라도 재할당 시 수동
# 규칙으로 잘못 분류되어서는 안 됩니다.
response '[]'
if FAIL_METHOD=refresh "$HELPER" "$TMP/response.json"; then
  echo 'FAIL: failed SafeShield refresh must fail reconciliation' >&2; exit 1
fi
[ "$(sed -n '1p' "$TMP/etc/state")" = '-' ]
grep -Fqx 'tv.example.org' "$TMP/etc/state"
# Simulate a still-present allow entry after the failed refresh.
printf '["tv.example.org"]' > "$TMP/rules.json"
response '["tv.example.org"]'
"$HELPER" "$TMP/response.json"
python3 - "$TMP/etc/receipt.json" <<'PY_REASSIGN'
import json,sys
receipt=json.load(open(sys.argv[1]))
assert receipt['domains'] == [{'domain':'tv.example.org','source':'managed'}], receipt
PY_REASSIGN
# A valid empty recommended_rules.domains array must also be accepted.
response '[]'
"$HELPER" "$TMP/response.json"
assert_rules '[]'
[ "$(wc -l < "$TMP/etc/state")" -eq 1 ]
# An empty allow list on both the initial read and verification is valid.
"$HELPER" "$TMP/response.json"
assert_rules '[]'
TEST_STAGE='기존 수동 허용 규칙 보존'
# Continue existing scenarios with pre-existing manual rules.
rm -f "$TMP/etc/state" "$TMP/etc/receipt.json" "$TMP/calls.log"
printf '["manual.example.org"]' > "$TMP/rules.json"
# Existing manual entries are never claimed even if the cloud recommends them.
response '["tv.example.org","manual.example.org"]'
"$HELPER" "$TMP/response.json"
assert_rules '["manual.example.org","tv.example.org"]'
grep -Fqx 'tv.example.org' "$TMP/etc/state"
! grep -Fqx 'manual.example.org' "$TMP/etc/state"
# A pre-existing allow entry is confirmed but never attributed to Hub.
python3 - "$TMP/etc/receipt.json" <<'PY_CHECK'
import json,sys
receipt=json.load(open(sys.argv[1]))
assert receipt['status']=='confirmed'
assert {d['domain']:d['source'] for d in receipt['domains']} == {'manual.example.org':'manual','tv.example.org':'managed'}
PY_CHECK
# Stable revisions must not call refresh again or perform a second list read.
count="$(wc -l < "$TMP/calls.log")"
list_count="$(wc -l < "$TMP/lists.log")"
"$HELPER" "$TMP/response.json"
[ "$count" -eq "$(wc -l < "$TMP/calls.log")" ]
[ "$((list_count + 1))" -eq "$(wc -l < "$TMP/lists.log")" ] || {
  echo 'FAIL: unchanged recommendations must read SafeShield once, not twice' >&2; exit 1;
}
# Even with the same revision, defer verification when SafeShield refreshes.
# A prior successful confirmation must survive that deferral unchanged.
list_count="$(wc -l < "$TMP/lists.log")"
if MOCK_SAFE_REFRESHING=1 "$HELPER" "$TMP/response.json"; then
  echo 'FAIL: refresh must defer a matching revision too' >&2; exit 1
else
  [ "$?" -eq 75 ] || exit 1
fi
[ "$list_count" -eq "$(wc -l < "$TMP/lists.log")" ]
[ -f "$TMP/etc/receipt.json" ]
# Removing one recommendation must only remove the locally owned entry.
response '[]'; "$HELPER" "$TMP/response.json"
assert_rules '["manual.example.org"]'
TEST_STAGE='규칙 변경 없는 새 추천 리비전'
# A recommendation pointing only to a user-created allow entry changes the
# revision but needs no mutation, refresh, or second full rules_list query.
response '["manual.example.org"]'
count="$(wc -l < "$TMP/calls.log")"
list_count="$(wc -l < "$TMP/lists.log")"
"$HELPER" "$TMP/response.json"
[ "$count" -eq "$(wc -l < "$TMP/calls.log")" ]
[ "$((list_count + 1))" -eq "$(wc -l < "$TMP/lists.log")" ]
python3 - "$TMP/etc/receipt.json" <<'PY_EXISTING'
import json,sys
receipt=json.load(open(sys.argv[1]))
assert receipt['domains'] == [{'domain':'manual.example.org','source':'manual'}], receipt
PY_EXISTING
TEST_STAGE='대량 규칙 일괄 검증'
# A full 100-domain recommendation made entirely of pre-existing manual rules
# should be a single SafeShield read, with no refresh, deletion or claim.
python3 - "$TMP/rules.json" "$TMP/response.json" <<'PY_BULK'
import json,hashlib,sys
entries=['manual.example.org'] + [f'allowed{i}.example.org' for i in range(99)]
json.dump(entries,open(sys.argv[1],'w'))
revision=hashlib.sha256('\n'.join(sorted(entries)).encode()).hexdigest()
json.dump({'recommended_rules':{'revision':revision,'domains':entries}},open(sys.argv[2],'w'))
PY_BULK
count="$(wc -l < "$TMP/calls.log")"
list_count="$(wc -l < "$TMP/lists.log")"
"$HELPER" "$TMP/response.json"
[ "$count" -eq "$(wc -l < "$TMP/calls.log")" ]
[ "$((list_count + 1))" -eq "$(wc -l < "$TMP/lists.log")" ]
[ "$(wc -l < "$TMP/etc/state")" -eq 1 ] || exit 1
python3 - "$TMP/etc/receipt.json" <<'PY_BULK_RECEIPT'
import json,sys
receipt=json.load(open(sys.argv[1]))
assert len(receipt['domains']) == 100
assert all(rule['source'] == 'manual' for rule in receipt['domains'])
PY_BULK_RECEIPT
# Restore the original manual allow entry for later failure/recovery cases.
printf '["manual.example.org"]\n' > "$TMP/rules.json"
response '["manual.example.org"]'
"$HELPER" "$TMP/response.json"
TEST_STAGE='잘못된 SafeShield 응답 방어'
# Broken responses must not be interpreted as an empty rules list.
response '["tv.example.org"]'
if BROKEN_LIST=1 "$HELPER" "$TMP/response.json"; then exit 1; fi
[ ! -f "$TMP/etc/receipt.json" ]
assert_rules '["manual.example.org"]'
TEST_STAGE='규칙 변경 실패 후 재시도'
# Rule mutation failures must not acknowledge a newer revision.
if FAIL_METHOD=rule_add "$HELPER" "$TMP/response.json"; then exit 1; fi
[ ! -f "$TMP/etc/receipt.json" ]
expected="$(python3 - "$TMP/response.json" <<'PY'
import sys,json
print(json.load(open(sys.argv[1]))['recommended_rules']['revision'])
PY
)"
[ "$(sed -n '1p' "$TMP/etc/state")" != "$expected" ]
"$HELPER" "$TMP/response.json"
assert_rules '["manual.example.org","tv.example.org"]'
# Failed refresh retries without deleting or duplicating recommendations.
response '[]'
if FAIL_METHOD=refresh "$HELPER" "$TMP/response.json"; then exit 1; fi
[ ! -f "$TMP/etc/receipt.json" ]
[ "$(sed -n '1p' "$TMP/etc/state")" = '-' ]
"$HELPER" "$TMP/response.json"
assert_rules '["manual.example.org"]'
[ "$(sed -n '1p' "$TMP/etc/state")" = "$expected" ] && exit 1
TEST_STAGE='잘못된 Hub 응답 및 도메인 검증'
# A missing or incorrectly typed array is NOT the same as an empty one.
revision="$(python3 - "$TMP/response.json" <<'PYREV'
import hashlib
print(hashlib.sha256(b'').hexdigest())
PYREV
)"
printf '{"recommended_rules":{"revision":"%s","domains":null}}\n' "$revision" > "$TMP/response.json"
if "$HELPER" "$TMP/response.json"; then exit 1; fi
printf '{"recommended_rules":{"revision":"%s","domains":{}}}\n' "$revision" > "$TMP/response.json"
if "$HELPER" "$TMP/response.json"; then exit 1; fi
# Bad domain or malformed hash must never mutate SafeShield.
response '["evil.example.org;reboot"]'
if "$HELPER" "$TMP/response.json"; then exit 1; fi
! grep -Fq evil.example.org "$TMP/calls.log"
printf '{"recommended_rules":{"revision":"invalid","domains":[]}}\n' > "$TMP/response.json"
if "$HELPER" "$TMP/response.json"; then exit 1; fi
# Older Hub versions do not opt into the cloud-managed list.
printf '{}\n' > "$TMP/response.json"
"$HELPER" "$TMP/response.json"
assert_rules '["manual.example.org"]'
TEST_STAGE='동기화 상태 JSON 및 RPC 계약'
# The last reconciliation result must be written to tmpfs and distinguish a
# SafeShield rule failure from a successful device account synchronization.
RECOMMENDED_STATUS="$ROOT/root/usr/share/rpcd/ucode/smartsafehub/device-registration.uc"
ACL="$ROOT/root/usr/share/rpcd/acl.d/luci-app-smartsafehub.json"
API="$ROOT/frontend/src/api/smartsafehub.ts"
APP="$ROOT/frontend/src/app/App.tsx"
grep -Fq 'RECOMMENDED_SYNC_STATUS=' "$DEVICE"
grep -Fq 'write_recommended_sync_status failed' "$DEVICE"
grep -Fq 'write_recommended_sync_status confirmed' "$DEVICE"
grep -Fq "sync?.status == 'failed'" "$RECOMMENDED_STATUS"
grep -Fq 'refresh_recommended_rules_status' "$RECOMMENDED_STATUS"
grep -Fq 'device_recommended_rules_refresh' "$RPC"
grep -Fq '"device_recommended_rules_refresh"' "$ACL"
grep -Fq 'refreshRecommendedRulesStatus' "$API"
grep -Fq 'onSyncRecommendedRules={refreshRecommendedRulesStatus}' "$APP"
grep -Fq '지금 동기화' "$PAGE"
! grep -Fq 'recommendedStatus.confirmedDomains.map' "$PAGE" # no repeated list
# Exercise the real helper's atomic status writer with an isolated temp dir.
sed -n '/^write_recommended_sync_status() {/,/^}/p' "$DEVICE" > "$TMP/status-function.sh"
(
  . "$TMP/status-function.sh"
  RUNTIME_DIR="$TMP/status-runtime"
  RECOMMENDED_SYNC_STATUS="$RUNTIME_DIR/recommended-rules.sync.json"
  now_epoch() { printf '12345'; }
  write_recommended_sync_status failed
  grep -Fq '"status":"failed","stage":"failed","reason":"","checkedAt":12345' "$RECOMMENDED_SYNC_STATUS"
  write_recommended_sync_status confirmed
  grep -Fq '"status":"confirmed","stage":"confirmed","reason":"","checkedAt":12345' "$RECOMMENDED_SYNC_STATUS"
  [ ! -e "$RECOMMENDED_SYNC_STATUS.tmp.$$" ]
)
# The UI must not allow manual deletion of entries owned by the cloud.
grep -Fq 'device_recommended_rules_status' "$RPC"
# A missing semicolon after an exported ucode function prevents the whole
# smartsafehub rpcd object from loading, including the security status RPC.
# Check this even on hosts without the ucode compiler (real compilation is
# separately mandatory in CI via tests/test-ucode-syntax.sh).
DEVICE_RPC="$ROOT/root/usr/share/rpcd/ucode/smartsafehub/device-registration.uc"
awk '
  /^export function read_device_registration_status\(/ {
    found = 1
    if (previous !~ /^[[:space:]]*};[[:space:]]*$/) exit 1
  }
  { if ($0 !~ /^[[:space:]]*$/) previous = $0 }
  END { if (!found) exit 1 }
' "$DEVICE_RPC" || {
  echo '추천 규칙 RPC 함수는 }; 로 끝나야 합니다 (ucode 모듈 로딩 실패 방지).' >&2
  exit 1
}
# Keep the shared rules page independent from executable API imports so that
# the public router demo does not inherit authenticated RPC dependencies.
grep -Fq 'onLoadRecommendedRulesStatus' "$PAGE"
# Only a confirmed change of actual recommendation content may re-read the
# full SafeShield rules list. Progress and status-only transitions are cheap.
grep -Fq 'const signature = JSON.stringify([status.revision, status.domains]);' "$PAGE"
grep -Fq "status.syncStatus === 'confirmed' && lastConfirmedSignature.current !== signature" "$PAGE"
grep -Fq "if (status.syncStatus === 'confirmed' && !reloaded) onRetry();" "$PAGE"
grep -Fq 'cmp -s "$STATE" "$temp"' "$HELPER"
! grep -Fq "data?.allow.join('\\n')" "$PAGE"
! grep -Fq "from '../api/" "$PAGE"
! grep -Fq 'from "../api/' "$PAGE"
grep -Fq 'onLoadRecommendedRulesStatus={fetchRecommendedRulesStatus}' "$ROOT/frontend/src/app/App.tsx"
grep -Fq 'disabled={busy || cloudManaged}' "$PAGE"
grep -Fq "cloudManaged ? '추천 규칙' : '직접 추가'" "$PAGE"
# Group allow entries by who controls them without repeating the domains.
grep -Fq 'aria-label="직접 추가한 허용 규칙"' "$PAGE"
grep -Fq 'aria-label="웹사이트 추천 규칙"' "$PAGE"
grep -Fq 'recommendedDomainSet.has(domain)' "$PAGE"
grep -Fq 'aria-expanded={showRecommended}' "$PAGE"
grep -Fq 'const showRecommended = searching ||' "$PAGE"
grep -Fq 'max-h-[20rem]' "$PAGE"
grep -Fq '약 30초마다 확인합니다' "$PAGE"
! grep -Fq '추천 규칙은 약 5분마다 자동 동기화됩니다' "$PAGE"
# Never invent service names that the router API does not provide.
! grep -Fq '삼성 TV Plus' "$PAGE"
grep -Fq 'aria-label="추천 사용자 규칙"' "$PAGE"
grep -Fq 'https://www.smartsafehub.com/dashboard/recommended-rules/' "$PAGE"
grep -Fq 'RECOMMENDED_HELPER' "$DEVICE"
grep -Fq 'recommended_rules_ack' "$DEVICE"
grep -Fq '/etc/smartsafehub/recommended-rules.state' "$ROOT/root/lib/upgrade/keep.d/smartsafehub-device"
TEST_STAGE='30초 경량 동기화 및 갱신 중 대기'
# The short-poll path must not use full device sync or reapply unchanged
# rules. Exercise the real function with a fake authenticated Hub response.
sed -n '/^reconcile_recommended_response() {/,/^}/p' "$DEVICE" > "$TMP/fast-function.sh"
sed -n '/^recommended_fast_sync() {/,/^}/p' "$DEVICE" >> "$TMP/fast-function.sh"
(
  . "$TMP/fast-function.sh"
  RUNTIME_DIR="$TMP/run"
  API_BASE_URL="https://example.test/api/v1"
  STATE_FILE="$TMP/device.json"
  RECOMMENDED_STATE="$TMP/etc/state"
  RECOMMENDED_HELPER="$HELPER"
  RECOMMENDED_RECEIPT="$TMP/etc/receipt.json"
  printf '{"accountRegistered":true}\n' > "$STATE_FILE"
  printf '[]\n' > "$TMP/rules.json"
  rm -f "$RECOMMENDED_STATE" "$TMP/calls.log"
  credential_token() { printf 'ssh_dev_test'; }
  json_value() { "$TMP/bin/jsonfilter" -i "$1" -e "$2" 2>/dev/null | head -n 1 || true; }
  write_recommended_sync_status() { printf '%s\n' "$1" > "$TMP/fast-status"; }
  log_message() { :; }
  post_json() {
    printf '%s\n' "$1" > "$TMP/fast-url"
    cp "$2" "$TMP/fast-request.json"
    cp "$TMP/hub-poll.json" "$3"
  }
  python3 - "$TMP/hub-poll.json" <<'PY_FAST'
import hashlib,json,sys
items=['tv.example.org']; revision=hashlib.sha256('\n'.join(items).encode()).hexdigest()
json.dump({'changed':True,'recommended_rules':{'revision':revision,'domains':items}},open(sys.argv[1],'w'))
PY_FAST
  # Hub request can succeed while SafeShield is refreshing. Keep the current
  # rules and do not report an irreversible failure; the next poll repairs it.
  # A subshell keeps the mock refresh flag isolated on macOS /bin/sh too.
  # The state and SafeShield mock results are written to files and remain visible.
  ( MOCK_SAFE_REFRESHING=1 recommended_fast_sync )
  grep -Fqx 'pending' "$TMP/fast-status"
  [ ! -f "$RECOMMENDED_STATE" ]
  recommended_fast_sync
  grep -Fqx 'confirmed' "$TMP/fast-status"
  grep -Fq '/devices/recommended-rules' "$TMP/fast-url"
  grep -Fqx 'tv.example.org' "$RECOMMENDED_STATE"
  grep -Fq 'tv.example.org' "$TMP/rules.json"
  [ -f "$RECOMMENDED_RECEIPT" ]
  old_count="$(wc -l < "$TMP/calls.log")"
  revision="$(sed -n '1p' "$RECOMMENDED_STATE")"
  printf '{"changed":false,"revision":"%s"}\n' "$revision" > "$TMP/hub-poll.json"
  recommended_fast_sync
  [ "$old_count" -eq "$(wc -l < "$TMP/calls.log")" ] || exit 1
  # 회귀: 이전 동기화가 수신 확인서를 잃으면 revision이 같더라도
  # 변경 없음으로 인정하지 말고 Hub에서 전체 데이터를 다시 요청합니다.
  rm -f "$RECOMMENDED_RECEIPT"
  python3 - "$TMP/hub-poll.json" <<'PY_RECOVER'
import hashlib,json,sys
items=['tv.example.org']; revision=hashlib.sha256('\n'.join(items).encode()).hexdigest()
json.dump({'changed':True,'recommended_rules':{'revision':revision,'domains':items}},open(sys.argv[1],'w'))
PY_RECOVER
  recommended_fast_sync
  python3 - "$TMP/fast-request.json" <<'PY_REQUEST'
import json,sys
assert json.load(open(sys.argv[1]))['revision'] == ''
PY_REQUEST
  [ -f "$RECOMMENDED_RECEIPT" ]
  [ "$old_count" -eq "$(wc -l < "$TMP/calls.log")" ] || exit 1
  # Removing an assigned rule must remove only the Hub-owned rule.
  python3 - "$TMP/hub-poll.json" <<'PY_EMPTY'
import hashlib,json,sys
json.dump({'changed':True,'recommended_rules':{'revision':hashlib.sha256(b'').hexdigest(),'domains':[]}},open(sys.argv[1],'w'))
PY_EMPTY
  recommended_fast_sync
  [ "$(cat "$TMP/rules.json")" = '[]' ] || exit 1
  # Never accept an invalid changed flag or an unverified no-change revision.
  printf '{"changed":false,"revision":"invalid"}\n' > "$TMP/hub-poll.json"
  if recommended_fast_sync; then exit 1; fi
  grep -Fqx 'failed' "$TMP/fast-status"
  printf '{"changed":true,"recommended_rules":{"revision":"bad","domains":[]}}\n' > "$TMP/hub-poll.json"
  if recommended_fast_sync; then exit 1; fi
  [ "$(cat "$TMP/rules.json")" = '[]' ] || exit 1
)
TEST_STAGE='추천 규칙 해제 명령행 인자 검증'
# Exercise the real CLI argument gate. Previous code treated a numeric rule ID
# as an invalid `--debug` flag, so the Hub request was never attempted.
# With an unregistered mock device, a valid ID reaches recommended_revoke()
# and fails with rc=1; an invalid ID is rejected at the CLI with rc=2.
export SMARTSAFEHUB_COMMON_LIB="$ROOT/root/usr/lib/smartsafehub/common.sh"
export SMARTSAFEHUB_RUNTIME_LIB="$ROOT/root/usr/lib/smartsafehub/runtime.sh"
export SMARTSAFEHUB_DEVICE_STATE_FILE="$TMP/nonexistent-device-state.json"
rc=0
"$DEVICE" recommended-revoke 42 > "$TMP/revoke-cli.out" 2>&1 || rc=$?
[ "$rc" -eq 1 ] || { echo 'FAIL: valid rule ID did not reach the revoke handler' >&2; cat "$TMP/revoke-cli.out" >&2; exit 1; }
rc=0
"$DEVICE" recommended-revoke invalid > "$TMP/revoke-cli.out" 2>&1 || rc=$?
[ "$rc" -eq 2 ] || { echo 'FAIL: invalid rule ID was accepted' >&2; exit 1; }
TEST_STAGE='추천 규칙 Hub 해제 및 로컬 적용'
# Revocation must call the device-authenticated Hub endpoint before touching
# SafeShield and must immediately reconcile the Hub's authoritative new list.
sed -n '/^reconcile_recommended_response() {/,/^}/p' "$DEVICE" > "$TMP/revoke-function.sh"
sed -n '/^recommended_revoke() {/,/^}/p' "$DEVICE" >> "$TMP/revoke-function.sh"
(
  . "$TMP/revoke-function.sh"
  API_BASE_URL="https://example.test/api/v1"
  RUNTIME_DIR="$TMP/run"
  STATE_FILE="$TMP/device.json"
  RECOMMENDED_HELPER="$HELPER"
  printf '{"accountRegistered":true}\n' > "$STATE_FILE"
  printf '[]\n' > "$TMP/rules.json"
  rm -f "$SMARTSAFEHUB_RECOMMENDED_STATE_FILE"
  response '["tv.example.org"]'
  "$HELPER" "$TMP/response.json"
  python3 - "$TMP/revoke-hub.json" <<'PY_REVOKE'
import json,hashlib,sys
json.dump({'changed':True,'recommended_rules':{
 'revision':hashlib.sha256(b'').hexdigest(),'domains':[],
 'rules':[], 'rules_revision':hashlib.sha256(b'[]').hexdigest()
}},open(sys.argv[1],'w'))
PY_REVOKE
  credential_token() { printf 'ssh_dev_test'; }
  json_value() { "$TMP/bin/jsonfilter" -i "$1" -e "$2" 2>/dev/null | head -n 1 || true; }
  write_recommended_sync_status() { printf '%s\n' "$1" > "$TMP/revoke-status"; }
  post_json() { printf '%s\n' "$1" > "$TMP/revoke-url"; cp "$TMP/revoke-hub.json" "$3"; }
  if recommended_revoke invalid; then exit 1; fi
  recommended_revoke 42
  grep -Fq '/devices/recommended-rules/42/revoke' "$TMP/revoke-url"
  grep -Fxq confirmed "$TMP/revoke-status"
  [ "$(cat "$TMP/rules.json")" = '[]' ] || exit 1
  python3 - "$TMP/run/recommended-rules.catalog.json" <<'PY_EMPTY_RULES'
import json,sys
assert json.load(open(sys.argv[1]))['rules'] == []
PY_EMPTY_RULES
)
TEST_STAGE='추천 규칙 UI 및 API 계약'
grep -Fq 'RECOMMENDED_POLL_INTERVAL_S=30' "$DEVICE"
grep -Fq 'next_fast=' "$DEVICE"
grep -Fq 'next_full=' "$DEVICE"
grep -Fq "recommended-sync) recommended_fast_sync" "$DEVICE"
# r39 queues the Hub sync in a separate worker; the RPC must only accept
# a request, not block rpcd while it runs the helper in the foreground.
RECOMMENDED_RPC="$ROOT/root/usr/share/rpcd/ucode/smartsafehub/device-registration.uc"
grep -Fq "request_job('recommended-sync')" "$RECOMMENDED_RPC" || {
  echo 'FAIL: recommended sync must enqueue the background worker' >&2
  exit 1
}
grep -Fq "return read_recommended_rules_status(request);" "$RECOMMENDED_RPC" || {
  echo 'FAIL: recommended sync must report the local status after enqueue' >&2
  exit 1
}
if grep -Fq "[ HELPER, 'recommended-sync' ]" "$RECOMMENDED_RPC"; then
  echo 'FAIL: recommended sync must not run the slow device helper in rpcd' >&2
  exit 1
fi
# With exactOptionalPropertyTypes, omit an optional callback rather than pass undefined.
# The block card does not need a revoke callback; only recommended allow rules do.
if grep -Fq 'onRequestRevoke={onRevokeRecommendedRule ? setRevokeTarget : undefined}' "$PAGE"; then
  echo 'FAIL: optional revoke callbacks must be omitted when unavailable' >&2
  exit 1
fi
grep -Fq '{...(onRevokeRecommendedRule ? { onRequestRevoke: setRevokeTarget } : {})}' "$PAGE" || {
  echo 'FAIL: the allow card must conditionally pass the revoke callback' >&2
  exit 1
}
[ "$(grep -Fc 'onRequestRevoke: setRevokeTarget' "$PAGE")" -eq 1 ] || {
  echo 'FAIL: only the allow card may request recommended rule revocation' >&2
  exit 1
}
echo '추천 사용자 규칙 동기화 및 UI 계약: PASS'
