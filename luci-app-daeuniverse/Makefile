# Copyright (C) 2016 Openwrt.org
# Copyright (C) 2026 QiuSimons <https://github.com/QiuSimons>
#
# This is free software, licensed under the Apache License, Version 2.0 .
#

include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-daeuniverse
PKG_VERSION:=2.0.0
PKG_RELEASE:=2

LUCI_TITLE:=LuCI support for DAE Universe (honk / dae)
LUCI_PKGARCH:=all
LUCI_DEPENDS:=@(aarch64||x86_64) \
	+luci-base +unzip \
	+DAEU_WITH_HONK:honk \
	+DAEU_WITH_DAE:dae
PKG_CONFIG_DEPENDS:=CONFIG_DAEU_WITH_HONK CONFIG_DAEU_WITH_DAE

define Package/luci-app-daeuniverse/config
	config DAEU_WITH_HONK
		bool "Include honk core engine (default core)"
		default y

	config DAEU_WITH_DAE
		bool "Include dae core engine (kdae)"
		default y
endef

define Package/luci-app-daeuniverse/conffiles
/etc/config/daeuniverse
/etc/daeuniverse/honk/config.dae
/etc/daeuniverse/honk/config.d/api.dae
/etc/daeuniverse/honk/config.d/dns.dae
/etc/daeuniverse/honk/config.d/node.dae
/etc/daeuniverse/honk/config.d/route.dae
/etc/daeuniverse/dae/config.dae
/etc/daeuniverse/dae/api.dae
/etc/daeuniverse/dae/config.d/global.dae
/etc/daeuniverse/dae/config.d/dns.dae
/etc/daeuniverse/dae/config.d/node.dae
/etc/daeuniverse/dae/config.d/subscription.dae
/etc/daeuniverse/dae/config.d/group.dae
/etc/daeuniverse/dae/config.d/routing.dae
endef

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
