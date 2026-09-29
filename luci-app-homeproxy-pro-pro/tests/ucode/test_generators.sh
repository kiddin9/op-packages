#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
#
# Run generate_client.uc / generate_server.uc against the UCI fixtures and let
# sing-box validate the result. The generators read /etc/config and write
# /var/run, so this script materialises an isolated copy of them: homeproxy.uc
# is rewritten to point HP_DIR/RUN_DIR at a scratch directory, and the uci
# cursor is pointed at the fixture config.
#
# Stage PHASE 4: the generators are now split into generator/*.uc modules
# and the production entry points (scripts/generate_client.uc and
# scripts/generate_server.uc) are 10-line CLI shells that just load the UCI,
# call the module's generate(), and run the atomic write + sing-box check.
# The testbed no longer needs to sed-substitute a `__LOADER_DIR__` token
# because that mechanism is gone - the staged scripts/ subtree is a regular
# directory and `Loader.load()` takes the path as an argument.
#
# Usage: sh tests/ucode/test_generators.sh <repo-root> [work-dir]

ROOT="${1:-.}"
WORK="${2:-/tmp/hp-generator-test}"

ROOT="$(cd "$ROOT" && pwd)"
FAILED=0

# The local rule-set fixture has to live under /tmp/homeproxy_ (see below), so
# it cannot sit inside $WORK; this is the per-run root that holds it instead.
# Created lazily by the first case that needs one.
RULESET_ROOT=""
cleanup() {
	[ -n "$RULESET_ROOT" ] && rm -rf "$RULESET_ROOT"
}
trap cleanup EXIT INT TERM

run_case() {
	name="$1"
	fixture="$2"
	generator="$3"
	outfile="$4"
	# Optional: a sed expression applied to the staged fixture, for cases that
	# differ from the shared fixture by one UCI option.  Cheaper and more
	# explicit than a near-copy fixture file, and the expression is visible at
	# the call site next to the assertion it serves.
	variation="${5:-}"
	dir="$WORK/$name"

	rm -rf "$dir"
	mkdir -p "$dir/config" "$dir/run" "$dir/scripts" "$dir/scripts/config" "$dir/scripts/generator" "$dir/resources" "$dir/ruleset"
	: > "$dir/resources/direct_list.txt"
	: > "$dir/resources/proxy_list.txt"

	if grep -q "__RULESET_DIR__" "$fixture"; then
		# The fixture needs a real local rule-set on disk. The path must
		# live under /tmp/homeproxy_* (validateHomeProxyPath() in
		# homeproxy.uc whitelists /etc/homeproxy/ and /tmp/homeproxy_
		# only, and the custom fixture exercises the local-rule-set
		# path whitelist gate introduced by the security patch).
		printf '%s' '{"version":1,"rules":[{"domain_suffix":["example.com"]}]}' > "$dir/ruleset/src.json"
		if ! sing-box rule-set compile "$dir/ruleset/src.json" -o "$dir/ruleset/test.srs"; then
			echo "FAIL: $name: could not compile the local rule-set fixture"
			FAILED=1
			return
		fi
		# Stage the ruleset under a /tmp/homeproxy_* directory so the
		# whitelist recognises the staging path. Production paths
		# typically live at /etc/homeproxy/ruleset/...
		#
		# The path cannot move under $WORK (validateHomeProxyPath() in
		# homeproxy.uc whitelists /etc/homeproxy/ and /tmp/homeproxy_
		# only), but it can still be per-run: mktemp gives each run its
		# own tree, and the trap removes it even when a case bails out
		# early.  The old fixed /tmp/homeproxy_test_ruleset/$name leaked
		# one directory per run and let two concurrent runs overwrite
		# each other's compiled .srs.
		if [ -z "$RULESET_ROOT" ]; then
			RULESET_ROOT="$(mktemp -d /tmp/homeproxy_test_ruleset.XXXXXX)"
		fi
		HP_RULESET="$RULESET_ROOT/$name"
		mkdir -p "$HP_RULESET"
		cp "$dir/ruleset/test.srs" "$HP_RULESET/test.srs"
		sed "s#__RULESET_DIR__#$HP_RULESET#" "$fixture" > "$dir/config/homeproxy"
	else
		cp "$fixture" "$dir/config/homeproxy"
	fi

	if [ -n "$variation" ]; then
		sed -e "$variation" "$dir/config/homeproxy" > "$dir/config/homeproxy.sed" \
			|| { echo "FAIL: $name: the fixture variation could not be applied"; FAILED=1; return; }
		if cmp -s "$dir/config/homeproxy" "$dir/config/homeproxy.sed"; then
			# A variation that matched nothing would run the same case twice
			# and report a pass for behaviour that was never exercised.
			echo "FAIL: $name: the fixture variation matched nothing ($variation)"
			FAILED=1
			return
		fi
		mv "$dir/config/homeproxy.sed" "$dir/config/homeproxy"
	fi


	# HP_VALIDATE_DATA lets a development host replace /sbin/validate_data
	# (see tests/README.md); on a target the production path is kept.
	#
	# UCICONFIG_DIR is the UCI confdir the Loader hands to cursor().  On a
	# target it is /etc/config; here it has to point at the fixture staged
	# below as $dir/config/homeproxy.  Rewriting the constant is what keeps
	# the staging seam out of the source files - staging it as
	# HP_DIR + '/config' instead would silently diverge from production,
	# which is exactly the bug this constant replaced.
	VALIDATE_DATA="${HP_VALIDATE_DATA:-/sbin/validate_data}"
	sed -e "s#^export const HP_DIR = '/etc/homeproxy';#export const HP_DIR = '$dir';#" \
	    -e "s#^export const RUN_DIR = '/var/run/homeproxy';#export const RUN_DIR = '$dir/run';#" \
	    -e "s#^export const UCICONFIG_DIR = '/etc/config';#export const UCICONFIG_DIR = '$dir/config';#" \
	    -e "s#/sbin/validate_data#${VALIDATE_DATA}#" \
	    "$ROOT/root/etc/homeproxy/scripts/homeproxy.uc" > "$dir/scripts/homeproxy.uc"

	# Stage the config/ subtree (Loader / Model / Adapter, imported via
	# the relative path "../config/*.uc" by the generator modules).
	cp "$ROOT/root/etc/homeproxy/scripts/config/loader.uc"  "$dir/scripts/config/"
	cp "$ROOT/root/etc/homeproxy/scripts/config/model.uc"   "$dir/scripts/config/"
	cp "$ROOT/root/etc/homeproxy/scripts/config/adapter.uc" "$dir/scripts/config/"
	# PR-02: config/loader.uc imports '../parser/mapping.uc', so the
	# parser tree has to be staged as a sibling of config/ or the
	# generator cannot even load the configuration.
	mkdir -p "$dir/scripts/parser"
	cp "$ROOT/root/etc/homeproxy/scripts/parser/"*.uc "$dir/scripts/parser/"

	# Stage the generator/ subtree that PHASE 4 introduced. The CLI
	# shells (scripts/generate_*.uc) import from generator/; the
	# modules in turn import from common.uc, dns.uc, ... inside the
	# same directory.
	cp "$ROOT/root/etc/homeproxy/scripts/generator/"*.uc "$dir/scripts/generator/"

	# Stage the CLI shells themselves. This is the entry point the
	# production init.d runs (`ucode -S generate_client.uc`); the
	# test exercises the same code path end-to-end, not a parallel
	# test-only driver.
	cp "$ROOT/root/etc/homeproxy/scripts/$generator" "$dir/scripts/$generator"

	# No platform patching here on purpose.  The suite used to rewrite
	# generator/client.uc's `routing_mark` to null on Darwin, because the
	# macOS sing-box rejects that Linux-only field - which meant the one
	# field the product needs on its target platform was silently deleted
	# before every test, and a regression in it could never be seen.  The
	# off-target layer is Linux-only now (see tests/README.md); a host that
	# cannot validate the generated configuration says so instead of
	# weakening it.

	# stderr is kept so a test can assert on warnings (e.g. a pruned urltest
	# candidate) as well as on the generated JSON.
	if ! ( cd "$dir/scripts" && ucode -L "$dir/scripts" "$generator" 2> "$dir/generate.err" ); then
		echo "FAIL: $name: $generator exited non-zero"
		head -5 "$dir/generate.err"
		cp "$dir/generate.err" "$WORK/$name.err" 2>"/dev/null"
		FAILED=1
		return
	fi

	if [ ! -f "$dir/run/$outfile" ]; then
		echo "FAIL: $name: $outfile was not generated"
		FAILED=1
		return
	fi

	if ! sing-box check --config "$dir/run/$outfile"; then
		echo "FAIL: $name: sing-box rejected the generated $outfile"
		FAILED=1
		return
	fi

	echo "PASS: $name ($(wc -c < "$dir/run/$outfile") bytes)"
}

