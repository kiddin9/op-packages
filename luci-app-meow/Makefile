include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-meow

# Keep in sync with meow/Makefile.
PKG_BASE_VERSION?=0.21.2

# Rewritten automatically by .github/workflows/sync-upstream.yml; the LuCI
# package always carries the same version as the core it drives.
PKG_VERSION?=$(PKG_BASE_VERSION).202610010807
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

  Adds Services -> meow (Overview, Panel, Configuration, Clients, Settings,
  Log). Runtime data comes from the meow REST API through authenticated LuCI
  RPC; curl is only used against the router's loopback API.
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
