#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"

fail() {
	printf 'FAIL: %s\n' "$*" >&2
	exit 1
}

command -v jq >/dev/null 2>&1 || fail 'jq is required to validate JSON files'

APP_STYLE="$ROOT_DIR/frontend/src/styles/app.css"
[ -f "$APP_STYLE" ] || fail 'missing frontend application stylesheet'

[ "$(grep -Fc ':host {' "$APP_STYLE")" -eq 1 ] || \
	fail 'app.css must keep host-level defaults in one rule'
if grep -Fq '.ssh-app > header,' "$APP_STYLE"; then
	fail 'app.css must not keep the obsolete direct-child header/main rule'
fi
if grep -Fq ".ssh-app[data-theme='dark'] [class~='bg-white']," "$APP_STYLE"; then
	fail 'dark bg-white/95 must not inherit a value that is immediately overridden'
fi
if grep -Fq ".ssh-app[data-theme='dark'] [class~='bg-slate-50']," "$APP_STYLE"; then
	fail 'dark bg-slate-50/70 must not inherit a value that is immediately overridden'
fi
[ "$(grep -Fc '  .ssh-safeshield-upgrade-action {' "$APP_STYLE")" -eq 1 ] || \
	fail 'mobile SafeShield upgrade action styling must be defined once'
if grep -Fq '  .ssh-safeshield-license-summary,' "$APP_STYLE"; then
	fail 'mobile license styles must not duplicate SafeShield upgrade-card alignment'
fi

for script in \
	root/etc/init.d/smartsafehub-events \
	root/etc/init.d/smartsafehub-updater \
	root/etc/init.d/smartsafehub-firmware \
	root/etc/init.d/smartsafehub-maintenance \
	root/etc/init.d/smartsafehub-health \
	root/etc/init.d/smartsafehub-license \
	root/usr/lib/smartsafehub/common.sh \
	root/usr/libexec/smartsafehub-events \
	root/usr/libexec/smartsafehub-updater \
	root/usr/libexec/smartsafehub-firmware \
	root/usr/libexec/smartsafehub-maintenance \
	root/usr/libexec/smartsafehub-health \
	root/usr/libexec/smartsafehub-license \
	root/usr/libexec/smartsafehub-backup \
	spec/contracts_spec.sh \
	tests/test-static-validation.sh \
	tests/test-shell-pipeline-safety.sh \
	tests/test-package-contract.sh \
	tests/test-events.sh \
	tests/test-activity-ui-contract.sh \
	tests/test-activity-cloud-sync.sh \
	tests/test-common-shell.sh \
	tests/test-navigation-contract.sh \
	tests/test-tailwind-shadow-dom.sh \
	tests/test-document-ui-contract.sh \
	tests/test-login-ui-contract.sh \
	tests/test-initial-password-setup.sh \
	tests/test-dashboard-ui-contract.sh \
	tests/test-network-input-contract.sh \
	tests/test-lan-settings.sh \
	tests/test-lan-uci-runtime.sh \
	tests/test-iptv.sh \
	tests/test-update-ui-contract.sh \
	tests/test-reload-safety.sh \
	tests/test-settings-ui-contract.sh \
	tests/test-system-time-contract.sh \
	tests/test-scheduled-reboot.sh \
	tests/test-health.sh \
	tests/test-license.sh \
	tests/test-backup-restore.sh \
	tests/test-rpc-contract.sh \
	tests/test-rules-ui-contract.sh \
	tests/test-safeshield-page-contract.sh \
	tests/test-statistics-ui-contract.sh \
	tests/test-ucode-syntax.sh \
	tests/test-ucode-imports.sh \
	tests/test-updater.sh \
	tests/test-firmware-updater.sh; do
	sh -n "$ROOT_DIR/$script"
done

# 실제 ucode 컴파일은 test-ucode-syntax.sh가 OpenWrt 전용 모듈 stub과
# target module search path를 구성한 뒤 단일 진입점으로 수행해야 합니다.
# 기능별 계약 테스트가 raw `ucode -c`를 추가하면 host CI에서는 ubus/uci/fs
# import를 찾지 못해 소스 문법과 무관한 false failure가 발생할 수 있습니다.
RAW_UCODE_COMPILE_TESTS="$(
	find "$ROOT_DIR/tests" -type f -name 'test-*.sh' \
		! -name 'test-ucode-syntax.sh' \
		! -name 'test-static-validation.sh' \
		-exec grep -l -E 'ucode[[:space:]].*-c' {} + 2>/dev/null || true
)"
[ -z "$RAW_UCODE_COMPILE_TESTS" ] || \
	fail "ucode 실제 컴파일은 tests/test-ucode-syntax.sh에서만 수행해야 합니다: $RAW_UCODE_COMPILE_TESTS"

find \
	"$ROOT_DIR/root/usr/share/rpcd/acl.d" \
	"$ROOT_DIR/root/usr/share/luci/menu.d" \
	-type f -name '*.json' -print |
	sort |
	while IFS= read -r json_file; do
		jq empty "$json_file"
	done

printf 'PASS: shell syntax and JSON files are valid\n'
