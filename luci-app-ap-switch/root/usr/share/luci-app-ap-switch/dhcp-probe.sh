#!/bin/sh

[ "$1" = "bound" ] || exit 0
[ -n "$ip" ] || exit 0

# Ignore DHCP offers from the local router itself (dnsmasq on br-lan)
if [ -n "$serverid" ]; then
	if [ -n "$AP_SWITCH_LOCAL_IP" ] && [ "$serverid" = "$AP_SWITCH_LOCAL_IP" ]; then
		exit 0
	fi
	local_ips=$(ip -4 -o addr show dev br-lan 2>/dev/null | awk '{print $4}' | cut -d/ -f1)
	for lip in $local_ips; do
		[ "$serverid" = "$lip" ] && exit 0
	done
fi

echo "$ip" > /tmp/ap_switch_probed_ip
