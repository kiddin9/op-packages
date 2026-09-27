#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
HELPER="$ROOT_DIR/root/usr/libexec/smartsafehub-license"
INIT_SCRIPT="$ROOT_DIR/root/etc/init.d/smartsafehub-license"
CONFIG="$ROOT_DIR/root/etc/config/smartsafehub"
LICENSE_MODULE="$ROOT_DIR/root/usr/share/rpcd/ucode/smartsafehub/license.uc"
RPC_ENTRY="$ROOT_DIR/root/usr/share/rpcd/ucode/smartsafehub.uc"
ACL="$ROOT_DIR/root/usr/share/rpcd/acl.d/luci-app-smartsafehub.json"
API="$ROOT_DIR/frontend/src/api/smartsafehub.ts"
HOOK="$ROOT_DIR/frontend/src/hooks/useSafeShieldActions.ts"
TYPES="$ROOT_DIR/frontend/src/types/license.ts"
PAGE="$ROOT_DIR/frontend/src/pages/SafeShieldPage.tsx"
APP="$ROOT_DIR/frontend/src/app/App.tsx"
REAL_SLEEP_BIN="$(command -v sleep)"

fail() {
	printf 'FAIL: %s\n' "$*" >&2
	exit 1
}

for file in "$HELPER" "$INIT_SCRIPT" "$CONFIG" "$LICENSE_MODULE" "$RPC_ENTRY" "$ACL" "$API" "$HOOK" "$TYPES" "$PAGE" "$APP"; do
	[ -f "$file" ] || fail "라이선스 소스 파일이 없습니다: ${file#$ROOT_DIR/}"
done

sh -n "$HELPER" || fail 'License helper가 POSIX shell 문법 검사를 통과해야 합니다.'
sh -n "$INIT_SCRIPT" || fail 'License init script가 POSIX shell 문법 검사를 통과해야 합니다.'

grep -Fq "config license 'license'" "$CONFIG" || fail 'smartsafehub license UCI section이 필요합니다.'
grep -Fq "option check_interval_s '300'" "$CONFIG" || fail '라이선스 상태 확인 기본 주기는 300초여야 합니다.'
grep -Fq 'procd_set_param command "$PROG" daemon' "$INIT_SCRIPT" || fail '라이선스 서비스는 독립 procd daemon으로 실행되어야 합니다.'
grep -Fq 'procd_set_param term_timeout 15' "$INIT_SCRIPT" || fail '라이선스 daemon은 Hub 요청 timeout보다 긴 정상 종료 유예 시간을 가져야 합니다.'
grep -Fq 'smartsafehub-license' "$INIT_SCRIPT" || fail '라이선스 init script가 전용 helper를 실행해야 합니다.'
grep -Fq 'umask 077' "$HELPER" || fail '라이선스 helper의 임시 request/response 파일은 root 전용 권한이어야 합니다.'
grep -Fq 'interruptible_sleep()' "$HELPER" || fail '라이선스 daemon의 장기 sleep은 SIGTERM으로 중단 가능해야 합니다.'
grep -Fq 'kill "$WAIT_PID"' "$HELPER" || fail '라이선스 daemon 종료 시 대기 중인 sleep child를 깨워야 합니다.'
grep -Fq '"lastHttpStatus"' "$HELPER" || fail '라이선스 상태 파일에 마지막 Hub HTTP 상태를 기록해야 합니다.'
grep -Fq '"lastActivationResult"' "$HELPER" || fail '라이선스 상태 파일에 마지막 activation 결과를 기록해야 합니다.'
grep -Fq '"lastActivationErrorCode"' "$HELPER" || fail '라이선스 상태 파일에 마지막 activation 오류를 기록해야 합니다.'
grep -Fq 'store_activity_credential_from_status' "$HELPER" || fail '라이선스 status-sync가 Cloud activity credential의 단일 발급/저장 경로여야 합니다.'

grep -Fq "activate --request-file" "$HELPER" || fail '향후 agent license 모듈로 옮길 수 있는 activate subcommand가 필요합니다.'
grep -Fq 'status-sync' "$HELPER" || fail '향후 agent license 모듈로 옮길 수 있는 status-sync subcommand가 필요합니다.'
grep -Fq 'status)' "$HELPER" || fail '향후 agent license 모듈로 옮길 수 있는 status subcommand가 필요합니다.'
grep -Fq "'license_status'" "$API" || fail '프런트엔드는 SmartSafeHub license_status RPC를 사용해야 합니다.'
grep -Fq "'license_activate'" "$API" || fail '프런트엔드는 SmartSafeHub license_activate RPC를 사용해야 합니다.'
grep -Fq 'requestSmartSafeHubLicenseActivation(normalizedKey)' "$HOOK" || fail '라이선스 등록은 Hub activate 경로를 사용해야 합니다.'
if grep -Fq 'updateSafeShieldLicense(normalizedKey)' "$HOOK"; then
	fail '새 라이선스 등록 시 Hub activate 전에 SafeShield에 직접 저장하면 안 됩니다.'
