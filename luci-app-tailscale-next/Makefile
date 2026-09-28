include $(TOPDIR)/rules.mk

LUCI_TITLE:=LuCI support for Tailscale Next
LUCI_URL:=https://github.com/tokisaki-galaxy/luci-app-tailscale-community
PKG_DESCRIPTION:=Provides a LuCI Web management interface for Tailscale, allowing viewing status, configuring nodes and daemons.
PKG_MAINTAINER:=Tokisaki-Galaxy <moebest@outlook.jp>
LUCI_DEPENDS:=+tailscale-next +ip-full +luci-base +ucode +ucode-mod-fs +ucode-mod-uci
LUCI_PKGARCH:=all

define Package/luci-app-tailscale-next/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || {
	rm -f /tmp/luci-indexcache.* /tmp/luci-modulecache/* 2>/dev/null
	chmod 0755 /etc/init.d/tailscale-settings /etc/hotplug.d/iface/99-tailscale-routes 2>/dev/null || true
	/etc/init.d/rpcd restart 2>/dev/null || true
}
exit 0
endef

define Package/luci-app-tailscale-next/prerm
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || {
	/etc/init.d/tailscale-settings clean_firewall 2>/dev/null || true
}
exit 0
endef

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
