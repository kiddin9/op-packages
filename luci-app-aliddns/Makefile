#
# Copyright (C) 2018-2026 honwen <https://github.com/honwen/>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-aliddns

PKG_LICENSE:=MIT
PKG_LICENSE_FILES:=LICENSE
PKG_MAINTAINER:=honwen <https://github.com/honwen/>

LUCI_TITLE:=LuCI Support for AliDDNS
LUCI_DESCRIPTION:=Native ucode and LuCI JavaScript client for Alibaba Cloud Dynamic DNS (AliDDNS) on OpenWrt 25.12+.
LUCI_DEPENDS:=+luci-base +ucode +ucode-mod-fs +ucode-mod-uci +ucode-mod-ubus +ucode-mod-uloop +ucode-mod-resolv +curl +ca-bundle
LUCI_PKGARCH:=all

define Package/luci-app-aliddns/conffiles
/etc/config/aliddns
endef

define Build/Prepare/luci-app-aliddns
	chmod 0755 $(PKG_BUILD_DIR)/root/etc/init.d/aliddns
	chmod 0755 $(PKG_BUILD_DIR)/root/usr/sbin/aliddns
endef

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
