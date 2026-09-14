# Copyright (C) 2016 Openwrt.org
#
# This is free software, licensed under the Apache License, Version 2.0 .
#

include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-openlist2
PKG_VERSION:=1.0.4
PKG_RELEASE:=7

LUCI_TITLE:=LuCI support for openlist
# Require a core package with both the restricted helper and automatic TLS.
LUCI_DEPENDS:=+openlist2 +openlist2-helper +openlist2-tls

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
