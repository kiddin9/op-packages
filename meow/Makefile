# SPDX-License-Identifier: MIT

include $(TOPDIR)/rules.mk

PKG_NAME:=meow
PKG_VERSION:=0.30.0
PKG_RELEASE:=22

PKG_SOURCE:=$(PKG_NAME)-$(PKG_VERSION).tar.gz
PKG_SOURCE_URL:=https://codeload.github.com/meow-rs/meow-rs/tar.gz/v$(PKG_VERSION)?
PKG_HASH:=skip
PKG_BUILD_DIR:=$(BUILD_DIR)/meow-rs-$(PKG_VERSION)

PKG_MAINTAINER:=Max Lv <max.c.lv@gmail.com>
PKG_LICENSE:=MIT
PKG_LICENSE_FILES:=LICENSE

PKG_BUILD_DEPENDS:=rust/host cmake/host
PKG_BUILD_PARALLEL:=1
PKG_CONFIG_DEPENDS:= \
	CONFIG_MEOW_MINIMAL \
	CONFIG_MEOW_EXTERNAL_UI_DOWNLOAD \
	CONFIG_MEOW_VERSION_SUFFIX

include $(INCLUDE_DIR)/package.mk
ifneq ($(wildcard $(INCLUDE_DIR)/rust-package.mk),)
  include $(INCLUDE_DIR)/rust-package.mk
else
  include $(TOPDIR)/feeds/packages/lang/rust/rust-package.mk
endif

define Package/meow
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=Web Servers/Proxies
  TITLE:=meow high-performance rule-based proxy core
  URL:=https://github.com/meow-rs/meow-rs
  DEPENDS:=$(RUST_ARCH_DEPENDS) @(aarch64||arm||x86_64||riscv64) \
    +kmod-nft-socket +kmod-nft-tproxy +libstdcpp
  MENU:=1
endef

define Package/meow/description
  A high-performance, rule-based tunneling proxy kernel in Rust, compatible
  with mihomo (Clash Meta). Configuration lives in /etc/meow/config.yaml,
  service settings in /etc/config/meow. Transparent-proxy / gateway mode
  uses kmod-nft-socket and kmod-nft-tproxy.
endef

define Package/meow/config
if PACKAGE_meow

	config MEOW_MINIMAL
		bool "Build with minimal feature set (--no-default-features --features minimal)"
		default n
		help
		  Build a smaller binary using the minimal feature bundle (< 8 MiB budget
		  on aarch64) instead of the default full feature set.

	config MEOW_EXTERNAL_UI_DOWNLOAD
		bool "Enable external-ui-download feature"
		default y
		help
		  Allow meow to auto-download a third-party web dashboard from
		  external-ui-url.

	config MEOW_VERSION_SUFFIX
		string "Optional version suffix (MEOW_VERSION_SUFFIX)"
		default ""
		help
		  Optional suffix appended to the version reported by `meow -v`
		  (e.g. -alpha+5d71564).

endif
endef

define Package/meow/conffiles
/etc/config/meow
/etc/meow/config.yaml
endef

RUST_PKG_FEATURES:=$(strip \
	$(if $(CONFIG_MEOW_MINIMAL),minimal) \
	$(if $(CONFIG_MEOW_EXTERNAL_UI_DOWNLOAD),external-ui-download) \
)

CARGO_PKG_VARS+= \
	MEOW_VERSION_SUFFIX="$(call qstrip,$(CONFIG_MEOW_VERSION_SUFFIX))"

define Build/Compile
	$(call Build/Compile/Cargo,crates/meow-app,--locked --bin meow $(if $(CONFIG_MEOW_MINIMAL),--no-default-features))
endef

define Package/meow/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_INSTALL_DIR)/bin/meow $(1)/usr/bin/meow

	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/meow.init $(1)/etc/init.d/meow
	$(INSTALL_BIN) ./files/meow-arp.init $(1)/etc/init.d/meow-arp

	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_DATA) ./files/meow.config $(1)/etc/config/meow

	$(INSTALL_DIR) $(1)/etc/meow
	$(INSTALL_DATA) ./files/config.yaml $(1)/etc/meow/config.yaml

	$(INSTALL_DIR) $(1)/usr/share/meow
	$(INSTALL_BIN) ./files/gateway.sh $(1)/usr/share/meow/gateway.sh
	$(INSTALL_BIN) ./files/arp-hijack.sh $(1)/usr/share/meow/arp-hijack.sh

	$(INSTALL_DIR) $(1)/etc/uci-defaults
	$(INSTALL_BIN) ./files/meow.uci-defaults $(1)/etc/uci-defaults/80_meow
endef

define Package/meow/prerm
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] && exit 0
/etc/init.d/meow-arp stop 2>/dev/null || true
/etc/init.d/meow-arp disable 2>/dev/null || true
/etc/init.d/meow stop 2>/dev/null || true
/etc/init.d/meow disable 2>/dev/null || true
exit 0
endef

$(eval $(call RustBinPackage,meow))
$(eval $(call BuildPackage,meow))
