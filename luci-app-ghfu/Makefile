include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-ghfu
PKG_VERSION:=1.6.1
PKG_RELEASE:=14
PKG_LICENSE:=GPL-3.0-only
PKG_LICENSE_FILES:=LICENSE
PKG_MAINTAINER:=Kiddin'

LUCI_TITLE:=LuCI for System Online Upgrade
LUCI_DEPENDS:=+luci-base +curl +wget-ssl +ca-bundle
LUCI_PKGARCH:=all

ifneq ($(wildcard $(TOPDIR)/feeds/luci/luci.mk),)
  include $(TOPDIR)/feeds/luci/luci.mk
else
  include $(TOPDIR)/feeds/luci/luci.mk
endif

# call BuildPackage - OpenWrt buildroot signature
