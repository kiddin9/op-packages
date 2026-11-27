#
# Copyright (C) 2025-2026 ox1d3x3 <https://github.com/ox1d3x3>
#
# UniWRT Portal — a network-controller-style standalone LuCI theme.
# This is free software, licensed under the Apache License 2.0.
#

include $(TOPDIR)/rules.mk

LUCI_TITLE:=UniWRT Portal - a modern controller-style LuCI theme
LUCI_DEPENDS:=+luci-base
LUCI_PKGARCH:=all

PKG_NAME:=luci-theme-uniwrt
PKG_VERSION:=$(shell cat $(CURDIR)/ucode/template/themes/uniwrt/version | tr -d '[:space:]')
# CI may pass THEME_RELEASE (e.g. the run number) for unique nightly builds;
# falls back to 1 for normal/local builds.
PKG_RELEASE:=2
PKG_LICENSE:=Apache-2.0
PKG_MAINTAINER:=ox1d3x3 <https://github.com/ox1d3x3>

# csstidy is a CSS2-era minifier that mangles modern CSS (backdrop-filter,
# multi-stop gradients, custom properties). Disable it so our committed,
# pre-built CSS reaches the device byte-for-byte.
CONFIG_LUCI_CSSTIDY:=

include $(TOPDIR)/feeds/luci/luci.mk

define Package/luci-theme-uniwrt/conffiles
/etc/config/uniwrt
endef

define Package/luci-theme-uniwrt/postrm
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || {
	uci -q batch <<-EOF
		delete luci.themes.UniWRT
		commit luci
	EOF
	rm -rf /tmp/luci-indexcache* /tmp/luci-modulecache 2>/dev/null
}
exit 0
endef

# call BuildPackage - OpenWrt buildroot signature
