include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-wrqr
PKG_VERSION:=0.1.0
PKG_RELEASE:=1
PKG_LICENSE:=MIT
PKG_MAINTAINER:=nikitid
PKGARCH:=all

include $(INCLUDE_DIR)/package.mk

define Package/luci-app-wrqr
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  TITLE:=Wi-Fi QR codes for Status Overview
  DEPENDS:=+luci-base +luci-lib-uqr
endef

define Package/luci-app-wrqr/description
 Display QR codes for active Wi-Fi access points on the LuCI Status Overview.
endef

define Build/Compile
endef

define Package/luci-app-wrqr/install
	$(INSTALL_DIR) $(1)/usr/share/rpcd/acl.d
	$(INSTALL_DATA) ./luci/acl.json $(1)/usr/share/rpcd/acl.d/luci-app-wrqr.json

	$(INSTALL_DIR) $(1)/www/luci-static/resources/wrqr
	$(INSTALL_DATA) ./luci/shared.js $(1)/www/luci-static/resources/wrqr/shared.js

	$(INSTALL_DIR) $(1)/www/luci-static/resources/view/status/include
	$(INSTALL_DATA) ./luci/overview.js $(1)/www/luci-static/resources/view/status/include/15_wifi-qr.js

	$(INSTALL_DIR) $(1)/usr/share/licenses/luci-app-wrqr
	$(INSTALL_DATA) ./LICENSE $(1)/usr/share/licenses/luci-app-wrqr/LICENSE
endef

define Package/luci-app-wrqr/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT:-}" ] && exit 0
rm -f /tmp/luci-indexcache
rm -rf /tmp/luci-modulecache
exit 0
endef

define Package/luci-app-wrqr/prerm
#!/bin/sh
[ -n "$${IPKG_INSTROOT:-}" ] && exit 0
case "$${1:-}" in upgrade) exit 0 ;; esac
[ "$${PKG_UPGRADE:-0}" = 1 ] && exit 0
rm -f /tmp/luci-indexcache
rm -rf /tmp/luci-modulecache
exit 0
endef

$(eval $(call BuildPackage,luci-app-wrqr))
