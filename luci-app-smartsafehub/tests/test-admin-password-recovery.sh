#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
RESET_HANDLER="$ROOT_DIR/root/etc/rc.button/reset"
HELPER="$ROOT_DIR/root/usr/libexec/smartsafehub-password-recovery"
INIT="$ROOT_DIR/root/etc/init.d/smartsafehub-password-recovery"
SECURITY_MODULE="$ROOT_DIR/root/usr/share/rpcd/ucode/smartsafehub/security.uc"
ENTRY="$ROOT_DIR/frontend/src/app/AuthenticatedEntry.tsx"
SETUP_PAGE="$ROOT_DIR/frontend/src/pages/InitialPasswordSetupPage.tsx"
LOGIN_PAGE="$ROOT_DIR/frontend/src/login/LoginApp.tsx"
SETTINGS_PAGE="$ROOT_DIR/frontend/src/pages/SettingsPage.tsx"
SECURITY_TYPES="$ROOT_DIR/frontend/src/types/security.ts"
MAIN="$ROOT_DIR/frontend/src/main.tsx"
MAKEFILE="$ROOT_DIR/Makefile"
FEATURES="$ROOT_DIR/docs/FEATURES.md"
RECOVERY_BRIDGE="$ROOT_DIR/root/www/cgi-bin/smartsafehub-password-recovery"
RECOVERY_API="$ROOT_DIR/frontend/src/api/passwordRecovery.ts"

fail() {
	printf 'FAIL: %s\n' "$*" >&2
	exit 1
}

for file in "$RESET_HANDLER" "$HELPER" "$INIT" "$SECURITY_MODULE" "$ENTRY" "$SETUP_PAGE" "$LOGIN_PAGE" "$SETTINGS_PAGE" "$SECURITY_TYPES" "$MAIN" "$MAKEFILE" "$FEATURES" "$RECOVERY_BRIDGE" "$RECOVERY_API"; do
	[ -f "$file" ] || fail "missing password recovery file: ${file#$ROOT_DIR/}"
done

[ -x "$RESET_HANDLER" ] || fail 'SmartSafeHub reset handler must be executable'
[ -x "$HELPER" ] || fail 'password recovery helper must be executable'
[ -x "$INIT" ] || fail 'password recovery boot reconciler must be executable'
[ -x "$RECOVERY_BRIDGE" ] || fail 'public password recovery bridge must be executable'

# SmartSafeHub Reset Policy v1 owns the physical reset gesture. Keep short press
# reboot behavior, reserve 5-9 seconds for password recovery, and move the
# destructive factory reset boundary to ten seconds or longer.
grep -Fq "SMARTSAFEHUB_RESET_POLICY='smartsafehub-v1'" "$RESET_HANDLER" || \
	fail 'reset handler must identify SmartSafeHub Reset Policy v1'
grep -Fq '[ "$SEEN" -lt 1 ]' "$RESET_HANDLER" || \
	fail 'sub-second reset press must preserve the reboot action'
grep -Fq '[ "$SEEN" -ge 5 ] && [ "$SEEN" -lt 10 ]' "$RESET_HANDLER" || \
	fail '5-9 second reset release must select administrator password recovery'
grep -Fq '"$RECOVERY_HELPER" request' "$RESET_HANDLER" || \
	fail 'password recovery window must delegate to the recovery helper'
grep -Fq '[ "$SEEN" -ge 10 ]' "$RESET_HANDLER" || \
	fail 'factory reset must require a reset hold of at least ten seconds'
grep -Fq '"$FACTORYRESET_BIN" -y && "$REBOOT_BIN" &' "$RESET_HANDLER" || \
	fail 'ten-second reset path must retain OpenWrt factoryreset semantics'
if find "$ROOT_DIR/root/etc/hotplug.d/button" -maxdepth 1 -type f -name '*password-recovery*' 2>/dev/null | grep -q .; then
	fail 'reset policy must have one owner and must not keep the old parallel hotplug recovery hook'
fi

# Live package upgrades on firmware that still owns the stock OpenWrt reset
# handler are unsafe because that firmware interprets >=5 seconds as factory
# reset. The package must refuse that mismatched combination.
grep -Fq "SMARTSAFEHUB_RESET_POLICY='smartsafehub-v1'" "$MAKEFILE" || \
	fail 'package pre-install must detect the SmartSafeHub reset policy handler'
