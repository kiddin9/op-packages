#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
MAKEFILE="$ROOT_DIR/Makefile"
PACKAGE_JSON="$ROOT_DIR/frontend/package.json"
PACKAGE_LOCK="$ROOT_DIR/frontend/package-lock.json"
CONFIG_FILE="$ROOT_DIR/root/etc/config/smartsafehub"
LOGIN_TEMPLATE="$ROOT_DIR/root/usr/share/ucode/luci/template/smartsafehub/login.ut"
FRONTEND_ENTRY="$ROOT_DIR/frontend/src/main.tsx"
FRONTEND_INDEX="$ROOT_DIR/frontend/index.html"
VITE_CONFIG="$ROOT_DIR/frontend/vite.config.ts"
DEV_ENV_EXAMPLE="$ROOT_DIR/frontend/.env.example"
GITIGNORE="$ROOT_DIR/.gitignore"
README="$ROOT_DIR/README.md"
FAVICON_FILE="$ROOT_DIR/root/www/luci-static/smartsafehub/favicon.svg"
SHELLSPEC_CONFIG="$ROOT_DIR/.shellspec"
SHELLSPEC_CONTRACTS="$ROOT_DIR/spec/contracts_spec.sh"

fail() {
	echo "FAIL: $*" >&2
	exit 1
}

require_file() {
	[ -f "$1" ] || fail "missing required file: ${1#$ROOT_DIR/}"
}

require_executable() {
	[ -x "$1" ] || fail "file must be executable in git checkout: ${1#$ROOT_DIR/}"
}

make_value() {
	key="$1"
	awk -F ':=' -v key="$key" '$1 == key { print $2; exit }' "$MAKEFILE" | tr -d '[:space:]'
}

require_file "$MAKEFILE"
require_file "$PACKAGE_JSON"
require_file "$PACKAGE_LOCK"
require_file "$CONFIG_FILE"
grep -Fq "config system 'system'" "$CONFIG_FILE" || \
	fail 'SmartSafeHub config must include the system metadata section'
grep -Fq "option timezone_initialized '0'" "$CONFIG_FILE" || \
	fail 'fresh SmartSafeHub config must leave browser timezone initialization pending'
require_file "$LOGIN_TEMPLATE"
require_file "$FRONTEND_ENTRY"
require_file "$FRONTEND_INDEX"
require_file "$VITE_CONFIG"
require_file "$README"
require_file "$FAVICON_FILE"
require_file "$SHELLSPEC_CONFIG"
require_file "$SHELLSPEC_CONTRACTS"
[ ! -e "$ROOT_DIR/tests/run.sh" ] || fail 'tests/run.sh must not be used; run shellspec directly'

