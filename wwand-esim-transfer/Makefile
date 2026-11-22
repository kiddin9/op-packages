#
# eSIM transfer for wwand: release a profile with its delete notification
# delivered, import a code or an SM-DS event, and the experimental GSMA TS.43
# (ODSA) client. A wwand PLUGIN (wwand plugins.uc), kept out of the wwand
# sources on purpose: it is not meant for upstream.
#
# Sources live in https://github.com/ddimension/wwand-esim-transfer. Pin a new
# commit: PKG_SOURCE_VERSION (+ PKG_VERSION), PKG_RELEASE+1, then
# scripts/update-hashes.sh wwand-esim-transfer.
#
# The ucode ships PRECOMPILED to bytecode (the source repository's CMakeLists.txt),
# with the SDK host ucode as the compiler — the same revision as the target
# runtime, since bytecode is VM-locked. Bytecode is architecture-independent,
# hence PKGARCH:=all. The same ucode version floor as wwand (wwand Makefile,
# "The ucode this build links and compiles against"): an interpreter upgraded
# past the bytecode format refuses to load it, and only this floor makes apk
# say so at install time instead of the plugin failing to load.
# CONFIG_WWAND_UCODE_SOURCE (wwand's opt-out) ships the source here too.

include $(TOPDIR)/rules.mk

PKG_NAME:=wwand-esim-transfer
PKG_VERSION:=0.1.0
PKG_RELEASE:=1

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/ddimension/wwand-esim-transfer.git
PKG_SOURCE_VERSION:=6c3f0e5585248038b6988cf5468f9b83f2db18bb
PKG_MIRROR_HASH:=skip

PKG_LICENSE:=GPL-2.0-only
PKG_LICENSE_FILES:=LICENSE
PKG_MAINTAINER:=

PKG_BUILD_DEPENDS:=ucode/host
PKG_CONFIG_DEPENDS:=CONFIG_WWAND_UCODE_SOURCE

include $(INCLUDE_DIR)/package.mk
include $(INCLUDE_DIR)/cmake.mk

CMAKE_BINARY_SUBDIR:=build
CMAKE_OPTIONS += \
	-DUCODE_COMPILER=$(STAGING_DIR_HOSTPKG)/bin/ucode \
	-DUCODE_PRECOMPILE=$(if $(CONFIG_WWAND_UCODE_SOURCE),OFF,ON)

OUT:=$(CMAKE_BINARY_DIR)/out

# the CMakeLists has no install rules: the files are taken from $(OUT) by
# the install sections below, so cmake.mk's default `install` target (ninja
# refuses an unknown target) must not run
Build/Install:=
UCDIR:=/usr/share/ucode/wwand

# read from ucode's Makefile exactly as the wwand Makefile does (see there)
UCODE_MAKEFILE:=$(firstword $(wildcard \
	$(TOPDIR)/package/utils/ucode/Makefile \
	$(TOPDIR)/package/feeds/base/ucode/Makefile \
	$(TOPDIR)/feeds/base/package/utils/ucode/Makefile))
UCODE_BUILT:=$(if $(UCODE_MAKEFILE),$(subst -,.,$(shell sed -n 's/^PKG_SOURCE_DATE:=//p' '$(UCODE_MAKEFILE)')))
UCODE_ABI:=$(if $(UCODE_MAKEFILE),$(shell sed -n 's/^PKG_ABI_VERSION:=//p' '$(UCODE_MAKEFILE)'))

define Package/wwand-esim-transfer
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=WWAN
  TITLE:=eSIM transfer for wwand (release, import, GSMA TS.43)
  # wwand-esim: modem_esim, the stdio APDU bridge and lpac; wwand-lpac-curl:
  # the TS.43 HTTPS client's transport — a curl that returns every
  # Set-Cookie (esim_transfer/http.uc says why uclient is not enough)
  DEPENDS:=+wwand-esim +wwand-lpac-curl
  EXTRA_DEPENDS:=$(if $(UCODE_BUILT),ucode (>=$(UCODE_BUILT))$(if $(UCODE_ABI),$(comma) libucode$(UCODE_ABI) (>=$(UCODE_BUILT))))
  PKGARCH:=all
