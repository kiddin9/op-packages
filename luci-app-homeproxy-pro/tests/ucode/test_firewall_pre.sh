#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
#
# Behaviour tests for firewall_pre.uc, the fw4 pre-rules generator.
#
# firewall_post.ut (the template firewall_pre.uc feeds) already has a
# rendering test, but the *generator* that decides which nft
# statements exist at all had none. Its two validation guards exist
# precisely because a malformed server section would otherwise be
# interpolated into a raw `meta l4proto ... th dport ...` statement:
#
#   - an invalid port emits `th dport  <garbage>` (nft rejects the
#     whole ruleset, so the firewall fails to load and the router
#     loses its ruleset, not just the homeproxy-pro rules)
#   - an invalid network is interpolated verbatim into the l4proto
#     position
#
# Each scenario runs in a fresh process: firewall_pre.uc has no
# exports and its body executes at import time, so one process can
# only exercise one configuration.
#
# Cursor + RUN_DIR redirection: firewall_pre.uc reads UCI and writes
# its fragments relative to RUN_DIR. The staged *copy* is rewritten
# so the cursor takes the sandbox dir and RUN_DIR comes from the
# mock. Production source keeps the plain `cursor()` call - the
# project removed production test seams with HP_TEST_HOOK and this
# keeps it that way.
#
# Usage: sh tests/ucode/test_firewall_pre.sh <repo-root> [work-dir]

ROOT="${1:-.}"
WORK="${2:-/tmp/hp-firewall-pre-test}"

ROOT="$(cd "$ROOT" && pwd)"
FAILED=0

STAGE="$WORK/scripts"

rm -rf "$WORK"
mkdir -p "$STAGE"

cp "$ROOT/tests/ucode/mocks/homeproxy_firewall.uc" "$STAGE/homeproxy-pro.uc"
cp "$ROOT/tests/ucode/test_firewall_pre.uc" "$STAGE/"

# Stage a cursor-redirected copy of firewall_pre.uc, with the shebang
# dropped.
#
# The cursor redirect is the usual no-test-seam-in-production staging: the
# test layer rewrites the one line that would otherwise open the live
# /etc/config.
#
# The shebang is dropped because the target ucode rejects a `#!` line when
# the file is loaded as a *module* ("Unexpected character"), and this test
# imports firewall_pre.uc. Production runs it as a program
# (`ucode "$HP_DIR/scripts/firewall_pre.uc"`), where the shebang is both
# allowed and meaningful, so this is a staging concern and not something to
# change in the source.
sed -e '1{/^#!\/usr\/bin\/ucode$/d;}' \
	-e 's|^const uci = cursor();$|const uci = cursor(ARGV[0]);|' \
	"$ROOT/root/etc/homeproxy-pro/scripts/firewall_pre.uc" > "$STAGE/firewall_pre.uc"

# Hard guard: if an anchor stops matching, the sed no-ops. Losing the
# cursor redirect means the test would read the *real* /etc/config and write
# real nft fragments into /var/run; losing the shebang strip means the
# module cannot be imported at all. Refuse to run rather than silently
# testing the live configuration.
if ! grep -q 'cursor(ARGV\[0\])' "$STAGE/firewall_pre.uc"; then
	echo "FAIL: firewall_pre: could not redirect the UCI cursor"
	echo "      (the 'const uci = cursor();' anchor no longer matches)"
	exit 1
fi
if head -1 "$STAGE/firewall_pre.uc" | grep -q '^#!'; then
	echo "FAIL: firewall_pre: the shebang was not stripped"
	echo "      (the '#!/usr/bin/ucode' anchor no longer matches)"
	exit 1
fi

# seed <scenario> <extra UCI lines...>
seed() {
	scenario="$1"
	shift
	mkdir -p "$WORK/$scenario/sandbox" "$WORK/$scenario/run"
	{
		printf "config homeproxy-pro 'config'\n"
		printf "\toption routing_mode '%s'\n" "$ROUTING_MODE"
		printf "\toption proxy_mode '%s'\n" "$PROXY_MODE"
		printf "\toption main_node '%s'\n" "$MAIN_NODE"
		printf "config homeproxy-pro 'infra'\n"
		printf "\toption tun_name '%s'\n" "${TUN_NAME:-singtun0}"
		printf "config homeproxy-pro 'server'\n"
		printf "\toption enabled '%s'\n" "$SERVER_ENABLED"
		for line in "$@"; do
			printf '%s\n' "$line"
		done
	} > "$WORK/$scenario/sandbox/homeproxy-pro"
}

run_scenario() {
	scenario="$1"
	if ( cd "$STAGE" && ucode -L "$STAGE" \
		test_firewall_pre.uc \
		"$WORK/$scenario/sandbox" \
		"$WORK/$scenario/run" \
		"$scenario" > "$WORK/$scenario/out.txt" 2>&1 ); then
		cat "$WORK/$scenario/out.txt"
	else
		echo "FAIL: firewall_pre scenario '$scenario'"
		cat "$WORK/$scenario/out.txt"
		FAILED=1
	fi
}

