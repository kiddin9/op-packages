include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-zabbix

LUCI_TITLE:=zabbix agentd configuration
LUCI_DEPENDS:=+luci-base
LUCI_DEPENDS:=zabbix-agentd-ssl
LUCI_PKGARCH:=all

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
