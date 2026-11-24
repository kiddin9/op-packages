# Copyright (C) 2026 permails <logo@permails.com>
# This is free software, licensed under the Apache License, Version 2.0

include $(TOPDIR)/rules.mk

LUCI_TITLE:=LuCI support for SecBox
LUCI_DEPENDS:=+luci-base +banip +nftables +kmod-nft-core +msmtp
LUCI_PKGARCH:=all

PKG_VERSION:=26.11
PKG_RELEASE:=2
PKG_LICENSE:=Apache-2.0
PKG_MAINTAINER:=permails <logo@permails.com>

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
