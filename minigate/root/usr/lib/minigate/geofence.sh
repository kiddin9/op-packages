#!/bin/sh
# MiniGate GeoFence - 地区访问控制
# 检查反代访问日志，非允许地区的 IP 用防火墙封禁
LOGFILE="/var/log/minigate-geofence.log"
CACHE_DIR="/tmp/minigate_geo"
BLOCK_SET="minigate_blocked"
ACCESS_LOG="/var/log/minigate-access.log"

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') [GEOFENCE] $*" >> "$LOGFILE"; }

# 查询 IP 归属地，返回省份名
lookup_geo() {
    local ip="$1"
    local cache="$CACHE_DIR/${ip}"
    
    # 缓存命中
    [ -f "$cache" ] && cat "$cache" && return 0
    
    local geo=""
    
    # API 1: pconline
    if [ -z "$geo" ]; then
        local raw=$(curl -s --connect-timeout 3 --max-time 5 "https://whois.pconline.com.cn/ipJson.jsp?ip=${ip}&json=true" 2>/dev/null)
        geo=$(echo "$raw" | jsonfilter -e '$.pro' 2>/dev/null)
    fi
    
    # API 2: ip9.com.cn
    if [ -z "$geo" ]; then
        local raw=$(curl -s --connect-timeout 3 --max-time 5 "https://ip9.com.cn/get?ip=${ip}" 2>/dev/null)
        geo=$(echo "$raw" | jsonfilter -e '$.data.prov' 2>/dev/null)
    fi
    
    # API 3: ip-api.com
    if [ -z "$geo" ]; then
        local raw=$(curl -s --connect-timeout 3 --max-time 5 "http://ip-api.com/json/${ip}?fields=regionName" 2>/dev/null)
        geo=$(echo "$raw" | jsonfilter -e '$.regionName' 2>/dev/null)
    fi
    
    [ -z "$geo" ] && geo="unknown"
    
    # 写入缓存
    mkdir -p "$CACHE_DIR"
    echo "$geo" > "$cache"
    echo "$geo"
}

# 检查 IP 是否在允许的地区列表中
is_allowed() {
    local geo="$1"
    local allowed=$(uci -q get minigate.global.geo_allowed)
    
    [ -z "$allowed" ] && return 0  # 未配置地区限制，全部放行
    
    # allowed 是逗号分隔的省份列表，如 "四川,重庆,贵州"
    echo "$allowed" | tr ',' '\n' | while read prov; do
        [ -z "$prov" ] && continue
        echo "$geo" | grep -q "$prov" && echo "yes" && return 0
    done | grep -q "yes"
}

# 初始化 ipset（nftables 或 iptables）
init_block_set() {
    if command -v nft >/dev/null 2>&1; then
        # nftables (OpenWrt 22+)
        nft list set inet fw4 "$BLOCK_SET" >/dev/null 2>&1 || {
            nft add set inet fw4 "$BLOCK_SET" '{ type ipv4_addr; flags timeout; }'
            nft add rule inet fw4 input ip saddr @"$BLOCK_SET" drop 2>/dev/null
            log "nftables 封禁集合已创建"
        }
    else
        # iptables fallback
        ipset list "$BLOCK_SET" >/dev/null 2>&1 || {
            ipset create "$BLOCK_SET" hash:ip timeout 43200 2>/dev/null  # 12小时超时
            iptables -I INPUT -m set --match-set "$BLOCK_SET" src -j DROP 2>/dev/null
            log "ipset 封禁集合已创建"
        }
    fi
}

# 封禁 IP
block_ip() {
    local ip="$1" reason="$2"
    if command -v nft >/dev/null 2>&1; then
        nft add element inet fw4 "$BLOCK_SET" "{ $ip timeout 12h }" 2>/dev/null
    else
        ipset add "$BLOCK_SET" "$ip" timeout 43200 2>/dev/null
    fi
    log "封禁: $ip ($reason) 12小时"
    
    # 记录到 UCI
    local ts=$(date '+%Y-%m-%d %H:%M:%S')
    uci -q add_list minigate.global.blocked_ips="${ip}|${reason}|${ts}"
    uci commit minigate 2>/dev/null
}

# 清理过期缓存（超过24小时的）
clean_cache() {
    [ -d "$CACHE_DIR" ] && find "$CACHE_DIR" -type f -mmin +1440 -delete 2>/dev/null
}

# 主逻辑：扫描 access log 中的新 IP
scan_and_block() {
    local enabled=$(uci -q get minigate.global.geo_enabled)
    [ "$enabled" != "1" ] && return 0
    
    local allowed=$(uci -q get minigate.global.geo_allowed)
    [ -z "$allowed" ] && { log "未配置允许地区，跳过"; return 0; }
    
    init_block_set
    
    # 提取所有外网 IP（排除内网）
    local ips=$(grep -oP '"client":"[^"]*"' "$ACCESS_LOG" 2>/dev/null | \
        grep -oP '[\d\.]+' | \
        grep -v '^192\.168\.' | grep -v '^10\.' | grep -v '^172\.(1[6-9]|2[0-9]|3[01])\.' | grep -v '^127\.' | \
        sort -u)
    
    local checked=0 blocked=0
    for ip in $ips; do
        # 已经封禁的跳过
        if command -v nft >/dev/null 2>&1; then
            nft list set inet fw4 "$BLOCK_SET" 2>/dev/null | grep -q "$ip" && continue
        else
            ipset test "$BLOCK_SET" "$ip" 2>/dev/null && continue
        fi
        
        local geo=$(lookup_geo "$ip")
        checked=$((checked + 1))
        
        if [ "$geo" = "unknown" ]; then
            log "警告: $ip 归属地未知，暂时放行"
            continue
        fi
        
        if ! is_allowed "$geo"; then
            block_ip "$ip" "$geo"
            blocked=$((blocked + 1))
        else
            log "放行: $ip ($geo)"
        fi
        
        # 限速，避免 API 过载
        sleep 1
    done
    
    [ "$checked" -gt 0 ] && log "扫描完成: 检查 $checked 个IP，封禁 $blocked 个"
    clean_cache
}

# 手动解封
unblock_ip() {
    local ip="$1"
    if command -v nft >/dev/null 2>&1; then
        nft delete element inet fw4 "$BLOCK_SET" "{ $ip }" 2>/dev/null
    else
        ipset del "$BLOCK_SET" "$ip" 2>/dev/null
    fi
    log "解封: $ip"
}

# 清除所有封禁
flush_blocks() {
    if command -v nft >/dev/null 2>&1; then
        nft flush set inet fw4 "$BLOCK_SET" 2>/dev/null
    else
        ipset flush "$BLOCK_SET" 2>/dev/null
    fi
    uci -q delete minigate.global.blocked_ips
    uci commit minigate 2>/dev/null
    log "已清除所有封禁"
}

case "${1:-scan}" in
    scan) scan_and_block ;;
    unblock) unblock_ip "$2" ;;
    flush) flush_blocks ;;
    *) echo "用法: $0 {scan|unblock <ip>|flush}" ;;
esac
