include $(TOPDIR)/rules.mk

PKG_NAME:=mwgp
PKG_VERSION:=2.1.7
PKG_RELEASE:=3

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/apernet/mwgp
PKG_SOURCE_VERSION:=bd3cbaa3b81f0b081c425de9ac15a54a6da5ef9a
PKG_MIRROR_HASH:=skip

PKG_MAINTAINER:=Apernet
PKG_LICENSE:=GPL-3.0
PKG_LICENSE_FILES:=LICENSE

PKG_BUILD_DEPENDS:=golang/host
PKG_BUILD_PARALLEL:=1
PKG_USE_MIPS16:=0

include $(INCLUDE_DIR)/package.mk

define Package/mwgp
	SECTION:=net
	CATEGORY:=Network
	SUBMENU:=VPN
	TITLE:=Multiple WireGuard Proxy
	URL:=https://github.com
	DEPENDS:=+ca-bundle
endef

define Package/mwgp/description
	mwgp is a proxy software for WireGuard traffic that supports port 
	multiplexing and experimental traffic obfuscation.
endef

# --- UNIVERSAL ARCHITECTURE TRANSLATION ---
# Go uses 'arm64' instead of 'aarch64'. This block detects aarch64 
# and safely translates it, otherwise it passes your SDK's $(ARCH) right to Go.
ifeq ($(ARCH),aarch64)
  TARGET_GOARCH:=arm64
else
  TARGET_GOARCH:=$(ARCH)
endif

# Size Minimization Magic (-s and -w shrink the router binary size)
GO_LDFLAGS:=-s -w

define Build/Compile
	# 1. Clear out any old target files
	rm -f $(PKG_BUILD_DIR)/mwgp
	
	# 2. Compile using the SDK's architecture target variables dynamically
	cd $(PKG_BUILD_DIR); \
		$(TARGET_CONFIGURE_OPTS) \
		GOOS=linux \
		GOARCH=$(TARGET_GOARCH) \
		CGO_ENABLED=0 \
		GO111MODULE=on \
		/usr/bin/go build \
			-v \
			-ldflags="$(GO_LDFLAGS)" \
			-o $(PKG_BUILD_DIR)/mwgp \
			./cmd/mwgp
endef

define Package/mwgp/install
	$(INSTALL_DIR) $(1)/usr/bin
	# Safely copy the explicitly generated router binary
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/mwgp $(1)/usr/bin/mwgp

	$(INSTALL_DIR) $(1)/etc/init.d/
	$(INSTALL_BIN) ./files/mwgp.init $(1)/etc/init.d/mwgp
	
	$(INSTALL_DIR) $(1)/etc/config/
	$(INSTALL_DATA) ./files/mwgp.config $(1)/etc/config/mwgp
endef

$(eval $(call BuildPackage,mwgp))
