#
# Remote SIM for wwand: a SIM card in a reader on the router — or on another
# machine over SSH — used by the modem as if it sat in its own slot, through
# Qualcomm's QMI UIM Remote service. A wwand PLUGIN (wwand plugins.uc), kept
# out of the wwand sources on purpose: it is not meant for upstream.
#
# Sources live in https://github.com/ddimension/wwand-rsim, tagged vX.Y.Z. Pin
# a new commit with `scripts/bump-source.sh wwand-rsim <tag|commit>`.
#
# Three packages from one source:
# - rsim-card: the card-side helper alone (C, the repo's helper/ subdirectory,
#   CMake). What a SIM HOST needs — another router that only holds the
#   reader: no wwand, no ucode, just the tool in /usr/bin, where an SSH reader
#   (`ssh:<user>@<host>:<reader>`) runs it by name.
# - wwand-rsim: the plugin and the wwandctl command (ucode, installed as they
#   are), pulling in rsim-card for readers on the modem's own router.
# - luci-app-wwand-rsim: the LuCI page (luci/), installed explicitly from
#   $(PKG_BUILD_DIR) like luci-app-wwand-ipa.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=wwand-rsim
PKG_VERSION:=0.0.1_p37
PKG_RELEASE:=2

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/ddimension/wwand-rsim.git
PKG_SOURCE_VERSION:=8bb57e354b74eeac891e70e3fe8b9bc309737c23
PKG_MIRROR_HASH:=skip

PKG_LICENSE:=GPL-2.0-only
PKG_LICENSE_FILES:=LICENSE
PKG_MAINTAINER:=

include $(INCLUDE_DIR)/package.mk
include $(INCLUDE_DIR)/cmake.mk

# The helper is the repo's helper/ subtree, in two builds (VARIANTs, built one
# after the other — no PKG_PARALLEL_VARIANTS, see the hostapd race in this
# feed's history): rsim-card without PC/SC — the Smartmouse USB, Phoenix and
# AT readers need none of it, and pcscd is a daemon a small SIM host should
# not have to run — and rsim-card-pcsc with it, for any CCID reader through
# pcscd. libusb is for the Smartmouse USB in both: its clock and mode are set
# and its UART driven over USB directly, no kernel serial driver needed.
CMAKE_SOURCE_SUBDIR:=helper
CMAKE_BINARY_SUBDIR:=build
CMAKE_OPTIONS += \
	-DWITH_LIBUSB=ON \
	-DBUILD_TESTING=OFF \
	-DRSIM_WERROR=OFF

ifeq ($(BUILD_VARIANT),pcsc)
  CMAKE_OPTIONS += -DWITH_PCSC=ON
else
  CMAKE_OPTIONS += -DWITH_PCSC=OFF
endif

# Beside the package: the same helper, linked statically, as a file the site
# hands out. A SIM host reached with `ssh:<user>@<host>:<reader>` runs
# `rsim-card` by name and needs nothing else of this project, so it should be
# able to fetch one file — build.yml collects $(BIN_DIR)/rsim-card into
# public/tools/<arch>/, publish-feed.sh puts it under tools/<channel>/<arch>/
# and the start page links it. It is NOT part of any .apk.
#
# x86_64 only, because that is what people plug a reader into; adding an arch
# is one more value here. The second CMake tree repeats the toolchain settings
# of include/cmake.mk rather than reusing Build/Configure/Default, which is
# bound to CMAKE_BINARY_DIR. RSIM_STATIC=ON (upstream 7452f28) takes the static
# pkg-config link lines, so libusb comes along — on musl it needs no udev, the
# reason the same switch cannot produce a static USB build on a glibc distro.
RSIM_STATIC_ARCHS:=x86_64

