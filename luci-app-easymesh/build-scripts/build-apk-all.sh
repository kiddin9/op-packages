#!/bin/bash
set -e

SRC="/home/zamimondol/easymesh-build/src/luci-app-easymesh"
OUT="/home/zamimondol/easymesh-build/output"
BUILD="/tmp/easymesh-apk"
APK="/home/zamimondol/easymesh-build/sdk-25.12/staging_dir/host/bin/apk"
PO2LMO="/home/zamimondol/easymesh-build/sdk-24.10/staging_dir/hostpkg/bin/po2lmo"

VERSION="2.4.1-r1"

BASE_DEPS="libc luci-base luci-compat luci-lua-runtime libiwinfo-lua kmod-cfg80211 kmod-batman-adv luci-proto-batman-adv batctl-default usteer luci-app-usteer"

mkdir -p "$OUT"
rm -rf "$BUILD"
mkdir -p "$BUILD"

stage_main() {
    local DEST="$1"
    mkdir -p "$DEST/usr/lib/lua/luci"
    cp -a "$SRC/luasrc/." "$DEST/usr/lib/lua/luci/"
    [ -d "$SRC/htdocs" ] && { mkdir -p "$DEST/www"; cp -a "$SRC/htdocs/." "$DEST/www/"; }
    [ -d "$SRC/root" ]   && cp -a "$SRC/root/." "$DEST/"
    find "$DEST" -name '*.luadoc' -delete
}

build_apk() {
    local NAME="$1" DIR="$2" DEPS="$3" DESC="$4"
    local OUTFILE="$OUT/${NAME}-${VERSION}.apk"
    rm -f "$OUTFILE"
    SOURCE_DATE_EPOCH=0 "$APK" mkpkg \
        --info "name:$NAME" \
        --info "version:$VERSION" \
        --info "arch:noarch" \
        --info "description:$DESC" \
        --info "maintainer:Arafat Rahman Zami Mondol <arafatrahmanzami@users.noreply.github.com>" \
        --info "depends:$DEPS" \
        --info "origin:luci-app-easymesh" \
        --files "$DIR" \
        --output "$OUTFILE"
    local MAGIC=$(head -c 4 "$OUTFILE" | od -An -tx1 | tr -d ' \n')
    [ "$MAGIC" = "41444264" ] && echo "    OK: $NAME" || echo "    WARN: $NAME"
}

echo "==> Building APK variants"

# Main (no wpad)
MAIN="$BUILD/main"
mkdir -p "$MAIN"
stage_main "$MAIN"
build_apk "luci-app-easymesh" "$MAIN" "$BASE_DEPS" \
    "LuCI Management Interface for EasyMesh (Batman-adv mesh)"

# Meta variants (empty package with just a wpad dep)
for v in openssl wolfssl mbedtls; do
    M="$BUILD/meta-$v"
    mkdir -p "$M"
    build_apk "luci-app-easymesh-wpad-$v" "$M" \
        "luci-app-easymesh wpad-mesh-$v" \
        "EasyMesh meta-package — installs with wpad-mesh-$v"
done

# i18n
if [ -x "$PO2LMO" ] && [ -f "$SRC/po/zh_Hans/easymesh.po" ]; then
    I18N="$BUILD/i18n"
    mkdir -p "$I18N/usr/lib/lua/luci/i18n" "$I18N/etc/uci-defaults"
    "$PO2LMO" "$SRC/po/zh_Hans/easymesh.po" \
        "$I18N/usr/lib/lua/luci/i18n/easymesh.zh-cn.lmo"
    echo "uci set luci.languages.zh_cn='简体中文'; uci commit luci" \
        > "$I18N/etc/uci-defaults/luci-i18n-easymesh-zh-cn"
    build_apk "luci-i18n-easymesh-zh-cn" "$I18N" "libc luci-app-easymesh" \
        "Chinese Simplified translation for luci-app-easymesh"
fi

echo ""
echo "============================================================"
ls -lh "$OUT"/*.apk
