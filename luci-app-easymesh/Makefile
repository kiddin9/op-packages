include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-easymesh
PKG_VERSION:=2.4.1
PKG_RELEASE:=4

PKG_LICENSE:=GPL-2.0
PKG_MAINTAINER:=Arafat Rahman Zami Mondol <zamimondol@gmail.com>
PKG_URL:=https://github.com/arafatrahmanzami/luci-app-easymesh

LUCI_TITLE:=LuCI Management Interface for EasyMesh (Batman-adv mesh)
LUCI_DESCRIPTION:=LuCI app for configuring and monitoring a Batman-adv \
	based 802.11s mesh network. Requires a wpad-mesh-* package \
	(openssl, wolfssl, or mbedtls) to be installed separately.

# ---- Runtime dependencies --------------------------------------------
# Wireless stack

LUCI_DEPENDS:= \
	+kmod-cfg80211 \
	+kmod-batman-adv \
	+luci-proto-batman-adv \
	+batctl-default \
	+luci-compat \
	+luci-lua-runtime \
	+wpad-mbedtls \
	+libiwinfo-lua 

# Client steering (works with or without usteer)
LUCI_DEPENDS += \
	+usteer \
	+luci-app-usteer 

LUCI_PKGARCH:=all

define Package/luci-app-easymesh/conffiles
/etc/config/easymesh
endef

define Package/luci-app-easymesh/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] && exit 0
rm -f /tmp/luci-indexcache 2>/dev/null
/etc/init.d/rpcd restart 2>/dev/null
/etc/init.d/uhttpd restart 2>/dev/null
exit 0
endef

include $(TOPDIR)/feeds/luci/luci.mk
# call BuildPackage - OpenWrt buildroot signature
