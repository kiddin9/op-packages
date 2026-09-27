#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
#
# Stage A1.1 skeleton test: the production Config Loader (root/etc/homeproxy/
# scripts/config/loader.uc) must read the UCI fixture and produce a
# HomeProxyConfig whose general / infra / nodes sub-objects match the
# expected values. The other five sub-objects (dns, routing, endpoints,
# access_control, server) are intentionally empty `{}` until A1.2 lands.
#
# Staging layout:
#   $WORK/scripts/                     - test_domain_model_skeleton.uc + homeproxy.uc
#   $WORK/scripts/config/              - loader.uc + model.uc + adapter.uc
#   $WORK/scripts/config/homeproxy     - UCI file (from fixture)
#
# The test runs `cd $WORK/scripts && ucode test_domain_model_skeleton.uc`,
# so Loader.load('./config') finds both the config/loader.uc module
# (relative-imported as ./config/loader.uc) and the homeproxy UCI file
# in the same directory.
#
# Usage: sh tests/ucode/test_domain_model_skeleton.sh <repo-root> [work-dir]

ROOT="${1:-.}"
WORK="${2:-/tmp/hp-domain-model-test}"

ROOT="$(cd "$ROOT" && pwd)"
FAILED=0

rm -rf "$WORK"
mkdir -p "$WORK/scripts/config"

# HP_VALIDATE_DATA lets a development host replace /sbin/validate_data (see
# tests/README.md); on a target the production path is kept.
VALIDATE_DATA="${HP_VALIDATE_DATA:-/sbin/validate_data}"
sed -e "s#/sbin/validate_data#${VALIDATE_DATA}#" \
    "$ROOT/root/etc/homeproxy/scripts/homeproxy.uc" > "$WORK/scripts/homeproxy.uc"

cp "$ROOT/root/etc/homeproxy/scripts/config/loader.uc"  "$WORK/scripts/config/"
cp "$ROOT/root/etc/homeproxy/scripts/config/model.uc"   "$WORK/scripts/config/"
cp "$ROOT/root/etc/homeproxy/scripts/config/adapter.uc" "$WORK/scripts/config/"
# PR-02: parse_uri.uc moved into scripts/parser/.  Stage the whole
# tree so the Loader's '../parser/mapping.uc' import resolves inside
# the sandbox.
mkdir -p "$WORK/scripts/parser"
cp "$ROOT/root/etc/homeproxy/scripts/parser/"*.uc       "$WORK/scripts/parser/"

cp "$ROOT/tests/ucode/test_domain_model_skeleton.uc" "$WORK/scripts/"

# Use the dedicated domain-model fixture (tests/fixtures/generators/domain.uci),
# which carries every UCI section the Loader is supposed to read. The
# generator regression suite uses client.uci and custom.uci; this fixture
# is only consumed by the domain-model test.
cp "$ROOT/tests/fixtures/generators/domain.uci" "$WORK/scripts/config/homeproxy"

if ( cd "$WORK/scripts" && ucode -L "$WORK/scripts" test_domain_model_skeleton.uc ); then
	echo "PASS: domain model skeleton"
else
	echo "FAIL: domain model skeleton"
	FAILED=1
fi

exit $FAILED
