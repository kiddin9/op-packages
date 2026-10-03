# Copyright (C) 2026 permails <logo@permails.com>
# This is free software, licensed under the Apache License, Version 2.0

include $(TOPDIR)/rules.mk

LUCI_TITLE:=LuCI support for SecBox
LUCI_DEPENDS:=+luci-base +banip +nftables +kmod-nft-core
LUCI_PKGARCH:=all

PKG_VERSION:=1.26.8
PKG_RELEASE:=1
PKG_LICENSE:=Apache-2.0
PKG_MAINTAINER:=permails <logo@permails.com>

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
