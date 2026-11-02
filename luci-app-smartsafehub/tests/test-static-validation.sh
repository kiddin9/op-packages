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

# Discover shell tests and shipped router entry points automatically.
# A new test or daemon is validated without editing this script.
sh "$ROOT_DIR/tools/check_shell_syntax.sh" "$ROOT_DIR" || \
    fail 'shell syntax validation failed'

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
