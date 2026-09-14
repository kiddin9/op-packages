include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-frpc-next
PKG_VERSION:=1.0.0
PKG_RELEASE:=1

PKG_LICENSE:=MIT
PKG_MAINTAINER:=Dante <dante@seckv.com>

LUCI_TITLE:=LuCI support for frp client (v0.68.x/v0.69.x+)
LUCI_DEPENDS:=+frpc-next +curl
LUCI_PKGARCH:=all

include $(TOPDIR)/feeds/luci/luci.mk

define Package/$(PKG_NAME)
  $(call Package/luci/webtemplate)
  TITLE:=$(LUCI_TITLE)
  DEPENDS:=$(LUCI_DEPENDS)
  PROVIDES:=luci-app-frpc
  CONFLICTS:=luci-app-frpc
endef

define Package/$(PKG_NAME)/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || {
	chmod 0755 /etc/init.d/frpc /etc/hotplug.d/iface/99-frpc 2>/dev/null || true
}
exit 0
endef

# call BuildPackage - OpenWrt buildroot signature
