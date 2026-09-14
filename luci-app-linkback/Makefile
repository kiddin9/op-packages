# SPDX-License-Identifier: Apache-2.0
#
# Copyright (C) 2026 Dante <dante@seckv.com>
#
# This is free software, licensed under the Apache License, Version 2.0 .
#

include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-linkback
PKG_VERSION:=1.0.0
PKG_RELEASE:=1
PKG_MAINTAINER:=Dante

LUCI_TITLE:=LuCI support for Multi-WAN LinkBack Failover/Failback
LUCI_DEPENDS:=+luci-base +ucode +ucode-mod-fs +ucode-mod-uci +ucode-mod-ubus +linkback
LUCI_PKGARCH:=all

define Package/$(PKG_NAME)/postinst
#!/sh
[ -n "$${IPKG_INSTROOT}" ] || {
	/etc/init.d/rpcd restart
}
exit 0
endef

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