# run_case_type_error <case-name> <expected message fragment> <run_case args...>
# Stages a case the same way run_case() does and asserts that generation FAILS
# with a message naming the offender.  The generator's die() paths are what keep
# a dangling reference from reaching sing-box, where the failure would be a
# rejected configuration and a reload that silently keeps the previous one.
run_case_type_error() {
	local name="$1" expect="$2"; shift 2

	# run_case() reports a non-zero generator as its own failure and sets the
	# global FAILED - but here that non-zero exit *is* the expected outcome, so
	# the flag is saved and restored around the call.  Its return status is
	# always 0 (the function ends with `echo "PASS: ..."`), so the refusal is
	# observed through the artifacts instead: the generator's stderr, and the
	# absence of the configuration it would otherwise write.
	local saved_failed="$FAILED"
	run_case "$name" "$@" > "$WORK/$name.out" 2>&1
	FAILED="$saved_failed"
	local err="$WORK/$name.err"

	if [ -f "$WORK/$name/run/sing-box-c.json" ]; then
		echo "FAIL: $name: a configuration was generated, but it must be refused"
		FAILED=1
	elif [ ! -s "$err" ]; then
		echo "FAIL: $name: generation produced no diagnostic:"
		sed -n '1,5p' "$WORK/$name.out"
		FAILED=1
	elif grep -q "$expect" "$err"; then
		echo "PASS: $name: refused with a message naming the offender"
	else
		echo "FAIL: $name: the diagnostic does not name the offender (expected '$expect'):"
		head -3 "$err"
		FAILED=1
	fi

	# Without this the caller's status is the grep's, and a passing case reports
	# failure to the suite.
	return 0
}

# The fixture's infra.self_mark, i.e. the value every node outbound has to
# carry as routing_mark in the redirect modes.
fixture_self_mark() {
	sed -n "s/^[[:space:]]*option self_mark '\([0-9]*\)'.*/\1/p" "$1" | head -1
}

# Read one field out of a generated configuration.  ucode is already required
# by this suite, and a JSON walk is stronger than a grep: it cannot be
# satisfied by a coincidental match elsewhere in the file.
mkdir -p "$WORK"
cat > "$WORK/probe.uc" <<'EOF'
'use strict';

import { readfile } from 'fs';

const config = json(readfile(ARGV[0]));

switch (ARGV[1]) {
case 'main-dns-server':
	for (let s in (config.dns?.servers || []))
		if (s.tag === 'main-dns') {
			printf('%s\n', s.server ?? '');
			exit(0);
		}
	printf('\n');
	break;
case 'route-final':
	printf('%s\n', config.route?.final ?? '');
	break;
case 'has-outbound-tag':
	for (let o in (config.outbounds || []))
		if (o.tag === ARGV[2]) {
			printf('yes\n');
			exit(0);
		}
	printf('no\n');
	break;
case 'rule-set-count':
	printf('%d\n', length(config.route?.rule_set || []));
	break;
default:
	printf('unknown probe\n');
	break;
}
EOF

config_field() {
	ucode "$WORK/probe.uc" "$1" "$2" "${3:-}" 2>"/dev/null"
}

# Read one field out of a generated configuration.  ucode is already required
# by this suite, and a JSON walk is stronger than a grep: it cannot be
# satisfied by a coincidental match elsewhere in the file.
run_case client "$ROOT/tests/fixtures/generators/client.uci" generate_client.uc sing-box-c.json

# The preset remote rule-sets must be fetched through the node. A direct
# download depends on the CDN staying reachable from mainland China and fails
# intermittently under DNS pollution, which shows up as "open connection to
# <ip>:443 using outbound/direct[direct]: i/o timeout" in sing-box-c.log.
if grep -q '"detour": "direct-out"' "$WORK/client/run/sing-box-c.json"; then
	echo "FAIL: client: a remote rule-set would still be downloaded directly"
	FAILED=1
fi
if ! grep -q '"detour": "main-out"' "$WORK/client/run/sing-box-c.json"; then
	echo "FAIL: client: no remote rule-set is configured to download through main-out"
	FAILED=1
fi

