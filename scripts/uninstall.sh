#!/bin/sh

set -eu

echo "Stopping clashoo service..."
/etc/init.d/clashoo stop >/dev/null 2>&1 || true
/etc/init.d/clashoo disable >/dev/null 2>&1 || true

core_still_installed() {
  if command -v apk >/dev/null 2>&1; then
    apk list -I 2>/dev/null | grep -q "^clashoo-[0-9]"
  elif command -v opkg >/dev/null 2>&1; then
    opkg list-installed 2>/dev/null | grep -q "^clashoo "
  else
    return 1
  fi
}

if command -v opkg >/dev/null 2>&1; then
  echo "Removing packages with opkg..."
  opkg remove luci-i18n-clashoo-zh-cn luci-app-clashoo clashoo >/dev/null 2>&1 || true
elif command -v apk >/dev/null 2>&1; then
  echo "Removing packages with apk..."
  apk del luci-i18n-clashoo-zh-cn luci-app-clashoo clashoo >/dev/null 2>&1 || true
else
  echo "No supported package manager found (opkg/apk), skip package removal."
fi

# Always safe: purely runtime/temp files, never owned by the package manager.
echo "Cleaning runtime temp files..."
rm -rf /tmp/clashoo /tmp/clashoo-install /tmp/clashoo_* /tmp/luci* 2>/dev/null || true

# CRITICAL: only delete package-owned files (config / init.d / dirs) when the
# core package was actually removed. If it's still installed - e.g. nikki, which
# depends on the clashoo-provided `mihomo`, blocks `apk del clashoo` - deleting
# these behind the package manager's back corrupts apk's state: the db keeps
# owning files that no longer exist, so a later same-version reinstall only
# writes `.apk-new` and never restores them, leaving the UI broken
# ("kernel not installed" / start stuck). Leave them in place instead.
if core_still_installed; then
  echo "WARNING: 'clashoo' is still installed because other packages depend on it"
  echo "         (e.g. nikki depends on the clashoo-provided 'mihomo')."
  echo "         Kept /etc/config/clashoo, /etc/init.d/clashoo and /etc/clashoo intact"
  echo "         to avoid corrupting package state. Remove nikki first for a full"
  echo "         uninstall, or just reinstall clashoo to refresh it."
else
  echo "Cleaning package files..."
  rm -rf /etc/clashoo /usr/share/clashoo /usr/share/clashbackup 2>/dev/null || true
  rm -f /etc/init.d/clashoo /etc/config/clashoo 2>/dev/null || true
fi

/etc/init.d/rpcd restart >/dev/null 2>&1 || true
/etc/init.d/uhttpd restart >/dev/null 2>&1 || true
/etc/init.d/dnsmasq restart >/dev/null 2>&1 || true
/etc/init.d/firewall restart >/dev/null 2>&1 || true

echo "Uninstall & reset complete."
