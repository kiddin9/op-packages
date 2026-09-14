include $(TOPDIR)/rules.mk

PKG_NAME:=shadowsocks-rust-next
PKG_VERSION:=1.25.0
PKG_RELEASE:=1

# Architecture mapping to match shadowsocks-rust release naming
ifeq ($(ARCH),x86_64)
	SS_ARCH:=x86_64-unknown-linux-musl
endif
ifeq ($(ARCH),aarch64)
	SS_ARCH:=aarch64-unknown-linux-musl
endif
ifeq ($(ARCH),arm)
	SS_ARCH:=armv7-unknown-linux-musleabihf
endif
ifeq ($(ARCH),i386)
	SS_ARCH:=i686-unknown-linux-musl
endif
ifeq ($(ARCH),mipsel)
	SS_ARCH:=mips-unknown-linux-musl
endif

PKG_SOURCE:=shadowsocks-v$(PKG_VERSION).$(SS_ARCH).tar.xz
PKG_SOURCE_URL:=https://github.com/shadowsocks/shadowsocks-rust/releases/download/v$(PKG_VERSION)/
PKG_HASH:=skip

PKG_MAINTAINER:=Dante <dante@example.com>
PKG_LICENSE:=MIT
PKG_LICENSE_FILES:=LICENSE

PKG_BUILD_DIR:=$(BUILD_DIR)/shadowsocks-v$(PKG_VERSION).$(SS_ARCH)

include $(INCLUDE_DIR)/package.mk

define Package/shadowsocks-rust-next/Default
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=Web Servers/Proxies
  TITLE:=shadowsocks-rust (Next)
  URL:=https://github.com/shadowsocks/shadowsocks-rust
  DEPENDS:=@(i386||x86_64||arm||aarch64||mipsel||mips)
endef

define Package/shadowsocks-rust-ssserver-next
  $(call Package/shadowsocks-rust-next/Default)
  TITLE+= (ssserver)
  PROVIDES:=shadowsocks-rust-ssserver
  CONFLICTS:=shadowsocks-rust-ssserver
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
	tar -C $(PKG_BUILD_DIR) -xf $(DL_DIR)/$(PKG_SOURCE)
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/shadowsocks-rust-ssserver-next/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/ssserver $(1)/usr/bin/
endef

define Package/shadowsocks-rust-sslocal-next
  $(call Package/shadowsocks-rust-next/Default)
  TITLE+= (sslocal)
  PROVIDES:=shadowsocks-rust-sslocal
  CONFLICTS:=shadowsocks-rust-sslocal
endef

define Package/shadowsocks-rust-sslocal-next/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/sslocal $(1)/usr/bin/
endef

$(eval $(call BuildPackage,shadowsocks-rust-ssserver-next))
$(eval $(call BuildPackage,shadowsocks-rust-sslocal-next))
