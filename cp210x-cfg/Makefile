
include $(TOPDIR)/rules.mk

PKG_NAME:=cp210x-cfg
PKG_VERSION:=1
PKG_RELEASE:=1

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL=https://github.com/iuncuim/cp210x-cfg.git
PKG_SOURCE_DATE:=2023-05-18
PKG_SOURCE_VERSION:=bf968c49c7cf004ebfba72f7deb0ba88330e1652
PKG_MIRROR_HASH:=skip

include $(INCLUDE_DIR)/package.mk

define Package/cp210x-cfg
	SECTION:=utils
	CATEGORY:=Utilities
	TITLE:=CLI utility for programming CP210x USB<->UART bridges
	DEPENDS:=+libusb-1.0
endef

TARGET_CFLAGS += -I$(STAGING_DIR)/usr/include
TARGET_LDFLAGS += -L$(STAGING_DIR)/usr/lib

define Package/cp210x-cfg/description
	CLI utility for programming CP210x USB<->UART bridges
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
	$(CP) ./src/* $(PKG_BUILD_DIR)/
endef

define Package/cp210x-cfg/install
	$(INSTALL_DIR) $(1)/sbin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/cp210x-cfg $(1)/sbin/
endef

$(eval $(call BuildPackage,cp210x-cfg))
