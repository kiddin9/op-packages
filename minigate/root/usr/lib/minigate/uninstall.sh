#!/bin/sh
set -u

PURGE="${1:-0}"
ROOT="${MINIGATE_ROOT:-}"
SKIP_PACKAGES="${MINIGATE_SKIP_PACKAGES:-0}"
SKIP_SERVICES="${MINIGATE_SKIP_SERVICES:-0}"
PRESERVE_DIR=""
LOCK_HELD=0

[ "$PURGE" = "0" ] || [ "$PURGE" = "1" ] || {
    echo "用法: $0 0|1" >&2
    exit 2
}

root_path() {
    printf '%s%s\n' "$ROOT" "$1"
}

LOG_FILE="$(root_path /tmp/minigate-uninstall.log)"

log() {
    mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
    printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG_FILE"
    [ -n "$ROOT" ] || logger -t minigate-uninstall "$*" 2>/dev/null || true
}

cleanup() {
    if [ "$LOCK_HELD" = "1" ]; then
        flock -u 9 2>/dev/null || true
    fi
}

trap cleanup EXIT
trap 'exit 1' HUP INT TERM

if [ -z "$ROOT" ] && command -v flock >/dev/null 2>&1; then
    exec 9>"$(root_path /var/lock/minigate-update.lock)"
    if ! flock -n 9; then
        log "已有更新或卸载任务运行，取消本次卸载"
        exit 1
    fi
    LOCK_HELD=1
fi

preserve_data() {
    local config data etc_dir
    config="$(root_path /etc/config/minigate)"
    data="$(root_path /etc/minigate)"
    etc_dir="$(root_path /etc)"
    PRESERVE_DIR="$(root_path /tmp)/minigate-uninstall-preserve.$$"
    mkdir -p "$PRESERVE_DIR" || return 1

    if [ -f "$config" ]; then
        cp -p "$config" "$PRESERVE_DIR/config" || return 1
    fi
    if [ -d "$data" ]; then
        tar -cf "$PRESERVE_DIR/data.tar" -C "$etc_dir" minigate || return 1
    fi
}

restore_data() {
    local config etc_dir
    [ -n "$PRESERVE_DIR" ] || return 0
    config="$(root_path /etc/config/minigate)"
    etc_dir="$(root_path /etc)"

    if [ -f "$PRESERVE_DIR/config" ]; then
        mkdir -p "$(dirname "$config")" || return 1
        cp -p "$PRESERVE_DIR/config" "$config" || return 1
    fi
    if [ -f "$PRESERVE_DIR/data.tar" ]; then
        mkdir -p "$etc_dir" || return 1
        tar -xf "$PRESERVE_DIR/data.tar" -C "$etc_dir" || return 1
    fi
}

restore_or_keep_backup() {
    if restore_data; then
        rm -rf "$PRESERVE_DIR"
        PRESERVE_DIR=""
        return 0
    fi
    log "保留数据恢复失败，临时备份位于 ${PRESERVE_DIR}"
    PRESERVE_DIR=""
    return 1
}

restart_after_failure() {
    local init
    [ "$SKIP_SERVICES" = "1" ] && return 0
    init="$(root_path /etc/init.d/minigate)"
    if [ -x "$init" ]; then
        "$init" enable >/dev/null 2>&1 || true
        "$init" start 9>&- >/dev/null 2>&1 || true
    fi
}

stop_process_tree() {
    local pid child
    pid="$1"
    if command -v pgrep >/dev/null 2>&1; then
        for child in $(pgrep -P "$pid" 2>/dev/null); do
            stop_process_tree "$child"
        done
    fi
    kill "$pid" 2>/dev/null || true
}

stop_services() {
    local init pid
    [ "$SKIP_SERVICES" = "1" ] && return 0

    if [ -z "$ROOT" ] && command -v pgrep >/dev/null 2>&1; then
        for pid in $(pgrep -f '/usr/lib/minigate/login_guard.sh run' 2>/dev/null); do
            stop_process_tree "$pid"
        done
    fi

    init="$(root_path /etc/init.d/minigate)"
    if [ -x "$init" ]; then
        "$init" stop 9>&- >/dev/null 2>&1 || true
        "$init" disable >/dev/null 2>&1 || true
    fi

    if [ -z "$ROOT" ]; then
        pid="$(cat "$(root_path /var/run/minigate-nginx.pid)" 2>/dev/null || true)"
        case "$pid" in
            ''|*[!0-9]*) ;;
            *) kill "$pid" 2>/dev/null || true ;;
        esac
        if command -v pgrep >/dev/null 2>&1; then
            for pid in $(pgrep -f '/usr/lib/minigate/' 2>/dev/null); do
                stop_process_tree "$pid"
            done
        fi
    fi
}

remove_nft_rule_for_set() {
    local set_name handle
    set_name="$1"
    command -v nft >/dev/null 2>&1 || return 0
    for handle in $(nft -a list chain inet fw4 input 2>/dev/null |
        awk -v marker="@${set_name}" 'index($0, marker) { for (i=1; i<=NF; i++) if ($i=="handle") print $(i+1) }'); do
        nft delete rule inet fw4 input handle "$handle" 2>/dev/null || true
    done
    nft delete set inet fw4 "$set_name" 2>/dev/null || true
}

