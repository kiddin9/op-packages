# SPDX-License-Identifier: GPL-2.0-only
#
# Copyright (C) 2025 ImmortalWrt.org
#
# Routing/network plumbing for homeproxy.
#
# The tproxy and TUN paths need ip rules, a routing table and (for TUN) the
# device itself before procd starts sing-box, and they need to be torn down
# again on stop.  All of that used to live inline in /etc/init.d/homeproxy.
#
# Layering note: this is a device-side module.  It calls `log` and, like the
# other runtime modules, requires `config_load` to have run (it reads the
# infra marks and the TUN device name itself).
#
# Sourced by /etc/init.d/homeproxy.

# hp_net_wait_wan [seconds]
# Block until a default route or an "up" wan interface exists.  Bounded: after
# the timeout sing-box is started anyway, because a missing default route is
# a common transient state at boot and refusing to start would be worse.
hp_net_wait_wan() {
	local limit="${1:-60}"
	local wan_waited=0

	while ! { ip route show default 2>"/dev/null" | grep -q . \
		|| ip -6 route show default 2>"/dev/null" | grep -q . \
		|| ifstatus wan 2>"/dev/null" | grep -q '"up": true'; }; do
		wan_waited=$((wan_waited + 1))
		if [ "$wan_waited" -ge "$limit" ]; then
			log "WARNING: No network route after ${limit}s, starting sing-box anyway."
			break
		fi
		sleep 1
	done
}

# hp_net_try <描述> <命令...>
# Run a step that may legitimately fail, logging the wrapped message.
hp_net_try() {
	local message="$1"; shift
	"$@" 2>"/dev/null" || log "Error: ${message}"
}

# hp_net_rule_add <family> <fwmark> <table> <描述>
# Install one ip rule idempotently.  `ip rule add` has no replace form and the
# kernel appends a second identical rule instead of reporting a conflict, so a
# repeated start (rc.common's `start` never calls stop_service) used to leave
# duplicates behind.  The teardown side already drains them with `while del`;
# this is the matching install side.  family is "" for ip, "-6" for ip -6.
hp_net_rule_add() {
	local family="$1" mark="$2" table="$3" message="$4"

	while ip $family rule del fwmark "$mark" table "$table" 2>"/dev/null"; do :; done
	hp_net_try "$message" ip $family rule add fwmark "$mark" table "$table"
}

