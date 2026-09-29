# SPDX-License-Identifier: GPL-3.0-only
#
# Copyright (C) 2026 vad-b
# Based on https://github.com/asvow/luci-app-tailscale

include $(TOPDIR)/rules.mk

LUCI_TITLE:=LuCI for Tailscale (NG)
LUCI_DEPENDS:=+tailscale
LUCI_PKGARCH:=all

PKG_VERSION:=0.1.1
PKG_RELEASE:=1

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
