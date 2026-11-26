#
# Copyright (C) 2020-2026 Tencent Cloud Plugins / OpenWrt Community
#
# Licensed under the Apache License, Version 2.0.
#

include $(TOPDIR)/rules.mk

PKG_LICENSE:=Apache-2.0
PKG_LICENSE_FILES:=LICENSE
PKG_MAINTAINER:=Tencent Cloud Plugins <https://github.com/Tencent-Cloud-Plugins/tencentcloud-openwrt-plugin-ddns>

LUCI_TITLE:=LuCI Support for Tencent Cloud / DNSPod DDNS
LUCI_DESCRIPTION:=Modern ucode and LuCI JS Dynamic DNS client for Tencent Cloud DNSPod API 3.0 (TC3-HMAC-SHA256) and Legacy Token API.
LUCI_PKGARCH:=all
LUCI_DEPENDS:= \
	+luci-base \
	+ucode \
	+ucode-mod-fs \
	+ucode-mod-uci \
	+ucode-mod-ubus \
	+ucode-mod-uloop \
	+ucode-mod-digest \
	+curl \
	+ca-bundle

define Build/Prepare/luci-app-tencentddns
	chmod 0755 \
		$(PKG_BUILD_DIR)/root/usr/bin/tencentddns \
		$(PKG_BUILD_DIR)/root/etc/init.d/tencentddns
endef

define Package/luci-app-tencentddns/conffiles
/etc/config/tencentddns
endef

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
