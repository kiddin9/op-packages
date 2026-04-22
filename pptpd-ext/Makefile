
include $(TOPDIR)/rules.mk

PKG_NAME:=pptpd-ext
PKG_VERSION:=1
PKG_RELEASE:=1
PKG_BUILD_DIR:=$(BUILD_DIR)/pptpd-ext

include $(INCLUDE_DIR)/package.mk

define Package/pptpd-ext
  TITLE:=pptpd server additional scripts
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=VPN
  PKGARCH:=all
endef

define Package/pptpd-ext/description
	 This package contains additional scripts and configuration files for pptpd
endef

define Build/Prepare
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/pptpd-ext/install
	$(INSTALL_DIR) $(1)/etc
	$(CP) ./files/pptpd.conf $(1)/etc/pptpd.conf

	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/pptpd.init $(1)/etc/init.d/pptpd

	$(INSTALL_DIR) $(1)/usr/lib/pptpd
	$(INSTALL_BIN) ./files/pptp-up $(1)/usr/lib/pptpd/pptp-up
	$(INSTALL_BIN) ./files/pptp-down $(1)/usr/lib/pptpd/pptp-down
	
	$(INSTALL_DIR) $(1)/etc/ppp
	$(CP) ./files/options.pptpd $(1)/etc/ppp/options.pptpd

	$(INSTALL_DIR) $(1)/etc/config
	$(CP) ./files/pptpd.config $(1)/etc/config/pptpd
endef

$(eval $(call BuildPackage,pptpd-ext))
