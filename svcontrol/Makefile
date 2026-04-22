
include $(TOPDIR)/rules.mk

PKG_NAME:=svcontrol
PKG_VERSION:=1
PKG_RELEASE:=1
PKG_BUILD_DIR:=$(BUILD_DIR)/svcontrol

include $(INCLUDE_DIR)/package.mk

define Package/svcontrol
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=Supervisor control 
  PKGARCH:=all
endef

define Package/svcontrol/description
	 This package contains a utility
endef

define Build/Prepare
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/svcontrol/install
	$(INSTALL_DIR) $(1)/bin
	$(INSTALL_BIN) ./files/svcontrol $(1)/bin/
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/svcontrol.init $(1)/etc/init.d/svcontrol
endef

$(eval $(call BuildPackage,svcontrol))
