# SPDX-License-Identifier: GPL-2.0-only
#
# Copyright (C) 2023 ImmortalWrt.org
# Copyright (C) 2026 QiuSimons <https://github.com/QiuSimons>

include $(TOPDIR)/rules.mk

PKG_NAME:=dae
PKG_VERSION:=2026.11.28~a2cc108
PKG_RELEASE:=63

DAE_SRC_URL:=https://github.com/olicesx/dae.git
DAE_SRC_VERSION:=a2cc10840b6f276a9f2206544fffb69c37da6ed6
DAE_SHORT_VERSION:=$(shell printf '%.7s' "$(DAE_SRC_VERSION)")

PKG_LICENSE:=AGPL-3.0-only
PKG_LICENSE_FILES:=LICENSE
PKG_MAINTAINER:=QiuSimons <https://github.com/QiuSimons>

DAE_ARCH_DEPENDS:=@(aarch64||x86_64)

define Package/dae
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=Web Servers/Proxies
  TITLE:=dae - eBPF transparent proxy engine (kdae branch)
  URL:=https://github.com/olicesx/dae
  DEPENDS:=$(DAE_ARCH_DEPENDS) \
    +ca-bundle +kmod-sched-core +kmod-sched-bpf \
    +kmod-veth +v2ray-geoip +v2ray-geosite \
    +DAE_USE_VMLINUX_BTF:vmlinux-btf
endef

define Package/dae/description
  kdae (olicesx/dae kdae branch) is an eBPF transparent proxy engine with native API support.
  Kernel requirements when building firmware: CONFIG_KERNEL_CGROUP_BPF=y,
  CONFIG_KERNEL_BPF_EVENTS=y, CONFIG_KERNEL_KPROBES=y, CONFIG_KERNEL_KPROBE_EVENTS=y,
  and CONFIG_KERNEL_DEBUG_INFO_BTF=y (or select DAE_USE_VMLINUX_BTF).
  AF_XDP (KERNEL_XDP_SOCKETS) is not used.
endef

define Package/dae/config
	choice
		prompt "BTF source for CO-RE"
		default DAE_USE_KERNEL_BTF
		depends on PACKAGE_dae

	config DAE_USE_KERNEL_BTF
		bool "Use kernel BTF (integrated)"
		depends on KERNEL_DEBUG_INFO_BTF

	config DAE_USE_VMLINUX_BTF
		bool "Use vmlinux-btf package"
	endchoice
endef

ifneq ($(wildcard $(CURDIR)/files/dae.bin),)

include $(INCLUDE_DIR)/package.mk

define Build/Prepare
	mkdir -p "$(PKG_BUILD_DIR)"
endef

define Build/Compile
	"$(CURDIR)/build_dae_core.sh" --if-needed "$(ARCH)" "$(CURDIR)/files/dae.bin"
	$(INSTALL_DIR) "$(PKG_INSTALL_DIR)/bin"
	$(INSTALL_BIN) "$(CURDIR)/files/dae.bin" "$(PKG_INSTALL_DIR)/bin/dae"
endef

define Package/dae/install
	$(INSTALL_DIR) "$(1)/usr/bin"
	$(INSTALL_BIN) "$(PKG_INSTALL_DIR)/bin/dae" "$(1)/usr/bin/dae"
endef

else

PKG_SOURCE:=$(PKG_NAME)-$(PKG_VERSION).tar.gz
PKG_SOURCE_PROTO:=git
PKG_SOURCE_VERSION:=$(DAE_SRC_VERSION)
PKG_SOURCE_URL:=$(DAE_SRC_URL)
PKG_MIRROR_HASH:=skip

PKG_BUILD_DEPENDS:=golang/host bpf-headers
PKG_BUILD_PARALLEL:=1
PKG_BUILD_FLAGS:=no-mips16

GO_PKG:=github.com/daeuniverse/dae
GO_PKG_EXCLUDES:=control/kern/tests

GO_PKG_LDFLAGS:= \
	-s -w -buildid= \
	-linkmode external -extldflags '-static -Wl,-s'
GO_PKG_LDFLAGS_X:= \
	$(GO_PKG)/cmd.Version=$(DAE_SHORT_VERSION) \
	$(GO_PKG)/common/consts.MaxMatchSetLen_=1024
GO_PKG_TAGS:=trace

include $(INCLUDE_DIR)/package.mk
include $(INCLUDE_DIR)/bpf.mk
include $(TOPDIR)/feeds/packages/lang/golang/golang-package.mk

GO_PKG_BUILD_VARS+= \
	GOFLAGS="-trimpath -buildvcs=false -pgo=auto" \
	GOTOOLCHAIN=auto

GO_PKG_TARGET_VARS+= \
	CGO_LDFLAGS="$(TARGET_LDFLAGS) -static -Wl,-s" \
	GOEXPERIMENT=newinliner,simd,heapminimum512kib,randomizedheapbase64

DAE_CFLAGS:= \
	-O2 -Wall -Werror \
	-DMAX_MATCH_SET_LEN=1024 \
	-I$(BPF_HEADERS_DIR)/tools/lib \
	-I$(BPF_HEADERS_DIR)/arch/$(BPF_KARCH)/include/asm/mach-generic

define Build/Prepare
	$(call Build/Prepare/Default)
endef

define Build/Compile
	( \
		pushd "$(PKG_BUILD_DIR)" ; \
		export \
		$(GO_GENERAL_BUILD_CONFIG_VARS) \
		$(GO_PKG_BUILD_CONFIG_VARS) \
		$(GO_PKG_BUILD_VARS) \
		BPF_CLANG="$(CLANG)" \
		BPF_STRIP_FLAG="-strip=$(LLVM_STRIP)" \
		BPF_CFLAGS="$(DAE_CFLAGS)" \
		BPF_TARGET="bpfel,bpfeb" \
		BPF_TRACE_TARGET="$(GO_ARCH)" ; \
		unset GOOS GOARCH GOARM GOAMD64 ; \
		go generate ./common/consts/ebpf.go ; \
		go generate ./control/control.go ; \
		go generate ./trace/trace.go ; \
		popd ; \
	)
	$(call GoPackage/Build/Compile)
endef

define Package/dae/install
	$(call GoPackage/Package/Install/Bin,$(PKG_INSTALL_DIR))
	$(INSTALL_DIR) "$(1)/usr/bin"
	$(INSTALL_BIN) "$(PKG_INSTALL_DIR)/usr/bin/dae" "$(1)/usr/bin/dae"
endef

$(eval $(call GoBinPackage,dae))

endif

$(eval $(call BuildPackage,dae))
