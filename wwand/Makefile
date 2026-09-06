# OpenWrt package definitions for the wwand connection manager.
# One source package (git: ddimension/wwand); the ucode side is split into a
# backend-neutral base plus per-backend packages so an install carries only the
# control protocols it needs:
#   wwand            - daemon + shared core + codec/client + native wwand_io.so
#                      transport module (no backend on its own)
#   wwand-qmi        - QMI backend            (DEPENDS wwand)
#   wwand-mbim       - MBIM backend           (DEPENDS wwand-qmi: the MBIM
#                                              QMI-over-MBIM passthrough reuses
#                                              qmi_backend)
#   wwand-ncm        - NCM/ECM backend        (DEPENDS wwand)
#   wwand-mhi        - PCIe/MHI transport + drivers (DEPENDS wwand; add a backend)
#   wwand-esim       - eSIM management        (DEPENDS wwand-qmi + wwand-lpac)
# A typical QMI router installs `wwand-qmi` (which pulls in `wwand`); add
# `wwand-mbim` / `wwand-ncm` for those modems, `wwand-mhi` for a PCIe/MHI modem.
# The ucode tree ships PRECOMPILED to bytecode (repo-root CMakeLists.txt,
# alongside wwand_io.so). `CONFIG_WWAND_UCODE_SOURCE` opts out and ships the
# readable sources instead — the same polarity the wwand repo's CMakeLists.txt
# and files/wwand.init already assume.
#
# The polarity matters beyond taste. It used to be an opt-in
# (WWAND_UCODE_PRECOMPILE, default n), which meant the desired outcome depended
# on a symbol SURVIVING defconfig — and in a per-package SDK build it does not:
# defconfig dropped it together with the CONFIG_PACKAGE_wwand it depends on, and
# the build then shipped source while reporting success. As an opt-out, a
# dropped symbol lands on the default we want, so the failure mode is gone.
#
# KNOWN COUPLING, accepted deliberately: bytecode carries a format version
# (UCODE_BYTECODE_VERSION, ucode's include/ucode/vm.h) that an interpreter
# upgraded past it refuses to load, and no package relation can express that —
# it is independent of libucode's PKG_ABI_VERSION/SONAME, so an ABI-versioned
# dependency does not capture it either. Upgrading ucode alone can therefore
# leave the daemon unable to start. That is not silent: files/wwand.init
# recognises "Bytecode version mismatch" / "Invalid file magic" and refuses with
# an explanatory line instead of respawning forever. The remedy is to reinstall
# wwand built against the running ucode, or to build with
# CONFIG_WWAND_UCODE_SOURCE.
#
# NOTE: the split needs the ucode source that lazy-loads every backend
# (qmi_lazy.uc + the backend-neutral daemon). Bump PKG_SOURCE_VERSION (and
# PKG_SOURCE_DATE / PKG_MIRROR_HASH) to a wwand commit that includes them.

include $(TOPDIR)/rules.mk

PKG_NAME:=wwand
PKG_RELEASE:=24

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/ddimension/wwand.git
PKG_SOURCE_VERSION:=6ddec23e3ea9c6c6bbe1cd5feef207972137d840
PKG_SOURCE_DATE:=2026-09-06
PKG_MIRROR_HASH:=skip

PKG_LICENSE:=GPL-2.0-only
PKG_MAINTAINER:=

# host ucode is the bytecode compiler, and it is now needed on the DEFAULT path,
# so the dependency is unconditional. It was `WWAND_UCODE_PRECOMPILE:ucode/host`
# — a conditional that could only ever be as reliable as the symbol behind it,
# and when the symbol went missing the compiler went with it and cmake fell back
# to shipping source. A build that opts out with CONFIG_WWAND_UCODE_SOURCE pays
# for a host ucode it does not use; that is the cheaper mistake by far.
PKG_BUILD_DEPENDS:=ucode/host

