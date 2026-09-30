include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-meow
PKG_VERSION?=0.21.2
PKG_RELEASE?=1

include $(INCLUDE_DIR)/package.mk

PKG_MAINTAINER:=Independent meow OpenWrt package <noreply@example.invalid>

define Package/luci-app-meow
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  TITLE:=LuCI support for meow
  URL:=https://github.com/meow-rs/meow-rs
  LICENSE:=MIT
  DEPENDS:=+luci-base +meow +curl
  PKGARCH:=all
endef

define Package/luci-app-meow/description
  LuCI interface for the meow OpenWrt package.
endef

define Build/Prepare
endef

define Build/Compile
endef

define Package/luci-app-meow/install
	$(INSTALL_DIR) $(1)
	cp -a ./root/. $(1)/
	$(INSTALL_DIR) $(1)/www/luci-static
	cp -a ./htdocs/luci-static/. $(1)/www/luci-static/
	find $(1)/usr/libexec -type f -exec chmod 0755 {} + 2>/dev/null || true
endef

$(eval $(call BuildPackage,luci-app-meow))
