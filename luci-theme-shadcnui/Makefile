#
# Copyright (C) 2026 bsatou
#
# This is free software, licensed under the Apache License, Version 2.0 .
#

include $(TOPDIR)/rules.mk

LUCI_TITLE:=shadcn/ui Theme for LuCI
LUCI_DEPENDS:=
LUCI_PKGARCH:=all

PKG_NAME:=luci-theme-shadcnui
PKG_VERSION:=0.3.7
PKG_RELEASE:=1
PKG_LICENSE:=Apache-2.0
PKG_MAINTAINER:=bsatou

include $(TOPDIR)/feeds/luci/luci.mk

# Post-install: replace the vanilla sysauth.ut with ours so our login layout
# (sidebar-less centered card) is used instead of LuCI's default. Save the
# original alongside it so we can restore on uninstall.
#
# luci-base owns /usr/share/ucode/luci/template/sysauth.ut, so we cannot ship
# the override directly inside the package — apk would refuse with a file
# overwrite conflict. Instead we ship our copy under the theme's own dir and
# do the swap here at install time.
define Package/$(PKG_NAME)/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] && exit 0       # skip when building image, only run on device

THEME_SYSAUTH=/usr/share/ucode/luci/template/themes/shadcnui/sysauth.ut
LIVE_SYSAUTH=/usr/share/ucode/luci/template/sysauth.ut
BACKUP=$${LIVE_SYSAUTH}.shadcnui-backup

if [ -f "$${THEME_SYSAUTH}" ]; then
    if [ -f "$${LIVE_SYSAUTH}" ] && [ ! -f "$${BACKUP}" ]; then
        cp -a "$${LIVE_SYSAUTH}" "$${BACKUP}"
    fi
    cp -af "$${THEME_SYSAUTH}" "$${LIVE_SYSAUTH}"
fi

# Drop LuCI caches so the new template is picked up immediately.
rm -f /tmp/luci-indexcache /tmp/luci-modulecache/* 2>/dev/null
exit 0
endef

define Package/$(PKG_NAME)/prerm
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] && exit 0

LIVE_SYSAUTH=/usr/share/ucode/luci/template/sysauth.ut
BACKUP=$${LIVE_SYSAUTH}.shadcnui-backup

if [ -f "$${BACKUP}" ]; then
    mv -f "$${BACKUP}" "$${LIVE_SYSAUTH}"
fi

rm -f /tmp/luci-indexcache /tmp/luci-modulecache/* 2>/dev/null
exit 0
endef

# call BuildPackage - OpenWrt buildroot signature
