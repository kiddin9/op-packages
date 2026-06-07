# Copyright (C) 2024 Openwrt.org
#
# This is free software, licensed under the Apache License, Version 2.0 .
#

include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-gecoosac
PKG_VERSION:=2.2
PKG_RELEASE:=5

LUCI_TITLE:=LuCI Support for gecoosac
LUCI_DEPENDS:=+luci-compat +gecoosac
LUCI_PKGARCH:=all

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
