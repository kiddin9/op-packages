include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-meow
PKG_VERSION?=0.0.0
PKG_RELEASE?=0

include $(INCLUDE_DIR)/package.mk

PKG_MAINTAINER:=Independent meow OpenWrt package <noreply@example.invalid>

# LuCI is architecture-independent; its companion "meow" package contains
# the target-specific Rust core.

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
  LuCI interface shipped from the upstream meow OpenWrt tree.
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
