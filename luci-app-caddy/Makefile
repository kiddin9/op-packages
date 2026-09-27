# luci-app-caddy - LuCI 管理 Caddy (反向代理 / ACME DNS-01 / Aliyun DDNS)
# Copyright (C) 2026 andangel - https://github.com/andangel/luci-app-caddy
#
# This is free software, licensed under the Apache License, Version 2.0 .
#

include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-caddy

LUCI_TITLE:=LuCI support for caddy
LUCI_DEPENDS:=+caddy
PKG_VERSION:=2.0
PKG_RELEASE:=3

define Package/$(PKG_NAME)/conffiles
/etc/config/caddy
/etc/caddy/Caddyfile
endef

define Package/$(PKG_NAME)/postrm
#!/bin/sh
[ -f /etc/caddy/Caddyfile ] && rm -rf /etc/caddy/Caddyfile >/dev/null 2>&1
return 0
endef

define Package/$(PKG_NAME)/postinst
#!/bin/sh
[ -n "${IPKG_INSTROOT}" ] || {
	( . /etc/uci-defaults/luci-caddy ) && rm -f /etc/uci-defaults/luci-caddy
	exit 0
}
endef

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
