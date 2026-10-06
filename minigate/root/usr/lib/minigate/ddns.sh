#!/bin/sh
LOGFILE="/var/log/minigate-ddns.log"
HISTORY_DIR="${MINIGATE_HISTORY_DIR:-/etc/minigate/ddns-history}"
HISTORY_WINDOW="${MINIGATE_HISTORY_WINDOW:-86400}"

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') [DDNS] $*" >> "$LOGFILE"; }
trim_log() { [ -f "$LOGFILE" ] && [ "$(wc -l < "$LOGFILE")" -gt 300 ] && { tail -n 150 "$LOGFILE" > "${LOGFILE}.tmp"; mv "${LOGFILE}.tmp" "$LOGFILE"; }; }

history_now() {
    if [ -n "${MINIGATE_HISTORY_NOW:-}" ]; then
        printf '%s\n' "$MINIGATE_HISTORY_NOW"
    else
        date +%s
    fi
}

compact_history_file() {
    local file="$1" now="$2" cutoff tmp
    cutoff=$((now - HISTORY_WINDOW))
    tmp="${file}.tmp.$$"

    awk -F '\t' -v cutoff="$cutoff" '
        $1 ~ /^[0-9]+$/ && NF >= 2 {
            if ($1 < cutoff) {
                anchor = $0
                next
            }
            if (!emitted && anchor != "") {
                print anchor
                emitted = 1
            }
            print
            emitted = 1
        }
        END {
            if (!emitted && anchor != "") print anchor
        }
    ' "$file" > "$tmp" && chmod 600 "$tmp" 2>/dev/null && mv "$tmp" "$file"
}

record_ip_history_locked() {
    local file="$1" ip="$2" now="$3" last_ip
    if [ -f "$file" ]; then
        last_ip=$(awk -F '\t' 'NF >= 2 { value=$2 } END { print value }' "$file" 2>/dev/null)
    else
        last_ip=""
    fi
    [ "$last_ip" = "$ip" ] && return 0

    printf '%s\t%s\n' "$now" "$ip" >> "$file" || return 1
    chmod 600 "$file" 2>/dev/null || true
    compact_history_file "$file" "$now"
}

record_ip_history() {
    local section="$1" family="$2" ip="$3" safe_section file now last_ip
    case "$family" in ipv4|ipv6) ;; *) return 1 ;; esac
    [ -n "$ip" ] || return 1

    safe_section=$(printf '%s' "$section" | tr -c 'A-Za-z0-9_-' '_')
    [ -n "$safe_section" ] || return 1
    if [ ! -d "$HISTORY_DIR" ]; then
        mkdir -p "$HISTORY_DIR" || return 1
        chmod 700 "$HISTORY_DIR" 2>/dev/null || true
    fi
    file="${HISTORY_DIR}/${safe_section}.${family}.tsv"
    if [ -f "$file" ]; then
        last_ip=$(awk -F '\t' 'NF >= 2 { value=$2 } END { print value }' "$file" 2>/dev/null)
        [ "$last_ip" = "$ip" ] && return 0
    fi
    now=$(history_now)
    case "$now" in ''|*[!0-9]*) return 1 ;; esac

    if command -v flock >/dev/null 2>&1; then
        (
            umask 077
            exec 8>"${file}.lock"
            flock -x 8 || exit 1
            record_ip_history_locked "$file" "$ip" "$now"
        )
    else
        record_ip_history_locked "$file" "$ip" "$now"
    fi
}

# ====== IPv4 获取 ======
get_ip4_iface() {
    local ip=""
    ip=$(ubus call network.interface.${1:-wan} status 2>/dev/null | jsonfilter -e '@["ipv4-address"][0].address' 2>/dev/null)
    [ -z "$ip" ] && ip=$(ifstatus "${1:-wan}" 2>/dev/null | jsonfilter -e '@["ipv4-address"][0].address' 2>/dev/null)
    echo "$ip" | grep -oE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'
}

