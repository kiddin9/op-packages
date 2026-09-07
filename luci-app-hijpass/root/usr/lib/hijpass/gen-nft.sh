#!/bin/sh

. /usr/lib/hijpass/app-logger.sh
. /lib/functions/network.sh

log_debug "$0"

TPROXY_MARK=0x1
TPROXY_SHUNT_MARK=0x3
TPROXY_PROTO=$(uci -q get hijpass.@firewall[0].tproxy_proto)
TPROXY_SHUNT_PORT=$(uci -q get hijpass.@firewall[0].shunt_port)
TPROXY_PORT=$(uci -q get hijpass.@firewall[0].proxy_port)
DNS_FORWARD_SOURCE=$(uci -q get hijpass.@firewall[0].dns_forward || :)
DNS_SERVICE=$(uci -q get hijpass.@dns[0].dns_service || :)
DNS_FORWARD_PORT=

is_valid_port() {
    [ "$1" -ge 1 ] 2>/dev/null && [ "$1" -le 65535 ] 2>/dev/null
}

case "$DNS_FORWARD_SOURCE" in
    ""|none)
        ;;
    pre-routing)
        if [ "$DNS_SERVICE" = "chinadns-ng" ]; then
            DNS_FORWARD_PORT=$(uci -q get hijpass.@dns[0].cdg_port || :)
        else
            log_warn "Independent DNS forwarding target is unavailable"
        fi
        ;;
    routing)
        if [ "$(uci -q get hijpass.@shunt[0].enabled || :)" != "0" ]; then
            DNS_FORWARD_PORT=$(uci -q get hijpass.@shunt[0].dns_listen_port || :)
        else
            log_warn "Core DNS forwarding target is disabled"
        fi
        ;;
    *)
        log_warn "Unknown DNS forwarding source: $DNS_FORWARD_SOURCE"
        ;;
esac

if [ -n "$DNS_FORWARD_PORT" ] && ! is_valid_port "$DNS_FORWARD_PORT"; then
    log_warn "Invalid DNS forwarding port: $DNS_FORWARD_PORT"
    DNS_FORWARD_PORT=
fi

if [ -z "$TPROXY_SHUNT_PORT" ] && [ -z "$TPROXY_PORT" ]; then
    exit 0
fi

RESOLV_FILE=$(uci -q get dhcp.@dnsmasq[0].resolvfile || :)
IP_DIRECT_CONF=$(uci -q get hijpass.@hijpass[0].ip_direct || :)
IP_PROXY_CONF=$(uci -q get hijpass.@hijpass[0].ip_proxy || :)
CHN_ROUTE_FILE=$(uci -q get hijpass.@hijpass[0].chn_route || :)
CHN_ROUTE6_FILE=$(uci -q get hijpass.@hijpass[0].chn_route6 || :)
ENABLE_CHN_ROUTE=$(uci -q get hijpass.@firewall[0].use_chnroute || :)
ENABLE_GFW_LIST=$(uci -q get hijpass.@dns[0].use_gfw || :)
ENABLE_CHN_LIST=$(uci -q get hijpass.@dns[0].use_chn || :)
PROXY_MAC=$(uci -q get hijpass.@firewall[0].proxy_mac_list || :)
PROXY_MAC_EXCLUDE=$(uci -q get hijpass.@firewall[0].proxy_mac_exclude_list || :)
PROXY_INTERFACE=$(uci -q get hijpass.@firewall[0].proxy_iface_list || :)
PROXY_INTERFACE_EXCLUDE=$(uci -q get hijpass.@firewall[0].proxy_iface_exclude_list || :)
ACL_DEFAULT_ALLOW=$(uci -q get hijpass.@firewall[0].acl_default_allow || :)
PROXY_LOCAL=$(uci -q get hijpass.@firewall[0].proxy_local || :)

LUA_SCRIPT="/usr/lib/hijpass/luci-utils.lua"
CONF_PATH="/etc/hijpass"
HIJPASS_USER="hijpass"

network_flush_cache
network_find_wan NET_IF
network_find_wan6 NET_IF6
network_get_physdev NET_L2D "${NET_IF}"
network_get_physdev NET_L2D6 "${NET_IF6}"

