include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-fancontrol
PKG_VERSION:=1.0.0
PKG_RELEASE:=5
PKG_LICENSE:=Apache-2.0
PKG_MAINTAINER:=Dante <dante@seckv.com>

LUCI_TITLE:=LuCI support for BPI-R4 PWM Fan Control
LUCI_DEPENDS:=+luci-base +ucode +ucode-mod-fs +ucode-mod-uci +ucode-mod-ubus
LUCI_PKGARCH:=all

define Package/$(PKG_NAME)/conffiles
/etc/config/fancontrol
endef

define Package/$(PKG_NAME)/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || {
	chmod 755 /etc/init.d/fancontrol /usr/sbin/fancontrold 2>/dev/null
	/etc/init.d/rpcd restart
	/etc/init.d/fancontrol enable
	/etc/init.d/fancontrol restart
}
exit 0
endef

define Package/$(PKG_NAME)/prerm
#!/bin/sh
if [ -z "$${IPKG_INSTROOT}" ]; then
	/etc/init.d/fancontrol stop
	/etc/init.d/fancontrol disable
fi
exit 0
endef

define Package/$(PKG_NAME)/postrm
#!/bin/sh
if [ -z "$${IPKG_INSTROOT}" ]; then
	rm -f /var/log/fancontrol.log*
	rm -f /var/run/fancontrol.*
fi
exit 0
endef

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
