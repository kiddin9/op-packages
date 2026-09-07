#!/bin/sh

. /usr/lib/hijpass/app-logger.sh

. /lib/functions.sh

log_debug "$0"

clean_log() {
    local log_file
    config_get log_file "$1" log_path
    [ -z "$log_file" ] && return
    if [ -f "$log_file" ]; then
        if tail -n 30000 "$log_file" >"$log_file.tmp" 2>/dev/null && [ -s "$log_file.tmp" ]; then
            cat "$log_file.tmp" >"$log_file"
            rm -f "$log_file.tmp"
            log_debug "Successfully cleaned log file: $log_file"
        else
            rm -f "$log_file.tmp"
            log_warn "Failed to clean log file: $log_file"
        fi
    fi
}

case "$1" in
clean)
    echo "" >"$2"
    log_info "Manually trigger log cleanup, log file: $2"
    ;;
hijpass)
    config_load hijpass
    config_foreach clean_log hijpass
    config_foreach clean_log proxy_node
    config_foreach clean_log shunt
    ;;
hijserver)
    config_load hijserver
    config_foreach clean_log server_node
    ;;
  *)
    config_load hijpass
    config_foreach clean_log hijpass
    config_foreach clean_log proxy_node
    config_foreach clean_log shunt

    config_load hijserver
    config_foreach clean_log server_node
esac
