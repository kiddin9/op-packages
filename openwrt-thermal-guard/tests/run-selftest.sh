#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
# Runs the decision logic against its test cases without touching any hardware.
# Everything the daemon would write goes to a scratch directory.

set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

STATE_DIR="$tmp/state" \
STATUS_FILE="$tmp/status" \
LIB_DIR="$root/thermal-guard/files/usr/share/thermal-guard" \
FIXTURE_DIR="$root/tests/fixtures" \
	sh "$root/thermal-guard/files/usr/sbin/thermal-guard" selftest
