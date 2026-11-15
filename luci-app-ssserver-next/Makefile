include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-ssserver-next
PKG_VERSION:=1.0.0
PKG_RELEASE:=3

PKG_MAINTAINER:=Dante <dante@example.com>
PKG_LICENSE:=Apache-2.0

LUCI_TITLE:=LuCI support for Shadowsocks-rust Server (Next)
LUCI_DEPENDS:=+shadowsocks-rust-ssserver-next +luci-base +ucode +ucode-mod-fs +ucode-mod-ubus
LUCI_PKGARCH:=all

define Package/luci-app-ssserver-next/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || {
	chmod +x /etc/init.d/ssserver 2>/dev/null || true
	/etc/init.d/rpcd restart >/dev/null 2>&1 || true
}
exit 0
endef

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
