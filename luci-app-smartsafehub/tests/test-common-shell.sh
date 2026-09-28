#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
COMMON_LIB="$ROOT_DIR/root/usr/lib/smartsafehub/common.sh"

fail() {
	printf 'FAIL: %s\n' "$*" >&2
	exit 1
}

[ -r "$COMMON_LIB" ] || fail 'SmartSafeHub 공통 shell library가 존재해야 합니다.'
sh -n "$COMMON_LIB" || fail '공통 shell library가 POSIX shell 문법 검사를 통과해야 합니다.'

# shellcheck disable=SC1090
. "$COMMON_LIB"
command -v json_escape >/dev/null 2>&1 || fail '공통 library가 json_escape 함수를 제공해야 합니다.'
command -v ascii_upper >/dev/null 2>&1 || fail '공통 library가 ascii_upper 함수를 제공해야 합니다.'
command -v ascii_lower >/dev/null 2>&1 || fail '공통 library가 ascii_lower 함수를 제공해야 합니다.'

[ "$(ascii_upper 'pro-Ultimate_1')" = 'PRO-ULTIMATE_1' ] || fail 'ascii_upper는 라이선스 토큰을 명시적 ASCII 매핑으로 대문자화해야 합니다.'
[ "$(ascii_lower 'PRO-Ultimate_1')" = 'pro-ultimate_1' ] || fail 'ascii_lower는 라이선스 토큰을 명시적 ASCII 매핑으로 소문자화해야 합니다.'

actual="$(json_escape "$(printf 'path\\name"value\r\nnext')")"
expected='path\\name\"value  next'
[ "$actual" = "$expected" ] || fail "json_escape 결과가 올바르지 않습니다: $actual"
[ -z "$(json_escape '')" ] || fail 'json_escape는 빈 문자열을 그대로 처리해야 합니다.'

for file in \
	root/usr/libexec/smartsafehub-events \
	root/usr/libexec/smartsafehub-updater \
	root/usr/libexec/smartsafehub-firmware \
	root/usr/libexec/smartsafehub-health \
	root/usr/libexec/smartsafehub-license \
	root/usr/libexec/smartsafehub-activity-sync; do
	path="$ROOT_DIR/$file"
	grep -Fq '../lib/smartsafehub/common.sh' "$path" || fail "$file 이 공통 shell library를 사용해야 합니다."
	grep -Fq '. "$COMMON_LIB"' "$path" || fail "$file 이 공통 shell library를 source해야 합니다."
	if grep -Eq '^json_escape\(\)[[:space:]]*\{' "$path"; then
		fail "$file 에 json_escape 중복 구현이 남아 있으면 안 됩니다."
	fi
done

printf 'PASS: shared SmartSafeHub shell helpers and consumers are valid\n'
