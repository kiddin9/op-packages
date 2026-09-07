#!/bin/sh

. /usr/lib/hijpass/app-logger.sh

log_debug "$0"

# 获取配置
DOWNLOAD_TIMEOUT=$(uci -q get hijpass.@rule[0].download_timeout || echo "30")
RETRY_COUNT=$(uci -q get hijpass.@rule[0].retry_count || echo "3")

# 文件路径
CHN_LIST_FILE=$(uci -q get hijpass.@hijpass[0].chn_list)
CHN_ROUTE_FILE=$(uci -q get hijpass.@hijpass[0].chn_route)
CHN_ROUTE6_FILE=$(uci -q get hijpass.@hijpass[0].chn_route6)
GFW_LIST_FILE=$(uci -q get hijpass.@hijpass[0].gfw_list)
GEO_SITE_FILE="/usr/share/v2ray/geosite.dat"
GEO_IP_FILE="/usr/share/v2ray/geoip.dat"

ENABLED=$(uci -q get hijpass.@hijpass[0].enabled || :)

LUA_SCRIPT="/usr/lib/hijpass/luci-utils.lua"

is_safe_query_arg() {
    [ -n "$1" ] && echo "$1" | grep -Eq "^[A-Za-z0-9._:/-]{1,255}$" >/dev/null 2>&1
}

# 下载函数（单个文件）
download_file() {
    local url output temp_file backup_file processed_file
    url="$1"
    output="$2"
    temp_file="${output}.tmp"
    backup_file="${output}.bak"
    processed_file="${output}.processed"

    log_info "Downloading from: $url"

    # 备份现有文件
    if [ -f "$output" ]; then
        cp "$output" "$backup_file"
        log_debug "Backed up existing file: $backup_file"
    fi

    # 使用curl下载
    if curl -L --connect-timeout "$DOWNLOAD_TIMEOUT" \
        --max-time "$((DOWNLOAD_TIMEOUT * 2))" \
        -o "$temp_file" "$url" 2>/dev/null; then

        # 检查文件是否有效（非空且大于100字节）
        if [ -s "$temp_file" ] && [ "$(wc -c <"$temp_file")" -gt 100 ]; then
            # 验证文件格式
            if validate_file_format "$temp_file" "$output"; then
                # 处理域名列表文件，只保留纯域名
                if process_domain_file "$temp_file" "$processed_file" "$output"; then
                    mv "$processed_file" "$output"
                    rm -f "$backup_file" "$temp_file"
                    log_info "Successfully downloaded and processed: $output ($(wc -c <"$output") bytes)"
                    return 0
                else
                    mv "$temp_file" "$output"
                    rm -f "$backup_file"
                    log_info "Successfully downloaded: $output ($(wc -c <"$output") bytes)"
                    return 0
                fi
            else
                log_warn "Downloaded file format validation failed: $url"
                # 恢复备份文件
                if [ -f "$backup_file" ]; then
                    mv "$backup_file" "$output"
                    log_info "Restored backup file: $output"
                fi
                rm -f "$temp_file"
                return 1
            fi
        else
            log_warn "Downloaded file is too small or empty: $url"
            rm -f "$temp_file"
            return 1
        fi
    else
        log_warn "Failed to download: $url"
        rm -f "$temp_file"
        return 1
    fi
}

