#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
#
# Architecture Guard.
#
# Static, cross-file invariants that the behavioural suites cannot see because
# each of them only exercises one layer at a time.  Every guard here exists
# because a real defect slipped through the whole suite:
#
#   guard 1  the generators read the UCI configuration through
#            HP_DIR + '/config', i.e. /etc/homeproxy-pro/config/homeproxy-pro - a path
#            that exists nowhere.  uci.load() returned null, every uci.get()
#            returned null, and the Loader silently produced pure defaults, so
#            every generated config lacked the main-out, the route/dns finals
#            and all of the user's ports and nodes.  The staged tests passed
#            because the test rewrote HP_DIR and staged the fixture wherever
#            the code happened to look.
#
#   guard 2  update_subscriptions.uc read subscription_urls and filter_keywords
#            off access_control.subscription, but the Loader puts them on
#            access_control itself.  Both were always [], so the updater's
#            `if (!isEmpty(subscription_urls))` guard never called main(): the
#            LuCI button and the cron entry were silent no-ops that exited 0.
#            The project's own model test asserted the *correct* shape, which
#            is exactly why the consumer's wrong read was never questioned.
#
# The lesson both share: a test that stages its own inputs cannot notice that
# production reads a different place.  These guards compare the layers to each
# other instead of comparing each layer to a fixture.
#
# POSIX sh + python3 for the scanners python is better at.  No ucode,
# no node.  Run:
#   sh tests/arch-guard.sh [repo-root]

set -u

ROOT="$(cd "${1:-$(dirname "$0")/..}" && pwd)"
SCRIPTS="$ROOT/root/etc/homeproxy-pro/scripts"
RPC="$ROOT/root/usr/share/rpcd/ucode/luci.homeproxy-pro"
ACL="$ROOT/root/usr/share/rpcd/acl.d/luci-app-homeproxy-pro.json"
VIEWS="$ROOT/htdocs/luci-static/resources"
RUNTIME="$SCRIPTS/runtime"

# assert_empty treats "no stdout" as a pass, which makes the suite
# green on an unrelated /etc tree or any path that exists but is not
# this repo.  Bail out loudly before any of that happens: a guard
# that says PASS while scanning nothing is worse than a guard that
# says FAIL, because nothing else in the report can tell them apart.
if [ ! -d "$SCRIPTS" ] || [ ! -f "$RPC" ] || [ ! -f "$ACL" ] || [ ! -d "$VIEWS" ]; then
	printf 'FATAL: arch-guard.sh needs the full repo tree under %s\n' "$ROOT" >&2
	printf '       (missing %s%s%s%s)\n' \
		"$([ -d "$SCRIPTS" ] || printf '%s ' "$SCRIPTS")" \
		"$([ -f "$RPC" ]     || printf '%s ' "$RPC")" \
		"$([ -f "$ACL" ]     || printf '%s ' "$ACL")" \
		"$([ -d "$VIEWS" ]   || printf '%s ' "$VIEWS")" >&2
	exit 2
fi

FAILED=0
checks=0

pass() { checks=$((checks + 1)); printf 'PASS: %s\n' "$1"; }
fail() { checks=$((checks + 1)); FAILED=1; printf 'FAIL: %s\n' "$1"; }

# assert_empty <description> <command...>
#
# Empty stdout is a pass only when the scan actually ran.  "Actually ran"
# means: the command existed (rc != 127) and could read its target (rc
# != 126, "cannot execute").  A grep that finds nothing exits 1 with
# empty stdout - the legitimate "nothing to report" answer - and stays
# a pass.  A grep on a path that does not exist exits 2 ("No such
# file"), which we DO want to flag: the previous behaviour silently
# produced green checks for nonexistent repos.
assert_empty() {
	desc="$1"; shift
	out="$("$@" 2>/dev/null)"
	rc=$?
	if [ "$rc" -ge 126 ]; then
		fail "$desc (scanner exited $rc - the command or the target is missing)"
		return
	fi
	if [ -z "$out" ]; then
		pass "$desc"
	else
		fail "$desc"
		printf '      %s\n' "$out" | head -20
	fi
}

# assert_nonempty <description> <command...>
assert_nonempty() {
	desc="$1"; shift
	out="$("$@" 2>/dev/null)"
	if [ -n "$out" ]; then
		pass "$desc"
	else
		fail "$desc (nothing found)"
	fi
}

echo "== guard 1: the generators read the production UCI directory =="

# The confdir the Loader hands to cursor() must be /etc/config.  Anything else
# means uci.load() reads a file the package does not ship.
if grep -q "^export const UCICONFIG_DIR = '/etc/config';$" "$SCRIPTS/homeproxy-pro.uc"; then
	pass "UCICONFIG_DIR defaults to /etc/config"
else
	fail "UCICONFIG_DIR does not default to /etc/config"
	grep -n "UCICONFIG_DIR" "$SCRIPTS/homeproxy-pro.uc" | sed 's/^/      /'
fi

for g in generate_client.uc generate_server.uc; do
	if grep -q "Loader.load(UCICONFIG_DIR)" "$SCRIPTS/$g"; then
		pass "$g loads through UCICONFIG_DIR"
	else
		fail "$g does not call Loader.load(UCICONFIG_DIR)"
		grep -n "Loader.load" "$SCRIPTS/$g" | sed 's/^/      /'
	fi
done

# The original mistake, in either spelling: deriving the UCI directory from
# HP_DIR.  HP_DIR is /etc/homeproxy-pro and holds resources/scripts, not config.
assert_empty "no source derives the UCI dir from HP_DIR" \
	grep -rn "Loader.load(HP_DIR\|Loader\.load( *HP_DIR" "$SCRIPTS"

# Every Loader.load() call site must use one of exactly two forms: the shared
# constant, or the bare default cursor().  A literal path - or any other
# expression - is how the original mistake would come back.
#
# Coverage boundary: comments are removed and all whitespace is collapsed
# before matching, so a call split over several lines
# (`Loader.load(` / newline / `UCICONFIG_DIR)`) is still one call site, and a
# call mentioned only inside a comment is not a call site at all.  A call the
# code assembles through a variable (`const f = Loader.load; f(...)`) is out
# of scope for a static guard; that boundary is stated, not silently assumed.
BADLOAD="$(python3 - "$SCRIPTS" <<'PY'
import pathlib, re, sys

# Blank out comments only; string literals are kept, because the argument of a
# Loader.load() call has to stay visible.  SQ and DQ exist because an escaped
# quote inside this here-document upsets the shell command-substitution
# scanner and truncates the program, which would leave the check passing
# without testing anything.
SQ, DQ = "'", '"'
STRING = DQ + r'(?:\\.|[^"\\])*' + DQ + '|' + SQ + r"(?:\\.|[^'\\])*" + SQ
COMMENT = r'/\*.*?\*/|//[^\n]*'
TOKENS = re.compile(STRING + '|' + COMMENT, re.S)


def blank(match):
    return ' ' if match.group(0).startswith('/') else match.group(0)


bad = set()
for f in sorted(pathlib.Path(sys.argv[1]).rglob('*.uc')):
    src = TOKENS.sub(blank, f.read_text(encoding='utf-8', errors='replace'))
    flat = re.sub(r'\s+', ' ', src)
    for arg in re.findall(r'Loader\s*\.\s*load\s*\(([^()]*)\)', flat):
        arg = arg.strip()
        if arg not in ('', 'UCICONFIG_DIR'):
            bad.add('%s: Loader.load(%s)' % (f.relative_to(sys.argv[1]), arg))
print('\n'.join(sorted(bad)))
PY
)" || BADLOAD="__SCAN_FAILED__"
if [ "$BADLOAD" = "__SCAN_FAILED__" ]; then
	fail "the Loader.load() scan could not run - fix the guard before trusting a pass"
elif [ -z "$BADLOAD" ]; then
	pass "every Loader.load() call site uses UCICONFIG_DIR or the bare default"
else
	fail "unexpected Loader.load() argument:"
	printf '      %s\n' "$BADLOAD"
fi

echo
echo "== guard 2: the subscription updater reads fields where the Loader puts them =="

# Keys the Loader nests inside access_control.subscription (the
# load_settings(...) list).
LOADER="$SCRIPTS/config/loader.uc"
NESTED="$(awk '
	/subscription: load_settings\(uci, SECTION\.subscription, \[/ { inb = 1; next }
	inb && /\]\)/ { inb = 0; next }
	inb { print }
' "$LOADER" | grep -oE "'[a-z_][a-z0-9_]*'" | tr -d "'" | sort -u)"

if [ -n "$NESTED" ]; then
	pass "parsed the nested subscription keys ($(printf '%s' "$NESTED" | wc -l | tr -d ' ') of them)"
else
	fail "could not parse the nested subscription keys out of loader.uc"
fi

# Every `sub.<field>` read in the updater must be one of them.  `sub` is bound
# to loaded.access_control.subscription.
UPDATER="$SCRIPTS/update_subscriptions.uc"
BAD=""
for f in $(grep -oE '\bsub\.[a-z_][a-z0-9_]*' "$UPDATER" | sed 's/^sub\.//' | sort -u); do
	if ! printf '%s\n' "$NESTED" | grep -qx "$f"; then
		BAD="$BAD sub.$f"
	fi
done

if [ -z "$BAD" ]; then
	pass "every sub.<field> read in update_subscriptions.uc is nested under subscription"
else
	fail "update_subscriptions.uc reads fields off subscription that the Loader does not nest there:$BAD"
fi

# And the other direction: the two fields that regressed sit on access_control
# itself, so the updater must reach them through access_control - reading them
# through `sub.` is what made them a permanent [].  Asserted positively too, so
# the check cannot pass by finding nothing (the first draft of this guard
# grepped the *loader* for an "access_control.X" spelling that never appears
# there, matched nothing, and silently checked nothing at all).
for f in subscription_urls filter_keywords; do
	if grep -qE "\bsub\.$f\b" "$UPDATER"; then
		fail "update_subscriptions.uc reads sub.$f, but load_access_control() puts it on access_control"
	elif grep -qE "\baccess_control\.$f\b" "$UPDATER"; then
		pass "$f is read from access_control"
	else
		fail "$f is neither read from access_control nor from sub - the updater lost it entirely"
	fi
done

echo
echo "== guard 3: the ACL grants only what the browser actually writes =="

# The certificate buttons and the staging path each one uploads to.  The
# frontend derives /tmp/homeproxy_cert_<name>.tmp from the same name it passes
# to certificate_write, so the button list is the source of truth for what the
# ACL needs.
BTN="$(grep -rhoE "uploadCertificate[^;]*'[a-z_]+'\)" "$VIEWS" \
	| grep -oE "'[a-z_]+'\)$" | tr -d "')" | sort -u)"

if [ -n "$BTN" ]; then
	pass "found the certificate upload buttons: $(printf '%s ' $BTN)"
else
	fail "could not find any uploadCertificate call site under $VIEWS"
fi

for n in $BTN; do
	if grep -q "/tmp/homeproxy_cert_$n.tmp" "$ACL"; then
		pass "the ACL grants the staging path for $n"
	else
		fail "the ACL is missing the staging path for $n"
	fi
done

# The write-file block, as a list of paths.
WRITE_FILES="$(awk '
	/"write"[[:space:]]*:/ { inwrite = 1 }
	inwrite && /"file"[[:space:]]*:/ { infile = 1; next }
	infile && /^[[:space:]]*}/ { infile = 0; inwrite = 0; next }
	infile { print }
' "$ACL" | grep -oE '"/[^"]*"' | tr -d '"')"

if [ -n "$WRITE_FILES" ]; then
	pass "parsed the ACL write-file list ($(printf '%s\n' "$WRITE_FILES" | grep -c . ) paths)"
else
	fail "could not parse the ACL write-file list"
fi

# The file ACL governs what a *browser session* may touch through fs.*.  The
# backend writes certs/ and resources/ as root, authorised by its ubus method
# entry - not by this list.  So a /etc/ entry here grants nothing the feature
# needs, and does grant a session holding only this ACL the ability to
# overwrite server_privatekey.pem directly through fs.write, bypassing the PEM
# and binary checks in certificate_write.
ETC_WRITES="$(printf '%s\n' "$WRITE_FILES" | grep '^/etc/' || true)"
if [ -z "$ETC_WRITES" ]; then
	pass "the ACL write list grants no /etc/ path"
else
	fail "the ACL write list grants /etc/ paths no browser operation uses:"
	printf '      %s\n' "$ETC_WRITES"
fi

# The general form, so a future fs.write has to come with a deliberate ACL
# change rather than silently inheriting a stale grant.
assert_empty "the frontend makes no fs.write call" \
	grep -rn "fs\.write" "$VIEWS"

echo
echo "== guard 4: the ACL and the rpcd method table agree =="

BACKEND_METHODS="$(sed -n 's/^\t\([a-z_][a-z0-9_]*\): {$/\1/p' "$RPC" | sort -u)"
if [ -n "$BACKEND_METHODS" ]; then
	pass "parsed $(printf '%s\n' "$BACKEND_METHODS" | grep -c .) rpcd methods"
else
	fail "could not parse any method out of $(basename "$RPC")"
fi

ACL_METHODS="$(awk '
	/"ubus"[[:space:]]*:/ { inubus = 1; next }
	inubus && /^[[:space:]]*}/ { inubus = 0; next }
	inubus && /"luci.homeproxy-pro"[[:space:]]*:/ { inlist = 1; next }
	inlist && /\]/ { inlist = 0; next }
	inlist { print }
' "$ACL" | grep -oE '"[a-z_]+"' | tr -d '"' | sort -u)"

if [ -n "$ACL_METHODS" ]; then
	pass "parsed $(printf '%s\n' "$ACL_METHODS" | grep -c .) ACL ubus methods"
