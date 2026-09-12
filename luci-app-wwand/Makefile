#
# LuCI status & settings app for the wwand modem daemon: the modem status page,
# the Modems editor, live settings, and the shared resources (wwand.bands /
# wwand.modemopts / wwand.simlist) reused by the proto handler.
#
# Sources live in https://github.com/ddimension/luci-app-wwand, tagged vX.Y.Z
# together with wwand. Pin a new commit with
# `scripts/bump-source.sh luci-app-wwand <tag|commit>`: it derives PKG_VERSION
# (X.Y.Z at a tag, X.Y.Z_pN after it), PKG_RELEASE and the mirror hash.
#
# NOTE: built from a git PKG_SOURCE, so it does NOT use luci.mk — luci.mk's
# htdocs/root install is gated on those dirs living next to the Makefile
# (in-tree), which yields an EMPTY package for a git-fetched source. We install
# explicitly from $(PKG_BUILD_DIR), like the wwand package in this feed.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-wwand
PKG_VERSION:=1.6.6_p7
PKG_RELEASE:=19

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/ddimension/luci-app-wwand.git
PKG_SOURCE_VERSION:=ef4b59a891229d189ad5167def96eab22a5ceb03
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

define Package/luci-app-wwand-statistics
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  TITLE:=wwand graphs for luci-app-statistics
  DEPENDS:=+luci-app-statistics +wwand
  PKGARCH:=all
endef

define Package/luci-app-wwand-statistics/description
  RRD graph definitions for the data `wwandctl collectd` feeds into collectd:
  signal strength, band power, quality, SINR, modem temperature and state, one
  line per radio technology.

  Split out because it drops a file into luci-app-statistics' own resource tree,
  which is only meaningful when that app is installed — luci-app-statistics
  lists that directory at runtime, so nothing over there has to know about us.

  Feeding it needs no extra package at all:

      config statistics 'collectd_exec'
              option enable '1'

      config collectd_exec_input
              option cmdline '/usr/bin/wwandctl collectd'
endef

# Named, not globbed. The same rule the wwand package follows for its ucode
# sources: a wildcard install silently ships whatever happens to be in the tree,
# so a file added for one package lands in another — which is exactly how the
# statistics graph definition would have been installed on boxes with no
# luci-app-statistics. A new resource has to be added here, and that is the
# point of listing them.
LUCI_WWAND_VIEW:=modems.js settings.js status.js
LUCI_WWAND_RES:=bands.js esim.js format.js graph.js logbox.js mccmnc.js \
	modemopts.js modemsid.js netsel.js rpc.js signal.svg simlist.js

define Package/luci-app-wwand/install
	$(INSTALL_DIR) $(1)/www/luci-static/resources/view/wwand
	$(INSTALL_DIR) $(1)/www/luci-static/resources/wwand
	for f in $(LUCI_WWAND_VIEW); do \
		$(INSTALL_DATA) $(PKG_BUILD_DIR)/htdocs/luci-static/resources/view/wwand/$$$$f \
			$(1)/www/luci-static/resources/view/wwand/ ; \
	done
	for f in $(LUCI_WWAND_RES); do \
		$(INSTALL_DATA) $(PKG_BUILD_DIR)/htdocs/luci-static/resources/wwand/$$$$f \
			$(1)/www/luci-static/resources/wwand/ ; \
	done
	$(INSTALL_DIR) $(1)/usr/share/luci/menu.d
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/root/usr/share/luci/menu.d/luci-app-wwand.json \
		$(1)/usr/share/luci/menu.d/
	$(INSTALL_DIR) $(1)/usr/share/rpcd/acl.d
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/root/usr/share/rpcd/acl.d/luci-app-wwand.json \
		$(1)/usr/share/rpcd/acl.d/
endef

define Package/luci-app-wwand-statistics/install
	$(INSTALL_DIR) $(1)/www/luci-static/resources/statistics/rrdtool/definitions
	$(INSTALL_DATA) \
		$(PKG_BUILD_DIR)/htdocs/luci-static/resources/statistics/rrdtool/definitions/wwand.js \
		$(1)/www/luci-static/resources/statistics/rrdtool/definitions/
endef

$(eval $(call BuildPackage,luci-app-wwand))
$(eval $(call BuildPackage,luci-app-wwand-statistics))
