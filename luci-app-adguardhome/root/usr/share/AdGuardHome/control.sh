#!/bin/sh
# /usr/share/AdGuardHome/control.sh
. /usr/share/AdGuardHome/helper.sh

ENABLED="$1"
case "$ENABLED" in
0|1) ;;
*) echo "Usage: $0 0|1" >&2; exit 1 ;;
esac
CONFIGURATION="adguardhome"
STATE_FILE="/var/run/adguardhome.state"

# --- input validation -------------------------------------------------------
# This script runs as root, but dns.port is read from a YAML file that lives in
# a directory owned by the unprivileged AdGuardHome user. Never trust it: it
# ends up in sed, nft rules, UCI values and the state file.
is_uint() {
    case "$1" in
    ''|*[!0-9]*) return 1 ;;
    esac
    return 0
}

is_port() {
    is_uint "$1" && [ "${#1}" -le 5 ] && [ "$1" -ge 1 ] && [ "$1" -le 65535 ]
}

is_redirect_mode() {
    case "$1" in
    none|redirect|dnsmasq-upstream|exchange) return 0 ;;
    esac
    return 1
}

# Print the AdGuardHome DNS port from its YAML config, or nothing if invalid.
get_agh_port() {
    local p
    p="$(config_editor "dns.port" "" "$1" "1")"
    is_port "$p" && echo "$p"
}

# Exact (whole-entry) membership test for the dnsmasq upstream server list.
has_dnsmasq_server() {
    local s
    for s in $(uci -q get dhcp.@dnsmasq[0].server 2>/dev/null); do
        [ "$s" = "$1" ] && return 0
    done
    return 1
}
NFT_RULES_TPL="/usr/share/AdGuardHome/adguardhome.nft.tpl"
NFT_RULES_FILE="/var/etc/adguardhome.nft"
NFT_TABLE="adguardhome"