grep -Fq 'firmware update required for SmartSafeHub Reset Policy v1' "$MAKEFILE" || \
	fail 'package pre-install must reject old firmware with the stock reset handler'
grep -Fq '/etc/init.d/smartsafehub-password-recovery enable' "$MAKEFILE" || \
	fail 'package post-install must enable password recovery boot reconciliation'

# Backend and frontend distinguish physical recovery from a normal first boot,
# and complete the temporary SSH lockdown after a new password is committed.
grep -Fq "const PASSWORD_RECOVERY_MARKER = '/etc/smartsafehub/password-recovery';" "$SECURITY_MODULE" || \
	fail 'security RPC must track persistent password recovery state'
grep -Fq 'recovery: !configured && root_password_recovery_requested()' "$SECURITY_MODULE" || \
	fail 'password status must expose recovery only while root password is empty'
grep -Fq "run_command([PASSWORD_RECOVERY_HELPER, 'complete'], 5000)" "$SECURITY_MODULE" || \
	fail 'successful password setup must complete password recovery state'
grep -Fq 'recovery: boolean;' "$SECURITY_TYPES" || \
	fail 'frontend password status must include the recovery flag'
grep -Fq 'setPasswordRecovery(status.recovery);' "$ENTRY" || \
	fail 'authenticated entry must preserve the backend recovery state'
grep -Fq 'recovery={passwordRecovery}' "$ENTRY" || \
	fail 'password setup page must receive the physical recovery state'
grep -Fq "recovery ? '관리자 비밀번호 복구' : '관리자 비밀번호 설정'" "$SETUP_PAGE" || \
	fail 'password setup page must provide recovery-specific copy'
grep -Fq '네트워크, Wi-Fi, SafeShield 등 기존 설정은 그대로 유지됩니다.' "$SETUP_PAGE" || \
	fail 'recovery screen must explain that normal router settings are preserved'
grep -Fq 'Reset 버튼을 5~9초' "$LOGIN_PAGE" || \
	fail 'login page must explain the password recovery hold window'
grep -Fq '10초 이상 누르면 모든 사용자 설정을 초기화' "$LOGIN_PAGE" || \
	fail 'login page must warn about the destructive factory-reset boundary'
grep -Fq '비밀번호를 잊었을 때' "$SETTINGS_PAGE" || \
	fail 'administrator password card must document the recovery path before lockout'
grep -Fq '관리자 비밀번호 복구가 완료되었습니다.' "$MAIN" || \
	fail 'recovery completion must return to login with recovery-specific feedback'
grep -Fq "requestPasswordRecoverySession" "$MAIN" || \
	fail 'entry bootstrap must probe physical password recovery before normal login'
recovery_line="$(grep -n 'requestPasswordRecoverySession()' "$MAIN" | head -1 | cut -d: -f1)"
session_line="$(grep -n 'probeLuciSession()' "$MAIN" | tail -1 | cut -d: -f1)"
[ -n "$recovery_line" ] && [ -n "$session_line" ] && [ "$recovery_line" -lt "$session_line" ] || \
	fail 'password recovery probe must run before ordinary LuCI session probing'
grep -Fq "const RECOVERY_ENDPOINT = '/cgi-bin/smartsafehub-password-recovery';" "$RECOVERY_API" || \
	fail 'frontend recovery probe must use the package public recovery bridge'
grep -Fq 'system_root_password_status' "$RECOVERY_BRIDGE" || \
	fail 'recovery bridge must grant root-password status only for recovery setup'
grep -Fq 'system_root_password_set' "$RECOVERY_BRIDGE" || \
	fail 'recovery bridge must grant the initial root-password setter'
if grep -Eq '\[\"smartsafehub\",\"\*\"\]|system_root_password_change|session.login' "$RECOVERY_BRIDGE"; then
	fail 'recovery bridge must not grant wildcard, password-change, or full login access'
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT INT TERM
MOCK_BIN="$TMP_DIR/bin"
STATE_DIR="$TMP_DIR/state"
SHADOW_FILE="$TMP_DIR/shadow"
DROPBEAR_STATE="$TMP_DIR/dropbear-enabled"
DROPBEAR_RUNNING="$TMP_DIR/dropbear-running"
CALLS="$TMP_DIR/calls"
mkdir -p "$MOCK_BIN" "$STATE_DIR"
: > "$CALLS"

