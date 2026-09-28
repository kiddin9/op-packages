# SPDX-License-Identifier: GPL-3.0-only
#
# Copyright (C) 2024 asvow

include $(TOPDIR)/rules.mk

LUCI_TITLE:=LuCI for Tailscale
LUCI_DEPENDS:=+tailscale +jshn +curl +jq +flock
LUCI_PKGARCH:=all
PKG_VERSION:=1.2.17
PKG_RELEASE:=5

define Package/luci-app-tailscale/conffiles
/etc/config/tailscale
/etc/config/tailscale_openclash
/etc/config/tailscale_policy_routing
endef

define Package/luci-app-tailscale/prerm
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] && exit 0

if [ -x /usr/sbin/tailscale_policy_routing ]; then
	/usr/sbin/tailscale_policy_routing cleanup >/dev/null 2>&1 || true
fi

if [ -x /etc/init.d/tailscale-policy-routing ]; then
	/etc/init.d/tailscale-policy-routing stop >/dev/null 2>&1 || true
	/etc/init.d/tailscale-policy-routing disable >/dev/null 2>&1 || true
fi

if [ -x /usr/sbin/tailscale_openclash_bypass ]; then
	/usr/sbin/tailscale_openclash_bypass cleanup >/dev/null 2>&1 || true
fi

if [ -x /etc/init.d/tailscale-openclash-bypass ]; then
	/etc/init.d/tailscale-openclash-bypass stop >/dev/null 2>&1 || true
	/etc/init.d/tailscale-openclash-bypass disable >/dev/null 2>&1 || true
fi

if [ -x /etc/init.d/tailscale ]; then
	/etc/init.d/tailscale stop >/dev/null 2>&1 || true
fi

exit 0
endef

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
