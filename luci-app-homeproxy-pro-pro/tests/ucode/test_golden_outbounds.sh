#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
#
# Golden snapshot for the protocol adapter.
#
# Builds one outbound per protocol with tests/fixtures/generators/outbounds.uci
# and diffs the result against tests/snapshots/generator/outbounds.json.
# Adding a protocol field, renaming a sing-box option or reordering the field
# tables shows up as a reviewable diff instead of passing silently.
#
# This replaces tests/ucode/test_demo_architecture.sh, which imported the
# production OutboundFactory and compared it against generate_outbound() - the
# same function - so it could never fail.
#
#   HP_UPDATE_SNAPSHOTS=1 sh tests/ucode/test_golden_outbounds.sh <repo-root>
# regenerates the snapshot (review the diff before committing it).
#
# Without sing-box on PATH the diff still runs but the schema check is only
# reported as NOT RUN (degraded). HP_REQUIRE_SINGBOX=1 turns that into a
# failure; it mirrors HP_REQUIRE_FW4 in test_firewall_template.sh.
#
# Usage: sh tests/ucode/test_golden_outbounds.sh <repo-root> [work-dir]

ROOT="${1:-.}"
WORK="${2:-/tmp/hp-golden-test}"

ROOT="$(cd "$ROOT" && pwd)"
SNAPSHOT="$ROOT/tests/snapshots/generator/outbounds.json"
FIXTURE="$ROOT/tests/fixtures/generators/outbounds.uci"
FAILED=0

rm -rf "$WORK"
mkdir -p "$WORK/scripts/config"

# HP_VALIDATE_DATA lets a development host replace /sbin/validate_data; the
# loader itself does not validate, but homeproxy.uc is imported by the adapter.
VALIDATE_DATA="${HP_VALIDATE_DATA:-/sbin/validate_data}"
sed -e "s#/sbin/validate_data#${VALIDATE_DATA}#" \
	"$ROOT/root/etc/homeproxy/scripts/homeproxy.uc" > "$WORK/scripts/homeproxy.uc"

cp "$ROOT/root/etc/homeproxy/scripts/config/loader.uc"  "$WORK/scripts/config/"
cp "$ROOT/root/etc/homeproxy/scripts/config/model.uc"   "$WORK/scripts/config/"
cp "$ROOT/root/etc/homeproxy/scripts/config/adapter.uc" "$WORK/scripts/config/"
# PR-02: config/loader.uc imports '../parser/mapping.uc'; stage the
# parser tree as a sibling of config/ or nothing loads.
mkdir -p "$WORK/scripts/parser"
cp "$ROOT/root/etc/homeproxy/scripts/parser/"*.uc "$WORK/scripts/parser/"
cp "$FIXTURE" "$WORK/scripts/config/homeproxy"

# One outbound per node, in fixture order.  %.J keeps the JSON value-exact and
# the key order is the field-table order, so the snapshot is stable across
# runs and only changes when the adapter changes.
cat > "$WORK/scripts/golden.uc" <<'EOF'
'use strict';

import { Loader } from './config/loader.uc';
import { OutboundFactory } from './config/adapter.uc';

const dm = Loader.load('./config');
const outbounds = {};

for (let node in dm.nodes)
	outbounds[node.id] = OutboundFactory.create(node, dm.infra.self_mark);

printf('%.J\n', outbounds);
EOF

if ! ( cd "$WORK/scripts" && ucode -L "$WORK/scripts" golden.uc > "$WORK/outbounds.json" 2> "$WORK/golden.err" ); then
	echo "FAIL: could not build the protocol outbounds"
	head -8 "$WORK/golden.err"
	exit 1
fi

if [ ! -s "$WORK/outbounds.json" ]; then
	echo "FAIL: the adapter produced no outbounds (fixture not loaded?)"
	exit 1
fi

# An empty result is the failure mode of a UCI syntax error in the fixture
# (e.g. a C-style comment, which UCI does not accept): uci.load() yields
# nothing and the adapter happily builds zero outbounds.  Fail loudly instead.
protocols="$(grep -c '"tag"' "$WORK/outbounds.json")"
if [ "$protocols" -lt 10 ]; then
	echo "FAIL: only $protocols protocol outbounds were built; the fixture did not load correctly"
	head -5 "$WORK/outbounds.json"
	exit 1
fi

