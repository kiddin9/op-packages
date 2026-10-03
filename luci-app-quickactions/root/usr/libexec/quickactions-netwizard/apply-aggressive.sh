#!/bin/sh
# Aggressive rebuild — matches source netwizard behaviour. Called only if user opts in.

MODE="$1"; LAN_IP="$2"; PPPOE_USER="$3"; PPPOE_PASS="$4"; WAN_IFACE="$5"
[ -z "$MODE" ] && MODE="dhcp"
[ -z "$LAN_IP" ] && LAN_IP="192.168.10.1"

BACKUP_DIR="/etc/config.bak.$(date +%s)"
mkdir -p "$BACKUP_DIR"
for f in network firewall dhcp wireless system wizard netwizard; do
    [ -f /etc/config/$f ] && cp /etc/config/$f "$BACKUP_DIR/"
done
echo "Backup saved to $BACKUP_DIR"

if [ -z "$WAN_IFACE" ]; then
    WAN_IFACE=$(uci -q get network.wan.device)
    [ -z "$WAN_IFACE" ] && WAN_IFACE=$(ls /sys/class/net/ 2>/dev/null | grep -E '^(eth[01]|wan)' | head -n1)
    [ -z "$WAN_IFACE" ] && WAN_IFACE="eth1"
fi

uci -q delete network.wan 2>/dev/null
uci -q delete network.wan6 2>/dev/null
uci -q delete network.lan6 2>/dev/null

WAN_IDX=$(uci show firewall | sed -n "s/^firewall\.@zone\[\([0-9]*\)\]\.name='wan'$/\1/p")
[ -n "$WAN_IDX" ] && uci -q delete firewall.@zone[$WAN_IDX] 2>/dev/null

if [ "$MODE" = "siderouter" ]; then
    LAN_IDX=$(uci show firewall | sed -n "s/^firewall\.@zone\[\([0-9]*\)\]\.name='lan'$/\1/p")
    [ -n "$LAN_IDX" ] && uci -q delete firewall.@zone[$LAN_IDX].masq 2>/dev/null
    uci set network.lan=interface
    uci set network.lan.proto='static'
    uci set network.lan.ipaddr="$LAN_IP"
    uci set network.lan.netmask='255.255.255.0'
else
    uci set network.wan=interface
    uci set network.wan.device="$WAN_IFACE"
    if [ "$MODE" = "pppoe" ]; then
        uci set network.wan.proto='pppoe'
        [ -n "$PPPOE_USER" ] && uci set network.wan.username="$PPPOE_USER"
        [ -n "$PPPOE_PASS" ] && uci set network.wan.password="$PPPOE_PASS"
    else
        uci set network.wan.proto='dhcp'
    fi
    uci set network.wan6=interface
    uci set network.wan6.device="@wan"
    uci set network.wan6.proto='dhcpv6'

    uci add firewall zone >/dev/null
    uci set firewall.@zone[-1].name='wan'
    uci set firewall.@zone[-1].input='REJECT'
    uci set firewall.@zone[-1].output='ACCEPT'
    uci set firewall.@zone[-1].forward='REJECT'
    uci set firewall.@zone[-1].masq='1'
    uci set firewall.@zone[-1].mtu_fix='1'
    uci add_list firewall.@zone[-1].network='wan'
    uci add_list firewall.@zone[-1].network='wan6'

    uci add firewall forwarding >/dev/null
    uci set firewall.@forwarding[-1].src='lan'
    uci set firewall.@forwarding[-1].dest='wan'

    uci set network.lan.ipaddr="$LAN_IP"
    uci set network.lan.netmask='255.255.255.0'
fi

uci -q commit network
uci -q commit firewall
uci -q commit dhcp

/etc/init.d/network restart >/dev/null 2>&1 &
sleep 2
/etc/init.d/firewall reload >/dev/null 2>&1 &
/etc/init.d/dnsmasq reload >/dev/null 2>&1 &

echo "Aggressive apply complete. Mode: $MODE, WAN: $WAN_IFACE, LAN: $LAN_IP"
echo "Backup: $BACKUP_DIR"