endef

define Package/wwand-esim-transfer/description
 Moves an eSIM subscription off or onto the router. Release: disable and
 delete a profile and keep sending its delete notification until the
 operator's SM-DP+ acknowledged it (so the operator lets it be issued
 elsewhere). Import: an activation code (QR / ePIN) or a profile an
 operator queued for the card's EID (SM-DS). TS.43 (experimental): the
 router's SIM proves the subscription to the operator's entitlement server
 and gets an activation code for this router's eUICC or another device.
 Shows the SGP.22 v3 Device Change settings of profiles that carry them.
 `wwandctl transfer`; LuCI page in luci-app-wwand-esim-transfer.
endef

define Package/luci-app-wwand-esim-transfer
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  TITLE:=eSIM transfer page for wwand-esim-transfer
  DEPENDS:=+luci-base +wwand-esim-transfer
  PKGARCH:=all
endef

define Package/luci-app-wwand-esim-transfer/description
 Network -> eSIM Transfer: release a profile, import a code (paste or a QR
 image), look for a queued profile, and run a TS.43 transfer.
endef

# /etc/wwand/esim-transfer holds the release record (which delete
# notifications went through) and the user's entitlement.json; created at
# runtime, so keep.d and not conffiles (the reason in the wwand-ipa Makefile)
define Package/wwand-esim-transfer/install
	$(INSTALL_DIR) $(1)$(UCDIR)/plugins $(1)$(UCDIR)/ctl $(1)$(UCDIR)/esim_transfer
	$(INSTALL_DATA) $(OUT)/plugins/esim_transfer.uc $(1)$(UCDIR)/plugins/
	$(INSTALL_DATA) $(OUT)/ctl/transfer.uc $(1)$(UCDIR)/ctl/
	$(INSTALL_DATA) \
		$(OUT)/esim_transfer/sha1.uc $(OUT)/esim_transfer/aka.uc \
		$(OUT)/esim_transfer/ts43.uc $(OUT)/esim_transfer/meta.uc \
		$(OUT)/esim_transfer/hints.uc $(OUT)/esim_transfer/http.uc \
		$(OUT)/esim_transfer/plugin.uc $(OUT)/esim_transfer/ctl.uc \
		$(1)$(UCDIR)/esim_transfer/
	$(INSTALL_DIR) $(1)/usr/libexec/wwand
	$(INSTALL_BIN) $(OUT)/libexec/esim-transfer-card $(1)/usr/libexec/wwand/
	$(INSTALL_DIR) $(1)/lib/upgrade/keep.d
	echo /etc/wwand/esim-transfer/ > $(1)/lib/upgrade/keep.d/wwand-esim-transfer
endef

# named, not globbed (the rule luci-app-wwand follows)
define Package/luci-app-wwand-esim-transfer/install
	$(INSTALL_DIR) $(1)/www/luci-static/resources/view/wwand
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/luci/htdocs/luci-static/resources/view/wwand/esim_transfer.js \
		$(1)/www/luci-static/resources/view/wwand/
	$(INSTALL_DIR) $(1)/usr/share/luci/menu.d $(1)/usr/share/rpcd/acl.d
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/luci/root/usr/share/luci/menu.d/luci-app-wwand-esim-transfer.json \
		$(1)/usr/share/luci/menu.d/
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/luci/root/usr/share/rpcd/acl.d/luci-app-wwand-esim-transfer.json \
		$(1)/usr/share/rpcd/acl.d/
endef

$(eval $(call BuildPackage,wwand-esim-transfer))
$(eval $(call BuildPackage,luci-app-wwand-esim-transfer))