# once, from the plain build: the static file carries no PC/SC either
ifeq ($(BUILD_VARIANT)$(filter $(ARCH),$(RSIM_STATIC_ARCHS)),nopcsc$(ARCH))
  define Build/Compile/StaticTool
	mkdir -p $(PKG_BUILD_DIR)/build-static
	(cd $(PKG_BUILD_DIR)/build-static; \
		CFLAGS="$(TARGET_CFLAGS) $(TARGET_CPPFLAGS)" \
		LDFLAGS="$(TARGET_LDFLAGS)" \
		cmake \
			--no-warn-unused-cli \
			-DCMAKE_SYSTEM_NAME=Linux \
			-DCMAKE_SYSTEM_VERSION=1 \
			-DCMAKE_SYSTEM_PROCESSOR=$(ARCH) \
			-DCMAKE_BUILD_TYPE=Release \
			-DCMAKE_C_FLAGS_RELEASE="-DNDEBUG" \
			-DCMAKE_C_COMPILER="$(CMAKE_C_COMPILER)" \
			-DCMAKE_AR="$(CMAKE_AR)" \
			-DCMAKE_NM="$(CMAKE_NM)" \
			-DCMAKE_RANLIB="$(CMAKE_RANLIB)" \
			-DCMAKE_FIND_ROOT_PATH="$(CMAKE_FIND_ROOT_PATH)" \
			-DCMAKE_FIND_ROOT_PATH_MODE_PROGRAM=NEVER \
			-DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY \
			-DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY \
			-DCMAKE_PREFIX_PATH=$(STAGING_DIR) \
			-DCMAKE_SKIP_RPATH=TRUE \
			-DCMAKE_STRIP=: \
			-DRSIM_STATIC=ON \
			-DWITH_PCSC=OFF \
			-DWITH_LIBUSB=ON \
			-DBUILD_TESTING=OFF \
			-DRSIM_WERROR=OFF \
			$(CMAKE_SOURCE_DIR))
	+$(MAKE) -C $(PKG_BUILD_DIR)/build-static rsim-card
	$(INSTALL_DIR) $(BIN_DIR)
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/build-static/rsim-card $(BIN_DIR)/rsim-card
  endef
  Hooks/Compile/Post += Build/Compile/StaticTool
endif

UCDIR:=/usr/share/ucode/wwand

define Package/rsim-card
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=WWAN
  TITLE:=SIM card reader helper for wwand-rsim (SIM host)
  # libusb-1.0: the Smartmouse USB backend (clock, mode and UART over USB)
  DEPENDS:=+libusb-1.0
  VARIANT:=nopcsc
  # the provider apk and Kconfig prefer for `rsim-card` (a dependency of
  # wwand-rsim): the plain one; rsim-card-pcsc provides the same name, and
  # same-provide variants need a default (include/package-pack.mk)
  DEFAULT_VARIANT:=1
endef

define Package/rsim-card-pcsc
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=WWAN
  TITLE:=SIM card reader helper for wwand-rsim, with PC/SC readers
  # pcscd + ccid: a CCID reader needs the daemon and its driver, and a
  # helper that can reach neither would only fail at the first card
  DEPENDS:=+libusb-1.0 +libpcsclite +pcscd +ccid
  VARIANT:=pcsc
  PROVIDES:=rsim-card
  CONFLICTS:=rsim-card
endef

define Package/rsim-card-pcsc/description
 rsim-card with the PC/SC backend as well (pcsc:<reader name or index>):
 any CCID smart-card reader through pcscd, besides the Smartmouse USB,
 Phoenix and AT readers. Installed instead of rsim-card; pulls in pcscd
 and the CCID driver. `rsim-card --list` shows the readers pcscd knows.
endef

