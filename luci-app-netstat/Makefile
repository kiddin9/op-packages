include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-netstat
PKG_VERSION:=1.2.0
PKG_RELEASE:=6

PKG_MAINTAINER:=NoobLK <liyanagelsofficial@gmail.com>
PKG_LICENSE:=GPL-3.0

LUCI_TITLE:=NET Stats
LUCI_DESCRIPTION:=This LuCI app provides net statistic functionality in a web interface.
LUCI_DEPENDS:=+vnstat2 +luci-compat +luci-lib-jsonc

include $(TOPDIR)/feeds/luci/luci.mk

define Package/luci-app-netstat/install
	$(CP) ./files/* $(1)/
	chmod 0755 $(1)/usr/libexec/netstat-vnstat-track
	# vnstat package owns /etc/config/vnstat on newer OpenWrt versions.
	# Remove it here to avoid file ownership conflicts if present in any tree.
	$(RM) $(1)/etc/config/vnstat
endef

define Package/luci-app-netstat/conffiles
/etc/config/netstats
endef

$(eval $(call BuildPackage,luci-app-netstat))