# 下载多个URL并合并去重
download_and_merge_files() {
    local urls output temp_file backup_file merged_file processed_file
    urls="$1"
    output="$2"
    temp_file="${output}.tmp"
    backup_file="${output}.bak"
    merged_file="${output}.merged"
    processed_file="${output}.processed"

    log_info "Downloading and merging from multiple URLs..."

    # 备份现有文件
    if [ -f "$output" ]; then
        cp "$output" "$backup_file"
        log_debug "Backed up existing file: $backup_file"
    fi

    # 清空合并文件
    : >"$merged_file"

    local success_count=0
    local total_count=0

    # 下载所有URL
    for _url in $urls; do
        if [ -n "$_url" ]; then
            total_count=$((total_count + 1))
            local retry=0
            local downloaded=0

            while [ $retry -lt "$RETRY_COUNT" ]; do
                if curl -L --connect-timeout "$DOWNLOAD_TIMEOUT" \
                    --max-time "$((DOWNLOAD_TIMEOUT * 2))" \
                    -o "$temp_file" "$_url" 2>/dev/null; then

                    # 检查文件是否有效
                    if [ -s "$temp_file" ] && [ "$(wc -c <"$temp_file")" -gt 100 ]; then
                        log_info "Successfully downloaded from: $_url"
                        cat "$temp_file" >>"$merged_file"
                        rm -f "$temp_file"
                        success_count=$((success_count + 1))
                        downloaded=1
                        break
                    fi
                fi
                retry=$((retry + 1))
                if [ $retry -lt "$RETRY_COUNT" ]; then
                    log_warn "Retry $retry/$RETRY_COUNT for: $_url"
                    sleep 2
                fi
            done

            if [ $downloaded -eq 0 ]; then
                log_warn "Failed to download from: $_url after $RETRY_COUNT retries"
            fi
        fi
    done

    # 检查是否至少有一个URL下载成功
    if [ $success_count -eq 0 ]; then
        log_error "Failed to download from all URLs"
        # 恢复备份文件
        if [ -f "$backup_file" ]; then
            mv "$backup_file" "$output"
            log_info "Restored backup file: $output"
        fi
        rm -f "$merged_file" "$temp_file"
        return 1
    fi

    log_info "Downloaded from $success_count/$total_count URLs successfully"

    # 处理合并后的文件（去重）
    if process_domain_file "$merged_file" "$processed_file" "$output"; then
        mv "$processed_file" "$output"
        rm -f "$backup_file" "$merged_file" "$temp_file"
        log_info "Successfully merged and processed: $output ($(wc -c <"$output") bytes)"
        return 0
    else
        # 如果处理失败，直接使用合并文件
        if [ -s "$merged_file" ]; then
            # 对合并文件进行基础去重
            sort "$merged_file" | uniq >"$output"
            rm -f "$backup_file" "$merged_file" "$temp_file"
            log_info "Successfully merged (without processing): $output ($(wc -c <"$output") bytes)"
            return 0
        else
            log_error "Merged file is empty"
            if [ -f "$backup_file" ]; then
                mv "$backup_file" "$output"
                log_info "Restored backup file: $output"
            fi
            rm -f "$merged_file" "$temp_file"
            return 1
        fi
    fi
}

# 检测文件格式类型
detect_file_format() {
    local file sample_lines
    file="$1"

    # 抽取前10行非空非注释行进行格式检测
    sample_lines=$(grep -v "^#\|^!\|^$" "$file" | head -n 10)

    if echo "$sample_lines" | grep -q "^server=/"; then
        echo "dnsmasq"
    elif echo "$sample_lines" | grep -q "^+\."; then
        echo "adguard"
    elif echo "$sample_lines" | grep -q "^@@||.*\^"; then
        echo "adblock"
    elif echo "$sample_lines" | grep -q "^domain:\|^full:\|^regexp:\|^keyword:"; then
        echo "v2ray"
    elif echo "$sample_lines" | grep -qE "^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$"; then
        echo "plain"
    else
        echo "unknown"
    fi
}

