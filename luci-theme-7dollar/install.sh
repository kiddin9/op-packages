#!/bin/sh
# 7Dollar — one line installer for OpenWrt
#   wget -qO- https://raw.githubusercontent.com/itsmaiGe/luci-theme-7dollar/main/install.sh | sh
# Behind the GFW? put a GitHub proxy in front:
#   wget -qO- https://<proxy>/https://raw.githubusercontent.com/itsmaiGe/luci-theme-7dollar/main/install.sh | PROXY=https://<proxy>/ sh

REPO=itsmaiGe/luci-theme-7dollar
BRANCH=${BRANCH:-main}
P=${PROXY:-}
RAW="${P}https://raw.githubusercontent.com/$REPO/$BRANCH"
TMP=/tmp/7dollar.$$

say()  { printf '\033[38;5;173m●\033[0m %s\n' "$*"; }
die()  { printf '\033[31m✕ %s\033[0m\n' "$*"; rm -rf "$TMP"; exit 1; }
get()  {
	if command -v uclient-fetch >/dev/null 2>&1; then uclient-fetch -q -O "$2" "$1"
	elif command -v wget >/dev/null 2>&1; then wget -q -O "$2" "$1"
	elif command -v curl >/dev/null 2>&1; then curl -fsSL -o "$2" "$1"
	else return 1; fi
}

[ -f /etc/openwrt_release ] || die "这不是 OpenWrt 系统 / not OpenWrt"
[ -d /usr/share/ucode/luci ] || die "需要 OpenWrt 23.05 或更新版本 (ucode LuCI) / needs OpenWrt 23.05+"
mkdir -p "$TMP" || die "无法创建临时目录"

say "7Dollar 主题安装中…"

# opkg (OpenWrt 23.05 / 24.10) installs the .ipk, apk (OpenWrt 25.x) the .apk
if command -v opkg >/dev/null 2>&1; then LIST=latest.txt; else LIST=latest-apk.txt; fi
get "$RAW/dist/$LIST" "$TMP/latest" || die "下载失败，请检查网络，或设置 PROXY 后重试"
PKG=$(head -n1 "$TMP/latest" | tr -d '\r\n ')
VER=$(echo "$PKG" | sed -n 's/^luci-theme-7dollar[_-]\([0-9.]*\)-r.*/\1/p')
say "下载 $PKG"
# from the Release (counted as a download on GitHub); the copy in the repo is the fallback
get "${P}https://github.com/$REPO/releases/download/v$VER/$PKG" "$TMP/$PKG" || get "$RAW/dist/$PKG" "$TMP/$PKG" \
	|| die "下载失败，请检查网络，或设置 PROXY 后重试"
if [ "$LIST" = latest.txt ]; then
	opkg install --force-reinstall "$TMP/$PKG" || die "opkg 安装失败"
else
	apk add --allow-untrusted "$TMP/$PKG" || die "apk 安装失败"
fi

rm -rf "$TMP" /tmp/luci-indexcache* /tmp/luci-modulecache/
say "完成！刷新浏览器里的路由器后台即可看到 7Dollar。"
say "Done! Reload the router page in your browser."
