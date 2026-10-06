#!/bin/sh

PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH

CURRENT_VERSION="2026.9.18-2"
REPOSITORY="tpxcer/minigate"
API_URL="https://api.github.com/repos/${REPOSITORY}/releases/latest"
DOWNLOAD_ROOT="https://github.com/${REPOSITORY}/releases/download"
STATE_FILE="/tmp/minigate-update-state.json"
RELEASE_FILE="/tmp/minigate-update-release.json"
LAST_CHECK_FILE="/tmp/minigate-update-last-check"
LOCK_FILE="/var/lock/minigate-update.lock"
TMP_ROOT="/tmp/minigate-update"
RUN_LOG="/var/log/minigate-update.log"
STATE_CURRENT="$CURRENT_VERSION"

umask 077

json_escape() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\r/ /g'
}

write_state() {
    local status="$1"
    local progress="$2"
    local latest="$3"
    local available="$4"
    local running="$5"
    local success="$6"
    local message="$7"
    local tmp="${STATE_FILE}.$$"

    mkdir -p "$TMP_ROOT" "$(dirname "$LOCK_FILE")"
    printf '{"status":"%s","progress":%s,"current":"%s","latest":"%s","available":%s,"running":%s,"success":%s,"message":"%s"}\n' \
        "$status" "$progress" "$STATE_CURRENT" "$latest" "$available" "$running" "$success" "$(json_escape "$message")" > "$tmp"
    mv -f "$tmp" "$STATE_FILE"
}

emit_state() {
    if [ ! -s "$STATE_FILE" ]; then
        write_state "idle" 0 "" false false true "点击检查更新获取最新版本"
    fi
    cat "$STATE_FILE"
}

download_file() {
    local url="$1"
    local output="$2"
    curl -fL --proto '=https' --tlsv1.2 \
        --connect-timeout 10 --max-time 120 --retry 2 --retry-delay 1 \
        -H 'Accept: application/vnd.github+json' \
        -H 'User-Agent: MiniGate-Updater/1' \
        -o "$output" "$url"
}

valid_version() {
    printf '%s' "$1" | grep -Eq '^[0-9]{4}\.(0?[1-9]|1[0-2])\.(0?[1-9]|[12][0-9]|3[01])(-[1-9][0-9]*)?$'
}

version_newer() {
    awk -v left="$1" -v right="$2" 'BEGIN {
        split(left, left_parts, "-");
        split(right, right_parts, "-");
        split(left_parts[1], a, ".");
        split(right_parts[1], b, ".");
        a[4] = left_parts[2] == "" ? 0 : left_parts[2] + 0;
        b[4] = right_parts[2] == "" ? 0 : right_parts[2] + 0;
        for (i = 1; i <= 4; i++) {
            if ((a[i] + 0) > (b[i] + 0)) exit 0;
            if ((a[i] + 0) < (b[i] + 0)) exit 1;
        }
        exit 1;
    }'
}

