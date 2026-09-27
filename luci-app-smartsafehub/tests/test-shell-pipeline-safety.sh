#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
SELF="$ROOT_DIR/tests/test-shell-pipeline-safety.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT INT TERM

fail() {
	printf 'FAIL: %s\n' "$*" >&2
	exit 1
}

# sed가 많은 출력을 생성하는 동안 downstream 명령이 입력을 조기에 닫으면
# GNU sed가 stderr에 "couldn't flush stdout: Broken pipe"를 남길 수 있습니다.
# 테스트 계약에서는 sed 뒤에 조기 종료 consumer를 두지 않고, grep은 -q 대신
# stdout redirection을 사용하며 첫 값 추출은 awk 등 단일 프로세스로 처리합니다.
find_unsafe_sed_pipeline() {
	awk '
		/^[[:space:]]*#/ { next }
		{
			line = $0
			if (line !~ /sed[[:space:]]/) next
			if (line ~ /[|][[:space:]]*head([[:space:]]|$)/) {
				print FNR ":" line
				next
			}
			if (line !~ /[|][[:space:]]*grep[[:space:]]/) next

			after = line
			sub(/^.*[|][[:space:]]*grep[[:space:]]*/, "", after)
			n = split(after, fields, /[[:space:]]+/)
			for (i = 1; i <= n; i++) {
				option = fields[i]
				if (option !~ /^-/) break
				if (option == "--quiet" || option ~ /^-[A-Za-z]*q[A-Za-z]*$/) {
					print FNR ":" line
					break
				}
			}
		}
	' "$1"
}

# 탐지기 자체도 회귀 테스트합니다. 위험 패턴은 반드시 잡고 안전한 대안은
# 허용해야 이후 정규식 변경으로 보호 장치가 무력화되지 않습니다.
cat > "$TMP/unsafe.sh" <<'EOF'
sed -n '/start/,/end/p' "$FILE" | grep -Fq 'needle'
sed -n 's/^PKG_VERSION:=//p' "$FILE" | head -n1
sed -n '/start/,/end/p' "$FILE" | grep -F --quiet 'needle'
EOF
unsafe_fixture="$(find_unsafe_sed_pipeline "$TMP/unsafe.sh")"
[ "$(printf '%s\n' "$unsafe_fixture" | awk 'NF { count++ } END { print count + 0 }')" -eq 3 ] || \
	fail 'pipeline safety detector must catch grep -q, grep --quiet and head consumers after sed'

cat > "$TMP/safe.sh" <<'EOF'
sed -n '/start/,/end/p' "$FILE" | grep -F 'needle' >/dev/null
awk -F ':=' '$1 == "PKG_VERSION" { print $2; exit }' "$FILE"
grep -Fq 'needle' "$FILE"
EOF
safe_fixture="$(find_unsafe_sed_pipeline "$TMP/safe.sh")"
[ -z "$safe_fixture" ] || fail "pipeline safety detector rejected safe patterns: $safe_fixture"

violations=''
for script in "$ROOT_DIR"/tests/test-*.sh; do
	[ "$script" = "$SELF" ] && continue
	matches="$(find_unsafe_sed_pipeline "$script")"
	[ -z "$matches" ] && continue
	while IFS= read -r match; do
		[ -n "$match" ] || continue
		violations="${violations}${script#$ROOT_DIR/}:$match
"
	done <<EOF
$matches
EOF
done

[ -z "$violations" ] || fail "sed output must not feed early-exit consumers in contract tests:\n$violations"

printf 'PASS: shell contract tests avoid sed pipelines that can emit broken-pipe stderr\n'
