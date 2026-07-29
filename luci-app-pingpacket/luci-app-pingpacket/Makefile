include $(TOPDIR)/rules.mk

LUCI_TITLE:=LuCI web interface for Pingpacket monitoring
LUCI_DEPENDS:=+luci-base +luci-lua-runtime +luci-compat +curl
LUCI_PKGARCH:=all

PKG_NAME:=luci-app-pingpacket
PKG_VERSION:=1.0.0
PKG_RELEASE:=20
PKG_LICENSE:=Apache-2.0

include $(TOPDIR)/feeds/luci/luci.mk

define Package/$(PKG_NAME)/install
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/controller
	$(INSTALL_DATA) ./luasrc/controller/pingpacket.lua $(1)/usr/lib/lua/luci/controller/pingpacket.lua

	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/view/pingpacket
	$(INSTALL_DATA) ./luasrc/view/pingpacket/status.htm $(1)/usr/lib/lua/luci/view/pingpacket/status.htm
	$(INSTALL_DATA) ./luasrc/view/pingpacket/logs.htm $(1)/usr/lib/lua/luci/view/pingpacket/logs.htm

	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./root/etc/config/pingpacket $(1)/etc/config/pingpacket

	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./root/etc/init.d/pingpacket $(1)/etc/init.d/pingpacket

	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) ./root/usr/bin/pingpacket.sh $(1)/usr/bin/pingpacket.sh

	$(INSTALL_DIR) $(1)/usr/share/rpcd/acl.d
	$(INSTALL_DATA) ./root/usr/share/rpcd/acl.d/luci-app-pingpacket.json \
		$(1)/usr/share/rpcd/acl.d/luci-app-pingpacket.json
endef

define Package/$(PKG_NAME)/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] && exit 0
rm -f /tmp/luci-indexcache.*
rm -rf /tmp/luci-modulecache/
/etc/init.d/rpcd reload 2>/dev/null
exit 0
endef

define Package/$(PKG_NAME)/prerm
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] && exit 0
[ -f /etc/init.d/pingpacket ] && {
	/etc/init.d/pingpacket disable 2>/dev/null
	/etc/init.d/pingpacket stop 2>/dev/null
}
exit 0
endef

$(eval $(call BuildPackage,$(PKG_NAME)))
