# SPDX-License-Identifier: Apache-2.0
#
# Wire feed first (see openwrt-feed/README.md and feeds.conf.example):
#   ./scripts/feeds update luci packages fwlive
#   ./scripts/feeds install luci-base luci-app-fwlive

include $(TOPDIR)/rules.mk

LUCI_TITLE:=Firewall Live View
LUCI_DESCRIPTION:=Live firewall log table (nftables/fw4 and iptables LOG) with filters
LUCI_DEPENDS:=+luci-base +logd +jsonfilter
LUCI_PKGARCH:=all

PKG_VERSION:=0.1.44
PKG_RELEASE:=27

# Reproducible build: honor SOURCE_DATE_EPOCH from the build environment (set by docker-sdk.sh / CI).
ifdef SOURCE_DATE_EPOCH
export SOURCE_DATE_EPOCH
endif

PKG_LICENSE:=Apache-2.0
PKG_MAINTAINER:=Lucas Albers <lucas.b.albers@gmail.com>

define Package/luci-app-fwlive/prerm
#!/bin/sh
case "$${IPKG_INSTROOT}" in
	''|/) ;;
	*) exit 0 ;;
esac
. /usr/libexec/fwlive-logging.sh
# Best-effort restore: always exit 0 so a transient lock/pending-staging
# failure cannot strand the package half-removed. Baseline is kept on
# failure (restore_wan_log_baseline) for admin recovery; helpers are still
# present while this prerm runs.
restore_wan_log_baseline || logger -t fwlive "WAN log baseline restore failed during uninstall"
exit 0
endef

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