cat > "$MOCK_BIN/passwd" <<'EOF_PASSWD'
#!/bin/sh
printf 'passwd %s\n' "$*" >> "$MOCK_CALLS"
[ "${MOCK_PASSWD_FAIL:-0}" = "1" ] && exit 1
[ "$1" = '-d' ] && [ "$2" = 'root' ] || exit 2
awk -F: 'BEGIN { OFS=":" } $1 == "root" { $2="" } { print }' "$MOCK_SHADOW_FILE" > "$MOCK_SHADOW_FILE.tmp" || exit 1
mv "$MOCK_SHADOW_FILE.tmp" "$MOCK_SHADOW_FILE"
EOF_PASSWD
chmod +x "$MOCK_BIN/passwd"

cat > "$MOCK_BIN/dropbear" <<'EOF_DROPBEAR'
#!/bin/sh
printf 'dropbear %s\n' "$*" >> "$MOCK_CALLS"
case "$1" in
	enabled) [ "$(cat "$MOCK_DROPBEAR_STATE")" = '1' ] ;;
	enable) printf '1\n' > "$MOCK_DROPBEAR_STATE" ;;
	disable) printf '0\n' > "$MOCK_DROPBEAR_STATE" ;;
	start) printf '1\n' > "$MOCK_DROPBEAR_RUNNING" ;;
	stop) printf '0\n' > "$MOCK_DROPBEAR_RUNNING" ;;
	*) exit 2 ;;
esac
EOF_DROPBEAR
chmod +x "$MOCK_BIN/dropbear"

cat > "$MOCK_BIN/reboot" <<'EOF_REBOOT'
#!/bin/sh
printf 'reboot\n' >> "$MOCK_CALLS"
: > "$MOCK_REBOOTED"
EOF_REBOOT
chmod +x "$MOCK_BIN/reboot"

cat > "$MOCK_BIN/logger" <<'EOF_LOGGER'
#!/bin/sh
printf 'logger %s\n' "$*" >> "$MOCK_CALLS"
EOF_LOGGER
chmod +x "$MOCK_BIN/logger"

run_helper() {
	SMARTSAFEHUB_RECOVERY_STATE_DIR="$STATE_DIR" \
	SMARTSAFEHUB_RECOVERY_SHADOW_FILE="$SHADOW_FILE" \
	SMARTSAFEHUB_RECOVERY_PASSWD_BIN="$MOCK_BIN/passwd" \
	SMARTSAFEHUB_RECOVERY_DROPBEAR_INIT="$MOCK_BIN/dropbear" \
	SMARTSAFEHUB_RECOVERY_REBOOT_BIN="$MOCK_BIN/reboot" \
	SMARTSAFEHUB_RECOVERY_LOGGER_BIN="$MOCK_BIN/logger" \
	MOCK_CALLS="$CALLS" \
	MOCK_SHADOW_FILE="$SHADOW_FILE" \
	MOCK_DROPBEAR_STATE="$DROPBEAR_STATE" \
	MOCK_DROPBEAR_RUNNING="$DROPBEAR_RUNNING" \
	MOCK_REBOOTED="$TMP_DIR/rebooted" \
	"$HELPER" "$@"
}

reset_fixture() {
	printf 'root:$6$examplehash:20000:0:99999:7:::\n' > "$SHADOW_FILE"
	printf '1\n' > "$DROPBEAR_STATE"
	printf '1\n' > "$DROPBEAR_RUNNING"
	rm -f "$STATE_DIR/password-recovery" "$TMP_DIR/rebooted"
	: > "$CALLS"
}

reset_fixture
run_helper request
for _i in 1 2 3 4 5; do
	[ -f "$TMP_DIR/rebooted" ] && break
	sleep 1
done
[ -f "$STATE_DIR/password-recovery" ] || fail 'recovery request must create a persistent marker'
grep -Fq 'reset_policy=smartsafehub-v1' "$STATE_DIR/password-recovery" || \
	fail 'recovery marker must record the reset policy contract'
grep -Fq 'dropbear_enabled=1' "$STATE_DIR/password-recovery" || \
	fail 'recovery marker must remember that SSH was enabled before recovery'
grep -Eq '^root::' "$SHADOW_FILE" || fail 'recovery request must clear only the root password'
[ "$(cat "$DROPBEAR_STATE")" = '0' ] || fail 'recovery request must disable passwordless SSH across reboot'
[ "$(cat "$DROPBEAR_RUNNING")" = '0' ] || fail 'recovery request must stop the active SSH server'
[ -f "$TMP_DIR/rebooted" ] || fail 'recovery request must reboot into the password setup flow'