# 处理域名文件，只保留纯域名
process_domain_file() {
    local input_file output_file original_output format
    input_file="$1"
    output_file="$2"
    original_output="$3"

    # 检查是否为域名列表文件
    case "$original_output" in
    *"gfw"* | *"chn-list"* | *"china"* | *"accelerated-domains"*)
        log_debug "Processing domain file: $original_output"

        # 检测文件格式
        format=$(detect_file_format "$input_file")
        log_debug "Detected file format: $format"

        # 根据格式选择批量处理方式
        case "$format" in
        "dnsmasq")
            # 批量处理dnsmasq格式: server=/domain.com/8.8.8.8
            grep "^server=/" "$input_file" |
                sed 's/server=\/\([^\/]*\)\/.*/\1/' |
                grep -E "^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$" |
                sort | uniq >"$output_file"
            ;;
        "adguard")
            # 批量处理AdGuard Home格式: +.domain.com
            grep "^+\." "$input_file" |
                sed 's/^+\.//' |
                grep -E "^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$" |
                sort | uniq >"$output_file"
            ;;
        "adblock")
            # 批量处理AdBlock格式: @@||domain.com^
            grep "^@@||.*\^" "$input_file" |
                sed 's/^@@||\([^|^]*\)\^.*/\1/' |
                grep -E "^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$" |
                sort | uniq >"$output_file"
            ;;
        "v2ray")
            # 批量处理V2Ray规则格式，只保留domain和full类型
            grep "^domain:\|^full:" "$input_file" |
                sed 's/^[^:]*://' |
                grep -E "^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$" |
                sort | uniq >"$output_file"
            ;;
        "plain")
            # 批量处理纯域名格式
            grep -v "^#\|^!\|^$" "$input_file" |
                grep -E "^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$" |
                sort | uniq >"$output_file"
            ;;
        "unknown")
            # 混合格式，使用通用处理方式
            {
                # dnsmasq格式
                grep "^server=/" "$input_file" | sed 's/server=\/\([^\/]*\)\/.*/\1/'
                # AdGuard Home格式
                grep "^+\." "$input_file" | sed 's/^+\.//'
                # AdBlock格式
                grep "^@@||.*\^" "$input_file" | sed 's/^@@||\([^|^]*\)\^.*/\1/'
                # V2Ray规则格式
                grep "^domain:\|^full:" "$input_file" | sed 's/^[^:]*://'
                # 纯域名格式
                grep -v "^#\|^!\|^$\|^server=\|^+\.\|^@@||\|^domain:\|^full:\|^regexp:\|^keyword:" "$input_file"
            } |
                grep -E "^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$" |
                sort | uniq >"$output_file"
            ;;
        esac

        # 检查处理后的文件是否有内容
        if [ -s "$output_file" ]; then
            local domain_count
            domain_count=$(wc -l <"$output_file")
            log_info "Processed domain file ($format format): extracted $domain_count unique domains"
            return 0
        else
            log_warn "No valid domains extracted from file"
            rm -f "$output_file"
            return 1
        fi
        ;;
    *)
        # 非域名文件，不需要处理
        return 1
        ;;
    esac
}

# 验证文件格式
validate_file_format() {
    local file output
    file="$1"
    output="$2"

    case "$output" in
    *"chn-list"* | *"china"* | *"accelerated-domains"*)
        # 验证域名列表格式
        if head -n 5 "$file" | grep -q "server="; then
            return 0
        elif head -n 5 "$file" | grep -qE "^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$"; then
            return 0
        fi
        ;;
    *"gfw"*)
        # 验证GFW域名列表格式
        if head -n 5 "$file" | grep -qE "^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$"; then
            log_debug "GFW file validated: plain domain format"
            return 0
        elif head -n 5 "$file" | grep -q "server="; then
            log_debug "GFW file validated: dnsmasq format"
            return 0
        elif head -n 5 "$file" | grep -qE "^\+\.[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$"; then
            log_debug "GFW file validated: AdGuard Home format"
            return 0
        elif head -n 5 "$file" | grep -qE "^@@\|\|[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}\^$"; then
            log_debug "GFW file validated: AdBlock format"
            return 0
        elif head -n 5 "$file" | grep -qE "^(domain|full|regexp|keyword):"; then
            log_debug "GFW file validated: v2ray rules format"
            return 0
        fi
        ;;
    *"geo"*".dat")
        # 验证GEO数据库文件（二进制文件）
        if file "$file" | grep -q "data"; then
            return 0
        fi
        ;;
    *"route"* | *"ip"*)
        # 验证IP路由格式
        if head -n 5 "$file" | grep -qE "^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(/[0-9]+)?$"; then
            return 0
        elif head -n 5 "$file" | grep -qE "^[0-9a-fA-F:]+(/[0-9]+)?$"; then
            return 0
        fi
        ;;
    esac

    log_warn "File format validation failed for: $file"
    return 1
}

