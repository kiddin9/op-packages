#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
LOGIN="$ROOT_DIR/frontend/src/login/LoginApp.tsx"
MAIN="$ROOT_DIR/frontend/src/main.tsx"
SESSION="$ROOT_DIR/frontend/src/auth/session.ts"
SESSION_EVENTS="$ROOT_DIR/frontend/src/auth/sessionEvents.ts"
RPC="$ROOT_DIR/frontend/src/api/rpc.ts"
THEME="$ROOT_DIR/frontend/src/utils/theme.ts"
LUCI_UTIL="$ROOT_DIR/frontend/src/utils/luci.ts"
APP_SHELL="$ROOT_DIR/frontend/src/components/AppShell.tsx"
ICONS="$ROOT_DIR/frontend/src/components/Icons.tsx"
STYLES="$ROOT_DIR/frontend/src/styles/app.css"
BUILT_JS="$ROOT_DIR/root/www/luci-static/smartsafehub/app.js"
BUILT_CSS="$ROOT_DIR/root/www/luci-static/smartsafehub/app.css"

fail() {
	echo "FAIL: $*" >&2
	exit 1
}

for file in "$LOGIN" "$MAIN" "$SESSION" "$LUCI_UTIL" "$SESSION_EVENTS" "$RPC" "$THEME" "$APP_SHELL" "$ICONS" "$STYLES" "$BUILT_JS" "$BUILT_CSS"; do
	[ -f "$file" ] || fail "missing login UI source: ${file#$ROOT_DIR/}"
done

grep -Fq "const [username, setUsername] = useState('root');" "$LOGIN" || \
	fail 'login must keep an editable default LuCI username'
grep -Fq 'autoComplete="username"' "$LOGIN" || \
	fail 'username field must expose browser username autocomplete'
grep -Fq 'name="username"' "$LOGIN" || \
	fail 'username field must expose a stable form name for password managers'
grep -Fq 'autoComplete="current-password"' "$LOGIN" || \
	fail 'password field must expose current-password autocomplete'
grep -Fq 'name="password"' "$LOGIN" || \
	fail 'password field must expose a stable form name for password managers'
grep -Fq "if (!user || (!secret && user !== 'root'))" "$LOGIN" || \
	fail 'login must allow the factory-default root account to reach forced password setup with an empty password'
grep -Fq '<ReloadIcon class="ssh-login-probe-spinner" aria-hidden="true" />' "$LOGIN" || \
	fail 'login session probe must spin the shared reload icon'
grep -Fq '<ReloadIcon class="ssh-login-submit-spinner" aria-hidden="true" />' "$LOGIN" || \
	fail 'login submit busy state must spin the shared reload icon'
grep -Fq 'onSubmit={submit}' "$LOGIN" || \
	fail 'login credentials must be submitted through a form for Enter-key support'
grep -Fq 'usernameInput.current?.focus()' "$LOGIN" || \
	fail 'empty username validation must restore focus to the username field'
grep -Fq 'aria-label={showPassword ? '\''비밀번호 숨기기'\'' : '\''비밀번호 표시'\''}' "$LOGIN" || \
	fail 'password visibility control must remain accessible'
grep -Fq '<EyeOffIcon /> : <EyeIcon />' "$LOGIN" || \
	fail 'password visibility control must use a clear icon affordance'
grep -Fq 'data-theme={theme}' "$LOGIN" || \
	fail 'public login must expose its selected color theme'
grep -Fq 'class="ssh-login-theme-toggle"' "$LOGIN" || \
	fail 'public login must provide a light/dark theme toggle'
grep -Fq 'persistColorTheme(theme);' "$LOGIN" || \
	fail 'public login must persist the shared theme preference'
grep -Fq 'applyDocumentTheme(theme);' "$LOGIN" || \
	fail 'public login must update document theme metadata'
grep -Fq 'applyDocumentTheme(readColorTheme());' "$ROOT_DIR/frontend/src/main.tsx" || \
	fail 'public entry must apply the saved theme before session probing/rendering'

grep -Fq 'const compatibilityPaths = new Set([' "$MAIN" || \
	fail 'public entry must canonicalize supported LuCI compatibility entry paths'
grep -Fq "luciUrl('/smartsafehub')" "$MAIN" || \
	fail 'legacy SmartSafeHub LuCI entry must remain a compatibility path'
grep -Fq "luciUrl('/admin/smartsafehub')" "$MAIN" || \
	fail 'legacy admin SmartSafeHub entry must remain a compatibility path'
grep -Fq 'return `/${normalizedHash}`;' "$LUCI_UTIL" || \
	fail 'official SmartSafeHub public URL must be the router root'

grep -Fq 'response.status === 401' "$SESSION" || \
	fail 'session probe must treat HTTP 401 as an unauthenticated session'
grep -Fq 'response.redirected' "$SESSION" || \
	fail 'session probe must recognize a followed LuCI login redirect after an invalid token body'
grep -Fq '/^<!doctype\s+html/i.test(sessionId)' "$SESSION" || \
	fail 'session probe must recognize a rendered LuCI login document as unauthenticated'