get_ip4_url() {
    local ip=""
    # 备用 URL 列表（主选 + 自动回退）
    local fallback_urls="http://ip.3322.net http://members.3322.org/dyndns/getip http://ns1.dnspod.net:6666 http://ip.tool.chinaz.com/getip"
    local urls="$1 $fallback_urls"

    for url in $urls; do
        local host=$(echo "$url" | sed -E 's|https?://||;s|/.*||;s|:.*||')
        local port=$(echo "$url" | grep -oE ':[0-9]+' | head -1 | tr -d ':')
        local path=$(echo "$url" | sed -E 's|https?://[^/]*||')
        [ -z "$path" ] && path="/"
        [ -z "$port" ] && port="80"

        # 方法1: 直连
        ip=$(curl -4 -s --connect-timeout 3 "$url" 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -1)
        [ -n "$ip" ] && { echo "$ip"; return; }

        # 方法2: DNS 解析后用 Host 头直连（绕过代理）
        local resolved=$(nslookup "$host" 223.5.5.5 2>/dev/null | grep -A1 'Name:' | grep 'Address:' | head -1 | awk '{print $2}')
        if [ -n "$resolved" ]; then
            ip=$(curl -4 -s --connect-timeout 3 -H "Host: ${host}" "http://${resolved}:${port}${path}" 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -1)
            [ -n "$ip" ] && { echo "$ip"; return; }
        fi
    done
    echo ""
}

# ====== IPv6 获取 ======
get_ip6_iface() {
    local ip="" iface="${1:-wan6}"
    # 优先取全局 IPv6 地址（排除 link-local fe80::）
    ip=$(ubus call network.interface.${iface} status 2>/dev/null | jsonfilter -e '@["ipv6-address"][0].address' 2>/dev/null)
    [ -z "$ip" ] && ip=$(ifstatus "${iface}" 2>/dev/null | jsonfilter -e '@["ipv6-address"][0].address' 2>/dev/null)
    # 也尝试从 ipv6-prefix-assignment 获取
    [ -z "$ip" ] && ip=$(ubus call network.interface.${iface} status 2>/dev/null | jsonfilter -e '@["ipv6-prefix-assignment"][0]["local-address"].address' 2>/dev/null)
    # 验证是有效的 IPv6（排除 link-local）
    echo "$ip" | grep -v '^fe80' | grep -oE '^[0-9a-fA-F:]+$' | head -1
}

get_ip6_url() {
    local url="$1" ip=""
    local host=$(echo "$url" | sed -E 's|https?://||;s|/.*||;s|:.*||')
    local port=$(echo "$url" | grep -oE ':[0-9]+' | head -1 | tr -d ':')

    # 先尝试直连
    ip=$(curl -6 -s --connect-timeout 5 "$url" 2>/dev/null | grep -oE '([0-9a-fA-F]{0,4}:){2,7}[0-9a-fA-F]{0,4}' | head -1)

    # 如果失败，DNS 解析后直连绕过代理
    if [ -z "$ip" ]; then
        local resolved=$(nslookup "$host" 223.5.5.5 2>/dev/null | grep -A1 'Name:' | grep 'Address:' | head -1 | awk '{print $2}')
        if [ -n "$resolved" ]; then
            local scheme="http"
            echo "$url" | grep -q '^https' && scheme="https"
            [ -z "$port" ] && { [ "$scheme" = "https" ] && port="443" || port="80"; }
            ip=$(curl -6 -s --connect-timeout 5 --resolve "${host}:${port}:${resolved}" "$url" 2>/dev/null | grep -oE '([0-9a-fA-F]{0,4}:){2,7}[0-9a-fA-F]{0,4}' | head -1)
        fi
    fi
    echo "$ip"
}

