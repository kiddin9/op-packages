# Copyright (C) 2016 Openwrt.org
#
# This is free software, licensed under the Apache License, Version 2.0 .
#

include $(TOPDIR)/rules.mk

LUCI_TITLE:=LuCI support for linkease
LUCI_DEPENDS:=+luci-lib-linkeasefile
LUCI_PKGARCH:=all
PKG_VERSION:=2.1.70-r4
# PKG_RELEASE MUST be empty for luci.mk
PKG_RELEASE:=2
LUCI_MINIFY_CSS:=0
LUCI_MINIFY_JS:=0

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature

