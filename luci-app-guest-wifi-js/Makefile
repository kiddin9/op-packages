#
# Copyright 2026 Rafał Wabik - IceG - From eko.one.pl forum
#
# Licensed to the GNU General Public License v3.0.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-guest-wifi-js
LUCI_TITLE:=LuCI JS support for Guest Wi-Fi
PKG_MAINTAINER:=Rafał Wabik <4Rafal@gmail.com>
LUCI_DESCRIPTION:=LuCI JS interface for the Guest Wi-Fi
LUCI_DEPENDS:=+luci-base +firewall4 +dnsmasq
LUCI_PKGARCH:=all
PKG_VERSION:=1.0.7
PKG_RELEASE:=1

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
