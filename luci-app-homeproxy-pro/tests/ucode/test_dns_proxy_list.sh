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
#      (the WAN/ISP resolver) for that lookup, which makes the ISP the
#      answerer of the one query that decides where every proxied name goes.
#      The resolver is derived from the China DNS server now, so both halves
#      of that rule are asserted: a bare IP there yields a bootstrap-dns that
#      main-dns points at and which carries no domain_resolver of its own,
#      and a hostname there yields no bootstrap server at all (a hostname
#      cannot resolve the hostname it would be needed to resolve).
#
# Usage: sh tests/ucode/test_dns_proxy_list.sh <repo-root> [work-dir]

ROOT="${1:-.}"
WORK="${2:-/tmp/hp-dns-proxy-list-test}"

ROOT="$(cd "$ROOT" && pwd)"
FIXTURE="$ROOT/tests/fixtures/generators/client.uci"
DIRECT_DOMAIN="direct.example.cn"
PROXY_DOMAIN="play.example.cn"
CHINA_DNS_IP="223.5.5.5"
CHINA_DNS_DOH="https://dns.alidns.com/dns-query"
FAILED=0

rm -rf "$WORK"
mkdir -p "$WORK"

# Stage the checkout the way test_generators.sh does: HP_DIR/RUN_DIR/UCICONFIG_DIR
# are rewritten into the work dir and the fixture is copied in as the UCI
# config.  The fixture carries no china_dns_server (the generator then falls
# back to the Aliyun public resolver), so the line is inserted into the
# `config` section here - the section the Loader reads it from.  It has to be
# inserted rather than substituted for that reason.
stage_case() {
	dir="$1"
	label="$2"
	china_dns="$3"
	fixture="$4"

	rm -rf "$dir"
	mkdir -p "$dir/config" "$dir/run" "$dir/scripts/config" "$dir/scripts/generator" \
		"$dir/scripts/parser" "$dir/resources"

	cp "$fixture" "$dir/config/homeproxy-pro"
	if [ -n "$china_dns" ]; then
		sed -i "/^\toption routing_mode /i\\
\toption china_dns_server '$china_dns'
" "$dir/config/homeproxy-pro"
	fi

	# Both lists are populated on purpose.  direct_list.txt is what makes the
	# direct-domain DNS rule appear at all, and the generator documents that
	# proxy-domain sits after it; with only one of the two the relative order
	# is untestable.
	printf '%s\n' "$DIRECT_DOMAIN" > "$dir/resources/direct_list.txt"
	printf '%s\n' "$PROXY_DOMAIN" > "$dir/resources/proxy_list.txt"

	# The client config carries a `type: local` rule-set generated from
	# china_ip4.txt; sing-box opens that path during `check`, and on a router
	# hp_prepare_runtime_files generates it before the config is used.
	if ! ucode -S "$ROOT/root/etc/homeproxy-pro/scripts/runtime/china_ip_ruleset.uc" \
		"$ROOT/root/etc/homeproxy-pro/resources/china_ip4.txt" "$dir/resources/china_ip4.json" \
		>>"$dir/resources/china_ip4.log" 2>&1; then
		printf '{"version":3,"rules":[{"ip_cidr":["192.0.2.0/24"]}]}\n' > "$dir/resources/china_ip4.json"
	fi

	# The DNS half of the China split.  generate_client.uc reports it as
	# ctx.china_domain_ready, an lstat on this file; absent, the domestic
	# lookup rule is not emitted and the ordering this file asserts cannot be
	# observed at all.  On a router hp_prepare_runtime_files generates it from
	# china_list.txt by the same route as china_ip4.json above.
	if ! ucode -S "$ROOT/root/etc/homeproxy-pro/scripts/runtime/domain_ruleset.uc" \
		"$ROOT/root/etc/homeproxy-pro/resources/china_list.txt" "$dir/resources/china-domain.json" \
		>>"$dir/resources/china-domain.log" 2>&1; then
		printf '{"version":3,"rules":[{"domain_suffix":["example.invalid"]}]}\n' > "$dir/resources/china-domain.json"
	fi

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

# The mode's default policy, asserted as a *pair*.  The DNS chain and the
# route chain each end in a fallback (`dns.final`, `route.final`), and they
# have to name the same side: a domain that ends up proxied must be resolved
# by the proxy-path resolver, and one that ends up direct must not be
# resolved through the proxy.  The two were literals in different modules with
# nothing tying them together, and the route side applied "unknown goes to the
# proxy" to all four modes - so "Only proxy mainland China" proxied everything
# it was not told to proxy.
check_fallback_pair() {
	label="$1"
	json="$2"

	case "$label" in
	proxy_mainland_china) want_route="direct-out"; want_dns="default-dns" ;;
	*)                    want_route="main-out";   want_dns="main-dns" ;;
	esac

	# The two finals sit in different blocks and their relative order is not
	# fixed (route.final is emitted before dns.final in the modes whose dns
	# block grows, after it in the others), so each is taken from its own
	# block: dns.final is the only '"final"' indented by two tabs inside the
	# top-level dns object, route.final the only one inside route.
	have_dns="$(awk '/^\t"dns": \{/{d=1} d && /^\t\t"final":/{gsub(/.*: "|".*/,""); print; exit}' "$json")"
	have_route="$(awk '/^\t"route": \{/{r=1} r && /^\t\t"final":/{gsub(/.*: "|".*/,""); print; exit}' "$json")"

	if [ "$have_route" != "$want_route" ]; then
		echo "FAIL: $label: route.final is '$have_route', the mode's policy is '$want_route'"
		return 1
	fi
	if [ "$have_dns" != "$want_dns" ]; then
		echo "FAIL: $label: dns.final is '$have_dns', the mode's policy is '$want_dns'"
		return 1
	fi
	# Stated as its own property, because the failure it catches is silent:
	# if one of the two ever gains a new value, the pair is what breaks.
	proxy_route=no; proxy_dns=no
	[ "$have_route" = "main-out" ] && proxy_route=yes
	[ "$have_dns" = "main-dns" ] && proxy_dns=yes
	if [ "$proxy_route" != "$proxy_dns" ]; then
		echo "FAIL: $label: route.final ($have_route) and dns.final ($have_dns) disagree on the mode's default"
		return 1
	fi

	echo "PASS: $label: route.final=$have_route and dns.final=$have_dns agree"

	# Both mainland modes match destinations against the local china-ip
	# rule-set, so both have to declare it.  proxy_mainland_china reached this
	# point without the declaration once and sing-box refused the whole config
	# with "initialize rule[3]: rule-set not found"; the health gate then
	# rolled the intercept layer back and the network went unproxied.
	case "$label" in
	bypass_mainland_china|proxy_mainland_china)
		if ! grep -qF '"rule_set": "china-ip"' "$json" || ! grep -qF '"tag": "china-ip"' "$json"; then
			echo "FAIL: $label: the route rule matches china-ip but the rule-set is not declared"
			return 1
		fi
		;;
	esac

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
		china_domain_rule="$(grep -nF '"rule_set": "china-domain"' "$json" | head -1 | cut -d: -f1)"
		if [ -z "$china_domain_rule" ] || [ "$china_domain_rule" -lt "$dns_rule" ]; then
			echo "FAIL: $label: china-domain must come after proxy-domain (proxy=$dns_rule china-domain=${china_domain_rule:-none})"
			return 1
		fi
		;;
	esac

	return 0
}

