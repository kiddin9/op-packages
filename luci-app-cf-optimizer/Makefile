include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-cf-optimizer
PKG_VERSION:=1.0.0
PKG_RELEASE:=1
PKG_LICENSE:=Apache-2.0
PKG_MAINTAINER:=Dante <dante@seckv.com>

LUCI_TITLE:=LuCI support for Cloudflare Proxy and Tunnel Host Optimizer
LUCI_DEPENDS:=+luci-base +curl +ucode +ucode-mod-fs +ucode-mod-uci +ucode-mod-ubus
LUCI_PKGARCH:=all

define Package/$(PKG_NAME)/conffiles
/etc/config/cf-optimizer
endef

define Package/$(PKG_NAME)/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || {
	rm -f /tmp/luci-indexcache.* /tmp/luci-modulecache/* 2>/dev/null
	chmod 755 /etc/init.d/cf-optimizer /usr/sbin/cf-optimizer 2>/dev/null
	/etc/init.d/cf-optimizer enable 2>/dev/null || true
	/etc/init.d/rpcd restart
}
exit 0
endef

define Package/$(PKG_NAME)/prerm
#!/bin/sh
if [ -z "$${IPKG_INSTROOT}" ]; then
	/etc/init.d/cf-optimizer stop
	/etc/init.d/cf-optimizer disable
	/usr/sbin/cf-optimizer clean
fi
exit 0
endef

define Package/$(PKG_NAME)/postrm
#!/bin/sh
if [ -z "$${IPKG_INSTROOT}" ]; then
	rm -rf /tmp/run/cf-optimizer /tmp/cf-optimizer
	rm -f /tmp/hosts/cf-optimizer /var/log/cf-optimizer.log*
	killall -HUP dnsmasq 2>/dev/null
fi
exit 0
endef

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
