# SPDX-License-Identifier: Apache-2.0
#
# Copyright (C) 2026 Amr Fateem <amr.fateem@yahoo.com>
#
# LuCI application for v2rayA.

include $(TOPDIR)/rules.mk

LUCI_TITLE:=LuCI support for v2rayA (NextGen)
LUCI_DEPENDS:=+luci-base +v2raya
LUCI_PKGARCH:=all
LUCI_MAINTAINER:=Amr Fateem <amr.fateem@yahoo.com>

# Date-based version (YY.DDD), the same scheme as the OpenWrt LuCI packages.
PKG_VERSION:=26.317.1
PKG_RELEASE:=1

PKG_LICENSE:=Apache-2.0
CONFLICTS:=luci-app-v2raya

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
