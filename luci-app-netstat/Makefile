include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-netstat
PKG_VERSION:=1.1.5
PKG_RELEASE:=1

PKG_MAINTAINER:=NoobLK <liyanagelsofficial@gmail.com>
PKG_LICENSE:=GPL-3.0

LUCI_TITLE:=NET Stats
LUCI_DESCRIPTION:=This LuCI app provides net statistic functionality in a web interface.
LUCI_DEPENDS:=+vnstat +luci-compat

include $(TOPDIR)/feeds/luci/luci.mk

define Package/luci-app-netstat/install
	$(CP) ./files/* $(1)/
	# vnstat package owns /etc/config/vnstat on newer OpenWrt versions.
	# Remove it here to avoid file ownership conflicts if present in any tree.
	$(RM) $(1)/etc/config/vnstat
endef

$(eval $(call BuildPackage,luci-app-netstat))
