#
# Copyright (C) 2024 sbwml <admin@cooluc.com>
# Copyright (c) 2025-2026 sirpdboy <herboy2008@gmail.com>
#
# This is free software, licensed under the GPL-3.0 License.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=ookla-speedtest
PKG_VERSION:=1.2.0
PKG_RELEASE:=3

ifeq ($(ARCH),aarch64)
  PKG_ARCH_SUFFIX:=aarch64
  PKG_HASH:=skip
else ifeq ($(ARCH),arm)
    ARM_CPU_FEATURES:=$(word 2,$(subst +,$(space),$(call qstrip,$(CONFIG_CPU_TYPE))))
  ifeq ($(ARM_CPU_FEATURES),)
    PKG_ARCH_SUFFIX:=armel
    PKG_HASH:=skip
  else
    PKG_ARCH_SUFFIX:=armhf
    PKG_HASH:=skip
  endif
else ifeq ($(ARCH),i386)
  PKG_ARCH_SUFFIX:=i386
  PKG_HASH:=skip
else ifeq ($(ARCH),x86_64)
  PKG_ARCH_SUFFIX:=x86_64
  PKG_HASH:=skip
endif

PKG_SOURCE:=ookla-speedtest-$(PKG_VERSION)-linux-$(PKG_ARCH_SUFFIX).tgz
PKG_SOURCE_URL:=https://install.speedtest.net/app/cli
PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)-$(PKG_VERSION)-$(PKG_ARCH_SUFFIX)

PKG_MAINTAINER:=sbwml <admin@cooluc.com>
include $(INCLUDE_DIR)/package.mk

define Package/$(PKG_NAME)
	SECTION:=net
	CATEGORY:=Network
	SUBMENU:=Speed Test
	TITLE:=Speedtest CLI by Ookla
	URL:=https://www.speedtest.net/
	DEPENDS:=@(aarch64||arm||i386||x86_64) +ca-certificates
	URL:=https://www.speedtest.net/
endef

define Package/$(PKG_NAME)/description
  Speedtest CLI by Ookla is the official command line client
  for testing internet bandwidth using speedtest.net servers.
endef


define Build/Prepare
	( \
		pushd $(PKG_BUILD_DIR) ; \
			$(TAR) -zxf $(DL_DIR)/ookla-speedtest-$(PKG_VERSION)-linux-$(PKG_ARCH_SUFFIX).tgz -C . ; \
		popd ; \
	)
endef

define Build/Compile
endef

define Package/$(PKG_NAME)/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/speedtest $(1)/usr/bin/ookla-speedtest
endef

$(eval $(call BuildPackage,$(PKG_NAME)))