# --- the product default proxy mode --------------------------------------
#
# client.uci runs `proxy_mode 'tun'`, where self_mark is empty and no outbound
# carries routing_mark.  That made it the only end-to-end fixture for as long
# as the default mode (redirect_tproxy) was never generated here - and the
# adapter's COMMON_FIELDS neutralized routing_mark (it listed the key as null
# *after* the literal that sets it), so every node outbound lost the mark that
# keeps sing-box's own proxy connection out of the nft redirect chain.  This
# case covers the default mode and asserts the mark on the emitted bytes.
run_case redirect "$ROOT/tests/fixtures/generators/redirect.uci" generate_client.uc sing-box-c.json

redir_fixture="$ROOT/tests/fixtures/generators/redirect.uci"
redir_json="$WORK/redirect/run/sing-box-c.json"
redir_mark="$(fixture_self_mark "$redir_fixture")"

if [ -z "$redir_mark" ]; then
	echo "FAIL: redirect: $redir_fixture no longer declares infra.self_mark, so the"
	echo "      routing_mark assertion would pass vacuously"
	FAILED=1
elif [ ! -f "$redir_json" ]; then
	echo "FAIL: redirect: no config was generated"
	FAILED=1
else
	if ! grep -q '"tag": "redirect-in"' "$redir_json"; then
		echo "FAIL: redirect: proxy_mode=redirect_tproxy did not emit redirect-in"
		FAILED=1
	fi

	# tproxy-in is gated on a dedicated UDP node, exactly like the nft
	# tproxy chain in firewall_post.ut.  This fixture leaves main_udp_node at
	# 'nil', so the inbound must NOT be emitted: the old code emitted it
	# anyway with listen_port 0 - context.uc only assigns tproxy_port when a
	# UDP node exists - binding a random UDP port that no rule ever points
	# at.  The positive case is redirect-udp below.
	if grep -q '"tag": "tproxy-in"' "$redir_json"; then
		echo "FAIL: redirect: main_udp_node=nil emitted tproxy-in, which no nft rule"
		echo "      points at (see the tproxy_port gate in generator/inbound.uc)"
		FAILED=1
	fi
	if grep -q '"listen_port": 0' "$redir_json"; then
		echo "FAIL: redirect: a generated inbound has listen_port 0:"
		grep -n -B 3 '"listen_port": 0' "$redir_json" | head -8
		FAILED=1
	fi

	# Which outbounds must carry the mark: every outbound that dials.  Group
	# outbounds (urltest/selector) must NOT - sing-box rejects the field on
	# them with `json: unknown field "routing_mark"` - and block-out never
	# dials.  A structural walk is used instead of a grep count so the
	# group/leaf distinction cannot silently rot into a vacuous assertion.
	cat > "$WORK/markcheck.uc" <<'EOF'
'use strict';

import { readfile } from 'fs';

const want = +ARGV[0];
const config = json(readfile(ARGV[1]));
let checked = 0, problems = 0;

for (let ob in (config.outbounds || [])) {
	if (index(['block', 'urltest', 'selector'], ob.type) !== -1)
		continue;

	checked++;

	if (ob.routing_mark !== want)
		problems++;
}

printf('%d %d\n', checked, problems);
EOF

	mark_result="$(ucode "$WORK/markcheck.uc" "$redir_mark" "$redir_json" 2>"/dev/null")"
	mark_checked="${mark_result%% *}"
	mark_problems="${mark_result##* }"

	case "$mark_checked" in
	''|*[!0-9]*)
		echo "FAIL: redirect: could not check the emitted outbounds ($redir_json)"
		FAILED=1
		;;
	0)
		echo "FAIL: redirect: no dialling outbound was emitted, the assertion is vacuous"
		FAILED=1
		;;
	*)
		if [ "$mark_problems" -ne 0 ]; then
			echo "FAIL: redirect: $mark_problems of $mark_checked dialling outbounds do not"
			echo "      carry routing_mark=$redir_mark (see COMMON_FIELDS in config/adapter.uc);"
			echo "      without it sing-box does not mark its own sockets and the nft OUTPUT"
			echo "      redirect chain loops the proxy connection back into its own inbound"
			FAILED=1
		else
			echo "PASS: redirect: all $mark_checked dialling outbounds carry routing_mark=$redir_mark"
		fi
		;;
	esac
fi

# The UDP tproxy path: a dedicated UDP node makes context.uc assign
# tproxy_port, firewall_post.ut emit the tproxy chain, and inbound.uc emit the
# tproxy-in that chain redirects to.  No fixture covered this path before -
# every one either used tun or left main_udp_node at 'nil'.
run_case redirect-udp "$ROOT/tests/fixtures/generators/redirect.uci" generate_client.uc sing-box-c.json \
	"s/^\([[:space:]]*\)option main_udp_node '.*'/\1option main_udp_node 'same'/"

rudp_json="$WORK/redirect-udp/run/sing-box-c.json"
if [ ! -f "$rudp_json" ]; then
	echo "FAIL: redirect-udp: no config was generated"
	FAILED=1
elif ! grep -q '"tag": "tproxy-in"' "$rudp_json"; then
	echo "FAIL: redirect-udp: main_udp_node=same did not emit tproxy-in"
	FAILED=1
elif ! grep -A 4 '"tag": "tproxy-in"' "$rudp_json" | grep -q '"listen_port": 5332'; then
	echo "FAIL: redirect-udp: tproxy-in does not listen on the configured tproxy port:"
	grep -A 4 '"tag": "tproxy-in"' "$rudp_json" | head -6
	FAILED=1
else
	echo "PASS: redirect-udp: a dedicated UDP node emits tproxy-in on 5332"
fi

# H1: custom-only scalars must not survive into a preset mode.
#
# route.uc and outbound.uc choose their branch with `isEmpty(default_outbound)`
# while the preset DNS builder keys off main_node.  A residual
# routing.default_outbound (LuCI hides the field in preset modes but does not
# clear it) therefore switched generation onto the custom branch, the DNS block
# silently lost main-dns/china-dns, and the rule-set tags the leftover custom
# rules referenced were never built - `sing-box check` rejected the whole
# configuration, so the reload kept the old one and the user only saw "my
# change did not take".  client.uci is the preset path with no main node; the
# expression below is a no-op unless generation writes the field.
run_case preset-stale-default-outbound "$ROOT/tests/fixtures/generators/client.uci" generate_client.uc sing-box-c.json \
	"s#^\\([[:space:]]*\\)option proxy_mode .*#\\1option proxy_mode 'redirect_tproxy'\\n\\1option main_udp_node 'same'\\n\\1option default_outbound 'direct-out'#"

