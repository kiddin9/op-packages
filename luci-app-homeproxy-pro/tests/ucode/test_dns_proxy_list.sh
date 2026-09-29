#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
#
# Two properties of the proxy-mode DNS block that the generator regression
# suite cannot see, because run_case() truncates the resource lists and uses a
# fixture without the bootstrap option:
#
#   1. The proxy-domain resource list has to reach the DNS block in *every*
#      proxy routing mode, not only in bypass_mainland_china.
#
#      proxy_list.txt is the user's escape hatch for a domain the preset lists
#      mis-classify - the canonical case is Google Play, whose
#      connect.googleapis.cn resolves through the domestic resolver and then
#      stays direct, so the store cannot update.  The routing half
#      (route.uc pushes the proxy-domain rule_set to main-out) has always been
#      emitted in all the proxy modes, while the DNS half used to be nested
#      inside the bypass_mainland_china branch.  In global / gfwlist /
#      proxy_mainland_china a listed domain therefore still resolved through
#      the domestic resolver; only the bypass mode did the right thing.
#
#   2. The bootstrap resolver: the DoH/DoT endpoint (main-dns) is the only
#      server whose address is a hostname, and it used to borrow default-dns
#      (the WAN/ISP resolver) for that lookup.  When the user configures a
#      bootstrap resolver, main-dns must point at it instead, and that server
#      must stay at the bottom of the chain (no domain_resolver of its own,
#      no DNS rule routing to it) or the lookup depends on itself.
#
# Usage: sh tests/ucode/test_dns_proxy_list.sh <repo-root> [work-dir]

ROOT="${1:-.}"
WORK="${2:-/tmp/hp-dns-proxy-list-test}"

ROOT="$(cd "$ROOT" && pwd)"
FIXTURE="$ROOT/tests/fixtures/generators/client.uci"
DIRECT_DOMAIN="direct.example.cn"
PROXY_DOMAIN="play.example.cn"
BOOTSTRAP_DNS="223.5.5.5"
FAILED=0

rm -rf "$WORK"
mkdir -p "$WORK"

