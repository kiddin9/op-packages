#!/bin/sh
# =============================================================================
# Hermes Agent LuCI 插件一键安装脚本
# 用法: sh -c "$(wget -qO- https://cdn.jsdelivr.net/gh/Boos4721/luci-app-hermes@main/scripts/install.sh)"
# =============================================================================
set -e

REPO="Boos4721/luci-app-hermes"
GITHUB_RELEASE="https://github.com/${REPO}/releases/latest/download"

_ok()   { echo "  [✓] $*"; }
_warn() { echo "  [!] $*"; }
_err()  { echo "  [✗] $*"; echo ""; exit 1; }

_download() {
    local url="$1" out="$2"
    if command -v wget >/dev/null 2>&1; then
        wget -q --no-check-certificate -O "$out" "$url" 2>/dev/null
    elif command -v curl >/dev/null 2>&1; then
        curl -fsSL --connect-timeout 15 -o "$out" "$url" 2>/dev/null
    else
        _err "未找到 wget 或 curl"
    fi
}

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║            Hermes Agent LuCI 插件一键安装                    ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# ── 检查环境 ──
[ -f /etc/openwrt_release ] || _err "仅支持 OpenWrt / ImmortalWrt 系统"
command -v opkg >/dev/null 2>&1 || _err "未找到 opkg，仅支持 OpenWrt 系统"

ARCH=$(uname -m)
DISTRIB=$(grep -o 'DISTRIB_DESCRIPTION="[^"]*"' /etc/openwrt_release 2>/dev/null | cut -d'"' -f2 || echo "OpenWrt")
_ok "系统: ${DISTRIB}"
_ok "架构: ${ARCH}"
echo ""

# ── 下载 ipk ──
IPK="/tmp/luci-app-hermes_$$.ipk"
_warn "正在下载 luci-app-hermes..."

# 主源：GitHub Releases
if ! _download "${GITHUB_RELEASE}/luci-app-hermes_all.ipk" "${IPK}"; then
    _warn "GitHub 下载失败，尝试备用源..."
    _download "https://github.com/${REPO}/releases/latest/download/luci-app-hermes_all.ipk" "${IPK}" || \
        _err "下载失败，请检查网络连接后重试"
fi

SIZE=$(wc -c < "${IPK}" 2>/dev/null || echo 0)
[ "${SIZE}" -gt 5000 ] || _err "下载文件无效 (${SIZE} 字节)，请稍后重试"
_ok "下载完成 ($(du -sh "${IPK}" 2>/dev/null | cut -f1))"

# ── 安装 ──
_warn "正在安装..."
opkg update >/dev/null 2>&1 || true

if ! opkg install --force-reinstall "${IPK}" 2>&1; then
    _warn "首次安装失败，尝试强制安装..."
    opkg install --force-reinstall --force-depends "${IPK}" || \
        _err "安装失败，请查看上方错误信息"
fi

rm -f "${IPK}"
rm -f /tmp/luci-indexcache 2>/dev/null || true
rm -rf /tmp/luci-modulecache 2>/dev/null || true

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  [OK] 安装完成！                                             ║"
echo "║                                                              ║"
echo "║  → LuCI → 服务 → Hermes Agent                               ║"
echo "║  → 点击「更多」→「安装环境」完成 Python + Hermes 安装       ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
