#!/bin/sh

. /usr/lib/hijpass/app-logger.sh

log_debug "$0"

ACTION="$1"
TABLE_NUMBER="233"
TPROXY_MARK="0x1"
RT_TABLES_FILE="/etc/iproute2/rt_tables"
TABLE_NAME="hijpass"

add_route() {
    delete_route
    add_table

    ip route add local default dev lo table "$TABLE_NAME"
    log_debug "Added IPv4 local route to table ${TABLE_NAME}"

    ip rule add fwmark "$TPROXY_MARK" table "$TABLE_NAME"
    log_debug "Added IPv4 rule with fwmark ${TPROXY_MARK}"

    ip -6 route add local default dev lo table "$TABLE_NAME"
    log_debug "Added IPv6 local route to table ${TABLE_NAME}"

    ip -6 rule add fwmark "$TPROXY_MARK" table "$TABLE_NAME"
    log_debug "Added IPv6 rule with fwmark ${TPROXY_MARK}"
}

delete_route() {
    while ip rule show | grep -q "fwmark $TPROXY_MARK lookup $TABLE_NAME"; do
        ip rule delete fwmark "$TPROXY_MARK" table "$TABLE_NAME"
        log_debug "IPv4 Rule with fwmark $TPROXY_MARK deleted from table ${TABLE_NAME}"
    done

    while ip -6 rule show | grep -q "fwmark $TPROXY_MARK lookup $TABLE_NAME"; do
        ip -6 rule delete fwmark "$TPROXY_MARK" table "$TABLE_NAME"
        log_debug "IPv6 rule with fwmark $TPROXY_MARK deleted from table ${TABLE_NAME}"
    done

    if ip route del local default dev lo table "$TABLE_NAME" 2>/dev/null; then
        log_debug "Removed ${TABLE_NAME} existing IPv4 default route Successfully"
    else
        log_debug "No existing IPv4 default route to remove"
    fi

    if ip -6 route del local default dev lo table "$TABLE_NAME" 2>/dev/null; then
        log_debug "Removed ${TABLE_NAME} existing IPv6 default route Successfully"
    else
        log_debug "No existing IPv6 default route to remove"
    fi

    delete_table
}

add_table() {
    if grep -qE "^\s*${TABLE_NUMBER}\s+${TABLE_NAME}\s*$" "$RT_TABLES_FILE"; then
        log_debug "Table ${TABLE_NAME} with number ${TABLE_NUMBER} already exists"
    else
        echo "${TABLE_NUMBER} ${TABLE_NAME}" >>"$RT_TABLES_FILE"
        log_debug "Table ${TABLE_NAME} with number ${TABLE_NUMBER} added"
    fi
}

delete_table() {
    if grep -qE "^\s*${TABLE_NUMBER}\s+${TABLE_NAME}\s*$" "$RT_TABLES_FILE"; then
        sed -i "/^\s*${TABLE_NUMBER}\s\+${TABLE_NAME}\s*$/d" "$RT_TABLES_FILE"
        log_debug "Deleted table ${TABLE_NAME} with number ${TABLE_NUMBER}"
    else
        log_debug "Table ${TABLE_NAME} with number ${TABLE_NUMBER} does not exist"
    fi
}

usage() {
    echo "Usage: $0 [reset_hijpass_route|remove_hijpass_route]"
    exit 1
}

if [ "$#" -ne 1 ]; then
    usage
fi

case "$ACTION" in
reset_hijpass_route)
    log_info "Configuring hijpass routing..."
    add_route
    log_info "Configured hijpass routing successfully"
    ;;
remove_hijpass_route)
    log_info "Removing hijpass routing configuration..."
    delete_route
    log_info "Removed hijpass routing configuration successfully"
    ;;
*)
    usage
    ;;
esac
