#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
#
# Direct unit tests for the firewall field validators
# (root/etc/homeproxy-pro/scripts/firewall_utils.uc).
#
# Why a separate file rather than extending test_firewall_template.sh:
# the rendering test needs the device-only `fw4` ucode module, so on a
# development host it only runs the source-level glue precondition; it
# cannot exercise the validators themselves.  The validators are pure
# functions, so a self-contained ucode test runs anywhere ucode runs.
# Together they are the report's H1: the renderer cannot regress
# silently because the validators are independently pinned here.
#
# Usage: sh tests/ucode/test_firewall_validators.sh <repo-root> [work-dir]

ROOT="${1:-.}"
WORK="${2:-/tmp/hp-firewall-validators-test}"

ROOT="$(cd "$ROOT" && pwd)"

if ! command -v ucode > "/dev/null" 2>&1; then
	echo "NOT RUN: ucode is not on PATH."
	echo "         Build the testbed toolchain first (tests/toolchain/build-ucode-linux.sh)."
	exit 2
fi

rm -rf "$WORK"
mkdir -p "$WORK"

# The validators import `isEmpty` from homeproxy-pro.uc. Stage a copy that
# just exports it - the validators under test are the only thing this
# process exercises, so pulling in the full homeproxy-pro.uc (with its
# validate_data / popen / luci.* imports) would break the unit test on
# a host that lacks /sbin/validate_data.
cat > "$WORK/homeproxy-pro.uc" <<'HPEOF'
export function isEmpty(res) {
	return !res || res === 'nil' || (type(res) in ['array', 'object'] && length(res) === 0);
};
HPEOF

cp "$ROOT/root/etc/homeproxy-pro/scripts/firewall_utils.uc" "$WORK/firewall_utils.uc"
cp "$ROOT/tests/ucode/test_firewall_validators.uc"     "$WORK/test_firewall_validators.uc"

if ( cd "$WORK" && ucode test_firewall_validators.uc ); then
	echo "PASS: firewall field validators drop invalid entries"
	exit 0
else
	echo "FAIL: firewall field validators"
	exit 1
fi
