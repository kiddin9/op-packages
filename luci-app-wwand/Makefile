#
# LuCI status & settings app for the wwand modem daemon: the modem status page,
# the Modems editor, live settings, and the shared resources (wwand.bands /
# wwand.modemopts / wwand.simlist) reused by the proto handler.
#
# Sources live in https://github.com/ddimension/luci-app-wwand — bump
# PKG_SOURCE_VERSION (and PKG_SOURCE_DATE) to pick up new source commits.
#
# NOTE: built from a git PKG_SOURCE, so it does NOT use luci.mk — luci.mk's
# htdocs/root install is gated on those dirs living next to the Makefile
# (in-tree), which yields an EMPTY package for a git-fetched source. We install
# explicitly from $(PKG_BUILD_DIR), like the wwand package in this feed.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-wwand
PKG_RELEASE:=3

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/ddimension/luci-app-wwand.git
PKG_SOURCE_VERSION:=c9c2e1870b094cdc7bdd9013a7e4862e030b9500
PKG_SOURCE_DATE:=2026-08-23
PKG_MIRROR_HASH:=skip

PKG_LICENSE:=GPL-2.0-only
PKG_MAINTAINER:=

include $(INCLUDE_DIR)/package.mk

define Package/luci-app-wwand
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  TITLE:=wwand cellular modem status & settings
  DEPENDS:=+luci-base +wwand
  PKGARCH:=all
endef

define Package/luci-app-wwand/description
  LuCI status and configuration app for the wwand cellular modem daemon.
endef

define Build/Compile
endef

define Package/luci-app-wwand/install
	$(INSTALL_DIR) $(1)/www/luci-static/resources
	$(CP) $(PKG_BUILD_DIR)/htdocs/luci-static/resources/* \
		$(1)/www/luci-static/resources/
	$(INSTALL_DIR) $(1)/usr/share/luci/menu.d
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/root/usr/share/luci/menu.d/*.json \
		$(1)/usr/share/luci/menu.d/
	$(INSTALL_DIR) $(1)/usr/share/rpcd/acl.d
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/root/usr/share/rpcd/acl.d/*.json \
		$(1)/usr/share/rpcd/acl.d/
endef

$(eval $(call BuildPackage,luci-app-wwand))
