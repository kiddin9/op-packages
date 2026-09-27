# package/meow/Makefile
include $(TOPDIR)/rules.mk

PKG_NAME:=meow
PKG_VERSION:=0.21.2
PKG_RELEASE:=1
PKG_MAINTAINER:=Max Lv <max.c.lv@gmail.com>
PKG_LICENSE:=MIT
PKG_LICENSE_FILES:=LICENSE

PKG_SOURCE:=meow-v$(PKG_VERSION)-aarch64-unknown-linux-musl.tar.gz
PKG_SOURCE_URL:=https://github.com/meow-rs/meow-rs/releases/download/v$(PKG_VERSION)/
PKG_HASH:=7966b35ee2101e32406009f074f97cbbcc8017489daa02cd3fc5b91b4dbcbfeb
PKG_BUILD_DIR:=$(BUILD_DIR)/meow-v$(PKG_VERSION)-aarch64-unknown-linux-musl

include $(INCLUDE_DIR)/package.mk

define Package/meow
  SECTION:=net
  CATEGORY:=Network
  TITLE:=meow - mihomo-compatible tunneling proxy kernel (Rust, static musl)
  URL:=https://github.com/meow-rs/meow-rs
  DEPENDS:=+libc
endef

define Package/meow/description
  A high-performance, rule-based tunneling proxy kernel in Rust, compatible
  with mihomo (Clash Meta). Static binary; YAML config in /etc/meow/config.yaml,
  service settings in /etc/config/meow.
endef

define Package/meow/conffiles
/etc/config/meow
/etc/meow/config.yaml
endef

# 二进制是官方发布的静态 musl 构建,无需在 buildroot 内编译
define Build/Compile
endef

define Package/meow/install
	$(INSTALL_DIR) $(1)/usr/bin $(1)/etc/init.d $(1)/etc/config $(1)/etc/meow $(1)/etc/uci-defaults

	$(INSTALL_BIN)  $(PKG_BUILD_DIR)/meow                     $(1)/usr/bin/meow
	$(INSTALL_BIN)  ./files/meow.init                         $(1)/etc/init.d/meow
	$(INSTALL_DATA) ./files/meow.config                       $(1)/etc/config/meow
	$(INSTALL_DATA) ./files/config.yaml                       $(1)/etc/meow/config.yaml
	$(INSTALL_DATA) ./files/gateway.nft.template              $(1)/etc/meow/gateway.nft.template
	$(INSTALL_BIN)  ./files/firewall.sh                       $(1)/etc/meow/firewall.sh
	$(INSTALL_BIN)  ./files/uci-defaults/99-meow-firewall     $(1)/etc/uci-defaults/99-meow-firewall
endef

$(eval $(call BuildPackage,meow))