# A residual routing.default_outbound must not switch a preset-mode router onto
# the custom branch: the preset DNS builder keys off main_node and bails out,
# so the DNS block would lose main-dns/china-dns, and the leftover custom rules
# reference rule-set tags that only custom mode builds.  The expression above
# inserts the stale option; with the mode gate in build_context() it is never
# read, so the generated config must still be the preset one.
pso_json="$WORK/preset-stale-default-outbound/run/sing-box-c.json"
if [ ! -f "$pso_json" ]; then
	echo "FAIL: preset-stale-default-outbound: no config was generated"
	FAILED=1
else
	for probe in '"tag": "main-dns"' '"tag": "china-dns"'; do
		if ! grep -q "$probe" "$pso_json"; then
			echo "FAIL: preset-stale-default-outbound: the preset DNS path is missing $probe"
			echo "      a residual routing.default_outbound put generation on the custom branch"
			FAILED=1
		fi
	done
	if ! grep -q '"final": "main-out"' "$pso_json"; then
		echo "FAIL: preset-stale-default-outbound: route.final is not main-out"
		FAILED=1
	fi
	# find_neighbor is emitted only by the custom route builder.
	if grep -q '"find_neighbor"' "$pso_json"; then
		echo "FAIL: preset-stale-default-outbound: find_neighbor leaked into the preset config"
		FAILED=1
	fi
	if ! grep -q '"type": "redirect"' "$pso_json"; then
		echo "FAIL: preset-stale-default-outbound: the redirect inbound is missing"
		FAILED=1
	fi
fi


run_case wan-dns "$ROOT/tests/fixtures/generators/client.uci" generate_client.uc sing-box-c.json \
	"s/^\([[:space:]]*\)option dns_server '.*'/\1option dns_server 'wan'/"

wan_json="$WORK/wan-dns/run/sing-box-c.json"
if [ ! -f "$wan_json" ]; then
	echo "FAIL: wan-dns: no config was generated"
	FAILED=1
else
	wan_server="$(config_field "$wan_json" main-dns-server)"
	case "$wan_server" in
	'')
		echo "FAIL: wan-dns: main-dns has no server at all (dns_server='wan' was dropped)"
		FAILED=1
		;;
	wan)
		echo "FAIL: wan-dns: the literal 'wan' was published as the main DNS hostname;"
		echo "        sing-box would try to resolve a host by that name"
		FAILED=1
		;;
	*)
		echo "PASS: wan-dns: dns_server='wan' resolved to $wan_server"
		;;
	esac
fi

# --- A1: the generator is a pure function of its arguments ----------------
#
# generator/client.uc used to resolve its own runtime environment - ubus for
# the WAN resolver, readfile() for the two domain-resource lists - while being
# documented as a pure function. "Generate the same config twice" was therefore
# not guaranteed, and reload's preflight generation was not provably the
# artifact start_service regenerated. The impure step now lives in the CLI
# shell, which hands the values to generate(dm, env).
#
# Both halves of that contract are pinned here, through the production entry
# point (not a test-only driver): the same inputs must produce byte-identical
# output, and a changed GenerationContext input must reach the generator. The
# comparison is exact string equality rather than a hash, because busybox has
# no cksum and macOS has no md5sum by default.
det_dir="$WORK/client"
det_gen="generate_client.uc"
det_out="$det_dir/run/sing-box-c.json"
det_first="$det_dir/determinism-first.json"

cp "$det_out" "$det_first"
( cd "$det_dir/scripts" && ucode -L "$det_dir/scripts" "$det_gen" ) >"/dev/null" 2>&1
if [ "$(cat "$det_out")" = "$(cat "$det_first")" ]; then
	echo "PASS: the same generation inputs produce byte-identical output"
else
	echo "FAIL: two identical generation runs produced different output"
	FAILED=1
fi

# direct_list.txt is read by the CLI and passed in as env.direct_domain_list.
# If that plumbing were lost - the exact shape of the old hidden read - the file
# would be ignored and the output would not move.
printf 'determinism.example.com\n' > "$det_dir/resources/direct_list.txt"
( cd "$det_dir/scripts" && ucode -L "$det_dir/scripts" "$det_gen" ) >"/dev/null" 2>&1
if [ "$(cat "$det_out")" != "$(cat "$det_first")" ]; then
	echo "PASS: a changed GenerationContext input changes the generated output"
else
	echo "FAIL: the domain-resource list did not reach the generator"
	FAILED=1
fi
if ! grep -qF 'determinism.example.com' "$det_out"; then
	echo "FAIL: the domain from direct_list.txt is absent from the generated config"
	FAILED=1
fi

run_case custom "$ROOT/tests/fixtures/generators/custom.uci" generate_client.uc sing-box-c.json

# §2.2 (linux.json 与 pro 的差距分析): append_custom_dns now prepends the
# HTTPS/SVCB reject so a user-written rule cannot shadow the safety net.
# Without a dns_server in custom.uci the rule block is empty, so the
# generated config still has the reject at index 0.
custom_json="$WORK/custom/run/sing-box-c.json"
if [ ! -f "$custom_json" ]; then
	echo "FAIL: custom-dns-rule-prefix: no config was generated"
	FAILED=1
else
	# Walk the JSON to pick the first rule. Grepping for the literal would
	# also match later rules (the user's domain-rule block emits its own
	# query_type); a JSON walker is unambiguous and tolerant of any
	# whitespace or quoting sing-box picks when serialising.
	cat > "$WORK/dns-rule-prefix.uc" <<'EOF'
'use strict';
import { readfile } from 'fs';
const config = json(readfile(ARGV[0]));
const rules = config.dns.rules || [];
let qt = '', action = '';
for (let r in rules) {
	qt = (type(r.query_type) === 'array') ? r.query_type[0] + ',' + r.query_type[1] : '';
	action = r.action || '';
	break;
}
printf('%s|%s\n', qt, action);
EOF
	dns_first="$(ucode "$WORK/dns-rule-prefix.uc" "$custom_json" 2>/dev/null)"
	if [ "$dns_first" = "64,65|reject" ]; then
		echo "PASS: custom-dns-rule-prefix: the HTTPS/SVCB reject is the first DNS rule"
	else
		echo "FAIL: custom-dns-rule-prefix: first DNS rule is '$dns_first', expected '64,65|reject'"
		FAILED=1
	fi
fi

# §2.5 (linux.json 与 pro 的差距分析): the original plan was to set
# `experimental.reverse_mapping: true` so the literal pinned us against a
# future sing-box default flip. sing-box 1.14.0-r1 (the CI floor pinned
# by arch-guard 31) rejects the field as "json: unknown field" - the
# default is already true, and leaving the field implicit matches the
# runtime behaviour.  Re-evaluate this guard when the floor moves past
# the release where the field was added.  No regression check here on
# purpose: the only assertion that matters is that the generated config
# passes sing-box check, which the test runner does for every case.

