#!/bin/sh

. /usr/lib/hijpass/app-logger.sh

log_debug "$0"

# 检查是否启用自动更新
UPDATE_INTERVAL=$(uci -q get hijpass.@rule[0].update_interval || echo "0")

if [ "$UPDATE_INTERVAL" = "0" ]; then
    log_debug "Auto update is disabled"
    exit 0
fi

# 检查上次更新时间
LAST_UPDATE_FILE="/tmp/hijpass_last_update"
CURRENT_TIME=$(date +%s)

if [ -f "$LAST_UPDATE_FILE" ]; then
    LAST_UPDATE=$(cat "$LAST_UPDATE_FILE" 2>/dev/null || echo "0")
    TIME_DIFF=$((CURRENT_TIME - LAST_UPDATE))
    UPDATE_INTERVAL_SECONDS=$((UPDATE_INTERVAL * 24 * 3600))

    if [ "$TIME_DIFF" -lt "$UPDATE_INTERVAL_SECONDS" ]; then
        log_debug "Not time to update yet. Last update: $LAST_UPDATE, interval: ${UPDATE_INTERVAL} days"
        exit 0
    fi
fi

log_info "Starting automatic rule files update..."

# 执行下载
if /usr/lib/hijpass/rules.sh all; then
    log_info "Automatic update completed successfully"
    echo "$CURRENT_TIME" > "$LAST_UPDATE_FILE"

    # 重启服务以应用新规则
    if [ "$(uci -q get hijpass.@hijpass[0].enabled)" = "1" ]; then
        log_info "Restarting hijpass service to apply new rules"
        /etc/init.d/hijpass restart
    fi
else
    log_error "Automatic update failed"
    exit 1
fi
