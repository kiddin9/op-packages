# SPDX-License-Identifier: GPL-3.0-only
#
# Copyright (C) 2021 ImmortalWrt.org

include $(TOPDIR)/rules.mk

PKG_NAME:=cloudflared-next
PKG_VERSION:=2026.9.3
PKG_RELEASE:=2

# Architecture mapping for pre-built binaries
ifeq ($(ARCH),x86_64)
	CF_ARCH:=amd64
endif
ifeq ($(ARCH),aarch64)
	CF_ARCH:=arm64
endif
ifeq ($(ARCH),arm64)
	CF_ARCH:=arm64
endif
ifeq ($(ARCH),armv8)
	CF_ARCH:=arm64
endif
ifeq ($(ARCH),arm)
	CF_ARCH:=arm
endif
ifeq ($(ARCH),armv7)
	CF_ARCH:=arm
endif
ifeq ($(ARCH),i386)
	CF_ARCH:=386
endif

PKG_SOURCE:=cloudflared-linux-$(CF_ARCH)-$(PKG_VERSION)
PKG_SOURCE_URL:=https://github.com/cloudflare/cloudflared/releases/download/$(PKG_VERSION)/cloudflared-linux-$(CF_ARCH)?
PKG_HASH:=skip

PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)-$(PKG_VERSION)

PKG_LICENSE:=Apache-2.0
PKG_LICENSE_FILES:=LICENSE
PKG_MAINTAINER:=Tianling Shen <cnsztl@immortalwrt.org>

include $(INCLUDE_DIR)/package.mk

define Package/cloudflared-next
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=Web Servers/Proxies
  TITLE:=Cloudflare Tunnel client Next - Pre-built Binary
  URL:=https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/get-started/
  DEPENDS:=@(x86_64||aarch64||arm||i386) +ca-bundle
  PROVIDES:=cloudflared
  CONFLICTS:=cloudflared
endef

define Package/cloudflared-next/description
  Contains the command-line client for Cloudflare Tunnel, a tunneling
  daemon that proxies traffic from the Cloudflare network to your origins.
  This package contains official pre-built static binaries.
endef

define Package/cloudflared-next/conffiles
/etc/config/cloudflared
/etc/cloudflared/
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
	$(CP) $(DL_DIR)/$(PKG_SOURCE) $(PKG_BUILD_DIR)/cloudflared
	chmod 0755 $(PKG_BUILD_DIR)/cloudflared
endef

define Build/Compile
endef

define Package/cloudflared-next/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/cloudflared $(1)/usr/bin/cloudflared

	$(INSTALL_DIR) $(1)/etc/cloudflared/
	$(INSTALL_CONF) $(CURDIR)/files/sample_config.yml $(1)/etc/cloudflared/config.yml
	$(INSTALL_DIR) $(1)/etc/config/
	$(INSTALL_CONF) $(CURDIR)/files/cloudflared.config $(1)/etc/config/cloudflared
	$(INSTALL_DIR) $(1)/etc/init.d/
	$(INSTALL_BIN) $(CURDIR)/files/cloudflared.init $(1)/etc/init.d/cloudflared
endef

$(eval $(call BuildPackage,cloudflared-next))
