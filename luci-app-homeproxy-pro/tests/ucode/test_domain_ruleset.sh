#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
#
# runtime/domain_ruleset.uc: the text -> sing-box local rule-set generator for
# the DNS half of the China split.
#
# Why this has its own test: it is the only thing standing between a downloaded
# host-name list and a DNS split.  sing-box rejects a rule-set containing an
# entry it cannot parse, and it rejects the WHOLE file when it does - so one bad
# line in a list that is replaced unattended, on a router nobody is watching,
# takes the resolver's half of the split down with it.  The cases below are the
# ones that decide whether that can happen.
#
# Three properties matter beyond "it produces a file":
#
#   - the entry has to be a SUFFIX.  `domain` would match only the name itself
#     and quietly stop matching www.<domain> for the whole list, which is a
#     split that looks configured and behaves as if the list were empty.
#   - the host-name check has to be in-process.  validation() in homeproxy-pro.uc
#     shells out to /sbin/validate_data once per call, and this list is 111k
#     lines - that is 111k process spawns, which is not a test that passes, it
#     is a test that never finishes.
#   - an empty or all-malformed source must fail rather than install a
#     rule-set that matches nothing.
#
# Usage: sh tests/ucode/test_domain_ruleset.sh <repo-root> [workdir]

set -u

ROOT="$(cd "${1:-$(dirname "$0")/../..}" && pwd)"
WORK="${2:-/tmp/hp-domain-test}"

if ! command -v ucode > "/dev/null" 2>&1; then
	echo "NOT RUN: ucode is not on PATH."
	exit 2
fi

HELPER="$ROOT/root/etc/homeproxy-pro/scripts/runtime/domain_ruleset.uc"
rm -rf "$WORK"
mkdir -p "$WORK"

FAILED=0
CHECKS=0
FAILURES=0

expect() {
	# expect <name> <actual> <expected>
	CHECKS=$((CHECKS + 1))
	if [ "$2" = "$3" ]; then
		echo "PASS: $1"
	else
		echo "FAIL: $1 (expected '$3', got '$2')"
		FAILED=1
		FAILURES=$((FAILURES + 1))
	fi
}

generate() {
	# generate <source> <destination>; stdout is "N domain suffixes"
	ucode -S "$HELPER" "$1" "$2" 2>"/dev/null"
}

# --- fixtures ---------------------------------------------------------------

# A list shaped like the real one: comments, blank lines, plain two-label
# names, the single-label and deep forms that appear in a real suffix list, and
# the ways a line can be malformed.
#
# Every malformed entry below is named so that its own assertion's grep pattern
# MATCHES it.  That is the point: an assertion whose pattern cannot match the
# entry it is about stays green whether or not the entry is rejected, which is
# a guard pointing at the wrong side.  The first draft of this fixture had
# "trailing-hyphen.com" and "trailing.dot.com" - both perfectly valid names -
# while the assertions claimed a trailing hyphen and a trailing dot, and both
# assertions were vacuous.
cat > "$WORK/mixed.txt" <<'EOF'
# comment
; also a comment

taobao.com
163.com
0.zone
a.b.c.example.cn
xn--fiqs8s.com
under_score.com
-leading-hyphen.com
trailinghyphen-.com
double..dot.com
.dotted.com
trailingdot.com.
with space.com
http://scheme.com
192.168.1.1
EOF

# Five survive: taobao.com, 163.com, 0.zone, a.b.c.example.cn,
# xn--fiqs8s.com.  Everything else in the fixture is one malformation.
expect "mixed list: only the valid entries survive" \
	"$(generate "$WORK/mixed.txt" "$WORK/mixed.json")" "5 domain suffixes"
expect "mixed list: the underscore name is gone" \
	"$(grep -c 'under_score' "$WORK/mixed.json")" "0"
expect "mixed list: the leading-hyphen label is gone" \
	"$(grep -c 'leading-hyphen' "$WORK/mixed.json")" "0"
expect "mixed list: the trailing-hyphen label is gone" \
	"$(grep -c 'trailinghyphen-' "$WORK/mixed.json")" "0"
expect "mixed list: the doubled dot is gone" \
	"$(grep -c 'double\.\.dot' "$WORK/mixed.json")" "0"