require_executable "$ROOT_DIR/root/etc/init.d/smartsafehub-events"
require_executable "$ROOT_DIR/root/etc/init.d/smartsafehub-updater"
require_executable "$ROOT_DIR/root/etc/init.d/smartsafehub-firmware"
require_executable "$ROOT_DIR/root/etc/init.d/smartsafehub-maintenance"
require_executable "$ROOT_DIR/root/etc/init.d/smartsafehub-health"
require_executable "$ROOT_DIR/root/etc/init.d/smartsafehub-license"
require_file "$ROOT_DIR/root/usr/lib/smartsafehub/common.sh"
require_executable "$ROOT_DIR/root/usr/libexec/smartsafehub-events"
require_executable "$ROOT_DIR/root/usr/libexec/smartsafehub-activity-sync"
require_executable "$ROOT_DIR/root/etc/init.d/smartsafehub-activity-sync"
require_executable "$ROOT_DIR/root/usr/libexec/smartsafehub-updater"
require_executable "$ROOT_DIR/root/usr/libexec/smartsafehub-firmware"
require_executable "$ROOT_DIR/root/usr/libexec/smartsafehub-maintenance"
require_executable "$ROOT_DIR/root/usr/libexec/smartsafehub-health"
require_executable "$ROOT_DIR/root/usr/libexec/smartsafehub-license"
require_executable "$ROOT_DIR/root/usr/libexec/smartsafehub-backup"
[ ! -e "$ROOT_DIR/root/lib/upgrade/keep.d/smartsafehub" ] || fail "firmware.json must not be preserved through a SmartSafeHub keep.d rule"
require_executable "$ROOT_DIR/root/etc/uci-defaults/91-smartsafehub-firmware-identity"
require_file "$ROOT_DIR/root/usr/libexec/smartsafehub-root-entry"
require_executable "$ROOT_DIR/root/etc/uci-defaults/90-smartsafehub-system-defaults"
require_executable "$ROOT_DIR/root/etc/uci-defaults/99-smartsafehub-root-entry"
require_executable "$ROOT_DIR/tests/test-static-validation.sh"
require_executable "$ROOT_DIR/tests/test-shell-pipeline-safety.sh"
require_executable "$ROOT_DIR/tests/test-events.sh"
require_executable "$ROOT_DIR/tests/test-activity-ui-contract.sh"
require_executable "$ROOT_DIR/tests/test-activity-cloud-sync.sh"
require_executable "$ROOT_DIR/tests/test-common-shell.sh"
require_executable "$ROOT_DIR/tests/test-updater.sh"
require_executable "$ROOT_DIR/tests/test-firmware-updater.sh"
require_executable "$ROOT_DIR/tests/test-firmware-identity.sh"
require_executable "$ROOT_DIR/tests/test-package-contract.sh"
require_executable "$ROOT_DIR/tests/test-tailwind-shadow-dom.sh"
require_executable "$ROOT_DIR/tests/test-document-ui-contract.sh"
require_executable "$ROOT_DIR/tests/test-documentation-contract.sh"
require_executable "$ROOT_DIR/tests/test-custom-select-contract.sh"
require_executable "$ROOT_DIR/tests/test-reload-safety.sh"
require_executable "$ROOT_DIR/tests/test-rpc-contract.sh"
require_executable "$ROOT_DIR/tests/test-system-time-contract.sh"
require_executable "$ROOT_DIR/tests/test-system-defaults.sh"
require_executable "$ROOT_DIR/tests/test-scheduled-reboot.sh"
require_executable "$ROOT_DIR/tests/test-health.sh"
require_executable "$ROOT_DIR/tests/test-license.sh"
require_executable "$ROOT_DIR/tests/test-backup-restore.sh"
require_executable "$ROOT_DIR/tests/test-initial-password-setup.sh"
require_executable "$ROOT_DIR/tests/test-ucode-imports.sh"
require_executable "$ROOT_DIR/tests/test-runtime-path-contract.sh"
require_executable "$ROOT_DIR/tests/test-lan-settings.sh"
require_executable "$ROOT_DIR/tests/test-root-url-rewrite.sh"
require_executable "$ROOT_DIR/tests/test-rpcd-reconcile.sh"
require_executable "$ROOT_DIR/root/usr/libexec/smartsafehub-rpcd-reconcile"

pkg_version="$(make_value PKG_VERSION)"
pkg_release="$(make_value PKG_RELEASE)"
frontend_version="$(jq -er '.version' "$PACKAGE_JSON")"
lock_version="$(jq -er '.version' "$PACKAGE_LOCK")"
lock_root_version="$(jq -er '.packages[""].version' "$PACKAGE_LOCK")"

[ -n "$pkg_version" ] || fail 'PKG_VERSION is missing'
printf '%s\n' "$pkg_version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' || \
	fail 'PKG_VERSION must use x.y.z format'
case "$pkg_release" in
	''|*[!0-9]*) fail 'PKG_RELEASE must be a positive integer' ;;
esac
[ "$pkg_release" -gt 0 ] || fail 'PKG_RELEASE must be greater than zero'

