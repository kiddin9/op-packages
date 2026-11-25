# SPDX-License-Identifier: GPL-2.0-only
#
# Copyright (C) 2024-2026 OpenWrt.org
#

include $(TOPDIR)/rules.mk

PKG_NAME:=clouddrive2
PKG_VERSION:=1.1.3
PKG_RELEASE:=7

ifeq ($(ARCH),aarch64)
	CD2_ARCH:=aarch64
	PKG_HASH:=skip
else ifeq ($(ARCH),arm)
	CD2_ARCH:=armv7
	PKG_HASH:=skip
else ifeq ($(ARCH),x86_64)
	CD2_ARCH:=x86_64
	PKG_HASH:=skip
endif

PKG_SOURCE:=clouddrive-2-linux-$(CD2_ARCH)-$(PKG_VERSION).tgz
PKG_SOURCE_URL:=https://github.com/cloud-fs/cloud-fs.github.io/releases/download/v$(PKG_VERSION)
PKG_LICENSE:=Proprietary

include $(INCLUDE_DIR)/package.mk

RSTRIP:=:
STRIP:=:

define Package/clouddrive2
  SECTION:=net
  CATEGORY:=Network
  TITLE:=CloudDrive2 multi-cloud storage service
  URL:=https://www.clouddrive2.com/
  DEPENDS:=@(arm||aarch64||x86_64) +fuse3-utils +kmod-fuse +ca-bundle
endef

define Package/clouddrive2/description
  CloudDrive2 is a multi-cloud storage management and FUSE local mounting service for OpenWrt.
endef

define Package/clouddrive2/conffiles
/etc/config/clouddrive2
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
	$(HOST_TAR) -xzf $(DL_DIR)/$(PKG_SOURCE) -C $(PKG_BUILD_DIR)
endef

define Build/Compile
endef

define Package/clouddrive2/install
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) $(CURDIR)/files/clouddrive2.init $(1)/etc/init.d/clouddrive2

	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) $(CURDIR)/files/clouddrive2.config $(1)/etc/config/clouddrive2

	$(INSTALL_DIR) $(1)/usr/share/clouddrive2
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/clouddrive-2-linux-$(CD2_ARCH)-$(PKG_VERSION)/clouddrive $(1)/usr/share/clouddrive2/clouddrive
	$(CP) $(PKG_BUILD_DIR)/clouddrive-2-linux-$(CD2_ARCH)-$(PKG_VERSION)/wwwroot $(1)/usr/share/clouddrive2/
endef

$(eval $(call BuildPackage,clouddrive2))
