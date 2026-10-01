#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
#
# The two "can this configuration be built at all" guards: Node.validate's
# TLS/server_name rule and bootstrap_addr's address check. See
# tests/ucode/test_build_guards.uc for why both used to be fatal rejections
# of configurations sing-box accepts.
#
# Neither rule reads UCI, so this stages the modules the two of them import
# and nothing else - no confdir, no fixture. That is what makes the test
# trustworthy on a target: `cursor(<dir>)` returns null there, so a UCI-based
# test would read an empty configuration and pass vacuously.
#
# Staging layout (mirrors production relative imports):
#   $WORK/scripts/homeproxy-pro.uc          - the real module, validate_data path rewritten
#   $WORK/scripts/config/model.uc       - Node / CREDENTIALS tables
#   $WORK/scripts/config/adapter.uc     - OutboundFactory
#   $WORK/scripts/generator/dns.uc      - build_dns
#   $WORK/scripts/generator/common.uc   - get_outbound / get_resolver
#   $WORK/scripts/parser/*.uc           - model.uc -> '../homeproxy-pro.uc', loader's mapping
#   $WORK/scripts/test_build_guards.uc  - the test
#
# Usage: sh tests/ucode/test_build_guards.sh <repo-root> [work-dir]

ROOT="${1:-.}"
WORK="${2:-/tmp/hp-build-guards-test}"

ROOT="$(cd "$ROOT" && pwd)"
FAILED=0

rm -rf "$WORK"
mkdir -p "$WORK/scripts/config" "$WORK/scripts/generator" "$WORK/scripts/parser"

# HP_VALIDATE_DATA lets a development host replace /sbin/validate_data (see
# tests/README.md); on a target the production path is kept.  The test itself
# never calls it - build_dns() parses the DNS address through parseURL() on
# its way to the block - but homeproxy-pro.uc has to load.
VALIDATE_DATA="${HP_VALIDATE_DATA:-/sbin/validate_data}"
sed -e "s#/sbin/validate_data#${VALIDATE_DATA}#" \
    "$ROOT/root/etc/homeproxy-pro/scripts/homeproxy-pro.uc" > "$WORK/scripts/homeproxy-pro.uc"

cp "$ROOT/root/etc/homeproxy-pro/scripts/config/model.uc"   "$WORK/scripts/config/"
cp "$ROOT/root/etc/homeproxy-pro/scripts/config/adapter.uc" "$WORK/scripts/config/"
cp "$ROOT/root/etc/homeproxy-pro/scripts/generator/dns.uc"    "$WORK/scripts/generator/"
cp "$ROOT/root/etc/homeproxy-pro/scripts/generator/common.uc" "$WORK/scripts/generator/"
cp "$ROOT/root/etc/homeproxy-pro/scripts/parser/"*.uc         "$WORK/scripts/parser/"
cp "$ROOT/tests/ucode/test_build_guards.uc"               "$WORK/scripts/"

if ( cd "$WORK/scripts" && ucode -L "$WORK/scripts" test_build_guards.uc ); then
	echo "PASS: build guards (TLS server_name, bootstrap address)"
else
	echo "FAIL: build guards (TLS server_name, bootstrap address)"
	FAILED=1
fi

exit $FAILED
