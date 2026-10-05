#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
#
# Render firewall_post.ut and verify the homeproxy-pro fw4 objects survive as real
# nft statements.
#
# The template opens with `{%-`, which trims the whitespace in front of it: any
# text placed above that tag loses its trailing newline and is glued onto the
# first generated statement, turning it into a comment. That silently dropped
# every homeproxy-pro chain/set from the fw4 ruleset once, so keep this check.
#
# Two layers, because the render needs the real `fw4` ucode module which only
# exists on a device (OpenWrt's firewall4 package ships /usr/share/ucode/fw4.uc):
#
#   1. a source-level assertion, always run, that the glue condition itself
#      cannot come back - `{%-` must be the first thing after the shebang, so
#      there is no preceding text whose newline could be trimmed;
#   2. the render + structural assertions, run whenever `fw4` is resolvable,
#      skipped with an explicit NOT RUN otherwise. A stub fw4 would make this
#      layer run everywhere, but it would also mean asserting on a ruleset the
#      real fw4 never produced, so the skip is kept and made *enforceable*
#      instead: HP_REQUIRE_FW4=1 turns it into a failure. tests/run.sh sets that
#      in its ssh branch, because a target always has firewall4 - so the one
#      environment that can run this layer must run it, and a target that
#      somehow cannot is a failure rather than a quiet NOT RUN.
#
#      `utpl` is not the blocker: it ships with ucode, which
#      tests/toolchain/build-ucode-linux.sh builds. The missing piece is
#      firewall4's /usr/share/ucode/fw4.uc.
#
# Usage: sh tests/ucode/test_firewall_template.sh <repo-root> [work-dir]

ROOT="${1:-.}"
ROOT="$(cd "$ROOT" && pwd)"
FAILED=0

TEMPLATE_SRC="$ROOT/root/etc/homeproxy-pro/scripts/firewall_post.ut"

# --- layer 1: the glue condition cannot come back ------------------------
# `{%-` trims the whitespace before it, so anything other than the shebang
# ahead of the tag ends up glued onto the first rendered line. Read the tag
# position directly instead of trusting a comment.
first_tag_line="$(grep -n '{%-' "$TEMPLATE_SRC" | head -1 | cut -d: -f1)"

if [ -z "$first_tag_line" ]; then
	echo "FAIL: firewall_post.ut has no '{%-' template tag"
	FAILED=1
else
	# Lines 1..(tag-1) must be blank or the shebang.
	bad="$(sed -n "1,$((first_tag_line - 1))p" "$TEMPLATE_SRC" |
		grep -nvE '^[[:space:]]*$|^#!/' || true)"
	if [ -n "$bad" ]; then
		echo "FAIL: text precedes the '{%-' tag and will be glued onto the first statement"
		echo "$bad" | head -3
		FAILED=1
	fi
fi

# --- R-08: the gfwlist gate follows the dnsmasq nftset capability ----------
# The gate compares the destination against the set dnsmasq fills with
# `nftset=`.  On a dnsmasq built without HAVE_NFTSET that set stays empty and
# `ip daddr != @<empty set>` is true for every packet, so gfwlist mode would
# silently route everything direct.  The template therefore reads the
# capability from resources/.dnsmasq-nftset - written by init.d before the
# render - and must omit the gate when it says "no".
#
# This is asserted at the source level, not by rendering gfwlist mode: the
# renderer runs with the device's own UCI (routing_mode = bypass_mainland_china
# on any normal router, including this suite's host), so the gfwlist branch is
# not reachable from here at all.  What is checkable is that every gate is
# wrapped and that the helper reads the marker the way init.d writes it.
# The declaration `{% if (routing_mode === 'gfwlist'): %}` in front of the set
# is data, not a gate; the gates are the same condition with a trailing colon.
GATED="$(grep -c "routing_mode === 'gfwlist' && dnsmasq_nftset()" "$TEMPLATE_SRC")"
UNGATED="$(grep -c "routing_mode === 'gfwlist'):" "$TEMPLATE_SRC")"

if [ "$GATED" -lt 4 ]; then
	echo "FAIL: only $GATED gfwlist gates carry the nftset capability check (expected 4:"
	echo "      the LAN redirect, the UDP tproxy, the local output and the include chain)"
	FAILED=1
fi
# Exactly one ungated condition is expected: the one that declares the set the
# gates match against.  Every additional one is a gate, and a gate over an empty
# set is true for every packet.
if [ "$UNGATED" -ne 1 ]; then
	echo "FAIL: $UNGATED ungated 'routing_mode === 'gfwlist'' conditions in the template"
	echo "      (exactly 1 is expected - the set declaration; the rest are gates)"
	FAILED=1
