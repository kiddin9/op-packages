#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
#
# Golden snapshot for the server inbound adapter (PR-04).
#
# Builds one inbound per protocol with tests/fixtures/generators/server.uci
# and diffs the result against tests/snapshots/generator/inbounds.json.
# Adding a protocol field, renaming a sing-box option or reordering the
# inbound field tables shows up as a reviewable diff instead of passing
# silently.
#
# This is the server-side counterpart of test_golden_outbounds.sh. Before
# PR-04 the server path had no snapshot at all, which is how the fixture's
# `listen_port` (an option neither the form nor the generator uses) stayed
# in place: the generated config simply had no listen_port and
# `sing-box check` accepted it.
#
#   HP_UPDATE_SNAPSHOTS=1 sh tests/ucode/test_golden_inbounds.sh <repo-root>
# regenerates the snapshot (review the diff before committing it).
#
# Without sing-box on PATH the diff still runs but the schema check is only
# reported as NOT RUN (degraded). HP_REQUIRE_SINGBOX=1 turns that into a
# failure; it mirrors HP_REQUIRE_FW4 in test_firewall_template.sh.
#
# Usage: sh tests/ucode/test_golden_inbounds.sh <repo-root> [work-dir]

ROOT="${1:-.}"
WORK="${2:-/tmp/hp-golden-inbounds-test}"

ROOT="$(cd "$ROOT" && pwd)"
SNAPSHOT="$ROOT/tests/snapshots/generator/inbounds.json"
FIXTURE="$ROOT/tests/fixtures/generators/server.uci"
FAILED=0

rm -rf "$WORK"
mkdir -p "$WORK/scripts/config" "$WORK/scripts/parser"

# HP_VALIDATE_DATA lets a development host replace /sbin/validate_data; the
# loader itself does not validate, but homeproxy-pro.uc is imported by the adapter.
VALIDATE_DATA="${HP_VALIDATE_DATA:-/sbin/validate_data}"
sed -e "s#/sbin/validate_data#${VALIDATE_DATA}#" \
	"$ROOT/root/etc/homeproxy-pro/scripts/homeproxy-pro.uc" > "$WORK/scripts/homeproxy-pro.uc"

cp "$ROOT/root/etc/homeproxy-pro/scripts/config/loader.uc"  "$WORK/scripts/config/"
cp "$ROOT/root/etc/homeproxy-pro/scripts/config/model.uc"   "$WORK/scripts/config/"
cp "$ROOT/root/etc/homeproxy-pro/scripts/config/adapter.uc" "$WORK/scripts/config/"
cp "$ROOT/root/etc/homeproxy-pro/scripts/parser/"*.uc       "$WORK/scripts/parser/"
cp "$FIXTURE" "$WORK/scripts/config/homeproxy-pro"

# One inbound per server section, keyed by the UCI section name so the
# snapshot is stable across runs and only changes when the adapter or the
# fixture changes.
#
# The ACME provider carries an absolute data_directory (HP_DIR + '/certs'),
# which differs between the work dir and a target device. Normalise it to a
# placeholder so the snapshot is portable; this is the same "path-only
# difference" allowance the outbound snapshot relies on.
# ucode resolves module-level names lexically, so the helper has to be
# declared above its caller.
cat > "$WORK/scripts/golden.uc" <<'EOF'
'use strict';

import { InboundFactory } from './config/adapter.uc';
import { Loader } from './config/loader.uc';

/* Replace the absolute certs directory with a placeholder. */
function rewrite_paths(tls) {
	if (tls && tls.certificate_provider)
		tls.certificate_provider.data_directory = '<HP_DIR>/certs';
	return tls;
}

const dm = Loader.load('./config');
const inbounds = {};

for (let inbound in (dm.server.inbounds || [])) {
	const built = InboundFactory.tryCreate(inbound);

	if (length(built.problems))
		die(sprintf('inbound %s: %s\n', inbound.id, join('; ', built.problems)));

	built.inbound.tls = rewrite_paths(built.inbound.tls);
	inbounds[inbound.id] = built.inbound;
}

