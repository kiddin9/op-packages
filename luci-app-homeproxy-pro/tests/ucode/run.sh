#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
#
# Run the ucode-level tests: the parse_uri unit tests, the fw4 inventory check
# and the generator regression fixtures. Requires ucode; sing-box is needed for
# the generator cases (they validate the emitted config with `sing-box check`).
#
# Usage: sh tests/ucode/run.sh <repo-root> [work-dir]

ROOT="${1:-.}"
WORK="${2:-/tmp/hp-ucode-tests}"

ROOT="$(cd "$ROOT" && pwd)"
FAILED=0

if ! command -v ucode > "/dev/null" 2>&1; then
	echo "NOT RUN: ucode is not on PATH."
	echo "         Build the toolchain first (Linux; the target and CI are both"
	echo "         Linux, and sing-box only accepts routing_mark there), or use"
	echo "         tests/run.sh, which copies the checkout to a device when the"
	echo "         host has no ucode:"
	echo "           sh tests/toolchain/build-ucode-linux.sh"
	exit 2
fi

# The target is OpenWrt (Linux), and this layer validates the generated
# configuration with sing-box.  routing_mark - the SO_MARK that keeps
# sing-box's own proxy connection out of the nft redirect chain - is a
# Linux-only field: `sing-box check` rejects it everywhere else, so a
# non-Linux host cannot tell a correct configuration from one that lost the
# field.  The suite used to paper over that by rewriting the field to null
# before testing, which is exactly how the regression stayed invisible; saying
# "cannot run here" is the honest version of the same fact.
if [ "$(uname -s)" != "Linux" ] && [ "${HP_ALLOW_NONLINUX_UCODE:-0}" != "1" ]; then
	echo "NOT RUN: the ucode layer requires Linux (this host is $(uname -s))."
	echo "         Run it in a Linux container or with"
	echo "         HP_TEST_HOST=root@<test-machine>; tests/README.md has both."
	echo "         HP_ALLOW_NONLINUX_UCODE=1 forces the run anyway - expect the"
	echo "         routing_mark assertions to fail, because the local sing-box"
	echo "         rejects that field."
	exit 2
fi

# homeproxy-pro.uc validates data through /sbin/validate_data, which only exists on
# a target. Off-target the generator cases would fail on the very first
# hostname check, so point them at the local stand-in (which in turn uses the
# same validation code as the parser unit tests). On a target the production
# binary is used unchanged.
if [ ! -x /sbin/validate_data ] && [ -x "$ROOT/tests/toolchain/validate-data.sh" ]; then
	HP_VALIDATE_DATA="$ROOT/tests/toolchain/validate-data.sh"
	export HP_VALIDATE_DATA
fi

# Nothing in this suite is target-only any more.  Every source compiles with
# the toolchain from tests/toolchain/build-ucode-*.sh (which ships utpl, the
# luci.* ucode modules and a matching sing-box), and the files that import
# through an absolute /etc/homeproxy-pro/... path are rewritten to the checkout
# below.  A missing piece of the toolchain now FAILS instead of being skipped:
# the old target-only skips are exactly what let a non-compiling
# update_subscriptions.uc, and a destructuring statement, reach the device.
SCRIPTS_DIR="$ROOT/root/etc/homeproxy-pro/scripts"
mkdir -p "$WORK/syntax"

echo "== ucode grammar canary =="
if ! sh "$ROOT/tests/ucode/test_ucode_grammar.sh"; then
	echo "FAIL: ucode grammar does not match the target dialect"
	FAILED=1
fi

