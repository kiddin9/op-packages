#!/bin/bash
# Create wpad meta-package APKs (OpenWrt 25.12+ apk format)
set -e

OUT="${1:-/home/zamimondol/easymesh-build/output}"
V="2.4.1-r1"
PKG="luci-app-easymesh"
MAINTAINER="Arafat Rahman Zami Mondol <arafatrahmanzami@users.noreply.github.com>"
APK="/home/zamimondol/easymesh-build/sdk-25.12-fresh/staging_dir/host/bin/apk"

if [ ! -x "$APK" ]; then
    echo "ERROR: apk tool not found at $APK"
    exit 1
fi

mkdir -p "$OUT"

create_meta_apk() {
    local NAME="$1" DEPS="$2" DESC="$3"
    local EMPTY="/tmp/meta-apk-empty"
    rm -rf "$EMPTY"
    mkdir -p "$EMPTY"

    rm -f "$OUT/${NAME}-${V}.apk"

    SOURCE_DATE_EPOCH=0 "$APK" mkpkg \
        --info "name:$NAME" \
        --info "version:$V" \
        --info "arch:noarch" \
        --info "description:$DESC" \
        --info "maintainer:$MAINTAINER" \
        --info "depends:libc $PKG $DEPS" \
        --info "origin:luci-app-easymesh" \
        --files "$EMPTY" \
        --output "$OUT/${NAME}-${V}.apk" 2>&1 | tail -2

    rm -rf "$EMPTY"

    local SIZE=$(stat -c%s "$OUT/${NAME}-${V}.apk" 2>/dev/null || echo 0)
    local MAGIC=$(head -c 4 "$OUT/${NAME}-${V}.apk" 2>/dev/null | od -An -tx1 | tr -d ' \n')

    if [ "$MAGIC" = "41444264" ]; then
        echo "  OK: $NAME (${SIZE} bytes, ADBd magic)"
    else
        echo "  FAIL: $NAME (magic=$MAGIC)"
    fi
}

echo "==> Creating wpad MESH meta APKs"
create_meta_apk "luci-app-easymesh-wpad-openssl" \
    "wpad-mesh-openssl" \
    "EasyMesh meta - installs with wpad-mesh-openssl (default OpenWrt)"

create_meta_apk "luci-app-easymesh-wpad-wolfssl" \
    "wpad-mesh-wolfssl" \
    "EasyMesh meta - installs with wpad-mesh-wolfssl (ImmortalWrt default)"

create_meta_apk "luci-app-easymesh-wpad-mbedtls" \
    "wpad-mesh-mbedtls" \
    "EasyMesh meta - installs with wpad-mesh-mbedtls (lightweight)"

echo ""
ls -lh "$OUT"/luci-app-easymesh-wpad-*.apk