set_nft_redirect() {
    local port="$1"
    [ -z "$port" ] && return 1
    [ ! -f "$NFT_RULES_TPL" ] && return 1

    local wan_section_name
    wan_section_name=$(uci show firewall | awk -F'.' '/\.name='\''wan'\''$/ {print $2}')
    local WAN_IFS=""
    if [ -n "$wan_section_name" ]; then
        WAN_IFS=$(uci get firewall.$wan_section_name.network 2>/dev/null | xargs)
    fi

    local WAN_NFT_SET=""
    for IF in $WAN_IFS; do
        WAN_NFT_SET="${WAN_NFT_SET} \"$IF\","
    done
    WAN_NFT_SET=$(echo "$WAN_NFT_SET" | sed 's/,$//')

    sed -e "s/__WAN_EXCLUDES__/${WAN_NFT_SET}/g" -e "s/__AGH_PORT__/${port}/g" "$NFT_RULES_TPL" > "$NFT_RULES_FILE"

    nft delete table inet "$NFT_TABLE" 2>/dev/null
    fw4 reload
    logger -t adguardhome "nft table $NFT_TABLE applied on port $port, WAN excludes: $WAN_NFT_SET"
}

clear_nft_redirect() {
    if nft list table inet "$NFT_TABLE" >/dev/null 2>&1; then
        [ -f "$NFT_RULES_FILE" ] && > "$NFT_RULES_FILE"
        nft delete table inet "$NFT_TABLE" 2>/dev/null
        fw4 reload
        logger -t adguardhome "nft table $NFT_TABLE cleared"
    fi
}

set_forward_dnsmasq() {
    local PORT="$1"
    is_port "$PORT" || return 1
    local addr="127.0.0.1#$PORT"
    local OLD_SERVER
    OLD_SERVER="$(uci get dhcp.@dnsmasq[0].server 2>/dev/null)"
    # Already the one and only upstream (exact match, not a prefix like #5353)
    [ "$OLD_SERVER" = "$addr" ] && return 0

    uci delete dhcp.@dnsmasq[0].server 2>/dev/null
    uci add_list dhcp.@dnsmasq[0].server="$addr"
    uci delete dhcp.@dnsmasq[0].resolvfile 2>/dev/null
    uci set dhcp.@dnsmasq[0].noresolv=1
    uci commit dhcp
    /etc/init.d/dnsmasq restart >/dev/null 2>&1
}

stop_forward_dnsmasq() {
    local OLD_PORT="$1"
    is_port "$OLD_PORT" || return 0
    local addr="127.0.0.1#$OLD_PORT"
    has_dnsmasq_server "$addr" || return 0

    uci del_list dhcp.@dnsmasq[0].server="$addr" 2>/dev/null
    local addrlist
    addrlist="$(uci get dhcp.@dnsmasq[0].server 2>/dev/null)"
    if [ -z "$addrlist" ]; then
        local resolvfile="/tmp/resolv.conf.d/resolv.conf.auto"
        [ ! -f "$resolvfile" ] && resolvfile="/tmp/resolv.conf.auto"
        uci set dhcp.@dnsmasq[0].resolvfile="$resolvfile" 2>/dev/null
        uci delete dhcp.@dnsmasq[0].noresolv 2>/dev/null
    fi
    uci commit dhcp
    /etc/init.d/dnsmasq restart >/dev/null 2>&1
}

agh_reload() {
    ubus call service event '{"type":"config.change","data":{"package":"adguardhome"}}' >/dev/null 2>&1
}

rm_port53() {
    local configpath
    configpath=$(uci -q get adguardhome.config.config_file)
    [ -z "$configpath" ] && configpath="/etc/adguardhome/adguardhome.yaml"

    local adguardhome_PORT dnsmasq_port
    adguardhome_PORT=$(get_agh_port "$configpath")
    dnsmasq_port=$(uci get dhcp.@dnsmasq[0].port 2>/dev/null)
    is_port "$dnsmasq_port" || dnsmasq_port="53"

    if [ "$dnsmasq_port" = "$adguardhome_PORT" ]; then
        [ "$dnsmasq_port" = "53" ] && dnsmasq_port="1745"
    elif [ "$dnsmasq_port" = "53" ]; then
        return
    fi

    config_editor "dns.port" "$dnsmasq_port" "$configpath"
    uci set dhcp.@dnsmasq[0].port="53"
    uci commit dhcp

    /etc/init.d/dnsmasq restart
    agh_reload
}

use_port53() {
    local configpath
    configpath=$(uci -q get adguardhome.config.config_file)
    [ -z "$configpath" ] && configpath="/etc/adguardhome/adguardhome.yaml"

    local adguardhome_PORT dnsmasq_port
    adguardhome_PORT=$(get_agh_port "$configpath")
    dnsmasq_port=$(uci get dhcp.@dnsmasq[0].port 2>/dev/null)
    is_port "$dnsmasq_port" || dnsmasq_port="53"
    # Without a valid AdGuardHome port there is nothing safe to swap.
    is_port "$adguardhome_PORT" || return

    if [ "$dnsmasq_port" = "$adguardhome_PORT" ]; then
        [ "$dnsmasq_port" = "53" ] && adguardhome_PORT="1745"
    elif [ "$adguardhome_PORT" = "53" ]; then
        return
    fi

    config_editor "dns.port" "53" "$configpath"
    uci set dhcp.@dnsmasq[0].port="$adguardhome_PORT"
    uci commit dhcp
    /etc/init.d/dnsmasq restart
    agh_reload
}

mark_redirect_flag() {
    local enabled="$1" redirect="$2" agh_port="$3"
    local configpath flag=0
    configpath=$(uci -q get adguardhome.config.config_file)
    [ -z "$configpath" ] && configpath="/etc/adguardhome/adguardhome.yaml"

    if [ "$enabled" = "1" ] && [ "$redirect" != "none" ]; then
        flag=1
        if [ "$redirect" = "redirect" ]; then
            nft list table inet "$NFT_TABLE" >/dev/null 2>&1 || flag=0
        elif [ "$redirect" = "dnsmasq-upstream" ]; then
            local s
            s="$(uci -q get dhcp.@dnsmasq[0].server | tr '\n' ' ')"
            printf '%s\n' "$s" | grep -q -E "(^|[[:space:]])127\.0\.0\.1#${agh_port}([[:space:]]|$)" || flag=0
        elif [ "$redirect" = "exchange" ]; then
            local cfgp dport
            cfgp="$(get_agh_port "$configpath")"
            dport="$(uci -q get dhcp.@dnsmasq[0].port)"
            if [ "$cfgp" != "53" ] || [ "$dport" = "53" ] ; then flag=0; fi
        fi
    fi
    printf '%s' "$flag" > /var/run/AdGredir
}

_do_redirect() {
    local enabled="$1"
    local configpath
    configpath=$(uci -q get adguardhome.config.config_file)
    [ -z "$configpath" ] && configpath="/etc/adguardhome/adguardhome.yaml"

    local adguardhome_PORT redirect old_redirect old_port old_enabled
    adguardhome_PORT="$(get_agh_port "$configpath")"
    [ -z "$adguardhome_PORT" ] && adguardhome_PORT="0"

    redirect=$(uci -q get adguardhome.config.redirect || echo "none")
    is_redirect_mode "$redirect" || redirect="none"

    # The state file is parsed and validated, never sourced: sourcing would
    # execute whatever ended up in it.
    old_redirect="none"
    old_port="0"
    old_enabled="0"
    if [ -f "$STATE_FILE" ] && [ ! -L "$STATE_FILE" ]; then
        local v
        v="$(sed -n 's/^old_redirect="\([a-z-]*\)"$/\1/p' "$STATE_FILE" | head -n 1)"
        is_redirect_mode "$v" && old_redirect="$v"
        v="$(sed -n 's/^old_port="\([0-9]*\)"$/\1/p' "$STATE_FILE" | head -n 1)"
        is_uint "$v" && [ "${#v}" -le 5 ] && old_port="$v"
        v="$(sed -n 's/^old_enabled="\([01]\)"$/\1/p' "$STATE_FILE" | head -n 1)"
        [ -n "$v" ] && old_enabled="$v"
    fi

    uci get dhcp.@dnsmasq[0].port >/dev/null 2>&1 || uci set dhcp.@dnsmasq[0].port="53"
    uci commit dhcp

    if [ "$old_enabled" = "1" ] && [ "$old_redirect" = "exchange" ]; then
        adguardhome_PORT="$(uci get dhcp.@dnsmasq[0].port 2>/dev/null)"
        is_uint "$adguardhome_PORT" || adguardhome_PORT="0"
    fi

    if [ "$old_redirect" != "$redirect" ] || [ "$old_port" != "$adguardhome_PORT" ] || { [ "$old_enabled" = "1" ] && [ "$enabled" = "0" ]; }; then
        if [ "$old_redirect" != "none" ]; then
            if [ "$old_redirect" = "redirect" ] && [ "$old_port" != "0" ]; then
                clear_nft_redirect
            elif [ "$old_redirect" = "dnsmasq-upstream" ]; then
                stop_forward_dnsmasq "$old_port"
            elif [ "$old_redirect" = "exchange" ]; then
                rm_port53
            fi
        fi
    elif [ "$old_enabled" = "1" ] && [ "$enabled" = "1" ]; then
        if [ "$old_redirect" = "redirect" ] && [ "$old_port" != "0" ]; then
            clear_nft_redirect
        fi
    fi

    # In exchange mode old_port is compared later against the port dnsmasq
    # holds (the AdGuardHome port before the swap). If the swap is already in
    # place (yaml 53, dnsmasq elsewhere), record dnsmasq's port, otherwise the
    # next run sees a bogus change and tears the swap down and rebuilds it.
    local state_port="$adguardhome_PORT"
    if [ "$redirect" = "exchange" ] && [ "$enabled" = "1" ] && [ "$adguardhome_PORT" = "53" ]; then
        local dp
        dp="$(uci -q get dhcp.@dnsmasq[0].port)"
        is_port "$dp" && [ "$dp" != "53" ] && state_port="$dp"
    fi

    # All three values are validated above, so this is plain data.
    printf 'old_redirect="%s"\nold_port="%s"\nold_enabled="%s"\n' \
        "$redirect" "$state_port" "$enabled" > "$STATE_FILE"

    if [ "$enabled" = "0" ] || [ "$adguardhome_PORT" = "0" ]; then
        printf '%s' "0" > /var/run/AdGredir
        return 1
    fi

    if [ "$redirect" = "redirect" ]; then
        set_nft_redirect "$adguardhome_PORT"
    elif [ "$redirect" = "dnsmasq-upstream" ]; then
        set_forward_dnsmasq "$adguardhome_PORT"
    elif [ "$redirect" = "exchange" ] && [ "$(uci get dhcp.@dnsmasq[0].port 2>/dev/null)" = "53" ]; then
        use_port53
    fi

    mark_redirect_flag "$enabled" "$redirect" "$adguardhome_PORT"
}

_do_redirect "$ENABLED"
