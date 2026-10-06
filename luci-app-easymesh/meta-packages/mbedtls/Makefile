include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-easymesh-wpad-mbedtls
PKG_VERSION:=2.4.1
PKG_RELEASE:=1

PKG_LICENSE:=GPL-2.0
PKG_MAINTAINER:=Arafat Rahman Zami Mondol <arafatrahmanzami@users.noreply.github.com>

include $(INCLUDE_DIR)/package.mk

define Package/luci-app-easymesh-wpad-mbedtls
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  TITLE:=EasyMesh — install with wpad-mesh-mbedtls
  DEPENDS:=+luci-app-easymesh +wpad-mesh-mbedtls
  PKGARCH:=all
endef

define Build/Compile
endef

define Package/luci-app-easymesh-wpad-mbedtls/install
	# Meta-package — no files.
endef

$(eval $(call BuildPackage,luci-app-easymesh-wpad-mbedtls))