include $(INCLUDE_DIR)/package.mk
include $(INCLUDE_DIR)/cmake.mk

# One cmake build (repo-root CMakeLists.txt) produces both the native
# wwand_io.so (io/ subdir) and — by default — the ucode tree compiled to
# bytecode, one compiler invocation per file with explicit source lists (the
# whole mechanism, incl. the invariants it enforces, is documented in the
# wwand repo's CMakeLists.txt). The bytecode compiler is the SDK's host ucode
# (PKG_BUILD_DEPENDS:=ucode/host) — same ucode revision as the target runtime,
# which bytecode is locked to.
CMAKE_BINARY_SUBDIR:=build

CMAKE_OPTIONS += \
	-DUCODE_COMPILER=$(STAGING_DIR_HOSTPKG)/bin/ucode \
	-DUCODE_PRECOMPILE=$(if $(CONFIG_WWAND_UCODE_SOURCE),OFF,ON)

# every install section takes the ucode tree from here: the cmake bytecode
# output, or the plain sources when CONFIG_WWAND_UCODE_SOURCE opts out.
WWAND_UCODE=$(if $(CONFIG_WWAND_UCODE_SOURCE),$(PKG_BUILD_DIR)/src-ucode,$(CMAKE_BINARY_DIR)/ucode/wwand)

UCDIR:=/usr/share/ucode/wwand

# Base-package ucode set, listed explicitly per install dir. No glob-then-`rm`:
# every module is owned by exactly one package, so a new backend file can never
# silently ship in the base too. The per-backend install lists below carry the
# QMI/MBIM/NCM/eSIM modules; main.uc/wwandctl.uc install as executables.
WWAND_BASE_UC:=apndb.uc atcmd.uc atcmd_parse.uc atport.uc backend.uc board.uc \
	carrier_config.uc client.uc config.uc config_check.uc context_common.uc context_monitor_qmi.uc \
	ctx_settings.uc daemon.uc discovery.uc hwops.uc log.uc modem_datapath_qmi.uc \
	modem_common.uc modem_init_qmi.uc modem_quirks.uc modeswitch.uc ncm_vendors.uc \
	netlink.uc netsel_ops.uc protocol_switch.uc reconnect.uc recovery.uc regdetail.uc \
	sim.uc sim_plmn.uc simops.uc sms.uc sms_pdu.uc telemetry_mbim.uc telemetry_ncm.uc \
	telemetry_qmi.uc transport.uc ubus.uc version.uc
WWAND_BASE_CODEC:=arfcn_bands.uc hex.uc qmux.uc tlv.uc
WWAND_BASE_SCHEMA:=cat.uc ctl.uc dms.uc dsd.uc loc.uc loc_lazy.uc merge.uc nas.uc pdc.uc rat.uc \
	tmd.uc uim.uc wda.uc wds.uc wms.uc wms_lazy.uc

# DEVELOPERS: set CONFIG_WWAND_UCODE_SOURCE to ship readable .uc source
# instead of bytecode — for editing modules live under /usr/share/ucode/wwand
# and for source-line tracebacks; bytecode tracebacks report offsets only.
PKG_CONFIG_DEPENDS:=CONFIG_WWAND_UCODE_SOURCE

define Package/wwand/config
config WWAND_UCODE_SOURCE
	bool "Ship the ucode tree as source instead of bytecode"
	depends on PACKAGE_wwand
	default n
	help
	  By default the ucode tree is compiled to bytecode, so the daemon
	  starts without a parse step (measured 41 ms -> 5 ms for the core
	  imports on x86; more on a router CPU). Enable this to ship the
	  readable sources instead: modules can then be edited in place
	  under /usr/share/ucode/wwand and tracebacks name source lines
	  rather than bytecode offsets.

	  Note that bytecode carries a format version that an interpreter
	  upgraded past it refuses to load, and nothing in the package
	  metadata can express that dependency — so upgrading ucode alone
	  can leave the daemon unable to start. The init script detects
	  exactly that case and refuses with an explanatory log line rather
	  than respawning forever; the remedy is to reinstall wwand built
	  against the running ucode, or to enable this option.

	  A build whose host ucode cannot emit bytecode does not fail: the
	  cmake capability probe falls back to shipping source on its own.