[ "$frontend_version" = "$pkg_version" ] || \
	fail "frontend/package.json version ($frontend_version) does not match PKG_VERSION ($pkg_version)"
[ "$lock_version" = "$pkg_version" ] || \
	fail "frontend/package-lock.json version ($lock_version) does not match PKG_VERSION ($pkg_version)"
[ "$lock_root_version" = "$pkg_version" ] || \
	fail "package-lock root version ($lock_root_version) does not match PKG_VERSION ($pkg_version)"

package_release_version="${pkg_version}-r${pkg_release}"
grep -Fq "data-asset-version=\"$package_release_version\"" "$LOGIN_TEMPLATE" || \
	fail "login template asset version must be $package_release_version"
grep -Fq "app.js?v=$package_release_version" "$LOGIN_TEMPLATE" || \
	fail "login template app.js cache key must be $package_release_version"
grep -Fq 'rel="icon" type="image/svg+xml"' "$LOGIN_TEMPLATE" || \
	fail 'login template must register the SmartSafeHub SVG favicon'
grep -Fq "favicon.svg?v=$package_release_version" "$LOGIN_TEMPLATE" || \
	fail "favicon cache key must be $package_release_version"
grep -Fq "assetVersion: host.dataset.assetVersion ?? '$package_release_version'" "$FRONTEND_ENTRY" || \
	fail "frontend fallback asset version must be $package_release_version"

grep -Fq 'data-asset-base="/src/styles/"' "$FRONTEND_INDEX" || \
	fail 'Vite dev index must load the Shadow DOM stylesheet from the root dev base'
grep -Fq "const isDevServer = command === 'serve';" "$VITE_CONFIG" || \
	fail 'Vite config must explicitly distinguish dev serve from production build'
grep -Fq "import { defineConfig, loadEnv } from 'vite';" "$VITE_CONFIG" || \
	fail 'Vite dev server must support SMARTSAFEHUB_DEV_ROUTER from local Vite env files'
grep -Fq "loadEnv(mode, frontendDirectory, 'SMARTSAFEHUB_')" "$VITE_CONFIG" || \
	fail 'Vite dev server must load only SmartSafeHub-prefixed local environment values'
grep -Fq 'process.env.SMARTSAFEHUB_DEV_ROUTER ?? fileEnv.SMARTSAFEHUB_DEV_ROUTER' "$VITE_CONFIG" || \
	fail 'explicit process environment must take precedence over frontend/.env.local'
grep -Fq 'SMARTSAFEHUB_DEV_ROUTER is required for local development.' "$VITE_CONFIG" || \
	fail 'Vite dev server must fail fast instead of silently running without the router proxy'
grep -Fq 'const devRouterTarget = isDevServer ? resolveDevRouterTarget(mode) : undefined;' "$VITE_CONFIG" || \
	fail 'router target resolution must run only for Vite serve, never production build'
grep -Fq "'/cgi-bin': {" "$VITE_CONFIG" || \
	fail 'Vite dev server must proxy SmartSafeHub LuCI and upload requests under /cgi-bin'
grep -Fq 'target: devRouterTarget,' "$VITE_CONFIG" || \
	fail 'Vite dev proxy must use the validated router target instead of a hard-coded address'
grep -Fq 'changeOrigin: true,' "$VITE_CONFIG" || \
	fail 'Vite dev proxy must rewrite the Host header for the target router'
grep -Fq 'secure: false,' "$VITE_CONFIG" || \
	fail 'Vite dev proxy must permit self-signed HTTPS router certificates during development'
grep -Fq "cookieDomainRewrite: ''," "$VITE_CONFIG" || \
	fail 'Vite dev proxy must strip router cookie domains for localhost sessions'
grep -Fq "base: isDevServer ? '/' : '/luci-static/smartsafehub/'," "$VITE_CONFIG" || \
	fail 'Vite must use root base for dev serve and preserve /luci-static/smartsafehub/ for production builds'
[ "$(grep -Fc 'resolveDevRouterTarget(mode)' "$VITE_CONFIG")" -eq 1 ] || \
	fail 'router target resolution must have exactly one serve-only call site'
grep -Fq 'SMARTSAFEHUB_DEV_ROUTER=http://192.168.1.1' "$DEV_ENV_EXAMPLE" || \
	fail 'frontend/.env.example must document the local router proxy target'
grep -Fq 'frontend/.env.local' "$GITIGNORE" || \
	fail 'local router environment overrides must stay out of git'
if grep -Eq 'target:.*(192\.168\.|10\.|172\.)' "$VITE_CONFIG"; then
	fail 'Vite dev proxy must not hard-code a private router address'
fi

grep -Eq '^LUCI_DEPENDS:=.*(^|[[:space:]])\+safeshield([[:space:]]|$)' "$MAKEFILE" || \
	fail 'LUCI_DEPENDS must include +safeshield'
grep -Eq '^LUCI_DEPENDS:=.*(^|[[:space:]])\+uclient-fetch([[:space:]]|$)' "$MAKEFILE" || \
	fail 'LUCI_DEPENDS must include +uclient-fetch for release note downloads'
grep -Eq '^LUCI_DEPENDS:=.*(^|[[:space:]])\+jsonfilter([[:space:]]|$)' "$MAKEFILE" || \
	fail 'LUCI_DEPENDS must include +jsonfilter for firmware metadata validation'
grep -Eq '^LUCI_DEPENDS:=.*(^|[[:space:]])\+igmpproxy([[:space:]]|$)' "$MAKEFILE" || \
	fail 'LUCI_DEPENDS must include +igmpproxy for IPTV multicast support'
grep -Eq '^LUCI_EXTRA_DEPENDS:=safeshield \(>=[0-9]+\.[0-9]+\.[0-9]+([._~+-][A-Za-z0-9._~+-]+)?\)$' "$MAKEFILE" || \
	fail 'LUCI_EXTRA_DEPENDS must require a minimum safeshield version'

safeshield_min_version="$(sed -n 's/^LUCI_EXTRA_DEPENDS:=safeshield (>=\([^)]*\))$/\1/p' "$MAKEFILE")"
[ -n "$safeshield_min_version" ] || fail 'could not resolve minimum safeshield version from Makefile'
grep -Fq "safeshield (>= $safeshield_min_version)" "$README" || \
	fail "README safeshield dependency must match Makefile minimum version ($safeshield_min_version)"

awk '
	/^define Package\/luci-app-smartsafehub\/conffiles$/ { in_block = 1; next }
	in_block && /^endef$/ { exit }
	in_block && $0 == "/etc/config/smartsafehub" { found = 1 }
	END { exit(found ? 0 : 1) }
' "$MAKEFILE" || fail '/etc/config/smartsafehub must be declared as a conffile'

preinst_block="$(awk '
	/^define Package\/luci-app-smartsafehub\/preinst$/ { in_block = 1 }
	in_block { print }
	in_block && /^endef$/ { exit }
' "$MAKEFILE")"
[ -n "$preinst_block" ] || fail 'package preinst hook is missing'
printf '%s\n' "$preinst_block" | grep -Fq '[ -z "$${IPKG_INSTROOT}" ]' ||
	fail 'package preinst must limit legacy event-daemon migration to runtime installation'

postinst_block="$(awk '
	/^define Package\/luci-app-smartsafehub\/postinst$/ { in_block = 1 }
	in_block { print }
	in_block && /^endef$/ { exit }
' "$MAKEFILE")"
[ -n "$postinst_block" ] || fail 'package postinst hook is missing'
printf '%s\n' "$postinst_block" | grep -Fq '[ -z "$${IPKG_INSTROOT}" ]' ||
	fail 'package postinst must limit service enable to runtime installation'
