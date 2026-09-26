# SPDX-License-Identifier: Apache-2.0
#
# Wire feed first (see openwrt-feed/README.md and feeds.conf.example):
#   ./scripts/feeds update luci packages fwlive
#   ./scripts/feeds install luci-base luci-app-fwlive

include $(TOPDIR)/rules.mk

LUCI_TITLE:=Firewall Live View
LUCI_DESCRIPTION:=Live firewall log table (firewall4/nft; iptables-tagged lines still classify) with filters
LUCI_DEPENDS:=+luci-base +logd +jsonfilter
LUCI_PKGARCH:=all

PKG_VERSION:=0.1.46
PKG_RELEASE:=39

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
# The opkg wrapper invokes this body as <wrapper> <action>.
# OpenWrt APK post-upgrade/pre-deinstall wiring is in package-pack.mk;
# post-upgrade exports PKG_UPGRADE=1. This guard is belt-and-braces with
# the upgrade action arg.
# A version-shaped $$1 with empty $$2 is APK uninstall (pre-deinstall).
# Same-version APK reinstall uses post-upgrade and does not run this hook.
# A version-changing APK upgrade is indistinguishable from uninstall at
# this hook (both pass the old version as $$1). Do not claim that path
# was lab-proven.
[ "$${PKG_UPGRADE:-}" = 1 ] && exit 0
case "$${2-}" in
	remove) ;;
	upgrade) exit 0 ;;
	'')
		case "$${1-}" in
			remove) ;;
			upgrade|''|[!0-9]*) exit 0 ;;
			# Character-class '.' so the version arm is a literal dot (1a2 must not restore).
			[0-9]*[.][0-9]*) ;;
			*) exit 0 ;;
		esac
		;;
	*) exit 0 ;;
esac
. /usr/libexec/fwlive-logging.sh
# Best-effort restore still exits 0 so a transient lock/pending-staging failure
# cannot strand the package half-removed. The baseline is kept on failure for
# admin recovery; helpers are still present while this prerm runs.
restore_wan_log_baseline || logger -t fwlive "WAN log baseline restore failed during uninstall"
exit 0
endef

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
