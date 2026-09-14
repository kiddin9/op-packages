include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-ap-switch
PKG_VERSION:=1.0.0
PKG_RELEASE:=1
PKG_LICENSE:=Apache-2.0
PKG_MAINTAINER:=Dante

LUCI_TITLE:=LuCI support for one-click AP mode switching
LUCI_DEPENDS:=+luci-base +ucode +ucode-mod-fs +ucode-mod-uci +ucode-mod-ubus
LUCI_PKGARCH:=all

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