printf '%s\n' "$postinst_block" | grep -Fq 'mkdir -p /tmp/smartsafehub' ||
	fail 'package postinst must create the SmartSafeHub runtime directory'
printf '%s\n' "$postinst_block" | grep -Fq '/etc/init.d/smartsafehub-events enable' ||
	fail 'package postinst must force-enable smartsafehub-events so boot events survive upgrades'
printf '%s\n' "$postinst_block" | grep -Fq '/etc/init.d/smartsafehub-events restart' ||
	fail 'package postinst must restart the unified smartsafehub-events daemon after upgrades'
printf '%s\n' "$postinst_block" | grep -Fq '/etc/init.d/smartsafehub-updater enable' ||
	fail 'package postinst must force-enable smartsafehub-updater so scheduled checks survive upgrades'
if printf '%s\n' "$postinst_block" | grep -Fq '/etc/init.d/smartsafehub-updater restart'; then
	fail 'package postinst must not restart smartsafehub-updater while it may be upgrading itself'
fi
printf '%s\n' "$postinst_block" | grep -Fq '/etc/init.d/smartsafehub-firmware enable' ||
	fail 'package postinst must force-enable smartsafehub-firmware'
printf '%s\n' "$postinst_block" | grep -Fq '/etc/init.d/smartsafehub-maintenance enable' ||
	fail 'package postinst must force-enable smartsafehub-maintenance so scheduled reboots survive upgrades'
printf '%s\n' "$postinst_block" | grep -Fq '/etc/init.d/smartsafehub-health enable' ||
	fail 'package postinst must force-enable smartsafehub-health'
printf '%s\n' "$postinst_block" | grep -Fq '/etc/init.d/smartsafehub-health restart' ||
	fail 'package postinst must start or restart smartsafehub-health immediately after installation'
printf '%s\n' "$postinst_block" | grep -Fq '/etc/init.d/smartsafehub-license enable' ||
	fail 'package postinst must force-enable smartsafehub-license'
printf '%s\n' "$postinst_block" | grep -Fq '/etc/init.d/smartsafehub-license restart' ||
	fail 'package postinst must start or restart smartsafehub-license immediately after installation'
printf '%s\n' "$postinst_block" | grep -Fq 'smartsafehub.iptv.enabled' ||
	fail 'package postinst must reconcile igmpproxy enable state from SmartSafeHub IPTV config'
printf '%s\n' "$postinst_block" | grep -Fq '/etc/init.d/igmpproxy stop' ||
	fail 'package postinst must stop igmpproxy while IPTV is disabled'
printf '%s\n' "$postinst_block" | grep -Fq '/etc/init.d/igmpproxy disable' ||
	fail 'package postinst must disable igmpproxy while IPTV is disabled'
printf '%s\n' "$postinst_block" | grep -Fq 'rm -f /tmp/luci-indexcache' ||
	fail 'package postinst must clear the LuCI index cache after installing RPC/menu changes'
printf '%s\n' "$postinst_block" | grep -Fq '/bin/sh /usr/libexec/smartsafehub-rpcd-reconcile' ||
	fail 'package postinst must reconcile rpcd and verify the SmartSafeHub core ubus object after upgrade'
if printf '%s\n' "$postinst_block" | grep -Eq '/etc/init.d/rpcd (reload|restart)'; then
	fail 'package postinst must centralize rpcd reload/restart fallback in the tested reconcile helper'
fi
rpcd_reconcile="$ROOT_DIR/root/usr/libexec/smartsafehub-rpcd-reconcile"
grep -Fq '"$RPCD_INIT" reload' "$rpcd_reconcile" ||
	fail 'rpcd reconcile helper must try graceful reload first'
grep -Fq 'list "$RPC_OBJECT"' "$rpcd_reconcile" ||
	fail 'rpcd reconcile helper must verify the smartsafehub ubus object after reload'
