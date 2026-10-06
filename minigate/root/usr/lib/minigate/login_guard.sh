#!/bin/sh
# MiniGate · 登录防护（Login Guard）
# 监控 SSH (dropbear) 和 LuCI 网页登录失败，达到阈值自动封禁源 IP
#
# 用法：
#   login_guard.sh run                后台监控（init.d 调用）
#   login_guard.sh list               列出当前已封禁的 IP
#   login_guard.sh status             状态总览
#   login_guard.sh ban <IP>           手动封禁
#   login_guard.sh unban <IP>         解封
#   login_guard.sh flush              清空所有封禁
#   login_guard.sh log                最近日志

# === 从 uci 读配置 ===
ENABLED=$(uci -q get minigate.login_guard.enabled || echo "0")
THRESHOLD=$(uci -q get minigate.login_guard.threshold || echo "3")
BANTIME=$(uci -q get minigate.login_guard.bantime || echo "43200")
WINDOW=$(uci -q get minigate.login_guard.window || echo "600")

DATA_DIR=/etc/minigate/login-guard
RUN_DIR=/var/run/minigate/login-guard
BANS_FILE="$DATA_DIR/bans.txt"
COUNTER_DIR="$RUN_DIR/counters"
LOG_FILE=/var/log/minigate-login-guard.log
ACCESS_LOG=/var/log/minigate-access.log
SET="login_banned_v4"
TABLE="inet fw4"

mkdir -p "$DATA_DIR" "$COUNTER_DIR"
touch "$BANS_FILE"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG_FILE"
    logger -t minigate-lg "$*"
}

# === 白名单：从 uci 读 list whitelist + 默认私有段 ===
is_whitelisted() {
    local ip="$1"
    case "$ip" in
        192.168.*|10.*|127.*|172.1[6-9].*|172.2[0-9].*|172.3[01].*) return 0 ;;
    esac
    local wl
    wl=$(uci -q get minigate.login_guard.whitelist 2>/dev/null)
    [ -z "$wl" ] && return 1
    for net in $wl; do
        case "$net" in
            "$ip") return 0 ;;
            */[0-9]*)
                # 简单 CIDR 匹配（前缀 byte 比较）
                local prefix="${net%/*}"
                local mask="${net#*/}"
                # 只比 /8 /16 /24 /32 这种整字节边界（够用）
                case "$mask" in
                    8)  [ "${ip%%.*}" = "${prefix%%.*}" ] && return 0 ;;
                    16) [ "${ip%.*.*}" = "${prefix%.*.*}" ] && return 0 ;;
                    24) [ "${ip%.*}" = "${prefix%.*}" ] && return 0 ;;
                    32) [ "$ip" = "$prefix" ] && return 0 ;;
                esac
                ;;
        esac
    done
    return 1
}

# === 确保 nft set + drop rule 存在（fw4 reload 后自动重建） ===
ensure_nft() {
    local recreated=0
    if ! nft list set $TABLE $SET >/dev/null 2>&1; then
        nft "add set $TABLE $SET { type ipv4_addr; flags timeout; timeout ${BANTIME}s; }" 2>/dev/null
        recreated=1
    fi
    if ! nft list chain $TABLE input 2>/dev/null | grep -q "@$SET"; then
        nft "insert rule $TABLE input ip saddr @$SET counter drop comment \"minigate-login-guard\"" 2>/dev/null
        recreated=1
    fi
    [ $recreated -eq 1 ] && log "已创建 nft set + drop 规则"
    return $recreated
}

# === 把 IP 加入封禁集合 + 持久化 ===
ban_ip() {
    local ip="$1"
    local exp=$(($(date +%s) + BANTIME))
    nft add element $TABLE $SET "{ $ip timeout ${BANTIME}s }" 2>/dev/null
    # 去重写入持久化文件
    grep -v "^$ip " "$BANS_FILE" > "${BANS_FILE}.tmp" 2>/dev/null || true
    echo "$ip $exp" >> "${BANS_FILE}.tmp"
    mv "${BANS_FILE}.tmp" "$BANS_FILE"
    log "BAN $ip 12小时（达到 $THRESHOLD 次失败）"
    rm -f "$COUNTER_DIR/$ip"
}

