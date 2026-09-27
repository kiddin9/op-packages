#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
#
# Local stand-in for OpenWrt's /sbin/validate_data.
#
# homeproxy.uc validates hostnames, addresses and ports by shelling out to
# validate_data, which only exists on an OpenWrt target; without it the
# generators cannot run on a development host at all. This wrapper reproduces
# the contract the caller relies on -- exit 0 means valid, non-zero means
# invalid -- and delegates the checks themselves to the test double that the
# parser unit tests already use, so the validation logic stays in one place
# instead of growing a third copy.
#
# PINNED FIXTURE, NOT AN EQUIVALENT.
# Its `validation()` is an approximation of the real /sbin/validate_data and is
# meant to stay that way; do not "fix" a difference by making it match. What it
# covers: port, ip4addr, ip6addr, hostname, host. What the real one covers and
# this does not: macaddr, network, ip4prefix/ip6prefix, ipset, uinteger, range,
# and the rest of OpenWrt's list. Anything that needs those must run on a
# target - tests/ucode/run.sh exports HP_VALIDATE_DATA only off-target, and a
# device keeps the production binary. The differences are deliberate, which is
# why tests/ucode/test_mock_sync.sh compares the copied *string helpers* with
# production but explicitly excludes validation().
#
# Not shipped in the package: it only exists for the local testbed, see
# tests/README.md.

set -eu

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"

datatype="${1:-}"
data="${2:-}"

[ -n "$datatype" ] && [ -n "$data" ] || exit 1

# The two values travel in the environment rather than being interpolated into
# the ucode source: a hostname containing a single quote used to close the
# string literal and turn the rest of the value into code, so this wrapper
# would report "invalid" for a valid name (and could in principle be made to
# run something).
HP_VD_TYPE="$datatype" HP_VD_DATA="$data" exec ucode -L "$HERE" -e '
	import { validation } from "'"$REPO"'/tests/ucode/mocks/homeproxy.uc";
	exit(validation(getenv("HP_VD_TYPE"), getenv("HP_VD_DATA")) === true ? 0 : 1);
'
