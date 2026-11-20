#
# VoLTE for a LAN SIP phone over a cellular modem: the router as its own IMS
# UE (ue/, sipd) and a modem-IMS plugin for the wwand daemon. A wwand PLUGIN
# (wwand plugins.uc) plus a SIP daemon, kept out of the wwand sources on
# purpose: it is NOT meant for upstream.
#
# Sources live in https://github.com/ddimension/wwand-ims, two lines like
# wwand: feed main pins its `main` (vX.Y.0-dev marker -> X.Y.0_preN), feed
# stable its release tags. Pin with `scripts/bump-source.sh wwand-ims <ref>`.
# What ships, and under which name, is the source's CMakeLists.txt: a new
# module is listed there, not here.
#
# GPL-2.0-only, and pure ucode + scripts (no native code): the NETLINK_XFRM
# binding sec-agree needs lives in wwand's own native module (wwand_io.so,
# sub-namespace xfrm), so wwand-ims just DEPENDS on wwand. A future mcfg C tool
# (mcfg_tools) is GPL-3.0 and ships as a SEPARATE package wwand-ims-mcfg with
# its own binaries (docs/design.md §7) — nothing GPL-3.0 or native is built
# here.
#
# The UE and sipd modules and the two programs ship PRECOMPILED to bytecode,
# as wwand's tree does (the source's CMakeLists.txt, wwand's approach): an SDK
# whose ucode cannot emit it (older than 2026.07.09) ships the sources instead,
# and so does CONFIG_WWAND_UCODE_SOURCE, wwand's developer switch, which covers this
# package too. The require()d scripts (plugin, wwandctl ims, sipd_core,
# sipd_sip, ims_mcfg) are source either way. Bytecode is tied to the ucode
# revision it was compiled with, as for wwand: the SDK's host ucode compiles
# it, the same build that compiles wwand.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=wwand-ims
PKG_VERSION:=0.2.0_pre5
PKG_RELEASE:=7

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/ddimension/wwand-ims.git
PKG_SOURCE_VERSION:=192c2e6d0f84b3ea8af31c0d65d75822c35fbd57
PKG_MIRROR_HASH:=skip

PKG_LICENSE:=GPL-2.0-only
PKG_MAINTAINER:=

# the host ucode is the bytecode compiler (as in wwand/Makefile)
PKG_BUILD_DEPENDS:=ucode/host
PKG_CONFIG_DEPENDS:=CONFIG_WWAND_UCODE_SOURCE

include $(INCLUDE_DIR)/package.mk
include $(INCLUDE_DIR)/cmake.mk

CMAKE_BINARY_SUBDIR:=build
CMAKE_OPTIONS += \
	-DUCODE_COMPILER=$(STAGING_DIR_HOSTPKG)/bin/ucode \
	-DUCODE_PRECOMPILE=$(if $(CONFIG_WWAND_UCODE_SOURCE),OFF,ON)

UCDIR:=/usr/share/ucode/wwand
IMSLIB:=/usr/share/wwand-ims

# +wwand: the daemon this plugs into, and the provider of the xfrm binding
# (wwand_io.so). ESP for sec-agree (TS 33.203) over NETLINK_XFRM: kmod-ipsec
# (xfrm core, and it already pulls crypto-authenc/cbc/hmac/sha1) + ipsec4/
# ipsec6 (ESP for v4/v6); AES is built into the kernel (CONFIG_CRYPTO_AES=y),
# so no crypto-aes kmod. The IMS VRF: kmod-vrf (netifd creates the `type vrf`
# device itself) plus ip-full — the l3mdev hotplug re-adds the `ip rule ...
# l3mdev` FIB rules netifd flushes, and the l3mdev selector is iproute2-only
# (busybox ip cannot). ucode stock modules the plugin/UE/sipd import.
define Package/wwand-ims
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=WWAN
  TITLE:=VoLTE for a LAN SIP phone over wwand (IMS UE + plugin)
  DEPENDS:=+wwand \
	+kmod-ipsec +kmod-ipsec4 +kmod-ipsec6 +kmod-vrf +ip-full \
	+ucode-mod-fs +ucode-mod-uloop +ucode-mod-ubus +ucode-mod-socket \
	+ucode-mod-uci +ucode-mod-digest +ucode-mod-struct
  PKGARCH:=all
endef

define Package/wwand-ims/description
 VoLTE for a LAN SIP phone or a PBX trunk through a cellular modem. The
 router is its own IMS UE: it registers over the modem's IMS PDN, borrows the
 USIM over wwand's APDU channel, runs sec-agree ESP in an IMS VRF, and bridges
 RTP to the LAN (sipd, a SIP registrar/B2BUA). A wwand plugin also drives the
 modem's own IMS over QMI, and "wwandctl ims" sets the router up from the
 carrier MBN. Not for upstream.
endef

# user-edited operator/profile config; keep it across sysupgrade
define Package/wwand-ims/conffiles
/etc/config/wwand_ims
endef

# the CMake project has no install rules (cmake.mk's default runs `ninja
# install`): Package/install copies the laid-out trees from the build directory
define Build/Install
endef

define Package/wwand-ims/install
	# the ucode files, laid out by the source's CMakeLists.txt under their
	# installed names: the plugin, `wwandctl ims` and ims_mcfg into the wwand
	# tree; sipd, the UE modules and the ims-register driver (run by `wwandctl
	# ims [modem] call`) into $(IMSLIB), where sipd's `ucode -L` finds them
	$(INSTALL_DIR) $(1)$(UCDIR) $(1)$(IMSLIB)
	$(CP) $(CMAKE_BINARY_DIR)/ucode/wwand/* $(1)$(UCDIR)/
	$(CP) $(CMAKE_BINARY_DIR)/ucode/wwand-ims/* $(1)$(IMSLIB)/
	# init, setup helper, example config, l3mdev hotplug
	$(INSTALL_DIR) $(1)/etc/init.d $(1)/usr/sbin $(1)/etc/config $(1)/etc/hotplug.d/iface
	$(INSTALL_BIN)  $(PKG_BUILD_DIR)/files/wwand-ims-sipd.init $(1)/etc/init.d/wwand-ims-sipd
	$(INSTALL_BIN)  $(PKG_BUILD_DIR)/files/wwand-ims-setup     $(1)/usr/sbin/wwand-ims-setup
	$(INSTALL_CONF) $(PKG_BUILD_DIR)/files/wwand_ims.config    $(1)/etc/config/wwand_ims
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/files/wwand-ims-l3mdev.hotplug \
		$(1)/etc/hotplug.d/iface/25-wwand-ims-l3mdev
	# examples (IMS PDN network + firewall, Asterisk trunk)
	$(INSTALL_DIR) $(1)$(IMSLIB)/examples
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/files/ims-network.example    $(1)$(IMSLIB)/examples/
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/files/asterisk-pjsip.example $(1)$(IMSLIB)/examples/
endef

$(eval $(call BuildPackage,wwand-ims))
