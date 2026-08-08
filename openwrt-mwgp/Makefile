include $(TOPDIR)/rules.mk

PKG_NAME:=mwgp
PKG_VERSION:=2.1.7
PKG_RELEASE:=2

PKG_SOURCE_PROTO:=git
PKG_SOURCE:=v$(PKG_VERSION).tar.gz
PKG_SOURCE_URL:=https://github.com/apernet/mwgp
PKG_SOURCE_VERSION:=bd3cbaa3b81f0b081c425de9ac15a54a6da5ef9a
PKG_HASH:=skip

PKG_MAINTAINER:=Apernet
PKG_LICENSE:=GPL-3.0

PKG_BUILD_DEPENDS:=golang/host
include $(INCLUDE_DIR)/package.mk
include $(TOPDIR)/feeds/packages/lang/golang/golang-package.mk

define Package/mwgp
	SECTION:=net
	CATEGORY:=Network
	SUBMENU:=Web Servers/Proxies
	TITLE:=Multiple WireGuard Proxy
	URL:=https://github.com/apernet/mwgp
	DEPENDS:=$(GO_ARCH_DEPENDS)
endef

define Package/mwgp/description
	A high-performance Multiple WireGuard Proxy server and client.
endef

define Build/Compile
	GOOS=linux go build -ldflags "-s -w" -o mwgp ./cmd/mwgp
endef

define Package/mwgp/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/cmd/mwgp $(1)/usr/bin/
endef

$(eval $(call GoBinPackage,mwgp))
$(eval $(call BuildPackage,mwgp))
											  
