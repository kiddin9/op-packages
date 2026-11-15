include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-frpc-next
PKG_VERSION:=1.0.0
PKG_RELEASE:=2

PKG_LICENSE:=MIT
PKG_MAINTAINER:=Dante <dante@seckv.com>

LUCI_TITLE:=LuCI support for frp client (v0.68.x/v0.69.x+)
LUCI_DEPENDS:=+frpc-next +curl
LUCI_PKGARCH:=all
PKG_PROVIDES:=luci-app-frpc

define Package/$(PKG_NAME)/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || {
	chmod 0755 /etc/init.d/frpc /etc/hotplug.d/iface/99-frpc 2>/dev/null || true
	/etc/init.d/rpcd restart >/dev/null 2>&1 || true
}
exit 0
endef

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
