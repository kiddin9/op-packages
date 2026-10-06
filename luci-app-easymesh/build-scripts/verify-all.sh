#!/bin/bash
# Verify all EasyMesh build artifacts before shipping

OUT="/home/zamimondol/easymesh-build/output"
PKG="/home/zamimondol/easymesh-build/easymesh-pkg"
BUNDLE="/home/zamimondol/easymesh-build/easymesh-pkg-2.4.1-r1.tar.gz"
SRC="/home/zamimondol/easymesh-build/src/luci-app-easymesh"
V="2.4.1-r1"

PASS=0
FAIL=0

check() {
    local label="$1" result="$2"
    if [ "$result" = "0" ]; then
        echo "  [PASS] $label"
        PASS=$((PASS+1))
    else
        echo "  [FAIL] $label"
        FAIL=$((FAIL+1))
    fi
}

section() { echo ""; echo "=== $1 ==="; }

TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT

# ============================================================
section "1. Source tree"
# ============================================================
[ -f "$SRC/Makefile" ]
check "Makefile exists" $?

[ -f "$SRC/luasrc/model/cbi/easymesh.lua" ]
check "CBI model exists" $?

[ -f "$SRC/luasrc/controller/easymesh.lua" ]
check "Controller exists" $?

[ -f "$SRC/root/etc/init.d/easymesh" ]
check "Init script exists" $?

[ -f "$SRC/root/etc/config/easymesh" ]
check "Config file exists" $?

[ -f "$SRC/root/etc/rc.wps/easymesh-pair" ]
check "WPS handler (rc.wps) exists" $?

[ ! -d "$SRC/root/etc/rc.button" ]
check "No rc.button dir (no conflict)" $?

[ -f "$SRC/root/etc/uci-defaults/luci-easymesh" ]
check "UCI-defaults exists" $?

grep -q "PKG_VERSION:=2.4.1" "$SRC/Makefile"
check "Version is 2.4.1" $?

grep -q "PKG_RELEASE:=1" "$SRC/Makefile"
check "Release is 1" $?

grep -q "LUCI_PKGARCH:=all" "$SRC/Makefile"
check "PKGARCH=all (universal)" $?

! grep -q "+wpad-mesh" "$SRC/Makefile"
check "No wpad dep in Makefile" $?

! grep -qE "uci set.*='.*'" "$SRC/root/etc/init.d/easymesh"
check "No escaped quotes in init script" $?

lua5.3 -e "assert(loadfile('$SRC/luasrc/model/cbi/easymesh.lua'))" 2>/dev/null
check "CBI Lua syntax valid" $?

sh -n "$SRC/root/etc/init.d/easymesh"
check "Init script syntax valid" $?

# ============================================================
section "2. IPK files"
# ============================================================
for p in luci-app-easymesh luci-app-easymesh-wpad-openssl \
         luci-app-easymesh-wpad-wolfssl luci-app-easymesh-wpad-mbedtls \
         luci-i18n-easymesh-zh-cn
do
    F="$OUT/${p}_${V}_all.ipk"
    [ -f "$F" ]
    check "IPK present: $(basename $F)" $?
done

# Verify main IPK contents
D="$TMP/ipk"; mkdir -p "$D"; cd "$D"
if ar x "$OUT/luci-app-easymesh_${V}_all.ipk" 2>/dev/null; then
    check "Main IPK is valid ar archive" 0

    tar xzf control.tar.gz 2>/dev/null
    grep -q "Package: luci-app-easymesh" control
    check "Main IPK control: package name" $?
    grep -q "Version: 2.4.1-r1" control
    check "Main IPK control: version" $?
    grep -q "Architecture: all" control
    check "Main IPK control: arch=all" $?
    grep -q "Depends:.*kmod-batman-adv" control
    check "Main IPK control: has batman dep" $?
    ! grep -q "Depends:.*wpad-mesh" control
    check "Main IPK control: no wpad dep" $?

    tar tzf data.tar.gz | grep -q "etc/rc.wps/easymesh-pair"
    check "Main IPK data: rc.wps handler present" $?
    ! tar tzf data.tar.gz | grep -q "etc/rc.button/wps"
    check "Main IPK data: no rc.button conflict" $?
    tar tzf data.tar.gz | grep -q "etc/init.d/easymesh"
    check "Main IPK data: init.d present" $?
    tar tzf data.tar.gz | grep -q "usr/lib/lua/luci/model/cbi/easymesh.lua"
    check "Main IPK data: CBI present" $?
