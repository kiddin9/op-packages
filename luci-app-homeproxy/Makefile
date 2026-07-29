# SPDX-License-Identifier: GPL-2.0-only
#
# Copyright (C) 2022-2023 ImmortalWrt.org

include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-homeproxy
PKG_VERSION:=2.0.0
PKG_RELEASE:=8

LUCI_TITLE:=Sing-box proxy management platform for OpenWrt
LUCI_PKGARCH:=all
LUCI_DEPENDS:= \
	+sing-box \
	+firewall4 \
	+dnsmasq-full \
	+ip-full \
	+kmod-tun \
	+kmod-nft-tproxy \
	+ca-bundle \
	+curl \
	+jsonfilter \
	+unzip \
	+ucode-mod-digest \
	+ucode-mod-fs \
	+ucode-mod-math \
	+ucode-mod-ubus \
	+ucode-mod-uci

define Package/luci-app-homeproxy/conffiles
/etc/config/homeproxy
/etc/homeproxy/certs/
/etc/homeproxy/ruleset/
/etc/homeproxy/resources/direct_list.txt
/etc/homeproxy/resources/proxy_list.txt
endef

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
