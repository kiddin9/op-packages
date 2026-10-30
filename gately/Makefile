# SPDX-License-Identifier: GPL-3.0-only
#
# Copyright (C) 2026 OpenWrt.org

include $(TOPDIR)/rules.mk

PKG_NAME:=gately
PKG_VERSION:=0.6.1
PKG_RELEASE:=18

PKG_SOURCE:=$(PKG_NAME)-$(PKG_VERSION).tar.gz
PKG_SOURCE_URL:=https://codeload.github.com/wangwanjie/gately/tar.gz/v$(PKG_VERSION)?
PKG_HASH:=skip

PKG_LICENSE:=Apache-2.0
PKG_LICENSE_FILES:=LICENSE
PKG_MAINTAINER:=wangwanjie <https://github.com/wangwanjie/gately>

PKG_BUILD_DEPENDS:=golang/host node/host node-pnpm/host
PKG_BUILD_PARALLEL:=1
PKG_BUILD_FLAGS:=no-mips16

BUILD_DATE:=$(shell date -u -d "@$(SOURCE_DATE_EPOCH)" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u +"%Y-%m-%dT%H:%M:%SZ")

GO_PKG:=github.com/wangwanjie/gately
GO_PKG_BUILD_PKG:=$(GO_PKG)/cmd/gately
GO_PKG_LDFLAGS_X:=\
	$(GO_PKG)/internal/version.Version=v$(PKG_VERSION) \
	$(GO_PKG)/internal/version.Commit=$(PKG_VERSION) \
	$(GO_PKG)/internal/version.BuildDate=$(BUILD_DATE)

include $(INCLUDE_DIR)/package.mk
include $(TOPDIR)/feeds/packages/lang/golang/golang-package.mk

define Package/gately
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=Web Servers/Proxies
  TITLE:=Open-source network gateway toolkit (Lucky alternative)
  URL:=https://github.com/wangwanjie/gately
  DEPENDS:=$(GO_ARCH_DEPENDS) +ca-bundle
endef

define Package/gately/description
  Gately is an open-source, auditable network gateway toolkit inspired by Lucky.
  It integrates DDNS, STUN NAT traversal, port forwarding, reverse proxy,
  ACME SSL certificates, WAF (Coraza + OWASP CRS), Wake-on-LAN, WebDAV, FTP,
  Web Terminal, scheduled tasks, and more in a single binary.
endef

define Package/gately/conffiles
/etc/gately/
/etc/config/gately
endef

define Build/Compile
	( \
		export HOME="$(PKG_BUILD_DIR)/web/.home" ; \
		export PNPM_HOME="$(PKG_BUILD_DIR)/web/.pnpm" ; \
		pushd "$(PKG_BUILD_DIR)/web" ; \
		pnpm install --frozen-lockfile ; \
		pnpm run build ; \
		popd ; \
		$(call GoPackage/Build/Compile) ; \
	)
endef

define Package/gately/install
	$(call GoPackage/Package/Install/Bin,$(1))

	$(INSTALL_DIR) $(1)/etc/gately
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) $(CURDIR)/files/gately.config $(1)/etc/config/gately
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) $(CURDIR)/files/gately.init $(1)/etc/init.d/gately
endef

$(eval $(call GoBinPackage,gately))
$(eval $(call BuildPackage,gately))
