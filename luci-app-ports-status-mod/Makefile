#
# Copyright 2025 Rafał Wabik - IceG - From eko.one.pl forum
# 
# MIT License
#

include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-ports-status-mod
PKG_MAINTAINER:=Rafał Wabik <4Rafal@gmail.com>
LUCI_TITLE:=Small modification of Ports Status
LUCI_DEPENDS:=+luci-mod-admin-full
LUCI_PKGARCH:=all
PKG_LICENSE:=MIT
PKG_VERSION:=1.0.8
PKG_RELEASE:=1

define Package/luci-app-ports-status-mod/conffiles
/etc/user_defined_ports.json
/etc/user_defined_ports.json.bak
endef

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
