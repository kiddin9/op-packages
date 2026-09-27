#!/bin/sh
# /usr/share/AdGuardHome/control.sh
. /usr/share/AdGuardHome/helper.sh

ENABLED="$1" 
CONFIGURATION="adguardhome"
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
    # 优化：只有当表存在时才清理和重载防火墙，避免无意义的性能开销
    if nft list table inet "$NFT_TABLE" >/dev/null 2>&1; then
        [ -f "$NFT_RULES_FILE" ] && > "$NFT_RULES_FILE"
        nft delete table inet "$NFT_TABLE" 2>/dev/null
        fw4 reload
        logger -t adguardhome "nft table $NFT_TABLE cleared"
    fi
}

set_forward_dnsmasq() {
    local PORT="$1"
    local addr="127.0.0.1#$PORT"
    local OLD_SERVER
    OLD_SERVER="$(uci get dhcp.@dnsmasq[0].server 2>/dev/null)"
    echo "$OLD_SERVER" | grep -q "^$addr" && return 0

    uci delete dhcp.@dnsmasq[0].server 2>/dev/null
    uci add_list dhcp.@dnsmasq[0].server="$addr"
    uci delete dhcp.@dnsmasq[0].resolvfile 2>/dev/null
    uci set dhcp.@dnsmasq[0].noresolv=1
    uci commit dhcp
    /etc/init.d/dnsmasq restart >/dev/null 2>&1
}

stop_forward_dnsmasq() {
    local OLD_PORT="$1"
    local addr="127.0.0.1#$OLD_PORT"
    local OLD_SERVER
    OLD_SERVER="$(uci get dhcp.@dnsmasq[0].server 2>/dev/null)"
    echo "$OLD_SERVER" | grep -q "^$addr" || return 0

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
    adguardhome_PORT=$(config_editor "dns.port" "" "$configpath" "1")
    dnsmasq_port=$(uci get dhcp.@dnsmasq[0].port 2>/dev/null)
    [ -z "$dnsmasq_port" ] && dnsmasq_port="53"

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
    adguardhome_PORT=$(config_editor "dns.port" "" "$configpath" "1")
    dnsmasq_port=$(uci get dhcp.@dnsmasq[0].port 2>/dev/null)
    [ -z "$dnsmasq_port" ] && dnsmasq_port="53"

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
            cfgp="$(config_editor "dns.port" "" "$configpath" "1")"
            dport="$(uci -q get dhcp.@dnsmasq[0].port)"
            if [ "$cfgp" != "53" ] || [ "$dport" = "53" ] ; then flag=0; fi
        fi
    fi
    echo -n "$flag" > /var/run/AdGredir
}

_do_redirect() {
    local enabled="$1"
    local configpath
    configpath=$(uci -q get adguardhome.config.config_file)
    [ -z "$configpath" ] && configpath="/etc/adguardhome/adguardhome.yaml"

    local adguardhome_PORT redirect old_redirect old_port old_enabled
    adguardhome_PORT="$(config_editor "dns.port" "" "$configpath" "1")"
    [ -z "$adguardhome_PORT" ] && adguardhome_PORT="0"

    redirect=$(uci -q get adguardhome.config.redirect || echo "none")

    # 【核心修复】：从内存文件中读取旧状态，彻底放弃污染 UCI
    if [ -f /var/run/adguardhome.state ]; then
        . /var/run/adguardhome.state
    else
        old_redirect="none"
        old_port="0"
        old_enabled="0"
    fi

    uci get dhcp.@dnsmasq[0].port >/dev/null 2>&1 || uci set dhcp.@dnsmasq[0].port="53"
    uci commit dhcp

    if [ "$old_enabled" = "1" ] && [ "$old_redirect" = "exchange" ]; then
        adguardhome_PORT="$(uci get dhcp.@dnsmasq[0].port 2>/dev/null)"
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

    # 【核心修复】：将当前状态覆盖写入内存文件，轻量、疾速、安全！
    cat <<EOF > /var/run/adguardhome.state
old_redirect="$redirect"
old_port="$adguardhome_PORT"
old_enabled="$enabled"
EOF

    if [ "$enabled" = "0" ] || [ "$adguardhome_PORT" = "0" ]; then
        echo -n "0" > /var/run/AdGredir
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