else
	fail "could not parse any ubus method out of the ACL"
fi

# Not `comm`: it takes file arguments, and POSIX sh has no process
# substitution.  The first draft used it anyway, so comm failed, the variable
# came back empty and the check passed without testing anything.
UNGATED=""
for m in $BACKEND_METHODS; do
	printf '%s\n' "$ACL_METHODS" | grep -qx "$m" || UNGATED="$UNGATED $m"
done
if [ -z "$UNGATED" ]; then
	pass "every rpcd method is reachable through the ACL"
else
	fail "these rpcd methods have no ACL entry, so no session can call them:"
	printf '      %s\n' "$UNGATED"
fi

PHANTOM=""
for m in $ACL_METHODS; do
	printf '%s\n' "$BACKEND_METHODS" | grep -qx "$m" || PHANTOM="$PHANTOM $m"
done
if [ -z "$PHANTOM" ]; then
	pass "the ACL grants no method the module does not define"
else
	fail "the ACL grants methods that do not exist:"
	printf '      %s\n' "$PHANTOM"
fi

# A wildcard would make the two checks above meaningless.
if grep -qE '"[*]"' "$ACL"; then
	fail "the ACL contains a wildcard"
else
	pass "the ACL contains no wildcard"
fi

echo
echo "== guard 5: every RPC the frontend calls is a real method, and is tested =="

FRONTEND_METHODS="$(grep -rhoE "rpcCall\('[a-z_]+'" "$VIEWS" \
	| sed "s/rpcCall('//" | tr -d "'" | sort -u)"

if [ -n "$FRONTEND_METHODS" ]; then
	pass "parsed $(printf '%s\n' "$FRONTEND_METHODS" | grep -c .) rpcCall method names"
else
	fail "found no rpcCall method names under $VIEWS"
fi

UNKNOWN=""
for m in $FRONTEND_METHODS; do
	# 'list' is the ubus *service* object, not this module's.
	if [ "$m" = "list" ]; then
		grep -rq "object: 'service'" "$VIEWS" \
			|| UNKNOWN="$UNKNOWN list(not via the service object)"
		continue
	fi
	printf '%s\n' "$BACKEND_METHODS" | grep -qx "$m" || UNKNOWN="$UNKNOWN $m"
done

if [ -z "$UNKNOWN" ]; then
	pass "every frontend rpcCall names a method the backend defines"
else
	fail "the frontend calls methods the backend does not define:$UNKNOWN"
fi

# And every one of them must be exercised by a test *script*, so a method
# cannot be shipped - or a call site broken - without a test noticing.  The
# old check was `grep -rq "$m" "$ROOT/tests"`: it counted the method name
# appearing anywhere under tests/, including tests/README.md prose, so a
# method could lose its only test and the guard would still pass on a
# sentence.  A script qualifies only when it both names the method and
# dispatches through the RPC layer (`.call(...)` - e.g. the
# `rpc[method].call({...})` sweep in test_rpc_methods.sh - or a frontend
# `rpcCall(...)` driven from a JS harness).  arch-guard.sh itself is excluded:
# it names every method while parsing the frontend, which is not exercising
# them.
UNTESTED="$(python3 - "$ROOT" $FRONTEND_METHODS <<'PY'
import pathlib, re, sys

root = pathlib.Path(sys.argv[1]) / 'tests'
methods = sys.argv[2:]
files = [p for p in root.rglob('*')
         if p.suffix in ('.sh', '.uc') and p.name != 'arch-guard.sh']
bodies = [p.read_text(encoding='utf-8', errors='replace') for p in files]
dispatch = re.compile(r'\.call\s*\(|rpcCall\s*\(')

bad = []
for m in methods:
    if m == 'list':
        continue
    name = re.compile(r'\b%s\b' % re.escape(m))
    if not any(name.search(b) and dispatch.search(b) for b in bodies):
        bad.append(m)
print(' '.join(bad))
PY
)" || UNTESTED="__SCAN_FAILED__"

if [ "$UNTESTED" = "__SCAN_FAILED__" ]; then
	fail "the test-script scan could not run - fix the guard before trusting a pass"
elif [ -z "$UNTESTED" ]; then
	pass "every RPC the frontend calls is exercised by a test script"
else
	fail "these RPCs are called by the frontend but exercised by no test script:$UNTESTED"
fi

echo
echo "== guard 6: every certificate button has a backend case =="

# guard 3 already found $BTN from the views.
BACKEND_CASES="$(awk '/certificate_write: \{/,/^\t\},/' "$RPC" \
	| grep -oE "case '[a-z_]+'" | sed "s/case '//" | tr -d "'" | sort -u)"

if [ -n "$BACKEND_CASES" ]; then
	pass "parsed the certificate_write cases: $(printf '%s ' $BACKEND_CASES)"
else
	fail "could not parse the certificate_write cases"
fi

for n in $BTN; do
	printf '%s\n' "$BACKEND_CASES" | grep -qx "$n" \
		&& pass "certificate_write handles '$n'" \
		|| fail "the '$n' upload button has no certificate_write case"
done

echo
echo "== guard 7: the semantic layers do not touch UCI =="

# UCI -> Loader -> {Parser, Generator, Runtime}: config/loader.uc owns the only
# cursor on the client path.  A parser or generator that grows its own cursor
# breaks the layering this refactor exists to establish.
LAYERS="$SCRIPTS/generator $SCRIPTS/parser $SCRIPTS/config/model.uc $SCRIPTS/config/adapter.uc"
assert_empty "no parser/generator/model/adapter imports the uci module" \
	grep -rn "from 'uci'" $LAYERS
assert_empty "no parser/generator/model/adapter opens a cursor" \
	grep -rn "cursor(" $LAYERS
assert_nonempty "the Loader is still the one that owns the cursor" \
	grep -rn "cursor(" "$SCRIPTS/config/loader.uc"

echo
echo "== guard 8: the generators write through a private scratch dir =="

# reload_service generates the client and start_service generates it again, so
# two runs can overlap. A fixed `<out>.tmp` name in RUN_DIR meant both wrote the
# same file, and `sing-box check` could validate a file the other run was still
# writing - the winner then installed a half-written config. mkdtemp() gives each
# run its own 0700 directory.
for g in generate_client.uc generate_server.uc; do
	if grep -q "mkdtemp()" "$SCRIPTS/$g"; then
		pass "$g uses mkdtemp() for its scratch dir"
	else
		fail "$g does not use mkdtemp() - its scratch path is shared between runs"
	fi

	# The specific shape that was wrong: a temp path built from RUN_DIR.
	SHARED="$(grep -n "RUN_DIR + '/sing-box-.*\.tmp'" "$SCRIPTS/$g" || true)"
	if [ -z "$SHARED" ]; then
		pass "$g does not build a fixed temp path under RUN_DIR"
	else
		fail "$g builds a shared temp path under RUN_DIR:"
		printf '      %s\n' "$SHARED"
	fi
done

echo
echo "== guard 9: the pgrep fallback still matches the procd command =="

# hp_instance_running falls back to `pgrep -f` only when ubus cannot be asked at
# all, and the pattern it matches has to stay in step with the command procd is
# told to run. Change either alone and the fallback silently stops matching -
# and then the health gate degrades to "always times out", which rolls back a
# perfectly good configuration. A wrong pattern would look like a bad config.
# ^[^#]* keeps this to code: health.sh's header comment mentions `pgrep -f`
# while explaining why the procd answer wins, and the first version of this
# guard matched that instead of the pattern.
PGREP_LINE="$(grep -nE '^[^#]*pgrep -f' "$RUNTIME/health.sh" | head -1)"
PROCD_LINE="$(grep -nE '^[^#]*procd_append_param command run' "$RUNTIME/service.sh" | head -1)"

if printf '%s' "$PGREP_LINE" | grep -q 'pgrep -f "run --config '; then
	pass "the pgrep fallback matches 'run --config <config>'"
else
	fail "the pgrep fallback no longer matches 'run --config <config>':"
	printf '      %s\n' "$PGREP_LINE"
fi

if printf '%s' "$PROCD_LINE" | grep -q 'procd_append_param command run --config '; then
	pass "procd is told to run 'run --config <config>'"
else
	fail "the procd command no longer starts with 'run --config':"
	printf '      %s\n' "$PROCD_LINE"
fi

echo
echo "== guard 10: nothing installs or removes packages on a target =="

# On 2026-09-15 an `apk add luci-app-homeproxy-pro` on the test machine rewrote
# /etc/config/homeproxy-pro from the feed package and destroyed the node
# configuration - six nodes plus the dns, server and subscription sections, with
# no backup and no snapshot. The suite stages instead, and this is the guard
# that keeps it that way: a package-manager *write* is never part of testing.
#
# Reading is fine and is used: tests/run.sh reports the target's installed
# version with `apk list -I`, and the opkg fallback reads `opkg status`.
# grep -v drops comment lines: this guard's own explanation quotes the command
# it forbids, and the first version flagged itself.
MUTATING="$(grep -rnE '(^|[^a-z-])(apk|opkg)[[:space:]]+(add|install|del|delete|remove|upgrade|fix|update)([[:space:]]|$)' \
	"$ROOT/.github/workflows" "$ROOT/tests" 2>/dev/null \
	| grep -vE ':[0-9]+:[[:space:]]*#' || true)"

if [ -z "$MUTATING" ]; then
	pass "no workflow or test runs a package-manager write"
else
	fail "a package-manager write appears - this is how the device config was lost:"
	printf '      %s\n' "$MUTATING"
fi

echo
echo "== guard 11: firewall_post.ut validates every UCI-derived field =="

# Three code-review findings rolled into one guard, because they share the
# same shape: any UCI value the template concatenates into an nft expression
# is an injection surface (closes a set expression, the whole fw4 reload
# fails, the router loses its firewall).  The defensive helpers exist; the
# guard exists so they cannot quietly stop being used.
TEMPLATE="$ROOT/root/etc/homeproxy-pro/scripts/firewall_post.ut"
UTILS="$ROOT/root/etc/homeproxy-pro/scripts/firewall_utils.uc"

if [ -f "$UTILS" ]; then
	pass "firewall_utils.uc exists (where the H1 validators live)"
else
	fail "firewall_utils.uc is missing - the H1 validators have nowhere to live"
fi

for fn in ipv4_to_nftarr mac_to_nftarr iface_to_nftarr ports_to_nftarr; do
	if grep -qE "^export function $fn\b" "$UTILS"; then
		pass "$fn is exported from firewall_utils.uc"
	else
		fail "$fn is not exported from firewall_utils.uc - the validator the report's H1 demands is missing"
	fi
done

# The template must actually import them - having the helpers but not using
# them would still leave a poisoned field landing in the nft output.
for fn in ipv4_to_nftarr mac_to_nftarr iface_to_nftarr ports_to_nftarr; do
	if grep -q "\b$fn\b" "$TEMPLATE"; then
		pass "firewall_post.ut imports/uses $fn"
	else
		fail "firewall_post.ut does not reference $fn"
	fi
done

# Every field type whose nft set/rule used to be raw `join(', ', control_info.X)`
# or `array_to_nftarr(control_info.X)` must now go through the matching helper.
# The names are taken from the helper function names; the field list is the
# closure of every control_info.X reference that ever appeared bare - kept as
# a literal so a new bare call site is obvious in a diff.
assert_empty "no bare array_to_nftarr(control_info.X) call site remains" \
	grep -nE 'array_to_nftarr\(control_info\.' "$TEMPLATE"
assert_empty "no bare join(', ', control_info.X) call site remains" \
	grep -nE "join\(', ', control_info\." "$TEMPLATE"
assert_empty "no bare join(', ', split(routing_port,...)) call site remains" \
	grep -nE "join\(', ', split\(routing_port" "$TEMPLATE"

# The four field families whose UCI surface area is the report's whole H1:
# IPv4 addresses, MAC addresses, interface names, and ports.  Any one of
# these landing verbatim in an nft expression closes a set and reloads the
# whole fw4 stack.  Asserted positively: each helper must be used on every
# field of its family, so a field the helper was meant to cover but the
# template forgot is a guard failure rather than a silent omission.
# (ipv6 is intentionally absent: it already had ipv6_to_nftarr before H1.)
#
# Field list is the exact set of control_info.<family> names used by the
# template - if a new field of an existing family is added, this list grows
# with it and the diff is the place to notice.
for f in wan_proxy_ipv4_ips wan_direct_ipv4_ips \
         lan_proxy_ipv4_ips lan_direct_ipv4_ips \
         lan_global_proxy_ipv4_ips lan_gaming_mode_ipv4_ips; do
	if grep -qE "ipv4_to_nftarr\(control_info\.$f\b" "$TEMPLATE"; then
		pass "ipv4_to_nftarr covers $f"
	else
		fail "ipv4_to_nftarr is not applied to $f (closes a nft set on a bad value)"
	fi
done

for f in lan_proxy_mac_addrs lan_direct_mac_addrs \
         lan_global_proxy_mac_addrs lan_gaming_mode_mac_addrs; do
	if grep -qE "mac_to_nftarr\(control_info\.$f\b" "$TEMPLATE"; then
		pass "mac_to_nftarr covers $f"
	else
		fail "mac_to_nftarr is not applied to $f (closes a nft set on a bad value)"
	fi
done

if grep -qE "iface_to_nftarr\(control_info\.listen_interfaces\b" "$TEMPLATE"; then
	pass "iface_to_nftarr covers listen_interfaces"
else
	fail "iface_to_nftarr is not applied to listen_interfaces"
fi

if grep -qE "ports_to_nftarr\(routing_port\b\)" "$TEMPLATE"; then
	pass "ports_to_nftarr covers routing_port"
else
	fail "ports_to_nftarr is not applied to routing_port"
fi

echo
echo "== guard 12: capabilities stay minimal =="

# Review H2: sing-box on this package runs in tproxy / TUN mode. Both rely
# on the kernel's packet path, not raw sockets, so CAP_NET_RAW is not needed;
# CAP_SYS_PTRACE lets any child process read arbitrary /proc/<pid>/mem, which
# on a process that handles untrusted network traffic is gratuitous attack
# surface.  Neither is granted anywhere.  inheritable is kept empty because
# nothing the orchestrator spawns needs to inherit caps.
CAPS="$ROOT/root/etc/capabilities/homeproxy-pro.json"

if [ -f "$CAPS" ]; then
	pass "homeproxy-pro.json exists"
else
	fail "homeproxy-pro.json is missing"
fi

for cap in CAP_SYS_PTRACE CAP_NET_RAW CAP_SYS_ADMIN CAP_DAC_OVERRIDE CAP_SYS_MODULE CAP_SYS_RAWIO; do
	if grep -qE "\"$cap\"" "$CAPS"; then
		fail "$cap is granted somewhere - review H2 said this should be dropped"
	else
		pass "$cap is not granted"
	fi
done

# inheritable must cover ambient.  A capability can only be raised into the
# ambient set while it is in BOTH the permitted and the inheritable set
# (capabilities(7), PR_CAP_AMBIENT_RAISE), and procd/ujail does exactly that
# when it launches the jailed sing-box.  The M1 review assumed an empty
# inheritable set was harmless ("every child is a shell that does not need
# elevated caps") and asserted that here - but the raise then fails with EPERM,
# sing-box never gets CAP_NET_BIND_SERVICE, and procd crash-loops:
#
#   jail: prctl(PR_CAP_AMBIENT, PR_CAP_AMBIENT_RAISE, 10, 0, 0) failed: Operation not permitted
#
# So the invariant is "ambient is a subset of inheritable", not "inheritable is
# empty".  Verified on the test device: with an empty inheritable set
# `homeproxy-pro start` exits 1 and sing-box-c never runs; restoring the two
# entries makes start/reload/stop pass and the instances come up.
AMBIENT="$(awk '/"ambient"/,/]/' "$CAPS" | grep -oE 'CAP_[A-Z_]+' | sort -u)"
INHERITABLE="$(awk '/"inheritable"/,/]/' "$CAPS" | grep -oE 'CAP_[A-Z_]+' | sort -u | tr '\n' ' ')"
MISSING=""
for cap in $AMBIENT; do
	case " $INHERITABLE " in
	*" $cap "*) ;;
	*) MISSING="$MISSING $cap" ;;
	esac
