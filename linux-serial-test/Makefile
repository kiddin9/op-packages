include $(TOPDIR)/rules.mk

PKG_NAME:=linux-serial-test
PKG_VERSION:=1
PKG_RELEASE:=1

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL=https://github.com/cbrake/linux-serial-test.git
PKG_SOURCE_DATE:=2024-01-15
PKG_SOURCE_VERSION:=6a28493a29f7b941172bc58cf4fdabbf8109022f
PKG_MIRROR_HASH:=skip

include $(INCLUDE_DIR)/package.mk

define Package/linux-serial-test
	SECTION:=utils
	CATEGORY:=Utilities
	TITLE:=Linux Serial Test Application
endef

define Package/linux-serial-test/description
	Linux Serial Test Application
endef

define Build/Compile
	$(TARGET_CC) $(TARGET_CFLAGS) $(TARGET_LDFLAGS) $(PKG_BUILD_DIR)/linux-serial-test.c -o $(PKG_BUILD_DIR)/linux-serial-test
endef

define Package/linux-serial-test/install
	$(INSTALL_DIR) $(1)/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/linux-serial-test $(1)/bin/
endef

$(eval $(call BuildPackage,linux-serial-test))
