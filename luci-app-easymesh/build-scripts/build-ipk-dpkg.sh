#!/bin/bash
set -e

SRC="/home/zamimondol/easymesh-build/src/luci-app-easymesh"
OUT="/home/zamimondol/easymesh-build/output"
BUILD="/tmp/easymesh-ipk-dpkg"
PO2LMO="/home/zamimondol/easymesh-build/sdk-24.10/staging_dir/hostpkg/bin/po2lmo"

V="2.4.1-r1"
PKG="luci-app-easymesh"
I18N="luci-i18n-easymesh-zh-cn"
BASE_DEPS="libc, luci-base, luci-compat, luci-lua-runtime, libiwinfo-lua, kmod-cfg80211, kmod-batman-adv, luci-proto-batman-adv, batctl-default, usteer, luci-app-usteer"

mkdir -p "$OUT"
rm -rf "$BUILD"
mkdir -p "$BUILD"

build_ipk() {
    local NAME="$1" DATADIR="$2" DEPS="$3" DESC="$4"
    local WORK="$BUILD/$NAME"
    rm -rf "$WORK"
    mkdir -p "$WORK/DEBIAN"

    # Copy data files into deb root
    if [ -d "$DATADIR" ]; then
        cp -a "$DATADIR/." "$WORK/"
    fi
    rm -rf "$WORK/CONTROL" "$WORK/.git"

    # DEBIAN/control
    cat > "$WORK/DEBIAN/control" <<EOF
Package: $NAME
Version: $V
Depends: $DEPS
Architecture: all
Maintainer: Arafat Rahman Zami Mondol <arafatrahmanzami@users.noreply.github.com>
Section: luci
Priority: optional
Description: $DESC
EOF

    if [ "$NAME" = "$PKG" ]; then
        echo "/etc/config/easymesh" > "$WORK/DEBIAN/conffiles"
        cat > "$WORK/DEBIAN/postinst" <<'POST'
#!/bin/sh
[ -n "${IPKG_INSTROOT}" ] && exit 0
rm -f /tmp/luci-indexcache 2>/dev/null
/etc/init.d/rpcd restart 2>/dev/null
/etc/init.d/uhttpd restart 2>/dev/null
exit 0
POST
        chmod 0755 "$WORK/DEBIAN/postinst"
    fi

    # Build .deb (which IS an ar archive, same format as .ipk)
    rm -f "$OUT/${NAME}_${V}_all.ipk"
    dpkg-deb --build -Zgzip -z9 "$WORK" "$OUT/${NAME}_${V}_all.ipk" >/dev/null

    # Verify
    local MAGIC=$(head -c 8 "$OUT/${NAME}_${V}_all.ipk" | od -An -tx1 | tr -d ' \n')
    if [ "$MAGIC" = "213c617263683e0a" ]; then
        echo "  OK: $NAME ($(stat -c%s "$OUT/${NAME}_${V}_all.ipk") bytes)"
    else
        echo "  FAIL: $NAME — magic $MAGIC"
    fi
}

# Main package
MAIN_DATA="$BUILD/main-data"
mkdir -p "$MAIN_DATA/usr/lib/lua/luci"
cp -a "$SRC/luasrc/." "$MAIN_DATA/usr/lib/lua/luci/"
[ -d "$SRC/root" ] && cp -a "$SRC/root/." "$MAIN_DATA/"
find "$MAIN_DATA" -name '*.luadoc' -delete

echo "==> Main"
build_ipk "$PKG" "$MAIN_DATA" "$BASE_DEPS" \
    "LuCI Management Interface for EasyMesh (Batman-adv mesh)"

# Meta packages
for v in openssl wolfssl mbedtls; do
    echo "==> Meta $v"
    EMPTY="$BUILD/empty"
    rm -rf "$EMPTY"; mkdir -p "$EMPTY"
    build_ipk "luci-app-easymesh-wpad-$v" "$EMPTY" \
        "libc, $PKG, wpad-mesh-$v" \
        "EasyMesh meta — installs with wpad-mesh-$v"
done

# i18n
if [ -x "$PO2LMO" ] && [ -f "$SRC/po/zh_Hans/easymesh.po" ]; then
    echo "==> i18n"
    I18N_DATA="$BUILD/i18n-data"
    rm -rf "$I18N_DATA"
    mkdir -p "$I18N_DATA/usr/lib/lua/luci/i18n" "$I18N_DATA/etc/uci-defaults"
    "$PO2LMO" "$SRC/po/zh_Hans/easymesh.po" \
        "$I18N_DATA/usr/lib/lua/luci/i18n/easymesh.zh-cn.lmo"
    echo "uci set luci.languages.zh_cn='简体中文'; uci commit luci" \
        > "$I18N_DATA/etc/uci-defaults/luci-i18n-easymesh-zh-cn"
    build_ipk "$I18N" "$I18N_DATA" "libc, $PKG" "Chinese Simplified"
fi

echo ""
echo "==> Output:"
ls -lh "$OUT"/*.ipk