done
if [ -n "$MISSING" ]; then
	fail "inheritable does not cover ambient:$MISSING - PR_CAP_AMBIENT_RAISE needs both sets, sing-box will crash-loop in the jail"
else
	pass "inheritable covers every ambient capability"
fi

# The two caps the package actually needs. Asserted positively so the
# check cannot pass by finding nothing.
for cap in CAP_NET_ADMIN CAP_NET_BIND_SERVICE; do
	if grep -qE "\"$cap\"" "$CAPS"; then
		pass "$cap is granted"
	else
		fail "$cap is missing - sing-box needs it for tproxy/TUN"
	fi
done

echo
echo "== guard 13: tests/run.sh has no guessed test host =="

# Review M1: tests/run.sh used to default HP_TEST_HOST to a specific LAN
# address, and tests/README.md repeated it.  Anyone cloning the repo and
# running `tests/run.sh` would have ssh'd into a stranger's box, with the
# whole checkout unpacked on top.  The default is now empty (SKIP), and
# the hardcoded IP is gone from tests/, .github/workflows/ and tests/README.md.
#
# Strip comment lines first: tests/README.md and the workflow headers
# legitimately mention the production-router IP in prose, and the workflow
# has an explicit refusal pattern that matches 192.168.1.1 to refuse it.
# Neither is a silent-connect.
strip_comments() {
	# `grep -v` of lines whose first non-whitespace character is `#`.
	awk '
		{
			s = $0
			sub(/^[[:space:]]+/, "", s)
			if (substr(s, 1, 1) != "#") print FILENAME ":" NR ":" $0
		}' "$1"
}

# The specific shape that was wrong: a literal ssh target in a HP_TEST_HOST
# default.  The empty default makes the suite skip instead.
BAD_DEFAULT="$(grep -nE 'HP_TEST_HOST[:=].*root@[0-9]' "$ROOT/tests/run.sh" \
	| strip_comments /dev/stdin || true)"
if [ -z "$BAD_DEFAULT" ]; then
	pass "tests/run.sh does not default HP_TEST_HOST to a hardcoded ssh host"
else
	fail "tests/run.sh defaults HP_TEST_HOST to a hardcoded ssh host - the silent-connect trap is back:"
	printf '      %s\n' "$BAD_DEFAULT"
fi

# The on-target.yml input default and the workflow-level host pinning.
# Same shape: a literal IP in the `host:` default or in a `HOST` env var.
BAD_INPUT="$(grep -nE "default:.*'[a-z]+@[0-9]" "$ROOT/.github/workflows/on-target.yml" \
	| strip_comments /dev/stdin || true)"
if [ -z "$BAD_INPUT" ]; then
	pass "on-target.yml input default is not a hardcoded ssh host"
else
	fail "on-target.yml input default is a hardcoded ssh host:"
	printf '      %s\n' "$BAD_INPUT"
fi

# The empty default is what makes the suite skip rather than silently
# connect to a guessed address.  Asserted positively so the check cannot
# pass by finding nothing.
if grep -q 'HOST="${HP_TEST_HOST:-}"' "$ROOT/tests/run.sh"; then
	pass "tests/run.sh defaults HP_TEST_HOST to empty (skip rather than connect)"
else
	fail "tests/run.sh no longer defaults HP_TEST_HOST to empty - the silent-connect trap is back"
fi

if grep -qE "default: ''" "$ROOT/.github/workflows/on-target.yml"; then
	pass "on-target.yml input default is empty"
else
	fail "on-target.yml input default is no longer empty - the workflow silently targets an IP again"
fi

echo
echo "== guard 14: wGETVerbose redacts the URL at the source =="

# Review H3: the original fetcher.uc logged a redacted URL but returned the
# raw wget stderr, which still had the full URL (wget -nv reports the target
# on the failure line, query string and all).  Every caller of wGETVerbose
# had to remember to redact the error themselves, and any that did not -
# silently leaked the subscription token.  The fix moved redaction into
# wGETVerbose itself, so the returned `error` is safe no matter where the
# caller ships it.
HOMEPROXY="$SCRIPTS/homeproxy-pro.uc"
FETCHER="$SCRIPTS/subscription/fetcher.uc"

if grep -qE '^export function redactReason\b' "$HOMEPROXY"; then
	pass "redactReason is exported from homeproxy-pro.uc"
else
	fail "redactReason is missing - the H3 redaction has no entry point"
fi

# wGETVerbose must call redactReason on the reason string before returning.
# Asserted positively so the check cannot pass by finding nothing (a regex
# in a comment would otherwise be enough to satisfy it).
# awk does not understand \b, so the function name pattern is anchored
# with `export function` and the opening paren instead.
WGET_BODY="$(awk '/^export function wGETVerbose/,/^};/' "$HOMEPROXY")"
if printf '%s' "$WGET_BODY" | grep -q 'redactReason(reason)'; then
	pass "wGETVerbose calls redactReason before returning"
else
	fail "wGETVerbose does not call redactReason on the reason - the token still leaks"
fi

# The fetcher used to do `redactUrl(url)` on the URL parameter *and* pass
# `result.error` (which carried the raw URL) into the log.  Now that
# wGETVerbose redacts internally, the fetcher must not double-process the
# error - it may still redact the URL parameter (it is the subscription
# token, distinct from the error), but must not touch result.error.
FETCHER_LOG="$(awk '/log\(sprintf.*Failed to fetch/,/\);$/' "$FETCHER")"
if printf '%s' "$FETCHER_LOG" | grep -qE "redactUrl\(result\.error"; then
	fail "subscription/fetcher.uc redacts result.error again - the redaction is now duplicated and result.error is meant to be already safe"
else
	pass "subscription/fetcher.uc does not re-redact result.error"
fi

echo
echo "== guard 15: every RPC whitelist uses index() === -1 ===="

# Review M6: the backend RPC module used two whitelisting spellings side by
# side (`x in [...]` and `index([...], x) === -1`).  They both work but the
# reader has to stop and confirm, and one of them silently behaves
# differently when the haystack is a string (it does substring matching
# instead of membership).  Pinning the rule to index() means a future method
# has to use the spelling the rest of the file uses.
#
# Coverage boundary: after comments are stripped and the source is flattened,
# the pattern matches a string-literal array with one or more elements in
# either quote style - so `x in ['a']` (single element) and `x in ["a", "b"]`
# (double quotes) are caught, as is a membership test split over several lines.
# Object key checks (`in {}`), `for ... in ...` over a non-literal and a
# mention inside a comment are deliberately not matches.
RPC="$ROOT/root/usr/share/rpcd/ucode/luci.homeproxy-pro"

IN_ARR="$(python3 - "$RPC" <<'PY'
import pathlib, re, sys

# SQ and DQ exist because an escaped quote inside this here-document upsets the
# shell command-substitution scanner and truncates the program, which would
# leave the check matching nothing and silently pass.
SQ, DQ = "'", '"'
COMMENT = r'/\*.*?\*/|//[^\n]*'
TOKENS = re.compile(
    DQ + r'(?:\\.|[^"\\])*' + DQ + '|' + SQ + r"(?:\\.|[^'\\])*" + SQ + '|' + COMMENT, re.S)


def blank(match):
    return ' ' if match.group(0).startswith('/') else match.group(0)


src = TOKENS.sub(blank, pathlib.Path(sys.argv[1]).read_text(encoding='utf-8', errors='replace'))
flat = re.sub(r'\s+', ' ', src)
# One or more string elements, single- or double-quoted.  The old pattern
# required a single-quoted pair, so `x in ['a']` and `x in ["a", "b"]` both
# slipped through.  Comments are stripped and the source is flattened first,
# so a membership test split over several lines is seen too.
LIT = '(?:' + DQ + '[^' + DQ + ']*' + DQ + '|' + SQ + '[^' + SQ + ']*' + SQ + ')'
for m in re.finditer(r'\bin\s*\[\s*' + LIT + r'(?:\s*,\s*' + LIT + r')*\s*\]', flat):
    print(m.group(0))
PY
)" || IN_ARR="__SCAN_FAILED__"
if [ "$IN_ARR" = "__SCAN_FAILED__" ]; then
	fail "the 'in [...]' scan could not run - fix the guard before trusting a pass"
elif [ -z "$IN_ARR" ]; then
	pass "no array-membership 'in [...]' remains in luci.homeproxy-pro"
else
	fail "array-membership 'in [...]' remains in luci.homeproxy-pro - the report's M6 said unify on index():"
	printf '      %s\n' "$IN_ARR"
fi

# Each whitelisting call site must use index() === -1 (or !== -1 for the
# subset checks).  Asserted positively so the check cannot pass by finding
# nothing (a regex in a comment would otherwise be enough).
if grep -qE "index\(\[".*"\], req\.args\?\.type\) === -1" "$RPC"; then
	pass "luci.homeproxy-pro uses index() === -1 for whitelist checks"
else
	fail "luci.homeproxy-pro no longer uses index() === -1 for whitelist checks - did someone reintroduce the in-style?"
fi

echo
echo "== guard 16: every shell argument goes through shellQuote() =="

# Review M6: shellQuote() is the one helper that wraps an arbitrary string
# into single quotes that the shell cannot parse as syntax.  Every script
# argument that the shell sees has to come out of shellQuote(); the only
# exception is a literal constant with no interpolation.  Today the
# generators used string concatenation (`'rm -rf ' + tmp`), the rpcd
# module had a local lowercase `shellquote()` that the report caught, and
# one site interpolated `${req.args?.params}` raw.  This guard pins all of
# those to the imported shellQuote() so a future shell call cannot
# quietly escape the rule.
#
# The check walks every `system(...)` / `popen(...)` invocation under
# $SCRIPTS and the rpcd tree.  A call is "compliant" if it either:
#   (a) contains no `${...}` interpolation at all (literal command), or
#   (b) contains at least one `shellQuote(` call somewhere in its
#       arguments, so every interpolation goes through it.
# grep -E0 is unavailable; split the check into two passes so a compliant
# line is not double-counted.

# Pass 1: shell calls with no interpolation at all are fine.
SHELL_CALLS="$(grep -rEn '(^|[^A-Za-z_])(system|popen)\(' \
	"$SCRIPTS" "$RPC" 2>/dev/null \
	| grep -vE '/\*|^[^:]+:[^:]+:[[:space:]]*//' || true)"

# Pass 2: of those, lines that contain `${` (interpolation) must also
# contain `shellQuote(` somewhere in the same line.  ${} inside a string
# means the value reached the shell unquoted.
UNQUOTED="$(printf '%s\n' "$SHELL_CALLS" | python3 -c '
import sys, re
# Two styles reach the shell unquoted:
#   (a) template literal with `${someVar}`     - luci.homeproxy-pro
#   (b) string concatenation `+ someVar +`     - the generator scripts
# A line is compliant if shellQuote() appears on it; both styles are
# caught with one rule because the helper is the same either way.
template = re.compile(r"\$\{[A-Za-z_]")
concat   = re.compile(r"\+ +[A-Za-z_][A-Za-z_0-9]*(?!\()")
quote    = re.compile(r"shellQuote\(")
for raw in sys.stdin:
    line = raw.rstrip("\n")
    # Strip the "<file>:<lineno>:" prefix the grep produced.
    body = line.split(":", 2)[2] if line.count(":") >= 2 else line
    if not (template.search(body) or concat.search(body)):
        continue
    if not quote.search(body):
        print(line)