endef

# ---------------------------------------------------------------------------
# base: daemon + framework + codec/client + shared core. No backend on its own;
# the daemon loads whichever wwand-qmi/-mbim/-ncm package is present.
# ---------------------------------------------------------------------------
define Package/wwand
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=WWAN
  TITLE:=Event-driven cellular connection manager (backend-neutral core)
  DEPENDS:=+ucode +ucode-mod-fs +ucode-mod-struct +ucode-mod-uloop \
	+ucode-mod-ubus +ucode-mod-uci +ucode-mod-rtnl
  # the native wwand_io transport module ships inside this package (it is
  # wwand-private, always version-locked to the ucode side). PROVIDES keeps
  # configs/upgrades from the era of the separate ucode-mod-wwand-io working.
  PROVIDES:=ucode-mod-wwand-io
endef

define Package/wwand/description
  wwand is an event-driven connection manager daemon for cellular modems,
  supporting multiple modems and multiple parallel PDP contexts. This base
  package carries the daemon, the netifd proto shim, the QMI codec (qmux/tlv +
  service schemas), the generic service client, the SIM/APDU layer and the
  shared modem/context core. Install a backend package (wwand-qmi, wwand-mbim
  or wwand-ncm) for the control protocols your modems use.
endef

define Package/wwand/install
	# native transport module (built by the cmake step from io/)
	$(INSTALL_DIR) $(1)/usr/lib/ucode
	$(INSTALL_BIN) $(CMAKE_BINARY_DIR)/io/wwand_io.so $(1)/usr/lib/ucode/
	# base ucode tree — explicit per-file lists (see WWAND_BASE_* above), so the
	# base package owns exactly its own modules and nothing a backend ships.
	$(INSTALL_DIR) $(1)$(UCDIR)/codec/schema
	$(INSTALL_DATA) $(addprefix $(WWAND_UCODE)/,$(WWAND_BASE_UC)) $(1)$(UCDIR)/
	$(INSTALL_DATA) $(addprefix $(WWAND_UCODE)/codec/,$(WWAND_BASE_CODEC)) $(1)$(UCDIR)/codec/
	$(INSTALL_DATA) $(addprefix $(WWAND_UCODE)/codec/schema/,$(WWAND_BASE_SCHEMA)) $(1)$(UCDIR)/codec/schema/
	# daemon + CLI as executables (not under $(UCDIR))
	$(INSTALL_DIR) $(1)/usr/sbin
	$(INSTALL_BIN) $(WWAND_UCODE)/main.uc $(1)/usr/sbin/wwand
	# wwandctl: the human-friendly CLI front-end over the ubus API
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(WWAND_UCODE)/wwandctl.uc $(1)/usr/bin/wwandctl
	$(INSTALL_DIR) $(1)/lib/netifd/proto
	# the shim registers `wwand` and nothing else — netifd sources every handler
	# in this directory, so two of them claiming `qmi` would be settled by load
	# order. `proto qmi` therefore stays uqmi's qmi.sh; migrating an interface is
	# the user's explicit act.
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/files/wwand-proto.sh $(1)/lib/netifd/proto/wwand.sh
	$(INSTALL_DIR) $(1)/usr/libexec/wwand
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/files/wwand-migrate $(1)/usr/libexec/wwand/migrate
	# migration is user-triggered (LuCI modem list / the migrate CLI); the
	# Config migration is ALWAYS user-triggered: nothing is installed under
	# /etc/uci-defaults, so installing or upgrading wwand never rewrites an
	# existing configuration. The example below is shipped inert; copying it
	# into /etc/uci-defaults/ runs the same migration once, at the next boot.
	$(INSTALL_DIR) $(1)/usr/share/wwand/examples
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/files/examples/99-wwand-migrate \
		$(1)/usr/share/wwand/examples/99-wwand-migrate
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/files/wwand.init $(1)/etc/init.d/wwand
	# no /etc/config/wwand for new installs — all config lives in
	# /etc/config/network now (existing files survive upgrade and are still read).
	# files/wwand.config is kept in the source tree only as a documented example.
	$(INSTALL_DIR) $(1)/etc/hotplug.d/usbmisc
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/files/wwand.hotplug $(1)/etc/hotplug.d/usbmisc/20-wwand
	# net hotplug: NCM modems (no cdc-wdm) + re-enumeration after a mode switch
	$(INSTALL_DIR) $(1)/etc/hotplug.d/net
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/files/wwand.hotplug.net $(1)/etc/hotplug.d/net/20-wwand
	# tty hotplug: AT ports appearing after the datapath netdev (vendor-serial
	# new_id bind / late kmodloader) re-kick a modem parked in no_at_port backoff
	$(INSTALL_DIR) $(1)/etc/hotplug.d/tty
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/files/wwand.hotplug.tty $(1)/etc/hotplug.d/tty/20-wwand
	# usb hotplug: bind qmi_wwan to the Huawei E1820's ethernet function. The
	# kernel hands the device to qmi_wwan (cdc_ether blacklists it) but its
	# table entry wants a vendor-specific class this old 802.3 layout does not
	# carry, so a scoped dynamic new_id is what makes the control channel appear
	# at all — and it is volatile, so it has to be re-created on every replug.
	$(INSTALL_DIR) $(1)/etc/hotplug.d/usb
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/files/wwand.hotplug.e1820 $(1)/etc/hotplug.d/usb/21-wwand-e1820
	# NOTE: the kernel-wwan-subsystem hotplug (/etc/hotplug.d/wwan/20-wwand) is
	# NOT installed here — it belongs to wwand-mhi, which also pulls the MHI
	# drivers that create /sys/class/wwan in the first place (procd only arms a
	# subsystem whose hotplug dir exists). USB modems never need it.