printf('%.J\n', inbounds);
EOF

if ! ( cd "$WORK/scripts" && ucode -L "$WORK/scripts" golden.uc > "$WORK/inbounds.json" 2> "$WORK/golden.err" ); then
	echo "FAIL: could not build the protocol inbounds"
	head -8 "$WORK/golden.err"
	exit 1
fi

if [ ! -s "$WORK/inbounds.json" ]; then
	echo "FAIL: the adapter produced no inbounds (fixture not loaded?)"
	exit 1
fi

# An empty result is the failure mode of a UCI syntax error in the fixture:
# uci.load() yields nothing and the adapter happily builds zero inbounds.
protocols="$(grep -c '"tag"' "$WORK/inbounds.json")"
if [ "$protocols" -lt 6 ]; then
	echo "FAIL: only $protocols protocol inbounds were built; the fixture did not load correctly"
	head -5 "$WORK/inbounds.json"
	exit 1
fi

if [ "${HP_UPDATE_SNAPSHOTS:-0}" = "1" ]; then
	mkdir -p "$(dirname "$SNAPSHOT")"
	cp "$WORK/inbounds.json" "$SNAPSHOT"
	echo "UPDATED: ${SNAPSHOT#"$ROOT"/}"
	exit 0
fi

if [ ! -s "$SNAPSHOT" ]; then
	echo "FAIL: $SNAPSHOT is missing; regenerate it with HP_UPDATE_SNAPSHOTS=1"
	exit 1
fi

# `cmp` rather than `diff` for the verdict: busybox on the target has no
# `diff`, and this suite runs there as well as on a development host.
if cmp -s "$SNAPSHOT" "$WORK/inbounds.json"; then
	echo "PASS: $protocols protocol inbounds match the golden snapshot"
else
	echo "FAIL: the generated inbounds differ from the golden snapshot"
	if command -v diff > "/dev/null" 2>&1; then
		diff -u "$SNAPSHOT" "$WORK/inbounds.json" | head -40
	else
		echo "      (no 'diff' here; compare ${SNAPSHOT#"$ROOT"/} with $WORK/inbounds.json)"
	fi
	echo "      (review the change; if it is intended, re-run with HP_UPDATE_SNAPSHOTS=1)"
	FAILED=1
fi

# The snapshot diff catches a *change*; this catches a *wrong* value that was
# snapshotted. Every emitted inbound is handed to the real schema checker.
#
# The data_directory placeholder is only valid inside the snapshot, so the
# schema check runs against the un-rewritten config.
if command -v sing-box > "/dev/null" 2>&1; then
	cat > "$WORK/scripts/schema.uc" <<'EOF'
'use strict';

import { writefile } from 'fs';

import { InboundFactory } from './config/adapter.uc';
import { Loader } from './config/loader.uc';

const dm = Loader.load('./config');
const list = [];

for (let inbound in (dm.server.inbounds || []))
	push(list, InboundFactory.create(inbound));

writefile('schema.json', sprintf('%.J\n', { inbounds: list }));
EOF
	if ( cd "$WORK/scripts" && ucode -L "$WORK/scripts" schema.uc ) \
	   && sing-box check --config "$WORK/scripts/schema.json"; then
		echo "PASS: sing-box check accepted every golden inbound"
	else
		echo "FAIL: sing-box rejected one of the golden inbounds"
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
	echo "         DEGRADED: the golden inbounds were only diffed against the"
	echo "         snapshot, not verified against the real sing-box schema"
	if [ "${HP_REQUIRE_SINGBOX:-0}" = "1" ]; then
		echo "FAIL: HP_REQUIRE_SINGBOX=1 but sing-box is not on PATH, so the"
		echo "      golden inbounds are unverified"
		FAILED=1
	fi
fi

exit $FAILED
