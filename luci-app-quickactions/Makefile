include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-quickactions
PKG_VERSION:=3.0.0
PKG_RELEASE:=2

PKG_LICENSE:=Apache-2.0
PKG_MAINTAINER:=arafatrahmanzami <zamimondol@gmail.com>

LUCI_TITLE:=Quick Actions Dashboard
LUCI_DESCRIPTION:=Tabbed dashboard for OpenWrt with 14 modules: Dashboard, Essential, Tools, Logs, Services, Hotplug, Crontab, Guest WiFi, Terminal, Task Plan, Network Setup, Command, Dependencies.
LUCI_DEPENDS:=+luci-base +luci-app-commands +rpcd-mod-file +rpcd-mod-luci +ttyd
LUCI_PKGARCH:=all

include $(TOPDIR)/feeds/luci/luci.mk

define Package/luci-app-quickactions/conffiles
/etc/config/guestwifi
/etc/config/hotplug
/etc/config/quickactions
/etc/config/taskplan
/etc/config/wizard
endef

$(eval $(call BuildPackage,luci-app-quickactions))