# --- scenario: tun mode emits the tun accept pair ---------------------
ROUTING_MODE='bypass_mainland_china' PROXY_MODE='tun' MAIN_NODE='urltest' SERVER_ENABLED='0'
seed tun
run_scenario tun

# --- scenario: tun mode with no outbound node emits nothing -----------
ROUTING_MODE='bypass_mainland_china' PROXY_MODE='tun' MAIN_NODE='nil' SERVER_ENABLED='0'
seed no-tun
run_scenario no-tun

# --- scenario: a hostile tun_name is refused, not interpolated --------
# It reaches the nft file fw4 loads as root, and the file's own threat model
# already validates the server port and network for the same reason.
ROUTING_MODE='bypass_mainland_china' PROXY_MODE='tun' MAIN_NODE='urltest' SERVER_ENABLED='0'
TUN_NAME='singtun0 } ; chain evil { type filter hook prerouting priority 0; policy accept; }'
seed bad-tun
run_scenario bad-tun
if ! grep -q 'WARN: ignoring invalid tun_name' "$WORK/bad-tun/out.txt"; then
	echo "FAIL: firewall_pre: the invalid tun_name was refused without a warning"
	FAILED=1
fi
# Whether a rule was emitted is asserted in the driver (bad-tun expects no
# forward and no input fragment). Grepping out.txt for the payload would be a
# false positive: the warning quotes the rejected value.
unset TUN_NAME

# --- a valid tun_name still reaches the ruleset ------------------------
# The driver asserts the exact rules; this only confirms the guard did not
# disable the feature wholesale.
ROUTING_MODE='bypass_mainland_china' PROXY_MODE='tun' MAIN_NODE='urltest' SERVER_ENABLED='0'
TUN_NAME='singtun9'
seed good-tun
run_scenario good-tun
unset TUN_NAME

# --- scenario: an enabled server with a valid port --------------------
ROUTING_MODE='bypass_mainland_china' PROXY_MODE='redirect_tproxy' MAIN_NODE='urltest' SERVER_ENABLED='1'
seed server "config server 'srv_ok'
	option enabled '1'
	option firewall '1'
	option port '443'"
run_scenario server

# --- scenario: an explicit tcp network narrows l4proto ----------------
ROUTING_MODE='bypass_mainland_china' PROXY_MODE='redirect_tproxy' MAIN_NODE='urltest' SERVER_ENABLED='1'
seed server-network "config server 'srv_tcp'
	option enabled '1'
	option firewall '1'
	option port '8080'
	option network 'tcp'"
run_scenario server-network

# --- scenario: invalid port is skipped, not interpolated --------------
ROUTING_MODE='bypass_mainland_china' PROXY_MODE='redirect_tproxy' MAIN_NODE='urltest' SERVER_ENABLED='1'
seed invalid-port "config server 'srv_bad'
	option enabled '1'
	option firewall '1'
	option port 'not-a-port'"
run_scenario invalid-port
if ! grep -q 'WARN: skipping server srv_bad: invalid port' "$WORK/invalid-port/out.txt"; then
	echo "FAIL: firewall_pre: the invalid port was skipped without a warning"
	FAILED=1
fi

# --- scenario: invalid network is skipped, not interpolated -----------
ROUTING_MODE='bypass_mainland_china' PROXY_MODE='redirect_tproxy' MAIN_NODE='urltest' SERVER_ENABLED='1'
seed invalid-network "config server 'srv_badnet'
	option enabled '1'
	option firewall '1'
	option port '443'
	option network 'sctp'"
run_scenario invalid-network
if ! grep -q 'WARN: skipping server srv_badnet: invalid network' "$WORK/invalid-network/out.txt"; then
	echo "FAIL: firewall_pre: the invalid network was skipped without a warning"
	FAILED=1
fi

# --- scenario: a hostile section name is refused, not interpolated -----
# firewall_pre.uc interpolates the section name into the nft comment, and that
# guard cannot be exercised through a config *file*: libuci accepts only
# [A-Za-z0-9_] in a section name, so a name carrying `"`/`}` - the only kind
# that can close the comment - never survives the parser ("invalid character in
# name field" on load, "Invalid argument" on `uci set`). The guard is the
# second line of defense for any path that hands the script a name libuci never
# validated, so this stage supplies one directly: the copy imports a cursor
# stub instead of libuci and yields the name verbatim.
#
# The stub reads the name from <sandbox>/section-name, which lets the same
# stage cover both halves: a name libuci would accept still gets its rule (so
# the stub really does reach the emit path and the refusal below is the guard,
# not a stub that emits nothing), and a hostile one is skipped.
#
# Grep for the warning, not the payload: the warning quotes the rejected name,
# so a payload grep would match even when the guard worked - the same false
# positive the bad-tun scenario calls out.

