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

actual="$(json_escape "$(printf 'path\\name"value\r\nnext')")"
expected='path\\name\"value  next'
[ "$actual" = "$expected" ] || fail "json_escape 결과가 올바르지 않습니다: $actual"
[ -z "$(json_escape '')" ] || fail 'json_escape는 빈 문자열을 그대로 처리해야 합니다.'

for file in \
	root/usr/libexec/smartsafehub-events \
	root/usr/libexec/smartsafehub-updater \
	root/usr/libexec/smartsafehub-firmware \
	root/usr/libexec/smartsafehub-health \
	root/usr/libexec/smartsafehub-license; do
	path="$ROOT_DIR/$file"
	grep -Fq '../lib/smartsafehub/common.sh' "$path" || fail "$file 이 공통 shell library를 사용해야 합니다."
	grep -Fq '. "$COMMON_LIB"' "$path" || fail "$file 이 공통 shell library를 source해야 합니다."
	if grep -Eq '^json_escape\(\)[[:space:]]*\{' "$path"; then
		fail "$file 에 json_escape 중복 구현이 남아 있으면 안 됩니다."
	fi
done

printf 'PASS: shared SmartSafeHub json_escape helper and consumers are valid\n'
