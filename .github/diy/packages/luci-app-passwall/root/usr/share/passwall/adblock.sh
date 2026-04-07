#!/bin/sh
# OpenWrt Passwall 广告域名列表下载与合并脚本

LOCK_FILE="/var/lock/ad_download.lock"
TMP_DIR="/tmp/ad_download"
RULES_PATH="/usr/share/passwall/rules"

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
        if ($0 ~ /^#/ || $0 == "") next

        # 前20行探测格式
        if (sample_count < 20) {
            sample_count++
            if (fmt == "" && $0 ~ /^address=\/[^\/]+\//)      fmt = "dnsmasq"
            if (fmt == "" && $0 ~ /^DOMAIN-SUFFIX,/)          fmt = "clash"
            if (fmt == "" && $0 ~ /^[a-zA-Z0-9]([a-zA-Z0-9\-]*[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]*[a-zA-Z0-9])?)+$/)
                fmt = "plain"
        }

        # 按格式提取域名
        if (fmt == "dnsmasq") {
            # 匹配 address=/domain/ 和 address=/domain/0.0.0.0 等
            n = split($0, a, "/")
            if (n >= 3 && a[1] == "address=") print a[2]
        } else if (fmt == "clash") {
            if (sub(/^DOMAIN-SUFFIX,/, "")) print
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
    process_url "$INDEX" "$url" &
done

# 等待所有后台任务完成
wait

# ========== 合并、去重、去空行 ==========
if ls "$TMP_DIR"/parsed_*.txt >/dev/null 2>&1; then
    awk '!seen[$0]++ && NF' "$TMP_DIR"/parsed_*.txt > $RULES_PATH/ads_host
    COUNT=$(wc -l < "$RULES_PATH/ads_host")
    echo "========================================"
    echo "[DONE] 合并完成: $RULES_PATH/ads_host"
    echo "[DONE] 总域名数: $COUNT"
    echo "========================================"
else
    echo "[ERROR] 没有成功解析任何文件"
    exit 1
fi

[ -s $RULES_PATH/ads_host ] && {
[ -s $RULES_PATH/my_block_host ] && {
rm -f $RULES_PATH/block_host
awk '!/^[[:space:]]*(#|$)/ && !seen[$0]++' $RULES_PATH/ads_host $RULES_PATH/my_block_host > $RULES_PATH/block_host
} || ln -sf $RULES_PATH/ads_host $RULES_PATH/block_host
}

/etc/init.d/passwall reload > /dev/null 2>&1 &

exit 0
