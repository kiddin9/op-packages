#!/bin/sh
set -eu
root="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
stage="${1:?usage: stage-package.sh STAGE_DIR}"
. "$root/release.env"
rm -rf "$stage"
mkdir -p "$stage/CONTROL" "$stage/usr/share/rpcd/acl.d" \
  "$stage/usr/share/licenses/$PKG_NAME" \
  "$stage/www/luci-static/resources/wrqr" \
  "$stage/www/luci-static/resources/view/status/include"
install -m 644 "$root/luci/acl.json" "$stage/usr/share/rpcd/acl.d/$PKG_NAME.json"
install -m 644 "$root/luci/shared.js" "$stage/www/luci-static/resources/wrqr/shared.js"
install -m 644 "$root/luci/overview.js" "$stage/www/luci-static/resources/view/status/include/15_wifi-qr.js"
install -m 644 "$root/LICENSE" "$stage/usr/share/licenses/$PKG_NAME/LICENSE"
cat >"$stage/CONTROL/control" <<EOF
Package: $PKG_NAME
Version: $PKG_VERSION
Architecture: $PKG_ARCH
Maintainer: nikitid
Depends: luci-base, luci-lib-uqr
Section: luci
Priority: optional
Description: Display active Wi-Fi access point QR codes on LuCI Status Overview.
EOF
cat >"$stage/CONTROL/postinst" <<'EOF'
#!/bin/sh
[ -n "${IPKG_INSTROOT:-}" ] && exit 0
rm -f /tmp/luci-indexcache
rm -rf /tmp/luci-modulecache
exit 0
EOF
cat >"$stage/CONTROL/prerm" <<'EOF'
#!/bin/sh
[ -n "${IPKG_INSTROOT:-}" ] && exit 0
case "${1:-}" in upgrade) exit 0 ;; esac
[ "${PKG_UPGRADE:-0}" = 1 ] && exit 0
rm -f /tmp/luci-indexcache
rm -rf /tmp/luci-modulecache
exit 0
EOF
chmod 755 "$stage/CONTROL/postinst" "$stage/CONTROL/prerm"
