#!/bin/sh

set -eu

root="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
stage="${1:?usage: stage-package.sh STAGE_DIR}"
. "$root/release.env"

rm -rf "$stage"
mkdir -p \
  "$stage/CONTROL" \
  "$stage/etc/config" \
  "$stage/etc/uci-defaults" \
  "$stage/usr/libexec" \
  "$stage/usr/share/luci/menu.d" \
  "$stage/usr/share/rpcd/acl.d" \
  "$stage/usr/share/licenses/$PKG_NAME" \
  "$stage/usr/lib/lua/luci/i18n" \
  "$stage/www/luci-static/resources/overview-manager" \
  "$stage/www/luci-static/resources/view/overview-manager" \
  "$stage/www/luci-static/resources/view/status/include"

install -m 600 "$root/openwrt/files/etc/config/overview-manager" \
  "$stage/etc/config/overview-manager"
install -m 755 "$root/runtime/overview-manager.sh" \
  "$stage/usr/libexec/overview-manager"
install -m 755 "$root/openwrt/files/etc/uci-defaults/luci-app-overview-manager" \
  "$stage/etc/uci-defaults/luci-app-overview-manager"
install -m 644 "$root/luci/menu.json" \
  "$stage/usr/share/luci/menu.d/$PKG_NAME.json"
install -m 644 "$root/luci/acl.json" \
  "$stage/usr/share/rpcd/acl.d/$PKG_NAME.json"
install -m 644 "$root/luci/shared.js" \
  "$stage/www/luci-static/resources/overview-manager/shared.js"
install -m 644 "$root/luci/settings.js" \
  "$stage/www/luci-static/resources/view/overview-manager/settings.js"
install -m 644 "$root/luci/overview.js" \
  "$stage/www/luci-static/resources/view/status/include/00_overview-manager.js"
install -m 644 "$root/LICENSE" \
  "$stage/usr/share/licenses/$PKG_NAME/LICENSE"

# The APK path compiles the same catalogs from the Makefile, so both packages
# ship identical translations without needing the LuCI feed host tools.
for po in "$root"/po/*/*.po; do
  [ -f "$po" ] || continue
  language="$(basename "$(dirname "$po")")"
  [ "$language" != templates ] || continue
  catalog="$stage/usr/lib/lua/luci/i18n/$(basename "$po" .po).$language.lmo"
  python3 "$root/scripts/po2lmo.py" "$po" "$catalog"
  # po2lmo.py honours the caller's umask; fix the mode so the packaged file
  # stays byte-identical across build hosts.
  chmod 644 "$catalog"
done

cat >"$stage/CONTROL/control" <<EOF
Package: $PKG_NAME
Version: $PKG_VERSION
Architecture: $PKG_ARCH
Maintainer: nikitid
Depends: luci-base, rpcd-mod-file
Section: luci
Priority: optional
Description: Configure the order and visibility of Status Overview widgets.
EOF

cat >"$stage/CONTROL/conffiles" <<'EOF'
/etc/config/overview-manager
EOF

cat >"$stage/CONTROL/postinst" <<'EOF'
#!/bin/sh
[ -n "${IPKG_INSTROOT:-}" ] && exit 0
# This package defines its own postinst, so the default handler that drains
# /etc/uci-defaults does not run. Apply the language registration here so a
# runtime install takes effect without waiting for the next boot.
if [ -x /etc/uci-defaults/luci-app-overview-manager ]; then
	/etc/uci-defaults/luci-app-overview-manager &&
		rm -f /etc/uci-defaults/luci-app-overview-manager
fi
rm -f /tmp/luci-indexcache
rm -rf /tmp/luci-modulecache
echo "Overview Manager installed. Open LuCI -> Status -> Overview Manager."
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
