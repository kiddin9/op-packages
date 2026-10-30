# SPDX-License-Identifier: GPL-2.0-only

include $(TOPDIR)/rules.mk

PKG_NAME:=honk
PKG_VERSION:=0.1.0_beta4
PKG_RELEASE:=25

# Raw upstream release tag. It keeps the dots in qualifiers (e.g. v0.0.1.beta.49)
# because that is what the GitHub release asset name uses.
HONK_RELEASE_TAG:=v0.1.0-beta.4
HONK_ASSET_TAG:=v0.1.0-beta.4

# SHA256 of each release tarball, kept in sync by scripts/update_honk_version.sh.
HONK_HASH_X86_64:=48f694b13b9c5200e8e884ee19431035bd67b0ef01d04caef007047ad11ba02c
HONK_HASH_AARCH64:=6cc92f862a1684ba9c49e9f9c08fb108f53444f338f1e9be84013e2f7fb7423d

PKG_LICENSE:=AGPL-3.0-only
PKG_LICENSE_FILE:=LICENSE
PKG_MAINTAINER:=luci-app-honk maintainers

ifeq ($(ARCH),x86_64)
  HONK_TARGET:=x86_64-unknown-linux-musl
  HONK_HASH:=$(HONK_HASH_X86_64)
else ifeq ($(ARCH),aarch64)
  HONK_TARGET:=aarch64-unknown-linux-musl
  HONK_HASH:=$(HONK_HASH_AARCH64)
endif

# mimalloc build: faster QUIC. honk.init sets MIMALLOC_ARENA_RESERVE=0 so the
# 1 GiB arena reservation stays out of VmSize. Use "-stock" to go back.
HONK_SUFFIX:=
# Upstream feature variant: -native-api (recommended for OpenWrt gateway), -full, or empty for legacy releases.
HONK_VARIANT:=-native-api
HONK_ASSET:=honk-core-$(HONK_ASSET_TAG)-$(HONK_TARGET)$(HONK_SUFFIX)$(HONK_VARIANT).tar.gz

PKG_SOURCE:=$(HONK_ASSET)
PKG_SOURCE_URL:=https://github.com/daeuniverse/honk/releases/download/$(HONK_RELEASE_TAG)/
PKG_HASH:=skip

include $(INCLUDE_DIR)/package.mk

define Package/honk
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=Web Servers/Proxies
  TITLE:=honk - eBPF transparent proxy engine (dae-compatible)
  URL:=https://github.com/daeuniverse/honk
  DEPENDS:=@(x86_64||aarch64) \
    +ca-bundle +ip-full \
    +kmod-sched-core +kmod-sched-bpf +kmod-veth +kmod-nft-queue \
    +v2ray-geoip +v2ray-geosite \
    +@KERNEL_XDP_SOCKETS \
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
	mkdir -p $(PKG_BUILD_DIR)
	$(TAR) -xzf $(DL_DIR)/$(PKG_SOURCE) -C $(PKG_BUILD_DIR) --strip-components=1
endef

define Build/Compile
	true
endef

define Package/honk/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/honk-core $(1)/usr/bin/honk-core

	$(INSTALL_DIR) $(1)/etc/honk/config.d
	$(INSTALL_CONF) $(CURDIR)/files/config.dae $(1)/etc/honk/config.dae
	$(INSTALL_CONF) $(CURDIR)/files/config.d/node.dae $(1)/etc/honk/config.d/node.dae
	$(INSTALL_CONF) $(CURDIR)/files/config.d/route.dae $(1)/etc/honk/config.d/route.dae
	$(INSTALL_CONF) $(CURDIR)/files/config.d/dns.dae $(1)/etc/honk/config.d/dns.dae
	$(INSTALL_CONF) $(CURDIR)/files/config.d/api.dae $(1)/etc/honk/config.d/api.dae

	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) $(CURDIR)/files/honk.config $(1)/etc/config/honk

	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) $(CURDIR)/files/honk.init $(1)/etc/init.d/honk
endef

$(eval $(call BuildPackage,honk))
