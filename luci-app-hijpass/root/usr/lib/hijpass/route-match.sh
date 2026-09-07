#!/bin/sh

# =================配置区域=================
# 你的配置文件名 (例如 openclash, passwall 等)
CONFIG_PACKAGE="hijpass"
# =========================================
LUA_SCRIPT="/usr/lib/hijpass/luci-utils.lua"
GEOVIEW_SCRIPT="/usr/lib/hijpass/geoview.sh"

. /lib/functions.sh

INPUT=$1
GEOSITE_TAGS=
GEOIP_TAGS=

if [ -z "$INPUT" ]; then
    echo "用法: $0 <域名 或 IP>"
    exit 1
fi

if ! echo "$INPUT" | grep -Eq "^[A-Za-z0-9._:/-]{1,255}$" >/dev/null 2>&1; then
    echo "非法输入: $INPUT" >&2
    exit 1
fi

# =========================================
# 函数 1: IP/CIDR 匹配检查
# 参数 1: 目标 IP (例如 192.168.1.5)
# 参数 2: 规则 IP 或 CIDR (例如 192.168.1.0/24)
# 返回: 0(命中), 1(未命中)
# =========================================
check_ip_cidr_match() {
    local target_ip="$1"
    local rule_cidr="$2"

    lua $LUA_SCRIPT ipmatch "$target_ip" "$rule_cidr" >/dev/null 2>&1
    return $?
}

# =========================================
# 函数 2: 复杂域名匹配检查 (核心更新)
# 支持: 纯字符串, regexp:, domain:, full:
# =========================================
check_domain_complex_match() {
    local target="$1"
    local rule="$2"

    # 1. 处理 "full:" (完整匹配)
    # 语法: full:www.google.com
    if echo "$rule" | grep -q "^full:"; then
        local content="${rule#full:}"
        if [ "$target" = "$content" ]; then
            return 0
        fi
        return 1
    fi

    # 2. 处理 "domain:" (域名及子域名匹配)
    # 语法: domain:google.com (匹配 google.com 和 mail.google.com)
    if echo "$rule" | grep -q "^domain:"; then
        local content="${rule#domain:}"
        # 情况A: 完全相等
        if [ "$target" = "$content" ]; then
            return 0
        fi
        # 情况B: 是子域名 (即 target 以 .content 结尾)
        # 使用 case 语句进行后缀匹配，效率高且兼容性好
        case "$target" in
        *."$content") return 0 ;;
        esac
        return 1
    fi

    # 3. 处理 "regexp:" (正则表达式)
    # 语法: regexp:^www\.
    if echo "$rule" | grep -q "^regexp:"; then
        local content="${rule#regexp:}"
        # 使用 grep -E 进行扩展正则匹配，-i 忽略大小写
        if echo "$target" | grep -E -i -q -e "$content"; then
            return 0
        fi
        return 1
    fi

    # 4. 处理 "纯字符串" (关键字匹配)
    # 语法: baidu (匹配 www.baidu.com, baidu.net)
    # 只要 target 包含 rule 字符串即算命中
    if echo "$target" | grep -F -i -q -e "$rule"; then
        return 0
    fi

    return 1
}

# =========================================
# 函数 3: GeoSite/GeoIP 标签检查 (抽象层)
# 参数 1: 规则行内容 (例如 geosite:google)
# 返回: 1 (始终不命中，仅做日志提示)
# 说明: Shell 无法解析 dat 文件，此函数仅用于识别标签类型
# =========================================
check_geo_label_match() {
    local tags="$1"
    [ -z "$tags" ] && return 1
    [ "$tags" = "notfound" ] && return 1
    local rule_line="$2"
    local type="$3"

    for tag in $tags; do
        if [ "$type:$tag" = "$rule_line" ]; then
            return 0
        fi
    done
    return 1
}

# =========================================
# 主逻辑
# =========================================

# 1. 识别输入类型
if lua $LUA_SCRIPT iptype "$INPUT" >/dev/null 2>&1; then
    IS_IP=1
    TYPE="IP"
#    echo "正在检测 IP: $INPUT ..."
else
    IS_IP=0
    TYPE="域名"
#    echo "正在检测域名: $INPUT ..."
fi

MATCHED_RULE=""

