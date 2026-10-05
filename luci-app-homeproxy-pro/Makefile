# SPDX-License-Identifier: GPL-2.0-only
#
# Copyright (C) 2022-2023 ImmortalWrt.org
#

include $(TOPDIR)/rules.mk

LUCI_TITLE:=The modern ImmortalWrt proxy platform for ARM64/AMD64 (sing-box 1.14)
LUCI_PKGARCH:=all
LUCI_DEPENDS:= \
	+sing-box \
	+firewall4 \
	+kmod-nft-tproxy \
    +ip-full \
    +kmod-tun \
	+uclient-fetch \
	+ucode-mod-digest

PKG_NAME:=luci-app-homeproxy-pro
PKG_VERSION:=28.10.1.14
PKG_RELEASE:=21

LUCI_BASENAME:=homeproxy-pro

define Package/luci-app-homeproxy-pro/conffiles
/etc/config/homeproxy-pro
/etc/homeproxy-pro/resources/china_ip4.txt
/etc/homeproxy-pro/resources/china_ip6.txt
/etc/homeproxy-pro/resources/china_list.txt
/etc/homeproxy-pro/resources/gfw_list.txt
/etc/homeproxy-pro/resources/china_ip4.ver
/etc/homeproxy-pro/resources/china_ip6.ver
/etc/homeproxy-pro/resources/china_list.ver
/etc/homeproxy-pro/resources/gfw_list.ver
endef

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
