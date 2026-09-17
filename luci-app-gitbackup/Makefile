#
# Copyright (C) 2026 VizzleTF
#
# This is free software, licensed under the GNU General Public License v2.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-gitbackup
PKG_VERSION:=0.1.1
PKG_RELEASE:=1

PKG_LICENSE:=GPL-2.0-only
PKG_MAINTAINER:=VizzleTF <vizzlef@gmail.com>

LUCI_TITLE:=Automatic configuration backup to a Git repository
# gitbackup itself (package/gitbackup) is where usr/sbin/gitbackup, the
# rpcd plugin and every shell module live -- this app is client-side JS
# only (ticket 11 acceptance criterion: "ни строки Lua, ни luci-compat, ни
# luci-lib-ipkg -- ни в коде, ни в зависимостях") and has nothing to render
# without it.
LUCI_DEPENDS:=+gitbackup
# Every byte here is POSIX shell (menu.d/acl.d JSON is not shell, but is not
# compiled either), plain JSON and client-side JS -- not one compiled byte,
# same reasoning as package/gitbackup's own PKGARCH:=all (spec, "Упаковка").
# LUCI_PKGARCH already defaults to "all" via luci.mk's own
# `LUCI_PKGARCH?=$(if $(realpath src/Makefile),,all)` (no src/Makefile here),
# but ticket 11's acceptance criterion asks for it spelled out explicitly.
LUCI_PKGARCH:=all

# This repository is a standalone third-party app, not a checkout living
# inside the openwrt/luci monorepo (unlike e.g. applications/luci-app-ttyd,
# which can say `include $(TOPDIR)/feeds/luci/luci.mk is two
# directories up from it there) -- so the helper has to be referenced by
# its real location in a buildroot that has the "luci" feed checked out,
# exactly as spec "Упаковка" names it.
include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
