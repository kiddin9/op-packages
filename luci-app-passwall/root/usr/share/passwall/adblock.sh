#!/bin/sh
# OpenWrt Passwall 广告域名列表下载与合并脚本

LOCK_FILE="/var/lock/ad_download.lock"
TMP_DIR="/tmp/ad_download"
RULES_PATH="/usr/share/passwall/rules"

# ========== 白名单：合并后需要排除的域名 ==========
WHITELIST="ip-api.com"

# ========== 加锁，防止重复运行 ==========
exec 200>"$LOCK_FILE"
if ! flock -n 200; then
    echo "[ERROR] 脚本已在运行中，退出"
    exit 1
fi
echo $$ >&200

cleanup() {
    rm -rf "$TMP_DIR"
    flock -u 200
    rm -f "$LOCK_FILE"
}
trap cleanup EXIT INT TERM

rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR"

# ========== 单个 URL 的下载与解析函数 ==========
process_url() {
    local idx="$1"
    local url="$2"
    local raw="$TMP_DIR/raw_${idx}.txt"
    local parsed="$TMP_DIR/parsed_${idx}.txt"

    echo "[INFO] #${idx} 正在下载: $url"
    wget -q --no-check-certificate -O "$raw" "$url" -T 15

    if [ ! -s "$raw" ]; then
        echo "[WARN] #${idx} 下载失败或文件为空，跳过: $url"
        return
    fi

    # 一次 awk 完成：去\r、去注释、去空行、格式检测、转换、域名校验
    awk '
    BEGIN { fmt = ""; sample_count = 0 }
    {
        # 去除 \r
        gsub(/\r/, "")
        # 去除首尾空格
        gsub(/^[[:space:]]+|[[:space:]]+$/, "")
        # 跳过注释和空行
        if ($0 ~ /^[#!]/ || $0 ~ /^\[Adblock/ || $0 == "") next

        # 前20行探测格式
        if (sample_count < 20) {
            sample_count++
            if (fmt == "" && $0 ~ /^address=\/[^\/]+\//)      fmt = "dnsmasq"
            if (fmt == "" && $0 ~ /^DOMAIN-SUFFIX,/)          fmt = "clash"
			if (fmt == "" && $0 ~ /^\|\|[a-zA-Z0-9]/)         fmt = "adguard"
			if (fmt == "" && $0 ~ /^(0\.0\.0\.0|127\.0\.0\.1)[[:space:]]/)
                fmt = "hosts"
            if (fmt == "" && $0 ~ /^[a-zA-Z0-9]([a-zA-Z0-9.\-]*[a-zA-Z0-9])?\.[a-zA-Z]{2,}$/)
                fmt = "plain"
        }

        # 按格式提取域名
        if (fmt == "dnsmasq") {
            # 匹配 address=/domain/ 和 address=/domain/0.0.0.0 等
            n = split($0, a, "/")
            if (n >= 3 && a[1] == "address=") print a[2]
        } else if (fmt == "clash") {
            if (sub(/^DOMAIN-SUFFIX,/, "")) print
        } else if (fmt == "hosts") {
            # 0.0.0.0  domain.com  或  127.0.0.1  domain.com
            if ($0 ~ /^(0\.0\.0\.0|127\.0\.0\.1)[[:space:]]/) {
                domain = $2
                # 去掉行尾可能的注释
                gsub(/#.*/, "", domain)
                gsub(/[[:space:]]/, "", domain)
                if (domain ~ /^[a-zA-Z0-9]([a-zA-Z0-9.\-]*[a-zA-Z0-9])?\.[a-zA-Z]{2,}$/)
                    print domain
            }
        } else if (fmt == "adguard") {
            if ($0 ~ /^\|\|/) {
                line = $0
                # 去掉开头 ||
                sub(/^\|\|/, "", line)
                # 去掉 ^ 及之后所有内容（^$third-party 等修饰符）
                sub(/\^.*/, "", line)
                # 去掉可能残留的 $ 修饰符
                sub(/\$.*/, "", line)
                # 校验结果是否为合法域名
                if (line ~ /^[a-zA-Z0-9]([a-zA-Z0-9.\-]*[a-zA-Z0-9])?\.[a-zA-Z]{2,}$/)
                    print line
            }
        } else if (fmt == "plain") {
            if ($0 ~ /^[a-zA-Z0-9]([a-zA-Z0-9\-]*[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]*[a-zA-Z0-9])?)+$/)
                print
        }
    }
    END {
        if (fmt == "")
            print "[WARN] 未知格式，已丢弃" > "/dev/stderr"
    }
    ' "$raw" > "$parsed"

    rm -f "$raw"

    # 如果解析结果为空则删除
    [ ! -s "$parsed" ] && rm -f "$parsed"
}

# ========== 读取所有 ad_url 并发下载 ==========
AD_URLS=$(uci -q get passwall.@global[0].ad_url 2>/dev/null)

if [ -z "$AD_URLS" ]; then
    echo "[ERROR] 未找到任何 ad_url 配置"
    exit 1
fi

INDEX=0
for url in $AD_URLS; do
    [ -z "$url" ] && continue
    INDEX=$((INDEX + 1))
    process_url "$INDEX" "$url"
done

# ========== 合并、去重、去空行、排除白名单 ==========
[ -f $RULES_PATH/my_block_host ] || touch $RULES_PATH/my_block_host
if ls "$TMP_DIR"/parsed_*.txt >/dev/null 2>&1; then
    NEW_FILE="$TMP_DIR/ad_domains_new.txt"
	awk -v wl="$WHITELIST" '
    BEGIN {
        n = split(wl, a, " ")
        for (i = 1; i <= n; i++) white[a[i]] = 1
    }
    NF && !seen[$0]++ && !($0 in white)
    ' "$TMP_DIR"/parsed_*.txt $RULES_PATH/my_block_host > "$NEW_FILE"

    # ========== 比较新旧文件 hash ==========
    if [ -f "$RULES_PATH/block_host" ]; then
        OLD_HASH=$(md5sum "$RULES_PATH/block_host" | awk '{print $1}')
    else
        OLD_HASH=""
    fi
    NEW_HASH=$(md5sum "$NEW_FILE" | awk '{print $1}')

    if [ "$OLD_HASH" = "$NEW_HASH" ]; then
        rm -f "$NEW_FILE"
    else
		[ -s $NEW_FILE ] && {
			rm -f $RULES_PATH/block_host
			mv -f "$NEW_FILE" "$RULES_PATH/block_host"
			/etc/init.d/passwall reload > /dev/null 2>&1 &
		}
    fi
else
    echo "[ERROR] 没有成功解析任何文件"
    exit 1
fi

[ "$OLD_HASH" != "$NEW_HASH" ] && exit 0 || exit 2