else
    check "Main IPK is valid ar archive" 1
fi
cd "$TMP"

# Verify a meta IPK
D="$TMP/meta"; mkdir -p "$D"; cd "$D"
if ar x "$OUT/luci-app-easymesh-wpad-wolfssl_${V}_all.ipk" 2>/dev/null; then
    tar xzf control.tar.gz 2>/dev/null
    grep -q "Package: luci-app-easymesh-wpad-wolfssl" control
    check "Wolfssl meta: correct name" $?
    grep -q "Depends:.*wpad-mesh-wolfssl" control
    check "Wolfssl meta: depends on wolfssl" $?
    grep -q "Depends:.*luci-app-easymesh" control
    check "Wolfssl meta: depends on main" $?
fi
cd "$TMP"

# ============================================================
section "3. APK files"
# ============================================================
for p in luci-app-easymesh luci-app-easymesh-wpad-openssl \
         luci-app-easymesh-wpad-wolfssl luci-app-easymesh-wpad-mbedtls \
         luci-i18n-easymesh-zh-cn
do
    F="$OUT/${p}-${V}.apk"
    [ -f "$F" ]
    check "APK present: $(basename $F)" $?

    if [ -f "$F" ]; then
        MAGIC=$(head -c 4 "$F" 2>/dev/null | od -An -tx1 | tr -d ' \n')
        [ "$MAGIC" = "41444264" ]
        check "  magic bytes ADBd: $(basename $F)" $?
    fi
done

# ============================================================
section "4. Tarballs"
# ============================================================
for t in luci-app-easymesh-${V}-all.tar.gz \
         luci-app-easymesh-${V}-full.tar.gz \
         luci-i18n-easymesh-zh-cn-${V}-all.tar.gz
do
    F="$OUT/$t"
    [ -f "$F" ]
    check "Tarball present: $t" $?

    if [ -f "$F" ]; then
        tar tzf "$F" >/dev/null 2>&1
        check "  tarball valid: $t" $?
    fi
done

# Verify full tarball contains the right paths
tar tzf "$OUT/luci-app-easymesh-${V}-full.tar.gz" 2>/dev/null | grep -q "etc/rc.wps/easymesh-pair"
check "Full tarball: rc.wps present" $?
tar tzf "$OUT/luci-app-easymesh-${V}-full.tar.gz" 2>/dev/null | grep -q "etc/init.d/easymesh"
check "Full tarball: init.d present" $?

# ============================================================
section "5. Bundle folder"
# ============================================================
[ -d "$PKG" ]
check "Bundle folder exists" $?

[ -f "$PKG/MANIFEST.txt" ]
check "MANIFEST.txt present" $?

[ -f "$PKG/ipk/luci-app-easymesh_${V}_all.ipk" ]
check "Bundle has main IPK" $?

[ -f "$PKG/apk/luci-app-easymesh-${V}.apk" ]
check "Bundle has main APK" $?

[ -f "$PKG/meta-packages/luci-app-easymesh/Makefile" ]
check "Bundle has source" $?

[ -f "$PKG/meta-packages/wpad-openssl/Makefile" ]
check "Bundle has openssl meta Makefile" $?

[ -f "$PKG/meta-packages/wpad-wolfssl/Makefile" ]
check "Bundle has wolfssl meta Makefile" $?

[ -f "$PKG/meta-packages/wpad-mbedtls/Makefile" ]
check "Bundle has mbedtls meta Makefile" $?

[ -f "$BUNDLE" ]
check "Bundle tarball exists" $?

if [ -f "$BUNDLE" ]; then
    tar tzf "$BUNDLE" >/dev/null 2>&1
    check "Bundle tarball valid" $?
fi

# ============================================================
echo ""
echo "============================================================"
echo "RESULT: $PASS passed, $FAIL failed"
echo "============================================================"

[ $FAIL -eq 0 ] && exit 0 || exit 1
