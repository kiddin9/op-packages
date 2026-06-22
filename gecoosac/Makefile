include $(TOPDIR)/rules.mk

PKG_NAME:=gecoosac
PKG_VERSION:=2.2.20251015
PKG_RELEASE:=14

PKG_MAINTAINER:=lwb1978 <lwb1978@gmail.com>
PKG_LICENSE:=AGPL-3.0-only
PKG_LICENSE_FILES:=LICENSE

ARCH_ID:=$(strip $(if $(ARCH_PACKAGES),$(ARCH_PACKAGES),$(ARCH)))

ifneq (,$(filter x86_64,$(ARCH_ID)))
  PKG_ARCH:=ac_linux_amd64
  PKG_HASH:=skip
else ifneq (,$(filter aarch64%,$(ARCH_ID)))
  PKG_ARCH:=ac_linux_arm64
  PKG_HASH:=skip
else ifneq (,$(filter arm arm_%,$(ARCH_ID)))
  PKG_ARCH:=ac_linux_arm
  PKG_HASH:=skip
else ifneq (,$(filter mipsel mipsel_%,$(ARCH_ID)))
  PKG_ARCH:=ac_linux_mipsle
  PKG_HASH:=skip
else ifneq (,$(filter mips mips_%,$(ARCH_ID)))
  PKG_ARCH:=ac_linux_mips
  PKG_HASH:=skip
else ifneq (,$(filter i386%,$(ARCH_ID)))
  PKG_ARCH:=ac_linux_386
  PKG_HASH:=skip
else
  PKG_HASH:=skip
endif

PKG_SOURCE:=$(PKG_NAME)-$(PKG_VERSION)-$(PKG_ARCH)
PKG_SOURCE_URL:=https://github.com/laipeng668/luci-app-gecoosac/releases/download/V$(PKG_VERSION)/$(PKG_ARCH)?
UNPACK_CMD=$(CP) $(DL_DIR)/$(PKG_SOURCE) $(PKG_BUILD_DIR)/$(PKG_NAME)

include $(INCLUDE_DIR)/package.mk

define Package/$(PKG_NAME)
  SECTION:=net
  CATEGORY:=Network
  TITLE:=gecoosac server (version $(PKG_VERSION))
  URL:=http://www.cnrouter.com/
  DEPENDS:=@(aarch64||arm||i386||mips||mipsel||x86_64) +openssl-util
endef

define Package/$(PKG_NAME)/conffiles
/etc/config/gecoosac
/etc/gecoosac/
endef

define Build/Prepare
	$(call Build/Prepare/Default)
	$(CP) ../LICENSE $(PKG_BUILD_DIR)/LICENSE
endef

define Build/Compile
endef

define Package/$(PKG_NAME)/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_DIR) $(1)/etc/gecoosac/tls
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_DIR) $(1)/etc/uci-defaults

	$(INSTALL_BIN) $(PKG_BUILD_DIR)/$(PKG_NAME) $(1)/usr/bin
	$(INSTALL_BIN) ./files/etc/init.d/gecoosac $(1)/etc/init.d/gecoosac
	$(INSTALL_BIN) ./files/etc/uci-defaults/gecoosac $(1)/etc/uci-defaults/gecoosac
	$(INSTALL_CONF) ./files/etc/config/gecoosac $(1)/etc/config/gecoosac
endef

$(eval $(call BuildPackage,$(PKG_NAME)))