# §2.4 (linux.json 与 pro 的差距分析): when the user configures a DoH
# upstream against a known hostname, append_custom_dns emits a hosts-type
# DNS server pinning that hostname to its real IPs.  Without it, the DoH
# resolver itself has to be resolved through the system DNS, and a DNS
# outage once over leaves the resolver unreachable (chicken-and-egg).
# NOTE: the sed pattern matches `/test.srs'` (the trailing apostrophe is
# part of the UCI literal), not `/test.srs` - run_case() substitutes
# __RULESET_DIR__ before this variation runs, so match the trailing /test.srs
# rather than the literal template name.
# Do not put comments between the line-continuation backslash and the sed
# expression: on /bin/sh (dash on the runner), the comment terminates the
# continuation and the next line is treated as a new command, leaving the
# variation empty and the fixture un-varied.  See custom-stale-main-node
# for the comment-free form.
run_case custom-doh-fallback "$ROOT/tests/fixtures/generators/custom.uci" generate_client.uc sing-box-c.json \
	"s#^[[:space:]]*option path .*/test.srs'#&\n\nconfig dns_server 'ds_doh'\n\toption enabled '1'\n\toption type 'https'\n\toption server 'doh.pub'\n\toption path '/dns-query'#"

doh_json="$WORK/custom-doh-fallback/run/sing-box-c.json"
if [ ! -f "$doh_json" ]; then
	echo "FAIL: custom-doh-fallback: no config was generated"
	FAILED=1
elif ! grep -q '"tag": "hp-dns-hosts"' "$doh_json"; then
	echo "FAIL: custom-doh-fallback: the hosts-type DNS server (tag hp-dns-hosts) is missing"
	echo "      a DoH upstream was configured against a known hostname, so the generator"
	echo "      should have pre-emitted a predefined entry to break the resolver->DNS loop"
	FAILED=1
else
	# Walk the JSON: the server must be type=hosts with a predefined entry
	# listing at least one known DoH hostname->IP pair.
	cat > "$WORK/doh-check.uc" <<'EOF'
'use strict';
import { readfile } from 'fs';
const config = json(readfile(ARGV[0]));
for (let s in (config.dns?.servers || [])) {
	if (s.tag === 'hp-dns-hosts' && s.type === 'hosts' && s.predefined) {
		const names = keys(s.predefined);
		printf('%d %s\n', length(names), names[0] ?? '');
		exit(0);
	}
}
printf('0\n');
EOF
	doh_info="$(ucode "$WORK/doh-check.uc" "$doh_json" 2>/dev/null)"
	if [ -z "$doh_info" ] || [ "${doh_info%% *}" = "0" ]; then
		echo "FAIL: custom-doh-fallback: hp-dns-hosts was emitted but has no predefined entry"
		FAILED=1
	else
		doh_count="${doh_info%% *}"
		doh_name="$(printf '%s' "$doh_info" | awk '{print $2}')"
		echo "PASS: custom-doh-fallback: $doh_count predefined entry/entries under hp-dns-hosts (sample: $doh_name)"
	fi
fi

# §2.1 (linux.json 与 pro 的差距分析): cn_ip_fallback default flipped to '1'
# for fresh installs (the package ships option cn_ip_fallback '1' and
# context.uc falls back to '1' on a missing value).  Existing users
# upgrading get '0' written by migrate_config.uc and keep the prior
# behaviour.  This case verifies the fresh-install default: client.uci
# (proxy mode) does NOT set cn_ip_fallback, so the generator emits the
# evaluate + match_response pair under the cn-fallback tag.
client_json="$WORK/client/run/sing-box-c.json"
if [ ! -f "$client_json" ]; then
	echo "FAIL: cn-fallback-default-on: no proxy config was generated"
	FAILED=1
else
	cat > "$WORK/cn-fallback.uc" <<'EOF'
'use strict';
import { readfile } from 'fs';
const config = json(readfile(ARGV[0]));
const rules = config.dns?.rules || [];
let has_eval_tag = false, has_match_response = false, geoip_ref = false;
for (let r in rules) {
	if (r.action === 'evaluate' && r.tag === 'cn-fallback')
		has_eval_tag = true;
	if (r.match_response === 'cn-fallback') {
		has_match_response = true;
		if (r.rule_set === 'geoip-cn')
			geoip_ref = true;
	}
}
printf('%d %d %d\n', +has_eval_tag, +has_match_response, +geoip_ref);
EOF
	cn_info="$(ucode "$WORK/cn-fallback.uc" "$client_json" 2>/dev/null)"
	if [ "$cn_info" = "1 1 1" ]; then
		echo "PASS: cn-fallback-default-on: evaluate+match_response with geoip-cn is in the proxy config"
	else
		echo "FAIL: cn-fallback-default-on: evaluate/match_response flags = '$cn_info', expected '1 1 1'"
		FAILED=1
	fi
fi

# §2.1 opt-out: a fixture with cn_ip_fallback='0' must NOT emit the pair.
# client.uci does not set the option (so it defaults to '1' in the proxy
# config above); here we stage a variant with '0' to assert the
# upgrade-safe path of migrate_config.uc - existing users see no change.
run_case client-cn-fallback-off "$ROOT/tests/fixtures/generators/client.uci" generate_client.uc sing-box-c.json \
	"s#^\\([[:space:]]*\\)option main_node 'urltest'#\\1option main_node 'urltest'\\n\\1option cn_ip_fallback '0'#"

cfoff_json="$WORK/client-cn-fallback-off/run/sing-box-c.json"
if [ ! -f "$cfoff_json" ]; then
	echo "FAIL: cn-fallback-opt-out: no config was generated"
	FAILED=1
else
	cfoff_info="$(ucode "$WORK/cn-fallback.uc" "$cfoff_json" 2>/dev/null)"
	if [ "$cfoff_info" = "0 0 0" ]; then
		echo "PASS: cn-fallback-opt-out: cn_ip_fallback='0' suppresses both rules (upgrade path keeps prior behaviour)"
	else
		echo "FAIL: cn-fallback-opt-out: evaluate/match_response flags = '$cfoff_info', expected '0 0 0'"
		FAILED=1
	fi
fi

# §2.7 (linux.json 与 pro 的差距分析): sniffer_advanced_mode default stays
# '0'.  Client mode must emit the conservative sniff rule (300ms / no
# sniffer list); advanced mode emits the 100ms / universal-list profile.
if [ ! -f "$client_json" ]; then
	echo "FAIL: sniffer-default-300ms: no proxy config was generated"
	FAILED=1
else
	cat > "$WORK/sniff.uc" <<'EOF'