fi
if ! grep -q "resources_dir + '/.dnsmasq-nftset'" "$TEMPLATE_SRC"; then
	echo "FAIL: the template does not read resources/.dnsmasq-nftset, the marker init.d writes"
	FAILED=1
fi
if ! grep -q '\.dnsmasq-nftset' "$ROOT/root/etc/init.d/homeproxy-pro"; then
	echo "FAIL: init.d no longer records the dnsmasq nftset capability for the template"
	FAILED=1
fi

# --- layer 2: the render -------------------------------------------------
# The render output and its stderr live beside the staged template, never at a
# fixed /tmp path.  A caller that passes a work dir (tests/ucode/run.sh hands
# every sub-suite a directory under its own $WORK) gets the pieces under it;
# with no argument each run gets its own mktemp -d instead.  Either way no two
# runs share a path, and the whole stage goes away on every exit path - this
# used to leak a directory per run (50 of them had accumulated on the test
# device), which is both untidy and a determinism problem.
if [ -n "${2:-}" ]; then
	STAGE="$2/firewall_template"
	rm -rf "$STAGE"
	mkdir -p "$STAGE"
	OWN_STAGE=0
else
	STAGE="$(mktemp -d "${TMPDIR:-/tmp}/hp-fwtpl.XXXXXX")"
	OWN_STAGE=1
fi
STAGED="$STAGE/firewall_post.ut"
OUT="$STAGE/rendered.nft"
ERR="$STAGE/render.err"
trap '[ "$OWN_STAGE" = 1 ] && rm -rf "$STAGE"' EXIT INT TERM

# --- the node-address bypass is not gated on the literal-address file ------
#
# This is a source-level check, not a render one, on purpose.  The render layer
# below is skipped wherever firewall4 is absent - which is every off-target
# run - and the failure this pins is one that renders perfectly and does
# nothing: with a host-name node there are no literal addresses, so a set and
# rules gated on "the literal list is non-empty" simply are not emitted, and
# dnsmasq's nftset= back-fill has no set to land in.  r41 shipped that.
#
# The invariant, stated so it can be grepped: `node_addr_v4` may guard the
# `elements = { ... }` line and nothing else.  Deciding whether the set and the
# return rules exist at all belongs to node_protect, which is true when either
# export file has content.
if ! grep -q 'function node_addr_protected(run_dir)' "$TEMPLATE_SRC"; then
	echo "FAIL: firewall_post.ut has no node_addr_protected(); the node bypass cannot"
	echo "      distinguish 'nothing to protect' from 'a host name dnsmasq will resolve'"
	FAILED=1
else
	np_body="$(sed -n '/function node_addr_protected(run_dir)/,/^}/p' "$TEMPLATE_SRC")"
	for f in node-addr-ips.txt node-addr-domains.txt; do
		if ! printf '%s' "$np_body" | grep -q "$f"; then
			echo "FAIL: node_addr_protected() does not look at $f"
			FAILED=1
		fi
	done
	[ "$FAILED" -eq 0 ] && echo "PASS: node_addr_protected() covers both export files"
fi

# Both helpers read run_dir, and they are defined ~80 lines above its
# declaration.  In this ucode a closure captures the block variables that exist
# where the function is DEFINED, so a function defined earlier cannot see a
# const declared later - the call fails with "access to undeclared variable
# run_dir" while run_dir sits right there in the file.  Passing it in is the
# only spelling that works, and r43 is what proved it.
for fn in node_addr_protected node_addr_to_nftarr; do
	if ! grep -q "function $fn(run_dir" "$TEMPLATE_SRC"; then
		echo "FAIL: $fn does not take run_dir as a parameter; in this ucode a closure only"
		echo "      sees block variables declared before the function definition, and both"
		echo "      helpers are defined above run_dir"
		FAILED=1
	fi
done
[ "$FAILED" -eq 0 ] && echo "PASS: the node-address helpers take run_dir as a parameter"