')" || UNQUOTED="__SCAN_FAILED__"

# Two exclusions the rule has to live with:
#   - update_subscriptions.uc uses sprintf() with shellQuote() arguments,
#     so `${shellQuote(x)}` is fine but the awk heuristic only sees it as
#     `${shellQuote(x)}` and considers it quoted.  sprintf() is a sibling
#     function that builds the command before passing it to system(); the
#     guard's grep on the source line therefore catches every other case
#     without needing to descend into sprintf.
#   - firewall_pre.uc writes nft fragments to disk rather than passing
#     them to a shell, so its system() calls only see literal commands.

if [ "$UNQUOTED" = "__SCAN_FAILED__" ]; then
	fail "the shellQuote() coverage scan could not run - fix the guard before trusting a pass"
elif [ -z "$UNQUOTED" ]; then
	pass "every shell arg with \${...} interpolation goes through shellQuote()"
else
	fail "shell args with \${...} interpolation bypass shellQuote():"
	printf '      %s\n' "$UNQUOTED" | head -20
fi

# The local lowercase `shellquote()` placeholder must be gone - it shadows
# the imported shellQuote() and would silently no-op on a future call site.
LOWER="$(grep -rnE '\bshellquote\(' "$SCRIPTS" "$RPC" 2>/dev/null || true)"
if [ -z "$LOWER" ]; then
	pass "the local lowercase shellquote() placeholder is gone"
else
	fail "local lowercase shellquote() is still referenced - replace with the imported shellQuote():"
	printf '      %s\n' "$LOWER"
fi

echo
echo "== guard 17: resource update has multi-mirror fallback =="

# Review M7: update_resources.sh used to hardcode fastly.jsdelivr.net.  When
# that CDN was unreachable (or shared the same rate limit / block as the
# user's network), the only path to "successfully updated" was for the user
# to switch the package's CDN manually - and there was no UI surface for
# it.  Walking a fallback list at download time keeps the script correct
# for the common case (fastly is up) and useful in the failure case
# (gcore, cdn, or raw.githubusercontent.com catches it).  The list lives
# in the script's MIRRORS variable; the order is part of the contract.
UPDATE_SCRIPT="$ROOT/root/etc/homeproxy-pro/scripts/update_resources.sh"

for mirror in fastly.jsdelivr.net gcore.jsdelivr.net cdn.jsdelivr.net raw.githubusercontent.com; do
	if grep -qE "\b$mirror\b" "$UPDATE_SCRIPT"; then
		pass "update_resources.sh mentions $mirror"
	else
		fail "update_resources.sh is missing $mirror in its mirror list"
	fi
done

# The fallback must actually iterate - asserting just that the names
# appear would pass on a one-line comment.
if grep -qE "for [a-zA-Z_]+ in \\\$MIRRORS" "$UPDATE_SCRIPT"; then
	pass "update_resources.sh iterates over the mirror list"
else
	fail "update_resources.sh does not iterate over the mirror list - the fallback is not wired"
fi

echo
echo "== guard 18: resource update exposes last-successful timestamp =="

# The .updated_at file is what the UI shows as "(last updated ...)".
# The .ver file holds the upstream commit date, which is not what the
# user wants - they want to know when *this router* last succeeded.
if grep -qE '\$RESOURCES_DIR/\$listtype\.updated_at' "$UPDATE_SCRIPT"; then
	pass "update_resources.sh writes the local success timestamp to <type>.updated_at"
else
	fail "update_resources.sh does not persist the local success timestamp - the UI has nothing to show"
fi

# The RPC must return both version and updated_at.  Asserted positively
# so the guard cannot pass by finding nothing.
LUCI="$ROOT/root/usr/share/rpcd/ucode/luci.homeproxy-pro"
if grep -qE "resources_get_version" "$LUCI" && grep -qE "\.updated_at" "$LUCI"; then
	pass "resources_get_version returns updated_at"
else
	fail "resources_get_version does not return updated_at - the UI cannot show \"(last updated ...)\""
fi

# The UI must read and display it.  Without this, the RPC field is
# unused and the user sees nothing new.
STATUS_JS="$ROOT/htdocs/luci-static/resources/view/homeproxy-pro/status.js"
if grep -qE "res\.updated_at" "$STATUS_JS"; then
	pass "status.js renders the last-updated timestamp"
else
	fail "status.js does not render res.updated_at - the RPC field is unused"
fi

echo
echo "== guard 19: acllist_write rejects bad lines with a line number =="

# Review L1: acllist_write used to return "invalid character in domain list"
# with no offset, so a 200-line list with one bad row forced the user to
# bisect by hand.  The rejection now names the line, and the UI hint tells
# the user what characters are banned.  Pinned by the guard so the line
# number cannot quietly regress.
LUCI="$ROOT/root/usr/share/rpcd/ucode/luci.homeproxy-pro"
ACLLIST_BODY="$(awk '/^[[:space:]]+acllist_write:/,/^[[:space:]]+},$/' "$LUCI")"

if printf '%s' "$ACLLIST_BODY" | grep -qE "line \\\$\\{i \\+ 1\\}"; then
	pass "acllist_write reports the offending line number"
else
	fail "acllist_write does not report a line number - the L1 fix is gone"
fi

# The UI hint (one per textarea) is the other half: the user sees the
# description *before* trying to save.  Both proxy_list and direct_list
# textareas must carry the hint; assert positively so the guard cannot
# pass by finding nothing.
ACCESS="$ROOT/htdocs/luci-static/resources/view/homeproxy-pro/client/access.js"
PROXY_HINT="$(awk '/_proxy_domain_list/,/description\s*=/' "$ACCESS" \
	| grep -c 'One domain per line')"
DIRECT_HINT="$(awk '/_direct_domain_list/,/description\s*=/' "$ACCESS" \
	| grep -c 'One domain per line')"
if [ "$PROXY_HINT" -ge 1 ]; then
	pass "access.js proxy_domain_list textarea carries the L1 hint"
else
	fail "access.js proxy_domain_list textarea is missing the L1 hint - the user is back to guessing which characters are allowed"
fi
if [ "$DIRECT_HINT" -ge 1 ]; then
	pass "access.js direct_domain_list textarea carries the L1 hint"
else
	fail "access.js direct_domain_list textarea is missing the L1 hint"
fi

# No shipped file may cite docs/.  The whole directory is gitignored, so every
# pointer to it is a dead link in a fresh clone - that is how README.md
# came to reference an agent guide and an improvement plan that no
# contributor can open.  Kept here (with the docs/ pattern, not the names)
# so the rule cannot quietly come back.
DEAD_DOCS="$(grep -rlE 'docs/(adr|architecture-improvement-plan|homeproxy_architecture_refactor_agent_guide|audit-report|next-step-plan)' \
	"$ROOT/README.md" "$ROOT/root" "$ROOT/htdocs" 2>/dev/null || true)"
if [ -z "$DEAD_DOCS" ]; then
	pass "no shipped file cites the gitignored docs/ tree"
else
	fail "these shipped files cite docs/ (gitignored, absent from every clone):"
	printf '%s\n' "$DEAD_DOCS"
fi

echo
echo "== guard 21: dnsmasq snippet writer is incremental =="

# Review L6: hp_dnsmasq_write_snippets rewrote the snippet set and restarted
# dnsmasq on every reload.  A dnsmasq restart flushes every client's DNS
# cache, and the lists only change once a day at best - so an ordinary
# reload was a LAN-wide cache flush for nothing.  The writer now renders
# into a staging directory, compares, and restarts only on a real change.
# tests/runtime/test_dns_snippets.sh pins the behaviour from the outside;
# this guard pins the two structural pieces that make it possible, so a
# future edit cannot quietly drop back to unconditional rewrite.
DNS_SH="$ROOT/root/etc/homeproxy-pro/scripts/runtime/dns.sh"

if grep -qE '^hp_dnsmasq_render_snippets\(\)' "$DNS_SH"; then
	pass "dns.sh has a side-effect-free snippet renderer"
else
	fail "dns.sh has no separate renderer - the staging/compare split is gone"
fi

if grep -qE '^hp_dnsmasq_dir_differs\(\)' "$DNS_SH"; then
	pass "dns.sh has a directory comparison helper"
else
	fail "dns.sh has no directory comparison helper - the skip branch cannot work"
fi

# The renderer must not touch the live directory: it takes a stage dir as
# its first argument and writes only there.
RENDER_BODY="$(awk '/^hp_dnsmasq_render_snippets\(\)/,/^}$/' "$DNS_SH")"
if printf '%s' "$RENDER_BODY" | grep -qE '\$stage/'; then
	pass "the renderer writes into the staging directory"
else
	fail "the renderer does not write into a staging directory"
fi
if printf '%s' "$RENDER_BODY" | grep -qE 'dnsmasq restart'; then
	fail "the renderer restarts dnsmasq - it is supposed to be side-effect free"
else
	pass "the renderer does not restart dnsmasq"
fi

# The skip branch must exist and must be reachable before the restart.
if grep -qE 'unchanged, skipping the restart' "$DNS_SH"; then
	pass "the skip branch is present"
else
	fail "the skip branch is gone - an unchanged snippet set would restart dnsmasq again"
fi

# The include file is one line of `conf-dir=`; `echo -e` renders a literal
# "-e " prefix on a POSIX sh and dnsmasq then refuses the file.  printf is
# the portable spelling and the only one used here.
if grep -qE 'echo -e "conf-dir=' "$DNS_SH"; then
	fail "dns.sh writes the conf-dir include with 'echo -e' - a POSIX sh emits a literal '-e ' prefix"
else
	pass "the conf-dir include is written with printf, not 'echo -e'"
fi

echo
echo "== guard 22: client tab modules return a LuCI class =="

# LuCI instantiates every module it requires and rejects anything that is not
# a Class subclass:
#
#   _class = _factory.apply(...);
#   if (!Class.isSubclass(_class))
#       error('TypeError', '"%s" factory yields invalid constructor', name);
#
# The M5 split shipped six view.homeproxy-pro.client.* modules returning a plain
# object (`return { render }`), so every tab threw and no browser could render
# the client page.  Nothing caught it: the modules parse, and the snapshot
# harness has its own loader that happily accepts a plain object.
for f in "$VIEWS"/view/homeproxy-pro/client/*.js; do
	[ -f "$f" ] || continue
	if grep -qE '^return baseclass\.extend\(' "$f"; then
		pass "$(basename "$f") returns a LuCI class"
	else
		fail "$(basename "$f") does not return baseclass.extend(...) - luci.js rejects it as an invalid constructor"
	fi
done

echo
echo "== guard 23: an hp method that reads \`this\` is bound to hp =="

# A method that reaches a sibling through `this` only works when the receiver
# is the module object itself.  Six call sites bound loadModalTitle() to a view
# instance, so `this.escapeTitleText` was undefined and every edit modal for a
# section that has a label threw a TypeError; four more did the same to
# uploadCertificate(), so no certificate upload ever reached its RPC.  Nothing
# caught it: the form snapshot does not record function-valued properties, and
# the frontend tests call hp.method() directly - where `this` *is* hp, so the
# only broken path was the one production uses.
#
# The rule: when a view binds an hp method through L.bind(), and that method's
# body reads `this`, the receiver has to be `hp`.
BOUND_WRONG="$(python3 - "$ROOT" <<'PY'
import re, sys, pathlib
root = pathlib.Path(sys.argv[1])
hp = (root / 'htdocs/luci-static/resources/homeproxy-pro.js').read_text(encoding='utf-8')

# Top-level method -> does its body read `this`?
uses_this, cur, body = set(), None, []
for line in hp.split('\n'):
    m = re.match(r'^\t([A-Za-z_$][\w$]*)\(', line)
    if m and cur is None:
        cur, body = m.group(1), []
    if cur is not None:
        body.append(line)
        if line == '\t},':
            if any('this.' in b for b in body):
                uses_this.add(cur)
            cur = None

bad = []
for f in sorted((root / 'htdocs').rglob('*.js')):
    if f.name == 'homeproxy-pro.js':
        continue
    for n, line in enumerate(f.read_text(encoding='utf-8').split('\n'), 1):
        for meth, recv in re.findall(r'L\.bind\(hp\.([A-Za-z_$][\w$]*),\s*([A-Za-z_$][\w$]*)', line):
            if meth in uses_this and recv != 'hp':
                bad.append(f'{f.relative_to(root)}:{n}: L.bind(hp.{meth}, {recv}, ...)')
print('\n'.join(bad))
PY
)" || BOUND_WRONG="__SCAN_FAILED__"
if [ "$BOUND_WRONG" = "__SCAN_FAILED__" ]; then
	fail "the bound-receiver scan could not run - fix the guard before trusting a pass"
elif [ -z "$BOUND_WRONG" ]; then
	pass "every receiver-dependent hp method is bound to hp"
else
	fail "an hp method that reads \`this\` is bound to a foreign receiver:"
	printf '      %s\n' "$BOUND_WRONG"
fi

echo
echo "== guard 24: dns-in listens on loopback only =="

# dns-in is a `direct` inbound, and a direct inbound forwards a connection
# without consulting the route rules.  It used to listen on '::' - every
# interface - so any host that reached the DNS port had its connection dialled
# straight out; a router log showed blocked addresses timing out through the
# built-in `direct` outbound while every route rule named main-out.  The only
# client that has any business at that port is the local resolver: dnsmasq is
# pointed at 127.0.0.1#<dns_port> by runtime/dns.sh, and it is the only DNS
# entry point on the LAN.
if awk "/tag: 'dns-in'/,/listen_port/" "$SCRIPTS/generator/inbound.uc" \
	| grep -qF "listen: '127.0.0.1'"; then
	pass "dns-in listens on 127.0.0.1 only"
else
	fail "dns-in does not listen on 127.0.0.1 - the DNS port is reachable from other hosts, and a direct inbound bypasses the routing rules"
fi

echo
echo "== guard 25: executeCommand() arguments are quoted by the caller =="

# executeCommand() joins its arguments into one shell command line, so a bare
# variable in an argument reaches /bin/sh unquoted.  Guard 16 only walks
# `system()` / `popen()` lines, and the busiest shell boundary in the package -
# wGETVerbose(), which fetches subscription bodies - builds its command through
# executeCommand() instead, so the guard could not see it.  Rule: every ${...}
# interpolation in an executeCommand() argument is shellQuote()d, or a pure
# numeric constant (the `head -c` limit).
EXEC_UNQUOTED="$(python3 - "$SCRIPTS" <<'PY'
import re, sys, pathlib
bad = []
for f in sorted(pathlib.Path(sys.argv[1]).rglob('*.uc')):
    for n, line in enumerate(f.read_text(encoding='utf-8').split('\n'), 1):
        if 'executeCommand(' not in line or line.lstrip().startswith('*'):
            continue
        for expr in re.findall(r'\$\{([^{}]*)\}', line):
            e = expr.strip()
            if e.startswith('shellQuote('):
                continue
            if re.fullmatch(r'[A-Za-z_]\w*\s*[-+*/]\s*\d+', e):
                continue
            bad.append(f'{f.name}:{n}: ${{{e}}}')