grep -Fq '"$RPCD_INIT" restart' "$rpcd_reconcile" ||
	fail 'rpcd reconcile helper must restart rpcd when reload leaves the core object unavailable'
printf '%s\n' "$postinst_block" | grep -Fq 'uci -q delete smartsafehub.firmware.check_enabled' ||
	fail 'package postinst must remove the obsolete firmware check_enabled option on existing installs'
if printf '%s\n' "$postinst_block" | grep -Fq 'smartsafehub.updates.check_enabled'; then
	fail 'package postinst must not remove the management software check_enabled option'
fi
if printf '%s\n' "$postinst_block" | grep -Eq 'PKG_UPGRADE|smartsafehub-updater enabled'; then
	fail 'updater service enable must not depend on upgrade or previous enabled state'
fi
if printf '%s\n' "$postinst_block" | grep -Eq 'PKG_UPGRADE|smartsafehub-firmware enabled'; then
	fail 'firmware service enable must not depend on upgrade or previous enabled state'
fi
if printf '%s\n' "$postinst_block" | grep -Eq 'PKG_UPGRADE|smartsafehub-maintenance enabled'; then
	fail 'maintenance service enable must not depend on upgrade or previous enabled state'
fi
printf '%s\n' "$postinst_block" | grep -Fq '/bin/sh /usr/libexec/smartsafehub-root-entry --install --reconcile' ||
	fail 'package postinst must register the SmartSafeHub exact-root uHTTPd rewrite at runtime via /bin/sh'

prerm_block="$(awk '
	/^define Package\/luci-app-smartsafehub\/prerm$/ { in_block = 1 }
	in_block { print }
	in_block && /^endef$/ { exit }
' "$MAKEFILE")"
[ -n "$prerm_block" ] || fail 'package prerm hook is missing'
printf '%s\n' "$prerm_block" | grep -Fq '[ -z "$${IPKG_INSTROOT}" ]' ||
	fail 'package prerm must limit uHTTPd cleanup to runtime removal'
printf '%s\n' "$prerm_block" | grep -Fq '/bin/sh /usr/libexec/smartsafehub-root-entry --remove --reconcile' ||
	fail 'package prerm must unregister only the SmartSafeHub root rewrite via /bin/sh'

firmware_config_block="$(awk '
	/^config firmware / { in_block = 1 }
	in_block && /^config / && $0 !~ /^config firmware / { exit }
	in_block { print }
' "$CONFIG_FILE")"
if printf '%s\n' "$firmware_config_block" | grep -Fq 'check_enabled'; then
	fail 'firmware config must not expose check_enabled; firmware checks are always enabled'
fi
grep -Fq "config updates 'updates'" "$CONFIG_FILE" ||
	fail 'updates config section is missing'
grep -A5 -F "config updates 'updates'" "$CONFIG_FILE" | grep -Fq "option check_enabled '1'" ||
	fail 'management software check_enabled must remain user-configurable'
if grep -R -F 'smartsafehub.firmware.check_enabled' \
	"$ROOT_DIR/root/usr/libexec/smartsafehub-firmware" \
	"$ROOT_DIR/root/usr/share/rpcd/ucode/smartsafehub/firmware.uc" \
	"$ROOT_DIR/frontend/src/types/firmware.ts" >/dev/null 2>&1; then
	fail 'firmware-only code must not reference smartsafehub.firmware.check_enabled'
fi
if grep -Fq 'checkEnabled' "$ROOT_DIR/root/usr/share/rpcd/ucode/smartsafehub/firmware.uc" || \
	grep -Fq 'checkEnabled' "$ROOT_DIR/frontend/src/types/firmware.ts"; then
	fail 'firmware status contract must not expose checkEnabled'
fi

echo "PASS: package metadata, versions, conffile, forced service enable policy, firmware check policy and executable permissions are consistent"
