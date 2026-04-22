
include $(TOPDIR)/rules.mk

PKG_NAME:=hotplug-generator
PKG_VERSION:=1
PKG_RELEASE:=1
PKG_BUILD_DIR:=$(BUILD_DIR)/hotplug-generator

include $(INCLUDE_DIR)/package.mk

define Package/hotplug-generator
  TITLE:=generator of hotplug scripts
  SECTION:=utils
  CATEGORY:=Utilities
  PKGARCH:=all
endef

define Package/hotplug-generator/description
	 This package contains additional scripts and configuration files for generation hotplug scripts
endef

define Build/Prepare
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/hotplug-generator/install
	$(INSTALL_DIR) $(1)/etc/config
	$(CP) ./files/hotplug.config $(1)/etc/config/hotplug
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/hotplug.init $(1)/etc/init.d/hotplug
endef

$(eval $(call BuildPackage,hotplug-generator))