fi

grep -Fq 'const LICENSE_ACTIVATION_POLL_INTERVAL_MS = 1000;' "$HOOK" || fail '라이선스 activation polling은 공유기 부하를 줄이기 위해 1초 간격이어야 합니다.'
grep -Fq 'const LICENSE_ACTIVATION_MAX_TRANSIENT_ERRORS = 2;' "$HOOK" || fail '일시적인 status RPC 오류는 제한적으로 재시도해야 합니다.'
grep -Fq "feedbackTarget: 'license'" "$HOOK" || fail '라이선스 오류/성공 피드백은 license 영역으로 라우팅해야 합니다.'
grep -Fq "actionFeedbackTarget === 'license' ? actionError : null" "$PAGE" || fail '라이선스 오류는 라이선스 카드 안에 표시해야 합니다.'
grep -Fq '라이선스를 확인하고 이 기기에 적용하고 있습니다…' "$PAGE" || fail '라이선스 카드 안에서 activation 진행 상태를 안내해야 합니다.'
grep -Fq 'actionFeedbackTarget={safeshieldActions.feedbackTarget}' "$APP" || fail 'SafeShield page에 feedback target을 전달해야 합니다.'
grep -Fq "callApi(API_OBJECT, 'license_status', {}, { timeoutMs: 5000 })" "$API" || fail 'license_status polling은 짧은 RPC timeout으로 UI 지연을 제한해야 합니다.'

if grep -Fq "safe_call('safeshield', 'status'" "$LICENSE_MODULE"; then
	fail 'license_activate RPC 안에서 SafeShield status를 동기 호출하면 rpcd nested ubus 대기가 발생할 수 있습니다.'
fi
grep -Fq 'write_private_request(license_key)' "$LICENSE_MODULE" || fail 'license_activate RPC는 키만 private request에 기록하고 즉시 helper로 넘겨야 합니다.'
grep -Fq 'build_activation_body()' "$HELPER" || fail 'detached helper가 Hub activate device payload를 구성해야 합니다.'
grep -Fq '"$UBUS_BIN" call safeshield status' "$HELPER" || fail 'detached helper가 SafeShield authoritative device identity를 조회해야 합니다.'
grep -Fq "'@.device.configured.vendor'" "$HELPER" || fail 'Hub activate는 SafeShield status의 configured vendor를 재사용해야 합니다.'
grep -Fq "'@.device.configured.model'" "$HELPER" || fail 'Hub activate는 SafeShield status의 configured model을 재사용해야 합니다.'
grep -Fq "'@.version'" "$HELPER" || fail 'Hub activate payload에 현재 SafeShield 버전이 포함되어야 합니다.'
grep -Fq "run_command([ '/bin/mkdir', '-p', RUNTIME_DIR ]" "$LICENSE_MODULE" || fail '첫 부팅에도 activate 전에 runtime 디렉터리를 준비해야 합니다.'
if grep -Eq 'license_key.*LICENSE_HELPER|LICENSE_HELPER.*license_key' "$LICENSE_MODULE"; then
	fail '평문 라이선스 키를 helper command line에 노출하면 안 됩니다.'
fi

grep -Fq '"license_status"' "$ACL" || fail 'license_status RPC read ACL이 필요합니다.'
grep -Fq '"license_activate"' "$ACL" || fail 'license_activate RPC write ACL이 필요합니다.'

TMP="$(mktemp -d)"
DAEMON_PID=''

cleanup_test() {
	if [ -n "$DAEMON_PID" ] && kill -0 "$DAEMON_PID" 2>/dev/null; then
		kill -KILL "$DAEMON_PID" 2>/dev/null || true
		wait "$DAEMON_PID" 2>/dev/null || true
	fi
	rm -rf "$TMP"
}
trap cleanup_test EXIT INT TERM
mkdir -p "$TMP/bin" "$TMP/runtime"

cat > "$TMP/bin/uci" <<'EOF_UCI'
#!/bin/sh
set -eu
[ "${1:-}" = "-q" ] && shift
[ "${1:-}" = "get" ] || exit 1
case "${2:-}" in
	smartsafehub.license.check_interval_s) printf '%s\n' "${MOCK_CHECK_INTERVAL:-300}" ;;
	smartsafehub.license.startup_delay_s) printf '%s\n' "${MOCK_STARTUP_DELAY:-0}" ;;
	smartsafehub.license.api_base_url) printf '%s\n' 'https://www.smartsafehub.com/api/v1' ;;
	smartsafehub.activity.cloud_sync_enabled) printf '%s\n' "${MOCK_ACTIVITY_CLOUD_SYNC_ENABLED:-1}" ;;
	*) exit 1 ;;
esac
EOF_UCI
chmod +x "$TMP/bin/uci"

cat > "$TMP/bin/jsonfilter" <<'EOF_JSONFILTER'
#!/bin/sh
set -eu
file=''
expression=''
while [ "$#" -gt 0 ]; do
	case "$1" in
		-i) file="$2"; shift 2 ;;
		-e) expression="$2"; shift 2 ;;
		*) shift ;;
	esac
