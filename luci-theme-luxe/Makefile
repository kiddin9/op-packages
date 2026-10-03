# LuCI Luxe Theme
# Copyright (C) 2008-2014 The LuCI Team <luci@lists.subsignal.org>
#
# This is free software, licensed under the Apache License, Version 2.0 .
#

include $(TOPDIR)/rules.mk

THEME_NAME:=luxe
THEME_TITLE:=LuxeOs
PKG_NAME:=luci-theme-$(THEME_NAME)
PKG_VERSION:=2.6.0
PKG_RELEASE:=1
PKG_MAINTAINER:=xidz_x

include $(INCLUDE_DIR)/package.mk

define Package/luci-theme-$(THEME_NAME)
	SECTION:=luci
	CATEGORY:=LuCI
	SUBMENU:=9. Themes
	DEPENDS:=+libc +luci-base
	TITLE:=LuCI Theme For OpenWrt - $(THEME_TITLE)
	URL:=https://github.com/de-quenx/luci-theme-luxe
	PKGARCH:=all
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/luci-theme-$(THEME_NAME)/install
	$(INSTALL_DIR) $(1)/etc
	$(CP) -a ./root/etc/* $(1)/etc/ 2>/dev/null || true
	$(INSTALL_DIR) $(1)/www/luci-static/$(THEME_NAME)
	$(CP) -a ./htdocs/luci-static/$(THEME_NAME)/* $(1)/www/luci-static/$(THEME_NAME)/ 2>/dev/null || true
	$(INSTALL_DIR) $(1)/www/luci-static/resources
	$(CP) -a ./htdocs/luci-static/resources/* $(1)/www/luci-static/resources/ 2>/dev/null || true
	$(INSTALL_DIR) $(1)/usr/share/ucode/luci/template/themes/$(THEME_NAME)
	$(CP) -a ./template/* $(1)/usr/share/ucode/luci/template/themes/$(THEME_NAME)/ 2>/dev/null || true
endef

define Package/luci-theme-$(THEME_NAME)/postinst
#!/bin/sh
if [ -z "$${IPKG_INSTROOT}" ]; then
	if [ -f /etc/uci-defaults/33_luci-theme-$(THEME_NAME) ]; then
		. /etc/uci-defaults/33_luci-theme-$(THEME_NAME)
		rm -f /etc/uci-defaults/33_luci-theme-$(THEME_NAME)
	fi
fi
exit 0
endef

$(eval $(call BuildPackage,luci-theme-$(THEME_NAME)))