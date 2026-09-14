include $(TOPDIR)/rules.mk

PKG_NAME:=frpc-next
PKG_VERSION:=0.71.0
PKG_RELEASE:=1

# Architecture mapping for pre-built binaries
ifeq ($(ARCH),mipsel)
	FRP_ARCH:=mipsle
endif
ifeq ($(ARCH),mips)
	FRP_ARCH:=mips
endif
ifeq ($(ARCH),i386)
	FRP_ARCH:=386
endif
ifeq ($(ARCH),x86_64)
	FRP_ARCH:=amd64
endif
ifeq ($(ARCH),arm)
	FRP_ARCH:=arm
endif
ifeq ($(ARCH),aarch64)
	FRP_ARCH:=arm64
endif

PKG_SOURCE:=frp_$(PKG_VERSION)_linux_$(FRP_ARCH).tar.gz
PKG_SOURCE_URL:=https://github.com/fatedier/frp/releases/download/v$(PKG_VERSION)/
PKG_HASH:=skip

PKG_LICENSE:=Apache-2.0
PKG_LICENSE_FILES:=LICENSE
PKG_MAINTAINER:=Dante <dante@seckv.com>

PKG_BUILD_DIR:=$(BUILD_DIR)/frp_$(PKG_VERSION)_linux_$(FRP_ARCH)

include $(INCLUDE_DIR)/package.mk

define Package/frpc-next
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=Web Servers/Proxies
  TITLE:=A fast reverse proxy (Client) - Binary
  URL:=https://github.com/fatedier/frp
  DEPENDS:=@(i386||x86_64||arm||aarch64||mipsel||mips)
  PROVIDES:=frpc
  CONFLICTS:=frpc
endef

define Package/frpc-next/description
  frp is a fast reverse proxy to help you expose a local server behind a
  NAT or firewall to the internet. This package contains the pre-built frpc client.
endef

define Build/Compile
endef

define Package/frpc-next/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/frpc $(1)/usr/bin/
endef

$(eval $(call BuildPackage,frpc-next))
