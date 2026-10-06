#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
#
# Unit tests for udp_transport_verdict() in homeproxy-pro.uc.
#
# The judgement decides whether QUIC is rejected in the fw4 ruleset, so every
# branch is pinned: each of the four main_udp_node values, and each hop of
# the resolution ('same' -> the main node, 'urltest' -> every member, a named
# section, and 'nil').
#
# The interesting case is 'same' with a TCP-transport main node - the shape
# this function exists for. It is invisible in the UCI value alone: both
# fields read perfectly reasonable.
#
# A real UCI cursor is required (the function reads configuration), so the
# runner stages a sandboxed config dir and passes the cursor in. cursor(dir)
# reads <dir>/<name> directly, NOT <dir>/config/<name>.
#
# Each case re-seeds the sandbox from inside the .uc driver through the
# cursor's own API and re-reads with a fresh cursor, so libuci's change
# tracking cannot carry one case's options into the next.
#
# Usage: sh tests/ucode/test_udp_transport.sh <repo-root> [work-dir]

ROOT="${1:-.}"
WORK="${2:-/tmp/hp-udp-transport-test}"

ROOT="$(cd "$ROOT" && pwd)"
FAILED=0

SANDBOX="$WORK/sandbox"
STAGE="$WORK/scripts"

rm -rf "$WORK"
mkdir -p "$SANDBOX" "$STAGE"

if ! command -v ucode > "/dev/null" 2>&1; then
	echo "NOT RUN: ucode is not on PATH."
	exit 2
fi

# /sbin/validate_data does not exist off-target and production homeproxy-pro.uc
# shells out to it from validation(); the driver never calls validation(), but
# the module still has to load. tests/ucode/test_mock_sync.sh rewrites the
# same literal for the same reason.
VALIDATE_DATA="${HP_VALIDATE_DATA:-/sbin/validate_data}"
if [ ! -x "$VALIDATE_DATA" ] && [ -x "$ROOT/tests/toolchain/validate-data.sh" ]; then
	VALIDATE_DATA="$ROOT/tests/toolchain/validate-data.sh"
fi

sed -e "s#/sbin/validate_data#$VALIDATE_DATA#" \
	"$ROOT/root/etc/homeproxy-pro/scripts/homeproxy-pro.uc" > "$STAGE/homeproxy-pro.uc"
cp "$ROOT/tests/ucode/test_udp_transport.uc" "$STAGE/test_udp_transport.uc"

cd "$STAGE" || exit 1
if HP_T_SANDBOX="$SANDBOX" ucode test_udp_transport.uc; then
	echo "PASS: udp_transport_verdict"
else
	echo "FAIL: udp_transport_verdict"
	FAILED=1
fi

exit "$FAILED"