# ====== Cloudflare API：支持 A 和 AAAA 记录 ======
cf_update() {
    local zone_id="$1" token="$2" domain="$3" ip="$4" record_type="$5"
    # record_type: A 或 AAAA
    [ -z "$record_type" ] && record_type="A"
    local resp match_resp rids rid keep_id result
    resp=$(curl -s --connect-timeout 10 -H "Authorization: Bearer $token" -H "Content-Type: application/json" \
        "https://api.cloudflare.com/client/v4/zones/${zone_id}/dns_records?type=${record_type}&name=${domain}" 2>/dev/null)
    result=$(echo "$resp" | jsonfilter -e '$.success' 2>/dev/null)
    [ "$result" = "true" ] || { echo "false"; return 1; }

    rids=$(echo "$resp" | jsonfilter -e '$.result[*].id' 2>/dev/null)
    if [ -n "$rids" ]; then
        match_resp=$(curl -s --connect-timeout 10 -H "Authorization: Bearer $token" -H "Content-Type: application/json" \
            "https://api.cloudflare.com/client/v4/zones/${zone_id}/dns_records?type=${record_type}&name=${domain}&content=${ip}" 2>/dev/null)
        result=$(echo "$match_resp" | jsonfilter -e '$.success' 2>/dev/null)
        [ "$result" = "true" ] || { echo "false"; return 1; }
        keep_id=$(echo "$match_resp" | jsonfilter -e '$.result[0].id' 2>/dev/null)

        if [ -z "$keep_id" ]; then
            for rid in $rids; do keep_id="$rid"; break; done
            resp=$(curl -s --connect-timeout 10 -X PUT -H "Authorization: Bearer $token" -H "Content-Type: application/json" \
                -d "{\"type\":\"$record_type\",\"name\":\"$domain\",\"content\":\"$ip\",\"ttl\":120,\"proxied\":false}" \
                "https://api.cloudflare.com/client/v4/zones/${zone_id}/dns_records/${keep_id}" 2>/dev/null)
            result=$(echo "$resp" | jsonfilter -e '$.success' 2>/dev/null)
            [ "$result" = "true" ] || { echo "false"; return 1; }
        fi

        for rid in $rids; do
            [ "$rid" = "$keep_id" ] && continue
            resp=$(curl -s --connect-timeout 10 -X DELETE -H "Authorization: Bearer $token" -H "Content-Type: application/json" \
                "https://api.cloudflare.com/client/v4/zones/${zone_id}/dns_records/${rid}" 2>/dev/null)
            result=$(echo "$resp" | jsonfilter -e '$.success' 2>/dev/null)
            [ "$result" = "true" ] || { echo "false"; return 1; }
        done
        echo "true"
    else
        resp=$(curl -s --connect-timeout 10 -X POST -H "Authorization: Bearer $token" -H "Content-Type: application/json" \
            -d "{\"type\":\"$record_type\",\"name\":\"$domain\",\"content\":\"$ip\",\"ttl\":120,\"proxied\":false}" \
            "https://api.cloudflare.com/client/v4/zones/${zone_id}/dns_records" 2>/dev/null)
        echo "$resp" | jsonfilter -e '$.success' 2>/dev/null
    fi
}

calc_next() {
    local interval="${1:-300}"
    local now=$(date +%s)
    local next=$((now + interval))
    date -d "@${next}" '+%H:%M:%S' 2>/dev/null || echo "${interval}秒后"
}