# The runtime-owned fields the literal in build_outbound() sets are applied
# BEFORE the COMMON_FIELDS table, so listing one of them there (even as null)
# silently deletes it.  routing_mark is exactly that case: without it sing-box
# does not mark its own sockets and the nft redirect chain loops the proxy
# connection back into sing-box's own redirect inbound.
#
# Deliberately checked against the emitted JSON rather than through
# `sing-box check`: routing_mark is a Linux-only field, so the schema check
# below accepts it on Linux and rejects it elsewhere, which is how this
# regression survived a green suite.  Asserting on the bytes is
# platform-independent.
SELF_MARK="$(sed -n "s/^[[:space:]]*option self_mark '\([0-9]*\)'.*/\1/p" "$FIXTURE" | head -1)"
if [ -z "$SELF_MARK" ]; then
	echo "FAIL: $FIXTURE declares no infra.self_mark, so the mark cannot be asserted"
	exit 1
fi
marked="$(grep -c "\"routing_mark\": $SELF_MARK" "$WORK/outbounds.json")"
if [ "$marked" -ne "$protocols" ]; then
	echo "FAIL: $protocols node outbounds were built, but only $marked carry routing_mark=$SELF_MARK"
	echo "      every node outbound must carry the runtime mark (see COMMON_FIELDS in"
	echo "      config/adapter.uc): without it the nft OUTPUT redirect chain sends"
	echo "      sing-box's own proxy connection back into its redirect inbound"
	exit 1
fi
echo "PASS: every node outbound carries routing_mark=$SELF_MARK"

if [ "${HP_UPDATE_SNAPSHOTS:-0}" = "1" ]; then
	mkdir -p "$(dirname "$SNAPSHOT")"
	cp "$WORK/outbounds.json" "$SNAPSHOT"
	echo "UPDATED: ${SNAPSHOT#"$ROOT"/}"
	exit 0
fi

if [ ! -s "$SNAPSHOT" ]; then
	echo "FAIL: $SNAPSHOT is missing; regenerate it with HP_UPDATE_SNAPSHOTS=1"
	exit 1
fi

# `cmp` rather than `diff` for the verdict: busybox on the target has no
# `diff`, and this suite runs there as well as on a development host.
if cmp -s "$SNAPSHOT" "$WORK/outbounds.json"; then
	echo "PASS: $protocols protocol outbounds match the golden snapshot"
else
	echo "FAIL: the generated outbounds differ from the golden snapshot"
	if command -v diff > "/dev/null" 2>&1; then
		diff -u "$SNAPSHOT" "$WORK/outbounds.json" | head -40
	else
		echo "      (no 'diff' here; compare ${SNAPSHOT#"$ROOT"/} with $WORK/outbounds.json)"
	fi
	echo "      (review the change; if it is intended, re-run with HP_UPDATE_SNAPSHOTS=1)"
	FAILED=1
fi

# The snapshot diff catches a *change*; this catches a *wrong* value that was
# snapshotted.  Every emitted outbound is handed to the real schema checker.
if command -v sing-box > "/dev/null" 2>&1; then
	cp "$WORK/outbounds.json" "$WORK/scripts/outbounds.json"
	cat > "$WORK/scripts/wrap.uc" <<'EOF'
'use strict';

import { readfile, writefile } from 'fs';

const outbounds = json(readfile('outbounds.json'));
const list = [];

for (let id in keys(outbounds))
	push(list, outbounds[id]);

writefile('schema.json', sprintf('%.J\n', { outbounds: list }));
EOF
	if ( cd "$WORK/scripts" && ucode -L "$WORK/scripts" wrap.uc ) \
	   && sing-box check --config "$WORK/scripts/schema.json"; then
		echo "PASS: sing-box check accepted every golden outbound"
	else
		echo "FAIL: sing-box rejected one of the golden outbounds"
		FAILED=1
	fi
else
	echo "NOT RUN: sing-box is not on PATH, schema check skipped"
	# A skipped schema check must not read as "verified". The snapshot diff
	# above catches a *change* and says nothing about whether the emitted JSON
	# is one sing-box would accept, so say plainly that this run is degraded.
	# HP_REQUIRE_SINGBOX=1 (the same shape as HP_REQUIRE_FW4 in
	# test_firewall_template.sh) turns the skip into a failure for callers that
	# know sing-box must be there - a target always has it.
	echo "         DEGRADED: the golden outbounds were only diffed against the"
	echo "         snapshot, not verified against the real sing-box schema"
	if [ "${HP_REQUIRE_SINGBOX:-0}" = "1" ]; then
		echo "FAIL: HP_REQUIRE_SINGBOX=1 but sing-box is not on PATH, so the"
		echo "      golden outbounds are unverified"
		FAILED=1
	fi
fi

exit $FAILED