fetch_latest() {
    local metadata="${TMP_ROOT}/latest.$$.json"
    local tag

    mkdir -p "$TMP_ROOT"
    if ! download_file "$API_URL" "$metadata" >> "$RUN_LOG" 2>&1; then
        rm -f "$metadata"
        return 1
    fi

    tag=$(jsonfilter -q -i "$metadata" -e '@.tag_name' 2>/dev/null)
    tag=${tag#v}
    if ! valid_version "$tag"; then
        rm -f "$metadata"
        return 1
    fi
    LATEST_VERSION="$tag"
    chmod 600 "$metadata"
    mv -f "$metadata" "$RELEASE_FILE"
    return 0
}

run_check() {
    local checked_file
    mkdir -p "$TMP_ROOT" "$(dirname "$LOCK_FILE")"
    exec 8>"$LOCK_FILE" || return 1
    if ! flock -n 8; then
        emit_state
        return 0
    fi
    write_state "checking" 10 "" false true true "正在检查 GitHub Release"
    if ! fetch_latest; then
        write_state "error" 0 "" false false false "检查失败，请确认路由器可以访问 GitHub"
        emit_state
        return 1
    fi
    checked_file=$(mktemp "${TMP_ROOT}/last-check.XXXXXX")
    if [ -n "$checked_file" ]; then
        date +%s > "$checked_file"
        mv -f "$checked_file" "$LAST_CHECK_FILE"
    fi

    if version_newer "$LATEST_VERSION" "$CURRENT_VERSION"; then
        write_state "available" 100 "$LATEST_VERSION" true false true "发现新版本，可直接更新"
    elif [ "$LATEST_VERSION" = "$CURRENT_VERSION" ]; then
        write_state "up_to_date" 100 "$LATEST_VERSION" false false true "当前已经是最新版本"
    else
        write_state "up_to_date" 100 "$LATEST_VERSION" false false true "当前版本高于 GitHub 最新正式版"
    fi
    emit_state
}

run_auto_check() {
    local now last age current status

    current=$(jsonfilter -q -i "$STATE_FILE" -e '@.current' 2>/dev/null)
    status=$(jsonfilter -q -i "$STATE_FILE" -e '@.status' 2>/dev/null)
    if [ "$current" = "$CURRENT_VERSION" ] && [ -s "$LAST_CHECK_FILE" ] && \
       { [ "$status" = "available" ] || [ "$status" = "up_to_date" ]; }; then
        now=$(date +%s)
        last=$(cat "$LAST_CHECK_FILE" 2>/dev/null)
        case "$last" in
            ''|*[!0-9]*) last=0 ;;
        esac
        age=$((now - last))
        if [ "$age" -ge 0 ] && [ "$age" -lt 600 ]; then
            emit_state
            return 0
        fi
    fi

    run_check
}

backup_program() {
    local output="$1"
    local paths=""
    local path

    for path in \
        etc/init.d/minigate \
        etc/config/minigate \
        usr/lib/minigate \
        usr/lib/lua/luci/controller/minigate.lua \
        usr/lib/lua/luci/model/cbi/minigate \
        usr/lib/lua/luci/view/minigate; do
        [ -e "/$path" ] && paths="$paths $path"
    done

    [ -n "$paths" ] || return 1
    tar -czf "${output}.new" -C / $paths || return 1
    tar -tzf "${output}.new" >/dev/null 2>&1 || return 1
    chmod 600 "${output}.new"
    mv -f "${output}.new" "$output"
}