endef

# ---------------------------------------------------------------------------
# wwand-qmi: the QMI backend (native qmux over /dev/cdc-wdmX).
# ---------------------------------------------------------------------------
define Package/wwand-qmi
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=WWAN
  TITLE:=QMI backend for wwand
  # kmod-rmnet is the QMAP demuxer and is needed on BOTH transports (an MHI
  # modem multiplexes through it too); only the USB glue is conditional, so a
  # target built without USB support can still select this backend and drive a
  # PCIe/MHI modem. On a USB target nothing changes.
  DEPENDS:=+wwand +USB_SUPPORT:kmod-usb-net-qmi-wwan +kmod-rmnet
  # coexists with the stock OpenWrt QMI stack (uqmi): wwand claims only
  # `proto wwand` interfaces, so both can be installed. To hand an existing
  # `proto qmi` interface to wwand, migrate it — from the LuCI modem list or
  # with `/usr/libexec/wwand/migrate --apply` — which rewrites it in place.
endef

define Package/wwand-qmi/description
  QMI control backend for wwand: talks QMI natively over /dev/cdc-wdmX (qmi_wwan
  driver) with QMAP multiplexing (rmnet), without spawning uqmi/qmicli. This is
  the common case for most cellular routers. Pair with wwand-mhi for modems
  attached over PCIe/MHI.
endef

define Package/wwand-qmi/install
	$(INSTALL_DIR) $(1)$(UCDIR)
	$(INSTALL_DATA) $(WWAND_UCODE)/modem.uc $(1)$(UCDIR)/
	$(INSTALL_DATA) $(WWAND_UCODE)/context.uc $(1)$(UCDIR)/
	$(INSTALL_DATA) $(WWAND_UCODE)/qmi_backend.uc $(1)$(UCDIR)/
	$(INSTALL_DATA) $(WWAND_UCODE)/callend.uc $(1)$(UCDIR)/
	$(INSTALL_DATA) $(WWAND_UCODE)/qmi_lazy.uc $(1)$(UCDIR)/