# Stage the checkout the way test_generators.sh does: HP_DIR/RUN_DIR/UCICONFIG_DIR
# are rewritten into the work dir and the fixture is copied in as the UCI
# config.  The extra bootstrap line is appended to the `config` section here
# (the section's first named section), which is how the Loader reads it.
stage_case() {
	dir="$1"
	label="$2"
	bootstrap="$3"
	fixture="$4"

	rm -rf "$dir"
	mkdir -p "$dir/config" "$dir/run" "$dir/scripts/config" "$dir/scripts/generator" \
		"$dir/scripts/parser" "$dir/resources"

	cp "$fixture" "$dir/config/homeproxy-pro"
	if [ -n "$bootstrap" ]; then
		sed -i "/^\toption routing_mode /i\\
\toption bootstrap_dns '$bootstrap'
" "$dir/config/homeproxy-pro"
	fi

	# Both lists are populated on purpose.  direct_list.txt is what makes the
	# direct-domain DNS rule appear at all, and the generator documents that
	# proxy-domain sits after it; with only one of the two the relative order
	# is untestable.
	printf '%s\n' "$DIRECT_DOMAIN" > "$dir/resources/direct_list.txt"
	printf '%s\n' "$PROXY_DOMAIN" > "$dir/resources/proxy_list.txt"

	VALIDATE_DATA="${HP_VALIDATE_DATA:-/sbin/validate_data}"
	sed -e "s#^export const HP_DIR = '/etc/homeproxy-pro';#export const HP_DIR = '$dir';#" \
	    -e "s#^export const RUN_DIR = '/var/run/homeproxy-pro';#export const RUN_DIR = '$dir/run';#" \
	    -e "s#^export const UCICONFIG_DIR = '/etc/config';#export const UCICONFIG_DIR = '$dir/config';#" \
	    -e "s#/sbin/validate_data#${VALIDATE_DATA}#" \
	    "$ROOT/root/etc/homeproxy-pro/scripts/homeproxy-pro.uc" > "$dir/scripts/homeproxy-pro.uc"

	cp "$ROOT/root/etc/homeproxy-pro/scripts/config/loader.uc"  "$dir/scripts/config/"
	cp "$ROOT/root/etc/homeproxy-pro/scripts/config/model.uc"   "$dir/scripts/config/"
	cp "$ROOT/root/etc/homeproxy-pro/scripts/config/adapter.uc" "$dir/scripts/config/"
	cp "$ROOT/root/etc/homeproxy-pro/scripts/parser/"*.uc       "$dir/scripts/parser/"
	cp "$ROOT/root/etc/homeproxy-pro/scripts/generator/"*.uc    "$dir/scripts/generator/"
	cp "$ROOT/root/etc/homeproxy-pro/scripts/generate_client.uc" "$dir/scripts/generate_client.uc"

	# macOS: `sing-box check` rejects the SO_MARK-based routing_mark on a
	# direct outbound (Linux-only), so the generator copy emits null there.
	# Same patch as test_generators.sh, applied to the same module.
	case "$(uname -s)" in
	Darwin)
		sed -i '' "s#routing_mark: strToInt(.*self_mark)#routing_mark: null#" \
			"$dir/scripts/generator/client.uc"
		;;
	esac

	if ! ( cd "$dir/scripts" && ucode -L "$dir/scripts" generate_client.uc > "$dir/generate.out" 2> "$dir/generate.err" ); then
		echo "FAIL: $label: generate_client.uc exited non-zero"
		head -5 "$dir/generate.err"
		return 1
	fi

	json="$dir/run/sing-box-c.json"
	if [ ! -s "$json" ]; then
		echo "FAIL: $label: no client configuration was generated"
		head -5 "$dir/generate.err"
		return 1
	fi

	if ! sing-box check --config "$json"; then
		echo "FAIL: $label: sing-box rejected the generated configuration"
		return 1
	fi

	return 0
}

# The rule_set assertions, shared by every case: the list reaches the config,
# the DNS half resolves through main-dns ahead of the SVCB/HTTPS reject, and
# direct-domain keeps its precedence.
check_proxy_list() {
	label="$1"
	json="$2"

	if ! grep -qF "$PROXY_DOMAIN" "$json"; then
		echo "FAIL: $label: proxy_list.txt never reached the generated config"
		return 1
	fi

	dns_rule="$(grep -nF '"rule_set": "proxy-domain"' "$json" | head -1 | cut -d: -f1)"
	if [ -z "$dns_rule" ]; then
		echo "FAIL: $label: no proxy-domain rule_set in the generated config"
		return 1
	fi

	if ! sed -n "$((dns_rule + 1)),$((dns_rule + 4))p" "$json" | grep -qF '"main-dns"'; then
		echo "FAIL: $label: the proxy-domain DNS rule does not resolve through main-dns:"
		sed -n "$((dns_rule - 3)),$((dns_rule + 4))p" "$json"
		return 1
	fi

	reject_line="$(grep -nF '"query_type": [' "$json" | head -1 | cut -d: -f1)"
	if [ -n "$reject_line" ] && [ "$dns_rule" -gt "$reject_line" ]; then
		echo "FAIL: $label: the proxy-domain DNS rule is emitted after the SVCB/HTTPS reject"
		return 1
	fi

	# A domain present in both lists keeps direct-domain first: the
	# relocation into the shared prefix must not have reversed the
	# precedence the bypass block used to have.
	direct_rule="$(grep -nF '"rule_set": "direct-domain"' "$json" | head -1 | cut -d: -f1)"
	if [ -z "$direct_rule" ] || [ "$direct_rule" -gt "$dns_rule" ]; then
		echo "FAIL: $label: direct-domain must be the first DNS rule (direct=${direct_rule:-none} proxy=$dns_rule)"
		return 1
	fi

	# In the one mode that has both, the domestic lookup still comes last.
	case "$label" in
	bypass_mainland_china*)
		geosite_rule="$(grep -nF '"rule_set": "geosite-cn"' "$json" | head -1 | cut -d: -f1)"
		if [ -z "$geosite_rule" ] || [ "$geosite_rule" -lt "$dns_rule" ]; then
			echo "FAIL: $label: geosite-cn must come after proxy-domain (proxy=$dns_rule geosite=${geosite_rule:-none})"
			return 1
		fi
		;;
	esac

	return 0
}

