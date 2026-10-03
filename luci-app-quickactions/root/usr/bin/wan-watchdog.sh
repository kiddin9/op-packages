#!/bin/sh
# quickactions WAN failover watchdog.
# Runs from cron every N seconds. Reads config from
# /etc/config/quickactions section 'failover'. Zero background RAM when idle.

. /lib/functions.sh

config_load quickactions

cfg() {
    local v
    config_get v failover "$1" "$2"
    echo "$v"
}

ENABLED=$(cfg enabled 1)
[ "$ENABLED" = "0" ] && exit 0

PRIMARY=$(cfg primary "")
[ -z "$PRIMARY" ] && exit 0

CHECK_IPS=$(cfg check_ips "1.1.1.1 8.8.8.8")
PING_TIMEOUT=$(cfg ping_timeout 5)
FAIL_AT=$(cfg fail_threshold 2)
REC_AT=$(cfg recover_threshold 1)
TAILSCALE_RESTART=$(cfg tailscale_restart 0)
FIREWALL_RESET=$(cfg firewall_reset 1)
LOG_HEALTHY=$(cfg log_healthy 0)

LOCK=/tmp/quickactions_wan_down.lock
FAILS=/tmp/quickactions_wan_fails.count
OKS=/tmp/quickactions_wan_oks.count

# Logical interface name -> kernel device name
phys_iface() {
    local log="$1" dev
    # pppoe-* style kernel interface
    if [ -e "/sys/class/net/pppoe-$log" ]; then echo "pppoe-$log"; return; fi
    # interface with pppoe in the name
    case "$log" in
        *pppoe*) [ -e "/sys/class/net/$log" ] && { echo "$log"; return; } ;;
    esac
    # read device from UCI network
    dev=$(uci -q get network.$log.device)
    [ -n "$dev" ] && [ -e "/sys/class/net/$dev" ] && { echo "$dev"; return; }
    # fallback
    echo "$log"
}

ping_ok() {
    local iface="$1" ip
    for ip in $CHECK_IPS; do
        ping -I "$iface" -c 1 -W "$PING_TIMEOUT" "$ip" >/dev/null 2>&1 && return 0
    done
    return 1
}

flush_ct() {
    if [ -e /proc/net/nf_conntrack ]; then
        echo f > /proc/net/nf_conntrack
    elif [ -e /proc/net/ip_conntrack ]; then
        echo f > /proc/net/ip_conntrack
    fi
}

PRIMARY_DEV=$(phys_iface "$PRIMARY")

# Recovery mode: we believe primary is down; check if it's back
if [ -f "$LOCK" ]; then
    OKS=0
    [ -f "$OKS" ] && OKS=$(cat "$OKS" 2>/dev/null)
    if ping_ok "$PRIMARY_DEV"; then
        OKS=$((OKS + 1))
        if [ "$OKS" -ge "$REC_AT" ]; then
            rm -f "$LOCK" "$FAILS" "$OKS"
            flush_ct
            logger -t quickactions-failover "PRIMARY $PRIMARY recovered; conntrack flushed"
            [ "$TAILSCALE_RESTART" = "1" ] && /etc/init.d/tailscale restart 2>/dev/null
        else
            echo "$OKS" > "$OKS"
        fi
    else
        echo 0 > "$OKS"
    fi
    exit 0
fi

# Normal mode: is primary healthy?
if ping_ok "$PRIMARY_DEV"; then
    rm -f "$FAILS"
    [ "$LOG_HEALTHY" = "1" ] && logger -t quickactions-failover "PRIMARY $PRIMARY HEALTHY"
    exit 0
fi

# Primary failed once
FAILS=0
[ -f "$FAILS" ] && FAILS=$(cat "$FAILS" 2>/dev/null)
FAILS=$((FAILS + 1))
echo "$FAILS" > "$FAILS"

if [ "$FAILS" -ge "$FAIL_AT" ]; then
    touch "$LOCK"
    rm -f "$FAILS"
    flush_ct
    logger -t quickactions-failover "PRIMARY $PRIMARY DOWN after $FAIL_AT failures; failover engaged"
    if [ "$FIREWALL_RESET" = "1" ]; then
        /etc/init.d/firewall restart 2>/dev/null
    fi
    if [ "$TAILSCALE_RESTART" = "1" ]; then
        sleep 30
        /etc/init.d/tailscale restart 2>/dev/null
    fi
fi

exit 0
