# SPDX-License-Identifier: GPL-3.0-only
#
# Copyright (C) 2021 ImmortalWrt.org
# Copyright (C) 2026 Amr Fateem <amr.fateem@yahoo.com>
#
# v2rayA OpenWrt packaging.
#
# The structure follows the packaging work by Tianling Shen
# <cnsztl@immortalwrt.org> in the v2raya-openwrt feed and the OpenWrt
# packages feed, updated for the 2.5.x layout where the service and the
# matching v2raya_core binary are separate Go modules.

include $(TOPDIR)/rules.mk

PKG_NAME:=v2raya
PKG_VERSION:=2.5.14
PKG_RELEASE:=5

PKG_SOURCE:=v2rayA-$(PKG_VERSION).tar.gz
PKG_SOURCE_URL:=https://codeload.github.com/v2rayA/v2rayA/tar.gz/v$(PKG_VERSION)?
PKG_HASH:=skip

PKG_BUILD_DIR:=$(BUILD_DIR)/v2rayA-$(PKG_VERSION)/service

PKG_LICENSE:=AGPL-3.0-only
PKG_LICENSE_FILES:=../LICENSE
PKG_MAINTAINER:=Amr Fateem <amr.fateem@yahoo.com>

PKG_BUILD_DEPENDS:=golang/host
PKG_BUILD_PARALLEL:=1
PKG_BUILD_FLAGS:=no-mips16

# v2rayA 2.5.x needs Go 1.26+ and v2raya_core needs Go 1.27+.  The host Go
# shipped by older OpenWrt releases is older than that, so let GOTOOLCHAIN
# fetch the matching toolchain from proxy.golang.org during the build.
# scripts/update-version.sh refreshes this after a major Go bump.
V2RAYA_GO_TOOLCHAIN?=go1.27.3+auto

GO_PKG:=github.com/v2rayA/v2rayA
GO_PKG_BUILD_PKG:=github.com/v2rayA/v2rayA
GO_PKG_LDFLAGS_X:= \
	$(GO_PKG)/conf.Version=$(PKG_VERSION) \
	$(GO_PKG)/kernel/iptables.TproxyNotSkipBr=true

include $(INCLUDE_DIR)/package.mk
include $(TOPDIR)/feeds/packages/lang/golang/golang-package.mk

# v2rayA's SQLite layer has no pure-Go driver for mips* or loong64.  Those
# targets must use cgo (and therefore the target C toolchain); all other
# targets get fully static, CGO-free binaries so one build runs on every
# OpenWrt release with the same CPU architecture.
V2RAYA_CGO:=0
ifneq ($(filter mips% loong64,$(GO_ARCH)),)
  V2RAYA_CGO:=1
endif

GO_PKG_TARGET_VARS:=$(filter-out CGO_ENABLED=%,$(GO_PKG_TARGET_VARS)) CGO_ENABLED=$(V2RAYA_CGO)
ifeq ($(V2RAYA_CGO),0)
  GO_PKG_DEFAULT_LDFLAGS:=$(filter-out -linkmode external,$(GO_PKG_DEFAULT_LDFLAGS))
endif
GO_PKG_BUILD_VARS:=$(filter-out GOTOOLCHAIN=%,$(GO_PKG_BUILD_VARS)) GOTOOLCHAIN=$(V2RAYA_GO_TOOLCHAIN)

TAR_OPTIONS+= --strip-components 1
TAR_CMD=$(HOST_TAR) -C $(1)/.. $(TAR_OPTIONS)

# geoip.dat and geosite.dat are intentionally not hard dependencies: v2rayA
# downloads missing files on first start.  Install v2raya-geoip and
# v2raya-geosite for offline/package-managed data.
define Package/v2raya
  TITLE:=v2rayA - web client for its own Xray-based core
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=Web Servers/Proxies
  DEPENDS:=$(GO_ARCH_DEPENDS) \
	+v2raya-core \
	+ca-bundle \
	+nftables \
	+kmod-nft-tproxy \
	+ip-full \
	+kmod-tun
  CONFLICTS:=v2raya-nextgen
  URL:=https://github.com/v2rayA/v2rayA
endef

define Package/v2raya/description
  v2rayA is a web client for its own Xray-based core. It imports
  subscriptions and share links, selects the fastest node, and provides
  transparent proxy on Linux.

  This package tracks the current upstream 2.5.x release. It installs the
  service together with the matching v2raya_core binary.
endef

define Package/v2raya/conffiles
/etc/config/v2raya
endef

