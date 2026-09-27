#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
#
# resource_blob_sha.uc: the git blob id helper the resource updater verifies
# downloads with.
#
# The check it feeds is only as good as this digest, so the expected values
# here are git's own: `git hash-object` on the same bytes, which is the oracle
# the helper has to reproduce (sha1("blob <len>\0" + content)). The fixtures
# are chosen to cover the two things an implementation gets wrong quietly:
# the empty file (a real blob id, not "no digest") and content whose byte
# length differs from its character count.
#
# Usage: sh tests/ucode/test_resource_blob_sha.sh <repo-root> [workdir]

set -u

ROOT="$(cd "${1:-$(dirname "$0")/../..}" && pwd)"
WORK="${2:-/tmp/hp-blob-sha-test}"

if ! command -v ucode > "/dev/null" 2>&1; then
	echo "NOT RUN: ucode is not on PATH."
	exit 2
fi

HELPER="$ROOT/root/etc/homeproxy/scripts/resource_blob_sha.uc"
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

blob_sha() {
	ucode -S "$HELPER" "$1" 2>"/dev/null"
}

# --- fixtures ---------------------------------------------------------------
: > "$WORK/empty"
printf 'abc' > "$WORK/abc"
printf '中文abc\n' > "$WORK/utf8"
printf 'line one\nline two\n' > "$WORK/two-lines"

# Expected values are git's own, printed at the end of this script so they can
# be re-derived with `git hash-object <file>` after any change to the helper's
# contract. They are literals rather than a live `git hash-object` call because
# the target this runs on has no git - and a test that silently loses its
# oracle on the device is worse than a literal with this comment on it.
expect "empty file"        "$(blob_sha "$WORK/empty")"     "e69de29bb2d1d6434b8b29ae775ad8c2e48c5391"
expect "abc"               "$(blob_sha "$WORK/abc")"       "f2ba8f84ab5c1bce84a7b441cb1959cfc7093b7f"
expect "two lines"         "$(blob_sha "$WORK/two-lines")" "e5c5c5583f49a34e86ce622b59363df99e09d4c6"
expect "multibyte content" "$(blob_sha "$WORK/utf8")"      "eadc1642bc94f8074dc8e3b1be0e3f0885d3f912"

# The helper must not invent a digest for something it cannot read: the
# updater treats an empty answer as "cannot verify" and refuses, so a
# non-empty answer here would turn an unreadable file into a passing check.
expect "missing file produces no digest" "$(blob_sha "$WORK/does-not-exist")" ""
ucode -S "$HELPER" >/dev/null 2>&1
expect "no argument exits non-zero" "$?" "1"
ucode -S "$HELPER" "$WORK/does-not-exist" >/dev/null 2>&1
expect "unreadable file exits non-zero" "$?" "1"

# Two different contents must not collide (the trivial "always returns a
# constant" regression).
if [ -n "$(blob_sha "$WORK/abc")" ] && [ "$(blob_sha "$WORK/abc")" != "$(blob_sha "$WORK/two-lines")" ]; then
	CHECKS=$((CHECKS + 1))
	echo "PASS: different contents produce different digests"
else
	CHECKS=$((CHECKS + 1))
	FAILED=1
	FAILURES=$((FAILURES + 1))
	echo "FAIL: different contents produced the same digest"
fi

# The repository's own resource files are the real inputs: verify them against
# git when the host has it (the CI runner and a developer machine do; a router
# does not). This is the check that would notice the helper drifting from git's
# format on a file it actually has to hash.
if command -v git > "/dev/null" 2>&1 && [ -d "$ROOT/.git" ]; then
	for f in "root/etc/homeproxy/resources/china_ip4.txt" \
	         "root/etc/homeproxy/resources/gfw_list.txt"; do
		[ -f "$ROOT/$f" ] || continue
		expect "matches git hash-object: $(basename "$f")" \
			"$(blob_sha "$ROOT/$f")" "$(git hash-object "$ROOT/$f")"
	done
fi

printf '%d checks, %d failures\n' "$CHECKS" "$FAILURES"
if [ "$FAILED" != "0" ]; then
	echo "BLOB SHA TESTS FAILED"
	exit 1
fi

echo "BLOB SHA TESTS PASSED"
exit 0
