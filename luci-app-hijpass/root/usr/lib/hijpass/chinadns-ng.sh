#!/bin/sh
. /usr/lib/hijpass/app-logger.sh
log_debug "$0"

GFW_FILE_PATH=$(uci -q get hijpass.@hijpass[0].gfw_list)
CHN_FILE_PATH=$(uci -q get hijpass.@hijpass[0].chn_list)
DOMAIN_PROXY_FILE_PATH=$(uci -q get hijpass.@hijpass[0].domain_proxy)
DOMAIN_DIRECT_FILE_PATH=$(uci -q get hijpass.@hijpass[0].domain_direct)
DIRECT_DNS=$(uci -q get hijpass.@dns[0].direct_dns)
PROXY_DNS=$(uci -q get hijpass.@dns[0].proxy_dns)
ENABLE_GFW=$(uci -q get hijpass.@dns[0].use_gfw)
ENABLE_CHN=$(uci -q get hijpass.@dns[0].use_chn)
CDG_PORT=$(uci -q get hijpass.@dns[0].cdg_port)
CHINADNS_NG_CONF="/etc/hijpass/chinadns-ng.conf"
GEOVIEW_SCRIPT="/usr/lib/hijpass/geoview.sh"
DOMAIN_PROXY_TEMP_FILE_PATH=/tmp/domain_proxy.tmp
DOMAIN_DIRECT_TEMP_FILE_PATH=/tmp/domain_direct.tmp

touch "$DOMAIN_PROXY_TEMP_FILE_PATH"
touch "$DOMAIN_DIRECT_TEMP_FILE_PATH"

if [ "$DIRECT_DNS" = "custom" ]; then
    DIRECT_DNS="$(uci -q get hijpass.@dns[0].direct_dns_custom)"
fi
if [ "$DIRECT_DNS" = "dnsmasq" ] || [ "$DIRECT_DNS" = "system" ]; then
    dnsmasq_port=$(uci -q get dhcp.@dnsmasq[0].port || echo "53")
    DIRECT_DNS="127.0.0.1#${dnsmasq_port:-53}"
fi
if [ "$PROXY_DNS" = "custom" ]; then
    PROXY_DNS="$(uci -q get hijpass.@dns[0].proxy_dns_custom)"
fi
if [ "$PROXY_DNS" = "dnsmasq" ] || [ "$PROXY_DNS" = "system" ]; then
    dnsmasq_port=$(uci -q get dhcp.@dnsmasq[0].port || echo "53")
    PROXY_DNS="127.0.0.1#${dnsmasq_port:-53}"
fi
proxy_domain_list="$([ -f "$DOMAIN_PROXY_FILE_PATH" ] && cat "$DOMAIN_PROXY_FILE_PATH" || :)"
geosite_proxy_lines=$(echo "$proxy_domain_list" | grep '^geosite:' | sed 's/^geosite://' | tr '\n' ',')
if [ -n "$geosite_proxy_lines" ]; then
    geosite_proxy_domains=$($GEOVIEW_SCRIPT -e "geosite" "${geosite_proxy_lines%,}")
    proxy_domain_list=$(echo "$proxy_domain_list" | grep -v '^geosite:')
    proxy_domain_list="$proxy_domain_list
$geosite_proxy_domains"
fi
echo "$proxy_domain_list" > "$DOMAIN_PROXY_TEMP_FILE_PATH"

direct_domain_list="$([ -f "$DOMAIN_DIRECT_FILE_PATH" ] && cat "$DOMAIN_DIRECT_FILE_PATH" || :)"
geosite_direct_lines=$(echo "$direct_domain_list" | grep '^geosite:' | sed 's/^geosite://' | tr '\n' ',')
if [ -n "$geosite_direct_lines" ]; then
    geosite_direct_domains=$($GEOVIEW_SCRIPT -e "geosite" "${geosite_direct_lines%,}")
    direct_domain_list=$(echo "$direct_domain_list" | grep -v '^geosite:')
    direct_domain_list="$direct_domain_list
$geosite_direct_domains"
fi
echo "$direct_domain_list" > "$DOMAIN_DIRECT_TEMP_FILE_PATH"

CONF="
# 监听地址和端口
bind-addr ::
bind-port $CDG_PORT

# 国内上游、可信上游
china-dns $DIRECT_DNS
trust-dns $PROXY_DNS

# 域名列表，用于分流
$([ "$ENABLE_CHN" = "1" ] && echo "chnlist-file  $CHN_FILE_PATH")
$([ "$ENABLE_GFW" = "1" ] && echo "gfwlist-file  $GFW_FILE_PATH")

$([ "$ENABLE_CHN" = "1" ] && [ "$ENABLE_GFW" != "1" ] && echo "default-tag gfw")
$([ "$ENABLE_GFW" = "1" ] && [ "$ENABLE_CHN" != "1" ] && echo "default-tag chn")

group userdirect
group-dnl $DOMAIN_DIRECT_TEMP_FILE_PATH
group-upstream $DIRECT_DNS
group-ipset inet@hijpass@dnsbypass4list,inet@hijpass@dnsbypass6list

group userproxy
group-dnl $DOMAIN_PROXY_TEMP_FILE_PATH
group-upstream $PROXY_DNS
group-ipset inet@hijpass@dnsproxy4list,inet@hijpass@dnsproxy6list

# 收集 tag:chn、tag:gfw 域名的 IP (可选)
add-tagchn-ip inet@hijpass@chn4list,inet@hijpass@chn6list
add-taggfw-ip inet@hijpass@gfw4list,inet@hijpass@gfw6list

# 测试 tag:none 域名的 IP (针对国内上游)
ipset-name4 inet@hijpass@chnroute4list
ipset-name6 inet@hijpass@chnroute6list

# dns 缓存
# cache 4096
# cache-stale 86400
# cache-refresh 20

# verdict 缓存 (用于 tag:none 域名)
verdict-cache 4096

# 详细日志
# verbose
"

echo "$CONF" >"$CHINADNS_NG_CONF"
