include $(TOPDIR)/rules.mk

PKG_VERSION:=1.6.2
PKG_RELEASE:=17
PKG_LICENSE:=GPL-3.0-only
PKG_LICENSE_FILES:=LICENSE
PKG_MAINTAINER:=Kiddin'

LUCI_TITLE:=LuCI for System Online Upgrade
LUCI_DEPENDS:=+luci-base +curl +ca-bundle
LUCI_PKGARCH:=all

define Package/luci-app-ghfu/conffiles
/etc/config/ghfu
endef

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