# UCI 遍历回调函数
handle_rule() {
    local config="$1"
    local name
    local enabled
    local domain_list
    local ip_list
    local proxy_node

    config_get name "$config" name "Unnamed"
    config_get enabled "$config" enabled "0"
    config_get proxy_node "$config" proxy_node "default"

    [ "$enabled" != "1" ] && return 0

    # === 检查 IP 列表 ===
    if [ "$IS_IP" -eq 1 ]; then
        config_get ip_list "$config" ip_list
        if [ -n "$ip_list" ]; then
            [ -z "$GEOIP_TAGS" ] && {
                if echo "$ip_list" | grep -v '^[[:space:]]*#' | grep -E -q 'geoip:'; then
                    GEOIP_TAGS="$($GEOVIEW_SCRIPT -l "geoip" "$INPUT")"
                    [ -z "$GEOIP_TAGS" ] && GEOIP_TAGS="notfound"
                fi
            }
            while IFS= read -r line; do
                # 清理注释和空格
                clean_line=$(echo "$line" | sed 's/#.*//' | sed 's/^[ \t]*//;s/[ \t]*$//')
                [ -z "$clean_line" ] && continue

                if echo "$clean_line" | grep -vq "geoip:"; then
                    # 调用 IP 检查函数
                    if check_ip_cidr_match "$INPUT" "$clean_line"; then
                        print_result "$name" "$clean_line" "$proxy_node" "$config"
                        exit 0
                    fi
                elif echo "$clean_line" | grep -E -q '^rule-set:'; then
                    continue
                else
                    if check_geo_label_match "$GEOIP_TAGS" "$clean_line" "geoip"; then
                        print_result "$name" "$clean_line" "$proxy_node" "$config"
                        exit 0
                    fi
                fi
            done <<EOF
$ip_list
EOF
        fi
    fi

    # === 检查 域名/Geo 列表 ===
    # 注意：即使输入是 IP，有些配置也可能在 domain_list 里放 geoip，但通常 domain_list 放域名
    # 这里逻辑是：如果输入是域名，才去检查 domain_list
    if [ "$IS_IP" -eq 0 ]; then
        config_get domain_list "$config" domain_list
        if [ -n "$domain_list" ]; then
            [ -z "$GEOSITE_TAGS" ] && {
                if echo "$domain_list" | grep -v '^[[:space:]]*#' | grep -E -q 'geosite:'; then
                    GEOSITE_TAGS="$($GEOVIEW_SCRIPT -l "geosite" "$INPUT")"
                    [ -z "$GEOSITE_TAGS" ] && GEOSITE_TAGS="notfound"
                fi
            }
            while IFS= read -r line; do
                clean_line=$(echo "$line" | sed 's/#.*//' | sed 's/^[ \t]*//;s/[ \t]*$//')
                [ -z "$clean_line" ] && continue

                if echo "$clean_line" | grep -v "geosite:" >/dev/null; then
                    if check_domain_complex_match "$INPUT" "$clean_line"; then
                        print_result "$name" "$clean_line" "$proxy_node" "$config"
                        exit 0
                    fi
                elif echo "$clean_line" | grep -E -q '^rule-set:'; then
                    continue
                else
                    if check_geo_label_match "$GEOSITE_TAGS" "$clean_line" "geosite"; then
                        print_result "$name" "$clean_line" "$proxy_node" "$config"
                        exit 0
                    fi
                fi
            done <<EOF
$domain_list
EOF
        fi
    fi
}

handle_default() {
    config="$1"
    local default_proxy_node
    config_get default_proxy_node "$config" default_proxy_node
    print_result "全局默认" "* (全部)" "$default_proxy_node" "-"
}

set_geo_tags() {
    local config="$1"

    [ -z "$GEOSITE_TAGS" ] && {
        local domain_list
        config_get domain_list "$config" domain_list
        if echo "$domain_list" | grep -v '^[[:space:]]*#' | grep -E -q 'geosite:'; then
            GEOSITE_TAGS="$($GEOVIEW_SCRIPT -l "geosite" "$INPUT")"
        fi
    }
    [ -z "$GEOIP_TAGS" ] && {
        local ip_list
        config_get ip_list "$config" ip_list
        if echo "$ip_list" | grep -v '^[[:space:]]*#' | grep -E -q 'geoip:'; then
            GEOIP_TAGS="$($GEOVIEW_SCRIPT -l "geoip" "$INPUT")"
        fi
    }
}

# 辅助函数：打印结果
print_result() {
    echo "规则名称 (Name) : $1"
    echo "匹配类型 (Type) : $TYPE"
    echo "匹配内容 (Item) : $2"
    echo "代理策略 (Node) : $3"
#    echo "配置段名 (ID)   : $4"
    MATCHED_RULE="yes"
}

# 加载配置
config_load "$CONFIG_PACKAGE"
config_foreach handle_rule shunt_route_rule

if [ -z "$MATCHED_RULE" ]; then
    echo -e "未匹配到任何自定义规则，除去协议、端口等规则外，将使用全局默认策略\n"
    config_foreach handle_default shunt
fi