# === 启动时从持久化文件恢复封禁 ===
restore_bans() {
    [ -f "$BANS_FILE" ] || return 0
    local now=$(date +%s)
    local tmp="${BANS_FILE}.tmp"
    > "$tmp"
    local count=0
    while read -r ip exp; do
        [ -z "$ip" ] && continue
        if [ "$exp" -gt "$now" ]; then
            local remaining=$((exp - now))
            nft add element $TABLE $SET "{ $ip timeout ${remaining}s }" 2>/dev/null
            echo "$ip $exp" >> "$tmp"
            count=$((count + 1))
        fi
    done < "$BANS_FILE"
    mv "$tmp" "$BANS_FILE"
    [ $count -gt 0 ] && log "从持久化文件恢复 $count 条封禁"
}

# === 处理一条登录失败 ===
handle_failure() {
    local ip="$1"
    [ -z "$ip" ] && return
    is_whitelisted "$ip" && return

    # 滑动窗口：超过 window 秒的旧失败丢弃
    local f="$COUNTER_DIR/$ip"
    local now=$(date +%s)
    local first=0
    local count=0
    if [ -f "$f" ]; then
        read -r first count < "$f"
        if [ -n "$first" ] && [ $((now - first)) -gt "$WINDOW" ]; then
            first=$now
            count=0
        fi
    else
        first=$now
    fi
    count=$((count + 1))
    echo "$first $count" > "$f"
    log "FAIL $ip ($count/$THRESHOLD)"

    if [ "$count" -ge "$THRESHOLD" ]; then
        # 加 ban 前再确认 nft 还在（fw4 可能重载）
        local ban_target="$ip"
        ensure_nft && restore_bans
        ban_ip "$ban_target"
    fi
}

extract_ip() {
    echo "$1" | grep -oE "[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+" | head -1
}

extract_json_field() {
    local key="$1"
    sed -n "s/.*\"${key}\":\"\([^\"]*\)\".*/\1/p" | head -1
}

is_luci_failed_post() {
    local line="$1"
    echo "$line" | grep -q '"method":"POST"' || return 1
    echo "$line" | grep -q '"status":403' || return 1
    echo "$line" | grep -Eq '"uri":"/cgi-bin/luci(/|")' || return 1
    return 0
}

access_log_loop() {
    touch "$ACCESS_LOG" 2>/dev/null
    tail -n 0 -f "$ACCESS_LOG" 2>/dev/null | while read -r line; do
        is_luci_failed_post "$line" || continue
        ip=$(echo "$line" | extract_json_field client)
        handle_failure "$ip"
    done
}

# === 后台 watchdog：每 5 分钟检查 nft 资源 ===
watchdog_loop() {
    while true; do
        sleep 300
        if ensure_nft; then
            restore_bans
        fi
    done
}

# === 主监控循环 ===
run_watcher() {
    [ "$ENABLED" = "1" ] || {
        log "未启用（minigate.login_guard.enabled=0），退出"
        exit 0
    }

    ensure_nft
    restore_bans
    log "登录防护启动 阈值=$THRESHOLD 窗口=${WINDOW}s 封禁=${BANTIME}s"

    # 后台 watchdog
    watchdog_loop &

    # MiniGate 反代访问 LuCI 时，LuCI 日志只会看到反代内网 IP。
    # 这里补充监听 nginx access log，用 JSON client 字段记录真实公网 IP。
    access_log_loop &

    # 主循环：监控系统日志
    logread -f 2>/dev/null | while read -r line; do
        case "$line" in
            *"Bad password attempt"*"from"*|\
            *"Login attempt for nonexistent user"*"from"*|\
            *"luci: failed login"*"from"*)
                ip=$(extract_ip "$line")
                handle_failure "$ip"
                ;;
        esac
    done
}

# === CLI 命令 ===

