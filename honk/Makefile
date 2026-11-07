# SPDX-License-Identifier: GPL-2.0-only
#
# Copyright (C) 2026 QiuSimons <https://github.com/QiuSimons>

include $(TOPDIR)/rules.mk

PKG_NAME:=honk
PKG_VERSION:=2026.11.07~73b1077
PKG_RELEASE:=32

HONK_SRC_URL:=https://github.com/daeuniverse/honk.git
HONK_SRC_VERSION:=73b1077bf9cdb639899f0447994cf8980abc0752

PKG_LICENSE:=AGPL-3.0-only
PKG_LICENSE_FILES:=LICENSE
PKG_MAINTAINER:=QiuSimons <https://github.com/QiuSimons>

include $(INCLUDE_DIR)/package.mk

HONK_RUST_ARCH_DEPENDS:=@(aarch64||x86_64)

define Package/honk
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=Web Servers/Proxies
  TITLE:=honk - eBPF transparent proxy engine (dae-compatible)
  URL:=https://github.com/daeuniverse/honk
  DEPENDS:=$(HONK_RUST_ARCH_DEPENDS) \
    +ca-bundle \
    +kmod-sched-core +kmod-sched-bpf +kmod-veth +kmod-nft-queue \
    +v2ray-geoip +v2ray-geosite \
    +HONK_USE_VMLINUX_BTF:vmlinux-btf
endef

define Package/honk/config
	choice
		prompt "BTF source for CO-RE"
		default HONK_USE_KERNEL_BTF
		depends on PACKAGE_honk

	config HONK_USE_KERNEL_BTF
		bool "Use kernel BTF (integrated)"
		depends on KERNEL_DEBUG_INFO_BTF

	config HONK_USE_VMLINUX_BTF
		bool "Use vmlinux-btf package"
	endchoice
endef

define Package/honk/conffiles
/etc/honk/config.dae
/etc/honk/config.d/
/etc/honk/state/
/etc/config/honk
endef

define Build/Prepare
	mkdir -p "$(PKG_BUILD_DIR)"
endef

define Build/Compile
	"$(CURDIR)/build_honk_core.sh" --if-needed "$(ARCH)" "$(CURDIR)/files/honk-core.bin"
	$(INSTALL_DIR) "$(PKG_INSTALL_DIR)/bin"
	$(INSTALL_BIN) "$(CURDIR)/files/honk-core.bin" "$(PKG_INSTALL_DIR)/bin/honk-core"
endef

define Package/honk/install
	$(INSTALL_DIR) "$(1)/usr/bin"
	$(INSTALL_BIN) "$(PKG_INSTALL_DIR)/bin/honk-core" "$(1)/usr/bin/honk-core"

	$(INSTALL_DIR) "$(1)/etc/honk/config.d"
	$(INSTALL_CONF) "$(CURDIR)/files/config.dae" "$(1)/etc/honk/config.dae"
	$(INSTALL_CONF) "$(CURDIR)/files/config.d/node.dae" "$(1)/etc/honk/config.d/node.dae"
	$(INSTALL_CONF) "$(CURDIR)/files/config.d/route.dae" "$(1)/etc/honk/config.d/route.dae"
	$(INSTALL_CONF) "$(CURDIR)/files/config.d/dns.dae" "$(1)/etc/honk/config.d/dns.dae"
	$(INSTALL_CONF) "$(CURDIR)/files/config.d/api.dae" "$(1)/etc/honk/config.d/api.dae"

	$(INSTALL_DIR) "$(1)/etc/config"
	$(INSTALL_CONF) "$(CURDIR)/files/honk.config" "$(1)/etc/config/honk"

	$(INSTALL_DIR) "$(1)/etc/init.d"
	$(INSTALL_BIN) "$(CURDIR)/files/honk.init" "$(1)/etc/init.d/honk"
endef

$(eval $(call BuildPackage,honk))
