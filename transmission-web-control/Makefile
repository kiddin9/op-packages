include $(TOPDIR)/rules.mk

PKG_NAME:=transmission-web-control
PKG_RELEASE:=4

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/QuickBox/transmission-web-control
PKG_SOURCE_DATE:=2026-10-10
PKG_SOURCE_VERSION:=a2818c1fcc013e1b751ec228a20f64976a90d4cf
PKG_MIRROR_HASH:=skip

PKG_LICENSE:=MIT
PKG_LICENSE_FILES:=LICENSE
PKG_MAINTAINER:=Richard Yu <yurichard3839@gmail.com>

include $(INCLUDE_DIR)/package.mk

define Package/transmission-web-control
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=BitTorrent
  DEPENDS:=+transmission-daemon
  TITLE:=A custom web UI for Transmission
  URL:=https://github.com/ronggang/transmission-web-control
  PKGARCH:=all
endef

define Package/transmission-web-control/description
 Transmission Web Control is a custom Web UI for Transmission.
endef

define Build/Compile
endef

define Package/transmission-web-control/install
	$(INSTALL_DIR) $(1)/usr/share/transmission/public_html
	$(CP) $(PKG_BUILD_DIR)/src/* $(1)/usr/share/transmission/public_html
endef

$(eval $(call BuildPackage,transmission-web-control))