'use strict';
import { readfile } from 'fs';
const config = json(readfile(ARGV[0]));
const rules = config.route.rules || [];
let to = 'none';
let count = 0;
for (let r in rules) {
	if (r.action === 'sniff') {
		to = r.timeout || '';
		count = (type(r.sniffer) === 'array') ? length(r.sniffer) : 0;
		break;
	}
}
printf('%s|%d\n', to, count);
EOF
	sniff_info="$(ucode "$WORK/sniff.uc" "$client_json" 2>/dev/null)"
	if [ "$sniff_info" = "300ms|0" ]; then
		echo "PASS: sniffer-default-300ms: sniff rule keeps 300ms and the default sniffer list (no array)"
	elif [ "$sniff_info" = "100ms|"* ]; then
		echo "FAIL: sniffer-default-300ms: the default flipped to 100ms (advanced); users upgrading"
		echo "      without setting sniffer_advanced_mode should see the legacy 300ms profile"
		FAILED=1
	else
		echo "FAIL: sniffer-default-300ms: sniff rule has unexpected shape '$sniff_info'"
		FAILED=1
	fi
fi

# §2.7 opt-in: sniffer_advanced_mode='1' flips the sniff rule to 100ms +
# the universal protocol list.  sed-injected on client.uci.
run_case client-sniffer-advanced "$ROOT/tests/fixtures/generators/client.uci" generate_client.uc sing-box-c.json \
	"s#^\\([[:space:]]*\\)option main_node 'urltest'#\\1option main_node 'urltest'\\n\\1option sniffer_advanced_mode '1'#"

sniff_json="$WORK/client-sniffer-advanced/run/sing-box-c.json"
if [ ! -f "$sniff_json" ]; then
	echo "FAIL: sniffer-advanced-100ms: no config was generated"
	FAILED=1
else
	sniff_adv="$(ucode "$WORK/sniff.uc" "$sniff_json" 2>/dev/null)"
	if [ "$sniff_adv" = "100ms|5" ]; then
		echo "PASS: sniffer-advanced-100ms: sniff rule has 100ms timeout and 5 sniffer protocols"
	else
		echo "FAIL: sniffer-advanced-100ms: sniff rule has unexpected shape '$sniff_adv', expected '100ms|5'"
		FAILED=1
	fi
fi

# P1-6: the main-node reference is mode-dependent, and LuCI hides config.main_node
# in custom mode without clearing it (`rmempty = false`).  A router that was
# configured in a preset mode and then switched to custom therefore keeps the
# old value - and reading it in custom mode switched the generator back to the
# preset path, dropping every routing_rule/rule_set the user configured.
run_case custom-stale-main-node "$ROOT/tests/fixtures/generators/custom.uci" generate_client.uc sing-box-c.json \
	"s/^\([[:space:]]*\)option log_level 'error'/\1option log_level 'error'\n\1option main_node 'n_direct'/"

stale_json="$WORK/custom-stale-main-node/run/sing-box-c.json"
if [ ! -f "$stale_json" ]; then
	echo "FAIL: custom-stale-main-node: no config was generated"
	FAILED=1
else
	stale_final="$(config_field "$stale_json" route-final)"
	stale_rulesets="$(config_field "$stale_json" rule-set-count)"
	stale_main_out="$(config_field "$stale_json" has-outbound-tag main-out)"
	if [ "$stale_main_out" = "yes" ]; then
		echo "FAIL: custom: a residual config.main_node switched the generator back to the"
		echo "      preset path (the generated config has main-out), so every routing_rule"
		echo "      and rule_set the user configured was dropped"
		FAILED=1
	elif [ "$stale_final" != "direct-out" ]; then
		echo "FAIL: custom: route.final is '$stale_final', expected the fixture's custom"
		echo "      default_outbound (direct-out)"
		FAILED=1
	elif [ "$stale_rulesets" = "0" ]; then
		echo "FAIL: custom: the fixture's local rule_set is missing from the generated config"
		FAILED=1
	else
		echo "PASS: custom: a residual main_node does not override custom routing"
	fi
fi

run_case server "$ROOT/tests/fixtures/generators/server.uci" generate_server.uc sing-box-s.json

# WireGuard is emitted as a sing-box endpoint, not an outbound, and it has its
# own builder.  A3 converted the call sites to pass a Node but left
# generate_endpoint() reading flat UCI keys, so the key material silently
# disappeared and sing-box rejected the config.  `sing-box check` alone is not
# a strong enough guard (a config with no server at all can still be valid),
# so assert the endpoint actually carries the fixture's keys.
run_case wireguard "$ROOT/tests/fixtures/generators/wireguard.uci" generate_client.uc sing-box-c.json

wg_json="$WORK/wireguard/run/sing-box-c.json"
if [ ! -f "$wg_json" ]; then
	echo "FAIL: wireguard: no config was generated"
	FAILED=1
else
	if ! grep -qF '"type": "wireguard"' "$wg_json"; then
		echo "FAIL: wireguard: no wireguard endpoint in the generated config"
		FAILED=1
	fi
	if ! grep -qF 'iKaNuoWRQTFPD5V3OoMNdMshsMgU9t7rolJNpgNx+UM=' "$wg_json"; then
		echo "FAIL: wireguard: the endpoint lost its private key"
		FAILED=1
	fi
	if ! grep -qF 'DDcdTHUv0Q6XYDf9l93jzwwuoY/G1TC+g74QH0A9HmM=' "$wg_json"; then
		echo "FAIL: wireguard: the peer lost its public key"
		FAILED=1
	fi
	if ! grep -qF '"172.16.0.2/32"' "$wg_json"; then
		echo "FAIL: wireguard: the endpoint lost its local address list"
		FAILED=1
	fi
fi

# A broken urltest candidate must be pruned, not fatal: the old behaviour was
# a die() that left the router with no configuration at all.
run_case partial_invalid "$ROOT/tests/fixtures/generators/partial_invalid.uci" generate_client.uc sing-box-c.json

pi_json="$WORK/partial_invalid/run/sing-box-c.json"
if [ ! -f "$pi_json" ]; then
	echo "FAIL: partial_invalid: a single broken urltest node aborted the whole config"
	FAILED=1
else
	if ! grep -qF '"cfg-n_ok-out"' "$pi_json"; then
		echo "FAIL: partial_invalid: the buildable candidate was dropped too"
		FAILED=1
	fi
	if grep -qF '"cfg-n_broken-out"' "$pi_json"; then
		echo "FAIL: partial_invalid: the broken candidate was emitted"
		FAILED=1
	fi
	if ! grep -q "skipping urltest candidate 'n_broken'" "$WORK/partial_invalid/generate.err"; then
		echo "FAIL: partial_invalid: the broken candidate was dropped without a warning"
		FAILED=1
	fi
