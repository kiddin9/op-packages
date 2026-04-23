include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-xl2tpd

LUCI_TITLE:=xl2tpd server configuration
LUCI_DEPENDS:=+luci-base +xl2tpd-ext +ppp-mod-pppol2tp
LUCI_PKGARCH:=all

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature