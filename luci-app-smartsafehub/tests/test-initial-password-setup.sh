#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
RPC_ENTRY="$ROOT_DIR/root/usr/share/rpcd/ucode/smartsafehub.uc"
SECURITY_MODULE="$ROOT_DIR/root/usr/share/rpcd/ucode/smartsafehub/security.uc"
ACL="$ROOT_DIR/root/usr/share/rpcd/acl.d/luci-app-smartsafehub.json"
LOGIN="$ROOT_DIR/frontend/src/login/LoginApp.tsx"
SESSION="$ROOT_DIR/frontend/src/auth/session.ts"
ENTRY="$ROOT_DIR/frontend/src/app/AuthenticatedEntry.tsx"
SETUP_PAGE="$ROOT_DIR/frontend/src/pages/InitialPasswordSetupPage.tsx"
SETUP_API="$ROOT_DIR/frontend/src/api/initialSetup.ts"
PASSWORD_UTIL="$ROOT_DIR/frontend/src/utils/password.ts"
STYLES="$ROOT_DIR/frontend/src/styles/app.css"
FEATURES="$ROOT_DIR/docs/FEATURES.md"

fail() {
	printf 'FAIL: %s\n' "$*" >&2
	exit 1
}

for file in "$RPC_ENTRY" "$SECURITY_MODULE" "$ACL" "$LOGIN" "$SESSION" "$ENTRY" "$SETUP_PAGE" "$SETUP_API" "$PASSWORD_UTIL" "$STYLES" "$FEATURES"; do
	[ -f "$file" ] || fail "missing initial password setup file: ${file#$ROOT_DIR/}"
done

grep -Fq "const SHADOW_FILE = '/etc/shadow';" "$SECURITY_MODULE" || \
	fail 'root password status must use the local shadow database'
grep -Fq "return length(password_hash) > 0;" "$SECURITY_MODULE" || \
	fail 'only an empty root shadow password field should trigger initial setup'
grep -Fq "if (length(password) < 8)" "$SECURITY_MODULE" || \
	fail 'server-side password policy must require at least eight characters'
grep -Fq 'match(password, /[A-Za-z]/) == null' "$SECURITY_MODULE" || \
	fail 'server-side password policy must require an English letter'
grep -Fq 'match(password, /[0-9]/) == null' "$SECURITY_MODULE" || \
	fail 'server-side password policy must require a number'
grep -Fq "'SYSTEM_ROOT_PASSWORD_ALREADY_CONFIGURED'" "$SECURITY_MODULE" || \
	fail 'initial password RPC must refuse to replace an already configured password'
grep -Fq "defer_call('luci', 'setPassword'" "$SECURITY_MODULE" || \
	fail 'root password setup must delegate to the LuCI setPassword implementation'
grep -Fq "username: 'root'" "$SECURITY_MODULE" || \
	fail 'initial password setup must only target the root account'
grep -Fq 'password: request.args.password' "$SECURITY_MODULE" || \
	fail 'initial password setup must pass the requested password to LuCI'
if grep -Fq 'oldpassword:' "$SECURITY_MODULE"; then
	fail 'OpenWrt 25.12 luci.setPassword compatibility must not send the newer oldpassword argument'
fi
if grep -Fq 'rpcd:' "$SECURITY_MODULE"; then
	fail 'OpenWrt 25.12 luci.setPassword compatibility must not send the newer rpcd argument'
fi
grep -Fq 'root_password_configured() != true' "$SECURITY_MODULE" || \
	fail 'password setup must verify the shadow state after LuCI reports success'
grep -Fq "defer_call('session', 'destroy'" "$SECURITY_MODULE" || \
	fail 'password setup must invalidate the empty-password ubus session server-side'
grep -Fq 'ubus_rpc_session: session_id' "$SECURITY_MODULE" || \
	fail 'password setup must destroy exactly the authenticated session that performed setup'

for method in system_root_password_status system_root_password_set; do
	grep -Eq "^[[:space:]]*${method}:[[:space:]]*\\{" "$RPC_ENTRY" || \
		fail "initial setup RPC is not registered: $method"
done
jq -e '."luci-app-smartsafehub".read.ubus.smartsafehub | index("system_root_password_status") != null' "$ACL" >/dev/null || \
	fail 'root password status RPC must be readable by the authenticated SmartSafeHub session'
jq -e '."luci-app-smartsafehub".write.ubus.smartsafehub | index("system_root_password_set") != null' "$ACL" >/dev/null || \
	fail 'initial root password setter must be in the SmartSafeHub write ACL'
grep -Fq "'SYSTEM_ROOT_PASSWORD_REQUIRED'" "$RPC_ENTRY" || \
	fail 'SmartSafeHub RPC entry must expose the initial password security gate'
