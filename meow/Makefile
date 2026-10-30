# SPDX-License-Identifier: MIT
#
#

include $(TOPDIR)/rules.mk

PKG_NAME:=meow
PKG_VERSION:=0.28.0
PKG_RELEASE:=18

PKG_SOURCE:=$(PKG_NAME)-$(PKG_VERSION).tar.gz
PKG_SOURCE_URL:=https://codeload.github.com/meow-rs/meow-rs/tar.gz/v$(PKG_VERSION)?
PKG_HASH:=skip
PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)-$(PKG_VERSION)

PKG_MAINTAINER:=Max Lv <max.c.lv@gmail.com>
PKG_LICENSE:=MIT
PKG_LICENSE_FILES:=LICENSE

PKG_BUILD_DEPENDS:=rust/host
PKG_BUILD_PARALLEL:=1

include $(INCLUDE_DIR)/package.mk
include $(TOPDIR)/feeds/packages/lang/rust/rust-package.mk

TAR_OPTIONS += --strip-components 1
TAR_CMD=$(HOST_TAR) -C $(1) $(TAR_OPTIONS)

define Package/meow
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=Web Servers/Proxies
  TITLE:=meow high-performance rule-based proxy core
  URL:=https://github.com/meow-rs/meow-rs
  DEPENDS:=@(aarch64||arm||x86_64||riscv64) +kmod-nft-socket +kmod-nft-tproxy +libstdcpp
endef

define Package/meow/description
  A high-performance, rule-based tunneling proxy kernel in Rust,
  compatible with mihomo (Clash Meta). Static binary; configuration lives in
  /etc/meow/config.yaml, service settings in /etc/config/meow.

  Transparent-proxy / gateway mode additionally uses kmod-nft-socket and
  kmod-nft-tproxy.
endef

define Package/meow/config
  if PACKAGE_meow
    config MEOW_MINIMAL
      bool "Build with minimal feature set (--no-default-features --features minimal)"
      default n
      help
        Build a smaller binary using the minimal feature bundle (< 8 MiB budget on aarch64)
        instead of the default full feature set.

    config MEOW_EXTERNAL_UI_DOWNLOAD
      bool "Enable external-ui-download feature"
      default y
      help
        Allow meow to auto-download a third-party web dashboard from external-ui-url.

    config MEOW_VERSION_SUFFIX
      string "Optional version suffix (MEOW_VERSION_SUFFIX)"
      default ""
      help
        Optional suffix appended to the version reported by `meow -v` (e.g. -alpha+5d71564).
  endif
endef

define Package/meow/conffiles
/etc/config/meow
/etc/meow/config.yaml
endef

define Select/Features
$(strip \
  $(if $(CONFIG_MEOW_MINIMAL),--no-default-features --features minimal) \
  $(if $(CONFIG_MEOW_EXTERNAL_UI_DOWNLOAD),--features external-ui-download) \
)
endef

define Build/Compile
	( \
		pushd $(PKG_BUILD_DIR) ; \
		$(CARGO_PKG_CONFIG_VARS) \
		MEOW_VERSION_SUFFIX="$(call qstrip,$(CONFIG_MEOW_VERSION_SUFFIX))" \
		cargo build --release \
			--locked \
			-p meow-app \
			--bin meow \
			--target $(RUSTC_TARGET_ARCH) \
			$(call Select/Features) ; \
		popd ; \
	)
endef

define Package/meow/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/target/$(RUSTC_TARGET_ARCH)/release/meow $(1)/usr/bin/meow

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
/etc/init.d/meow-arp stop 2>/dev/null
/etc/init.d/meow-arp disable 2>/dev/null
/etc/init.d/meow stop 2>/dev/null
/etc/init.d/meow disable || true
exit 0
endef

$(eval $(call RustBinPackage,meow))
$(eval $(call BuildPackage,meow))
