include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-minigate
PKG_VERSION:=1.0.0
PKG_RELEASE:=1
PKG_LICENSE:=MIT
PKG_MAINTAINER:=MiniGate

LUCI_TITLE:=LuCI - MiniGate (DDNS + ACME + Reverse Proxy)
LUCI_DESCRIPTION:=Lightweight gateway management for OpenWrt: Cloudflare DDNS, Let's Encrypt SSL certificates, and Nginx reverse proxy with LuCI web interface.
LUCI_DEPENDS:=+luci-base +nginx-ssl +openssl-util +wget +curl +jsonfilter +coreutils-stat
LUCI_PKGARCH:=all

define Package/$(PKG_NAME)/conffiles
/etc/config/minigate
endef

include $(TOPDIR)/feeds/luci/luci.mk

define Package/$(PKG_NAME)/install
	# LuCI files
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/controller
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/model/cbi/minigate
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/view/minigate
	$(CP) ./luasrc/controller/minigate.lua $(1)/usr/lib/lua/luci/controller/
	$(CP) ./luasrc/model/cbi/minigate/*.lua $(1)/usr/lib/lua/luci/model/cbi/minigate/
	$(CP) ./luasrc/view/minigate/*.htm $(1)/usr/lib/lua/luci/view/minigate/

	# Backend scripts
	$(INSTALL_DIR) $(1)/usr/lib/minigate
	$(INSTALL_BIN) ./root/usr/lib/minigate/ddns.sh $(1)/usr/lib/minigate/
	$(INSTALL_BIN) ./root/usr/lib/minigate/acme.sh $(1)/usr/lib/minigate/
	$(INSTALL_BIN) ./root/usr/lib/minigate/proxy.sh $(1)/usr/lib/minigate/

	# Config
	$(INSTALL_DIR) $(1)/etc/config
	$(CP) ./root/etc/config/minigate $(1)/etc/config/

	# Init script
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./root/etc/init.d/minigate $(1)/etc/init.d/

	# Data directories
	$(INSTALL_DIR) $(1)/etc/minigate/acme
	$(INSTALL_DIR) $(1)/etc/minigate/certs
	$(INSTALL_DIR) $(1)/etc/minigate/nginx
	$(INSTALL_DIR) $(1)/etc/minigate/nginx/sites

	# i18n / translations
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/i18n
	po2lmo ./po/zh-cn/minigate.po $(1)/usr/lib/lua/luci/i18n/minigate.zh-cn.lmo
endef

define Package/$(PKG_NAME)/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || {
	chmod +x /etc/init.d/minigate
	chmod +x /usr/lib/minigate/*.sh
	/etc/init.d/minigate enable
	echo "MiniGate installed. Configure at: LuCI → Services → MiniGate"
}
endef

define Package/$(PKG_NAME)/prerm
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || {
	/etc/init.d/minigate stop
	/etc/init.d/minigate disable
}
endef

$(eval $(call BuildPackage,$(PKG_NAME)))
