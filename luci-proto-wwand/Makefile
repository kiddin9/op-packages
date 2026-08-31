#
# LuCI network-manager protocol handler for the wwand modem daemon.
# Registers only the 'wwand' protocol UI (protocol/wwand.js). It deliberately
# does NOT ship a 'qmi' alias: `proto qmi` stays with luci-proto-qmi/uqmi (no
# file collision, good-citizen coexistence), and interfaces are moved to
# `proto wwand` via the migration list in the LuCI modem page.
#
# Sources live in https://github.com/ddimension/luci-proto-wwand — bump
# PKG_SOURCE_VERSION (and PKG_SOURCE_DATE) to pick up new source commits.
#
# NOTE: this is built from a git PKG_SOURCE, so it does NOT use luci.mk. luci.mk
# gates its htdocs/root install on those directories living NEXT TO the Makefile
# (in-tree); for a git-fetched source they only exist under $(PKG_BUILD_DIR), so
# luci.mk produces an EMPTY package. We install explicitly from $(PKG_BUILD_DIR),
# exactly like the wwand package in this feed.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=luci-proto-wwand
PKG_RELEASE:=5

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/ddimension/luci-proto-wwand.git
PKG_SOURCE_VERSION:=35f0323f5621eb06e69991f5819ff53e4ca8cc7a
PKG_SOURCE_DATE:=2026-08-31
PKG_MIRROR_HASH:=skip

PKG_LICENSE:=GPL-2.0-only
PKG_MAINTAINER:=

include $(INCLUDE_DIR)/package.mk

define Package/luci-proto-wwand
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=4. Protocols
  TITLE:=Support for QMI/5G cellular modems (wwand)
  # This handler uses five resource modules that luci-app-wwand ships —
  # wwand.bands, .format, .modemopts, .modemsid and .rpc — so it depends on
  # the app rather than carrying a second copy of them.
  DEPENDS:=+luci-base +wwand +luci-app-wwand
  PKGARCH:=all
endef

define Package/luci-proto-wwand/description
  LuCI protocol handler for the wwand cellular modem daemon: the network-native
  'wwand' proto plus the legacy 'qmi' alias.
endef

define Build/Compile
endef

define Package/luci-proto-wwand/install
	$(INSTALL_DIR) $(1)/www/luci-static/resources/protocol
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/htdocs/luci-static/resources/protocol/*.js \
		$(1)/www/luci-static/resources/protocol/
	$(INSTALL_DIR) $(1)/usr/share/rpcd/acl.d
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/root/usr/share/rpcd/acl.d/*.json \
		$(1)/usr/share/rpcd/acl.d/
endef

$(eval $(call BuildPackage,luci-proto-wwand))
