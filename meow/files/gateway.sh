#!/bin/sh
# Transparent-proxy rules for traffic forwarded through this router.

. /lib/functions.sh
. /lib/functions/network.sh

TABLE="inet meow_gateway"
RULES=/var/run/meow/gateway.nft
FWMARK=0x2333
ROUTING_MARK=0x2537
ROUTE_TABLE=233

load_config() {
	config_load meow
	config_get interface tproxy interface lan
	config_get mode tproxy mode tproxy
	config_get tproxy_port tproxy tproxy_port 7893
	config_get_bool dns_hijack tproxy dns_hijack 1
	config_get dns_port tproxy dns_port 1053
	config_get_bool ipv6 tproxy ipv6 0
	config_get bypass tproxy bypass ''
	config_get bypass_mac tproxy bypass_mac ''
	bypass_mac=$(echo "$bypass_mac" | tr 'A-F' 'a-f')
}

validate_config() {
    case "$mode:$ipv6" in redirect:0|redirect:1|tproxy:0) ;; *) return 1 ;; esac
    for port in "$tproxy_port" "$dns_port"; do
        case "$port" in ''|*[!0-9]*) return 1 ;; esac
        [ "$port" -ge 1 ] && [ "$port" -le 65535 ] || return 1
    done
    case "$interface" in ''|*[!a-zA-Z0-9_.:-]*) return 1 ;; esac
    for cidr in $bypass; do
        case "$cidr" in *[!0-9a-fA-F.:/]*|'') return 1 ;; esac
    done
}

port_listening() {
	local hex
	hex=$(printf '%04X' "$1")
	grep -qE "^ *[0-9]+: [0-9A-F]+:$hex [0-9A-F]+:[0-9A-F]+ 0A" \
		/proc/net/tcp /proc/net/tcp6 2>/dev/null
}

gen_rules() {
	local device="$1" extra4="" extra6="" macs="" cidr mac
	for cidr in $bypass; do
		case "$cidr" in
			*:*) extra6="$extra6, $cidr" ;;
			*) extra4="$extra4, $cidr" ;;
		esac
	done
	for mac in $bypass_mac; do
		macs="${macs:+$macs, }$mac"
	done

	cat <<-NFT
	table inet meow_gateway {
		set reserved4 {
			type ipv4_addr; flags interval; auto-merge
			elements = {
				0.0.0.0/8, 10.0.0.0/8, 100.64.0.0/10, 127.0.0.0/8,
				169.254.0.0/16, 172.16.0.0/12, 192.168.0.0/16,
				224.0.0.0/4, 240.0.0.0/4$extra4
			}
		}
		set reserved6 {
			type ipv6_addr; flags interval; auto-merge
			elements = { ::/128, ::1/128, fc00::/7, fe80::/10, ff00::/8$extra6 }
		}
		set bypass_src {
			type ether_addr;
		NFT
	[ -n "$macs" ] && echo "		elements = { $macs }"
	cat <<-NFT
		}

		chain dstnat {
			type nat hook prerouting priority dstnat - 5; policy accept;
			iifname != "$device" return
			meta mark $ROUTING_MARK return
			ether saddr @bypass_src return
	NFT
	[ "$dns_hijack" -eq 1 ] && echo "		meta nfproto ipv4 meta l4proto udp th dport 53 redirect to :$dns_port"
	[ "$ipv6" -eq 1 ] || echo "		meta nfproto ipv6 return"
	cat <<-NFT
			fib daddr type local return
			ip daddr @reserved4 return
			ip6 daddr @reserved6 return
			meta l4proto tcp redirect to :$tproxy_port
		}
	NFT

	if [ "$mode" != redirect ]; then
		cat <<-NFT

		chain mangle_tproxy {
			type filter hook prerouting priority mangle; policy accept;
			iifname != "$device" return
			meta mark $ROUTING_MARK return
			ether saddr @bypass_src return
		NFT
		[ "$dns_hijack" -eq 1 ] && echo "		meta l4proto udp th dport 53 return"
		[ "$ipv6" -eq 1 ] || echo "		meta nfproto ipv6 return"
		cat <<-NFT
			fib daddr type local return
			ip daddr @reserved4 return
			ip6 daddr @reserved6 return
			meta l4proto udp socket transparent 1 meta mark set $FWMARK accept
			meta l4proto udp tproxy to :$tproxy_port meta mark set $FWMARK accept
		}
		NFT
	fi
	echo "}"
}

route_up() {
	ip rule add fwmark $FWMARK lookup $ROUTE_TABLE || return 1
	ip route replace local 0.0.0.0/0 dev lo table $ROUTE_TABLE || return 1
	if [ "$ipv6" -eq 1 ]; then
		ip -6 rule add fwmark $FWMARK lookup $ROUTE_TABLE
		ip -6 route replace local ::/0 dev lo table $ROUTE_TABLE
	fi
}

route_down() {
	while ip rule del fwmark $FWMARK lookup $ROUTE_TABLE 2>/dev/null; do :; done
	ip route flush table $ROUTE_TABLE 2>/dev/null
	while ip -6 rule del fwmark $FWMARK lookup $ROUTE_TABLE 2>/dev/null; do :; done
	ip -6 route flush table $ROUTE_TABLE 2>/dev/null
	return 0
}

case "$1" in
    run)
        child=''
        trap '[ -z "$child" ] || kill "$child" 2>/dev/null; "$0" down; exit 0' TERM INT
        "$0" wait & child=$!
        wait "$child" || exit 1
        child=''
        "$0" up || exit 1
        while :; do sleep 3600 & child=$!; wait "$child"; done
        ;;
	up)
		load_config
		validate_config || { logger -t meow "gateway: invalid configuration"; exit 1; }
		network_get_device device "$interface"
		[ -n "$device" ] || exit 1
		case "$device" in *[!a-zA-Z0-9_.:-]*) exit 1 ;; esac
		mkdir -p "${RULES%/*}"
		gen_rules "$device" > "$RULES"
		nft -c -f "$RULES" || exit 1
		nft delete table $TABLE 2>/dev/null
		route_down
		nft -f "$RULES" || exit 1
		if [ "$mode" = redirect ]; then
			logger -t meow "gateway: redirect $device tcp -> :$tproxy_port"
		else
			route_up || { "$0" down; exit 1; }
			logger -t meow "gateway: tproxy $device tcp(redirect)+udp -> :$tproxy_port"
		fi
		;;
	down)
		nft delete table $TABLE 2>/dev/null
		route_down
		;;
	wait)
		load_config
		i=0
		while [ $i -lt 150 ]; do
			port_listening "$tproxy_port" && exit 0
			sleep 0.2
			i=$((i + 1))
		done
		logger -t meow "gateway: :$tproxy_port not listening after 30s"
		exit 0
		;;
	status)
		nft list table $TABLE
		;;
	*)
		echo "usage: $0 up|down|wait|status" >&2
		exit 1
		;;
esac