# 下载CHN List
download_chn_list() {
    if [ -z "$CHN_LIST_FILE" ]; then
        log_warn "CHN list file path not configured"
        return 1
    fi
    local chn_domain_list
    chn_domain_list="$(uci -q get hijpass.@rule[0].chn_domain_list || :)"
    if [ -z "$chn_domain_list" ]; then
        log_warn "No CHN list download URLs configured"
        return 1
    fi

    log_info "Downloading CHN list..."

    # 下载所有URL并合并去重
    if download_and_merge_files "$chn_domain_list" "$CHN_LIST_FILE"; then
        log_info "CHN list downloaded and merged successfully"
        return 0
    else
        log_error "Failed to download CHN list from all URLs"
        return 1
    fi
}

# 下载CHN Route IPv4
download_chn_route_ipv4() {
    if [ -z "$CHN_ROUTE_FILE" ]; then
        log_warn "CHN route IPv4 file path not configured"
        return 1
    fi
    local chn_v4_route
    chn_v4_route=$(uci -q get hijpass.@rule[0].chn_v4_route)
    if [ -z "$chn_v4_route" ]; then
        log_warn "No CHN route IPv4 download URLs configured"
        return 1
    fi

    log_info "Downloading CHN route IPv4..."

    # 下载所有URL并合并去重
    if download_and_merge_files "$chn_v4_route" "$CHN_ROUTE_FILE"; then
        log_info "CHN route IPv4 downloaded and merged successfully"
        return 0
    else
        log_error "Failed to download CHN route IPv4 from all URLs"
        return 1
    fi
}

# 下载CHN Route IPv6
download_chn_route_ipv6() {
    if [ -z "$CHN_ROUTE6_FILE" ]; then
        log_warn "CHN route IPv6 file path not configured"
        return 1
    fi

    local chn_v6_route
    chn_v6_route=$(uci -q get hijpass.@rule[0].chn_v6_route)
    if [ -z "$chn_v6_route" ]; then
        log_warn "No CHN route IPv6 download URLs configured"
        return 1
    fi

    log_info "Downloading CHN route IPv6..."

    # 下载所有URL并合并去重
    if download_and_merge_files "$chn_v6_route" "$CHN_ROUTE6_FILE"; then
        log_info "CHN route IPv6 downloaded and merged successfully"
        return 0
    else
        log_error "Failed to download CHN route IPv6 from all URLs"
        return 1
    fi
}

# 下载GeoSite
download_geosite() {
    local url retry
    url=$(uci -q get hijpass.@rule[0].geosite)
    if [ -z "$url" ]; then
        log_warn "GeoSite download URL not configured"
        return 1
    fi

    log_info "Downloading GeoSite..."

    retry=0
    while [ $retry -lt "$RETRY_COUNT" ]; do
        if download_file "$url" "$GEO_SITE_FILE"; then
            log_info "GeoSite downloaded successfully"
            return 0
        fi
        retry=$((retry + 1))
        log_warn "Retry $retry/$RETRY_COUNT for GeoSite"
        sleep 2
    done

    log_error "Failed to download GeoSite"
    return 1
}

# 下载GeoIP
download_geoip() {
    local url retry
    url=$(uci -q get hijpass.@rule[0].geoip)
    if [ -z "$url" ]; then
        log_warn "GeoIP download URL not configured"
        return 1
    fi

    log_info "Downloading GeoIP..."

    retry=0
    while [ $retry -lt "$RETRY_COUNT" ]; do
        if download_file "$url" "$GEO_IP_FILE"; then
            log_info "GeoIP downloaded successfully"
            return 0
        fi
        retry=$((retry + 1))
        log_warn "Retry $retry/$RETRY_COUNT for GeoIP"
        sleep 2
    done

    log_error "Failed to download GeoIP"
    return 1
}

