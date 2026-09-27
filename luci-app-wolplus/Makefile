# Copyright (C) 2016 Openwrt.org
#
# This is free software, licensed under the Apache License, Version 2.0 .
#

include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-wolplus
PKG_VERSION:=1.2
PKG_RELEASE:=2
PKG_LICENSE:=Apache-2.0
PKG_MAINTAINER:=sundaqiang

LUCI_TITLE:=LuCI support for wolplus From sundaqiang
LUCI_DEPENDS:=+luci-base +etherwake +rpcd +ucode +ucode-mod-fs +ucode-mod-uci
LUCI_PKGARCH:=all

include $(TOPDIR)/feeds/luci/luci.mk

# 包安装后修复 rpcd ucode 脚本执行权限（部分编译环境会丢失执行位）
define Package/$(PKG_NAME)/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || {
	chmod 0755 /usr/share/rpcd/ucode/luci.wolplus 2>/dev/null
	rm -f /tmp/luci-indexcache.*
	rm -rf /tmp/luci-modulecache/
	/etc/init.d/rpcd reload 2>/dev/null
	exit 0
}
endef

# call BuildPackage - OpenWrt buildroot signature
