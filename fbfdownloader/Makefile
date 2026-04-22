
include $(TOPDIR)/rules.mk

PKG_NAME:=fbfdownloader
PKG_VERSION:=4.9.0.7
PKG_RELEASE:=1
PKG_BUILD_DIR:=$(BUILD_DIR)/fbfdownloader


include $(INCLUDE_DIR)/package.mk

define Package/fbfdownloader
  SECTION:=utils
  CATEGORY:=Utilities
  DEPENDS+= +libpthread
  TITLE:=Firmware flash tool for ASR based modems
endef

TARGET_CFLAGS += -I$(STAGING_DIR)/usr/include
TARGET_LDFLAGS += -L$(STAGING_DIR)/usr/lib

define Package/fbfdownloader/description
 This package contains utility for sim check manage.
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
	$(CP) ./src/* $(PKG_BUILD_DIR)/
endef

define Package/fbfdownloader/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/fbfdownloader_cross $(1)/usr/bin
endef

$(eval $(call BuildPackage,fbfdownloader))
