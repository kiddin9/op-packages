include $(TOPDIR)/rules.mk

PKG_NAME:=minigate
PKG_VERSION:=2026.9.18-2
PKG_RELEASE:=1
PKG_LICENSE:=MIT
PKG_MAINTAINER:=MiniGate

include $(INCLUDE_DIR)/package.mk

define Package/$(PKG_NAME)
	SECTION:=luci
	CATEGORY:=LuCI
	SUBMENU:=3. Applications
	TITLE:=LuCI - MiniGate (DDNS + ACME + Reverse Proxy + Login Guard)
	DEPENDS:=+luci-base +nginx-ssl +nginx-mod-stream +openssl-util +wget +curl +jsonfilter +coreutils-stat +nftables
	PROVIDES:=luci-app-minigate
	CONFLICTS:=luci-app-minigate
	VERSION:=$(if $(CONFIG_USE_APK),$(subst -,-r,$(PKG_VERSION)),$(PKG_VERSION))
	PKGARCH:=all
endef

define Package/$(PKG_NAME)/description
Lightweight gateway management for OpenWrt: Cloudflare DDNS, Let's Encrypt SSL certificates,
Nginx reverse proxy, and SSH/LuCI brute-force ban (Login Guard) with LuCI web interface.
endef

define Package/$(PKG_NAME)/conffiles
/etc/config/minigate
endef

define Build/Compile
endef

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
	$(INSTALL_BIN) ./root/usr/lib/minigate/geofence.sh $(1)/usr/lib/minigate/
	$(INSTALL_BIN) ./root/usr/lib/minigate/login_guard.sh $(1)/usr/lib/minigate/
	$(INSTALL_BIN) ./root/usr/lib/minigate/update.sh $(1)/usr/lib/minigate/
	$(INSTALL_BIN) ./root/usr/lib/minigate/uninstall.sh $(1)/usr/lib/minigate/

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
	$(INSTALL_DIR) $(1)/etc/minigate/nginx/streams
	$(INSTALL_DIR) $(1)/etc/minigate/login-guard

	# i18n / translations
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/i18n
	[ ! -f ./po/zh-cn/minigate.po ] || $(STAGING_DIR_HOSTPKG)/bin/po2lmo ./po/zh-cn/minigate.po $(1)/usr/lib/lua/luci/i18n/minigate.zh-cn.lmo
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
