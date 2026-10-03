# SPDX-License-Identifier: Apache-2.0
include $(TOPDIR)/rules.mk

PKG_NAME:=luci-theme-rmm
PKG_VERSION:=0.9.0
PKG_RELEASE:=1
PKG_LICENSE:=Apache-2.0
PKG_LICENSE_FILES:=LICENSE

include $(INCLUDE_DIR)/package.mk

define Package/luci-theme-rmm
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=4. Themes
  TITLE:=OpenWrt RMM theme for LuCI
  DEPENDS:=+luci-base +luci-theme-bootstrap
  PKGARCH:=all
endef

define Package/luci-theme-rmm/description
  Compact dark LuCI theme styled after the OpenWrt RMM console.
endef

define Build/Compile
endef

define Package/luci-theme-rmm/install
	$(INSTALL_DIR) $(1)/www/luci-static/rmm
	$(INSTALL_DATA) ./htdocs/luci-static/rmm/cascade.css $(1)/www/luci-static/rmm/cascade.css
	$(INSTALL_DATA) ./htdocs/luci-static/rmm/icons.svg $(1)/www/luci-static/rmm/icons.svg
	$(INSTALL_DATA) ./htdocs/luci-static/rmm/navigation.js $(1)/www/luci-static/rmm/navigation.js
	$(INSTALL_DATA) ./htdocs/luci-static/rmm/components.js $(1)/www/luci-static/rmm/components.js
	$(INSTALL_DATA) ./htdocs/luci-static/rmm/search.js $(1)/www/luci-static/rmm/search.js
	$(INSTALL_DIR) $(1)/usr/share/ucode/luci/template/themes/rmm
	$(INSTALL_DATA) ./ucode/template/themes/rmm/*.ut $(1)/usr/share/ucode/luci/template/themes/rmm/
	$(INSTALL_DIR) $(1)/etc/uci-defaults
	$(INSTALL_BIN) ./root/etc/uci-defaults/30_luci-theme-rmm $(1)/etc/uci-defaults/30_luci-theme-rmm
	$(INSTALL_DIR) $(1)/usr/share/licenses/luci-theme-rmm
	$(INSTALL_DATA) ./LICENSE $(1)/usr/share/licenses/luci-theme-rmm/LICENSE
	$(INSTALL_DATA) ./licenses/Tabler-Icons-MIT.txt $(1)/usr/share/licenses/luci-theme-rmm/Tabler-Icons-MIT.txt
	$(INSTALL_DATA) ./NOTICE.md $(1)/usr/share/licenses/luci-theme-rmm/NOTICE.md
endef

define Package/luci-theme-rmm/postinst
#!/bin/sh
if [ -z "$${IPKG_INSTROOT}" ]; then
	if [ -f /etc/uci-defaults/30_luci-theme-rmm ]; then
		sh /etc/uci-defaults/30_luci-theme-rmm || exit $$?
		rm -f /etc/uci-defaults/30_luci-theme-rmm
	fi
fi
exit 0
endef

define Package/luci-theme-rmm/postrm
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || {
	if [ "$$(uci -q get luci.main.mediaurlbase)" = '/luci-static/rmm' ]; then
		uci set luci.main.mediaurlbase='/luci-static/bootstrap'
	fi
	uci -q delete luci.themes.RMM
	uci commit luci
}
exit 0
endef

$(eval $(call BuildPackage,luci-theme-rmm))
