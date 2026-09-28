#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
RPC_ENTRY="$ROOT_DIR/root/usr/share/rpcd/ucode/smartsafehub.uc"
SECURITY_MODULE="$ROOT_DIR/root/usr/share/rpcd/ucode/smartsafehub/security.uc"
ACL="$ROOT_DIR/root/usr/share/rpcd/acl.d/luci-app-smartsafehub.json"
SECURITY_API="$ROOT_DIR/frontend/src/api/security.ts"
PASSWORD_UTIL="$ROOT_DIR/frontend/src/utils/password.ts"
SETUP_PAGE="$ROOT_DIR/frontend/src/pages/InitialPasswordSetupPage.tsx"
SETTINGS_PAGE="$ROOT_DIR/frontend/src/pages/SettingsPage.tsx"
APP="$ROOT_DIR/frontend/src/app/App.tsx"
ENTRY="$ROOT_DIR/frontend/src/app/AuthenticatedEntry.tsx"
MAIN="$ROOT_DIR/frontend/src/main.tsx"
SESSION="$ROOT_DIR/frontend/src/auth/session.ts"
FEATURES="$ROOT_DIR/docs/FEATURES.md"

fail() {
	printf 'FAIL: %s\n' "$*" >&2
	exit 1
}

for file in "$RPC_ENTRY" "$SECURITY_MODULE" "$ACL" "$SECURITY_API" "$PASSWORD_UTIL" "$SETUP_PAGE" "$SETTINGS_PAGE" "$APP" "$ENTRY" "$MAIN" "$SESSION" "$FEATURES"; do
	[ -f "$file" ] || fail "missing administrator password change file: ${file#$ROOT_DIR/}"
done

grep -Fq 'export function change_root_password(request)' "$SECURITY_MODULE" || \
	fail 'security backend must expose a dedicated password change handler'
grep -Fq "defer_call('session', 'login'" "$SECURITY_MODULE" || \
	fail 'current administrator password must be verified through rpcd authentication'
grep -Fq "username: 'root'" "$SECURITY_MODULE" || \
	fail 'administrator password verification and update must target root only'
grep -Fq 'password: current_password' "$SECURITY_MODULE" || \
	fail 'current administrator password must be passed only to the authentication call'
grep -Fq 'timeout: 60' "$SECURITY_MODULE" || \
	fail 'password verification session must be intentionally short lived'
grep -Fq 'ubus_rpc_session: verification_session_id' "$SECURITY_MODULE" || \
	fail 'temporary password verification session must be destroyed'
grep -Fq "'SYSTEM_ROOT_PASSWORD_CURRENT_INVALID'" "$SECURITY_MODULE" || \
	fail 'wrong current password must return a dedicated error'
grep -Fq "'SYSTEM_ROOT_PASSWORD_UNCHANGED'" "$SECURITY_MODULE" || \
	fail 'new administrator password must differ from the current password'
grep -Fq 'password: new_password' "$SECURITY_MODULE" || \
	fail 'new administrator password must be written through luci.setPassword'
grep -Fq 'reply_password_change_success(request);' "$SECURITY_MODULE" || \
	fail 'successful password change must invalidate the authenticated session'
grep -Fq 'ubus_rpc_session: session_id' "$SECURITY_MODULE" || \
	fail 'successful password change must destroy the requesting ubus session'
if grep -Fq 'oldpassword:' "$SECURITY_MODULE" || grep -Fq 'rpcd:' "$SECURITY_MODULE"; then
	fail 'OpenWrt 25.12 password write must keep the username/password-only luci.setPassword contract'
fi

grep -Eq '^[[:space:]]*system_root_password_change:[[:space:]]*\{' "$RPC_ENTRY" || \
	fail 'administrator password change RPC must be registered'
grep -Fq "current_password: ''" "$RPC_ENTRY" || \
	fail 'password change RPC must declare current_password input'
grep -Fq "new_password: ''" "$RPC_ENTRY" || \
	fail 'password change RPC must declare new_password input'
grep -Fq 'return change_root_password(request);' "$RPC_ENTRY" || \
	fail 'password change RPC must delegate to the security module'
jq -e '."luci-app-smartsafehub".write.ubus.smartsafehub | index("system_root_password_change") != null' "$ACL" >/dev/null || \
	fail 'administrator password change RPC must be granted by the write ACL'

grep -Fq "'system_root_password_change'" "$SECURITY_API" || \
	fail 'frontend security API must call the dedicated password change RPC'
grep -Fq 'current_password: currentPassword' "$SECURITY_API" || \
	fail 'frontend must send the current password only as the password-change RPC argument'
grep -Fq 'new_password: newPassword' "$SECURITY_API" || \
	fail 'frontend must send the requested new password to the password-change RPC'

grep -Fq 'export function passwordPolicy(password: string)' "$PASSWORD_UTIL" || \
	fail 'initial setup and Settings must share one frontend password policy'
grep -Fq "import { passwordPolicy, passwordPolicySatisfied } from '../utils/password';" "$SETUP_PAGE" || \
	fail 'initial password setup must use the shared password policy'
grep -Fq "import { passwordPolicy, passwordPolicySatisfied } from '../utils/password';" "$SETTINGS_PAGE" || \
	fail 'administrator password change must use the shared password policy'

grep -Fq 'title="관리자 비밀번호"' "$SETTINGS_PAGE" || \
	fail 'system management must expose an administrator password card'
grep -Fq 'autoComplete="current-password"' "$SETTINGS_PAGE" || \
	fail 'current administrator password must expose password-manager autocomplete semantics'
grep -Fq 'autoComplete="new-password"' "$SETTINGS_PAGE" || \
	fail 'new administrator password fields must expose new-password autocomplete semantics'
grep -Fq 'await changeRootPassword(currentPassword, newPassword);' "$SETTINGS_PAGE" || \
	fail 'administrator password card must call the dedicated frontend API'
grep -Fq 'await logoutLuciSession();' "$SETTINGS_PAGE" || \
	fail 'successful password change must also clear the LuCI browser session'
grep -Fq '비밀번호는 현재 공유기에 직접 적용되며 외부 서버로 전송되지 않습니다.' "$SETTINGS_PAGE" || \
	fail 'administrator password UI must explain the local-only password handling boundary'
grep -Fq '현재 로그인 세션은 종료됩니다.' "$SETTINGS_PAGE" || \
	fail 'administrator password UI must warn that the user will be logged out'
grep -Fq 'className="lg:col-span-2"' "$SETTINGS_PAGE" || \
	fail 'system tools must move below the two first-class system management cards on desktop'

grep -Fq 'onAdministratorPasswordChanged={onAdministratorPasswordChanged}' "$APP" || \
	fail 'App must pass the password-change completion callback into Settings'
grep -Fq '<App onAdministratorPasswordChanged={onAdministratorPasswordChanged} />' "$ENTRY" || \
	fail 'authenticated entry must pass the re-login callback into App'
grep -Fq '관리자 비밀번호가 변경되었습니다. 새 비밀번호로 다시 로그인해 주세요.' "$MAIN" || \
	fail 'successful password change must return the user to login with explicit feedback'
grep -Fq "luciUrl('/admin/logout')" "$SESSION" || \
	fail 'password change re-login flow must keep using the LuCI logout endpoint'

grep -Fq '`설정 > 시스템 관리 > 관리자 비밀번호`' "$FEATURES" || \
	fail 'FEATURES must document administrator password changes'

printf 'PASS: administrator password change verifies the current password and forces safe re-login\n'
