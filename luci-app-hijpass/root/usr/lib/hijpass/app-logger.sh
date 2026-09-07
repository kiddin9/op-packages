#!/bin/sh

LOG_FILE=$(uci -q get hijpass.@hijpass[0].log_path || :)
LOG_LEVEL=$(uci -q get hijpass.@hijpass[0].log_level || echo "INFO") # debug, info, warn, error
LOG_DIR=$(uci -q get hijpass.@hijpass[0].log_dir || :)
[ -z "$LOG_DIR" ] && exit 1
[ -d "$LOG_DIR" ] || mkdir -p "$LOG_DIR"
LOG_LEVELS="DEBUG:1 INFO:2 WARN:3 ERROR:4"

get_log_level_num() {
    local level="$1"
    echo "$LOG_LEVELS" | tr ' ' '\n' | grep "^$level:" | cut -d':' -f2
}

log() {
    local level level_num min_level_num message datetime
    level=$(echo "$1" | tr 'a-z' 'A-Z')
    shift
    message=$*
    level_num=$(get_log_level_num "$level")
    min_level_num=$(get_log_level_num "$LOG_LEVEL")

    if [ -n "$level_num" ] && [ -n "$min_level_num" ]; then
        if [ "$level_num" -ge "$min_level_num" ]; then
            datetime=$(date "+%Y-%m-%d %H:%M:%S")
            # 处理多行消息的对齐
            if [ "$LOG_LEVEL" = "DEBUG" ]; then
                # DEBUG模式下，第一行包含脚本名和时间戳
                printf "%s   %-8s%-40s%s\n" "[$datetime]" "${level}" "$0" "$(echo "$message" | head -n1)" >>"$LOG_FILE"
                # 后续行只保留缩进，不显示时间戳
                echo "$message" | tail -n +2 | while IFS= read -r line; do
                    printf "%-23s%-8s%-40s%s\n" "" "" "" "$line" >>"$LOG_FILE"
                done
            else
                # 普通模式下，第一行正常输出
                printf "%s   %-8s%s\n" "[$datetime]" "${level}" "$(echo "$message" | head -n1)" >>"$LOG_FILE"
                # 后续行只保留缩进，不显示时间戳
                echo "$message" | tail -n +2 | while IFS= read -r line; do
                    printf "%-23s%-8s%s\n" "" "" "$line" >>"$LOG_FILE"
                done
            fi
        fi
    fi
}

log_debug() {
    log "debug" "$@"
}

log_info() {
    log "info" "$@"
}

log_warn() {
    log "warn" "$@"
}

log_error() {
    log "error" "$@"
}