# --- 1. bootstrap resolver -------------------------------------------------

dir="$WORK/bootstrap"
if stage_case "$dir" "bootstrap" "$BOOTSTRAP_DNS" "$FIXTURE"; then
	json="$dir/run/sing-box-c.json"

	bootstrap_line="$(grep -nF '"tag": "bootstrap-dns"' "$json" | head -1 | cut -d: -f1)"
	if [ -z "$bootstrap_line" ]; then
		echo "FAIL: bootstrap: no bootstrap-dns server was emitted"
		FAILED=1
	elif ! sed -n "$bootstrap_line,$((bootstrap_line + 4))p" "$json" | grep -qF "\"$BOOTSTRAP_DNS\""; then
		echo "FAIL: bootstrap: bootstrap-dns does not carry $BOOTSTRAP_DNS"
		FAILED=1
	elif sed -n "$bootstrap_line,$((bootstrap_line + 4))p" "$json" | grep -qF '"domain_resolver"'; then
		echo "FAIL: bootstrap: the bootstrap resolver has a domain_resolver of its own"
		FAILED=1
	else
		# main-dns is the only hostname-addressed server, so it is the only
		# one allowed to point at the bootstrap resolver.
		main_line="$(grep -nF '"tag": "main-dns"' "$json" | head -1 | cut -d: -f1)"
		if [ -z "$main_line" ]; then
			echo "FAIL: bootstrap: no main-dns server was emitted"
			FAILED=1
		elif ! sed -n "$main_line,$((main_line + 6))p" "$json" | grep -qF '"server": "bootstrap-dns"'; then
			echo "FAIL: bootstrap: main-dns still resolves through the WAN resolver"
			FAILED=1
		else
			echo "PASS: bootstrap: main-dns resolves its own hostname through bootstrap-dns ($BOOTSTRAP_DNS)"
		fi
	fi
else
	FAILED=1
fi

# --- 2. the default (no bootstrap configured) ------------------------------

dir="$WORK/default"
if stage_case "$dir" "default" "" "$FIXTURE"; then
	json="$dir/run/sing-box-c.json"
	if grep -qF '"tag": "bootstrap-dns"' "$json"; then
		echo "FAIL: default: an unconfigured bootstrap resolver was emitted"
		FAILED=1
	elif ! grep -qF '"server": "default-dns"' "$json"; then
		echo "FAIL: default: main-dns no longer resolves through the WAN resolver"
		FAILED=1
	else
		echo "PASS: default: no bootstrap server, main-dns still resolves through default-dns"
	fi
else
	FAILED=1
fi

# --- 3. proxy-domain in every proxy routing mode ---------------------------

# One case per proxy routing mode.  Custom mode is deliberately absent: it
# ignores both resource lists (context.uc gates their inputs on
# `routing_mode !== 'custom'`) and has its own user-defined dns_rule sections.
for mode in bypass_mainland_china global gfwlist proxy_mainland_china; do
	dir="$WORK/$mode"
	sed "s#^\(\s*option routing_mode \).*#\1'$mode'#" "$FIXTURE" > "$WORK/fixture-$mode.uci"
	if stage_case "$dir" "$mode" "" "$WORK/fixture-$mode.uci"; then
		if check_proxy_list "$mode" "$dir/run/sing-box-c.json"; then
			echo "PASS: $mode: direct-domain < proxy-domain via main-dns < SVCB/HTTPS reject"
		else
			FAILED=1
		fi
	else
		FAILED=1
	fi
done

exit $FAILED