run_helper boot
[ "$(cat "$DROPBEAR_STATE")" = '0' ] || fail 'boot reconciliation must keep SSH disabled while root password is empty'
[ -f "$STATE_DIR/password-recovery" ] || fail 'boot reconciliation must keep an active recovery marker'

printf 'root:$6$newhash:20000:0:99999:7:::\n' > "$SHADOW_FILE"
run_helper complete
[ ! -e "$STATE_DIR/password-recovery" ] || fail 'completed recovery must remove the persistent marker'
[ "$(cat "$DROPBEAR_STATE")" = '1' ] || fail 'completed recovery must restore the previous SSH enable state'
[ "$(cat "$DROPBEAR_RUNNING")" = '1' ] || fail 'completed recovery must restart SSH when it was previously enabled'

# Recovery must not broaden SSH access when it was intentionally disabled.
reset_fixture
printf '0\n' > "$DROPBEAR_STATE"
printf '0\n' > "$DROPBEAR_RUNNING"
run_helper request
for _i in 1 2 3 4 5; do
	[ -f "$TMP_DIR/rebooted" ] && break
	sleep 1
done
printf 'root:$6$newhash:20000:0:99999:7:::\n' > "$SHADOW_FILE"
run_helper complete
[ "$(cat "$DROPBEAR_STATE")" = '0' ] || fail 'recovery must preserve an originally disabled SSH service'
[ "$(cat "$DROPBEAR_RUNNING")" = '0' ] || fail 'recovery must not start SSH when it was originally disabled'

# Password deletion failure must rollback the recovery marker and SSH state.
reset_fixture
if MOCK_PASSWD_FAIL=1 \
	SMARTSAFEHUB_RECOVERY_STATE_DIR="$STATE_DIR" \
	SMARTSAFEHUB_RECOVERY_SHADOW_FILE="$SHADOW_FILE" \
	SMARTSAFEHUB_RECOVERY_PASSWD_BIN="$MOCK_BIN/passwd" \
	SMARTSAFEHUB_RECOVERY_DROPBEAR_INIT="$MOCK_BIN/dropbear" \
	SMARTSAFEHUB_RECOVERY_REBOOT_BIN="$MOCK_BIN/reboot" \
	SMARTSAFEHUB_RECOVERY_LOGGER_BIN="$MOCK_BIN/logger" \
	MOCK_CALLS="$CALLS" MOCK_SHADOW_FILE="$SHADOW_FILE" \
	MOCK_DROPBEAR_STATE="$DROPBEAR_STATE" MOCK_DROPBEAR_RUNNING="$DROPBEAR_RUNNING" \
	MOCK_REBOOTED="$TMP_DIR/rebooted" \
	"$HELPER" request; then
	fail 'password deletion failure must make recovery request fail'
fi
[ ! -e "$STATE_DIR/password-recovery" ] || fail 'failed recovery must remove its marker'
[ "$(cat "$DROPBEAR_STATE")" = '1' ] || fail 'failed recovery must restore SSH enable state'
[ "$(cat "$DROPBEAR_RUNNING")" = '1' ] || fail 'failed recovery must restore SSH running state'
[ ! -e "$TMP_DIR/rebooted" ] || fail 'failed recovery must not reboot'

# Factory-default devices already have an empty root password; do not create a
# second recovery cycle there.
printf 'root::20000:0:99999:7:::\n' > "$SHADOW_FILE"
rm -f "$STATE_DIR/password-recovery" "$TMP_DIR/rebooted"
run_helper request
[ ! -e "$STATE_DIR/password-recovery" ] || fail 'already-empty root password must not create a recovery marker'
[ ! -e "$TMP_DIR/rebooted" ] || fail 'already-empty root password must not force another reboot'

# The public recovery bridge must remain inert outside a physical recovery
# state and, while recovery is active, issue only a narrow short-lived ubus
# session instead of an automatically authenticated root session.
BRIDGE_MARKER="$TMP_DIR/bridge-password-recovery"
BRIDGE_SHADOW="$TMP_DIR/bridge-shadow"
BRIDGE_CALLS="$TMP_DIR/bridge-calls"
BRIDGE_SID='0123456789abcdef0123456789abcdef'
: > "$BRIDGE_CALLS"