# 下载GFW
download_gfw_list() {
    GFW_LIST_FILE=$(uci -q get hijpass.@hijpass[0].gfw_list)
    if [ -z "$GFW_LIST_FILE" ]; then
        log_warn "GFW list file path not configured"
        return 1
    fi
    local urls
    urls=$(uci -q get hijpass.@rule[0].gfw_list)
    if [ -z "$urls" ]; then
        log_warn "GFW download URLs not configured"
        return 1
    fi

    log_info "Downloading GFW list..."

    # 下载所有URL并合并去重
    if download_and_merge_files "$urls" "$GFW_LIST_FILE"; then
        log_info "GFW list downloaded and merged successfully"
        return 0
    else
        log_error "Failed to download GFW list from all URLs"
        return 1
    fi
}

query_rule() {
    if lua $LUA_SCRIPT iptype "$1" >/dev/null 2>&1; then
        find "/etc/hijpass/rules/" -type f \( -name "chn-route*" -o -name "ip*" \) | while read -r file; do
            if lua $LUA_SCRIPT ipmatch "$1" -f "$file" >/dev/null 2>&1; then
                basename "$file"
            fi
        done | sort -u
    else
        find "/etc/hijpass/rules/" -type f \( -name "*list.txt" -o -name "domain*" \) | while read -r file; do
              if lua $LUA_SCRIPT domainmatch "$1" "$file" >/dev/null 2>&1; then
                  basename "$file"
              fi
        done | sort -u
    fi
}

update_rule_files() {
    local failed=0

    log_info "Update all rule files..."
    download_gfw_list || failed=1
    download_chn_list || failed=1
    download_chn_route_ipv4 || failed=1
    download_chn_route_ipv6 || failed=1
    download_geosite || failed=1
    download_geoip || failed=1

    if [ "$ENABLED" != "1" ]; then
        log_info "Skip restart hijpass"
    elif ! /etc/init.d/hijpass restart; then
        failed=1
    fi

    return "$failed"
}

# 主函数
main() {
    local action="$1"

    case "$action" in
    "chnlist")
        download_chn_list
        ;;
    "gfw")
        download_gfw_list
        ;;
    "chnroute")
        download_chn_route_ipv4
        download_chn_route_ipv6
        ;;
    "geo")
        download_geosite
        download_geoip
        ;;
    "all")
        log_info "Downloading all rule files..."
        download_gfw_list
        download_chn_list
        download_chn_route_ipv4
        download_chn_route_ipv6
        download_geosite
        download_geoip
        ;;
    "update")
        if update_rule_files; then
            printf '{"success":true}\n'
        else
            printf '{"success":false}\n'
            return 1
        fi
        ;;
    "query")
        if ! is_safe_query_arg "$2"; then
            echo "Invalid query" >&2
            exit 1
        fi
        query_rule "$2"
        ;;
    *)
        echo "Usage: $0 [chnlist|chnroute|geo|all|update|query]"
        exit 1
        ;;
    esac
}

# 创建必要的目录
mkdir -p "$(dirname "$CHN_LIST_FILE")" 2>/dev/null
mkdir -p "$(dirname "$CHN_ROUTE_FILE")" 2>/dev/null
mkdir -p "$(dirname "$CHN_ROUTE6_FILE")" 2>/dev/null
mkdir -p "$(dirname "$GEO_SITE_FILE")" 2>/dev/null
mkdir -p "$(dirname "$GEO_IP_FILE")" 2>/dev/null
mkdir -p "$(dirname "$GFW_LIST_FILE")" 2>/dev/null

# 执行主函数
main "$@"
