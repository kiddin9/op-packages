# SPDX-License-Identifier: Apache-2.0
#
# 7Dollar — an elegant, lightweight LuCI theme.
# Drop this directory into feeds/luci/themes/ (or package/) of an OpenWrt
# buildroot / SDK and select it under LuCI -> Themes.

include $(TOPDIR)/rules.mk

PKG_NAME:=luci-theme-7dollar
PKG_VERSION:=1.0.16
PKG_RELEASE:=1

LUCI_TITLE:=7Dollar — an elegant, lightweight LuCI theme
LUCI_DESCRIPTION:=A calm, card based LuCI theme with five palettes, light/dark mode, \
	a friendly home dashboard and grouped navigation. Built for OpenWrt 23.05+ (ucode LuCI).
LUCI_DEPENDS:=+luci-base
LUCI_PKGARCH:=all

PKG_LICENSE:=Apache-2.0
PKG_MAINTAINER:=itsmaiGe <https://github.com/itsmaiGe>

define Package/luci-theme-7dollar/conffiles
/etc/config/7dollar
endef

define Package/luci-theme-7dollar/postrm
#!/bin/sh
[ "$$1" = upgrade ] && exit 0
[ -n "$${IPKG_INSTROOT}" ] || {
	uci -q delete luci.themes.7Dollar
	[ "$$(uci -q get luci.main.mediaurlbase)" = "/luci-static/7dollar" ] && \
		uci -q set luci.main.mediaurlbase=/luci-static/bootstrap
	uci commit luci
	rm -rf /tmp/luci-indexcache* /tmp/luci-modulecache/
}
endef

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