cat > "$MOCK_BIN/ubus" <<'EOF_UBUS'
#!/bin/sh
printf '%s\n' "$*" >> "$MOCK_BRIDGE_CALLS"
[ "$1" = 'call' ] || exit 2
case "$2" in
	session)
		case "$3" in
			create) printf '{"ubus_rpc_session":"%s"}\n' "$MOCK_BRIDGE_SID" ;;
			grant|destroy) printf '{}\n' ;;
			*) exit 3 ;;
		esac
		;;
	*) exit 4 ;;
esac
EOF_UBUS
chmod +x "$MOCK_BIN/ubus"

cat > "$MOCK_BIN/jsonfilter" <<'EOF_JSONFILTER'
#!/bin/sh
cat >/dev/null
[ "$1" = '-e' ] && [ "$2" = '@.ubus_rpc_session' ] || exit 2
printf '%s\n' "$MOCK_BRIDGE_SID"
EOF_JSONFILTER
chmod +x "$MOCK_BIN/jsonfilter"

run_bridge() {
	REQUEST_METHOD=GET \
	SMARTSAFEHUB_RECOVERY_MARKER="$BRIDGE_MARKER" \
	SMARTSAFEHUB_RECOVERY_SHADOW_FILE="$BRIDGE_SHADOW" \
	SMARTSAFEHUB_RECOVERY_UBUS_BIN="$MOCK_BIN/ubus" \
	SMARTSAFEHUB_RECOVERY_JSONFILTER_BIN="$MOCK_BIN/jsonfilter" \
	MOCK_BRIDGE_CALLS="$BRIDGE_CALLS" \
	MOCK_BRIDGE_SID="$BRIDGE_SID" \
	"$RECOVERY_BRIDGE"
}

printf 'root::20000:0:99999:7:::\n' > "$BRIDGE_SHADOW"
rm -f "$BRIDGE_MARKER"
: > "$BRIDGE_CALLS"
bridge_output="$(run_bridge)"
printf '%s\n' "$bridge_output" | grep -Fq '{"active":false}' || \
	fail 'recovery bridge must stay inactive without a physical recovery marker'
[ ! -s "$BRIDGE_CALLS" ] || fail 'inactive recovery bridge must not create an ubus session'

: > "$BRIDGE_MARKER"
printf 'root:$6$configured:20000:0:99999:7:::\n' > "$BRIDGE_SHADOW"
: > "$BRIDGE_CALLS"
bridge_output="$(run_bridge)"
printf '%s\n' "$bridge_output" | grep -Fq '{"active":false}' || \
	fail 'recovery bridge must stay inactive when the root password is configured'
[ ! -s "$BRIDGE_CALLS" ] || fail 'configured root password must not create a recovery session'

printf 'root::20000:0:99999:7:::\n' > "$BRIDGE_SHADOW"
: > "$BRIDGE_CALLS"
bridge_output="$(run_bridge)"
printf '%s\n' "$bridge_output" | grep -Fq "{\"active\":true,\"sessionId\":\"$BRIDGE_SID\"}" || \
	fail 'active physical recovery must return a restricted recovery session'
grep -Fq 'session create {"timeout":900}' "$BRIDGE_CALLS" || \
	fail 'recovery bridge must create a short-lived fifteen-minute session'
grep -Fq '"scope":"ubus"' "$BRIDGE_CALLS" || \
	fail 'recovery bridge must grant only ubus procedure access'
grep -Fq '["smartsafehub","system_root_password_status"]' "$BRIDGE_CALLS" || \
	fail 'recovery session must grant password status access'
grep -Fq '["smartsafehub","system_root_password_set"]' "$BRIDGE_CALLS" || \
	fail 'recovery session must grant password setup access'
if grep -Eq 'system_root_password_change|\["smartsafehub","\*"\]|session login' "$BRIDGE_CALLS"; then
	fail 'recovery session must not receive broader administrator access'
fi

grep -Fq 'Reset 버튼을 5~9초' "$FEATURES" || \
	fail 'FEATURES must document the physical administrator password recovery window'
grep -Fq '10초 이상' "$FEATURES" || \
	fail 'FEATURES must document the factory-reset boundary'

printf 'PASS: SmartSafeHub Reset Policy v1 safely separates password recovery from factory reset\n'