endef

# ---------------------------------------------------------------------------
# wwand-mbim: the MBIM backend. Depends on wwand-qmi because the QMI-over-MBIM
# passthrough runs the QMI stack (qmi_backend) over the open MBIM channel.
# ---------------------------------------------------------------------------
define Package/wwand-mbim
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=WWAN
  TITLE:=MBIM backend for wwand
  # conditional for the same reason as wwand-qmi: the ucode side is
  # transport-neutral, and on MHI the transport is kmod-mhi-wwan-mbim, which
  # wwand-mhi already pulls
  DEPENDS:=+wwand-qmi +USB_SUPPORT:kmod-usb-net-cdc-mbim
  # coexists with the stock OpenWrt MBIM stack (netifd `mbim` proto, package
  # umbim): wwand manages a cdc_mbim modem only once its interface has been
  # migrated to `proto wwand` (LuCI modem list / migrate CLI), so both stacks can
  # be installed side by side.
endef

define Package/wwand-mbim/description
  MBIM control backend for wwand (cdc_mbim driver): native MS Basic Connect (+
  Extensions v2/v3) plus a QMI-over-MBIM passthrough that tunnels the whole QMI
  stack over the open MBIM channel for full CDC-level telemetry/config. The
  passthrough reuses qmi_backend, hence the dependency on wwand-qmi. Pair
  with wwand-mhi for modems attached over PCIe/MHI.
endef

