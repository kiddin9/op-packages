include $(TOPDIR)/rules.mk

PKG_NAME:=mwgp
PKG_VERSION:=2.1.7
PKG_RELEASE:=5

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/apernet/mwgp
PKG_SOURCE_VERSION:=bd3cbaa3b81f0b081c425de9ac15a54a6da5ef9a
PKG_MIRROR_HASH:=skip

PKG_MAINTAINER:=Apernet
PKG_LICENSE:=MIT
PKG_LICENSE_FILES:=LICENSE

PKG_BUILD_DEPENDS:=golang/host
PKG_BUILD_PARALLEL:=1
PKG_USE_MIPS16:=0

include $(INCLUDE_DIR)/package.mk
# Absolute environment lookup reference
include $(TOPDIR)/feeds/packages/lang/golang/golang-package.mk

define Package/mwgp
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=VPN
  TITLE:=Multiple WireGuard Proxy
  URL:=https://github.com
  DEPENDS:=$(GO_ARCH_DEPENDS) +ca-bundle
endef

define Package/mwgp/description
  mwgp is a proxy software for WireGuard traffic that supports port 
  multiplexing and experimental traffic obfuscation.
endef

# Setup build targets pointing to the sub-folder module logic
GO_PKG:=://github.com
GO_PKG_BUILD_PKG:=$(GO_PKG)/cmd/mwgp
GO_PKG_LDFLAGS:=-s -w

# FIXED: Explicitly tell OpenWrt to compile this using the Go pipeline macro 
# instead of falling back to running a standard Makefile 'make' loop.
define Build/Compile
	$(call GoPackage/Golang/Build/Compile)
enddefine

define Package/mwgp/install
	$(INSTALL_DIR) $(1)/usr/bin
	# Safely capture the compiled Go binary from the architecture build directory
	$(INSTALL_BIN) $(GO_PKG_BUILD_BIN_DIR)/mwgp $(1)/usr/bin/mwgp

	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/mwgp.init $(1)/etc/init.d/mwgp
	
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_DATA) ./files/mwgp.config $(1)/etc/config/mwgp
endef

$(eval $(call GoBinPackage,mwgp))
$(eval $(call BuildPackage,mwgp))