[ "$(grep -Fc 'call: require_root_password(function(request)' "$RPC_ENTRY")" -ge 20 ] || \
	fail 'normal SmartSafeHub management RPCs must remain behind the root password gate'

# The factory-default root account can authenticate with an empty password. The
# login form must therefore allow that one case so the authenticated setup gate
# can be reached, while non-root accounts still require a password.
grep -Fq "if (!user || (!secret && user !== 'root'))" "$LOGIN" || \
	fail 'login must allow only root to attempt the factory-default empty password'
grep -Fq '초기 설정 전 root 계정은 비밀번호가 비어 있을 수 있습니다.' "$LOGIN" || \
	fail 'login must explain the factory-default root empty-password case'

# The authenticated entry must check the gate before mounting App. This keeps
# App hooks from starting status/update polling while the router is unsecured.
grep -Fq 'const status = await readRootPasswordStatus();' "$ENTRY" || \
	fail 'authenticated entry must read root password state before the app is mounted'
grep -Fq "setPhase(status.configured ? 'ready' : 'required');" "$ENTRY" || \
	fail 'authenticated entry must force initial setup when root password is missing'
grep -Fq "if (phase === 'ready')" "$ENTRY" || \
	fail 'normal SmartSafeHub App must only mount after the password gate passes'
grep -Fq '<InitialPasswordSetupPage' "$ENTRY" || \
	fail 'missing-password state must render the dedicated initial setup page'
grep -Fq 'recovery={passwordRecovery}' "$ENTRY" || \
	fail 'initial setup entry must pass through password recovery state'

grep -Fq 'length: password.length >= 8' "$PASSWORD_UTIL" || \
	fail 'shared frontend password policy must require at least eight characters'
grep -Fq 'letter: /[A-Za-z]/.test(password)' "$PASSWORD_UTIL" || \
	fail 'shared frontend password policy must require an English letter'
grep -Fq 'number: /[0-9]/.test(password)' "$PASSWORD_UTIL" || \
	fail 'shared frontend password policy must require a number'
grep -Fq "import { passwordPolicy, passwordPolicySatisfied } from '../utils/password';" "$SETUP_PAGE" || \
	fail 'initial setup must consume the shared frontend password policy'
grep -Fq 'if (password !== confirmation)' "$SETUP_PAGE" || \
	fail 'initial setup must require password confirmation'
grep -Fq 'autoComplete="new-password"' "$SETUP_PAGE" || \
	fail 'initial password fields must expose new-password autocomplete semantics'
grep -Fq 'await setInitialRootPassword(password);' "$SETUP_PAGE" || \
	fail 'initial setup form must call the dedicated server-side password setter'
grep -Fq 'await logoutLuciSession();' "$SETUP_PAGE" || \
	fail 'successful initial setup must destroy the old empty-password login session'
grep -Fq "luciUrl('/admin/logout')" "$SESSION" || \
	fail 'session logout must use the LuCI logout endpoint'
grep -Fq "redirect: 'manual'" "$SESSION" || \
	fail 'background logout must not navigate away from the SmartSafeHub entry'
grep -Fq '새 비밀번호로 다시 로그인' "$SETUP_PAGE" || \
	fail 'initial setup UI must explain the required re-login'

grep -Fq '<span class="ssh-password-setup-brand-title-line">SmartSafeHub</span>' "$SETUP_PAGE" || \
	fail 'initial setup hero must keep SmartSafeHub on its own title line'
grep -Fq "recovery ? '비밀번호 복구' : '보호 시작'" "$SETUP_PAGE" || \
	fail 'initial setup hero must render protection start and recovery variants on the second title line'
grep -Fq '.ssh-password-setup-brand-title-line {' "$STYLES" || \
	fail 'initial setup hero title lines must have dedicated block styling'
grep -Fq '비밀번호는 현재 공유기에 직접 설정되며 외부 서버로 전송되지 않습니다.' "$SETUP_PAGE" || \
	fail 'initial setup security note must use product-facing administrator wording'
if grep -Fq '비밀번호는 현재 공유기의 root 계정에 직접 설정되며 외부 서버로 전송되지 않습니다.' "$SETUP_PAGE"; then
	fail 'initial setup security note must not expose the root account name'
fi

grep -Fq '.ssh-password-requirements {' "$STYLES" || \
	fail 'password policy status must have dedicated styling'
grep -Fq '.ssh-password-setup-summary {' "$STYLES" || \
	fail 'initial setup security notice must have dedicated styling'
grep -Fq 'root 관리자 비밀번호' "$FEATURES" || \
	fail 'FEATURES must document the enforced root password initialization flow'

printf 'PASS: root password initialization, policy, RPC gate and re-login contracts are consistent\n'