expect "mixed list: the leading dot is gone" \
	"$(grep -c '"\.dotted\.com"' "$WORK/mixed.json")" "0"
expect "mixed list: the trailing dot is gone" \
	"$(grep -c '"trailingdot\.com\."' "$WORK/mixed.json")" "0"
expect "mixed list: the name with a space is gone" \
	"$(grep -c 'with space' "$WORK/mixed.json")" "0"
expect "mixed list: the URL is gone" \
	"$(grep -c 'scheme.com' "$WORK/mixed.json")" "0"
expect "mixed list: a bare address is not treated as a domain" \
	"$(grep -c '192\.168\.1\.1' "$WORK/mixed.json")" "0"
expect "mixed list: the plain names stay" \
	"$(grep -c 'taobao\.com\|163\.com\|0\.zone\|a\.b\.c\.example\.cn\|xn--fiqs8s\.com' "$WORK/mixed.json")" "5"

# The single most consequential property: suffix, not exact.
expect "output is a single domain_suffix rule" \
	"$(grep -c '"domain_suffix"' "$WORK/mixed.json")" "1"
expect "output does not use exact domain matching" \
	"$(grep -c '"domain":' "$WORK/mixed.json")" "0"
expect "output carries a version" \
	"$(grep -c '"version": 3' "$WORK/mixed.json")" "1"

# --- the real bundled list --------------------------------------------------

# This is the list the DNS split runs on.  A generator that mangles it would
# send every mainland lookup to the proxy resolver while looking healthy.
if [ -f "$ROOT/root/etc/homeproxy-pro/resources/china_list.txt" ]; then
	expect "the bundled china_list.txt generates" \
		"$(generate "$ROOT/root/etc/homeproxy-pro/resources/china_list.txt" "$WORK/real.json")" \
		"$(wc -l < "$ROOT/root/etc/homeproxy-pro/resources/china_list.txt" | tr -d ' ') domain suffixes"
	expect "the bundled list is emitted as suffixes, not exact names" \
		"$(grep -c '"domain_suffix"' "$WORK/real.json")" "1"
	expect "the bundled list emits no exact-domain rules" \
		"$(grep -c '"domain":' "$WORK/real.json")" "0"
else
	echo "SKIP: the bundled china_list.txt is not in the tree."
fi

# --- failure paths ----------------------------------------------------------

# An empty source must not install an empty rule-set: the DNS split would then
# match nothing and every mainland lookup would go to the proxy resolver, with
# nothing in the log saying so.
: > "$WORK/empty.txt"
expect "empty source produces no file" "$(generate "$WORK/empty.txt" "$WORK/empty.json")" ""
ucode -S "$HELPER" "$WORK/empty.txt" "$WORK/empty.json" >/dev/null 2>&1
expect "empty source exits non-zero" "$?" "1"

# A source that is entirely malformed is the same case reached differently.
printf 'http://a\nhttp://b\nunder_score\n' > "$WORK/junk.txt"
expect "all-malformed source produces no file" "$(generate "$WORK/junk.txt" "$WORK/junk.json")" ""
ucode -S "$HELPER" "$WORK/junk.txt" "$WORK/junk.json" >/dev/null 2>&1
expect "all-malformed source exits non-zero" "$?" "1"

# A missing source is a caller error, not an empty list.
expect "missing source exits non-zero" \
	"$(ucode -S "$HELPER" "$WORK/no-such-file.txt" "$WORK/none.json" >/dev/null 2>&1; echo $?)" "1"

# --- atomicity --------------------------------------------------------------

# sing-box watches this file and reloads it in place, so a partially written
# one is read by a running instance.  The destination has to appear whole or
# not at all.
cat > "$WORK/atomic.txt" <<'EOF'
one.example
two.example
three.example
EOF
generate "$WORK/atomic.txt" "$WORK/atomic.json" >/dev/null
expect "the destination is complete after a run" \
	"$(grep -c 'one\.example\|two\.example\|three\.example' "$WORK/atomic.json")" "3"
expect "no temporary file is left behind" \
	"$(ls "$WORK" | grep -c 'atomic\.json\.tmp')" "0"

# --- summary ----------------------------------------------------------------

echo "  ($CHECKS checks, $FAILURES failures)"
exit "$FAILED"