done
jq_expression="$(printf '%s' "$expression" | sed 's/^@//')"
jq -r "($jq_expression) as \$value | if \$value == null then empty else \$value end" "$file"
EOF_JSONFILTER
chmod +x "$TMP/bin/jsonfilter"

cat > "$TMP/bin/ubus" <<'EOF_UBUS'
#!/bin/sh
set -eu
[ "${1:-}" = "call" ] || exit 1
case "${2:-}:${3:-}" in
	safeshield:license_get)
		[ "${MOCK_LICENSE_GET_EXIT:-0}" -eq 0 ] || exit "${MOCK_LICENSE_GET_EXIT}"
		printf '{"license":{"configured":%s,"key":"%s"}}\n' "${MOCK_LICENSE_CONFIGURED:-true}" "${MOCK_LICENSE_KEY:-LIC-LOCAL-001}"
		;;
	safeshield:status)
		[ "${MOCK_SAFESHIELD_STATUS_EXIT:-0}" -eq 0 ] || exit "${MOCK_SAFESHIELD_STATUS_EXIT}"
		cat <<'EOF_STATUS'
{"version":"0.3.23-r1","device":{"physical_fingerprint":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","fingerprint_version":1,"identity_provider":"factory_mac","identity_source":"mtd:Factory:0x4:mac","identity_strength":"hardware_soft","identity_profile":"iptime_ax3000sm","installation_id":"11111111-1111-4111-8111-111111111111","configured":{"physical_fingerprint":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","vendor":"ipTIME","model":"ipTIME AX3000SM","arch":"aarch64_cortex-a53","memory_mb":256}}}
EOF_STATUS
		;;
	safeshield:license_update)
		printf '%s\n' "${4:-}" >> "${MOCK_LICENSE_UPDATE_LOG:?}"
		exit "${MOCK_LICENSE_UPDATE_EXIT:-0}"
		;;
	*) exit 1 ;;
esac
EOF_UBUS
chmod +x "$TMP/bin/ubus"

cat > "$TMP/bin/uclient-fetch" <<'EOF_FETCH'
#!/bin/sh
set -eu
output=''
body=''
url=''
while [ "$#" -gt 0 ]; do
	case "$1" in
		-O) output="$2"; shift 2 ;;
		--body-file=*) body="${1#*=}"; shift ;;
		--body-file) body="$2"; shift 2 ;;
		http://*|https://*) url="$1"; shift ;;
		*) shift ;;
	esac
