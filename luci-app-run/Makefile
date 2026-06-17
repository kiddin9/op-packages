include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-run
PKG_VERSION:=1.0.0
PKG_RELEASE:=3

LUCI_TITLE:=LuCI support for running makeself .run installers
LUCI_DESCRIPTION:=Upload and execute makeself-generated .run installers from LuCI.
LUCI_DEPENDS:=+luci-base +rpcd +libubox
LUCI_PKGARCH:=all

PKG_MAINTAINER:=wukongdaily <2666180@gmail.com>



include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