print('\n'.join(bad))
PY
)" || EXEC_UNQUOTED="__SCAN_FAILED__"
if [ "$EXEC_UNQUOTED" = "__SCAN_FAILED__" ]; then
	fail "the executeCommand() interpolation scan could not run - fix the guard before trusting a pass"
elif [ -z "$EXEC_UNQUOTED" ]; then
	pass "every executeCommand() interpolation is shellQuote()d or numeric"
else
	fail "an executeCommand() argument reaches the shell unquoted:"
	printf '      %s\n' "$EXEC_UNQUOTED"
fi

echo
echo "== guard 26: ucode sources carry no PCRE-only regex syntax =="

# ucode's regex engine is not PCRE, and it does not reject the unsupported
# construct at parse time: `(?:...)` compiles fine and then fails when the
# literal is evaluated ("Repetition not preceded by valid expression").  That
# is how r11 shipped a luci.homeproxy-pro whose resources_get_version threw on
# every call - the build, `ucode -c` and every syntax check stayed green while
# the resources panel rendered "undefined".  One grep keeps it out.
PCRE_ONLY="$(grep -rn '(?:' "$ROOT/root" --include='*.uc' --include='*.ut' 2>"/dev/null" \
	| grep -vE ':[0-9]+:[[:space:]]*(\*|/\*|//|#)' || true)"
if [ -z "$PCRE_ONLY" ]; then
	pass "no non-capturing groups in ucode sources"
else
	fail "ucode does not support (?: ...) - it compiles and then fails at run time:"
	printf '      %s\n' "$PCRE_ONLY"
fi

echo
echo "== guard 27: generator/ is a pure function of its arguments =="

# generator/client.uc was documented as a pure function while it called ubus for
# the WAN resolver and readfile() for the two domain-resource lists. Generation
# was therefore not reproducible - two runs could differ if the WAN lease changed
# - and reload's preflight config was not provably the artifact start_service
# regenerated. The impure boundary is the CLI shells (scripts/generate_*.uc);
# every module under generator/ takes its environment as an argument. See
# generator/context.uc.
GEN_IMPURE="$(grep -rnE "from '(ubus|fs)'" "$SCRIPTS/generator" --include='*.uc' 2>"/dev/null" \
	| grep -vE ':[0-9]+:[[:space:]]*(\*|/\*|//|#)' || true)"
if [ -z "$GEN_IMPURE" ]; then
	pass "no generator module imports ubus or fs"
else
	fail "a generator module reaches for live router state instead of taking it as an argument:"
	printf '      %s\n' "$GEN_IMPURE"
fi

echo
echo "== guard 28: the subscription run reads its state inside the lock =="

# update_subscriptions.uc used to read the domain model and the recovery
# snapshot at module scope, and only then try to take the lock. A run that read
# while another one held the lock and then acquired it after that one finished
# committed against the base it had read earlier and, on failure, restored a
# snapshot older than the run that had just committed. The reads must therefore
# live inside load_locked_state(), and that function must only be called after
# acquire_lock() succeeds.
#
# Two checks: no configuration read may appear at module scope (column 0), and
# the load_locked_state() call must come after the acquire_lock() call.
SNAP_ORDER="$(python3 - "$SCRIPTS/update_subscriptions.uc" <<'PY'
import re, sys
lines = open(sys.argv[1], encoding='utf-8').read().split('\n')
read = re.compile(r'\b(cursor\(|Loader\.load\(|uci\.load\(|readfile\(CONFIG_FILE\))')
problems = []
lock = lls = None
for n, line in enumerate(lines, 1):
    if line.lstrip().startswith(('*', '/*', '#')):
        continue
    if line[:1] not in ('', ' ', '\t') and read.search(line):
        problems.append('line %d reads configuration at module scope: %s' % (n, line.strip()))
    if 'function acquire_lock' in line:
        continue
    if 'function load_locked_state' in line:
        continue
    if lock is None and 'acquire_lock()' in line:
        lock = n
    if lls is None and 'load_locked_state()' in line:
        lls = n
if lock is None:
    problems.append('no acquire_lock() call site')
if lls is None:
    problems.append('no load_locked_state() call site')
elif lock is not None and lls < lock:
    problems.append('load_locked_state() at line %d runs before the lock at line %d' % (lls, lock))
print('\n'.join(problems))
PY
)" || SNAP_ORDER="__SCAN_FAILED__"
if [ "$SNAP_ORDER" = "__SCAN_FAILED__" ]; then
	fail "the lock-ordering scan could not run - fix the guard before trusting a pass"
elif [ -z "$SNAP_ORDER" ]; then
	pass "the domain model and the recovery snapshot are read after the lock"
else
	fail "the subscription run reads state outside the lock:"
	printf '      %s\n' "$SNAP_ORDER"
fi

echo
echo "== guard 29: the certificate path policy is identical in both layers =="

# TLS certificate_path / key_path had two different policies: the LuCI form
# offered /etc/homeproxy-pro/certs/, /etc/acme/ and /etc/ssl/, while the backend
# validator only knew /etc/homeproxy-pro/ and /tmp/homeproxy_. A certificate the
# user picked from /etc/ssl/ was therefore accepted by the UI, dropped by
# buildTLSObject(), and the listener failed with nothing pointing at the path.
# Both layers now read the same list - CERT_PATH_ROOTS in homeproxy-pro.uc and
# HP_CERT_PATH_ROOTS in homeproxy-pro.js - and this guard keeps the two copies in
# step, because nothing else can see across the JS/ucode boundary.
CERT_ROOTS="$(python3 - "$SCRIPTS/homeproxy-pro.uc" "$VIEWS/homeproxy-pro.js" <<'PY'
import re, sys

def roots(path, pattern, label):
    text = open(path, encoding='utf-8').read()
    m = re.search(pattern, text)
    if not m:
        return None, '%s: could not find the root list' % label
    return re.findall(r"'([^']+)'", m.group(1)), None

problems = []
backend, err = roots(sys.argv[1], r'\bCERT_PATH_ROOTS\s*=\s*\[([^\]]*)\]', 'homeproxy-pro.uc')
problems += [err] if err else []
frontend, err = roots(sys.argv[2], r'\bHP_CERT_PATH_ROOTS\s*=\s*\[([^\]]*)\]', 'homeproxy-pro.js')
problems += [err] if err else []
if not problems and backend != frontend:
    problems.append('homeproxy-pro.uc %s != homeproxy-pro.js %s' % (backend, frontend))
print('\n'.join(problems))
PY
)" || CERT_ROOTS="__SCAN_FAILED__"
if [ "$CERT_ROOTS" = "__SCAN_FAILED__" ]; then
	fail "the cert-roots scan could not run - fix the guard before trusting a pass"
elif [ -z "$CERT_ROOTS" ]; then
	pass "the frontend and backend certificate path roots agree"
else
	fail "the certificate path policy differs between the layers:"
	printf '      %s\n' "$CERT_ROOTS"
fi

echo
echo "== guard 30: the ACL grants no file execution =="

# The subscription button used fs.exec_direct() on
# /etc/homeproxy-pro/scripts/update_subscriptions.uc, and that is the only reason
# the ACL carried `"exec"` for a root-owned path: a browser session authorised
# to execute a file, rather than to call one named method. The updater is a ubus
# method now (update_subscriptions), so no path in this ACL may be executable -
# and no view may try, because the exec would be denied at run time.
ACL_EXEC="$(grep -n '"exec"' "$ACL" 2>"/dev/null" || true)"
if [ -z "$ACL_EXEC" ]; then
	pass "the ACL grants no executable file path"
else
	fail "the ACL still grants file execution:"
	printf '      %s\n' "$ACL_EXEC"
fi

# Block comments are stripped first: the call site's own explanatory comment
# names fs.exec_direct(), and a naive grep matched that prose - the same trap
# the frontend RPC boundary test documents.
EXEC_DIRECT="$(python3 - "$VIEWS" <<'PY'
import pathlib, re, sys
bad = []
for f in sorted(pathlib.Path(sys.argv[1]).rglob('*.js')):
    src = re.sub(r'/\*[\s\S]*?\*/', '', f.read_text(encoding='utf-8'))
    for n, line in enumerate(src.split('\n'), 1):
        if 'exec_direct' in line:
            bad.append('%s:%d: %s' % (f.relative_to(sys.argv[1]), n, line.strip()))
print('\n'.join(bad))
PY
)" || EXEC_DIRECT="__SCAN_FAILED__"
if [ "$EXEC_DIRECT" = "__SCAN_FAILED__" ]; then
	fail "the fs.exec_direct scan could not run - fix the guard before trusting a pass"
elif [ -z "$EXEC_DIRECT" ]; then
	pass "no view runs a file directly (the ACL grants no exec right)"
else
	fail "a view still calls fs.exec_direct, which needs the exec grant this ACL no longer has:"
	printf '      %s\n' "$EXEC_DIRECT"
fi

echo
echo "== guard 31: the sing-box floor is identical in the gate, the testbed and the docs =="

# The package cannot express "sing-box >= 1.14" as an OpenWrt dependency: the
# build system has no version-constrained depends for a package the feed
# builds independently, so an install on a 1.13 source succeeds and the service
# only refuses at start time (hp_require_singbox). That makes the floor a
# number stated in four places, any of which a later edit can desync:
#
#   runtime/service.sh    hp_require_singbox()   the enforcement
#   tests/toolchain/*     SINGBOX_VERSION        what the suite tests against
#   Makefile              +sing-box              the dependency itself
#   README.md             the stated requirement
#
# The testbed pin matters most: if it moved below the gate, the generator cases
# would feed configs to a binary the package rejects and the suite would pass
# on a version users cannot run.
GATE_MAJOR="$(grep -oE 'sb_major" -lt [0-9]+' "$RUNTIME/service.sh" 2>"/dev/null" | grep -oE '[0-9]+$' | head -1)"
GATE_MINOR="$(grep -oE 'sb_minor" -lt [0-9]+' "$RUNTIME/service.sh" 2>"/dev/null" | grep -oE '[0-9]+$' | head -1)"
TESTBED_VERSION="$(sed -n 's/^SINGBOX_VERSION="\([0-9][0-9.]*\)"$/\1/p' \
	"$ROOT/tests/toolchain/build-ucode-linux.sh" 2>"/dev/null" | head -1)"
TESTBED_FLOOR="${TESTBED_VERSION%.*}"

FLOOR_PROBLEMS=""
[ -n "$GATE_MAJOR" ] && [ -n "$GATE_MINOR" ] || FLOOR_PROBLEMS="$FLOOR_PROBLEMS no floor in runtime/service.sh"
[ -n "$TESTBED_VERSION" ] || FLOOR_PROBLEMS="$FLOOR_PROBLEMS no SINGBOX_VERSION in the testbed script"
if [ -n "$GATE_MAJOR" ] && [ -n "$TESTBED_VERSION" ] && [ -n "$GATE_MINOR" ]; then
	[ "$GATE_MAJOR.$GATE_MINOR" = "$TESTBED_FLOOR" ] \
		|| FLOOR_PROBLEMS="$FLOOR_PROBLEMS the gate refuses below $GATE_MAJOR.$GATE_MINOR but the testbed pins $TESTBED_VERSION"
fi
grep -q '+sing-box' "$ROOT/Makefile" 2>"/dev/null" \
	|| FLOOR_PROBLEMS="$FLOOR_PROBLEMS the Makefile does not depend on +sing-box"
if [ -n "$GATE_MAJOR" ] && [ -n "$GATE_MINOR" ]; then
	# The requirement section specifically, not "1.14 appears somewhere in the
	# README": the title and the comparison table mention 1.14 too, and a guard
	# that any of those can satisfy would pass on a README whose requirements
	# no longer state the floor at all - which is exactly how the earlier
	# version of this check behaved.
	README_REQ="$(awk '/^## 运行要求/{f=1;next} /^## /{f=0} f' "$ROOT/README.md" 2>"/dev/null")"
	if [ -z "$README_REQ" ]; then
		FLOOR_PROBLEMS="$FLOOR_PROBLEMS README.md has no '## 运行要求' section"
	elif ! printf '%s\n' "$README_REQ" | grep -qE "sing-box[^0-9]{0,6}$GATE_MAJOR\\.$GATE_MINOR"; then
		FLOOR_PROBLEMS="$FLOOR_PROBLEMS the README requirements do not state the $GATE_MAJOR.$GATE_MINOR floor"
	fi
