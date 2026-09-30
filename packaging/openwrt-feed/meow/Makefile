include $(TOPDIR)/rules.mk

PKG_NAME:=meow
PKG_VERSION?=0.0.0
PKG_RELEASE?=0

include $(INCLUDE_DIR)/package.mk

PKG_MAINTAINER:=Independent meow OpenWrt package <noreply@example.invalid>

# This feed is intentionally a prebuilt-core package. The GitHub Actions
# workflow compiles the exact upstream meow-rs commit first, then injects the
# resulting target binary as ./prebuilt/meow before invoking the OpenWrt SDK.

define Package/meow
  SECTION:=net
  CATEGORY:=Network
  TITLE:=meow high-performance rule-based proxy core
  URL:=https://github.com/meow-rs/meow-rs
  LICENSE:=MIT
  DEPENDS:=+libc
endef

define Package/meow/description
  meow Rust proxy core built from the exact upstream main commit recorded in
  UPSTREAM.json. The package contains the architecture-specific static binary
  plus the upstream OpenWrt service/configuration files.
endef

define Build/Prepare
endef

define Build/Compile
endef

define Package/meow/install
  $(INSTALL_DIR) $(1)/usr/bin
  $(INSTALL_DIR) $(1)/etc/init.d
  $(INSTALL_DIR) $(1)/etc/config
  $(INSTALL_DIR) $(1)/etc/meow
  $(INSTALL_DIR) $(1)/etc/uci-defaults
  $(INSTALL_DIR) $(1)/usr/share/meow
  $(INSTALL_BIN) ./prebuilt/meow $(1)/usr/bin/meow
  $(INSTALL_BIN) ./files/meow.init $(1)/etc/init.d/meow
  $(INSTALL_DATA) ./files/meow.config $(1)/etc/config/meow
  $(INSTALL_DATA) ./files/config.yaml $(1)/etc/meow/config.yaml
  $(INSTALL_BIN) ./files/gateway.sh $(1)/usr/share/meow/gateway.sh
  $(INSTALL_BIN) ./files/arp-hijack.sh $(1)/usr/share/meow/arp-hijack.sh
  $(INSTALL_BIN) ./files/meow-arp.init $(1)/etc/init.d/meow-arp
  $(INSTALL_BIN) ./files/meow.uci-defaults $(1)/etc/uci-defaults/80_meow
endef

define Package/meow/conffiles
/etc/config/meow
/etc/meow/config.yaml
endef

$(eval $(call BuildPackage,meow))