remove_firewall_state() {
    [ "$SKIP_SERVICES" = "1" ] && return 0
    [ -z "$ROOT" ] || return 0

    remove_nft_rule_for_set login_banned_v4
    remove_nft_rule_for_set minigate_blocked
    if command -v iptables >/dev/null 2>&1; then
        while iptables -D INPUT -m set --match-set minigate_blocked src -j DROP >/dev/null 2>&1; do :; done
    fi
    command -v ipset >/dev/null 2>&1 && ipset destroy minigate_blocked >/dev/null 2>&1 || true
}

remove_cron() {
    local cron_file cron_tmp
    cron_file="$(root_path /etc/crontabs/root)"
    if [ -f "$cron_file" ]; then
        cron_tmp="${cron_file}.minigate.$$"
        if sed '/minigate/d' "$cron_file" > "$cron_tmp"; then
            cat "$cron_tmp" > "$cron_file"
        fi
        rm -f "$cron_tmp"
    fi
    if [ "$SKIP_SERVICES" != "1" ] && [ -z "$ROOT" ] && [ -x /etc/init.d/cron ]; then
        /etc/init.d/cron restart 9>&- >/dev/null 2>&1 || true
    fi
}

remove_registered_packages() {
    local package
    [ "$SKIP_PACKAGES" = "1" ] && return 0
    [ -z "$ROOT" ] || return 0

    if command -v opkg >/dev/null 2>&1; then
        for package in minigate luci-app-minigate; do
            if opkg list-installed 2>/dev/null | awk -v name="$package" '$1 == name { found=1 } END { exit !found }'; then
                opkg remove "$package" 9>&- >> "$LOG_FILE" 2>&1 || return 1
            fi
        done
    fi
    if command -v apk >/dev/null 2>&1; then
        for package in minigate luci-app-minigate; do
            if apk info -e "$package" >/dev/null 2>&1; then
                apk del "$package" 9>&- >> "$LOG_FILE" 2>&1 || return 1
            fi
        done
    fi
}

remove_program_files() {
    rm -f \
        "$(root_path /etc/init.d/minigate)" \
        "$(root_path /usr/lib/lua/luci/controller/minigate.lua)" \
        "$(root_path /usr/lib/lua/luci/i18n/minigate.zh-cn.lmo)"
    rm -rf \
        "$(root_path /usr/lib/minigate)" \
        "$(root_path /usr/lib/lua/luci/model/cbi/minigate)" \
        "$(root_path /usr/lib/lua/luci/view/minigate)"
}

remove_runtime_files() {
    local tmp_dir log_dir
    tmp_dir="$(root_path /tmp)"
    log_dir="$(root_path /var/log)"
    rm -rf \
        "$(root_path /var/run/minigate)" \
        "$(root_path /tmp/minigate-update)" \
        "$(root_path /tmp/minigate-geo-cache)" \
        "$(root_path /tmp/minigate_geo)"
    rm -f \
        "$(root_path /var/run/minigate-nginx.pid)" \
        "$(root_path /tmp/minigate-update-state.json)" \
        "$(root_path /tmp/minigate-update-release.json)" \
        "$(root_path /tmp/minigate-update-last-check)" \
        "$tmp_dir"/minigate_proxy_*.tmp \
        "$tmp_dir"/minigate_default_*.tmp \
        "$tmp_dir"/minigate_stream_*.tmp \
        "$tmp_dir"/minigate_ddns_*.cache

    if [ "$PURGE" = "1" ]; then
        rm -f "$(root_path /etc/config/minigate)" "$log_dir"/minigate-*.log
        rm -rf "$(root_path /etc/minigate)"
    fi
}

refresh_luci() {
    rm -f "$(root_path /tmp/luci-indexcache)" "$(root_path /tmp/luci-modulecache)" 2>/dev/null || true
    if [ "$SKIP_SERVICES" != "1" ] && [ -z "$ROOT" ] && [ -x /etc/init.d/uhttpd ]; then
        /etc/init.d/uhttpd restart 9>&- >/dev/null 2>&1 || true
    fi
}

log "开始卸载（清除数据=${PURGE}）"
if [ "$PURGE" != "1" ] && ! preserve_data; then
    log "无法创建保留数据的临时备份，已取消卸载"
    [ -z "$PRESERVE_DIR" ] || rm -rf "$PRESERVE_DIR"
    PRESERVE_DIR=""
    exit 1
fi
stop_services
remove_firewall_state
remove_cron

if ! remove_registered_packages; then
    log "包管理器卸载失败，已停止清理"
    [ "$PURGE" = "1" ] || restore_or_keep_backup
    restart_after_failure
    exit 1
fi

remove_program_files
remove_runtime_files
if [ "$PURGE" != "1" ] && ! restore_or_keep_backup; then
    exit 1
fi
refresh_luci
log "卸载完成（清除数据=${PURGE}）"
