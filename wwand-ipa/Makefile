#
# eSIM fleet management for wwand: the router as the SGP.32 IoT Profile
# Assistant of an eIM. A wwand PLUGIN (wwand plugins.uc), kept out of the
# wwand sources on purpose: it is not meant for upstream.
#
# Sources live in https://github.com/ddimension/wwand-ipa, tagged vX.Y.Z. Pin
# a new commit with `scripts/bump-source.sh wwand-ipa <tag|commit>`.
#
# Built from a git PKG_SOURCE, so, like luci-app-wwand, installed explicitly
# from $(PKG_BUILD_DIR) and not through luci.mk.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=wwand-ipa
PKG_VERSION:=0.1.0
PKG_RELEASE:=1

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/ddimension/wwand-ipa.git
PKG_SOURCE_VERSION:=fc0fad051213f23d10864f26ebc7205ae5c0a451
PKG_MIRROR_HASH:=skip

PKG_LICENSE:=GPL-2.0-only
PKG_LICENSE_FILES:=LICENSE
PKG_MAINTAINER:=

include $(INCLUDE_DIR)/package.mk

UCDIR:=/usr/share/ucode/wwand

define Package/wwand-ipa
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=WWAN
  TITLE:=eSIM fleet management (SGP.32 eIM) for wwand
  # wwand-esim: its bridge carries the assistant's APDUs; wwand-ipad: the
  # assistant itself (onomondo-ipa with the stdio card backend)
  DEPENDS:=+wwand-esim +wwand-ipad
  PKGARCH:=all
endef

define Package/wwand-ipa/description
 Lets an eIM manage the modem's eSIM: wwand polls it (after the connection
 comes up, then every ipa_interval seconds) with the onomondo-ipa assistant,
 relays the assistant's card traffic over the modem's APDU channel, and after
 a profile change resets the SIM (or the modem) and waits for the session on
 the new profile before the result is reported. Runs against an SGP.22
 consumer eUICC (the assistant's IoT eUICC emulation); the eIM must accept
 that mode. Enable per modem with `wwandctl ipa [modem] eim <file>`. While
 enabled, manual profile changes on that card are refused unless forced.
endef

define Package/luci-app-wwand-ipa
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  TITLE:=eSIM fleet management page for wwand-ipa
  DEPENDS:=+luci-base +wwand-ipa
  PKGARCH:=all
endef

define Package/luci-app-wwand-ipa/description
 Network -> eSIM Fleet: per modem, where the eIM polling stands, what the
 last run did to the card, and a poll on request.
endef

define Build/Compile
endef

# /etc/wwand/ipa holds each card's nvstate (in emulation: its eIM
# configuration and replay counter) and usually the eIM configuration file.
# Losing it in a sysupgrade cuts the card off its eIM, so it is kept through
# keep.d, NOT conffiles: sysupgrade treats conffiles as file+checksum pairs of
# what the package shipped, and these files are created at runtime; keep.d
# entries go through find, which takes the whole directory (base-files
# sbin/sysupgrade list_conffiles / list_static_conffiles, OpenWrt bacda03b76,
# 2026-07-19).
define Package/wwand-ipa/install
	$(INSTALL_DIR) $(1)$(UCDIR)/plugins $(1)$(UCDIR)/ctl
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/plugins/ipa.uc $(1)$(UCDIR)/plugins/
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/ctl/ipa.uc $(1)$(UCDIR)/ctl/
	$(INSTALL_DIR) $(1)/lib/upgrade/keep.d
	echo /etc/wwand/ipa/ > $(1)/lib/upgrade/keep.d/wwand-ipa
endef

# named, not globbed (the rule luci-app-wwand follows)
define Package/luci-app-wwand-ipa/install
	$(INSTALL_DIR) $(1)/www/luci-static/resources/view/wwand $(1)/www/luci-static/resources/wwand
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/luci/htdocs/luci-static/resources/view/wwand/ipa.js \
		$(1)/www/luci-static/resources/view/wwand/
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/luci/htdocs/luci-static/resources/wwand/ipafmt.js \
		$(1)/www/luci-static/resources/wwand/
	$(INSTALL_DIR) $(1)/usr/share/luci/menu.d $(1)/usr/share/rpcd/acl.d
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/luci/root/usr/share/luci/menu.d/luci-app-wwand-ipa.json \
		$(1)/usr/share/luci/menu.d/
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/luci/root/usr/share/rpcd/acl.d/luci-app-wwand-ipa.json \
		$(1)/usr/share/rpcd/acl.d/
endef

$(eval $(call BuildPackage,wwand-ipa))
$(eval $(call BuildPackage,luci-app-wwand-ipa))
