include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-overview-manager
PKG_VERSION:=0.1.0
PKG_RELEASE:=1
PKG_LICENSE:=MIT
PKG_MAINTAINER:=nikitid
PKGARCH:=all

include $(INCLUDE_DIR)/package.mk

define Package/luci-app-overview-manager
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=2. Modules
  TITLE:=Status Overview widget manager
  DEPENDS:=+luci-base +rpcd-mod-file
endef

define Package/luci-app-overview-manager/description
 LuCI application for ordering and hiding Status Overview widgets without
 modifying files owned by other packages.
endef

define Package/luci-app-overview-manager/conffiles
/etc/config/overview-manager
endef

LUCI_LANGUAGES:=$(sort $(filter-out templates,$(notdir $(wildcard ${CURDIR}/po/*))))

define Build/Compile
endef

define Package/luci-app-overview-manager/install
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./openwrt/files/etc/config/overview-manager $(1)/etc/config/overview-manager

	$(INSTALL_DIR) $(1)/etc/uci-defaults
	$(INSTALL_BIN) ./openwrt/files/etc/uci-defaults/luci-app-overview-manager \
		$(1)/etc/uci-defaults/luci-app-overview-manager

	$(INSTALL_DIR) $(1)/usr/libexec
	$(INSTALL_BIN) ./runtime/overview-manager.sh $(1)/usr/libexec/overview-manager

	$(INSTALL_DIR) $(1)/usr/share/luci/menu.d $(1)/usr/share/rpcd/acl.d
	$(INSTALL_DATA) ./luci/menu.json $(1)/usr/share/luci/menu.d/luci-app-overview-manager.json
	$(INSTALL_DATA) ./luci/acl.json $(1)/usr/share/rpcd/acl.d/luci-app-overview-manager.json

	$(INSTALL_DIR) $(1)/www/luci-static/resources/overview-manager
	$(INSTALL_DATA) ./luci/shared.js $(1)/www/luci-static/resources/overview-manager/shared.js

	$(INSTALL_DIR) $(1)/www/luci-static/resources/view/overview-manager
	$(INSTALL_DATA) ./luci/settings.js $(1)/www/luci-static/resources/view/overview-manager/settings.js

	$(INSTALL_DIR) $(1)/www/luci-static/resources/view/status/include
	$(INSTALL_DATA) ./luci/overview.js $(1)/www/luci-static/resources/view/status/include/00_overview-manager.js

	$(INSTALL_DIR) $(1)/usr/share/licenses/luci-app-overview-manager
	$(INSTALL_DATA) ./LICENSE $(1)/usr/share/licenses/luci-app-overview-manager/LICENSE

	# scripts/po2lmo.py is a byte-compatible reimplementation of the luci-base
	# po2lmo tool. Using it keeps this package independent of the LuCI feed
	# host tools and produces the same catalogs as the SDK-less IPK build.
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/i18n
	$(foreach language,$(LUCI_LANGUAGES), \
		$(foreach po,$(wildcard ${CURDIR}/po/$(language)/*.po), \
			python3 $(CURDIR)/scripts/po2lmo.py $(po) \
				$(1)/usr/lib/lua/luci/i18n/$(basename $(notdir $(po))).$(language).lmo; \
			chmod 0644 $(1)/usr/lib/lua/luci/i18n/$(basename $(notdir $(po))).$(language).lmo;))
endef

define Package/luci-app-overview-manager/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT:-}" ] && exit 0
# This package defines its own postinst, so the default handler that drains
# /etc/uci-defaults does not run. Apply the language registration here so a
# runtime install takes effect without waiting for the next boot.
if [ -x /etc/uci-defaults/luci-app-overview-manager ]; then
	/etc/uci-defaults/luci-app-overview-manager &&
		rm -f /etc/uci-defaults/luci-app-overview-manager
fi
rm -f /tmp/luci-indexcache
rm -rf /tmp/luci-modulecache
echo "Overview Manager installed. Open LuCI -> Status -> Overview Manager."
exit 0
endef

define Package/luci-app-overview-manager/prerm
#!/bin/sh
[ -n "$${IPKG_INSTROOT:-}" ] && exit 0
case "$${1:-}" in upgrade) exit 0 ;; esac
[ "$${PKG_UPGRADE:-0}" = 1 ] && exit 0
rm -f /tmp/luci-indexcache
rm -rf /tmp/luci-modulecache
exit 0
endef

$(eval $(call BuildPackage,luci-app-overview-manager))