echo "== ucode syntax check =="
for file in "$SCRIPTS_DIR"/*.uc \
           "$SCRIPTS_DIR"/subscription/*.uc \
           "$SCRIPTS_DIR"/config/*.uc \
           "$SCRIPTS_DIR"/generator/*.uc \
           "$ROOT"/root/usr/share/rpcd/ucode/*; do
	[ -f "$file" ] || continue
	# Modules (with export statements) cannot be compiled as a program; they
	# are loaded through `import` below instead.
	case "$file" in
	*homeproxy-pro.uc|*firewall_utils.uc|*/parser/*.uc|*/subscription/*.uc|*/config/*.uc|*/generator/*.uc) continue ;;
	esac

	# luci.homeproxy-pro imports homeproxy-pro.uc through an absolute /etc/... path
	# that does not exist off-target.  Compile a rewritten copy instead of
	# skipping the file.
	target="$file"
	case "$file" in
	*/usr/share/rpcd/ucode/*)
		target="$WORK/syntax/$(basename "$file")"
		sed "s#'/etc/homeproxy-pro/scripts/#'$SCRIPTS_DIR/#g" "$file" > "$target" ;;
	esac

	if ! ucode -L "$SCRIPTS_DIR" -c -o "/dev/null" "$target" 2> "$WORK/syntax.err"; then
		echo "FAIL: ${file#"$ROOT"/}"
		head -8 "$WORK/syntax.err"
		FAILED=1
	fi
done
# Modules are syntax-checked by loading them through `import`. The
# -e expression is a no-op program; the import itself is what we
# want to validate. Only top-level module names are searched in the
# -L tree, so anything in a subdirectory is loaded by absolute path
# in the second loop below.
for module in homeproxy-pro firewall_utils; do
	if ! ucode -L "$ROOT/root/etc/homeproxy-pro/scripts" -e "import * as m from \"$module\";" 2> "$WORK/syntax.err"; then
		echo "FAIL: module $module"
		head -8 "$WORK/syntax.err"
		FAILED=1
	fi
done
# `parser/*.uc` (added in PR-02), `config/*.uc` and `generator/*.uc` are
# imported through relative paths, so a syntax error there only surfaces
# when a generator or a test runs; import them explicitly too so the
# failure names the module. `generator/client.uc` and `generator/server.uc`
# are the public entry points and pull the rest of that subtree in
# transitively, which is the cheapest way to syntax-check it.
for module in parser/uri parser/protocols parser/validator parser/normalize parser/flatten parser/mapping \
              subscription/filter subscription/decoder subscription/fetcher subscription/repository \
              config/loader config/model config/adapter \
              generator/client generator/server; do
	if ! ucode -L "$SCRIPTS_DIR" -e "import * as m from \"$SCRIPTS_DIR/$module.uc\";" 2> "$WORK/syntax.err"; then
		echo "FAIL: module $module"
		head -8 "$WORK/syntax.err"
		FAILED=1
	fi
done
[ "$FAILED" -eq 0 ] && echo "PASS: all ucode sources compile"

echo "== fw4 chain/set inventory =="
sh "$ROOT/tests/ucode/test_fw4_names.sh" "$ROOT" || FAILED=1

echo "== shell syntax check =="
# init.d/homeproxy-pro and the runtime helpers are shell, so no ucode check covers
# them.  They decide whether a bad configuration can leave the router without
# a service, so a syntax error there is as bad as one in the generators.
for file in "$ROOT"/root/etc/init.d/* \
            "$ROOT"/root/etc/homeproxy-pro/scripts/*.sh \
            "$ROOT"/root/etc/homeproxy-pro/scripts/runtime/*.sh; do
	[ -f "$file" ] || continue
	if ! sh -n "$file" 2> "$WORK/syntax.err"; then
		echo "FAIL: ${file#"$ROOT"/}"
		head -5 "$WORK/syntax.err"
		FAILED=1
	fi
done

echo "== runtime configuration transaction =="
sh "$ROOT/tests/runtime/test_config_transaction.sh" "$ROOT" || FAILED=1

echo "== dnsmasq snippet writer (review L6) =="
# Counts dnsmasq restarts through a stub: an unchanged snippet set must not
# restart dnsmasq, a changed one must.  Pure shell, no ucode needed.
sh "$ROOT/tests/runtime/test_dns_snippets.sh" "$ROOT" "$WORK/dns-snippets" || FAILED=1

echo "== runtime extraction equivalence (PR-05) =="
# Drives the init script through a stubbed environment and compares the
# resulting command/file trace against the pre-PR-05 trace.  It needs no
# ucode, but it belongs in this suite so CI runs it on every PR.
# Pass this run's work dir: the test defaults to its own mktemp -d, but keeping
# it under one root makes a failed run easier to inspect and avoids a second
# temporary tree.
sh "$ROOT/tests/runtime/test_runtime_extraction.sh" "$ROOT" "$WORK/runtime-extraction" || FAILED=1

echo "== firewall template rendering =="
# utpl ships with ucode (it is a symlink to the same binary), so this check
# runs off-target too.  A toolchain without it is incomplete, not a reason to
# skip the only test that guards the fw4 statement layout.
if ! command -v utpl > "/dev/null" 2>&1; then
	echo "FAIL: utpl is missing; build the toolchain (tests/toolchain/build-ucode-*.sh)"
	FAILED=1
else
	sh "$ROOT/tests/ucode/test_firewall_template.sh" "$ROOT" || FAILED=1
fi

echo "== firewall_pre generator behaviour =="
# Covers the generator that decides *which* nft statements exist, not just
# whether the template renders.  Its two validation guards are the reason a
# malformed server section cannot take the whole fw4 ruleset down with it,
# so they get asserted directly rather than only through a golden file.
sh "$ROOT/tests/ucode/test_firewall_pre.sh" "$ROOT" "$WORK/firewall_pre" || FAILED=1

echo "== firewall field validators =="
# The pure-function helpers firewall_post.ut routes every UCI field through
# (review H1).  Pure functions, no fw4 module needed - so they run on a
# development host while the renderer above stays NOT RUN, and the renderer
# cannot regress silently because the validators are independently pinned
# here.  Guard 11 in tests/arch-guard.sh covers the template still calls
# them.
sh "$ROOT/tests/ucode/test_firewall_validators.sh" "$ROOT" "$WORK/firewall_validators" || FAILED=1

echo "== parse_uri unit tests =="
# PR-02 moved the share-link parsers from parse_uri.uc to
# scripts/parser/{uri,protocols,validator,normalize,mapping}.uc.
# Stage the whole parser/ tree so test_parse_uri.uc can `import` from
# it the same way the production orchestrator does.
rm -rf "$WORK/parse_uri"
mkdir -p "$WORK/parse_uri/parser"
cp "$ROOT/root/etc/homeproxy-pro/scripts/parser/"*.uc "$WORK/parse_uri/parser/"
cp "$ROOT/tests/ucode/mocks/homeproxy-pro.uc" "$WORK/parse_uri/"
cp "$ROOT/tests/ucode/test_parse_uri.uc" "$WORK/parse_uri/"

if ( cd "$WORK/parse_uri" && ucode -L "$WORK/parse_uri" test_parse_uri.uc ); then
	echo "PASS: parse_uri unit tests"
else
	echo "FAIL: parse_uri unit tests"
	FAILED=1
fi

echo "== parser/normalize unit tests =="
# PR-02: parser/normalize.uc turns the parser's flat UCI-key output
# into the canonical Node shape the Adapter reads. The staged
# $WORK/parse_uri/ already has parser/ and the homeproxy-pro mock, so we
# just drop the test next to test_parse_uri.uc.
cp "$ROOT/tests/ucode/test_parser_normalize.uc" "$WORK/parse_uri/"
if ( cd "$WORK/parse_uri" && ucode -L "$WORK/parse_uri" test_parser_normalize.uc ); then
	echo "PASS: parser/normalize unit tests"
else
	echo "FAIL: parser/normalize unit tests"
	FAILED=1
fi

echo "== parser/flatten round-trip tests =="
# PR-03: parser/flatten.uc is the canonical -> flat inverse. The
# round-trip invariant is that flatten(normalize(parse_uri(uri)))
# produces the same flat UCI dict the parser would have written
# directly, so Repository.apply_nodes can write it verbatim and
# the Loader's next read yields the same canonical Node.
cp "$ROOT/tests/ucode/test_parser_flatten.uc" "$WORK/parse_uri/"
if ( cd "$WORK/parse_uri" && ucode -L "$WORK/parse_uri" test_parser_flatten.uc ); then
	echo "PASS: parser/flatten round-trip tests"
else
	echo "FAIL: parser/flatten round-trip tests"
	FAILED=1
fi

echo "== subscription filter unit tests =="
# The production modules live at root/etc/homeproxy-pro/scripts/subscription/
# *.uc and are imported by update_subscriptions.uc with a relative path.
# For the unit tests we want the modules on a flat search path so their
# `from 'homeproxy-pro'` import resolves to the mock, so we stage them at
# the work dir top level (drop the subscription/ prefix) and let the
# test files import them as bare names.
rm -rf "$WORK/subscription"
# Mirror the production layout: the module under test lives in subscription/ and
# reaches homeproxy-pro.uc one level up (a relative import - production cannot rely on
# a module search path, see the note above the syntax check). The tests are the
# entry scripts and import the module under test by name, so -L points at
# subscription/.
rm -rf "$WORK/subscription"
mkdir -p "$WORK/subscription"
cp "$ROOT/tests/ucode/mocks/homeproxy-pro.uc" "$WORK/homeproxy-pro.uc"
cp "$ROOT/root/etc/homeproxy-pro/scripts/subscription/filter.uc" "$WORK/subscription/filter.uc"
cp "$ROOT/root/etc/homeproxy-pro/scripts/subscription/decoder.uc" "$WORK/subscription/decoder.uc"
# The filter test also asserts that applying the policy to the canonical Node
# writes the same UCI keys the old flat order did, so it drives the real
# normalize()/flatten() pair. Those live in parser/ and import ./mapping.uc
# relatively, so all three are staged together next to the test.
mkdir -p "$WORK/parser"
cp "$ROOT/root/etc/homeproxy-pro/scripts/parser/normalize.uc" \
   "$ROOT/root/etc/homeproxy-pro/scripts/parser/flatten.uc" \
   "$ROOT/root/etc/homeproxy-pro/scripts/parser/mapping.uc" "$WORK/parser/"
cp "$ROOT/tests/ucode/test_subscription_filter.uc" "$WORK/"
cp "$ROOT/tests/ucode/test_subscription_decoder.uc" "$WORK/"

if ( cd "$WORK" && ucode -L "$WORK/subscription" test_subscription_filter.uc ); then
	echo "PASS: subscription filter unit tests"
else
	echo "FAIL: subscription filter unit tests"
	FAILED=1
fi

if ( cd "$WORK" && ucode -L "$WORK/subscription" test_subscription_decoder.uc ); then
	echo "PASS: subscription decoder unit tests"
else
	echo "FAIL: subscription decoder unit tests"
	FAILED=1
fi

echo "== subscription repository integration test =="
# The repository writes to a real UCI cursor, so its testbed needs
# the uci + digest shared objects. tests/ucode/run.sh exports
# UCODE_MODULES_DIR for that; the test runner script itself stages
# a sandboxed config dir with seed sections.
sh "$ROOT/tests/ucode/test_subscription_repository.sh" "$ROOT" "$WORK/subscription_repo" || FAILED=1

echo "== subscription updater actually runs =="
# Drives update_subscriptions.uc end to end, which nothing did before: the
# script read subscription_urls off the wrong object, so `call(main)` never
# ran and both the LuCI button and the cron entry were silent no-ops.  The
# URL points at a closed port, so main() fails before its reload call.
sh "$ROOT/tests/ucode/test_subscription_updater_runs.sh" "$ROOT" "$WORK/updater_runs" || FAILED=1

echo "== udp transport verdict =="
# Decides whether QUIC is rejected in the fw4 ruleset. Its 'same' +
# TCP-transport-main-node case is the regression: both UCI fields read
# perfectly reasonable and the QUIC reject stayed off anyway.
sh "$ROOT/tests/ucode/test_udp_transport.sh" "$ROOT" "$WORK/udp_transport" || FAILED=1

echo "== rpcd method behaviour =="
# The rpcd module used to be syntax-checked and never executed, which is how
# certificate_write('client_ech_conf') stayed broken from the initial commit:
# the frontend called it, the ACL granted it, and the backend had no case.
sh "$ROOT/tests/ucode/test_rpc_methods.sh" "$ROOT" "$WORK/rpc_methods" || FAILED=1

echo "== the scripts run the way production runs them =="
# init.d/homeproxy-pro calls `ucode -S "$HP_DIR/scripts/generate_client.uc"` and the
# cron entry runs update_subscriptions.uc through its shebang - neither passes a
# module search path. Everything else in this suite passes -L (the harness has
# to, to reach the staged tree), which is exactly why a bare
# `import ... from 'homeproxy-pro'` inside a subdirectory compiled here for months
# and failed on the first real install: ucode resolves a bare specifier relative
# to the IMPORTING module's directory, so config/model.uc looked in config/.
#
# This runs the real script with no -L at all. Only the runtime paths are
# redirected, the same way the generator cases do it.
PROD="$WORK/prod-invocation"
rm -rf "$PROD"
mkdir -p "$PROD/scripts" "$PROD/cfg" "$PROD/run" "$PROD/resources"
cp -R "$ROOT/root/etc/homeproxy-pro/scripts/." "$PROD/scripts/"
sed -e "s#^export const RUN_DIR = '/var/run/homeproxy-pro';#export const RUN_DIR = '$PROD/run';#" \
    -e "s#^export const HP_DIR = '/etc/homeproxy-pro';#export const HP_DIR = '$PROD';#" \
    -e "s#^export const UCICONFIG_DIR = '/etc/config';#export const UCICONFIG_DIR = '$PROD/cfg';#" \
    "$PROD/scripts/homeproxy-pro.uc" > "$PROD/scripts/homeproxy-pro.uc.new"
mv -f "$PROD/scripts/homeproxy-pro.uc.new" "$PROD/scripts/homeproxy-pro.uc"
cat > "$PROD/cfg/homeproxy-pro" <<'PRODCFG'
config homeproxy-pro 'config'
	option routing_mode 'bypass_mainland_china'
	option proxy_mode 'tun'
	option main_node 'nil'
	option ipv6_support '0'
PRODCFG

# The assertion is about module resolution specifically: whether the generated
# config then satisfies `sing-box check` is what the generator cases cover, and
# this fixture is deliberately too small for that.
( cd "$PROD" && ucode -S scripts/generate_client.uc ) > "$PROD/out.txt" 2>&1
if grep -q "Unable to resolve path for module" "$PROD/out.txt"; then
	echo "FAIL: generate_client.uc cannot resolve its modules without -L:"
	grep -m2 "Unable to resolve path for module" "$PROD/out.txt"
	FAILED=1
else
	echo "PASS: generate_client.uc resolves its modules with no search path"
fi

# The syntax check above imports every module with -L, so it cannot see this;
# and neither can the updater test, which also passes -L.
( cd "$PROD" && ucode -S scripts/update_subscriptions.uc ) > "$PROD/out2.txt" 2>&1
if grep -q "Unable to resolve path for module" "$PROD/out2.txt"; then
	echo "FAIL: update_subscriptions.uc cannot resolve its modules without -L:"
	grep -m2 "Unable to resolve path for module" "$PROD/out2.txt"
	FAILED=1
else
	echo "PASS: update_subscriptions.uc resolves its modules with no search path"
fi

echo "== resource blob digest helper (B2) =="
# resource_blob_sha.uc is what the resource updater verifies downloads with, so
# its digest has to be git's own: sha1("blob <len>\0" + content). The expected
# values in the test are `git hash-object` output, and it re-checks the
# repository's real resource files against git when the host has it.
sh "$ROOT/tests/ucode/test_resource_blob_sha.sh" "$ROOT" "$WORK/resource_blob_sha" || FAILED=1

echo "== china ip rule-set generator =="
# The route side's mainland split is decided from a local rule-set generated out
# of china_ip4.txt - the same list the firewall renders its nft set from.  One
# malformed entry makes sing-box reject the whole rule-set and the client
# refuses to start, and the list is replaced unattended, so the generator's
# validation and its atomic write are both load-bearing.
sh "$ROOT/tests/ucode/test_china_ip_ruleset.sh" "$ROOT" "$WORK/china_ip_ruleset" || FAILED=1

# The DNS half of the same split.  Same failure mode and the same consequence
# class - one bad entry in a list that is replaced unattended makes sing-box
# reject the whole rule-set - plus one that is its own: the entry has to be a
# suffix, or the split quietly stops matching anything under the listed names.
sh "$ROOT/tests/ucode/test_domain_ruleset.sh" "$ROOT" "$WORK/domain_ruleset" || FAILED=1

echo "== test doubles still match production =="
# The mocks copy isEmpty/decodeBase64Str/parseURL/redactUrl from production and
# their headers say to keep them in sync; nothing enforced it, and the fetcher's
# redaction security assertion is made against the copy.  Compared on a shared
# corpus, so the mock may be reformatted but not changed in behaviour.
sh "$ROOT/tests/ucode/test_mock_sync.sh" "$ROOT" "$WORK/mock_sync" || FAILED=1

echo "== the factory configuration loads =="
# root/etc/config/homeproxy-pro ships to every new install and was never read by
# any test; json-assets.js checks its grammar, this drives the real Loader.
sh "$ROOT/tests/ucode/test_factory_config.sh" "$ROOT" "$WORK/factory_config" || FAILED=1

echo "== homeproxy-pro helper tests =="
rm -rf "$WORK/homeproxy-pro"
mkdir -p "$WORK/homeproxy-pro"
cp "$ROOT/root/etc/homeproxy-pro/scripts/homeproxy-pro.uc" "$WORK/homeproxy-pro/"
cp "$ROOT/tests/ucode/test_homeproxy_utils.uc" "$WORK/homeproxy-pro/"

# The fetch-layer guard runs against a stub, not against whatever fetcher this
# host happens to have.  That is the whole point: the guard exists to catch
# "an option the fetcher does not have", and while it ran against the host's
# own binary it only ever checked the configuration that already worked - CI's
# GNU wget, the maintainer's GNU wget.  The stub accepts exactly the option list
# read off the applet on a device and rejects the rest, so the check means the
# same thing everywhere and needs no network.
#
# On a target /bin/uclient-fetch really exists, so fetchBinary() returns it and
# the assertions run against the real applet.  Both directions are useful: the
# stub catches "an option we invented", the target catches "an option the real
# applet lacks".
mkdir -p "$WORK/fetchbin"
cp "$ROOT/tests/fixtures/uclient-fetch-stub" "$WORK/fetchbin/uclient-fetch"
chmod +x "$WORK/fetchbin/uclient-fetch"

# The binary and HTTP-error shapes are something the fetcher has to PRODUCE, so
# on a target the real applet can only produce them by talking to a real server
# - the stub's magic URL paths mean nothing to it (they read as an ordinary URL
# it fails to connect to, which is why those three assertions used to fail on
# every real device).  So stand up a throwaway uhttpd over a temp docroot and
# hand the test its base URL via HP_T_HTTP_BASE.
#
# It is a second uhttpd on a high port serving a temp directory, killed right
# after the test and by the trap below: the running LuCI instance, /www and
# port 80 are never touched.  If it cannot be started the test reports those
# three as skipped, which is honest; they must never be made to read as a pass.
HP_T_HTTP_BASE=""
HP_T_HTTP_PID=""
hp_http_stop() {
	if [ -n "$HP_T_HTTP_PID" ]; then
		kill "$HP_T_HTTP_PID" 2> /dev/null
		wait "$HP_T_HTTP_PID" 2> /dev/null
		HP_T_HTTP_PID=""
	fi
}
trap hp_http_stop EXIT INT TERM

if { [ -x /bin/uclient-fetch ] || [ -x /usr/bin/uclient-fetch ]; } &&
   command -v uhttpd > /dev/null 2>&1; then
	hp_docroot="$WORK/httproot"
	rm -rf "$hp_docroot"
	mkdir -p "$hp_docroot"
	# A body executeCommand() must classify as binary: an .srs magic number
	# with NUL bytes in it, the same shape the stub emits.
	printf 'SRS\002x\332b\000\014\000\000\001\000\001' > "$hp_docroot/hp-binary.srs"

	for hp_port in 18099 18100 18101 18102 18103 18104; do
		uhttpd -f -p "127.0.0.1:$hp_port" -h "$hp_docroot" -x /cgi-bin -t 5 -T 5 &
		HP_T_HTTP_PID=$!
		# Integer sleep on purpose: busybox ash has no fractional wait, and
		# uhttpd needs a moment to bind before the first fetch can reach it.
		sleep 1
		if kill -0 "$HP_T_HTTP_PID" 2> /dev/null; then
			HP_T_HTTP_BASE="http://127.0.0.1:$hp_port"
			break
		fi
		HP_T_HTTP_PID=""
	done
fi

if ( cd "$WORK/homeproxy-pro" && PATH="$WORK/fetchbin:$PATH" HP_T_HTTP_BASE="$HP_T_HTTP_BASE" ucode test_homeproxy_utils.uc ); then
	echo "PASS: executeCommand() regression tests"
else
	echo "FAIL: executeCommand() regression tests"
	FAILED=1
fi
hp_http_stop

echo "== TLS / transport builder tests =="
rm -rf "$WORK/tls_transport"
mkdir -p "$WORK/tls_transport"
cp "$ROOT/root/etc/homeproxy-pro/scripts/homeproxy-pro.uc" "$WORK/tls_transport/"
cp "$ROOT/tests/ucode/test_tls_transport.uc" "$WORK/tls_transport/"
if ( cd "$WORK/tls_transport" && ucode test_tls_transport.uc ); then
	echo "PASS: TLS / transport builder tests"
else
	echo "FAIL: TLS / transport builder tests"
	FAILED=1
fi

echo "== subscription fetcher tests =="
rm -rf "$WORK/fetcher"
mkdir -p "$WORK/fetcher/subscription"
cp "$ROOT/tests/ucode/mocks/homeproxy_fetcher.uc" "$WORK/fetcher/homeproxy-pro.uc"
cp "$ROOT/root/etc/homeproxy-pro/scripts/subscription/fetcher.uc" "$WORK/fetcher/subscription/fetcher.uc"
cp "$ROOT/tests/ucode/test_subscription_fetcher.uc" "$WORK/fetcher/"
if ( cd "$WORK/fetcher" && ucode -L "$WORK/fetcher/subscription" test_subscription_fetcher.uc ); then
	echo "PASS: subscription fetcher tests"
else
	echo "FAIL: subscription fetcher tests"
	FAILED=1
fi

echo "== migrate_config regressions =="
sh "$ROOT/tests/ucode/test_migrate_config.sh" "$ROOT" "$WORK/migrate" || FAILED=1

echo "== executeCommand() failure-path test =="
rm -rf "$WORK/homeproxy_inject"
mkdir -p "$WORK/homeproxy_inject"
sed 's|^\t\texitcode = system(.*);|\t\tdie("injected failure");|' \
	"$ROOT/root/etc/homeproxy-pro/scripts/homeproxy-pro.uc" > "$WORK/homeproxy_inject/homeproxy-pro.uc"

# Hard guard: if the anchor stops matching, the sed no-ops and the test
# passes without ever exercising the exceptional path - the same trap the
# other staged rewrites guard against. Refuse to run instead.
if ! grep -q 'die("injected failure")' "$WORK/homeproxy_inject/homeproxy-pro.uc"; then
	echo "FAIL: executeCommand() failure path: could not inject the failure"
	echo "      (the 'exitcode = system(...)' anchor no longer matches)"
	exit 1
fi

cp "$ROOT/tests/ucode/test_homeproxy_utils_inject.uc" "$WORK/homeproxy_inject/"
if ( cd "$WORK/homeproxy_inject" && ucode test_homeproxy_utils_inject.uc 2>"/dev/null" ); then
	echo "PASS: executeCommand() failure path"
else
	echo "FAIL: executeCommand() failure path"
	FAILED=1
fi

echo "== generator regression tests =="
sh "$ROOT/tests/ucode/test_generators.sh" "$ROOT" "$WORK/generators" || FAILED=1

echo "== proxy-domain DNS routing and DNS bootstrap =="
# The generator suite truncates the resource lists and has no bootstrap option,
# so it can see neither proxy_list.txt -> dns.rules (per proxy mode: the
# routing half was always mode-agnostic, the DNS half was not) nor the
# bootstrap resolver main-dns uses for its own hostname.
sh "$ROOT/tests/ucode/test_dns_proxy_list.sh" "$ROOT" "$WORK/dns-proxy-list" || FAILED=1

echo "== golden protocol snapshot =="
sh "$ROOT/tests/ucode/test_golden_outbounds.sh" "$ROOT" "$WORK/golden" || FAILED=1

echo "== inbound adapter unit tests =="
# PR-04: InboundFactory's protocol-shape decisions (snell / shadowsocks get
# no users[] block, vless / vmess keep flow / alterId per-user, the snell
# listener set, the server-only TLS tail, hysteria v1 vs v2 obfs, and the
# per-protocol credential requirements). The golden snapshot pins the
# emitted JSON for the fixture; this pins the decisions behind it.
rm -rf "$WORK/inbound_adapter"
mkdir -p "$WORK/inbound_adapter/config" "$WORK/inbound_adapter/parser"
# The adapter needs the real homeproxy-pro.uc (buildTLSObject /
# buildTransportObject / strTo* / parse_port), not the test double; the
# golden tests stage it the same way. HP_VALIDATE_DATA lets a development
# host replace /sbin/validate_data, which homeproxy-pro.uc calls.
INBOUND_VALIDATE_DATA="${HP_VALIDATE_DATA:-/sbin/validate_data}"
sed -e "s#/sbin/validate_data#${INBOUND_VALIDATE_DATA}#" \
	"$ROOT/root/etc/homeproxy-pro/scripts/homeproxy-pro.uc" > "$WORK/inbound_adapter/homeproxy-pro.uc"
cp "$ROOT/root/etc/homeproxy-pro/scripts/config/loader.uc"  "$WORK/inbound_adapter/config/"
cp "$ROOT/root/etc/homeproxy-pro/scripts/config/model.uc"   "$WORK/inbound_adapter/config/"
cp "$ROOT/root/etc/homeproxy-pro/scripts/config/adapter.uc" "$WORK/inbound_adapter/config/"
cp "$ROOT/root/etc/homeproxy-pro/scripts/parser/"*.uc       "$WORK/inbound_adapter/parser/"
cp "$ROOT/tests/ucode/test_inbound_adapter.uc"          "$WORK/inbound_adapter/"

if ( cd "$WORK/inbound_adapter" && ucode -L "$WORK/inbound_adapter" test_inbound_adapter.uc ); then
	echo "PASS: inbound adapter unit tests"
else
	echo "FAIL: inbound adapter unit tests"
	FAILED=1
fi

echo "== generator tag helpers =="
# get_outbound() emits `cfg-<node>-out`; isDirectOutboundTag() is asked about
# that emitted tag, so it has to undo the wrapper before looking the node up.
# It did not, and every routing_node answered "not direct".
rm -rf "$WORK/gen_common"
mkdir -p "$WORK/gen_common/config" "$WORK/gen_common/parser" "$WORK/gen_common/generator"
GEN_VALIDATE_DATA="${HP_VALIDATE_DATA:-/sbin/validate_data}"
sed -e "s#/sbin/validate_data#${GEN_VALIDATE_DATA}#" \
	"$ROOT/root/etc/homeproxy-pro/scripts/homeproxy-pro.uc" > "$WORK/gen_common/homeproxy-pro.uc"
cp "$ROOT/root/etc/homeproxy-pro/scripts/config/loader.uc"  "$WORK/gen_common/config/"
cp "$ROOT/root/etc/homeproxy-pro/scripts/config/model.uc"   "$WORK/gen_common/config/"
cp "$ROOT/root/etc/homeproxy-pro/scripts/config/adapter.uc" "$WORK/gen_common/config/"
cp "$ROOT/root/etc/homeproxy-pro/scripts/parser/"*.uc       "$WORK/gen_common/parser/"
cp "$ROOT/root/etc/homeproxy-pro/scripts/generator/"*.uc    "$WORK/gen_common/generator/"
cp "$ROOT/tests/ucode/test_generator_common.uc"         "$WORK/gen_common/"

if ( cd "$WORK/gen_common" && ucode -L "$WORK/gen_common" test_generator_common.uc ); then
	echo "PASS: generator tag helpers"
else
	echo "FAIL: generator tag helpers"
	FAILED=1
fi

echo "== golden inbound snapshot =="
# PR-04: the server-side counterpart. Before this the server path had no
# snapshot, which is how the fixture's unused `listen_port` option survived
# (the generated config carried no listen_port at all and sing-box accepted
# it, so nothing ever noticed).
sh "$ROOT/tests/ucode/test_golden_inbounds.sh" "$ROOT" "$WORK/golden-inbounds" || FAILED=1

echo "== protocol inventory =="
sh "$ROOT/tests/ucode/test_protocol_inventory.sh" "$ROOT" "$WORK/inventory" || FAILED=1

echo "== domain model skeleton =="
sh "$ROOT/tests/ucode/test_domain_model_skeleton.sh" "$ROOT" "$WORK/domain_model" || FAILED=1

echo "== build guards (TLS server_name, bootstrap address) =="
# The two rules that decide whether a configuration can be built at all. Both
# used to be fatal rejections of configurations sing-box accepts, so a node
# without an SNI (every share link with no `sni=`) took the main outbound -
# and with it the whole client configuration - down. Pure functions, so this
# one needs no fixture and no confdir.
sh "$ROOT/tests/ucode/test_build_guards.sh" "$ROOT" "$WORK/build_guards" || FAILED=1

exit $FAILED