define Package/wwand-mbim/install
	$(INSTALL_DIR) $(1)$(UCDIR)/codec/mbim_schema
	$(INSTALL_DATA) $(WWAND_UCODE)/modem_mbim.uc $(1)$(UCDIR)/
	$(INSTALL_DATA) $(WWAND_UCODE)/context_mbim.uc $(1)$(UCDIR)/
	$(INSTALL_DATA) $(WWAND_UCODE)/mbim_backend.uc $(1)$(UCDIR)/
	$(INSTALL_DATA) $(WWAND_UCODE)/mbim_client.uc $(1)$(UCDIR)/
	$(INSTALL_DATA) $(WWAND_UCODE)/qmi_over_mbim.uc $(1)$(UCDIR)/
	$(INSTALL_DATA) $(WWAND_UCODE)/mbim_lazy.uc $(1)$(UCDIR)/
	$(INSTALL_DATA) $(WWAND_UCODE)/atcmd_mbim.uc $(1)$(UCDIR)/
	$(INSTALL_DATA) $(WWAND_UCODE)/atcmd_mbim_lazy.uc $(1)$(UCDIR)/
	$(INSTALL_DATA) $(WWAND_UCODE)/codec/mbim.uc $(1)$(UCDIR)/codec/
	$(INSTALL_DATA) $(WWAND_UCODE)/codec/mbim_schema/*.uc $(1)$(UCDIR)/codec/mbim_schema/
endef

# ---------------------------------------------------------------------------
# wwand-ncm: the NCM/ECM backend (cdc_ncm / cdc_ether, AT-controlled).
# ---------------------------------------------------------------------------
define Package/wwand-ncm
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=WWAN
  TITLE:=NCM/ECM backend for wwand
  # +kmod-usb-net-rndis: the RNDIS datapath (rndis_host) used by e.g. the
  # Fibocom FM350-GL (MediaTek T700) — same AT-driven backend, RNDIS netdev.
  # These three stay UNCONDITIONAL, unlike the USB kmods of wwand-qmi and
  # wwand-mbim. Those two have a non-USB transport behind them — QMI keeps
  # +kmod-rmnet unconditional and reaches a modem over MHI, MBIM gets
  # kmod-mhi-wwan-mbim through wwand-mhi — so gating their USB kmod still
  # leaves a package that works on a PCIe-only target. NCM has no such path:
  # it drives a single cdc_ncm/cdc_ether netdev and the only variant it
  # recognises is rndis_host, all USB. Gating these on USB_SUPPORT would leave
  # the package selectable on a !USB_SUPPORT target while pulling no datapath
  # driver at all — installable and inert. The hard dependency is what keeps it
  # unselectable there. (Raised in review on openwrt/packages#30185.)
  DEPENDS:=+wwand +kmod-usb-net-cdc-ncm +kmod-usb-net-cdc-ether \
	+kmod-usb-net-rndis
  # coexists with the stock OpenWrt NCM stack (netifd `ncm` proto, package
  # comgt-ncm): wwand drives an AT/NCM modem only once its interface has been
  # migrated to `proto wwand` (LuCI modem list / migrate CLI), so both stacks can
  # be installed side by side.
endef

define Package/wwand-ncm/description
  NCM/ECM control backend for wwand: an AT-controlled datapath over a plain
  cdc_ncm / cdc_ether netdev, for modems that expose no cdc-wdm control device.
endef

define Package/wwand-ncm/install
	$(INSTALL_DIR) $(1)$(UCDIR)
	$(INSTALL_DATA) $(WWAND_UCODE)/modem_ncm.uc $(1)$(UCDIR)/
	$(INSTALL_DATA) $(WWAND_UCODE)/context_ncm.uc $(1)$(UCDIR)/
	$(INSTALL_DATA) $(WWAND_UCODE)/ncm_lazy.uc $(1)$(UCDIR)/
endef

# ---------------------------------------------------------------------------
# wwand-mhi: PCIe/MHI transport bundle. Modems on the kernel `wwan` subsystem
# (Foxconn T99W175/SDX, Quectel RM5xx-AE, Telit FN990, …) expose their QMI/MBIM
# control port under /sys/class/wwan — not usbmisc/cdc-wdm — and need the MHI
# driver stack instead of the USB kmods. This package pulls those drivers and
# ships the wwan-subsystem hotplug that binds such a modem on cold-plug. It is
# transport-only and backend-neutral: install ALONGSIDE wwand-qmi (QMI over MHI,
# rmnet data) or wwand-mbim (MBIM over MHI) for the control protocol.
# ---------------------------------------------------------------------------
define Package/wwand-mhi
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=WWAN
  TITLE:=PCIe/MHI transport + drivers for wwand
  DEPENDS:=+wwand +kmod-mhi-pci-generic +kmod-mhi-wwan-ctrl \
	+kmod-mhi-wwan-mbim +kmod-mhi-net
endef

define Package/wwand-mhi/description
  Support for cellular modems attached over PCIe/MHI (Foxconn T99W175 and
  similar), whose control ports appear on the kernel wwan subsystem. Pulls the
  MHI bus/PCI/control/data drivers and installs the wwan-subsystem hotplug so
  wwand binds these modems on boot. Install together with a control backend
  (wwand-qmi or wwand-mbim).

  Adding wwand-mbim is worth weighing on a QMI-driven MHI modem: many of them
  expose no DUN channel and therefore no AT port at all, and wwand can then
  carry AT over the modem's MBIM channel instead (Quectel QDU). The cost is
  that wwand-mbim currently pulls the USB MBIM transport with it, which this
  path does not use — and on a target built without USB support it cannot be
  selected at all. Without it the capability is simply absent: vendor AT
  commands, the protocol switch and AT telemetry are unavailable, which is a
  limitation rather than a failure.
endef

define Package/wwand-mhi/install
	# wwan-subsystem hotplug: MHI modems expose their control port under
	# /sys/class/wwan (/dev/wwanXqmiN|mbimN). procd only dispatches the `wwan`
	# subsystem once this directory exists — so it ships with the MHI drivers,
	# not with the base package.
	$(INSTALL_DIR) $(1)/etc/hotplug.d/wwan
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/files/wwand.hotplug.wwan $(1)/etc/hotplug.d/wwan/20-wwand
endef

# ---------------------------------------------------------------------------
# wwand-esim: eSIM (eUICC) profile management. Needs a QMI UIM/APDU channel.
# ---------------------------------------------------------------------------
define Package/wwand-esim
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=WWAN
  TITLE:=eSIM (eUICC) profile management for wwand
  # Needs an lpac binary at /usr/bin/lpac: either the generic openwrt-packages
  # lpac, or our self-contained static wwand-lpac (bundled wolfSSL+libcurl, no
  # OpenSSL/mbedtls .so — it PROVIDES lpac, so it satisfies +lpac too). lpac
  # drives the SM-DP+ download/notification (ES9+ HTTPS on the router); the
  # daemon bridges its stdio APDU protocol inline. APDU access uses the modem
  # UIM channel, so it also needs the QMI backend.
  DEPENDS:=+wwand-qmi +lpac
endef

define Package/wwand-esim/description
 Optional ES10c (SGP.22) profile management for wwand: EID, profile list,
 enable/disable/delete over the modem UIM APDU channel. SM-DP+ profile
 downloads and notification acknowledgements are driven by lpac: its ES10
 APDUs are relayed through wwand's own APDU channel (ubus modem_apdu) by the
 stdio bridge, so wwand stays the sole owner of the modem — no separate AT
 port. lpac runs the ES9+ HTTPS on the router; no dedicated modem APN is
 required.

 The download is handled by an lpac binary (the +lpac dependency): either the
 generic openwrt-packages lpac, or the self-contained wwand-lpac (which PROVIDES
 lpac) — a single ~0.9 MB binary with a minimal static wolfSSL + libcurl linked
 in, needing no libcurl/libssl/libcrypto .so (vs the ~6.4 MB stock libcurl+
 OpenSSL pulls in) and carrying the GSMA-capable TLS itself. Either works via
 /usr/bin/lpac; the stdio APDU bridge needs lpac >= 2.3.0 (upstream PR #399).
 See wwand-lpac/Makefile.
endef

define Package/wwand-esim/install
	$(INSTALL_DIR) $(1)$(UCDIR)
	$(INSTALL_DATA) $(WWAND_UCODE)/esim.uc $(1)$(UCDIR)/
	$(INSTALL_DATA) $(WWAND_UCODE)/esim_bridge.uc $(1)$(UCDIR)/
endef

# ---------------------------------------------------------------------------
# wwand-datapath-rmnet_nss: Qualcomm NSS offload behind the VENDOR qmi_wwan_q.
# A datapath add-on, not a control backend — it plugs into wwand's datapath
# interface (`option mux 'rmnet_nss'`, or picked up on its own under 'auto').
# Underscore in the name on purpose: the datapath name doubles as the ucode
# module name (wwand.datapath_rmnet_nss), and the daemon's "package not
# installed" note is built from it, so the two must read alike.
# ---------------------------------------------------------------------------
define Package/wwand-datapath-rmnet_nss
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=WWAN
  TITLE:=NSS-offloaded QMAP datapath (vendor qmi_wwan_q) for wwand
  # +wwand-qmi: it is a QMI datapath. The vendor driver and the NSS shim are
  # NOT dependencies — they come from the board's own kernel tree (QSDK/NSS
  # builds), and this package must stay installable next to them rather than
  # try to name them.
  DEPENDS:=+wwand-qmi
endef

define Package/wwand-datapath-rmnet_nss/description
  Datapath add-on for Qualcomm NSS builds (ipq807x and friends), where the modem
  datapath is offloaded to the NSS cores. The attach point is a global callback
  contract: rmnet_nss publishes rmnet_nss_callbacks and the vendor qmi_wwan_q
  driver calls nss_create() on each QMAP netdev it registers. Mainline rmnet
  makes no such call, so wwand's built-in rmnet/qmimux datapaths produce children
  that never reach the NSS shim — traffic forwards, but on the CPU.

  This datapath therefore creates nothing: qmi_wwan_q registers the children in
  its USB probe, one per its qmap_mode module parameter, and wwand adopts them,
  drives the per-channel link_state gate and binds each WDS session to the QMAP
  id the driver expects (0x81 upwards, not the config channel number).

  It claims any parent carrying those vendor children, with or without the NSS
  shim: they need adopting either way, and leaving a non-NSS vendor box to
  mainline rmnet makes it build a second set of children on a parent that
  already demuxes QMAP itself. For the offload, rmnet_nss must be LOADED BEFORE
  the modem's driver binds — qmi_wwan_q captures whether NSS is available at the
  moment it creates each child, so a module loaded afterwards leaves them
  without an NSS context; that case is logged and shown on the status page.

  That constraint belongs to the STOCK driver, not to NSS itself: the single
  nss_create() attempt can be turned into a bounded delayed-work retry, and the
  child then attaches whenever the NSS data plane comes up, in any order. If you
  build the vendor driver yourself, kuncy7/aw1000-nss-builder carries such a
  patch (package-patches/quectel-qmi-wwan/950-rmnet-nss-deferred-attach.patch).
  It is a change to the quectel-qmi-wwan kernel module, not to wwand, so nothing
  here can apply it for you — but it removes the ordering requirement at its
  source rather than working around it.

  Install it on a box with the vendor qmi_wwan_q driver; anywhere else it probes
  false and changes nothing.
endef

define Package/wwand-datapath-rmnet_nss/install
	$(INSTALL_DIR) $(1)$(UCDIR)
	$(INSTALL_DATA) $(WWAND_UCODE)/datapath_rmnet_nss.uc $(1)$(UCDIR)/
endef

$(eval $(call BuildPackage,wwand))
$(eval $(call BuildPackage,wwand-qmi))
$(eval $(call BuildPackage,wwand-mbim))
$(eval $(call BuildPackage,wwand-ncm))
$(eval $(call BuildPackage,wwand-mhi))
$(eval $(call BuildPackage,wwand-esim))
define Package/wwand-datapath-rmnet_nss_mhi
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=WWAN
  TITLE:=NSS-offloaded QMAP datapath (vendor PCIe/MHI) for wwand
  # +wwand: it serves both control protocols, so it names neither backend
  # package. The vendor pcie_mhi driver and the NSS shim come from the board's
  # own kernel tree and are deliberately not named here.
  DEPENDS:=+wwand
endef

define Package/wwand-datapath-rmnet_nss_mhi/description
  The PCIe/MHI sibling of wwand-datapath-rmnet_nss, for Quectel's vendor
  pcie_mhi driver (mhi_netdev_quectel). That driver registers the QMAP children
  itself and calls the rmnet_nss callbacks on each, so wwand adopts them rather
  than creating any -- mainline rmnet would build a second set on a parent that
  already demuxes.

  It serves QMI and MBIM alike, because the driver does. The wire id differs:
  QMAP framing uses 0x81 upwards, MBIM framing uses the MBIM session id, which
  equals wwand's channel number on ordinary hardware and is offset by 112 on an
  SDX7x (PCI 17cb:0309).

  NOT hardware-verified: written from the driver sources. On any board without
  that driver it probes false and changes nothing.
endef

define Package/wwand-datapath-rmnet_nss_mhi/install
	$(INSTALL_DIR) $(1)$(UCDIR)
	$(INSTALL_DATA) $(WWAND_UCODE)/datapath_rmnet_nss_mhi.uc $(1)$(UCDIR)/
endef

$(eval $(call BuildPackage,wwand-datapath-rmnet_nss))
$(eval $(call BuildPackage,wwand-datapath-rmnet_nss_mhi))
