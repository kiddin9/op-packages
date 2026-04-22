
include $(TOPDIR)/rules.mk

PKG_NAME:=svupgrade
PKG_VERSION:=48.7.1.2.1
PKG_RELEASE:=1
PKG_BUILD_DIR:=$(BUILD_DIR)/svupgrade

include $(INCLUDE_DIR)/package.mk

define Package/svupgrade
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=Supervisor FW upgrade for LT70
  PKGARCH:=all
endef

define Package/svupgrade/description
	 This package contains a script and fw for supervisor update
endef

define Build/Prepare
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/svupgrade/install
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/svupgrade.init $(1)/etc/init.d/svupgrade
	$(INSTALL_DIR) $(1)/lib/firmware/gd3x
	$(INSTALL_BIN) ./files/gd3x.bin $(1)/lib/firmware/gd3x/gd3x.bin.backup
	#$(INSTALL_BIN) ./files/gd3x.bin $(1)/lib/firmware/gd3x/gd3x.bin
endef

$(eval $(call BuildPackage,svupgrade))