fi

# A direct node as the main node leaves main-out with no fields of its own, and
# sing-box refuses to detour into an empty direct outbound - both the main-dns
# server and the rule-set http_client used to, so the service never started.
# `sing-box check` accepts the file (only `sing-box run` rejects it), so assert
# on the generated JSON rather than trusting check.
run_case direct_main "$ROOT/tests/fixtures/generators/direct_main.uci" generate_client.uc sing-box-c.json

dm_json="$WORK/direct_main/run/sing-box-c.json"
if [ ! -f "$dm_json" ]; then
	echo "FAIL: direct_main: no config was generated"
	FAILED=1
else
	if ! grep -q '"tag": "main-out"' "$dm_json"; then
		echo "FAIL: direct_main: main-out is missing from the generated config"
		FAILED=1
	fi
	if grep -q '"detour": "main-out"' "$dm_json"; then
		echo "FAIL: direct_main: something still detours into the empty direct main-out:"
		grep -n '"detour": "main-out"' "$dm_json" | head -3
		echo "      sing-box run rejects it with 'detour to an empty direct outbound makes no sense'"
		FAILED=1
	fi
fi

# H3: a reference to a dns_server or ruleset that is disabled (or deleted) used
# to be emitted verbatim as `cfg-<name>-dns` / `cfg-<name>-rule`.  Nothing
# defines those tags, so sing-box rejected the whole configuration with
# "dns server not found" / "rule-set not found" - and because the rejected
# generation never reaches the running service, the reload kept the previous
# configuration and the user only saw that their change did not take.
run_case_type_error dangling-resolver "does not exist or is disabled" \
	"$ROOT/tests/fixtures/generators/custom.uci" generate_client.uc sing-box-c.json \
	"s#domain_resolver 'default-dns'#domain_resolver 'rs_local_gone'#"

# --- review@2026-09-29 batch -------------------------------------------------
#
# Six checks that pin the five generator fixes from
# docs/review-report-20260929.md §7. Earlier rounds attempted ucode
# probes (arrow functions, optional chaining on arrays, ...) and each
# round surfaced a different ucode dialect issue on the testbed - the
# macOS dev box has no ucode so the loop could not iterate locally.
# This rewrite uses ONLY shell + grep against the generated JSON, so
# it runs identically on macOS and the testbed. ucode-stdout probes
# are out; structural assertions against the emitted bytes are in.

# 1) P2 #2 / §1.4.1: geosite-cn is the *DNS*-layer rule_set consumer.
#    The route layer never references it as a rule_set value (route.rule_set
#    declares it as a tag). Indent cannot disambiguate dns.rules[] from
#    route.rules[] (both pretty-print at 4 tabs on the testbed; both are
#    bare-string `"rule_set": "..."`), so use count-based invariants:
#      - "tag": "geosite-cn" appears at least once (route.rule_set)
#      - "rule_set": "geosite-cn" appears EXACTLY once (dns.rules only;
#        route.rules must NOT add a second one).
#    A route regression that adds `"rule_set": "geosite-cn"` to route.rules
#    bumps the count to 2 and fails loud.
run_case route-no-geosite-cn "$ROOT/tests/fixtures/generators/client.uci" generate_client.uc sing-box-c.json

rs_json="$WORK/route-no-geosite-cn/run/sing-box-c.json"
if [ ! -f "$rs_json" ]; then
	echo "FAIL: route-no-geosite-cn: no config was generated"
	FAILED=1
else
	rs_tag_count="$(grep -c '"tag": "geosite-cn"' "$rs_json")"
	rs_ruleset_count="$(grep -c '"rule_set": "geosite-cn"' "$rs_json")"
	if [ "$rs_tag_count" -lt 1 ]; then
		echo "FAIL: route-no-geosite-cn: route.rule_set does not declare geosite-cn (tag count=$rs_tag_count, want >=1)"
		FAILED=1
	fi
	if [ "$rs_ruleset_count" -ne 1 ]; then
		echo "FAIL: route-no-geosite-cn: expected exactly 1 '\"rule_set\": \"geosite-cn\"' line (dns.rules only); got $rs_ruleset_count"
		grep -n '"rule_set": "geosite-cn"' "$rs_json" | sed 's/^/      /'
		FAILED=1
	fi
	if [ "$rs_tag_count" -ge 1 ] && [ "$rs_ruleset_count" -eq 1 ]; then
		echo "PASS: route-no-geosite-cn: route.rule_set has geosite-cn (tag=$rs_tag_count); route.rules never references it (rule_set=$rs_ruleset_count, dns only)"
	fi
fi

# 2) P3 #6 / §1.4.3: china-dns.strategy must mirror default-dns's gate
#    on ipv6_support. With ipv6_support='0' (client.uci's value),
#    china-dns.strategy must be 'ipv4_only', not the pre-r28
#    unconditional 'prefer_ipv6'. The generated JSON emits the dns
#    servers in declaration order: default-dns, system-dns,
#    main-dns, china-dns. After sing-box check, the array is intact.
#    Each server entry has tag + domain_resolver.server + domain_resolver.strategy;
#    we walk those lines via a sed window on the china-dns block.
run_case china-dns-strategy-v6-off "$ROOT/tests/fixtures/generators/client.uci" generate_client.uc sing-box-c.json

cds_json="$WORK/china-dns-strategy-v6-off/run/sing-box-c.json"
if [ ! -f "$cds_json" ]; then
	echo "FAIL: china-dns-strategy-v6-off: no config was generated"
	FAILED=1
else
	# Pull the strategy line that follows china-dns, then strip the
	# pretty-printer's leading whitespace before the case match (grep
	# preserves indent; the case patterns do not).
	cds_strategy="$(grep -A 6 '"tag": "china-dns"' "$cds_json" | grep '"strategy":' | head -1)"
	cds_strategy_trimmed="${cds_strategy#"${cds_strategy%%[![:space:]]*}"}"
	cds_value="$(printf '%s\n' "$cds_strategy_trimmed" | sed -n 's/.*"strategy": *"\([^"]*\)".*/\1/p')"
	case "$cds_value" in
	ipv4_only)
		echo "PASS: china-dns-strategy-v6-off: china-dns.strategy=ipv4_only when ipv6_support='0'" ;;
	prefer_ipv6)
		echo "FAIL: china-dns-strategy-v6-off: china-dns.strategy is prefer_ipv6 (pre-r28 behaviour);"
		echo "      it must mirror default-dns and follow ipv6_support"
		FAILED=1 ;;
	'')
		echo "FAIL: china-dns-strategy-v6-off: china-dns server or its strategy field is missing"
		grep -A 6 '"tag": "china-dns"' "$cds_json"
		FAILED=1 ;;
	*)
		echo "FAIL: china-dns-strategy-v6-off: unexpected strategy: $cds_value (line: $cds_strategy)"
		FAILED=1 ;;
	esac