done
[ -n "$output" ] && [ -n "$body" ] && [ -n "$url" ] || exit 2
printf '%s\n' "$url" >> "${MOCK_FETCH_URL_LOG:?}"
printf '%s\n' '---' >> "${MOCK_FETCH_BODY_LOG:?}"
cat "$body" >> "${MOCK_FETCH_BODY_LOG:?}"
printf '\n' >> "${MOCK_FETCH_BODY_LOG:?}"
case "$url" in
	*/licenses/activate)
		if [ "${MOCK_ACTIVATE_FETCH_EXIT:-0}" -ne 0 ]; then
			printf '{"code":"%s"}\n' "${MOCK_ACTIVATE_ERROR_CODE:-license_invalid}" > "$output"
			exit "${MOCK_ACTIVATE_FETCH_EXIT}"
		fi
		cat > "$output" <<EOF_ACTIVATE
{"license":{"key":"LIC-ACTIVATE-001","plan":"ultimate","status":"active","is_licensed":true},"activation":{"status":"active"},"device":{"physical_fingerprint":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}}
EOF_ACTIVATE
		;;
	*/licenses/status)
		if [ "${MOCK_STATUS_FETCH_EXIT:-0}" -ne 0 ]; then
			exit "${MOCK_STATUS_FETCH_EXIT}"
		fi
		cat > "$output" <<EOF_STATUS
{"license":{"plan":"${MOCK_STATUS_PLAN:-ultimate}","status":"${MOCK_STATUS_LICENSE_STATUS:-active}","is_licensed":${MOCK_STATUS_LICENSED:-true}},"activation":{"status":"${MOCK_STATUS_ACTIVATION:-active}"},"device":{"physical_fingerprint":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"},"device_action":"${MOCK_STATUS_ACTION:-none}","activity_history":{"upload_url":"https://www.smartsafehub.com/api/v1/activity/events","token":"activity-test-token","token_expires_in_s":172800,"retention_days":90}}
EOF_STATUS
		;;
	*) exit 3 ;;
esac
EOF_FETCH
chmod +x "$TMP/bin/uclient-fetch"

cat > "$TMP/bin/date" <<'EOF_DATE'
#!/bin/sh
[ "${1:-}" = '+%s' ] || exit 1
printf '%s\n' "${MOCK_EPOCH:-1800000000}"
EOF_DATE
chmod +x "$TMP/bin/date"

cat > "$TMP/bin/logger" <<'EOF_LOGGER'
#!/bin/sh
exit 0
EOF_LOGGER
chmod +x "$TMP/bin/logger"

cat > "$TMP/bin/sleep" <<'EOF_SLEEP'
#!/bin/sh
exit 0
EOF_SLEEP
chmod +x "$TMP/bin/sleep"

STATE_FILE="$TMP/runtime/license.json"
LOCK_DIR="$TMP/runtime/license-activate.lock"
UPDATE_LOG="$TMP/license-update.log"
FETCH_URL_LOG="$TMP/fetch-url.log"
FETCH_BODY_LOG="$TMP/fetch-body.log"
ACTIVITY_CREDENTIAL_FILE="$TMP/runtime/activity-sync-credential.json"
: > "$UPDATE_LOG"
: > "$FETCH_URL_LOG"
: > "$FETCH_BODY_LOG"

reset_mocks() {
	MOCK_LICENSE_CONFIGURED=true
	MOCK_LICENSE_KEY='LIC-LOCAL-001'
	MOCK_LICENSE_GET_EXIT=0
	MOCK_LICENSE_UPDATE_EXIT=0
	MOCK_SAFESHIELD_STATUS_EXIT=0
	MOCK_ACTIVATE_FETCH_EXIT=0
	MOCK_ACTIVATE_ERROR_CODE='license_invalid'
	MOCK_STATUS_FETCH_EXIT=0
	MOCK_STATUS_ACTION='none'
	MOCK_STATUS_LICENSED=true
	MOCK_STATUS_PLAN='ultimate'
	MOCK_STATUS_LICENSE_STATUS='active'
	MOCK_STATUS_ACTIVATION='active'
	MOCK_EPOCH=1800000000
	MOCK_ACTIVITY_CLOUD_SYNC_ENABLED=1
}

run_license() {
	MOCK_LICENSE_UPDATE_LOG="$UPDATE_LOG" \
	MOCK_FETCH_URL_LOG="$FETCH_URL_LOG" \
	MOCK_FETCH_BODY_LOG="$FETCH_BODY_LOG" \
	MOCK_LICENSE_CONFIGURED="${MOCK_LICENSE_CONFIGURED:-true}" \
	MOCK_LICENSE_KEY="${MOCK_LICENSE_KEY:-LIC-LOCAL-001}" \
	MOCK_LICENSE_GET_EXIT="${MOCK_LICENSE_GET_EXIT:-0}" \
	MOCK_LICENSE_UPDATE_EXIT="${MOCK_LICENSE_UPDATE_EXIT:-0}" \
	MOCK_SAFESHIELD_STATUS_EXIT="${MOCK_SAFESHIELD_STATUS_EXIT:-0}" \
	MOCK_ACTIVATE_FETCH_EXIT="${MOCK_ACTIVATE_FETCH_EXIT:-0}" \
	MOCK_ACTIVATE_ERROR_CODE="${MOCK_ACTIVATE_ERROR_CODE:-license_invalid}" \
	MOCK_STATUS_FETCH_EXIT="${MOCK_STATUS_FETCH_EXIT:-0}" \
	MOCK_STATUS_ACTION="${MOCK_STATUS_ACTION:-none}" \
	MOCK_STATUS_LICENSED="${MOCK_STATUS_LICENSED:-true}" \
	MOCK_STATUS_PLAN="${MOCK_STATUS_PLAN:-ultimate}" \
	MOCK_STATUS_LICENSE_STATUS="${MOCK_STATUS_LICENSE_STATUS:-active}" \
	MOCK_STATUS_ACTIVATION="${MOCK_STATUS_ACTIVATION:-active}" \
	MOCK_EPOCH="${MOCK_EPOCH:-1800000000}" \
	MOCK_ACTIVITY_CLOUD_SYNC_ENABLED="${MOCK_ACTIVITY_CLOUD_SYNC_ENABLED:-1}" \
	SMARTSAFEHUB_LICENSE_RUNTIME_DIR="$TMP/runtime" \
	SMARTSAFEHUB_LICENSE_STATE_FILE="$STATE_FILE" \
	SMARTSAFEHUB_ACTIVITY_CREDENTIAL_FILE="$ACTIVITY_CREDENTIAL_FILE" \
	SMARTSAFEHUB_LICENSE_ACTIVATION_LOCK="$LOCK_DIR" \
	SMARTSAFEHUB_LICENSE_UCI_BIN="$TMP/bin/uci" \
	SMARTSAFEHUB_LICENSE_UBUS_BIN="$TMP/bin/ubus" \
	SMARTSAFEHUB_LICENSE_JSONFILTER_BIN="$TMP/bin/jsonfilter" \
	SMARTSAFEHUB_LICENSE_UCLIENT_FETCH_BIN="$TMP/bin/uclient-fetch" \
	SMARTSAFEHUB_LICENSE_DATE_BIN="$TMP/bin/date" \
	SMARTSAFEHUB_LICENSE_LOGGER_BIN="$TMP/bin/logger" \
	SMARTSAFEHUB_LICENSE_SLEEP_BIN="$TMP/bin/sleep" \
	PATH="$TMP/bin:$PATH" \
	"$HELPER" "$@"
}

# Explicit activation posts the prepared device identity first and only then
# persists the key through SafeShield's official API.
reset_mocks
ACTIVATION_REQUEST="$TMP/runtime/license-activate.request.json"
cat > "$ACTIVATION_REQUEST" <<'EOF_REQUEST'
{"license_key":"LIC-ACTIVATE-001"}
EOF_REQUEST
printf '%s\n' '{"schema":1,"token":"stale-token"}' > "$ACTIVITY_CREDENTIAL_FILE"
mkdir "$LOCK_DIR"
run_license activate --request-file "$ACTIVATION_REQUEST" || fail '유효한 라이선스 activate 요청이 성공해야 합니다.'
grep -Fq '/api/v1/licenses/activate' "$FETCH_URL_LOG" || fail 'activate endpoint가 호출되어야 합니다.'
grep -Fq '"license_key":"LIC-ACTIVATE-001"' "$FETCH_BODY_LOG" || fail 'activate payload에 입력한 키가 포함되어야 합니다.'
grep -Fq '"physical_fingerprint":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"' "$FETCH_BODY_LOG" || fail 'activate payload에 SafeShield physical fingerprint가 포함되어야 합니다.'
grep -Fq '"vendor":"ipTIME"' "$FETCH_BODY_LOG" || fail 'activate helper가 SafeShield vendor를 Hub payload에 포함해야 합니다.'
grep -Fq '"safeshield_version":"0.3.23-r1"' "$FETCH_BODY_LOG" || fail 'activate helper가 SafeShield 버전을 Hub payload에 포함해야 합니다.'
grep -Fq 'LIC-ACTIVATE-001' "$UPDATE_LOG" || fail 'Hub activation 성공 뒤에만 SafeShield license_update가 호출되어야 합니다.'
[ ! -e "$ACTIVATION_REQUEST" ] || fail 'activate 요청 임시 파일은 완료 후 삭제되어야 합니다.'
[ ! -d "$LOCK_DIR" ] || fail 'activate single-flight lock은 완료 후 해제되어야 합니다.'
[ ! -e "$ACTIVITY_CREDENTIAL_FILE" ] || fail '새 라이선스가 적용되면 이전 entitlement의 activity credential을 폐기해야 합니다.'
[ "$(jq -r '.phase' "$STATE_FILE")" = 'active' ] || fail 'activate 성공 상태는 active여야 합니다.'
[ "$(jq -r '.lastResult' "$STATE_FILE")" = 'activated' ] || fail 'activate 성공 결과는 activated여야 합니다.'
[ "$(jq -r '.lastHttpStatus' "$STATE_FILE")" = '200' ] || fail 'activate 성공 시 마지막 Hub HTTP 상태를 200으로 기록해야 합니다.'
[ "$(jq -r '.lastActivationResult' "$STATE_FILE")" = 'active' ] || fail '마지막 activation 성공 결과를 별도로 보존해야 합니다.'
[ "$(jq -r '.lastActivationErrorCode' "$STATE_FILE")" = 'null' ] || fail 'activate 성공 후 마지막 activation 오류는 비어 있어야 합니다.'
if grep -Fq 'LIC-ACTIVATE-001' "$STATE_FILE"; then
	fail 'runtime 상태 파일에는 평문 라이선스 키를 저장하면 안 됩니다.'
fi

# A normal status sync keeps the local key and only records the remote state.
reset_mocks
: > "$UPDATE_LOG"
: > "$FETCH_URL_LOG"
: > "$FETCH_BODY_LOG"
MOCK_EPOCH=1800000300 MOCK_STATUS_ACTION=none MOCK_STATUS_LICENSED=true run_license status-sync || fail 'active status-sync가 성공해야 합니다.'
grep -Fq '/api/v1/licenses/status' "$FETCH_URL_LOG" || fail 'status endpoint가 호출되어야 합니다.'
grep -Fq '"license_key":"LIC-LOCAL-001"' "$FETCH_BODY_LOG" || fail 'status payload는 현재 SafeShield 키를 일시적으로 사용해야 합니다.'
[ ! -s "$UPDATE_LOG" ] || fail 'active status 응답은 SafeShield 라이선스를 변경하면 안 됩니다.'
[ "$(jq -r '.phase' "$STATE_FILE")" = 'active' ] || fail 'active status 응답은 active 상태로 기록해야 합니다.'
[ "$(jq -r '.lastHttpStatus' "$STATE_FILE")" = '200' ] || fail 'status 성공 시 마지막 Hub HTTP 상태를 갱신해야 합니다.'
[ "$(jq -r '.lastActivationResult' "$STATE_FILE")" = 'active' ] || fail '주기 status-sync가 마지막 activation 결과를 덮어쓰면 안 됩니다.'
[ -s "$ACTIVITY_CREDENTIAL_FILE" ] || fail 'active paid status-sync는 activity upload credential을 private runtime cache에 저장해야 합니다.'
[ "$(jq -r '.token' "$ACTIVITY_CREDENTIAL_FILE")" = 'activity-test-token' ] || fail 'activity credential cache에 Hub가 발급한 token이 저장되어야 합니다.'
[ "$(jq -r '.plan' "$ACTIVITY_CREDENTIAL_FILE")" = 'ultimate' ] || fail 'activity credential cache에 현재 plan을 저장해야 합니다.'
[ "$(jq -r '.retention_days' "$ACTIVITY_CREDENTIAL_FILE")" = '90' ] || fail 'activity credential cache에 retention 정책을 저장해야 합니다.'

# Opting out of Cloud activity history does not disable license reconciliation,
# but the optional activity upload token must not be retained locally.
reset_mocks
rm -f "$ACTIVITY_CREDENTIAL_FILE"
: > "$FETCH_URL_LOG"
MOCK_ACTIVITY_CLOUD_SYNC_ENABLED=0 MOCK_EPOCH=1800000400 run_license status-sync || fail 'Cloud 활동 OFF에서도 license status-sync 자체는 정상 동작해야 합니다.'
grep -Fq '/api/v1/licenses/status' "$FETCH_URL_LOG" || fail 'Cloud 활동 OFF에서도 라이선스 reconciliation은 유지되어야 합니다.'
[ ! -e "$ACTIVITY_CREDENTIAL_FILE" ] || fail 'Cloud 활동 OFF에서는 activity upload credential을 runtime cache에 저장하면 안 됩니다.'
[ "$(jq -r '.phase' "$STATE_FILE")" = 'active' ] || fail 'Cloud 활동 OFF가 유효한 라이선스 상태를 바꾸면 안 됩니다.'

# Explicit server revocation is authoritative and clears the local key through
# SafeShield, never by writing SafeShield UCI directly.
reset_mocks
: > "$UPDATE_LOG"
MOCK_EPOCH=1800000600 \
MOCK_STATUS_ACTION=clear_license \
MOCK_STATUS_LICENSED=false \
MOCK_STATUS_ACTIVATION=revoked \
run_license status-sync || fail 'revoked status-sync가 로컬 정리를 완료해야 합니다.'
grep -Fq '"license_key":""' "$UPDATE_LOG" || fail 'clear_license는 SafeShield license_update에 빈 키를 전달해야 합니다.'
[ "$(jq -r '.phase' "$STATE_FILE")" = 'cleared' ] || fail '해제 완료 상태는 cleared여야 합니다.'
[ "$(jq -r '.activationStatus' "$STATE_FILE")" = 'revoked' ] || fail '서버 activation 상태를 진단용 상태에 남겨야 합니다.'
[ ! -e "$ACTIVITY_CREDENTIAL_FILE" ] || fail '서버가 라이선스를 해제하면 activity credential cache도 제거해야 합니다.'

# Network/server failures are fail-open locally: never clear a key unless a
# successful response explicitly asks for clear_license.
reset_mocks
: > "$UPDATE_LOG"
if MOCK_EPOCH=1800000900 MOCK_STATUS_FETCH_EXIT=1 run_license status-sync; then
	fail 'status HTTP 실패는 실패 상태를 반환해야 합니다.'
fi
[ ! -s "$UPDATE_LOG" ] || fail 'status HTTP 실패만으로 로컬 라이선스를 제거하면 안 됩니다.'
[ "$(jq -r '.lastErrorCode' "$STATE_FILE")" = 'LICENSE_STATUS_HTTP_FAILED' ] || fail 'status HTTP 실패 코드를 기록해야 합니다.'
[ "$(jq -r '.lastHttpStatus' "$STATE_FILE")" = 'null' ] || fail 'HTTP 상태를 확인할 수 없는 fetch 실패는 null로 기록해야 합니다.'
[ "$(jq -r '.lastActivationResult' "$STATE_FILE")" = 'active' ] || fail 'status 통신 실패가 마지막 activation 결과를 지우면 안 됩니다.'

# A SafeShield API failure is not the same thing as an unconfigured license.
# Keep the local state intact and surface a diagnosable error instead.
reset_mocks
: > "$FETCH_URL_LOG"
: > "$UPDATE_LOG"
if MOCK_LICENSE_GET_EXIT=1 MOCK_EPOCH=1800001050 run_license status-sync; then
	fail 'SafeShield license_get 실패는 상태 동기화 실패여야 합니다.'
fi
[ ! -s "$FETCH_URL_LOG" ] || fail '로컬 라이선스 조회 실패 시 Hub status API를 호출하면 안 됩니다.'
[ ! -s "$UPDATE_LOG" ] || fail '로컬 라이선스 조회 실패 시 라이선스를 변경하면 안 됩니다.'
[ "$(jq -r '.lastErrorCode' "$STATE_FILE")" = 'LICENSE_LOCAL_READ_FAILED' ] || fail '로컬 라이선스 조회 실패 코드를 기록해야 합니다.'

# Periodic reconciliation must not overwrite an explicit activation that is
# still in flight. The activation lock becomes the future agent module's
# single-flight boundary as well.
reset_mocks
: > "$FETCH_URL_LOG"
jq '.phase = "activating" | .lastAttemptAt = 1800001100' "$STATE_FILE" > "$STATE_FILE.tmp"
mv "$STATE_FILE.tmp" "$STATE_FILE"
mkdir "$LOCK_DIR"
MOCK_EPOCH=1800001105 run_license status-sync || fail 'activate 진행 중 status-sync는 안전하게 skip해야 합니다.'
[ ! -s "$FETCH_URL_LOG" ] || fail 'activate 진행 중에는 Hub status API를 호출하면 안 됩니다.'
rmdir "$LOCK_DIR"

# A killed detached helper must not leave the daemon permanently blocked. An
# activation lock older than the bounded activation window is recovered.
reset_mocks
: > "$FETCH_URL_LOG"
printf '%s\n' 'stale' > "$TMP/runtime/license-activate.request.json"
jq '.phase = "activating" | .lastAttemptAt = 1800001000' "$STATE_FILE" > "$STATE_FILE.tmp"
mv "$STATE_FILE.tmp" "$STATE_FILE"
mkdir "$LOCK_DIR"
MOCK_EPOCH=1800001200 run_license status-sync || fail 'stale activate lock은 자동 복구되어야 합니다.'
[ ! -d "$LOCK_DIR" ] || fail 'stale activation lock이 제거되어야 합니다.'
[ ! -e "$TMP/runtime/license-activate.request.json" ] || fail 'stale activation request도 함께 제거되어야 합니다.'
grep -Fq '/api/v1/licenses/status' "$FETCH_URL_LOG" || fail 'stale lock 복구 후 status API를 계속 확인해야 합니다.'

# Unconfigured devices do not send periodic status requests.
reset_mocks
: > "$FETCH_URL_LOG"
: > "$UPDATE_LOG"
MOCK_LICENSE_CONFIGURED=false MOCK_LICENSE_KEY='' MOCK_EPOCH=1800001200 run_license status-sync || fail '미설정 라이선스 상태 확인은 정상 종료해야 합니다.'
[ ! -s "$FETCH_URL_LOG" ] || fail '로컬 라이선스가 없으면 Hub status API를 호출하면 안 됩니다.'
[ "$(jq -r '.phase' "$STATE_FILE")" = 'unconfigured' ] || fail '로컬 라이선스가 없으면 unconfigured 상태여야 합니다.'
[ "$(jq -r '.lastActivationResult' "$STATE_FILE")" = 'active' ] || fail '미설정 상태 전환 뒤에도 마지막 activation 결과는 진단용으로 남아야 합니다.'

# SafeShield identity lookup happens only in the detached helper. Failure must
# become an activation error without calling Hub or storing the supplied key.
reset_mocks
: > "$FETCH_URL_LOG"
: > "$UPDATE_LOG"
ACTIVATION_REQUEST="$TMP/runtime/license-activate.request.json"
printf '%s\n' '{"license_key":"LIC-IDENTITY-FAIL"}' > "$ACTIVATION_REQUEST"
mkdir "$LOCK_DIR"
if MOCK_SAFESHIELD_STATUS_EXIT=1 MOCK_EPOCH=1800001350 run_license activate --request-file "$ACTIVATION_REQUEST"; then
	fail 'SafeShield identity 조회 실패 시 activate helper가 실패해야 합니다.'
fi
[ ! -s "$FETCH_URL_LOG" ] || fail '장치 identity를 읽지 못하면 Hub activate API를 호출하면 안 됩니다.'
[ ! -s "$UPDATE_LOG" ] || fail '장치 identity를 읽지 못하면 로컬 라이선스를 저장하면 안 됩니다.'
[ "$(jq -r '.lastErrorCode' "$STATE_FILE")" = 'LICENSE_DEVICE_IDENTITY_UNAVAILABLE' ] || fail '장치 identity 조회 실패 코드를 기록해야 합니다.'
[ "$(jq -r '.lastActivationResult' "$STATE_FILE")" = 'failed' ] || fail 'identity 조회 실패를 마지막 activation 결과에 보존해야 합니다.'
[ "$(jq -r '.lastActivationErrorCode' "$STATE_FILE")" = 'LICENSE_DEVICE_IDENTITY_UNAVAILABLE' ] || fail 'identity 조회 실패 코드를 activation 진단 필드에도 보존해야 합니다.'
[ ! -d "$LOCK_DIR" ] || fail 'identity 조회 실패 뒤 activate lock을 해제해야 합니다.'

# Hub activation rejection must not persist the supplied key locally.
reset_mocks
: > "$UPDATE_LOG"
ACTIVATION_REQUEST="$TMP/runtime/license-activate.request.json"
printf '%s\n' '{"license_key":"BAD-LICENSE"}' > "$ACTIVATION_REQUEST"
mkdir "$LOCK_DIR"
if MOCK_ACTIVATE_FETCH_EXIT=1 MOCK_ACTIVATE_ERROR_CODE=license_invalid MOCK_EPOCH=1800001500 run_license activate --request-file "$ACTIVATION_REQUEST"; then
	fail 'Hub가 거부한 activate 요청은 실패해야 합니다.'
fi
[ ! -s "$UPDATE_LOG" ] || fail 'Hub activate 실패 시 SafeShield에 키를 저장하면 안 됩니다.'
[ "$(jq -r '.lastErrorCode' "$STATE_FILE")" = 'license_invalid' ] || fail 'Hub 오류 코드를 activation 상태에 보존해야 합니다.'
[ "$(jq -r '.lastHttpStatus' "$STATE_FILE")" = 'null' ] || fail 'Hub activate fetch 실패에서 알 수 없는 HTTP 상태는 null이어야 합니다.'
[ "$(jq -r '.lastActivationResult' "$STATE_FILE")" = 'failed' ] || fail 'Hub activate 거부를 마지막 activation 실패로 보존해야 합니다.'
[ "$(jq -r '.lastActivationErrorCode' "$STATE_FILE")" = 'license_invalid' ] || fail 'Hub activation 오류 코드를 별도 진단 필드에 보존해야 합니다.'

# The daemon must exit promptly while waiting for the next 5-minute sync.
# Run the real sleep command so SIGTERM exercises the parent/child wait path
# that previously left procd waiting until it sent SIGKILL.
reset_mocks
: > "$FETCH_URL_LOG"
: > "$FETCH_BODY_LOG"
: > "$UPDATE_LOG"
MOCK_LICENSE_UPDATE_LOG="$UPDATE_LOG" \
MOCK_FETCH_URL_LOG="$FETCH_URL_LOG" \
MOCK_FETCH_BODY_LOG="$FETCH_BODY_LOG" \
MOCK_LICENSE_CONFIGURED=true \
MOCK_LICENSE_KEY='LIC-LOCAL-001' \
MOCK_LICENSE_GET_EXIT=0 \
MOCK_LICENSE_UPDATE_EXIT=0 \
MOCK_SAFESHIELD_STATUS_EXIT=0 \
MOCK_STATUS_FETCH_EXIT=0 \
MOCK_STATUS_ACTION=none \
MOCK_STATUS_LICENSED=true \
MOCK_STATUS_PLAN=ultimate \
MOCK_STATUS_LICENSE_STATUS=active \
MOCK_STATUS_ACTIVATION=active \
MOCK_EPOCH=1800001800 \
MOCK_CHECK_INTERVAL=300 \
MOCK_STARTUP_DELAY=0 \
SMARTSAFEHUB_LICENSE_RUNTIME_DIR="$TMP/runtime" \
SMARTSAFEHUB_LICENSE_STATE_FILE="$STATE_FILE" \
	SMARTSAFEHUB_ACTIVITY_CREDENTIAL_FILE="$ACTIVITY_CREDENTIAL_FILE" \
SMARTSAFEHUB_LICENSE_ACTIVATION_LOCK="$LOCK_DIR" \
SMARTSAFEHUB_LICENSE_UCI_BIN="$TMP/bin/uci" \
SMARTSAFEHUB_LICENSE_UBUS_BIN="$TMP/bin/ubus" \
SMARTSAFEHUB_LICENSE_JSONFILTER_BIN="$TMP/bin/jsonfilter" \
SMARTSAFEHUB_LICENSE_UCLIENT_FETCH_BIN="$TMP/bin/uclient-fetch" \
SMARTSAFEHUB_LICENSE_DATE_BIN="$TMP/bin/date" \
SMARTSAFEHUB_LICENSE_LOGGER_BIN="$TMP/bin/logger" \
SMARTSAFEHUB_LICENSE_SLEEP_BIN="$REAL_SLEEP_BIN" \
PATH="$TMP/bin:$PATH" \
"$HELPER" daemon > "$TMP/daemon.out" 2>&1 &
DAEMON_PID=$!

"$REAL_SLEEP_BIN" 1
kill -0 "$DAEMON_PID" 2>/dev/null || fail '종료 테스트 전에 license daemon이 실행 중이어야 합니다.'
kill -TERM "$DAEMON_PID" 2>/dev/null || fail 'license daemon에 SIGTERM을 전달할 수 있어야 합니다.'

stop_wait=0
while kill -0 "$DAEMON_PID" 2>/dev/null && [ "$stop_wait" -lt 3 ]; do
	"$REAL_SLEEP_BIN" 1
	stop_wait=$((stop_wait + 1))
done
if kill -0 "$DAEMON_PID" 2>/dev/null; then
	kill -KILL "$DAEMON_PID" 2>/dev/null || true
	wait "$DAEMON_PID" 2>/dev/null || true
	fail 'license daemon이 장기 sleep 중 SIGTERM에 신속히 종료되어야 합니다.'
fi
wait "$DAEMON_PID" 2>/dev/null || true

printf 'PASS: SmartSafeHub license daemon shutdown, diagnostics, Hub activate/status sync, SafeShield reconciliation and future agent module boundaries are valid\n'