define Package/rsim-card/description
 The card-side helper of wwand-rsim on its own: it owns a SIM card reader
 (Phoenix/Smartmouse serial readers, the WB Electronics Smartmouse USB over
 libusb) or the SIM of a modem it reaches over its AT port (at:<tty>,
 AT+CSIM; that modem's radio is switched off while its card is lent), and
 speaks JSON lines on stdin/stdout; a paired phone's SIM over the
 Bluetooth SIM Access Profile (bt:<address>, kernel sockets only).
 `rsim-card --list` shows what the machine offers; `rsim-card --serve` is
 the forced command for the router's SSH key. Install it on a router that only holds
 the reader or the modem (a SIM host); the router with the using modem
 reaches it over SSH (rsim_reader ssh:<user>@<host>:<reader>). Needs
 nothing of wwand.
endef

define Package/wwand-rsim
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=WWAN
  TITLE:=Remote SIM (QMI UIM Remote) for wwand
  # wwand-qmi: the plugin allocates its UIM Remote client on the modem's QMI
  # channel (core dep qmi_client); rsim-card: the helper for a reader on this
  # router (the plugin looks for it in /usr/bin since upstream 56c9a71)
  DEPENDS:=+wwand-qmi +rsim-card
  VARIANT:=nopcsc
endef

define Package/wwand-rsim/description
 Lets a Qualcomm modem use a SIM card that is not in its own slot, as if
 it were (QMI UIM Remote): in a reader on the router or on another machine
 reached over SSH (Phoenix/Smartmouse serial readers, the WB Electronics
 Smartmouse USB over libusb), in a phone paired over Bluetooth (SIM Access
 Profile), in a modem wwand does not manage (AT+CSIM), in another modem of
 this router, in a modem of another wwand router (over SSH, restricted with
 rsim-card --serve; that router needs wwand-rsim-provider), or in an
 osmo-remsim SIM bank (RSPRO). A lending modem detaches
 first and keeps its radio off; the lender's APN settings come along as a
 wwand_sim for the card. Configure per modem with `option rsim` (a
 wwand_simreader) or in LuCI. The modem firmware must have the service
 enabled: `wwandctl rsim [modem] enable --reset` (Quectel).
endef

define Package/wwand-rsim-provider
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=WWAN
  TITLE:=Lend this router's modem SIMs to other wwand routers
  # the lending itself is the rsim plugin's, in the daemon; this is the
  # relay another router runs here over SSH (wwandctl rsim proxy)
  DEPENDS:=+wwand-rsim
  VARIANT:=nopcsc
endef

define Package/wwand-rsim-provider/description
 The provider side of wwand-rsim: `wwandctl rsim proxy`, which another
 router's wwand-rsim runs here over SSH to borrow the card of one of this
 router's modems (SIM Access or APDU by APDU, the modem's radio parked
 meanwhile), and `wwandctl rsim proxy --list`, which a scan from there
 shows. Without it this router lends its cards only to its own modems (SIM
 sponsor), and another router reaches them only over an AT port.
endef

define Package/luci-app-wwand-rsim
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  TITLE:=Remote SIM page for wwand-rsim
  DEPENDS:=+luci-base +wwand-rsim
  PKGARCH:=all
  VARIANT:=nopcsc
endef

define Package/luci-app-wwand-rsim/description
 Network -> Remote SIM: per modem, where its SIM comes from (its own, a
 reader on the router or on another machine over SSH, or another modem
 lending its card), the state of the remote card, and the router's SSH key.
endef

define Package/rsim-card/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(CMAKE_BINARY_DIR)/rsim-card $(1)/usr/bin/
endef

Package/rsim-card-pcsc/install = $(Package/rsim-card/install)

define Package/wwand-rsim/install
	$(INSTALL_DIR) $(1)$(UCDIR)/plugins $(1)$(UCDIR)/ctl
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/plugins/rsim.uc $(1)$(UCDIR)/plugins/
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/ctl/rsim.uc $(1)$(UCDIR)/ctl/
endef

define Package/wwand-rsim-provider/install
	$(INSTALL_DIR) $(1)$(UCDIR)/ctl
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/ctl/rsim_provider.uc $(1)$(UCDIR)/ctl/
endef

# named, not globbed (the rule luci-app-wwand follows)
define Package/luci-app-wwand-rsim/install
	$(INSTALL_DIR) $(1)/www/luci-static/resources/view/wwand
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/luci/htdocs/luci-static/resources/view/wwand/rsim.js \
		$(1)/www/luci-static/resources/view/wwand/
	$(INSTALL_DIR) $(1)/usr/share/luci/menu.d $(1)/usr/share/rpcd/acl.d
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/luci/root/usr/share/luci/menu.d/luci-app-wwand-rsim.json \
		$(1)/usr/share/luci/menu.d/
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/luci/root/usr/share/rpcd/acl.d/luci-app-wwand-rsim.json \
		$(1)/usr/share/rpcd/acl.d/
endef

$(eval $(call BuildPackage,rsim-card))
$(eval $(call BuildPackage,rsim-card-pcsc))
$(eval $(call BuildPackage,wwand-rsim))
$(eval $(call BuildPackage,wwand-rsim-provider))
$(eval $(call BuildPackage,luci-app-wwand-rsim))
