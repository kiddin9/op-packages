include $(TOPDIR)/rules.mk

PKG_NAME:=mwgp
PKG_VERSION:=2.1.7
PKG_RELEASE:=1

PKG_SOURCE_PROTO:=git
PKG_SOURCE:=v$(PKG_VERSION).tar.gz
PKG_SOURCE_URL:=https://github.com/apernet/mwgp
PKG_SOURCE_VERSION:=bd3cbaa3b81f0b081c425de9ac15a54a6da5ef9a
PKG_HASH:=skip

PKG_LICENSE:=GPL-3.0-only
PKG_LICENSE_FILES:=LICENSE
PKG_MAINTAINER:=Your Name <your.email@example.com>

PKG_BUILD_DEPENDS:=golang/host
PKG_BUILD_PARALLEL:=1
PKG_BUILD_FLAGS:=no-mips16

GO_PKG:=github.com/apernet/mwgp

include $(INCLUDE_DIR)/package.mk
include $(TOPDIR)/feeds/packages/lang/golang/golang-package.mk

define Package/mwgp
  SECTION:=net
  CATEGORY:=Network
  TITLE:=Multiple WireGuard Proxy
  URL:=https://github.com/apernet/mwgp
endef

define Package/mwgp/description
  mwgp (Multiple WireGuard Proxy) is a proxy designed to multiplex and accelerate WireGuard traffic.
endef

#define Build/Compile
	#GOOS=linux GOARCH=arm64 go build -ldflags "-s -w" -o mwgp ./cmd/mwgp
#endef

define Package/mwgp/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/cmd/mwgp $(1)/usr/bin/
endef

$(eval $(call BuildPackage,mwgp))
