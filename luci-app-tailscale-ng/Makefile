# SPDX-License-Identifier: GPL-3.0-only
#
# Copyright (C) 2026 vad-b
# Based on https://github.com/asvow/luci-app-tailscale

include $(TOPDIR)/rules.mk

LUCI_TITLE:=LuCI for Tailscale (NG)
LUCI_DESCRIPTION:=LuCI web interface for managing Tailscale on OpenWrt routers
LUCI_DEPENDS:=+tailscale
LUCI_PKGARCH:=all
LUCI_MAINTAINER:=vad-b

PKG_VERSION:=0.1.3
PKG_RELEASE:=5
PKG_PO_VERSION:=$(PKG_VERSION)-r$(PKG_RELEASE)
PKG_LICENSE:=GPL-3.0-only

define Build/Prepare/luci-app-tailscale-ng
	$(SED) 's/@APP_VERSION@/$(PKG_VERSION)/g' $(PKG_BUILD_DIR)/htdocs/luci-static/resources/view/tailscale-ng/index.js
endef

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
