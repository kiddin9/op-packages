#
# VoLTE for a LAN SIP phone over a cellular modem: the router as its own IMS
# UE (ue/, sipd) and a modem-IMS plugin for the wwand daemon. A wwand PLUGIN
# (wwand plugins.uc) plus a SIP daemon, kept out of the wwand sources on
# purpose: it is NOT meant for upstream.
#
# Sources live in https://github.com/ddimension/wwand-ims (branch main, no
# vX.Y.Z-dev marker scheme yet — it is pinned by commit like wwand-ipa, not via
# bump-source.sh). After a PKG_SOURCE_VERSION bump run
# `scripts/update-hashes.sh wwand-ims` to fill PKG_MIRROR_HASH from the SDK.
#
# GPL-2.0-only, and pure ucode + scripts (no compiled code): the NETLINK_XFRM
# binding sec-agree needs lives in wwand's own native module (wwand_io.so,
# sub-namespace xfrm), so wwand-ims just DEPENDS on wwand. A future mcfg C tool
# (mcfg_tools) is GPL-3.0 and ships as a SEPARATE package wwand-ims-mcfg with
# its own binaries (docs/design.md §7) — nothing GPL-3.0 or compiled is built
# here. The ucode tree ships as source (the wwand daemon loads the plugin; the
# sipd init loads the UE modules with `ucode -L`), like wwand-ipa.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=wwand-ims
PKG_VERSION:=0.1.0
PKG_RELEASE:=1

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/ddimension/wwand-ims.git
PKG_SOURCE_VERSION:=1ec70fa685404c54e060c53f3d13db0dad5ebaeb
PKG_MIRROR_HASH:=skip

PKG_LICENSE:=GPL-2.0-only
PKG_MAINTAINER:=

include $(INCLUDE_DIR)/package.mk

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

# pure ucode + scripts: nothing to compile
define Build/Compile
endef

define Package/wwand-ims/install
	# the modem-IMS plugin, loaded by the wwand daemon
	$(INSTALL_DIR) $(1)$(UCDIR)/plugins $(1)$(UCDIR)/ctl
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/plugins/ims.uc $(1)$(UCDIR)/plugins/
	# `wwandctl ims` and the MBN helper (installed under the module name)
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/ctl/ims.uc  $(1)$(UCDIR)/ctl/ims.uc
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/ctl/mcfg.uc $(1)$(UCDIR)/ims_mcfg.uc
	# the router's own IMS UE + sipd, under their `ucode -L` module names
	$(INSTALL_DIR) $(1)$(IMSLIB)
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/sipd/sipd.uc     $(1)$(IMSLIB)/sipd.uc
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/sipd/core.uc     $(1)$(IMSLIB)/sipd_core.uc
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/sipd/sip.uc      $(1)$(IMSLIB)/sipd_sip.uc
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/sipd/line_ue.uc  $(1)$(IMSLIB)/sipd_line_ue.uc
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/sipd/relay.uc    $(1)$(IMSLIB)/sipd_relay.uc
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/ue/aka.uc        $(1)$(IMSLIB)/ue_aka.uc
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/ue/secagree.uc   $(1)$(IMSLIB)/ue_secagree.uc
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/ue/reg.uc        $(1)$(IMSLIB)/ue_reg.uc
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/ue/call.uc       $(1)$(IMSLIB)/ue_call.uc
	# the proven UE driver, run by `wwandctl ims [modem] call <number>`
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/tools/ims-register.uc $(1)$(IMSLIB)/ims-register.uc
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
