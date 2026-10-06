#!/bin/bash
set -e
OUT="/home/zamimondol/easymesh-build/output"
PKG="/home/zamimondol/easymesh-build/easymesh-pkg"
SRC="/home/zamimondol/easymesh-build/src/luci-app-easymesh"
META="/home/zamimondol/easymesh-build/meta-packages"
V="2.4.1-r1"

rm -rf "$PKG"
mkdir -p "$PKG"/{ipk,apk,tarballs,meta-packages/luci-app-easymesh,meta-packages/wpad-openssl,meta-packages/wpad-wolfssl,meta-packages/wpad-mbedtls}

# Source
cp -a "$SRC/." "$PKG/meta-packages/luci-app-easymesh/"
rm -rf "$PKG/meta-packages/luci-app-easymesh/.git"
cp "$META/openssl/Makefile" "$PKG/meta-packages/wpad-openssl/"
cp "$META/wolfssl/Makefile" "$PKG/meta-packages/wpad-wolfssl/"
cp "$META/mbedtls/Makefile" "$PKG/meta-packages/wpad-mbedtls/"

# IPKs
cp -v "$OUT"/luci-app-easymesh_${V}_all.ipk              "$PKG/ipk/"
cp -v "$OUT"/luci-app-easymesh-wpad-openssl_${V}_all.ipk "$PKG/ipk/"
cp -v "$OUT"/luci-app-easymesh-wpad-wolfssl_${V}_all.ipk "$PKG/ipk/"
cp -v "$OUT"/luci-app-easymesh-wpad-mbedtls_${V}_all.ipk "$PKG/ipk/"
find "$OUT" -name "luci-i18n-easymesh-zh-cn_*_all.ipk" -exec cp {} "$PKG/ipk/" \;

# APKs
cp -v "$OUT"/luci-app-easymesh-${V}.apk              "$PKG/apk/"
cp -v "$OUT"/luci-app-easymesh-wpad-openssl-${V}.apk "$PKG/apk/"
cp -v "$OUT"/luci-app-easymesh-wpad-wolfssl-${V}.apk "$PKG/apk/"
cp -v "$OUT"/luci-app-easymesh-wpad-mbedtls-${V}.apk "$PKG/apk/"
find "$OUT" -name "luci-i18n-easymesh-zh-cn-*_all.apk" -exec cp {} "$PKG/apk/" \;

# Tarballs
find "$OUT" -name "luci-app-easymesh-${V}-*.tar.gz" -exec cp {} "$PKG/tarballs/" \;

cat > "$PKG/MANIFEST.txt" <<EOF
EasyMesh $V — Package Bundle
Generated: $(date)

Pick ONE of the following for your router:

A) Fresh install, want auto wpad selection
   OpenWrt 24.10 (opkg):
     opkg install ipk/luci-app-easymesh_${V}_all.ipk
     opkg install ipk/luci-app-easymesh-wpad-openssl_${V}_all.ipk
   OpenWrt 25.12 (apk):
     apk add --allow-untrusted apk/luci-app-easymesh-${V}.apk
     apk add --allow-untrusted apk/luci-app-easymesh-wpad-openssl-${V}.apk

B) Already have wpad-mesh-wolfssl (ImmortalWrt default)
     Use wpad-wolfssl variant instead

C) Already have wpad-mesh-mbedtls (lightweight builds)
     Use wpad-mbedtls variant instead

D) Any OpenWrt, any wpad already installed
     opkg install ipk/luci-app-easymesh_${V}_all.ipk
     (no wpad meta needed)

E) Tarball install (any OpenWrt)
     scp tarballs/luci-app-easymesh-${V}-full.tar.gz root@router:/tmp/
     ssh root@router
     cd /
     tar xzf /tmp/luci-app-easymesh-${V}-full.tar.gz
     chmod +x /etc/init.d/easymesh
     rm -f /tmp/luci-indexcache
     /etc/init.d/rpcd restart
     /etc/init.d/uhttpd restart
     (Installs the app. Install your wpad variant separately.)

Credits:
  Original: torguardvpn/luci-app-easymesh
  Fixes:    mobing8/luci-app-easymesh-dawn
  This build: Arafat Rahman Zami Mondol
EOF

echo "Bundle ready: $PKG"
du -sh "$PKG"/*
