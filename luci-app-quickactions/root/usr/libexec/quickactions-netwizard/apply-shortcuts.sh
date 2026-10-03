#!/bin/sh
# Regenerate nginx shortcut server blocks + dnsmasq domain entries from /etc/config/wizard shortcuts.
# Called after the user adds/removes a shortcut in the UI.

clean() {
    local sec
    for sec in $(uci -q show nginx 2>/dev/null | sed -n "s/^nginx\.\(_sc_[^=.]*\)=server$/\1/p"); do
        uci -q delete nginx."$sec"
    done
    for sec in $(uci -q show dhcp 2>/dev/null | sed -n "s/^dhcp\.\(_sc_[^=.]*\)=domain$/\1/p"); do
        uci -q delete dhcp."$sec"
    done
}

process_one() {
    local shortcut to_url lanaddr cfg="$1"
    lanaddr="$(uci -q get network.lan.ipaddr | tr ' ' '\n' | head -n1)"
    lanaddr="${lanaddr%%/*}"
    [ -z "$lanaddr" ] && lanaddr="10.0.0.1"

    config_get shortcut "$cfg" shortcut
    config_get to_url "$cfg" to_url
    [ -z "$shortcut" ] || [ -z "$to_url" ] && return 0

    if [ -f /etc/nginx/uci.conf ]; then
        uci -q set nginx._sc_$shortcut=server
        uci -q set nginx._sc_$shortcut.server_name="$shortcut"
        uci -q add_list nginx._sc_$shortcut.listen="80"
        uci -q set nginx._sc_$shortcut.return="302 $to_url"
        uci -q set dhcp._sc_$shortcut=domain
        uci -q set dhcp._sc_$shortcut.name="$shortcut"
        uci -q set dhcp._sc_$shortcut.ip="$lanaddr"
    fi
}

clean
config_load wizard
config_foreach process_one shortcuts

uci -q commit nginx 2>/dev/null
uci -q commit dhcp 2>/dev/null
[ -x /etc/init.d/nginx ] && /etc/init.d/nginx reload >/dev/null 2>&1
[ -x /etc/init.d/dnsmasq ] && /etc/init.d/dnsmasq reload >/dev/null 2>&1

echo "Shortcuts applied."
