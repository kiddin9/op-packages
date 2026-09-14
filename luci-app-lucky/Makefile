# SPDX-License-Identifier: GPL-3.0-only
#
# Copyright (C) 2022-2023 gdy  
# 
# This is free software, licensed under the Apache License, Version 2.0 .
#
include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-lucky
PKG_VERSION:=1.0.4
PKG_RELEASE:=2

LUCI_TITLE:=LuCI Support for lucky 
LUCI_DEPENDS:=+lucky
LUCI_PKGARCH:=all

define Package/$(PKG_NAME)/prerm
#!/bin/sh
rm -f /tmp/lucky_info_cache 2>/dev/null
exit 0
endef

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