# 用 nft -j 拿封禁列表，输出每行: <IP> <剩余秒数>
# 注意 nft -j 输出可能有空格、字段顺序也不固定（有的 elem 多个 timeout 字段）
parse_set_json() {
    nft -j list set $TABLE $SET 2>/dev/null | awk '
    {
        # 在每条 elem 块（{...}）内匹配 val + expires
        # [^{}]* 限制不跨越 brace 边界
        while (match($0, /"val":[ ]*"[0-9.]+"[^{}]*"expires":[ ]*[0-9]+/)) {
            block = substr($0, RSTART, RLENGTH)
            $0 = substr($0, RSTART + RLENGTH)
            # 提取 IP
            if (match(block, /[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/)) {
                ip = substr(block, RSTART, RLENGTH)
            }
            # 提取 expires
            if (match(block, /"expires":[ ]*[0-9]+/)) {
                exp_str = substr(block, RSTART, RLENGTH)
                gsub(/[^0-9]/, "", exp_str)
                print ip, exp_str
            }
        }
    }'
}

# 把秒数转人类可读
fmt_duration() {
    local s=$1
    if [ "$s" -ge 3600 ]; then
        printf "%dh%dm" $((s/3600)) $(((s%3600)/60))
    elif [ "$s" -ge 60 ]; then
        printf "%dm%ds" $((s/60)) $((s%60))
    else
        printf "%ds" "$s"
    fi
}

cmd_list() {
    echo "=== 当前已封禁 IP ==="
    local out
    out=$(parse_set_json)
    if [ -z "$out" ]; then
        echo "（暂无）"
        return
    fi
    echo "$out" | while read -r ip secs; do
        printf "  %-18s 剩余 %s\n" "$ip" "$(fmt_duration "$secs")"
    done
}

cmd_status() {
    local banned watching
    banned=$(parse_set_json | wc -l)
    watching=$(ls "$COUNTER_DIR" 2>/dev/null | wc -l)
    echo "已封禁 IP 数: $banned"
    echo "失败计数中的 IP: $watching"
    if [ "$banned" -gt 0 ]; then
        echo "--- 已封禁 ---"
        cmd_list | tail -n +2
    fi
    if [ "$watching" -gt 0 ]; then
        echo "--- 失败计数详情 ---"
        for f in "$COUNTER_DIR"/*; do
            [ -f "$f" ] || continue
            local ip count first now age
            ip=$(basename "$f")
            read -r first count < "$f"
            now=$(date +%s)
            age=$((now - first))
            printf "  %-18s %d/%d (距首次失败 %ds)\n" "$ip" "$count" "$THRESHOLD" "$age"
        done
    fi
}

cmd_unban() {
    local ip="$1"
    [ -z "$ip" ] && { echo "用法: $0 unban <IP>"; exit 1; }
    nft delete element $TABLE $SET "{ $ip }" 2>&1
    grep -v "^$ip " "$BANS_FILE" > "${BANS_FILE}.tmp" 2>/dev/null || true
    mv "${BANS_FILE}.tmp" "$BANS_FILE"
    rm -f "$COUNTER_DIR/$ip"
    echo "✓ 已解封 $ip"
    log "MANUAL unban $ip"
}

cmd_ban() {
    local ip="$1"
    [ -z "$ip" ] && { echo "用法: $0 ban <IP>"; exit 1; }
    ensure_nft
    local exp=$(($(date +%s) + BANTIME))
    nft add element $TABLE $SET "{ $ip timeout ${BANTIME}s }" 2>&1
    grep -v "^$ip " "$BANS_FILE" > "${BANS_FILE}.tmp" 2>/dev/null || true
    echo "$ip $exp" >> "${BANS_FILE}.tmp"
    mv "${BANS_FILE}.tmp" "$BANS_FILE"
    echo "✓ 已封禁 $ip"
    log "MANUAL ban $ip"
}

cmd_flush() {
    nft flush set $TABLE $SET 2>&1 || true
    > "$BANS_FILE"
    rm -rf "$COUNTER_DIR"/*
    echo "✓ 已清空所有封禁"
    log "MANUAL flush all bans"
}

cmd_log() {
    local n="${1:-30}"
    if [ -f "$LOG_FILE" ]; then
        tail -n "$n" "$LOG_FILE"
    else
        logread -e minigate-lg | tail -n "$n"
    fi
}

# === 入口 ===
case "${1:-help}" in
    run)        run_watcher ;;
    list|ls)    cmd_list ;;
    status)     cmd_status ;;
    ban)        cmd_ban "$2" ;;
    unban)      cmd_unban "$2" ;;
    flush)      cmd_flush ;;
    log|logs)   cmd_log "$2" ;;
    *)
        cat <<EOH
MiniGate 登录防护

  $0 run               后台监控（init.d 用）
  $0 list              列出已封禁 IP
  $0 status            状态总览
  $0 ban <IP>          手动封禁
  $0 unban <IP>        解封
  $0 flush             清空所有封禁
  $0 log [N]           最近 N 条日志（默认 30）
EOH
        ;;
esac