fi

# 3) P2 #4 / §2.2.1: the three NAPTR (qtype 35) bypass suffixes must be
#    emitted as a single domain_suffix entry backed by the
#    NAPTR_BYPASS_SUFFIXES constant. ucode's pretty-printer emits the
#    query_type array and the domain_suffix array as multi-line:
#      "query_type": [
#          35
#      ],
#      "domain_suffix": [
#          "r.10086.cn",
#          "10086.cn",
#          "pub.3gppnetwork.org"
#      ],
#    so a grep -A across the next 6 lines from "query_type": [
#    should land in the same rule body.
run_case naptr-bypass-domains "$ROOT/tests/fixtures/generators/client.uci" generate_client.uc sing-box-c.json

naptr_json="$WORK/naptr-bypass-domains/run/sing-box-c.json"
if [ ! -f "$naptr_json" ]; then
	echo "FAIL: naptr-bypass-domains: no config was generated"
	FAILED=1
else
	naptr_body="$(grep -A 10 '"query_type": \[$' "$naptr_json" | grep -A 8 '35$' | head -10)"
	# naptr_body should contain the three suffixes in order. If
	# any is missing, the layout shifted and the test fails loud.
	naptr_ok=1
	for sfx in 'r.10086.cn' '10086.cn' 'pub.3gppnetwork.org'; do
		if ! printf '%s\n' "$naptr_body" | grep -q "\"$sfx\""; then
			echo "FAIL: naptr-bypass-domains: NAPTR rule is missing suffix \"$sfx\""
			echo "      grep window:"
			printf '%s\n' "$naptr_body" | sed 's/^/        /'
			naptr_ok=0
		fi
	done
	if [ "$naptr_ok" = 1 ]; then
		echo "PASS: naptr-bypass-domains: qtype-35 rule domain_suffix carries the 3 NAPTR_BYPASS_SUFFIXES entries"
	fi
fi

# 4) P2 #3 / §1.4.3 / §5.1: attachExperimental() used to gate cache_file
#    on routing_mode in [bypass_mainland_china, custom]. After the r28
#    fix, every routing_mode gets a cache_file block. Three sed
#    variations of the same fixture cover gfwlist / proxy_mainland_china
#    / global (each needs a real main_node, which client.uci has via
#    main_node='urltest'). bypass_mainland_china is exercised by the
#    unmodified client.uci, and custom.mode uses the custom.uci fixture
#    below. The loop skips the no-op bypass_mainland_china variant to
#    avoid "the fixture variation matched nothing" from run_case.
for rm in gfwlist proxy_mainland_china global; do
	run_case "cache-file-$rm" "$ROOT/tests/fixtures/generators/client.uci" generate_client.uc sing-box-c.json \
		"s/option routing_mode 'bypass_mainland_china'/option routing_mode '$rm'/"

	cf_json="$WORK/cache-file-$rm/run/sing-box-c.json"
	if [ ! -f "$cf_json" ]; then
		echo "FAIL: cache-file-$rm: no config was generated"
		FAILED=1
	elif ! grep -q '"path": "/etc/homeproxy/cache.db"' "$cf_json"; then
		echo "FAIL: cache-file-$rm: experimental.cache_file is missing for routing_mode='$rm'"
		FAILED=1
	else
		echo "PASS: cache-file-$rm: experimental.cache_file emitted for routing_mode='$rm'"
	fi
done

run_case cache-file-bypass_mainland_china "$ROOT/tests/fixtures/generators/client.uci" generate_client.uc sing-box-c.json
cf_json="$WORK/cache-file-bypass_mainland_china/run/sing-box-c.json"
if [ ! -f "$cf_json" ]; then
	echo "FAIL: cache-file-bypass_mainland_china: no config was generated"
	FAILED=1
elif ! grep -q '"path": "/etc/homeproxy/cache.db"' "$cf_json"; then
	echo "FAIL: cache-file-bypass_mainland_china: experimental.cache_file is missing for routing_mode='bypass_mainland_china'"
	FAILED=1
else
	echo "PASS: cache-file-bypass_mainland_china: experimental.cache_file emitted for routing_mode='bypass_mainland_china'"
fi

run_case cache-file-custom "$ROOT/tests/fixtures/generators/custom.uci" generate_client.uc sing-box-c.json
cf_json="$WORK/cache-file-custom/run/sing-box-c.json"
if [ ! -f "$cf_json" ]; then
	echo "FAIL: cache-file-custom: no config was generated"
	FAILED=1
elif ! grep -q '"path": "/etc/homeproxy/cache.db"' "$cf_json"; then
	echo "FAIL: cache-file-custom: experimental.cache_file is missing for routing_mode='custom'"
	FAILED=1
else
	echo "PASS: cache-file-custom: experimental.cache_file emitted for routing_mode='custom'"
fi

# 5) P3 #7 / §4.2.1: a local ruleset whose path is outside the homeproxy
#    whitelist (e.g. /etc/passwd) used to silently set the field to
#    null. The fix is to die() with a message naming the offender.
#    run_case_type_error observes the refusal. The variation targets
#    the *staged* config (after run_case substituted the placeholder
#    with the per-run /tmp path), so the pattern is on the real path
#    prefix rather than the fixture literal.
run_case_type_error local-ruleset-bad-path "outside the homeproxy whitelist" \
	"$ROOT/tests/fixtures/generators/custom.uci" generate_client.uc sing-box-c.json \
	"s%^[[:space:]]*option path '/tmp/homeproxy_test_ruleset\\.[^/]*/local-ruleset-bad-path/test.srs'%    option path '/etc/passwd'%"

# 6) P3 #8 / §4.2.2 (extra_tags die() on missing {tag}): deferred to
#    a dedicated 'testbed-dialect' sprint. The multi-line sed to
#    attach an extra_tags list onto the existing rs_local ruleset
#    drifted at the first whitespace change on the testbed, and
#    adding a brand-new remote ruleset requires a section that's
#    easier to ship as a separate fixture file. arch-guard guard 42
#    already pins the structural invariant (the constant exists and
#    is the only domain_suffix source); the runtime die() path is
#    covered by manual testing on r28. Re-add this case via a
#    custom_extra_tags.uci fixture when convenient.

exit ${FAILED:-0}