MOCK_STAGE="$WORK/mock-stage"
mkdir -p "$MOCK_STAGE"
cp "$ROOT/tests/ucode/mocks/homeproxy_firewall.uc" "$MOCK_STAGE/homeproxy-pro.uc"
cp "$ROOT/tests/ucode/test_firewall_pre.uc" "$MOCK_STAGE/"

# The cursor stub. It replaces libuci for this stage only; print / writefile and
# the rest of the runtime stay real.
cat > "$MOCK_STAGE/test_uci.uc" <<'STUB'
/* Cursor stub for the section-name scenario in tests/ucode/test_firewall_pre.sh.
 * It yields a single `server` section whose name comes verbatim from
 * <sandbox>/section-name - including names libuci refuses, so the firewall_pre
 * guard is the only thing between the name and the nft comment. Everything
 * else matches the file-based fixture (config / infra / server globals). */
import { readfile } from 'fs';

export function cursor(dir) {
	const name = trim(readfile(dir + '/section-name'));
	const globals = {
		config: { routing_mode: 'bypass_mainland_china', proxy_mode: 'redirect_tproxy', main_node: 'urltest' },
		infra:  { tun_name: 'singtun0' },
		server: { enabled: '1' }
	};

	function load() {
		return true;
	}

	function get(cfg, section, option) {
		const entry = globals[section];

		return entry ? entry[option] : null;
	}

	function foreach(cfg, type, cb) {
		if (type === 'server')
			cb({ '.name': name, enabled: '1', firewall: '1', port: '443' });
	}

	return { load: load, get: get, foreach: foreach };
};
STUB

sed -e '1{/^#!\/usr\/bin\/ucode$/d;}' \
	-e "s|^import { cursor } from 'uci';\$|import { cursor } from './test_uci.uc';|" \
	-e 's|^const uci = cursor();$|const uci = cursor(ARGV[0]);|' \
	"$ROOT/root/etc/homeproxy-pro/scripts/firewall_pre.uc" > "$MOCK_STAGE/firewall_pre.uc"

# Same hard guards as above: a no-op sed must not silently fall back to libuci
# (the hostile name would vanish and the scenario would pass for the wrong
# reason) or to the live /etc/config.
if ! grep -q "from './test_uci.uc'" "$MOCK_STAGE/firewall_pre.uc"; then
	echo "FAIL: firewall_pre: could not redirect the cursor to the test stub"
	echo "      (the \"import { cursor } from 'uci';\" anchor no longer matches)"
	exit 1
fi
if ! grep -q 'cursor(ARGV\[0\])' "$MOCK_STAGE/firewall_pre.uc"; then
	echo "FAIL: firewall_pre: could not redirect the UCI cursor"
	echo "      (the 'const uci = cursor();' anchor no longer matches)"
	exit 1
fi

run_mock_scenario() {
	scenario="$1"
	name="$2"
	mkdir -p "$WORK/$scenario/sandbox" "$WORK/$scenario/run"
	printf '%s' "$name" > "$WORK/$scenario/sandbox/section-name"
	if ( cd "$MOCK_STAGE" && ucode -L "$MOCK_STAGE" \
		test_firewall_pre.uc \
		"$WORK/$scenario/sandbox" \
		"$WORK/$scenario/run" \
		"$scenario" > "$WORK/$scenario/out.txt" 2>&1 ); then
		cat "$WORK/$scenario/out.txt"
	else
		echo "FAIL: firewall_pre scenario '$scenario'"
		cat "$WORK/$scenario/out.txt"
		FAILED=1
	fi
}

run_mock_scenario mock-good-section-name 'srv_ok_mock'
run_mock_scenario invalid-section-name 'srv" } ; chain evil { type filter hook prerouting priority 0; policy accept; }'
if ! grep -q 'WARN: skipping server .*: invalid section name' "$WORK/invalid-section-name/out.txt"; then
	echo "FAIL: firewall_pre: the hostile section name was not refused with a warning"
	FAILED=1
fi

# --- scenario: firewall='0' opts a server out entirely ----------------
ROUTING_MODE='bypass_mainland_china' PROXY_MODE='redirect_tproxy' MAIN_NODE='urltest' SERVER_ENABLED='1'
seed firewall-off "config server 'srv_manual'
	option enabled '1'
	option firewall '0'
	option port '443'"
run_scenario firewall-off

# --- scenario: tun and server rules coexist ---------------------------
ROUTING_MODE='bypass_mainland_china' PROXY_MODE='tun' MAIN_NODE='urltest' SERVER_ENABLED='1'
seed both "config server 'srv_ok'
	option enabled '1'
	option firewall '1'
	option port '443'"
run_scenario both

[ "$FAILED" -eq 0 ] && echo "PASS: firewall_pre behaviour tests"

exit $FAILED