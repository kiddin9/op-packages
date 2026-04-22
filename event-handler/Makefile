
include $(TOPDIR)/rules.mk

PKG_NAME:=event-handler
PKG_VERSION:=1
PKG_RELEASE:=1
PKG_BUILD_DIR:=$(BUILD_DIR)/event-handler

include $(INCLUDE_DIR)/package.mk

define Package/event-handler
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=Event Handler for lt70
  PKGARCH:=all
endef

define Package/event-handler/description
	 This package contains a utility
endef

define Build/Prepare
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/event-handler/install
	$(INSTALL_DIR) $(1)/bin
	$(INSTALL_BIN) ./files/event-handler $(1)/bin/
	$(INSTALL_DIR) $(1)/etc/config
	$(CP) ./files/event-handler.config $(1)/etc/config/event-handler
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/event-handler.init $(1)/etc/init.d/event-handler
	$(INSTALL_DIR) $(1)/etc/rc.button
	$(INSTALL_BIN) ./files/BTN_0 $(1)/etc/rc.button/
endef

$(eval $(call BuildPackage,event-handler))