define Package/v2raya/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || {
	mkdir -p /etc/v2raya /var/log/v2raya
	chmod 750 /etc/v2raya
	chmod 755 /var/log/v2raya
	/etc/init.d/v2raya enable
	if [ "$$(uci -q get v2raya.config.enabled)" = "1" ]; then
		/etc/init.d/v2raya restart
	fi
}
endef

define Package/v2raya/prerm
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || {
	[ "$$1" = "upgrade" ] && exit 0
	/etc/init.d/v2raya stop
	/etc/init.d/v2raya disable
}
endef

# v2rayA publishes the built web UI as web.tar.gz on its releases.  The
# GitHub release CDN has been returning 504/404 for it, which makes every
# matrix build fail.  Keep the 871 KiB asset in the package instead; the
# hash of the upstream v2.5.13 asset is
# 76774f195ee74604fbc43a48fe74e5f3363e81ec68af02d1c26feeeacc0f63ae.

define Build/Prepare
	$(call Build/Prepare/Default)

	# OpenWrt's LAN is a bridge (br-lan). v2rayA 2.5.x defaults to excluding
	# br-* from transparent proxy, which silently bypasses every LAN client.
	# The old OpenWrt package removed that exclusion with TproxyNotSkipBr;
	# 2.5.x moved it into this stored default, so strip it here as well.
	$(SED) 's/,br-\*"/"/' $(PKG_BUILD_DIR)/db/configure/setting.go

	# v2rayA 2.2.7 (the old OpenWrt package) did not hijack DNS. 2.5.x turns
	# DNS interception on by default and sends queries through the proxy. With
	# a vless/ws or other UDP-incapable node this breaks all client DNS, so the
	# OpenWrt default stays off. Users can still enable it in the web UI.
	$(SED) 's/DnsHijack: *Yes,/DnsHijack:                          No,/' \
		$(PKG_BUILD_DIR)/db/configure/setting.go
	$(SED) '/if setting.DnsHijack == ""/,/}/ s/setting.DnsHijack = Yes/setting.DnsHijack = No/' \
		$(PKG_BUILD_DIR)/db/configure/migrate_dns.go

	# Router defaults: warn-level logging reduces flash writes, QUIC
	# sniffing is pointless when the LAN QUIC block is in place, and the
	# DNS cache is bounded for the case where a user enables the DNS
	# module later.
	$(SED) 's/LogLevel: *"info"/LogLevel:                           "warn"/' \
		$(PKG_BUILD_DIR)/db/configure/setting.go
	$(SED) 's/InboundSniffing: *"http,tls,quic"/InboundSniffing:                    "http,tls"/' \
		$(PKG_BUILD_DIR)/db/configure/setting.go
	$(SED) 's/DnsCacheSize: *4096/DnsCacheSize:     1024/' \
		$(PKG_BUILD_DIR)/db/configure/setting.go
	$(SED) 's/DnsPrefetch: *true/DnsPrefetch:      false/' \
		$(PKG_BUILD_DIR)/db/configure/setting.go
	$(SED) 's/DnsNegativeCache: *true/DnsNegativeCache: false/' \
		$(PKG_BUILD_DIR)/db/configure/setting.go

	( \
		mkdir -p $(PKG_BUILD_DIR)/server/router/web ; \
		gzip -dc $(CURDIR)/files/web.tar.gz | $(HOST_TAR) -C $(PKG_BUILD_DIR)/server/router/web $(TAR_OPTIONS) ; \
	)
endef

define Package/v2raya/install
	$(call GoPackage/Package/Install/Bin,$(PKG_INSTALL_DIR))

	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_INSTALL_DIR)/usr/bin/v2rayA $(1)/usr/bin/v2raya

	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) $(CURDIR)/files/v2raya.config $(1)/etc/config/v2raya

	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) $(CURDIR)/files/v2raya.init $(1)/etc/init.d/v2raya

	$(INSTALL_DIR) $(1)/usr/libexec
	$(INSTALL_BIN) $(CURDIR)/files/v2raya-detect $(1)/usr/libexec/v2raya-detect

	# Keep the database and the web password across sysupgrade.  Listing
	# /etc/v2raya as an opkg conffile copies the whole directory and has
	# broken real upgrades.
	$(INSTALL_DIR) $(1)/lib/upgrade/keep.d
	$(INSTALL_DATA) $(CURDIR)/files/v2raya.keep $(1)/lib/upgrade/keep.d/v2raya

	$(INSTALL_DIR) $(1)/usr/share/v2raya
endef

$(eval $(call GoBinPackage,v2raya))
$(eval $(call BuildPackage,v2raya))
