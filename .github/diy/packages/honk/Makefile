# SPDX-License-Identifier: GPL-2.0-only

include $(TOPDIR)/rules.mk

PKG_NAME:=honk
ifeq ($(DUMP)$(filter clean,$(MAKECMDGOALS)),)
  PKG_VERSION:=$(or $(shell curl -fsSLm 5 https://raw.githubusercontent.com/QiuSimons/luci-app-daeuniverse/master/honk/Makefile | sed -n 's/^PKG_VERSION:=//p'),0.0.0)
else
  PKG_VERSION:=0.0.0
endif
PKG_RELEASE:=1

PKG_LICENSE:=AGPL-3.0-only
PKG_MAINTAINER:=QiuSimons <https://github.com/QiuSimons>

include $(INCLUDE_DIR)/package.mk

define Package/honk
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=Web Servers/Proxies
  TITLE:=honk - eBPF transparent proxy engine (dae-compatible)
  URL:=https://github.com/daeuniverse/honk
  DEPENDS:=@(aarch64||x86_64) \
    +ca-bundle \
    +kmod-sched-core +kmod-sched-bpf +kmod-veth +kmod-nft-queue \
    +v2ray-geoip +v2ray-geosite \
    +HONK_USE_VMLINUX_BTF:vmlinux-btf
endef

define Package/honk/description
  honk is an eBPF-based transparent proxy core with native API and dae-compatible syntax.
  This package installs the honk-core binary for use with luci-app-daeuniverse.
endef

define Package/honk/config
  choice
    prompt "BTF source for CO-RE"
    default HONK_USE_KERNEL_BTF
    depends on PACKAGE_honk

    config HONK_USE_KERNEL_BTF
      bool "Use kernel BTF (integrated)"

    config HONK_USE_VMLINUX_BTF
      bool "Use vmlinux-btf package"
  endchoice
endef

define Build/Prepare
	mkdir -p "$(PKG_BUILD_DIR)"
	curl -fsSL https://api.github.com/repos/QiuSimons/luci-app-daeuniverse/releases/latest \
		| grep -oE 'https://[^"]*/honk_[^"]*_$(ARCH)[^"]*\.ipk' | head -n1 \
		| xargs -r curl -fsSL | tar -xzf - -C "$(PKG_BUILD_DIR)"
	tar -xzf "$(PKG_BUILD_DIR)/data.tar.gz" -C "$(PKG_BUILD_DIR)"
endef

define Build/Compile
endef

define Package/honk/install
	$(INSTALL_DIR) "$(1)/usr/bin"
	$(INSTALL_BIN) "$(PKG_BUILD_DIR)/usr/bin/honk-core" "$(1)/usr/bin/honk-core"
endef

$(eval $(call BuildPackage,honk))
