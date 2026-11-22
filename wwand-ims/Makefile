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
PKG_VERSION:=0.2.0_pre21
PKG_RELEASE:=15

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/ddimension/wwand-ims.git
PKG_SOURCE_VERSION:=19af07673c9f1d6de9a97da28dd7ded97c967d45
PKG_MIRROR_HASH:=skip

PKG_LICENSE:=GPL-2.0-only
PKG_MAINTAINER:=

# the host ucode is the bytecode compiler (as in wwand/Makefile)
PKG_BUILD_DEPENDS:=ucode/host strongswan
PKG_CONFIG_DEPENDS:=CONFIG_WWAND_UCODE_SOURCE

include $(INCLUDE_DIR)/package.mk
include $(INCLUDE_DIR)/cmake.mk

CMAKE_BINARY_SUBDIR:=build
CMAKE_OPTIONS += \
	-DUCODE_COMPILER=$(STAGING_DIR_HOSTPKG)/bin/ucode \
	-DUCODE_PRECOMPILE=$(if $(CONFIG_WWAND_UCODE_SOURCE),OFF,ON) \
	-DSTRONGSWAN_PLUGINS=ON \
	-DSTRONGSWAN_INCLUDE_DIR=$(STAGING_DIR)/usr/include/strongswan \
	-DSTRONGSWAN_LIB_DIR=$(STAGING_DIR)/usr/lib/ipsec

# the charon plugins (src/strongswan) are built against this strongSwan's
# headers (its Build/InstallDev) and tied to its ABI: bump with the feed's
# strongswan PKG_VERSION/PKG_RELEASE
SW_VERSION:=6.0.7
SW_RELEASE:=118
SW_ABI:=$(SW_VERSION)-r$(SW_RELEASE)
# The plugin packages' own version: strongSwan's with its release as a 4th
# component, so it stays above the 6.0.7-r117 they had when the strongswan
# package built them (apk: 6.0.7.118 > 6.0.7) and follows each strongSwan
# bump. SW_PLUGIN_REL counts changes of the plugins' sources in between —
# raise it then, or devices keep the older build.
SW_PLUGIN_REL:=1
SW_PLUGIN_VERSION:=$(SW_VERSION).$(SW_RELEASE)-r$(SW_PLUGIN_REL)

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
  # modem_sms_deliver and the plugins' sms_send hook (SMS over IP),
  # wwand 4ad3cde = v1.10.0-dev-20
  EXTRA_DEPENDS:=wwand (>=1.10.0_pre20)
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

# VoWiFi: the router's IMS UE over an IKEv2 tunnel to the operator's ePDG
# (ims_modem option access 'vowifi'). charon driven over vici only, EAP-AKA
# by the USIM in the modem through strongSwan's ext-aka plugin (this feed's
# strongswan). A package of its own for the dependencies: strongSwan and the
# XFRM interface are not wanted on a VoLTE-only router.
define Package/wwand-ims-vowifi
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=WWAN
  TITLE:=VoWiFi for wwand-ims (IKEv2/EAP-AKA tunnel to the ePDG)
  DEPENDS:=+wwand-ims +ip-full +kmod-xfrm-interface +xfrm \
	+strongswan-charon +strongswan-mod-vici +strongswan-mod-kernel-netlink \
	+strongswan-mod-socket-default +strongswan-mod-random +strongswan-mod-kdf \
	+strongswan-mod-aes +strongswan-mod-gcm +strongswan-mod-sha1 +strongswan-mod-sha2 \
	+strongswan-mod-hmac +strongswan-mod-gmp +strongswan-mod-curve25519 \
	+strongswan-mod-x509 +strongswan-mod-pubkey +strongswan-mod-pkcs1 +strongswan-mod-pem \
	+strongswan-mod-constraints +strongswan-mod-eap-identity +strongswan-mod-eap-aka +strongswan-mod-fips-prf \
	+strongswan-mod-ext-aka +strongswan-mod-p-cscf +strongswan-mod-epdg-idr
  PKGARCH:=all
endef

