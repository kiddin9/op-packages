include $(TOPDIR)/rules.mk

THEME_NAME:=devgate
PKG_NAME:=luci-app-devgate

PKG_LICENSE:=Apache-2.0

LUCI_TITLE:=LuCI 设备门禁插件
LUCI_DESCRIPTION:=基于 firewall4 通信规则的设备门禁插件。
LUCI_DEPENDS:=+firewall4
LUCI_PKGARCH:=all
LUCI_MINIFY_CSS:=0

PKG_VERSION:=3.2.4
PKG_RELEASE:=1
define Build/Compile
endef

define Package/$(PKG_NAME)/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || {
	/etc/init.d/rpcd reload >/dev/null 2>&1 || true
	/etc/init.d/devgate enable >/dev/null 2>&1 || true
	/etc/init.d/devgate start >/dev/null 2>&1 || true
	rm -rf /tmp/luci-indexcache /tmp/luci-modulecache /tmp/luci-*cache
}
endef

define Package/$(PKG_NAME)/prerm
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || {
	[ -x /etc/init.d/devgate ] && /etc/init.d/devgate stop >/dev/null 2>&1 || true
	[ -x /usr/bin/devgate ] && /usr/bin/devgate stop >/dev/null 2>&1 || true
	rm -rf /tmp/luci-indexcache /tmp/luci-modulecache /tmp/luci-*cache
}
exit 0
endef

define Package/$(PKG_NAME)/postrm
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || {
	/etc/init.d/rpcd reload >/dev/null 2>&1 || true
	rm -rf /tmp/luci-indexcache /tmp/luci-modulecache /tmp/luci-*cache
}
exit 0
endef

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