# --- 1. bootstrap resolver, derived from a bare-IP China DNS server ---------

dir="$WORK/bootstrap"
if stage_case "$dir" "bootstrap" "$CHINA_DNS_IP" "$FIXTURE"; then
	json="$dir/run/sing-box-c.json"

	bootstrap_line="$(grep -nF '"tag": "bootstrap-dns"' "$json" | head -1 | cut -d: -f1)"
	if [ -z "$bootstrap_line" ]; then
		echo "FAIL: bootstrap: a bare-IP China DNS server produced no bootstrap-dns server"
		FAILED=1
	elif ! sed -n "$bootstrap_line,$((bootstrap_line + 4))p" "$json" | grep -qF "\"$CHINA_DNS_IP\""; then
		echo "FAIL: bootstrap: bootstrap-dns does not carry the China DNS server ($CHINA_DNS_IP)"
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
			echo "PASS: bootstrap: main-dns resolves its own hostname through bootstrap-dns ($CHINA_DNS_IP)"
		fi
	fi
else
	FAILED=1
fi

# --- 2. a hostname China DNS server is not a usable bootstrap --------------
# The option also accepts a DoH/DoT URL, and a URL is a hostname: using one to
# resolve the hostname it would be needed to resolve is the cycle this whole
# mechanism exists to avoid.  It must fall back to the WAN resolver, loudly
# enough to be visible here, rather than to a broken bootstrap.

dir="$WORK/hostname"
if stage_case "$dir" "hostname" "$CHINA_DNS_DOH" "$FIXTURE"; then
	json="$dir/run/sing-box-c.json"
	if grep -qF '"tag": "bootstrap-dns"' "$json"; then
		echo "FAIL: hostname: a DoH China DNS server was used as the bootstrap resolver"
		FAILED=1
	elif ! grep -qF '"server": "default-dns"' "$json"; then
		echo "FAIL: hostname: no bootstrap server and main-dns does not use default-dns either"
		FAILED=1
	else
		echo "PASS: hostname: a DoH China DNS server yields no bootstrap server, main-dns uses default-dns"
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
		check_fallback_pair "$mode" "$dir/run/sing-box-c.json"
	else
		FAILED=1
	fi
done

exit $FAILED
