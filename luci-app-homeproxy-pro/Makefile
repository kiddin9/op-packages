# SPDX-License-Identifier: GPL-2.0-only
#
# Copyright (C) 2022-2023 ImmortalWrt.org
#

include $(TOPDIR)/rules.mk

LUCI_TITLE:=The modern ImmortalWrt proxy platform for ARM64/AMD64 (sing-box 1.14)
# Pure ucode/JS payload with no compiled code, so the package itself is arch
# independent. The real arch constraint comes from the +sing-box dependency,
# which the feed builds for every architecture Go supports (aarch64, arm,
# mipsel, riscv64, x86_64, ...); where no sing-box package exists, dependency
# resolution refuses the install. Checked against the ImmortalWrt 25.12.1
# package index (sing-box 1.14.0-r1 published for all of the above).
LUCI_PKGARCH:=all
LUCI_DEPENDS:= \
	+sing-box \
	+firewall4 \
	+kmod-nft-tproxy \
    +ip-full \
    +kmod-tun \
	+ucode-mod-digest

PKG_NAME:=luci-app-homeproxy-pro
PKG_VERSION:=28.9.1.14
PKG_RELEASE:=8

# Only files the package actually ships belong here.  The previous list named
# four paths that exist nowhere in the tree - certs/ and ruleset/ are created at
# runtime, and the two *_list.txt files are written by the LuCI ACL editor - so
# those declarations did nothing.  What is listed instead is the resource data
# the router updates by itself: on a running device those files are newer than
# the ones in the package, and without this an upgrade would overwrite them.
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
