# SPDX-License-Identifier: GPL-2.0-only
#
# Copyright (C) 2022-2023 ImmortalWrt.org
#

include $(TOPDIR)/rules.mk

LUCI_TITLE:=The modern ImmortalWrt proxy platform for ARM64/AMD64 (sing-box 1.14)
LUCI_PKGARCH:=all

# `cron` is a real dependency, not a convenience: runtime/service.sh writes two
# entries into /etc/crontabs/root and calls `/etc/init.d/cron restart`
# (hp_sync_resource_cron, hp_sync_autoupdate_cron, hp_clear_autoupdate_cron),
# and the resource-list refresh and the subscription update only ever run from
# those entries.  Without the package the writes still succeed - a crontab file
# is just a file - so the router looks fine while neither the China lists nor
# the subscriptions are ever refreshed again, and the only trace is a Warning
# in the log from the failed `cron restart`.
#
# DO NOT add `+cron` back.  There is no package by that name: ImmortalWrt
# 25.12.2's feeds carry 11 496 packages and none of them is called `cron`, and
# /etc/init.d/cron is a file of *busybox* (whose apk metadata provides only
# `busybox-any`).  An unsatisfiable dependency is not a missing-feature warning,
# it makes the package impossible to install at all - apk refuses to select it,
# and forcing the install (--force-broken-world) PURGES the installed package
# instead.  Measured on 192.168.1.1: r44 with `+cron` could not be installed,
# and the forced attempt removed the running package and left the router
# unproxied until r44 (built before that line existed) was put back.
#
# The dependency the original change was reaching for is real - the cron entries
# are load-bearing - but it is satisfied by busybox's crond, which every image
# in this family ships and which cannot be removed without removing busybox.
LUCI_DEPENDS:= \
	+sing-box \
	+firewall4 \
	+kmod-nft-tproxy \
    +ip-full \
    +kmod-tun \
	+uclient-fetch \
	+ucode-mod-digest

PKG_NAME:=luci-app-homeproxy-pro
PKG_VERSION:=28.10.1.14
PKG_RELEASE:=26

LUCI_BASENAME:=homeproxy-pro

define Package/luci-app-homeproxy-pro/conffiles
/etc/config/homeproxy-pro
/etc/homeproxy-pro/resources/china_ip4.txt
/etc/homeproxy-pro/resources/china_ip6.txt
/etc/homeproxy-pro/resources/china_list.txt
/etc/homeproxy-pro/resources/gfw_list.txt
/etc/homeproxy-pro/resources/china_ip4.ver
/etc/homeproxy-pro/resources/china_ip6.ver
/etc/homeproxy-pro/resources/china_list.ver
/etc/homeproxy-pro/resources/gfw_list.ver
endef

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