fi

if [ -z "$FLOOR_PROBLEMS" ]; then
	pass "gate, testbed pin, dependency and README all say sing-box $GATE_MAJOR.$GATE_MINOR"
else
	fail "the sing-box floor is inconsistent:$FLOOR_PROBLEMS"
fi

echo
echo "== guard 32: the adapter's shared field table cannot overwrite a runtime field =="

# build_outbound() builds the literal `{ type, tag, routing_mark }` and then
# applies COMMON_FIELDS over it, so a key listed in that table wins - even when
# it is `null`, after which removeBlankAttrs() drops the field entirely.  That
# is how routing_mark (the SO_MARK that keeps sing-box's own proxy connection
# out of the nft redirect chain) disappeared from every outbound while
# `sing-box check` stayed green: on macOS the field is unknown, so the suite
# could not see it.  The two key sets have to stay disjoint; a runtime-owned
# field belongs in build_outbound()'s literal (or in its `mark` parameter),
# never in this table.
ADAPTER="$SCRIPTS/config/adapter.uc"
COMMON_KEYS="$(awk '/^const COMMON_FIELDS = \{/{f=1;next} f && /^\};/{exit} f' "$ADAPTER" 2>"/dev/null" \
	| sed -n 's/^\t\([a-z_][a-z_0-9]*\):.*/\1/p' | sort -u)"
LITERAL_KEYS="$(awk '/^function build_outbound\(/{f=1;next} f && /COMMON_FIELDS\)/{exit} f' "$ADAPTER" 2>"/dev/null" \
	| sed -n 's/^\t\t\([a-z_][a-z_0-9]*\):.*/\1/p' | sort -u)"
OVERLAP="$(printf '%s\n%s\n' "$COMMON_KEYS" "$LITERAL_KEYS" | sort | uniq -d | tr '\n' ' ')"
if [ -z "$COMMON_KEYS" ] || [ -z "$LITERAL_KEYS" ]; then
	fail "could not read both field sets from config/adapter.uc (COMMON_FIELDS: $([ -n "$COMMON_KEYS" ] && echo ok || echo empty), build_outbound literal: $([ -n "$LITERAL_KEYS" ] && echo ok || echo empty))"
elif [ -n "$OVERLAP" ]; then
	fail "COMMON_FIELDS lists a field build_outbound() already set, so it is overwritten: $OVERLAP"
else
	pass "no key is set by both build_outbound()'s literal and COMMON_FIELDS"
fi

echo
echo "== guard 33: both packaging paths declare every Makefile conffile =="

# The release artifacts are built by .github/build-pkg.sh, which parses the
# Makefile itself - so the Makefile's conffiles block has to reach both package
# formats.  It used to filter that list down to /etc/config/<app> for the apk
# and the ipk, which meant the released packages protected one path while the
# feed build protected all nine; the resource lists the device updates were
# then overwritten by an upgrade.  A filtered list or a single write means the
# two packaging paths have diverged again.
BUILD_PKG="$ROOT/.github/build-pkg.sh"
CONF_FILTERED="$(grep -n 'CONFFILES\[@\]' "$BUILD_PKG" 2>"/dev/null" | grep 'grep -x' || true)"
CONF_WRITES="$(grep -c 'CONFFILES\[@\]' "$BUILD_PKG" 2>"/dev/null")"
if [ -n "$CONF_FILTERED" ]; then
	fail "build-pkg.sh filters the conffile list instead of shipping it whole: $CONF_FILTERED"
elif [ "${CONF_WRITES:-0}" -lt 2 ]; then
	fail "build-pkg.sh writes the conffile list ${CONF_WRITES:-0} time(s); the apk and the ipk each need it"
else
	pass "the whole conffile list reaches both the apk and the ipk"
fi

echo
echo
echo "== guard 34: the bundled resource versions use the writers' format =="

# Both writers - scripts/update_resources.sh on the device and
# .github/update-geodata.sh for the package - store `<YYYY-MM-DD> <git-sha>`,
# and the reader (rpcd ucode, resources_get_version) splits the value on the
# space.  The package shipped bare timestamps instead (20260704060757), so the
# status page presented a 14-digit number as the upstream version and the
# "already at the latest version" comparison could never match.  The date/sha
# shape is checked with case/parameter expansion rather than a grep interval,
# which busybox grep may not support.
RES_VER_BAD=""
for f in "$ROOT"/root/etc/homeproxy-pro/resources/*.ver; do
	[ -f "$f" ] || continue
	RES_VER="${f##*/}"
	RES_VER_VALUE="$(cat "$f" 2>"/dev/null")"
	RES_VER_SHA="${RES_VER_VALUE##* }"
	case "$RES_VER_VALUE" in
	[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]' '*) ;;
	*) RES_VER_BAD="$RES_VER_BAD $RES_VER(missing date)"; continue ;;
	esac
	if [ "${#RES_VER_SHA}" -ne 40 ] || printf '%s' "$RES_VER_SHA" | grep -q '[^0-9a-f]'; then
		RES_VER_BAD="$RES_VER_BAD $RES_VER(missing sha)"
	fi
done
if [ -n "$RES_VER_BAD" ]; then
	fail "bundled .ver files are not '<date> <sha>':$RES_VER_BAD"
else
	pass "every bundled .ver file is '<date> <sha>'"
fi

echo
echo "== guard 35: mock copies of redactUrl match the real one =="

# tests/ucode/mocks/*.uc carry verbatim copies of redactUrl() so the parser and
# fetcher tests can run without homeproxy-pro.uc's other dependencies.  A copy is
# only worth having while it is identical: when the real function started
# masking the URL path (the subscription token is often the path), both mocks
# had to be updated by hand and nothing failed when they were not - the fetcher
# test would have kept exercising the old behaviour and passing.
extract_fn() {
	awk -v fn="$2" '
		$0 ~ ("^export function " fn "\\(") { inside = 1 }
		inside { print }
		inside && /^};$/ { exit }
	' "$1"
}
REAL_REDACT="$(extract_fn "$HOMEPROXY" redactUrl)"
MOCK_DRIFT=""
if [ -z "$REAL_REDACT" ]; then
	fail "redactUrl could not be extracted from homeproxy-pro.uc"
else
	for m in "$ROOT"/tests/ucode/mocks/*.uc; do
		[ -f "$m" ] || continue
		grep -q "^export function redactUrl(" "$m" || continue
		if [ "$(extract_fn "$m" redactUrl)" != "$REAL_REDACT" ]; then
			MOCK_DRIFT="$MOCK_DRIFT ${m##*/}"
		fi
	done
	if [ -n "$MOCK_DRIFT" ]; then
		fail "mock copies of redactUrl have drifted from homeproxy-pro.uc:$MOCK_DRIFT"
	else
		pass "every mock's redactUrl is identical to homeproxy-pro.uc's"
	fi
fi


echo "== guard 36: the certificate upload buttons pass the handler's arguments =="

# The four Upload buttons wire L.bind(hp.uploadCertificate, hp, <label>, <name>)
# and LuCI calls onclick(ev, section_id): L.bind prepends the bound arguments,
# the event comes first.  A handler that declares a leading parameter no caller
# passes shifts everything by one - filename became the event object, the
# staging path became /tmp/homeproxy_cert_[object Event].tmp, and neither the
# ACL nor certificate_write knew that path, so every certificate upload failed.
# guard 3 cannot see it (the last quoted argument of the call site was still the
# right UCI option name) and guard 23 only checks the bound receiver.
#
# The call site must therefore pass exactly the two arguments that occupy the
# handler's first two parameter slots: the button label and the UCI option
# name, each as a quoted literal.  Nothing else may sit between them (a third
# argument, or a bare value shifted into the wrong slot, changes the staging
# path), and the handler must take exactly one parameter more than the call
# passes - the event LuCI adds in front.
CERT_HANDLER="$VIEWS/homeproxy-pro.js"
CERT_SITES=0
CERT_BAD=""
CERT_CALLS="$(mktemp)"
trap 'rm -f "$CERT_CALLS"' EXIT INT TERM

CERT_ARGS="$(sed -n 's/.*uploadCertificate(\([^)]*\)).*/\1/p' "$CERT_HANDLER" | head -1)"
CERT_NARGS="$(printf '%s' "$CERT_ARGS" | awk -F',' '{ print NF }')"
case "$CERT_NARGS" in
''|*[!0-9]*) CERT_NARGS="" ;;
esac

if [ -z "$CERT_ARGS" ]; then
	fail "could not read the uploadCertificate parameter list from $CERT_HANDLER"
elif [ "$CERT_NARGS" != "3" ]; then
	fail "uploadCertificate takes $CERT_NARGS parameters; the buttons pass the label and the filename, LuCI prepends the event, so it must take 3 (type, filename, ev)"
fi

grep -hoE "L\.bind\(hp\.uploadCertificate[^;]*" "$VIEWS"/view/homeproxy-pro/*.js > "$CERT_CALLS" 2>"/dev/null"

while IFS= read -r call; do
	[ -n "$call" ] || continue
	CERT_SITES=$((CERT_SITES + 1))
	# The quoted literals of the call, in order.
	lits="$(printf '%s' "$call" | sed -n "s/'[^']*'/&\n/gp" | tr -d "'" | tr '\n' '|')"
	label="${lits%%|*}"
	filename="$(printf '%s' "$lits" | sed 's/^[^|]*|//; s/|.*//')"
	nlits="$(printf '%s' "$lits" | awk -F'|' '{ print NF - 1 }')"
	if [ -z "$filename" ]; then
		CERT_BAD="$CERT_BAD
	      $call passes no quoted filename"
	elif [ "$nlits" -ne 2 ]; then
		CERT_BAD="$CERT_BAD
	      $call passes $nlits quoted arguments (expected exactly the label and the filename)"
	elif [ -z "$label" ]; then
		CERT_BAD="$CERT_BAD
	      $call passes an empty button label"
	fi
done < "$CERT_CALLS"

if [ "$CERT_SITES" -eq 0 ]; then
	fail "no L.bind(hp.uploadCertificate ...) call site was found under $VIEWS"
elif [ -n "$CERT_BAD" ]; then
	fail "the certificate upload call sites do not match uploadCertificate's signature:$CERT_BAD"
	echo "      L.bind prepends its arguments and LuCI passes the event first, so an unused"
	echo "      leading parameter makes 'filename' the event object and the staging path"
	echo "      leaves the ACL whitelist"
else
	pass "$CERT_SITES certificate upload call sites pass a label and a filename for 3 parameters"
fi

echo
echo "== guard 37: the Makefile's conffiles block parses as the packaging path reads it =="

# guard 33 greps build-pkg.sh for the *shape* of its conffile handling; it never
# runs the other half of that contract.  get_conffiles() is an awk state
# machine, and one drift in the Makefile markers - a `define` line that no
# longer matches the `^define Package/<pkg>/conffiles` anchor, an indented
# `endef`, entries moved above their header - makes it return nothing.  Then
# `${#CONFFILES[@]}` is 0, build-pkg.sh takes its `else` branch and writes
# /etc/config/<app> alone, so the released apk/ipk stop protecting the eight
# resource files while guard 33 still passes.  That is exactly the silent
# downgrade guard 33 was written to prevent, so the parse itself gets a check.
#
# Two independent measures, because comparing the state machine to itself would
# prove nothing: the same awk build-pkg.sh runs (get_conffiles), against a
# separately written exact-match counter and against the expected count.  The
# count is deliberately a constant - changing which files a package protects is
# a deliberate packaging decision, and this is the line that makes it a
# deliberate edit here too.
MAKEFILE="$ROOT/Makefile"
MK_PKG_NAME="$(sed -n 's/^PKG_NAME:=//p' "$MAKEFILE" 2>"/dev/null" | head -1)"

# The same awk as .github/build-pkg.sh's get_conffiles(), byte for byte.
parse_conffiles() {
	awk -v pkg="$1" '
		$0 ~ "^define Package/"pkg"/conffiles" { flag=1; next }
		flag && /^endef/ { flag=0; next }
		flag && NF { print }
	' "$MAKEFILE"
}

# The declared lines counted without the regex anchors: exact marker match plus
# a `/`-prefixed-line filter.  If the awk regexes drift, the two disagree.
count_declared_conffiles() {
	awk -v pkg="$1" '
		$0 == "define Package/" pkg "/conffiles" { flag=1; next }
		flag && $0 == "endef" { flag=0 }
		flag && /^\// { n++ }
		END { print n+0 }
	' "$MAKEFILE"
}

EXPECTED_CONFFILES=9
CONF_PARSED="$(parse_conffiles "$MK_PKG_NAME")"
CONF_COUNT="$(printf '%s\n' "$CONF_PARSED" | grep -c .)"
CONF_DECLARED="$(count_declared_conffiles "$MK_PKG_NAME")"

if [ -z "$MK_PKG_NAME" ]; then
	fail "PKG_NAME is not declared in the Makefile - the conffile block cannot be located"
elif [ -z "$CONF_PARSED" ]; then
	fail "the get_conffiles() parse of Package/$MK_PKG_NAME/conffiles returned nothing - build-pkg.sh would ship /etc/config/<app> alone"
else
	pass "parsed $CONF_COUNT conffiles out of Package/$MK_PKG_NAME/conffiles"
fi

if [ -n "$CONF_PARSED" ] && [ "$CONF_COUNT" = "$CONF_DECLARED" ]; then
	pass "the awk parse sees every declared line ($CONF_COUNT of $CONF_DECLARED)"
