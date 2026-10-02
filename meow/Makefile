include $(TOPDIR)/rules.mk

PKG_NAME:=meow

# Upstream release baseline. Bump by hand when meow-rs tags a new release.
PKG_BASE_VERSION?=0.21.2

# PKG_VERSION is rewritten automatically by
# .github/workflows/sync-upstream.yml from the pinned upstream commit's
# committer time (UTC, %Y%m%d%H%M). Do not edit this line by hand.
# All-numeric dotted segments keep the version valid for both package
# managers:  apk -> meow-0.21.2.202610010430-r1.apk
#            ipk -> meow_0.21.2.202610010430-1_<arch>.ipk
PKG_VERSION?=$(PKG_BASE_VERSION).202610010807
PKG_RELEASE?=1

include $(INCLUDE_DIR)/package.mk

PKG_MAINTAINER:=Independent meow OpenWrt package <noreply@example.invalid>

define Package/meow
  SECTION:=net
  CATEGORY:=Network
  TITLE:=meow high-performance rule-based proxy core
  URL:=https://github.com/meow-rs/meow-rs
  LICENSE:=MIT
  # Required by the default transparent-proxy mode implemented in
  # files/gateway.sh (nftables "socket transparent" + tproxy for UDP).
  # Both packages exist for OpenWrt 25.12 (openwrt-25.12 netfilter.mk);
  # they are published per target under targets/<t>/<s>/kmods/<kver>/.
  # If you need the package to install on a target whose kmods feed is
  # stale or mismatched, drop this line - gateway.sh already probes for
  # the modules at runtime and logs a hint instead of leaking traffic.
  DEPENDS:=+kmod-nft-socket +kmod-nft-tproxy
endef

define Package/meow/description
  meow Rust proxy core built from the upstream commit recorded in UPSTREAM.json.

  /usr/bin/meow, the procd init script, UCI settings and the default config
  at /etc/meow/config.yaml (mixed HTTP/SOCKS5 proxy on :7890, REST API and
  web panel on :9090, rule mode with MATCH,DIRECT).

  Transparent-proxy / gateway mode additionally needs kmod-nft-socket and
  kmod-nft-tproxy (pulled in as dependencies).
endef

define Build/Prepare
endef

define Build/Compile
endef

define Package/meow/install
	@test -s ./prebuilt-meow || { echo "ERROR: meow/prebuilt-meow is not populated yet; run build-core.yml first."; exit 1; }
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_DIR) $(1)/etc/meow
	$(INSTALL_DIR) $(1)/etc/uci-defaults
	$(INSTALL_DIR) $(1)/usr/share/meow
	$(INSTALL_BIN) ./prebuilt-meow $(1)/usr/bin/meow
	$(INSTALL_BIN) ./files/meow.init $(1)/etc/init.d/meow
	$(INSTALL_DATA) ./files/meow.config $(1)/etc/config/meow
	$(INSTALL_DATA) ./files/config.yaml $(1)/etc/meow/config.yaml
	$(INSTALL_BIN) ./files/gateway.sh $(1)/usr/share/meow/gateway.sh
	$(INSTALL_BIN) ./files/arp-hijack.sh $(1)/usr/share/meow/arp-hijack.sh
	$(INSTALL_BIN) ./files/meow-arp.init $(1)/etc/init.d/meow-arp
	$(INSTALL_BIN) ./files/meow.uci-defaults $(1)/etc/uci-defaults/80_meow
endef

define Package/meow/conffiles
/etc/config/meow
/etc/meow/config.yaml
endef

$(eval $(call BuildPackage,meow))