# Every consumer of the v4 set outside its own elements= line must be gated on
# node_protect.  `node_addr_v4)` as a condition is exactly the mistake.
stray_gate="$(awk '
	/if \(node_addr_v4/ {
		# The one legitimate use guards the elements= line that follows it.
		saw = 1; ln = NR; next
	}
	saw {
		if ($0 ~ /elements *= *\{/) { saw = 0; next }
		print "      " ln ": " $0
		saw = 0
	}
' "$TEMPLATE_SRC" || true)"
if [ -n "$stray_gate" ]; then
	echo "FAIL: the node-address set is gated on node_addr_v4 having elements; a host-name"
	echo "      node has none, and the set plus its return rules then never exist:"
	printf '      %s\n' "$stray_gate"
	FAILED=1
fi

# And the return rules themselves must be present in all three chains, each
# behind node_protect rather than behind a literal-address list.
for chain in redirect mangle_prerouting mangle_output; do
	if ! grep -q "$chain" "$TEMPLATE_SRC"; then
		echo "FAIL: chain $chain disappeared from firewall_post.ut"
		FAILED=1
	fi
done
# Asserted per chain, not as a global count.  The global count is what this
# check used to be ("expected 3"), and it is exactly how the missing rule went
# unnoticed: the TUN chain needed one and the assertion counted the three that
# already existed.  The four chains below are the ones that steer traffic into
# the tunnel or the redirect/tproxy port - each must exempt the node's own
# address once, so a new chain that starts steering traffic has to be added
# here (and the operator reading the diff sees why).
for chain in homeproxy_redirect homeproxy_mangle_prerouting homeproxy_mangle_output homeproxy_mangle_tun; do
	body="$(awk -v c="$chain" 'index($0, "chain " c " {") == 1 { f = 1 } f { print } f && /^}/ { exit }' "$TEMPLATE_SRC")"
	n="$(printf '%s\n' "$body" | grep -c 'ip daddr @homeproxy_node_addr_v4 counter return' || true)"
	if [ "$n" -eq 1 ]; then
		echo "PASS: $chain carries exactly one node-address return rule"
	else
		echo "FAIL: $chain carries $n node-address return rules (expected exactly 1)"
		FAILED=1
	fi
done

# Probe with ucode, not utpl: `utpl -e` is not an eval flag, it renders the
# argument as template text and always succeeds.
if ! ucode -e 'require("fw4");' > "/dev/null" 2>&1; then
	echo "NOT RUN: the 'fw4' ucode module is not available (device-only), render skipped"

	# A skipped layer must not be able to hide a broken template. Firewall4 is
	# always installed where homeproxy-pro runs, so the on-target suite sets
	# HP_REQUIRE_FW4=1 (tests/run.sh does it in the ssh branch) and a skip there
	# is a failure: it means the render stopped being exercised in the one
	# environment that can exercise it. `utpl` itself is not the blocker - it
	# ships with ucode, which the toolchain builds - the missing piece is
	# firewall4's /usr/share/ucode/fw4.uc, and stubbing that would mean
	# asserting on a ruleset the real fw4 never produced.
	if [ "${HP_REQUIRE_FW4:-0}" = "1" ]; then
		echo "FAIL: HP_REQUIRE_FW4=1 but 'fw4' is not resolvable, so the render"
		echo "      layer cannot run here and the template is unverified"
		exit 1
	fi

	[ "$FAILED" -eq 0 ] && echo "PASS: firewall_post.ut keeps '{%-' directly after the shebang"
	exit $FAILED
fi

# Where the render reads its UCI from.
#
#   * on a target: the real /etc/config - the render has to see the
#     configuration that is actually deployed;
#   * anywhere else (CI): tests/fixtures/firewall/render.uci, so this layer -
#     the only one that turns the template into nft text - runs in CI instead
#     of reporting NOT RUN.  That is T1's other half: the module it needs is
#     staged by the toolchain (tests/toolchain/build-ucode-linux.sh) and the
#     configuration it reads is staged here.
#
# HP_T_FW4_CONFIG_DIR overrides both, which is how the fixture path itself is
# exercised on a device (real fw4, fixture config).
FW4_CONFIG_DIR="${HP_T_FW4_CONFIG_DIR:-}"
if [ -z "$FW4_CONFIG_DIR" ] && [ ! -f "/etc/config/homeproxy-pro" ]; then
	FW4_CONFIG_DIR="$STAGE/cfg"
	mkdir -p "$FW4_CONFIG_DIR"
	cp "$ROOT/tests/fixtures/firewall/render.uci" "$FW4_CONFIG_DIR/homeproxy-pro"
	cp "$ROOT/tests/fixtures/firewall/dhcp" "$FW4_CONFIG_DIR/dhcp"
fi

# The template is written for a device: it imports homeproxy-pro.uc through
# /etc/homeproxy-pro/scripts/ and reads /etc/homeproxy-pro/resources. Neither exists
# off-target, so render a staged copy with those prefixes rewritten to the
# checkout - the same trick run.sh uses for the absolute import in
# root/usr/share/rpcd/ucode/luci.homeproxy-pro.  The cursor is rewritten too when
# the UCI comes from the fixture rather than from /etc/config.
if [ -n "$FW4_CONFIG_DIR" ]; then
	sed -e "s#'/etc/homeproxy-pro/#'$ROOT/root/etc/homeproxy-pro/#g" \
	    -e "s#^const uci = cursor();#const uci = cursor('$FW4_CONFIG_DIR');#" \
	    "$TEMPLATE_SRC" > "$STAGED"
else
	sed -e "s#'/etc/homeproxy-pro/#'$ROOT/root/etc/homeproxy-pro/#g" "$TEMPLATE_SRC" > "$STAGED"
fi

# Hard guard: the cursor rewrite has to have matched, or the render silently
# reads a configuration that is not there (and the assertions would be about a
# ruleset nobody asked for).
if [ -n "$FW4_CONFIG_DIR" ] && ! grep -qF "cursor('$FW4_CONFIG_DIR')" "$STAGED"; then
	echo "FAIL: firewall_post.ut: could not point the render at $FW4_CONFIG_DIR"
	echo "      (the 'const uci = cursor();' anchor no longer matches)"
	exit 1
fi

# Hard guard: if the prefix ever changes, the sed silently no-ops and the
# render fails for an unrelated reason, which would look like a template
# regression. Refuse to run instead.
if grep -q "'/etc/homeproxy-pro/" "$STAGED"; then
	echo "FAIL: firewall_post.ut: could not rewrite the device paths"
	echo "      (the '/etc/homeproxy-pro/' prefix anchor no longer matches)"
	exit 1
fi

if ! utpl -S "$STAGED" > "$OUT" 2> "$ERR"; then
	echo "FAIL: could not render firewall_post.ut"
	head -5 "$ERR"
	exit 1
fi

# Declared unconditionally by the template, so they must always be present as
# standalone statements.
for name in homeproxy_local_addr_v4 homeproxy_wan_proxy_addr_v4; do
	if ! grep -q "^set $name {" "$OUT"; then
		echo "FAIL: 'set $name {' is missing from the rendered firewall template"
		grep -n "$name" "$OUT" | head -2
		FAILED=1
	fi
done

# A statement glued onto the preceding comment looks like
# "# <comment text>.set homeproxy_x {" -- exactly the failure mode above.
if grep -nE "^#[^!].*homeproxy_[a-z0-9_]+ \{" "$OUT" > "/dev/null"; then
	echo "FAIL: an nft statement is glued onto a comment line"
	grep -nE "^#[^!].*homeproxy_[a-z0-9_]+ \{" "$OUT" | head -2
	FAILED=1
fi

if [ "$FAILED" -eq 0 ]; then
	echo "PASS: firewall_post.ut renders homeproxy-pro objects as standalone nft statements"
	echo "PASS: the gfwlist gate follows the dnsmasq nftset capability"
fi

# The wan guard (S4): with `listen_interfaces` empty the intercept layer has to
# exclude the wan zone's devices.  Two ways this went wrong on the device and
# both render *something*, which is why the assertion is not just "a guard is
# there":
#
#   - r46 shipped a template whose guard silently disappeared: fw4 had no state
#     in this process (`zones()` is null outside fw4's own render), the loop
#     threw, the catch swallowed it, and the rendered chain had no iifname at
#     all - the exact hole the guard was added to close;
#   - resolving it from /var/run/fw4.state instead yields the LOGICAL names
#     ("wan", "wan_6"), so `meta iifname { wan }` renders and can never match.
#
# Resolving zone devices needs ubus, so off-target runs report SKIP rather than
# pretending: the render needs fw4's real zone data for this one.
GUARD_IFACES="$(grep -oE 'meta iifname( !=)? \{[^}]*\}' "$OUT" | sort -u | tr '\n' ' ')"
case "$GUARD_IFACES" in
*'{ wan }'*|*'{ wan,'*|*'wan_6 }'*|*'wan_6,'*)
	echo "FAIL: the wan guard rendered a logical network name, which never matches:"
	echo "      $GUARD_IFACES"
	FAILED=1
	;;
esac

if grep -q 'not the WAN side' "$OUT"; then
	echo "PASS: the wan guard is rendered (resolved devices: ${GUARD_IFACES:-none})"
elif ubus -v list network.interface > "/dev/null" 2>&1; then
	echo "FAIL: the wan guard is missing although fw4 could resolve zone devices"
	FAILED=1
else
	echo "SKIP: the wan guard needs ubus to resolve zone devices (not available here)"
fi

exit $FAILED