WAN_DEVICE_NAMES=
append_wan_device() {
    local wan_device="$1"
    [ -z "$wan_device" ] && return
    case " $WAN_DEVICE_NAMES " in
        *" $wan_device "*) return ;;
    esac
    WAN_DEVICE_NAMES="$WAN_DEVICE_NAMES $wan_device"
}

for wan_device in $(fw4 zone wan 2>/dev/null | sort -u); do
    append_wan_device "$wan_device"
done
for wan_device in $NET_L2D $NET_L2D6; do
    [ "$wan_device" = "br-lan" ] || append_wan_device "$wan_device"
done

INPUT_WAN_L2_DEV=
for wan_device in $WAN_DEVICE_NAMES; do
    escaped_device=$(printf '%s' "$wan_device" | sed 's/\\/\\\\/g; s/"/\\"/g')
    if [ -n "$INPUT_WAN_L2_DEV" ]; then
        INPUT_WAN_L2_DEV="$INPUT_WAN_L2_DEV, "
    fi
    INPUT_WAN_L2_DEV="${INPUT_WAN_L2_DEV}\"${escaped_device}\""
done

FW4_TEMPLATE=$(cat "$CONF_PATH/fw4-template.nft")

log_debug "Generating fw4 rules with mark:$TPROXY_MARK proxy port:$TPROXY_PORT shunt port:$TPROXY_SHUNT_PORT proto:$TPROXY_PROTO"

IP_DIRECT_LIST=$([ -f "$IP_DIRECT_CONF" ] && cat "$IP_DIRECT_CONF" | grep -v -e '^\s*$' -e '^\s*#' || :)
IP_PROXY_LIST=$([ -f "$IP_PROXY_CONF" ] && cat "$IP_PROXY_CONF" | grep -v -e '^\s*$' -e '^\s*#' || :)

IP4_DIRECT_LIST=
IP6_DIRECT_LIST=
IP4_PROXY_LIST=
IP6_PROXY_LIST=

for ip in $IP_DIRECT_LIST; do
    type=$(lua "$LUA_SCRIPT" "iptype" "$ip")
    if [ "$type" = "4" ]; then
        IP4_DIRECT_LIST="$IP4_DIRECT_LIST
$ip"
    elif [ "$type" = "6" ]; then
        IP6_DIRECT_LIST="$IP6_DIRECT_LIST
$ip"
    else
        log_warn "Invalid IP address: $ip"
    fi
done

for ip in $IP_PROXY_LIST; do
    type=$(lua "$LUA_SCRIPT" "iptype" "$ip")
    if [ "$type" = "4" ]; then
        IP4_PROXY_LIST="$IP4_PROXY_LIST
$ip"
    elif [ "$type" = "6" ]; then
        IP6_PROXY_LIST="$IP6_PROXY_LIST
$ip"
    else
        log_warn "Invalid IP address: $ip"
    fi
done

DNS_V4=
DNS_V6=

if [ -f "$RESOLV_FILE" ]; then
    DNS_V4=$(grep <"$RESOLV_FILE" -E -o "[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+" | sort -u | grep -v 0.0.0.0 | grep -v 127.0.0.1)
    DNS_V6=$(grep <"$RESOLV_FILE" -E "([A-Fa-f0-9]{1,4}::?){1,7}[A-Fa-f0-9]{1,4}" | awk -F % '{print $1}' | awk -F " " '{print $2}' | sort -u | grep -v -Fx ::1 | grep -v -Fx ::)
fi

LOCAL_V4_CIDR=$(ip address | grep -w inet | awk '{print $2}')
LOCAL_V6_CIDR=$(ip address | grep -w inet6 | awk '{print $2}')

CHN_ROUTE=
CHN_ROUTE6=

if [ "$ENABLE_CHN_ROUTE" = "1" ]; then
    CHN_ROUTE=$([ -f "$CHN_ROUTE_FILE" ] && cat "$CHN_ROUTE_FILE" | grep -v -e '^\s*$' -e '^\s*#' | sort -u | awk 'NF {printf "%s,\n", $0}' | sed '$ s/,$//' || :)
    CHN_ROUTE6=$([ -f "$CHN_ROUTE6_FILE" ] && cat "$CHN_ROUTE6_FILE" | grep -v -e '^\s*$' -e '^\s*#' | sort -u | awk 'NF {printf "%s,\n", $0}' | sed '$ s/,$//' || :)
