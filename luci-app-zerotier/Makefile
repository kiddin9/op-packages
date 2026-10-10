#
# Copyright (C) 2008-2014 The LuCI Team <luci@lists.subsignal.org>
#
# This is free software, licensed under the Apache License, Version 2.0 .
#

include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-zerotier
PKG_VERSION:=2.2
PKG_RELEASE:=6
PKG_LICENSE:=Apache-2.0

LUCI_TITLE:=LuCI for ZeroTier
LUCI_DESCRIPTION:=LuCI interface for ZeroTier VPN service with Auto NAT support
LUCI_DEPENDS:=+luci-base +zerotier +jsonfilter
LUCI_PKGARCH:=all

PKG_MAINTAINER:=OpenWrt LuCI community

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