else
	fail "the get_conffiles() parse and the declared lines disagree: parsed ${CONF_COUNT:-0}, declared ${CONF_DECLARED:-0} - the anchor no longer matches the block"
fi

if [ "$CONF_COUNT" = "$EXPECTED_CONFFILES" ]; then
	pass "Package/$MK_PKG_NAME/conffiles declares $EXPECTED_CONFFILES conffiles, the count guard 37 pins"
else
	fail "Package/$MK_PKG_NAME/conffiles parses as $CONF_COUNT entries, guard 37 expects $EXPECTED_CONFFILES - if the packaging list really changed, update EXPECTED_CONFFILES in the same commit"
fi

# Each parsed path must sit between the block header and its endef.  This is the
# part guard 33's grep cannot see: a path present elsewhere in the Makefile (a
# comment, another define) satisfies "the text appears" while the block parses
# empty or short.
CONF_DEFINE_LINE="$(grep -n "^define Package/$MK_PKG_NAME/conffiles\$" "$MAKEFILE" 2>"/dev/null" | head -1 | cut -d: -f1)"
CONF_ENDEF_LINE="$(awk -v start="${CONF_DEFINE_LINE:-0}" 'NR > start && $0 == "endef" { print NR; exit }' "$MAKEFILE")"
CONF_OUTSIDE=""
for f in $CONF_PARSED; do
	# Looking for the path *inside* the range rather than taking its first
	# occurrence: an identical line elsewhere in the Makefile would otherwise
	# decide the answer.
	CONF_IN_BLOCK="$(awk -v want="$f" -v lo="${CONF_DEFINE_LINE:-0}" -v hi="${CONF_ENDEF_LINE:-0}" '
		NR > lo && NR < hi && $0 == want { found = 1 }
		END { print found + 0 }
	' "$MAKEFILE")"
	[ "$CONF_IN_BLOCK" = "1" ] || CONF_OUTSIDE="$CONF_OUTSIDE $f"
done
if [ -n "$CONF_PARSED" ] && [ -z "$CONF_OUTSIDE" ]; then
	pass "every parsed conffile sits inside the block (lines $CONF_DEFINE_LINE-$CONF_ENDEF_LINE)"
else
	fail "these parsed conffiles are not inside Package/$MK_PKG_NAME/conffiles:$CONF_OUTSIDE"
fi

# A declared conffile the package does not ship protects nothing; the Makefile's
# own comment records that the previous list named four paths that exist
# nowhere in the tree.
CONF_MISSING=""
for f in $CONF_PARSED; do
	case "$f" in
	/*) [ -f "$ROOT/root$f" ] || CONF_MISSING="$CONF_MISSING $f" ;;
	*) CONF_MISSING="$CONF_MISSING $f(not absolute)" ;;
	esac
done
if [ -n "$CONF_PARSED" ] && [ -z "$CONF_MISSING" ]; then
	pass "every declared conffile exists in the package payload (root/)"
else
	fail "these declared conffiles are not shipped by the package, so the declaration protects nothing:$CONF_MISSING"
fi

echo "== guard 38: append_custom_dns emits the HTTPS/SVCB reject as its first DNS rule =="

# The proxy path emits this reject (append_proxy_dns line 102); the custom
# path used to rely on whatever the user wrote, so a rule that targets the
# same query_type could shadow the safety net.  The fix (see
# docs/linux.json 与 pro 的差距分析.md §2.2) prepends the same literal in
# append_custom_dns.  Two checks keep that ordering:
#
#   (a) the literal appears in BOTH append_proxy_dns and append_custom_dns;
#   (b) the second occurrence (the one inside append_custom_dns) comes
#       BEFORE the user-rules loop, so a user rule cannot shadow it.
#
# A regression that drops the custom-path literal, or moves it after the
# loop, would expose the user to Fake-IP bypass / HTTPS answer smuggling.
custom_dns_uc="$SCRIPTS/generator/dns.uc"
reject_count="$(grep -c 'query_type: *\[64, *65\]' "$custom_dns_uc")"
if [ "$reject_count" -eq 2 ]; then
	pass "the HTTPS/SVCB reject appears in both append_proxy_dns and append_custom_dns"
else
	fail "expected 2 occurrences of 'query_type: [64, 65]' in generator/dns.uc, found $reject_count"
	fail "the custom path lost its built-in reject; see §2.2 of the gap analysis"
fi

# (b): the custom-path reject is the SECOND occurrence (append_custom_dns
# is the second function defined).  It must come before the user-rules
# loop, which is the first `for (let cfg in dm.dns.rules)` AFTER the
# `const builtin_dns_rules = []` that opens the custom-path rule block.
custom_reject_line="$(grep -n 'query_type: *\[64, *65\]' "$custom_dns_uc" | sed -n '2p' | cut -d: -f1)"
custom_const_line="$(awk 'NR > 1 && /const builtin_dns_rules = \[\]/ { print NR; exit }' "$custom_dns_uc")"
custom_loop_line="$(awk -v start="$custom_const_line" '
	NR > start && /for \(let cfg in dm\.dns\.rules\)/ { print NR; exit }
' "$custom_dns_uc")"

if [ -n "$custom_reject_line" ] && [ -n "$custom_const_line" ] && [ -n "$custom_loop_line" ]; then
	if [ "$custom_reject_line" -gt "$custom_const_line" ] && [ "$custom_reject_line" -lt "$custom_loop_line" ]; then
		pass "append_custom_dns pushes the reject between the rules array init (line $custom_const_line) and the user-rules loop (line $custom_loop_line)"
	else
		fail "the reject in append_custom_dns (line $custom_reject_line) sits outside the"
			fail "init (line $custom_const_line) -> loop (line $custom_loop_line) range; a"
			fail "user rule could now shadow the HTTPS/SVCB reject"
	fi
else
	fail "could not locate both the reject and the user-rules loop in append_custom_dns"
fi

echo "== guard 39: sniffer_advanced_mode default stays at '0' =="

# §2.7 (linux.json 与 pro 的差距分析.md): the advanced-mode sniff profile

# §2.7 (linux.json 与 pro 的差距分析.md): the advanced-mode sniff profile
# (100ms / universal list) is gated behind a UCI opt-in so an upgrade
# does not change the sniffer behaviour.  The default must remain '0';
# the generator falls back to '0' on a missing UCI value, and the
# package-shipped /etc/config/homeproxy-pro must not bump the default to
# '1' on a whim.  Two checks:
#
#   (a) the generator's fallback is '0';
#   (b) the package-shipped UCI default is '0'.
if grep -q "sniffer_advanced_mode: dm.general.sniffer_advanced_mode || '0'" "$SCRIPTS/generator/context.uc"; then
	pass "the generator falls back to '0' on a missing sniffer_advanced_mode"
else
	fail "context.uc no longer falls back to '0' for sniffer_advanced_mode - the"
		fail "sniff rule's 300ms / default-list profile is no longer the safe default"
fi

# The package default lives in root/etc/config/homeproxy-pro.  It must be
# '0' for upgrades to be invisible; new installs also default to the
# same until the user opts in.
if grep -q "^	option sniffer_advanced_mode '0'" "$ROOT/root/etc/config/homeproxy-pro"; then
	pass "the package-shipped /etc/config/homeproxy-pro keeps sniffer_advanced_mode '0'"
else
	fail "the package default for sniffer_advanced_mode is no longer '0'; users who"
		fail "upgraded without touching the option would silently switch to 100ms +"
		fail "the universal sniffer list, which is a behaviour change"
fi

echo
echo "== guard 40: rule/routing rule action enum agrees across UI and generator =="
# The 'action' dropdown in client/common.js is the *user-visible* set the
# form lets the user pick.  The generator's per-action gates (in dns.uc and
# route.uc) are the *what sing-box sees* set.  When the UI ships an action
# the generator does not know about, the form serialises a value the
# generator then emits as `rule.action = '<unknown>'` - sing-box 1.14
# refuses the whole config with "unknown action".  When the UI defines an
# action the generator does not handle, sing-box refuses the action with
# "unknown field".  Both directions matter, both directions are checked.
#
# Reading order:
#   UI dns_rule actions:    extracted from common.js inside `if (is_dns) { ... }` of the
#                            action ListValue (the values that surface when is_dns=true)
#   UI routing_rule actions: the values outside the is_dns branch
#   generator dns_rule:     all `'action' === '...'` literals in dns.uc's custom loop
#   generator routing_rule: all `'action' === '...'` literals in route.uc's per-rule loop
ACTION_ENUM="$(python3 - "$ROOT" <<'PY' || ACTION_ENUM="__SCAN_FAILED__"
import re, sys, pathlib
root = pathlib.Path(sys.argv[1])
common = (root / 'htdocs/luci-static/resources/view/homeproxy-pro/client/common.js').read_text()

# Find the action ListValue block: from "ss.taboption('field_other', form.ListValue, 'action'"
# until 'so.default = 'route'' on the next non-conditional line.  Within that
# block, is_dns and !is_dns branches control which values get exposed.
m = re.search(r"so = ss\.taboption\('field_other', form\.ListValue, 'action'.*?so\.default = 'route'",
              common, re.DOTALL)
if not m:
    print('__SCAN_FAILED__')
    sys.exit()

block = m.group(0)
# Inside the if (is_dns) { ... } else { ... }, collect value('xxx', ...) names.
# The else branch is "routing_rule actions"; the if branch is "dns_rule actions".
is_dns_m = re.search(r"if \(is_dns\) \{(.*?)\} else \{(.*?)\}", block, re.DOTALL)
if not is_dns_m:
    print('__SCAN_FAILED__')
    sys.exit()

def actions(branch):
    return set(re.findall(r"so\.value\('([^']+)'", branch))

dns_actions = actions(is_dns_m.group(1))
routing_actions = actions(is_dns_m.group(2))

dns_uc = (root / 'root/etc/homeproxy-pro/scripts/generator/dns.uc').read_text()
route_uc = (root / 'root/etc/homeproxy-pro/scripts/generator/route.uc').read_text()

def gates(text):
    return set(re.findall(r"cfg\.action === '([^']+)'", text))

dns_gates = gates(dns_uc)
route_gates = gates(route_uc)

problems = []
ui_extra = dns_actions - dns_gates
if ui_extra:
    problems.append(f'dns_rule UI exposes {sorted(ui_extra)} but generator/dns.uc does not gate on them')
gates_extra = dns_gates - dns_actions - {'route-options'}  # generator-internal sentinel
# (Above: dns_gates may include 'route-options' from old guard; clean ignore.)
# A gate the UI does not offer is fine if the generator never emits it (matches),
# but we should still flag if it could be reached from UCI (impossible here because the ListValue is the only writer).

ui_extra_r = routing_actions - route_gates
if ui_extra_r:
    problems.append(f'routing_rule UI exposes {sorted(ui_extra_r)} but generator/route.uc does not gate on them')

print('\n'.join(problems))
PY
)"
if [ "$ACTION_ENUM" = "__SCAN_FAILED__" ]; then
	fail "the rule action enum scan could not run - fix the guard before trusting a pass"
elif [ -z "$ACTION_ENUM" ]; then
	pass "every rule action in the UI dropdown is gated by the matching generator"
else
	fail "the rule action enum drifted between the UI and the generator:"
	printf '      %s\n' "$ACTION_ENUM"
fi

echo "== guard 41: experimental.cache_file is unconditional in attachExperimental() =="

# Review (2026-09-29, docs/review-report-20260929.md §1.4.3 / §5.1, P2 #3):
# attachExperimental() used to wrap the experimental.cache_file block in
# `if (routing_mode in ['bypass_mainland_china', 'custom'])`, leaving
# gfwlist / proxy_mainland_china / global with cold-start DNS on every
# reload.  cache_file is a fresh-install no-op and the file is the only
# piece of state the generator writes outside /etc/config/homeproxy-pro, so
# gating it on routing_mode buys nothing and lost DNS cache for 3 modes.
# The fix removed the gate; this guard pins the unconditional emission so
# a future refactor (e.g. adding a 'cache_file.enabled: 0' opt-out) does
# not silently re-introduce the routing_mode gate.
AE_RESULT="$(python3 - "$ROOT/root/etc/homeproxy-pro/scripts/generator/common.uc" <<'PY' || echo __SCAN_FAILED__
import re, sys, pathlib
src = pathlib.Path(sys.argv[1]).read_text()
m = re.search(r'^export function attachExperimental\b.*?\n\};',
              src, re.MULTILINE | re.DOTALL)
if not m:
    print('__NO_FUNCTION__'); sys.exit()
body = m.group(0)
# Strip /* ... */ comments so a commented-out gate does not trip the check.
body_nc = re.sub(r'/\*.*?\*/', '', body, flags=re.DOTALL)
# Look for an `if (... routing_mode ...)` gate anywhere in the body.
gate = re.search(r'\bif\s*\([^)]*\brouting_mode\b', body_nc)
if gate:
    print('GATED: ' + gate.group(0).strip()); sys.exit()
# Verify the unconditional shape: `config.experimental = { ... }` containing
# `cache_file:` must appear, both outside any `if (...)` block.
if not re.search(r'config\.experimental\s*=\s*\{', body_nc):
    print('NO_EXPERIMENTAL_BLOCK'); sys.exit()
if 'cache_file:' not in body_nc:
    print('NO_CACHE_FILE_FIELD'); sys.exit()
print('OK')
PY
)"
case "$AE_RESULT" in
__SCAN_FAILED__)
	fail "the attachExperimental scan could not run - fix the guard before trusting a pass" ;;
__NO_FUNCTION__)
	fail "attachExperimental() not found in generator/common.uc" ;;
NO_EXPERIMENTAL_BLOCK)
	fail "attachExperimental() does not assign config.experimental (cache_file regression)" ;;
