# SPDX-License-Identifier: GPL-3.0-only
#
# Copyright (C) 2026 vad-b
# Based on https://github.com/asvow/luci-app-tailscale

include $(TOPDIR)/rules.mk

LUCI_TITLE:=LuCI for Tailscale (NG)
LUCI_DEPENDS:=+tailscale
LUCI_PKGARCH:=all

PKG_VERSION:=0.1.2

# match the i18n pkg version to the main pkg version
PKG_RELEASE:=4
PKG_PO_VERSION:=$(PKG_VERSION)-r$(PKG_RELEASE)

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
