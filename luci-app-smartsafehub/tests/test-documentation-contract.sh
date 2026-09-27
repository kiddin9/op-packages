#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
README="$ROOT_DIR/README.md"
FEATURES="$ROOT_DIR/docs/FEATURES.md"
DEVELOPMENT="$ROOT_DIR/docs/DEVELOPMENT.md"
OPERATIONS="$ROOT_DIR/docs/OPERATIONS.md"

fail() {
	printf 'FAIL: %s\n' "$*" >&2
	exit 1
}

for file in "$README" "$FEATURES" "$DEVELOPMENT" "$OPERATIONS"; do
	[ -f "$file" ] || fail "missing documentation file: ${file#$ROOT_DIR/}"
done

readme_lines="$(wc -l < "$README" | tr -d '[:space:]')"
[ "$readme_lines" -le 160 ] || fail "README must stay concise (current: $readme_lines lines)"

grep -Fq '## 패키지 버전' "$README" || fail 'README must keep the package version section'
grep -Fq '## 라이선스' "$README" || fail 'README must keep the license section'
grep -Fq '[GPL-3.0-or-later](LICENSE)' "$README" || fail 'README must link to the GPL-3.0-or-later license'

for link in \
	'docs/FEATURES.md' \
	'docs/ARCHITECTURE.md' \
	'docs/DEVELOPMENT.md' \
	'docs/OPERATIONS.md' \
	'docs/STATISTICS_TESTING.md'; do
	grep -Fq "$link" "$README" || fail "README must link to $link"
done

if grep -Eq '^## (ucode 컴파일 검사|배포 전 체크리스트|프런트엔드 캐시 문제)$' "$README"; then
	fail 'implementation and troubleshooting details must stay in docs instead of README'
fi

grep -Fq '## 장치 대시보드' "$FEATURES" || fail 'FEATURES.md must contain detailed feature documentation'
grep -Fq '## OpenWrt 패키지 빌드' "$DEVELOPMENT" || fail 'DEVELOPMENT.md must contain package build documentation'
grep -Fq '## ucode 컴파일 검사' "$DEVELOPMENT" || fail 'DEVELOPMENT.md must contain ucode validation documentation'
grep -Fq '## 설치 후 확인' "$OPERATIONS" || fail 'OPERATIONS.md must contain post-install checks'
grep -Fq '### SmartSafeHub 라이선스 lifecycle' "$OPERATIONS" || fail 'OPERATIONS.md must contain license lifecycle documentation'

printf 'PASS: README summary and detailed documentation split are consistent\n'
