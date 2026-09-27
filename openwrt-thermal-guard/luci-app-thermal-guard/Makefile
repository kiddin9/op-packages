#
# Copyright (C) 2026 SyntaxError NullPointer
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#

include $(TOPDIR)/rules.mk

PKG_VERSION:=2.0.0
PKG_RELEASE:=1

PKG_LICENSE:=GPL-2.0-only
PKG_MAINTAINER:=SyntaxError NullPointer <287466119+SyntaxError-NullPointer@users.noreply.github.com>

LUCI_TITLE:=LuCI support for thermal-guard
LUCI_DESCRIPTION:=Monitor and configuration pages for thermal-guard: temperatures, fan, protection stages and thresholds.
LUCI_DEPENDS:=+luci-base +thermal-guard
LUCI_PKGARCH:=all

include $(TOPDIR)/feeds/luci/luci.mk

# No own postinst: luci.mk's default drops the menu caches and reloads rpcd,
# without which the new ACL is not loaded and the pages are refused.

# call BuildPackage - OpenWrt buildroot signature