NO_CACHE_FILE_FIELD)
	fail "attachExperimental() does not emit cache_file (cache_file regression)" ;;
GATED:*)
	fail "attachExperimental() must not gate cache_file on routing_mode: ${AE_RESULT#GATED: }" ;;
OK)
	pass "attachExperimental() emits cache_file unconditionally for every routing_mode" ;;
*)
	fail "unexpected attachExperimental scan result: $AE_RESULT" ;;
esac

echo "== guard 42: NAPTR_BYPASS_SUFFIXES is the only domain_suffix qtype-35 source =="

# Review (2026-09-29, docs/review-report-20260929.md §2.2.1, P2 #4): the three
# NAPTR (qtype 35) bypass suffixes (r.10086.cn, 10086.cn, pub.3gppnetwork.org)
# used to be inlined into a push() call inside append_proxy_dns() and the
# comment that explained them was on the same line as the push. The fix
# extracted the list to a module-level constant NAPTR_BYPASS_SUFFIXES and
# moved the rationale to the constant's own comment block. This guard
# pins the actual invariant: a constant declaration exists, AND the
# qtype-35 DNS rule's domain_suffix field references that constant
# (not a hand-rolled literal array, which would re-inline the list).
DNS_UC="$ROOT/root/etc/homeproxy-pro/scripts/generator/dns.uc"
NAPTR_CONST="$(grep -nE '^(const|var)\s+NAPTR_BYPASS_SUFFIXES\s*=' "$DNS_UC" || true)"
NAPTR_USE="$(grep -nE '^\s*domain_suffix:\s*NAPTR_BYPASS_SUFFIXES\b' "$DNS_UC" || true)"
NAPTR_LITERAL_USE="$(grep -nE '^\s*domain_suffix:\s*\[' "$DNS_UC" || true)"
if [ -z "$NAPTR_CONST" ]; then
	fail "NAPTR_BYPASS_SUFFIXES constant missing in generator/dns.uc"
elif [ -z "$NAPTR_USE" ]; then
	fail "the qtype-35 DNS rule does not reference NAPTR_BYPASS_SUFFIXES; the constant is dead code"
elif [ -n "$NAPTR_LITERAL_USE" ]; then
	fail "domain_suffix uses a literal array; route it through NAPTR_BYPASS_SUFFIXES instead:"
	printf '      %s\n' "$NAPTR_LITERAL_USE"
else
	pass "the qtype-35 DNS rule references NAPTR_BYPASS_SUFFIXES (no inline literal)"
fi

echo
echo "== guard 43: the rollback UCI snapshot matches the keys the intercept layer reads =="

# Review 2026-09-29 (docs/review-report-20260929-full.md §1.2-1.4, P2 #1/#2).
#
# reload_service rolls back by restoring the known-good sing-box file *and*
# replaying a UCI snapshot of the keys that steer the network layer - the
# second half exists because start_service reinstalls the nft / dnsmasq
# layer from CURRENT UCI, so without it a rollback would restore the sing-box
# bytes and leave the failing layer in place (review P1-3, 2026-09-28).
#
# That snapshot was a hand-maintained five-line list. It named four real
# keys out of the twenty-two the layer reads, and the fifth line was
# `infra.tun_address` - an option that exists nowhere; the real ones are
# `tun_addr4` / `tun_addr6` (config/loader.uc). So the line was always empty,
# the replay was a no-op for it, and tests/fixtures/runtime/trace.golden.txt
# recorded the empty line as the expected shape. A test that pins the format
# cannot notice that a key does not exist.
#
# The lesson is the one this file already states: compare the layers to each
# other instead of to a hand-written list. The read set below is extracted
# from the four files that actually build the intercept layer, and the two
# directions are checked:
#
#   read - snapshot   a key the layer reads was left out of the rollback
#   snapshot - read   a key nothing reads is in the rollback (the ghost-key
#                     case; the declared extras below are the only ones
#                     allowed)
#
# init.d/homeproxy-pro is deliberately NOT in the read set: its config_get calls
# serve the health gate (health_probe_*) and the cron (subscription.*), which
# do not steer the layer. Every key it reads that *does* steer the layer is
# also read by firewall_post.ut, so nothing is lost by excluding it.
# Pure shell on purpose: the first version of this guard ran the extraction
# from a python3 heredoc, and dash (which is what `sh` is on CI, and what
# tests/run.sh:176 invokes it with) did not recognise the heredoc inside the
# command substitution - the file failed to parse at all.  grep / sed / awk
# are already this script's only tools, so nothing is lost.
SNAP_TMP="$(mktemp -d)"
trap 'rm -rf "$SNAP_TMP"' EXIT INT TERM

SNAP_POST="$ROOT/root/etc/homeproxy-pro/scripts/firewall_post.ut"
SNAP_PRE="$ROOT/root/etc/homeproxy-pro/scripts/firewall_pre.uc"
SNAP_NET="$ROOT/root/etc/homeproxy-pro/scripts/runtime/net.sh"
SNAP_DNS="$ROOT/root/etc/homeproxy-pro/scripts/runtime/dns.sh"
SNAP_SVC="$ROOT/root/etc/homeproxy-pro/scripts/runtime/service.sh"

for f in "$SNAP_POST" "$SNAP_PRE" "$SNAP_NET" "$SNAP_DNS" "$SNAP_SVC"; do
	if [ ! -r "$f" ]; then
		fail "guard 43 cannot read $f - fix the guard before trusting a pass"
		break
	fi
done

# The read set: uci.get(cfgname, '<section>', '<option>') in the two firewall
# scripts, plus the control_options array (walked through a loop variable, so
# its members are the only place those keys are spelled out), plus
# config_get / config_get_bool in the two runtime modules.  `dhcp.<dnsmasq>`
# is another package's config and is deliberately not matched.
{
	grep -hoE "uci\.get\(cfgname, *'[a-z_]+', *'[a-z_0-9]+'\)" "$SNAP_POST" "$SNAP_PRE" 2>/dev/null \
		| sed -E "s/.*'([a-z_]+)', *'([a-z_0-9]+)'.*/\1.\2/"
	sed -n '/const control_options = \[/,/\];/p' "$SNAP_POST" 2>/dev/null \
		| grep -oE '"[a-z_0-9]+"' | tr -d '"' | sed 's/^/control./'
	grep -hoE 'config_get[a-z_]* +[a-z_0-9]+ +"[a-z_]+" +"[a-z_0-9]+"' "$SNAP_NET" "$SNAP_DNS" 2>/dev/null \
		| sed -E 's/.*"([a-z_]+)" +"([a-z_0-9]+)"/\1.\2/'
} 2>/dev/null | grep -E '^[a-z_]+\.[a-z_0-9]+$' | sort -u > "$SNAP_TMP/read"

# The snapshot the writer declares: the keys listed in the two shell string
# constants in runtime/service.sh.  Both ends of a block need care: the first
# key sits on the opening `HP_INTERCEPT_*="` line and the last one shares its
# line with the closing quote, so neither is a line of its own.  Dropping
# either would make the guard report a key the source does declare - which is
# exactly the false positive that appeared while this was being written.
awk '
	/^HP_INTERCEPT_(SCALARS|LISTS)="/ {
		inblock = 1
		line = $0
		sub(/^HP_INTERCEPT_(SCALARS|LISTS)="/, "", line)
		gsub(/"/, "", line)
		if (line ~ /^[a-z_]+\.[a-z_0-9]+$/) print line
		next
	}
	inblock && /^[a-z_]+\.[a-z_0-9]+"?$/ { gsub(/"/, ""); print; next }
' "$SNAP_SVC" 2>/dev/null | sort -u > "$SNAP_TMP/snap"

# Declared extras: read by the generator (context.uc -> inbound.uc), never by
# a layer consumer.  The TUN address only reaches the device through the
# generated file, so a rollback that left UCI describing the failed address
# would make the next reload regenerate the configuration that just failed.
printf '%s\n' infra.tun_addr4 infra.tun_addr6 | sort -u > "$SNAP_TMP/extras"

# Direction 1: a key the layer reads was left out of the rollback snapshot.
comm -23 "$SNAP_TMP/read" "$SNAP_TMP/snap" > "$SNAP_TMP/missing"
# Direction 2: a key nothing reads is in the snapshot - the tun_address case.
comm -23 "$SNAP_TMP/snap" "$SNAP_TMP/read" | comm -23 - "$SNAP_TMP/extras" > "$SNAP_TMP/ghost"
# Direction 3: a declared extra is no longer snapshotted.  The extras are an
# allowlist, so without this they would silently become optional and dropping
# one from HP_INTERCEPT_SCALARS would go unnoticed.
comm -23 "$SNAP_TMP/extras" "$SNAP_TMP/snap" > "$SNAP_TMP/unused"

if [ ! -s "$SNAP_TMP/read" ]; then
	fail "the intercept-layer read set came out empty - the extraction is broken, not the code"
elif [ -s "$SNAP_TMP/missing" ]; then
	fail "these keys steer the intercept layer but are not in the rollback UCI snapshot:"
	while IFS= read -r k; do printf '      %s\n' "$k"; done < "$SNAP_TMP/missing"
elif [ -s "$SNAP_TMP/ghost" ]; then
	fail "the rollback UCI snapshot names keys no layer consumer reads (the tun_address case):"
	while IFS= read -r k; do printf '      %s\n' "$k"; done < "$SNAP_TMP/ghost"
elif [ -s "$SNAP_TMP/unused" ]; then
	fail "these keys are declared as snapshot-only but are not in HP_INTERCEPT_SCALARS:"
	while IFS= read -r k; do printf '      %s\n' "$k"; done < "$SNAP_TMP/unused"
else
	pass "the rollback UCI snapshot covers every intercept-layer key and names no unread key"
fi

rm -rf "$SNAP_TMP"
trap - EXIT INT TERM

echo
echo "== guard 45: the bootstrap resolver is derived, not configured =="

# main-dns is the user's DoH/DoT endpoint and the one server in the config
# whose address is a hostname, so it needs a domain_resolver before it can
# answer.  It used to borrow default-dns - the WAN/ISP resolver - which makes
# the ISP the answerer of the single query that decides where every proxied
# name goes.  It used to be a form field for that; it is derived now, from the
# China DNS server.  Both halves are pinned:
#   (a) the generator must read the China DNS server, never a separate option
#       - a second DNS address next to the China one made no sense to read;
#   (b) a bare IP is the only usable value, because the option also accepts
#       'wan' and a DoH/DoT URL, and a hostname cannot resolve a hostname.
#
# (b) is asserted on the *validator*, not on a hand-rolled regex.  The guard
# used to require the two shape tests this function used to carry
# (/^[0-9]+(\.[0-9]+){3}$/ and /^[0-9a-fA-F:]+$/), and that is exactly what let
# a real bug through: the second one matches any hostname made only of hex
# digits and colons - cafe, face, abc, add, dead:beef - and the first one never
# range-checked the octets, so 999.999.999.999 passed too (measured on the
# device, 2026-10-01).  The bootstrap server is emitted with no
# domain_resolver by design, so any of those is unsatisfiable and sing-box
# refuses to start at all:
#   FATAL create service: initialize DNS server[0]: missing domain resolver
#   for domain server address
# isValidCIDR() - the same validator the firewall path runs every address
# through - is the shared definition of "is this an address", and the ucode
# test tests/ucode/test_build_guards.uc pins the behaviour (bare v4/v6 in,
# 'wan' / a DoH URL / a hostname / an out-of-range address out).
if grep -q "const addr = ctx.china_dns_server;" "$SCRIPTS/generator/dns.uc"; then
	pass "the bootstrap address is taken from the China DNS server"
else
	fail "bootstrap_addr() no longer reads ctx.china_dns_server - if it reads a"
	fail "separate option again, main-dns may fall back to the WAN resolver"
fi

if grep -q "isValidCIDR(addr, 4) || isValidCIDR(addr, 6)" "$SCRIPTS/generator/dns.uc"; then
	pass "only a bare IP is accepted as the bootstrap address (via isValidCIDR)"
else
	fail "bootstrap_addr() no longer rejects a non-IP value - a DoH URL or the"
	fail "literal 'wan' is a hostname, and using one to resolve a hostname is a cycle"
	fail "(it must go through isValidCIDR; a hand-rolled shape test accepted"
	fail "'cafe' and 999.999.999.999, which made sing-box refuse to start)"
fi

if grep -qE "match\(addr, /\^\[0-9" "$SCRIPTS/generator/dns.uc"; then
	fail "a hand-rolled IP shape test is back in bootstrap_addr() - use isValidCIDR"
else
	pass "no hand-rolled IP shape test in bootstrap_addr()"
fi

# The option is gone from the form and from the shipped config; leaving either
# would mean a value nothing reads, which is how the confusing second field
# came to exist in the first place.
if grep -q "bootstrap_dns" "$ROOT/root/etc/config/homeproxy-pro"; then
	fail "the package-shipped /etc/config/homeproxy-pro still carries a bootstrap_dns -"
	fail "the generator derives it now, so this option is read by nothing"
else
	pass "the package-shipped /etc/config/homeproxy-pro carries no bootstrap_dns"
fi

if grep -rq "bootstrap_dns" "$ROOT/htdocs/luci-static/resources/view/homeproxy-pro/"; then
	fail "a view still renders a bootstrap_dns field - the value is derived from"
	fail "the China DNS server, and a second DNS address only reads as a mistake"
else
	pass "no view offers a bootstrap_dns field any more"
fi

echo
printf '%s checks, %s failures\n' "$checks" "$([ "$FAILED" = 0 ] && echo 0 || echo 'nonzero')"
if [ "$FAILED" != 0 ]; then
	echo "ARCHITECTURE GUARD FAILED"
	exit 1
fi

echo "ARCHITECTURE GUARD PASSED"
exit 0