restore_program() {
    local backup="$1"

    /etc/init.d/minigate stop >> "$RUN_LOG" 2>&1 || true
    rm -f /etc/init.d/minigate /usr/lib/lua/luci/controller/minigate.lua
    rm -rf /usr/lib/minigate \
        /usr/lib/lua/luci/model/cbi/minigate \
        /usr/lib/lua/luci/view/minigate
    tar -xzf "$backup" -C / >> "$RUN_LOG" 2>&1 || return 1
    chmod +x /etc/init.d/minigate /usr/lib/minigate/*.sh 2>/dev/null || true
    rm -f /tmp/luci-indexcache /tmp/luci-modulecache
    /etc/init.d/minigate start >> "$RUN_LOG" 2>&1 9>&- || true
    /etc/init.d/uhttpd restart >> "$RUN_LOG" 2>&1 9>&- || true

    if [ "$(uci -q get minigate.global.enabled)" = "1" ]; then
        local pid
        pid=$(cat /var/run/minigate-nginx.pid 2>/dev/null)
        [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null || return 1
        nginx -t -c /etc/minigate/nginx/minigate.conf >> "$RUN_LOG" 2>&1 || return 1
    fi
    return 0
}

verify_install() {
    grep -Fxq "CURRENT_VERSION=\"${LATEST_VERSION}\"" /usr/lib/minigate/update.sh || return 1
    [ -x /etc/init.d/minigate ] || return 1
    [ -x /usr/lib/minigate/proxy.sh ] || return 1

    if [ "$(uci -q get minigate.global.enabled)" = "1" ]; then
        nginx -t -c /etc/minigate/nginx/minigate.conf >> "$RUN_LOG" 2>&1 || return 1
        local pid
        pid=$(cat /var/run/minigate-nginx.pid 2>/dev/null)
        [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null || return 1
    fi
    return 0
}

run_apply_locked() {
    local work_dir source_name source_file sums_file expected actual valid_hash backup
    local confirmed_version="$1"

    if ! valid_version "$confirmed_version"; then
        write_state "error" 0 "" false false false "请先检查更新并确认本次更新内容"
        return 1
    fi

    : > "$RUN_LOG"
    write_state "checking" 5 "" false true true "正在检查最新版本"
    if ! fetch_latest; then
        write_state "error" 0 "" false false false "检查失败，请确认路由器可以访问 GitHub"
        return 1
    fi
    if [ "$LATEST_VERSION" != "$confirmed_version" ]; then
        write_state "error" 0 "$LATEST_VERSION" true false false "最新版本已变化，请重新查看更新内容并确认"
        return 1
    fi
    if ! version_newer "$LATEST_VERSION" "$CURRENT_VERSION"; then
        write_state "up_to_date" 100 "$LATEST_VERSION" false false true "当前已经是最新版本"
        return 0
    fi

    work_dir=$(mktemp -d "${TMP_ROOT}/work.XXXXXX") || {
        write_state "error" 0 "$LATEST_VERSION" true false false "无法创建更新临时目录"
        return 1
    }
    source_name="minigate-v${LATEST_VERSION}-src.tar.gz"
    source_file="${work_dir}/${source_name}"
    sums_file="${work_dir}/SHA256SUMS"

    write_state "downloading" 20 "$LATEST_VERSION" true true true "正在下载版本清单"
    if ! download_file "${DOWNLOAD_ROOT}/v${LATEST_VERSION}/SHA256SUMS" "$sums_file" >> "$RUN_LOG" 2>&1; then
        write_state "error" 0 "$LATEST_VERSION" true false false "下载校验清单失败，未修改当前版本"
        rm -rf "$work_dir"
        return 1
    fi

    write_state "downloading" 40 "$LATEST_VERSION" true true true "正在下载更新包"
    if ! download_file "${DOWNLOAD_ROOT}/v${LATEST_VERSION}/${source_name}" "$source_file" >> "$RUN_LOG" 2>&1; then
        write_state "error" 0 "$LATEST_VERSION" true false false "下载更新包失败，未修改当前版本"
        rm -rf "$work_dir"
        return 1
    fi

    write_state "verifying" 55 "$LATEST_VERSION" true true true "正在校验 SHA-256 和版本信息"
    expected=$(awk -v file="$source_name" '$2 == file || $2 == ("*" file) { print $1; exit }' "$sums_file")
    valid_hash=$(printf '%s' "$expected" | grep -Ec '^[0-9a-fA-F]{64}$')
    actual=$(sha256sum "$source_file" | awk '{print $1}')
    if [ "$valid_hash" != "1" ] || [ "$(printf '%s' "$expected" | tr 'A-F' 'a-f')" != "$actual" ]; then
        write_state "error" 0 "$LATEST_VERSION" true false false "SHA-256 校验失败，未修改当前版本"
        rm -rf "$work_dir"
        return 1
    fi
    if tar -tzf "$source_file" | awk '{
        path=$0; sub(/^\.\//, "", path);
        if (path ~ /^\// || path ~ /(^|\/)\.\.(\/|$)/) bad=1;
    } END { exit bad ? 0 : 1 }'; then
        write_state "error" 0 "$LATEST_VERSION" true false false "更新包路径不安全，已拒绝安装"
        rm -rf "$work_dir"
        return 1
    fi

    mkdir -p "${work_dir}/source"
    if ! tar -xzf "$source_file" -C "${work_dir}/source" >> "$RUN_LOG" 2>&1; then
        write_state "error" 0 "$LATEST_VERSION" true false false "更新包无法解压，未修改当前版本"
        rm -rf "$work_dir"
        return 1
    fi
    if ! grep -Fxq "PKG_VERSION:=${LATEST_VERSION}" "${work_dir}/source/Makefile" || \
       ! grep -Fxq "PKG_VERSION=\"${LATEST_VERSION}\"" "${work_dir}/source/scripts/build-ipk.sh" || \
       ! grep -Fxq "CURRENT_VERSION=\"${LATEST_VERSION}\"" "${work_dir}/source/root/usr/lib/minigate/update.sh"; then
        write_state "error" 0 "$LATEST_VERSION" true false false "更新包版本信息不一致，已拒绝安装"
        rm -rf "$work_dir"
        return 1
    fi

    backup="${TMP_ROOT}/backup-before-${CURRENT_VERSION}.tar.gz"
    write_state "backing_up" 65 "$LATEST_VERSION" true true true "正在备份当前程序和配置"
    if ! backup_program "$backup"; then
        write_state "error" 0 "$LATEST_VERSION" true false false "备份失败，未修改当前版本"
        rm -rf "$work_dir"
        return 1
    fi

    write_state "installing" 75 "$LATEST_VERSION" true true true "正在安装新版本，请勿断电"
    if ! /bin/sh "${work_dir}/source/install.sh" >> "$RUN_LOG" 2>&1; then
        write_state "rolling_back" 85 "$LATEST_VERSION" true true false "安装失败，正在恢复原版本"
        if restore_program "$backup"; then
            write_state "rolled_back" 100 "$LATEST_VERSION" true false false "安装失败，已恢复原版本"
        else
            write_state "rollback_failed" 100 "$LATEST_VERSION" true false false "安装失败且自动恢复未完成，请查看更新日志"
        fi
        rm -rf "$work_dir"
        return 1
    fi

    write_state "restarting" 90 "$LATEST_VERSION" true true true "正在验证并重启服务"
    sleep 2
    if ! verify_install; then
        write_state "rolling_back" 95 "$LATEST_VERSION" true true false "服务验证失败，正在恢复原版本"
        if restore_program "$backup"; then
            write_state "rolled_back" 100 "$LATEST_VERSION" true false false "服务验证失败，已恢复原版本"
        else
            write_state "rollback_failed" 100 "$LATEST_VERSION" true false false "服务验证失败且自动恢复未完成，请查看更新日志"
        fi
        rm -rf "$work_dir"
        return 1
    fi

    rm -f /tmp/luci-indexcache /tmp/luci-modulecache
    /etc/init.d/uhttpd restart >> "$RUN_LOG" 2>&1 9>&- || true
    STATE_CURRENT="$LATEST_VERSION"
    write_state "success" 100 "$LATEST_VERSION" false false true "更新成功，服务已恢复"
    rm -rf "$work_dir"
    return 0
}

run_apply() {
    local result

    mkdir -p "$TMP_ROOT" "$(dirname "$LOCK_FILE")"
    exec 9>"$LOCK_FILE" || return 1
    if ! flock -n 9; then
        [ -s "$STATE_FILE" ] || write_state "busy" 0 "" false true false "已有更新任务正在运行"
        exec 9>&-
        return 2
    fi

    run_apply_locked "$1"
    result=$?
    flock -u 9 2>/dev/null || true
    exec 9>&-
    return "$result"
}

case "${1:-status}" in
    status) emit_state ;;
    auto) run_auto_check ;;
    check) run_check ;;
    apply) run_apply "${2:-}" ;;
    *)
        write_state "error" 0 "" false false false "不支持的操作"
        emit_state
        exit 2
        ;;
esac