fi

IP4_DIRECT_NFT_LIST=$(echo "$DNS_V4
$IP4_DIRECT_LIST
$LOCAL_V4_CIDR
" | sort -u | awk 'NF {printf "%s,\n", $0}' | sed '$ s/,$//')

IP6_DIRECT_NFT_LIST=$(echo "$DNS_V6
$IP6_DIRECT_LIST
$LOCAL_V6_CIDR
" | sort -u | awk 'NF {printf "%s,\n", $0}' | sed '$ s/,$//')

IP4_PROXY_NFT_LIST=$(echo "$IP4_PROXY_LIST" | sort -u | awk 'NF {printf "%s,\n", $0}' | sed '$ s/,$//')
IP6_PROXY_NFT_LIST=$(echo "$IP6_PROXY_LIST" | sort -u | awk 'NF {printf "%s,\n", $0}' | sed '$ s/,$//')

[ -n "$PROXY_INTERFACE" ] && PROXY_INTERFACE="${PROXY_INTERFACE// /,}"
[ -n "$PROXY_INTERFACE_EXCLUDE" ] && PROXY_INTERFACE_EXCLUDE="${PROXY_INTERFACE_EXCLUDE// /,}"
[ -n "$PROXY_MAC" ] && PROXY_MAC="${PROXY_MAC// /,}"
[ -n "$PROXY_MAC_EXCLUDE" ] && PROXY_MAC_EXCLUDE="${PROXY_MAC_EXCLUDE// /,}"

fw_rules="
define DNS_FORWARD_PORT = $DNS_FORWARD_PORT
define HIJPASS_USER = $HIJPASS_USER
define TPROXY_MARK = $TPROXY_MARK
define TPROXY_PORT = $TPROXY_PORT
define TPROXY_SHUNT_MARK = $TPROXY_SHUNT_MARK
define TPROXY_SHUNT_PORT = $TPROXY_SHUNT_PORT
define TPROXY_PROTO = { $TPROXY_PROTO }
define WAN_DEV = { $INPUT_WAN_L2_DEV }
define IP4_DIRECT_NFT_LIST = { $IP4_DIRECT_NFT_LIST }
define IP6_DIRECT_NFT_LIST = { $IP6_DIRECT_NFT_LIST }
define IP4_PROXY_NFT_LIST = { $IP4_PROXY_NFT_LIST }
define IP6_PROXY_NFT_LIST = { $IP6_PROXY_NFT_LIST }
define IP4_CHNROUTE_LIST = { $CHN_ROUTE }
define IP6_CHNROUTE_LIST = { $CHN_ROUTE6 }
define PROXY_INTERFACE = { $PROXY_INTERFACE }
define PROXY_INTERFACE_EXCLUDE = { $PROXY_INTERFACE_EXCLUDE }
define PROXY_MAC = { $PROXY_MAC }
define PROXY_MAC_EXCLUDE = { $PROXY_MAC_EXCLUDE }

$FW4_TEMPLATE
"

if [ -z "$DNS_FORWARD_PORT" ]; then
    fw_rules=$(echo "$fw_rules" | grep -v "DNS_FORWARD_")
    fw_rules=$(echo "$fw_rules" | sed '/^    chain dns-forward {/,/^    }/d')
    fw_rules=$(echo "$fw_rules" | sed '/^    chain dns-forward-output {/,/^    }/d')
elif [ "$PROXY_LOCAL" != "1" ]; then
    fw_rules=$(echo "$fw_rules" | sed '/^    chain dns-forward-output {/,/^    }/d')
fi

if [ "$PROXY_LOCAL" != "1" ]; then
    fw_rules=$(echo "$fw_rules" | sed '/^    chain out-route {/,/^    }/d')
fi

if [ -z "$INPUT_WAN_L2_DEV" ]; then
    fw_rules=$(echo "$fw_rules" | grep -v 'define WAN_DEV =')
    fw_rules=$(echo "$fw_rules" | grep -v 'iifname $WAN_DEV counter return')
fi

if [ -z "$TPROXY_SHUNT_PORT" ]; then
    fw_rules=$(echo "$fw_rules" | grep -v "TPROXY_SHUNT_PORT")
    fw_rules=$(echo "$fw_rules" | grep -v "shunt mark")
    fw_rules=$(echo "$fw_rules" | grep -v "@chnroute")
    fw_rules=$(echo "$fw_rules" | grep -Ev "@chn.list")
fi

if [ -z "$TPROXY_PORT" ]; then
    fw_rules=$(echo "$fw_rules" | grep -v "TPROXY_PORT")
fi

if [ -z "$ENABLE_CHN_ROUTE" ]; then
    fw_rules=$(echo "$fw_rules" | grep -v "@chnroute")
    fw_rules=$(echo "$fw_rules" | sed '/set chnroute.list {/,/^    }/d')
fi

if [ -z "$ENABLE_GFW_LIST" ]; then
    fw_rules=$(echo "$fw_rules" | grep -v "@gfw")
    fw_rules=$(echo "$fw_rules" | sed '/set gfw.list {/,/^    }/d')
fi

if [ -z "$ENABLE_CHN_LIST" ]; then
    fw_rules=$(echo "$fw_rules" | grep -Ev "@chn.list")
    fw_rules=$(echo "$fw_rules" | sed '/set chn.list {/,/^    }/d')
fi

if [ "$DNS_SERVICE" = "custom" ]; then
    fw_rules=$(echo "$fw_rules" | grep -Ev "@dns.*\dlist")
    fw_rules=$(echo "$fw_rules" | sed '/set dns.*\dlist {/,/^    }/d')
fi

if [ "$ACL_DEFAULT_ALLOW" = "1" ]; then
    # 默认全代理模式：移除 deny 模式规则和 proxy 集合
    fw_rules=$(echo "$fw_rules" | grep -v "iif != @proxy_interface_list ether saddr != @proxy_mac_list")
    fw_rules=$(echo "$fw_rules" | sed '/set proxy_mac_list {/,/^    }/d')
    fw_rules=$(echo "$fw_rules" | sed '/set proxy_interface_list {/,/^    }/d')
    fw_rules=$(echo "$fw_rules" | grep -v "define PROXY_INTERFACE =")
    fw_rules=$(echo "$fw_rules" | grep -v "define PROXY_MAC =")
    if [ -z "$PROXY_MAC_EXCLUDE" ]; then
        fw_rules=$(echo "$fw_rules" | grep -v "ether saddr @proxy_mac_exclude_list")
        fw_rules=$(echo "$fw_rules" | sed '/set proxy_mac_exclude_list {/,/^    }/d')
        fw_rules=$(echo "$fw_rules" | grep -v "define PROXY_MAC_EXCLUDE =")
    fi
    if [ -z "$PROXY_INTERFACE_EXCLUDE" ]; then
        fw_rules=$(echo "$fw_rules" | grep -v "iif @proxy_interface_exclude_list")
        fw_rules=$(echo "$fw_rules" | sed '/set proxy_interface_exclude_list {/,/^    }/d')
        fw_rules=$(echo "$fw_rules" | grep -v "define PROXY_INTERFACE_EXCLUDE =")
    fi
else
    # 默认不代理模式：移除 allow 模式规则和 exclude 集合
    fw_rules=$(echo "$fw_rules" | grep -v "iif @proxy_interface_exclude_list")
    fw_rules=$(echo "$fw_rules" | grep -v "ether saddr @proxy_mac_exclude_list")
    fw_rules=$(echo "$fw_rules" | sed '/set proxy_mac_exclude_list {/,/^    }/d')
    fw_rules=$(echo "$fw_rules" | sed '/set proxy_interface_exclude_list {/,/^    }/d')
    fw_rules=$(echo "$fw_rules" | grep -v "define PROXY_MAC_EXCLUDE =")
    fw_rules=$(echo "$fw_rules" | grep -v "define PROXY_INTERFACE_EXCLUDE =")
fi

echo "$fw_rules"
