#!/bin/sh
# Lay out the installed file tree of luci-theme-7dollar in $1 (shared by build-ipk.sh and build-apk.sh).
# JS and CSS are minified on the way (what the OpenWrt buildroot does for LuCI itself); the sources in
# the repo stay readable. MINIFY=0 skips it.
set -eu
cd "$(dirname "$0")/.."
D=$1
mkdir -p "$D/www" "$D/usr/share/ucode/luci"
cp -R htdocs/. "$D/www/"
cp -R ucode/. "$D/usr/share/ucode/luci/"
cp -R root/. "$D/"
find "$D" -name .DS_Store -exec rm {} +
[ "${MINIFY:-1}" = 0 ] || npx -y esbuild@0.28.2 $(find "$D/www" -name '*.js' -o -name '*.css') \
	--minify --charset=utf8 --target=esnext --log-level=warning --allow-overwrite --outbase="$D/www" --outdir="$D/www"
find "$D" -type d -exec chmod 755 {} +
find "$D" -type f -exec chmod 644 {} +
chmod 755 "$D"/etc/uci-defaults/*