# hp_net_setup <proxy-mode> <routing-mode>
# Create the tproxy or TUN routing state for the configured proxy mode.
# Requires config_load.
#
# Every step is idempotent on purpose: `start` on an already-running service
# re-runs this function without a preceding teardown.  The old code reported
# "failed to add the tproxy local route (table 100)" on every such start
# (EEXIST from `ip route add`) while silently appending a duplicate ip rule.
# Routes use `replace`, rules are drained before they are added, and the TUN
# device is only created when it does not already exist.
hp_net_setup() {
	local proxy_mode="$1"
	local routing_mode="$2"
	local ipv6_support table_mark outbound_udp_node tproxy_mark tun_name tun_mark

	config_get_bool ipv6_support "config" "ipv6_support" "0"
	config_get table_mark "infra" "table_mark" "100"

	case "$proxy_mode" in
	"redirect_tproxy")
		config_get outbound_udp_node "config" "main_udp_node" "nil"
		if [ "$outbound_udp_node" != "nil" ] || [ "$routing_mode" = "custom" ]; then
			config_get tproxy_mark "infra" "tproxy_mark" "101"

			hp_net_rule_add "" "$tproxy_mark" "$table_mark" \
				"failed to add the tproxy ip rule (fwmark ${tproxy_mark}, table ${table_mark})."
			hp_net_try "failed to add the tproxy local route (table ${table_mark})." \
				ip route replace local 0.0.0.0/0 dev lo table "$table_mark"

			if [ "$ipv6_support" -eq "1" ]; then
				hp_net_rule_add "-6" "$tproxy_mark" "$table_mark" \
					"failed to add the tproxy IPv6 rule (fwmark ${tproxy_mark}, table ${table_mark})."
				hp_net_try "failed to add the tproxy IPv6 local route (table ${table_mark})." \
					ip -6 route replace local ::/0 dev lo table "$table_mark"
			fi
		fi
		;;
	"redirect_tun"|"tun")
		config_get tun_name "infra" "tun_name" "singtun0"
		config_get tun_mark "infra" "tun_mark" "102"

		# Only wait after a real creation: the old unconditional `sleep 1s`
		# delayed every start (including reloads) even when the device was
		# already present.
		if ! ip link show "$tun_name" >"/dev/null" 2>&1; then
			hp_net_try "failed to create the TUN device ${tun_name}." \
				ip tuntap add mode tun user root name "$tun_name"
			sleep 1s
		fi
		hp_net_try "failed to bring up the TUN device ${tun_name}." \
			ip link set "$tun_name" up

		hp_net_try "failed to set the TUN default route (table ${table_mark})." \
			ip route replace default dev "$tun_name" table "$table_mark"
		hp_net_rule_add "" "$tun_mark" "$table_mark" \
			"failed to add the TUN ip rule (fwmark ${tun_mark}, table ${table_mark})."

		if [ "$ipv6_support" -eq "1" ]; then
			hp_net_try "failed to set the TUN IPv6 default route (table ${table_mark})." \
				ip -6 route replace default dev "$tun_name" table "$table_mark"
			hp_net_rule_add "-6" "$tun_mark" "$table_mark" \
				"failed to add the TUN IPv6 rule (fwmark ${tun_mark}, table ${table_mark})."
		fi
		;;
	esac
}

# hp_net_teardown
# Remove every tproxy/TUN rule and route homeproxy added.  Requires
# config_load.
#
# ip rule del removes a single matching rule, so a repeated start (or an
# upgrade that starts before the old instance stopped) leaves duplicates
# behind.  Delete every match instead of only the first one.
hp_net_teardown() {
	local table_mark tproxy_mark tun_mark tun_name

	config_get table_mark "infra" "table_mark" "100"
	config_get tproxy_mark "infra" "tproxy_mark" "101"
	config_get tun_mark "infra" "tun_mark" "102"
	config_get tun_name "infra" "tun_name" "singtun0"

	while ip rule del fwmark "$tproxy_mark" table "$table_mark" 2>"/dev/null"; do :; done
	ip route del local 0.0.0.0/0 dev lo table "$table_mark" 2>"/dev/null"
	while ip -6 rule del fwmark "$tproxy_mark" table "$table_mark" 2>"/dev/null"; do :; done
	ip -6 route del local ::/0 dev lo table "$table_mark" 2>"/dev/null"

	ip route del default dev "$tun_name" table "$table_mark" 2>"/dev/null"
	while ip rule del fwmark "$tun_mark" table "$table_mark" 2>"/dev/null"; do :; done

	ip -6 route del default dev "$tun_name" table "$table_mark" 2>"/dev/null"
	while ip -6 rule del fwmark "$tun_mark" table "$table_mark" 2>"/dev/null"; do :; done
}

# hp_net_remove_tun
# service_stopped() hook on the genuine-stop path only (HP_RELOAD_IN_PROGRESS=0):
# procd calls it after the instances are gone, so the TUN device can be removed.
# Requires config_load.
#
# On the reload path (HP_RELOAD_IN_PROGRESS=1) the caller skips this entirely,
# so the device survives across the stop;start that reload_service drives; the
# table-100 default route is therefore not pulled mid-reload - the
# "tun mode reload exposes the LAN with the real IP" failure that the previous
# TODO documented (review P2, 2026-09-28) is the issue the caller now closes.
hp_net_remove_tun() {
	local tun_name

	config_get tun_name "infra" "tun_name" "singtun0"

	ip link set "$tun_name" down 2>"/dev/null"
	ip tuntap del mode tun name "$tun_name" 2>"/dev/null"
}