define Package/wwand-ims-vowifi/description
 VoWiFi for the router's own IMS UE: an IKEv2 tunnel to the operator's ePDG
 (EAP-AKA through the modem's USIM, the P-CSCF from the ePDG), the IMS
 traffic on an XFRM interface in a VRF of its own. On with ims_modem option
 access 'vowifi'; `wwand-ims-vowifi up|down|status` drives the tunnel by hand.
endef

# The two charon plugins, out of strongSwan's tree (wwand-ims src/strongswan,
# no patch to strongswan): the package names are the ones the feed's
# strongswan built them under before, so configs and dependents stay.
define Package/strongswan-mod-ext-aka
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=VPN
  TITLE:=StrongSwan EAP-AKA card backed by an external program (a USIM elsewhere) plugin
  DEPENDS:=+strongswan-charon +strongswan-libsimaka
  EXTRA_DEPENDS:=strongswan-charon (=$(SW_ABI))
  VERSION:=$(SW_PLUGIN_VERSION)
endef

define Package/strongswan-mod-ext-aka/description
 charon's EAP-AKA card for a USIM it cannot reach itself: AUTHENTICATE runs
 in an external program (/usr/libexec/strongswan/ext-aka; wwand-ims-vowifi
 puts the modem's or a card reader's USIM there).
endef

define Package/strongswan-mod-epdg-idr
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=VPN
  TITLE:=StrongSwan plugin accepting the IKEv2 responder identity an ePDG answers with
  DEPENDS:=+strongswan-charon
  EXTRA_DEPENDS:=strongswan-charon (=$(SW_ABI))
  VERSION:=$(SW_PLUGIN_VERSION)
endef

define Package/strongswan-mod-epdg-idr/description
 For the EAP-only connections it names (charon.plugins.epdg-idr.connections):
 the IMS APN goes out as IDr (TS 24.302 7.2.2), the identity the ePDG answers
 with is accepted.
endef

define Package/strongswan-mod-ext-aka/install
	$(INSTALL_DIR) $(1)/usr/lib/ipsec/plugins $(1)/etc/strongswan.d/charon
	$(CP) $(CMAKE_BINARY_DIR)/src/strongswan/libstrongswan-ext-aka.so $(1)/usr/lib/ipsec/plugins/
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/files/strongswan-ext-aka.conf $(1)/etc/strongswan.d/charon/ext-aka.conf
endef

define Package/strongswan-mod-ext-aka/conffiles
/etc/strongswan.d/charon/ext-aka.conf
endef

define Package/strongswan-mod-epdg-idr/install
	$(INSTALL_DIR) $(1)/usr/lib/ipsec/plugins $(1)/etc/strongswan.d/charon
	$(CP) $(CMAKE_BINARY_DIR)/src/strongswan/libstrongswan-epdg-idr.so $(1)/usr/lib/ipsec/plugins/
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/files/strongswan-epdg-idr.conf $(1)/etc/strongswan.d/charon/epdg-idr.conf
endef

define Package/strongswan-mod-epdg-idr/conffiles
/etc/strongswan.d/charon/epdg-idr.conf
endef

define Package/luci-app-wwand-ims
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  TITLE:=VoLTE status and settings pages for wwand-ims
  DEPENDS:=+luci-base +wwand-ims
  PKGARCH:=all
endef

define Package/luci-app-wwand-ims/description
 Status -> VoLTE: the IMS registration, the phones registered at sipd, the
 running call and the last ten calls. Network -> VoLTE: /etc/config/wwand_ims
 (the SIP gateway, phones and trunks, the IMS modem, operator profiles).
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

define Package/wwand-ims-vowifi/install
	# the VoWiFi modules next to sipd's (sipd require()s vowifi_lazy)
	$(INSTALL_DIR) $(1)$(IMSLIB)
	$(CP) $(CMAKE_BINARY_DIR)/ucode/wwand-ims-vowifi/* $(1)$(IMSLIB)/
	# the card program strongSwan's ext-aka plugin runs, and the tunnel by hand
	$(INSTALL_DIR) $(1)/usr/libexec/strongswan $(1)/usr/sbin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/files/vowifi-ext-aka.sh $(1)/usr/libexec/strongswan/ext-aka
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/files/wwand-ims-vowifi.sh $(1)/usr/sbin/wwand-ims-vowifi
	# the netifd proto handler that takes the tunnel's IP configuration
	$(INSTALL_DIR) $(1)/lib/netifd/proto
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/files/vowifi-proto.sh $(1)/lib/netifd/proto/wwandvowifi.sh
	# the charon settings vici cannot carry, for the tunnel's connection by
	# name (charon's global settings stay as they are): the P-CSCF request,
	# and the ePDG's own identity accepted (plugin epdg-idr)
	$(INSTALL_DIR) $(1)/etc/strongswan.d/charon
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/files/vowifi-strongswan.conf \
		$(1)/etc/strongswan.d/charon/wwand-ims-vowifi.conf
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/files/vowifi-strongswan-ike.conf \
		$(1)/etc/strongswan.d/wwand-ims-vowifi-ike.conf
endef

define Package/wwand-ims-vowifi/conffiles
/etc/strongswan.d/charon/wwand-ims-vowifi.conf
/etc/strongswan.d/wwand-ims-vowifi-ike.conf
endef

# named, not globbed (the rule luci-app-wwand follows)
define Package/luci-app-wwand-ims/install
	$(INSTALL_DIR) $(1)/www/luci-static/resources/view/wwand $(1)/www/luci-static/resources/wwand
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/luci/htdocs/luci-static/resources/view/wwand/ims-status.js \
		$(PKG_BUILD_DIR)/luci/htdocs/luci-static/resources/view/wwand/ims-config.js \
		$(1)/www/luci-static/resources/view/wwand/
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/luci/htdocs/luci-static/resources/wwand/imsfmt.js \
		$(1)/www/luci-static/resources/wwand/
	$(INSTALL_DIR) $(1)/usr/share/luci/menu.d $(1)/usr/share/rpcd/acl.d
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/luci/root/usr/share/luci/menu.d/luci-app-wwand-ims.json \
		$(1)/usr/share/luci/menu.d/
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/luci/root/usr/share/rpcd/acl.d/luci-app-wwand-ims.json \
		$(1)/usr/share/rpcd/acl.d/
endef

$(eval $(call BuildPackage,wwand-ims))
$(eval $(call BuildPackage,wwand-ims-vowifi))
$(eval $(call BuildPackage,strongswan-mod-ext-aka))
$(eval $(call BuildPackage,strongswan-mod-epdg-idr))
$(eval $(call BuildPackage,luci-app-wwand-ims))
