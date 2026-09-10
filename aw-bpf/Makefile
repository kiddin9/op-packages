#
# Copyright (C) 2025 Dengfeng Liu
#
# This is free software, licensed under the GNU General Public License v3.
# See /LICENSE for more information.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=aw-bpf
PKG_VERSION:=1.08.23
PKG_RELEASE:=1

PKG_SOURCE:=aw-bpf-$(PKG_VERSION).tar.gz
PKG_SOURCE_URL:=https://codeload.github.com/liudf0716/$(PKG_NAME)/tar.gz/$(PKG_VERSION)?
PKG_HASH:=skip
PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)-$(PKG_VERSION)

PKG_MAINTAINER:=Dengfeng Liu <liudf0716@gmail.com>
PKG_LICENSE:=GPL-2.0-or-later
PKG_LICENSE_FILES:=LICENSE

PKG_BUILD_DEPENDS:=bpf-headers

include $(INCLUDE_DIR)/package.mk
include $(INCLUDE_DIR)/cmake.mk
include $(INCLUDE_DIR)/bpf.mk
include $(INCLUDE_DIR)/kernel.mk

define Package/aw-bpf
  SECTION:=net
  CATEGORY:=Network
  TITLE:=ApFree eBPF programs and tools
  DEPENDS:=+libbpf +libelf +libjson-c +libmnl +libnftnl +tc-full +bpftool-minimal +ip +kmod-xdpi +kmod-sched-bpf $(BPF_DEPENDS)
  URL:=https://github.com/liudf0716/aw-bpf
endef

define Package/aw-bpf/description
	ApFree eBPF provides eBPF programs for session tracking, xDPI, DNS monitoring
	and user-space tools: aw-bpfctl (control CLI) and aw-eventd (session / DNS
	consumer with independent nftables table inet awbpf).
endef


define KernelPackage/xdpi
  SECTION:=kernel
  SUBMENU:=Network Support
  TITLE:=xdpi ebpf module
  FILES:=$(PKG_BUILD_DIR)/xdpi_bpf.ko
  AUTOLOAD:=$(call AutoProbe,xdpi_bpf)
endef

# Build cmake userspace first (aw-bpfctl, aw-eventd), then BPF objects and kmod.
define Build/Compile
	$(call Build/Compile/Default)
	$(call CompileBPF,$(PKG_BUILD_DIR)/aw_bpf.c,$(if $(filter arm aarch64 x86_64 i386,$(ARCH)),-DENABLE_XDPI_FEATURE))
	$(call CompileBPF,$(PKG_BUILD_DIR)/dns_bpf.c,$(if $(filter arm aarch64 x86_64 i386,$(ARCH)),-DENABLE_XDPI_FEATURE))
	$(KERNEL_MAKE) M=$(PKG_BUILD_DIR) modules
endef

define Package/aw-bpf/conffiles
/etc/config/aw-bpf
endef

define Package/aw-bpf/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/aw-bpfctl $(1)/usr/bin/aw-bpfctl
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/aw-eventd $(1)/usr/bin/aw-eventd
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/aw-bpf.init $(1)/etc/init.d/aw-bpf
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./files/aw-bpf.conf $(1)/etc/config/aw-bpf
	$(INSTALL_DIR) $(1)/lib/bpf
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/aw_bpf.o $(1)/lib/bpf/aw-bpf.o
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/dns_bpf.o $(1)/lib/bpf/dns-bpf.o
endef

$(eval $(call BuildPackage,aw-bpf))
$(eval $(call KernelPackage,xdpi))
