#
# Copyright (C) 2021 CZ.NIC, z. s. p. o. (https://www.nic.cz/)
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=tailscale-next
PKG_VERSION:=1.102.4
PKG_RELEASE:=1

# Architecture mapping for pre-built binaries
ifeq ($(ARCH),x86_64)
	TS_ARCH:=amd64
endif
ifeq ($(ARCH),aarch64)
	TS_ARCH:=arm64
endif
ifeq ($(ARCH),arm64)
	TS_ARCH:=arm64
endif
ifeq ($(ARCH),armv8)
	TS_ARCH:=arm64
endif
ifeq ($(ARCH),arm)
	TS_ARCH:=arm
endif
ifeq ($(ARCH),armv7)
	TS_ARCH:=arm
endif
ifeq ($(ARCH),i386)
	TS_ARCH:=386
endif
ifeq ($(ARCH),mips)
	TS_ARCH:=mips
endif
ifeq ($(ARCH),mipsel)
	TS_ARCH:=mipsle
endif
ifeq ($(ARCH),riscv64)
	TS_ARCH:=riscv64
endif

PKG_SOURCE:=tailscale_$(PKG_VERSION)_$(TS_ARCH).tgz
PKG_SOURCE_URL:=https://pkgs.tailscale.com/stable/
PKG_HASH:=skip

PKG_MAINTAINER:=Dante <dante@seckv.com>
PKG_LICENSE:=BSD-3-Clause
PKG_LICENSE_FILES:=LICENSE
PKG_CPE_ID:=cpe:/a:tailscale:tailscale

PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)-$(PKG_VERSION)

include $(INCLUDE_DIR)/package.mk

define Package/tailscale-next
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=VPN
  TITLE:=Zero config VPN (Next) - Pre-built Binary
  URL:=https://tailscale.com
  DEPENDS:=@(x86_64||aarch64||arm||i386||mips||mipsel||riscv64) +ca-bundle +kmod-tun +iptables
  PROVIDES:=tailscale tailscaled
  CONFLICTS:=tailscale tailscaled
endef

define Package/tailscale-next/description
  It creates a secure network between your servers, computers,
  and cloud instances. Even when separated by firewalls or subnets.
  This package contains official pre-built static binaries.
endef

define Package/tailscale-next/conffiles
/etc/config/tailscale
/etc/tailscale/
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
	tar -xzf $(DL_DIR)/$(PKG_SOURCE) -C $(PKG_BUILD_DIR) --strip-components=1
endef

define Build/Compile
endef

define Package/tailscale-next/install
	$(INSTALL_DIR) $(1)/usr/sbin $(1)/etc/init.d $(1)/etc/config
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/tailscaled $(1)/usr/sbin/tailscaled
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/tailscale $(1)/usr/sbin/tailscale
	$(INSTALL_BIN) ./files/tailscale.init $(1)/etc/init.d/tailscale
	$(INSTALL_DATA) ./files/tailscale.conf $(1)/etc/config/tailscale
endef

$(eval $(call BuildPackage,tailscale-next))
