#!/bin/sh

set -eu

root="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
stage="${1:?usage: stage-package.sh STAGE_DIR}"
. "$root/release.env"

rm -rf "$stage"
mkdir -p \
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

# The Makefile compiles the same catalogs with the same script, so this tree
# matches the APK payload without needing the LuCI feed host tools.
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
