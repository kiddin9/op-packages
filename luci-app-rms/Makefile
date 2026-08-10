#
# OpenWrt LuCI application for RMS configuration.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-rms
PKG_VERSION:=1.0.0
PKG_RELEASE:=1

LUCI_TITLE:=LuCI support for RMS
LUCI_DEPENDS:=+luci-base +rms
LUCI_PKGARCH:=all

PKG_LICENSE:=Proprietary
PKG_MAINTAINER:=RMS

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