update_one() {
    local sec="$1" force="$2"
    local enabled=$(uci -q get minigate.${sec}.enabled)
    [ "$enabled" = "1" ] || return 0

    local domain=$(uci -q get minigate.${sec}.domain)
    local zone_id=$(uci -q get minigate.${sec}.cf_zone_id)
    local token=$(uci -q get minigate.${sec}.cf_api_token)
    local ip_source=$(uci -q get minigate.${sec}.ip_source)
    local iface=$(uci -q get minigate.${sec}.interface)
    local ip_url=$(uci -q get minigate.${sec}.ip_url)
    local interval=$(uci -q get minigate.${sec}.check_interval); interval=${interval:-300}
    local ip_version=$(uci -q get minigate.${sec}.ip_version); ip_version=${ip_version:-ipv4}
    local iface6=$(uci -q get minigate.${sec}.interface6); iface6=${iface6:-wan6}
    local ip_url6=$(uci -q get minigate.${sec}.ip_url6); ip_url6=${ip_url6:-https://api6.ipify.org}

    [ -z "$domain" ] || [ -z "$zone_id" ] || [ -z "$token" ] && {
        log "$domain: 配置不完整"
        uci -q set minigate.${sec}.status="error"; uci -q set minigate.${sec}.status_msg="配置不完整"
        return 1
    }

    local cache="/tmp/minigate_ddns_${sec}.cache"
    local cache6="/tmp/minigate_ddns_${sec}_v6.cache"
    local cached=$(cat "$cache" 2>/dev/null)
    local cached6=$(cat "$cache6" 2>/dev/null)
    local next_time=$(calc_next "$interval")
    local any_ok=0 any_fail=0
    local result_ip="" result_ip6=""
    local msgs=""

    # ====== IPv4 处理 ======
    if [ "$ip_version" = "ipv4" ] || [ "$ip_version" = "dual" ]; then
        local ip4=""
        case "$ip_source" in url) ip4=$(get_ip4_url "$ip_url");; *) ip4=$(get_ip4_iface "$iface");; esac

        if [ -z "$ip4" ]; then
            log "$domain: 获取IPv4失败"
            msgs="${msgs}IPv4获取失败; "
            any_fail=1
        else
            record_ip_history "$domain" "ipv4" "$ip4" || log "$domain: IPv4历史记录写入失败"
        fi

        if [ -n "$ip4" ] && { [ "$force" = "1" ] || [ "$ip4" != "$cached" ]; }; then
            log "$domain: IPv4 ${cached:-无} -> $ip4"
            local result=$(cf_update "$zone_id" "$token" "$domain" "$ip4" "A")
            if [ "$result" = "true" ]; then
                log "$domain: A记录同步成功"
                echo "$ip4" > "$cache"
                result_ip="$ip4"
                msgs="${msgs}A:${ip4} ✓; "
                any_ok=1
            else
                log "$domain: A记录同步失败"
                msgs="${msgs}A记录失败; "
                any_fail=1
            fi
        elif [ -n "$ip4" ]; then
            log "$domain: IPv4地址一致($ip4)"
            result_ip="$ip4"
            msgs="${msgs}A:${ip4} (未变); "
            any_ok=1
        fi
    fi

    # ====== IPv6 处理 ======
    if [ "$ip_version" = "ipv6" ] || [ "$ip_version" = "dual" ]; then
        local ip6=""
        case "$ip_source" in url) ip6=$(get_ip6_url "$ip_url6");; *) ip6=$(get_ip6_iface "$iface6");; esac

        if [ -z "$ip6" ]; then
            log "$domain: 获取IPv6失败"
            msgs="${msgs}IPv6获取失败; "
            # 双栈模式下 IPv6 获取失败不算整体失败
            [ "$ip_version" = "ipv6" ] && any_fail=1
        else
            record_ip_history "$domain" "ipv6" "$ip6" || log "$domain: IPv6历史记录写入失败"
        fi

        if [ -n "$ip6" ] && { [ "$force" = "1" ] || [ "$ip6" != "$cached6" ]; }; then
            log "$domain: IPv6 ${cached6:-无} -> $ip6"
            local result=$(cf_update "$zone_id" "$token" "$domain" "$ip6" "AAAA")
            if [ "$result" = "true" ]; then
                log "$domain: AAAA记录同步成功"
                echo "$ip6" > "$cache6"
                result_ip6="$ip6"
                msgs="${msgs}AAAA:${ip6} ✓; "
                any_ok=1
            else
                log "$domain: AAAA记录同步失败"
                msgs="${msgs}AAAA记录失败; "
                any_fail=1
            fi
        elif [ -n "$ip6" ]; then
            log "$domain: IPv6地址一致($ip6)"
            result_ip6="$ip6"
            msgs="${msgs}AAAA:${ip6} (未变); "
            any_ok=1
        fi
    fi

    # ====== 更新状态 ======
    if [ "$any_ok" = "1" ] && [ "$any_fail" = "0" ]; then
        uci -q set minigate.${sec}.status="ok"
    elif [ "$any_ok" = "1" ] && [ "$any_fail" = "1" ]; then
        uci -q set minigate.${sec}.status="partial"
    else
        uci -q set minigate.${sec}.status="error"
    fi
    uci -q set minigate.${sec}.status_msg="$msgs"
    [ -n "$result_ip" ] && uci -q set minigate.${sec}.last_ip="$result_ip"
    [ -n "$result_ip6" ] && uci -q set minigate.${sec}.last_ip6="$result_ip6"
    uci -q set minigate.${sec}.last_update="$(date '+%Y-%m-%d %H:%M:%S')"
    uci -q set minigate.${sec}.next_sync="$next_time"
}

main() {
    local gen=$(uci -q get minigate.global.enabled)
    if [ "$gen" != "1" ]; then
        log "全局未启用，跳过 DDNS"
        return 0
    fi

    local force=0; [ "$1" = "force" ] && force=1
    log "--- 开始同步 ---"
    local sections=$(uci -q show minigate | grep '=ddns$' | cut -d. -f2 | cut -d= -f1)
    local c=0
    for sec in $sections; do update_one "$sec" "$force"; c=$((c + 1)); done
    [ "$c" = "0" ] && log "无 DDNS 记录"
    uci commit minigate
    log "--- 同步完成 ($c 条) ---"
    trim_log
}

if [ "${MINIGATE_DDNS_LIBRARY_ONLY:-0}" = "1" ]; then
    return 0 2>/dev/null || exit 0
fi

# 手动单条同步
if [ "$1" = "single" ] && [ -n "$2" ]; then
    log "手动同步: $2"
    update_one "$2" "1"
    uci commit minigate
    trim_log
    exit 0
fi

main "$@"