grep -Fq '/^(?:access|permission)\s+denied\.?$/i.test(sessionId)' "$SESSION" || \
	fail 'session probe must recognize a plain Access denied response as unauthenticated'

grep -Fq "export const SESSION_EXPIRED_EVENT = 'smartsafehub:session-expired';" "$SESSION_EVENTS" || \
	fail 'session expiry must use one shared application event'
grep -Fq 'notifySessionExpired(bootstrap.sessionId);' "$RPC" || \
	fail 'confirmed RPC session expiry must notify the application immediately'
grep -Fq "new RpcError('SESSION_EXPIRED', SESSION_EXPIRED_MESSAGE)" "$RPC" || \
	fail 'confirmed access denial must become a dedicated session-expired RPC error'
grep -Fq 'currentSessionMatches(bootstrap.sessionId)' "$RPC" || \
	fail 'stale RPC failures must not expire a newly authenticated session'
grep -Fq 'async function probeRpcSessionAccess' "$RPC" || \
	fail 'RPC access denial must verify the current session against an existing SmartSafeHub RPC before forcing logout'
grep -Fq "'system_root_password_status'" "$RPC" || \
	fail 'RPC access verification must use the long-lived root password status method'
grep -Fq "'RPC_PERMISSION_DENIED'" "$RPC" || \
	fail 'a valid session missing only a new ACL grant must remain an ordinary permission error'
if grep -Fq 'probeLuciSession' "$RPC"; then
	fail 'RPC access-denied recovery must not probe the LuCI session echo endpoint'
fi
grep -Fq 'window.addEventListener(SESSION_EXPIRED_EVENT' "$MAIN" || \
	fail 'public entry must listen for session expiry globally'
grep -Fq 'renderLogin(host, mountPoint, SESSION_EXPIRED_MESSAGE);' "$MAIN" || \
	fail 'session expiry must replace the authenticated application with the login screen'
grep -Fq 'notice={notice}' "$MAIN" || \
	fail 'login rendering must receive session-expiry feedback'
grep -Fq 'class="ssh-login-toast"' "$LOGIN" || \
	fail 'session-expiry feedback must be rendered as a login toast'
grep -Fq 'role="alert"' "$LOGIN" || \
	fail 'session-expiry toast must be announced to assistive technology'
grep -Fq 'window.setTimeout(() => setNotice(null), 7_000);' "$LOGIN" || \
	fail 'session-expiry toast must dismiss automatically'
grep -Fq '.ssh-login-toast {' "$STYLES" || \
	fail 'session-expiry toast must have isolated login styling'

grep -Fq 'smartsafehub:session-expired' "$BUILT_JS" || \
	fail 'built frontend asset must include global session-expiry handling'
grep -Fq 'ssh-login-toast' "$BUILT_JS" || \
	fail 'built frontend asset must include the session-expiry toast'
grep -Fq '.ssh-login-toast' "$BUILT_CSS" || \
	fail 'built stylesheet must include session-expiry toast styling'

grep -Fq "export const THEME_STORAGE_KEY = 'smartsafehub.theme';" "$THEME" || \
	fail 'login and authenticated app must share one theme preference key'
grep -Fq "window.matchMedia('(prefers-color-scheme: dark)')" "$THEME" || \
	fail 'theme utility must fall back to the system color preference'
grep -Fq 'persistColorTheme(theme);' "$APP_SHELL" || \
	fail 'authenticated AppShell must use the shared theme persistence helper'
grep -Fq 'applyDocumentTheme(theme);' "$APP_SHELL" || \
	fail 'authenticated AppShell must use the shared document theme helper'

grep -Fq 'export function EyeIcon' "$ICONS" || \
	fail 'login password control must provide an eye icon'
grep -Fq 'export function EyeOffIcon' "$ICONS" || \
	fail 'login password control must provide an eye-off icon'
grep -Fq 'class="ssh-login-field-icon"' "$LOGIN" || \
	fail 'login credential icons must use a dedicated icon tile'
grep -Fq '.ssh-login-field-icon {' "$STYLES" || \
	fail 'login credential icon tile must have explicit styling'
grep -Fq 'width: 2.35rem;' "$STYLES" || \
	fail 'password visibility icon must use a compact icon-button footprint'
if grep -Fq 'border-left: 1px solid var(--ssh-login-border);' "$STYLES"; then
	fail 'password visibility icon must not render as a full-height split input cell'
fi
grep -Fq 'input:-webkit-autofill' "$STYLES" || \
	fail 'browser autofill must preserve the SmartSafeHub login field surface'
grep -Fq 'border: 2px solid var(--ssh-login-border-strong);' "$STYLES" || \
	fail 'login text inputs must use the same strong product form-control border'
grep -Fq ".ssh-login-page[data-theme='dark']" "$STYLES" || \
	fail 'public login must provide a dark theme palette'
grep -Fq '.ssh-login-theme-toggle {' "$STYLES" || \
	fail 'public login must style its theme toggle as a secondary control'

echo 'PASS: login account, password and theme contracts are consistent'
