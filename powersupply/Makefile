
include $(TOPDIR)/rules.mk

PKG_NAME:=powersupply
PKG_VERSION:=1
PKG_RELEASE:=1
PKG_BUILD_DIR:=$(BUILD_DIR)/powersupply

include $(INCLUDE_DIR)/package.mk

define Package/powersupply
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=Power Supply for LT70
  PKGARCH:=all
endef

define Package/powersupply/description
	 This package contains a utility for powersupply
endef

define Build/Prepare
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/powersupply/install
	$(INSTALL_DIR) $(1)/etc/config
	$(CP) ./files/powersupply.config $(1)/etc/config/powersupply
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/powersupply.init $(1)/etc/init.d/powersupply
	$(INSTALL_DIR) $(1)/usr/libexec/rpcd
	$(INSTALL_BIN) ./files/powersupply.rpcd $(1)/usr/libexec/rpcd/powersupply
endef

$(eval $(call BuildPackage,powersupply))
