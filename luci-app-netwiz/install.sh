#!/bin/sh

echo "🚀 开始极速安装/升级/修复 NetWiz"

# ==========================================
# 0. 环境初始化与版本识别
# ==========================================
PKG_TYPE="ipk"
if command -v apk >/dev/null 2>&1; then
    PKG_TYPE="apk"
elif command -v opkg >/dev/null 2>&1; then
    PKG_TYPE="ipk"
else
    echo "❌ 找不到支持的软件包管理器 (未找到 apk 或 opkg)！"
    exit 1
fi

# 函数：获取当前系统中已安装的版本
get_installed_version() {
    if [ "$PKG_TYPE" = "apk" ]; then
        apk info -v 2>/dev/null | grep -E "^luci-app-netwiz-[0-9]" | head -n 1 | sed 's/^luci-app-netwiz-//'
    else
        opkg status luci-app-netwiz 2>/dev/null | grep -i "^Version:" | awk '{print $2}'
    fi
}

# 函数：透视获取本地保险箱中安装包的版本
get_local_version() {
    local file="$1"
    local ver=""
    
    if [ "$PKG_TYPE" = "apk" ]; then
        # 1. 尝试直接跨流提取 .PKGINFO
        ver=$(tar -Ozxf "$file" .PKGINFO 2>/dev/null | grep "^pkgver =" | cut -d'=' -f2 | tr -d ' ')
        # 2. 核心修复：如果由于多段 gzip 拼接导致 tar 失败，利用 zcat 暴力读取压缩流明文
        [ -z "$ver" ] && ver=$(zcat "$file" 2>/dev/null | grep -a -m 1 "^pkgver =" | cut -d'=' -f2 | tr -d ' ')
        # 3. 终极穿透：利用 strings 强制提取二进制文件中的可见版本字符
        [ -z "$ver" ] && ver=$(strings "$file" 2>/dev/null | grep -m 1 "^pkgver =" | cut -d'=' -f2 | tr -d ' ')
    else
        # ipk 架构的提取非常稳定
        ver=$(tar -Ozxf "$file" ./control.tar.gz 2>/dev/null | tar -Ozxf - ./control 2>/dev/null | grep -i "^Version:" | awk '{print $2}')
    fi
    
    # 4. 从文件名兜底提取
    [ -z "$ver" ] && ver=$(basename "$file" | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?(-r[0-9]+)?' | head -n 1)
    
    echo "$ver"
}

# 函数：版本对比算法
version_ge() {
    awk -v v1="$1" -v v2="$2" '
    function split_ver(v, a) {
        gsub(/^[vV]/, "", v); gsub(/-.*/, "", v);
        return split(v, a, ".");
    }
    BEGIN {
        if (v1 == "" && v2 == "") exit 0;
        if (v1 == "") exit 1;
        if (v2 == "") exit 0;
        n1 = split_ver(v1, a1); n2 = split_ver(v2, a2);
        max = (n1 > n2) ? n1 : n2;
        for (i=1; i<=max; i++) {
            if (a1[i]+0 > a2[i]+0) exit 0;
            if (a1[i]+0 < a2[i]+0) exit 1;
        }
        exit 0;
    }'
}

INSTALLED_VER=$(get_installed_version)
echo "🔍 当前系统架构: $PKG_TYPE"
echo "📦 当前运行版本: ${INSTALLED_VER:-未安装 (或已被精简)}"

# ==========================================
# 1. 备份脚本自身，确保离线可用
# ==========================================
mkdir -p /etc/netwiz/custom_pkgs/
cp -f "$0" /etc/netwiz/custom_pkgs/install.sh 2>/dev/null

# ==========================================
# 2. 尝试从云端拉取最新版 (高透明度探测)
# ==========================================
echo "⬇️ 正在从云端尝试获取最新版本..."
FILES="luci-app-netwiz luci-i18n-netwiz-zh-cn luci-i18n-netwiz-zh-tw"
DOWNLOAD_SUCCESS=0

for FILE in $FILES; do
    TARGET_FILE="${PKG_TYPE}_${FILE}.${PKG_TYPE}"
    URL_DIRECT="https://github.com/huchd0/luci-app-netwiz/releases/latest/download/${TARGET_FILE}"
    
    PROXY_1="https://mirror.ghproxy.com/${URL_DIRECT}"
    PROXY_2="https://ghfast.top/${URL_DIRECT}"
    PROXY_3="https://ghp.ci/${URL_DIRECT}"

    echo -n "正在拉取: ${TARGET_FILE} ... "
    
    # 尝试 1：官方直连 (仅等待 5 秒)
    wget -qO "/tmp/${TARGET_FILE}" --no-check-certificate -T 5 "$URL_DIRECT"
    if [ "$?" -eq 0 ] && [ -s "/tmp/${TARGET_FILE}" ]; then
        DOWNLOAD_SUCCESS=$((DOWNLOAD_SUCCESS + 1))
        echo "👉 👉 👉 [官方直连] 成功！✅✅✅"
        continue
    fi
    
    # 尝试 2：代理节点 1
    wget -qO "/tmp/${TARGET_FILE}" --no-check-certificate -T 5 "$PROXY_1"
    if [ "$?" -eq 0 ] && [ -s "/tmp/${TARGET_FILE}" ]; then
        DOWNLOAD_SUCCESS=$((DOWNLOAD_SUCCESS + 1))
        echo "👉 👉 👉 [加速节点1] 成功！✅✅✅"
        continue
    fi

    # 尝试 3：代理节点 2
    wget -qO "/tmp/${TARGET_FILE}" --no-check-certificate -T 5 "$PROXY_2"
    if [ "$?" -eq 0 ] && [ -s "/tmp/${TARGET_FILE}" ]; then
        DOWNLOAD_SUCCESS=$((DOWNLOAD_SUCCESS + 1))
        echo "👉 👉 👉 [加速节点2] 成功！✅✅✅"
        continue
    fi
    
    # 尝试 4：代理节点 3
    wget -qO "/tmp/${TARGET_FILE}" --no-check-certificate -T 5 "$PROXY_3"
    if [ "$?" -eq 0 ] && [ -s "/tmp/${TARGET_FILE}" ]; then
        DOWNLOAD_SUCCESS=$((DOWNLOAD_SUCCESS + 1))
        echo "👉 👉 👉 [加速节点3] 成功！✅✅✅"
        continue
    fi

    echo "❌ 所有节点均失败！"
done

# ==========================================
# 3. 云端全新安装 vs 离线智能对比
# ==========================================
if [ "$DOWNLOAD_SUCCESS" -eq 3 ]; then
    echo "🌐 云端下载完整！正在覆盖至本地保险箱..."
    for FILE in $FILES; do
        TARGET_FILE="${PKG_TYPE}_${FILE}.${PKG_TYPE}"
        mv -f "/tmp/${TARGET_FILE}" "/etc/netwiz/custom_pkgs/${TARGET_FILE}"
    done
    echo "👉 准备执行全新安装/升级！"
else
    echo "⚠️ 云端连接失败或文件不完整，转入【离线恢复模式】！"
    echo "🔍 正在检查本地保险箱状态..."
    
    LOCAL_MAIN=$(ls /etc/netwiz/custom_pkgs/*luci-app-netwiz*.${PKG_TYPE} 2>/dev/null | head -n 1)
    if [ -n "$LOCAL_MAIN" ] && [ -f "$LOCAL_MAIN" ]; then
        LOCAL_VER=$(get_local_version "$LOCAL_MAIN")
        echo "📦 发现本地储备版本: ${LOCAL_VER:-未知}"
        
        # 双向对比机制
        if [ -n "$INSTALLED_VER" ] && [ -n "$LOCAL_VER" ]; then
            if version_ge "$LOCAL_VER" "$INSTALLED_VER"; then
                echo "✅ 本地储备版 ($LOCAL_VER) >= 当前运行版 ($INSTALLED_VER)，允许覆盖恢复！"
            else
                echo "🚫 智能拦截：本地储备版 ($LOCAL_VER) 低于当前运行版 ($INSTALLED_VER)！"
                echo "💡 为保护系统，无需进行降级安装，已自动安全退出。"
                exit 0
            fi
        elif [ -n "$INSTALLED_VER" ] && [ -z "$LOCAL_VER" ]; then
            echo "⚠️ 无法准确识别本地包版本，默认放行执行覆盖安装以尝试修复系统！"
        else
            echo "✅ 系统核心未挂载，允许执行离线急救部署！"
        fi
    else
        echo "❌ 致命错误：云端下载失败，且本地保险箱无可用急救包！"
        exit 1
    fi
fi

# ==========================================
# 4. 卸载旧版并注入新版
# ==========================================
echo "🧹 正在清理系统旧版本残留..."
if [ "$PKG_TYPE" = "apk" ]; then
    apk del luci-app-netwiz luci-i18n-netwiz-zh-cn luci-i18n-netwiz-zh-tw >/dev/null 2>&1
else
    opkg remove luci-app-netwiz luci-i18n-netwiz-zh-cn luci-i18n-netwiz-zh-tw --force-remove >/dev/null 2>&1
fi

echo "⚙️ 正在执行批量注入安装..."
if [ "$PKG_TYPE" = "apk" ]; then
    apk add --allow-untrusted --force-overwrite /etc/netwiz/custom_pkgs/*luci-*netwiz*.apk 2>/dev/null
else
    opkg install /etc/netwiz/custom_pkgs/*luci-*netwiz*.ipk --force-reinstall --force-overwrite 2>/dev/null
fi

# ==========================================
# 5. 重建缓存与唤醒服务
# ==========================================
echo "🔄 正在重建 LuCI 缓存并唤醒服务..."
# 1. 清空所有 LuCI 缓存
rm -rf /tmp/luci-indexcache* /tmp/luci-modulecache* /var/run/luci-indexcache* /var/run/luci-modulecache* 2>/dev/null
rm -rf /tmp/luci-sessions/* /var/run/luci-sessions/* 2>/dev/null

# 2. 重启 rpcd，确保后端的 netwiz 脚本被正确加载入内核
/etc/init.d/rpcd restart 2>/dev/null

# 3. 智能重启 Web 服务
if [ -f "/etc/init.d/uhttpd" ]; then
    /etc/init.d/uhttpd restart 2>/dev/null
elif [ -f "/etc/init.d/nginx" ]; then
    /etc/init.d/nginx restart 2>/dev/null
fi

echo -e "\n👉 👉 👉 🎉 NetWiz 核心程序部署完成！✅✅✅"
echo -e "💡 登录状态已安全重置，请返回浏览器按下 【F5】 刷新即可看到新菜单！"

# 6. 匿名安装量统计
(
    if [ -f /etc/openwrt_release ]; then
        . /etc/openwrt_release
        OW_VER=${DISTRIB_RELEASE:-"unknown"}
        OW_ARCH=${DISTRIB_TARGET:-"unknown"}
    else
        OW_VER="unknown"
        OW_ARCH=$(uname -m 2>/dev/null || echo "unknown")
    fi
    API_URL="https://netwiz-tracker.vercel.app/api/track"
    REQ_URL="${API_URL}?app=netwiz&ver=${OW_VER}&arch=${OW_ARCH}"
    
    if command -v curl >/dev/null 2>&1; then
        curl -s -m 3 "$REQ_URL" >/dev/null 2>&1
    else
        wget -qO- -T 3 "$REQ_URL" >/dev/null 2>&1
    fi
) &

exit 0
