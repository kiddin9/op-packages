include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-isp-split
PKG_VERSION:=0.1.3
PKG_RELEASE:=4
PKG_LICENSE:=MIT
PKG_MAINTAINER:=jihebube <jihebube@users.noreply.github.com>

include $(INCLUDE_DIR)/package.mk

define Package/luci-app-isp-split
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  TITLE:=LuCI support for ISP-aware policy routing
  DEPENDS:=+isp-split +luci-base
  PKGARCH:=all
endef

define Package/luci-app-isp-split/description
  LuCI page for isp-split: shows per-ISP element counts and hit
  counters, and offers one-click sync, data refresh, and config
  editing (wire/apply/dns).
endef

define Build/Compile
endef

define Package/luci-app-isp-split/install
	$(INSTALL_DIR) $(1)/www/luci-static/resources/view/isp-split
	$(INSTALL_DATA) ./htdocs/luci-static/resources/view/isp-split/overview.js \
		$(1)/www/luci-static/resources/view/isp-split/overview.js
	$(INSTALL_DATA) ./htdocs/luci-static/resources/view/isp-split/config.js \
		$(1)/www/luci-static/resources/view/isp-split/config.js
	$(INSTALL_DIR) $(1)/usr/share/luci/menu.d
	$(INSTALL_DATA) ./root/usr/share/luci/menu.d/luci-app-isp-split.json \
		$(1)/usr/share/luci/menu.d/luci-app-isp-split.json
	$(INSTALL_DIR) $(1)/usr/share/rpcd/acl.d
	$(INSTALL_DATA) ./root/usr/share/rpcd/acl.d/luci-app-isp-split.json \
		$(1)/usr/share/rpcd/acl.d/luci-app-isp-split.json
endef

define Package/luci-app-isp-split/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] && exit 0
rm -f /tmp/luci-indexcache* 2>/dev/null
/etc/init.d/rpcd restart >/dev/null 2>&1
exit 0
endef

$(eval $(call BuildPackage,luci-app-isp-split))
