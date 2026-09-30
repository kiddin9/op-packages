#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
#
# runtime/china_ip_ruleset.uc: the text -> sing-box local rule-set generator
# that keeps the route side and the firewall deciding mainland China from one
# list.
#
# Why this has its own test: sing-box parses the generated file with
# netip.ParsePrefix(), which is strict, and one bad entry makes it reject the
# *whole* rule-set - taking the client's start with it ("initialize router:
# parse rule-set[0]: ... ParseAddr: IPv4 field has value >255", reproduced on
# the target).  The source list is downloaded and replaced unattended, so the
# failure would arrive on a router nobody is watching.  The cases below are the
# ones that decide whether that can happen: a malformed line must be skipped,
# the file must be replaced atomically (the running instance watches it), and
# an empty or unreadable source must fail rather than install an empty rule-set
# that silently matches nothing.
#
# Usage: sh tests/ucode/test_china_ip_ruleset.sh <repo-root> [workdir]

set -u

ROOT="$(cd "${1:-$(dirname "$0")/../..}" && pwd)"
WORK="${2:-/tmp/hp-china-ip-test}"

if ! command -v ucode > "/dev/null" 2>&1; then
	echo "NOT RUN: ucode is not on PATH."
	exit 2
fi

HELPER="$ROOT/root/etc/homeproxy-pro/scripts/runtime/china_ip_ruleset.uc"
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
	# generate <source> <destination>; stdout is "N prefixes", status 0/1
	ucode -S "$HELPER" "$1" "$2" 2>"/dev/null"
}

# --- fixtures ---------------------------------------------------------------

# A list shaped like the real one: comments, blank lines, valid IPv4 and IPv6,
# and five ways a line can be malformed.
cat > "$WORK/mixed.txt" <<'EOF'
# comment
; also a comment

1.1.8.0/24
2.2.2.2/32
10.0.0.0/8
2001:db8::/32
fe80::/10
999.1.1.1/24
01.2.3.4/24
1.1.8.0/33
fe80::/129
garbage
1.2.3.4
EOF

# Five survive: 1.1.8.0/24, 2.2.2.2/32, 10.0.0.0/8, 2001:db8::/32, fe80::/10.
expect "mixed list: only the valid entries survive" \
	"$(generate "$WORK/mixed.txt" "$WORK/mixed.json")" "5 prefixes"
expect "mixed list: the out-of-range octet is gone" \
	"$(grep -c '999\.1\.1\.1' "$WORK/mixed.json")" "0"
expect "mixed list: the leading-zero address is gone" \
	"$(grep -c '01\.2\.3\.4' "$WORK/mixed.json")" "0"
expect "mixed list: the /33 prefix is gone" \
	"$(grep -c '1\.1\.8\.0/33' "$WORK/mixed.json")" "0"
expect "mixed list: the /129 prefix is gone" \
	"$(grep -c 'fe80::/129' "$WORK/mixed.json")" "0"
expect "mixed list: a bare address is gone" \
	"$(grep -c '"1\.2\.3\.4"' "$WORK/mixed.json")" "0"
expect "mixed list: the valid IPv4 entries stay" \
	"$(grep -c '1\.1\.8\.0/24\|2\.2\.2\.2/32\|10\.0\.0\.0/8' "$WORK/mixed.json")" "3"
expect "mixed list: the valid IPv6 entry stays" \
	"$(grep -c '2001:db8::/32' "$WORK/mixed.json")" "1"

# The rule-set has to be one `ip_cidr` array: one netipx.IPSet on the sing-box
# side, not N rules to walk per packet.
expect "output is a single ip_cidr rule" \
	"$(grep -c '"ip_cidr"' "$WORK/mixed.json")" "1"
expect "output carries a version" \
	"$(grep -c '"version": 3' "$WORK/mixed.json")" "1"

# --- the real bundled list --------------------------------------------------

# The list this ships with is what the firewall renders its nft set from; a
# generator that mangles it would break both sides at once.
expect "the bundled china_ip4.txt generates" \
	"$(generate "$ROOT/root/etc/homeproxy-pro/resources/china_ip4.txt" "$WORK/real.json")" "4068 prefixes"
# 8.152.0.0/13 is the range geoip-cn.srs does *not* carry, and the one that
# made segmentfault.com and ctrip.com resolve into the proxy path.
expect "the bundled list carries 8.152.0.0/13" \
	"$(grep -c '8\.152\.0\.0/13' "$WORK/real.json")" "1"

# --- failure paths ----------------------------------------------------------

# An empty source must not install an empty rule-set: the caller would then be
# running a split that matches nothing while looking like it worked.
: > "$WORK/empty.txt"
expect "empty source produces no file" "$(generate "$WORK/empty.txt" "$WORK/empty.json")" ""
ucode -S "$HELPER" "$WORK/empty.txt" "$WORK/empty.json" >/dev/null 2>&1
expect "empty source exits non-zero" "$?" "1"
expect "empty source wrote nothing" "$(test -e "$WORK/empty.json" && echo yes || echo no)" "no"

ucode -S "$HELPER" "$WORK/does-not-exist.txt" "$WORK/missing.json" >/dev/null 2>&1
expect "unreadable source exits non-zero" "$?" "1"
expect "unreadable source wrote nothing" "$(test -e "$WORK/missing.json" && echo yes || echo no)" "no"

ucode -S "$HELPER" >/dev/null 2>&1
expect "no arguments exits non-zero" "$?" "1"

# --- atomicity --------------------------------------------------------------

# The running instance watches this path with fswatch, so a partial write would
# be read as a broken rule-set.  The generator writes a sibling temp file and
# renames it, which is why no `*.tmp` may survive a successful run.
rm -f "$WORK/real.json" "$WORK/real.json.tmp"
generate "$ROOT/root/etc/homeproxy-pro/resources/china_ip4.txt" "$WORK/real.json" >"/dev/null"
expect "a successful run leaves no temp file" \
	"$(ls "$WORK"/real.json.tmp 2>/dev/null | wc -l)" "0"
expect "a successful run leaves the rule-set" \
	"$(test -s "$WORK/real.json" && echo yes || echo no)" "yes"

# A failed run must not damage an existing rule-set either: the destination is
# only touched by the rename.
cp "$WORK/real.json" "$WORK/keep.json"
ucode -S "$HELPER" "$WORK/empty.txt" "$WORK/keep.json" >/dev/null 2>&1
expect "a failed run leaves the previous rule-set in place" \
	"$(test -s "$WORK/keep.json" && echo yes || echo no)" "yes"
expect "a failed run leaves no temp file behind" \
	"$(ls "$WORK"/keep.json.tmp 2>/dev/null | wc -l)" "0"

echo
echo "$CHECKS checks, $FAILURES failures"
[ "$FAILED" -eq 0 ] && echo "CHINA IP RULESET TESTS PASSED"
exit "$FAILED"
