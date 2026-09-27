#
# Copyright (C) 2026 SyntaxError NullPointer
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=thermal-guard
PKG_VERSION:=2.0.0
PKG_RELEASE:=1

PKG_LICENSE:=GPL-2.0-only
PKG_LICENSE_FILES:=LICENSE
PKG_MAINTAINER:=SyntaxError NullPointer <287466119+SyntaxError-NullPointer@users.noreply.github.com>

include $(INCLUDE_DIR)/package.mk

define Package/thermal-guard
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=Overheating protection with staged mitigation
  DEPENDS:=+libubox +ubus +coreutils-timeout +jsonfilter
  PKGARCH:=all
endef

define Package/thermal-guard/description
  Watches SoC and modem temperature and escalates in stages when a router runs
  hot, typically after a fan failure: fan to full speed, modem radio off, Wi-Fi
  off. Stages do not roll back on their own, clearing them is an operator
  decision, and they survive a reboot. Fan control works either through the
  kernel thermal zone or through sysfs PWM, modem temperature through Quectel or
  Fibocom AT commands, a file or a hook script. Warnings are posted to a URL.
  Where the kernel drives the fan, it can lower the fan's trip points while the
  modem runs hotter than the CPU.
endef

define Package/thermal-guard/conffiles
/etc/config/thermal-guard
endef

# procd keeps an instance whose command line did not change, so without this
# an upgrade leaves the old daemon running. A service that was stopped stays so.
define Package/thermal-guard/postinst
#!/bin/sh
[ "$${PKG_UPGRADE}" = 1 ] && [ -z "$${IPKG_INSTROOT}" ] &&
	/etc/init.d/thermal-guard running && /etc/init.d/thermal-guard restart
exit 0
endef

define Build/Compile
endef

define Package/thermal-guard/install
	$(INSTALL_DIR) $(1)/usr/sbin $(1)/usr/libexec $(1)/usr/share/thermal-guard $(1)/etc/config $(1)/etc/init.d $(1)/etc/uci-defaults $(1)/etc/thermal-guard/hooks $(1)/lib/upgrade/keep.d
	$(INSTALL_DATA) ./files/lib/upgrade/keep.d/thermal-guard $(1)/lib/upgrade/keep.d/thermal-guard
	$(INSTALL_DATA) ./files/etc/thermal-guard/hooks/README $(1)/etc/thermal-guard/hooks/README
	$(INSTALL_BIN) ./files/usr/sbin/thermal-guard $(1)/usr/sbin/thermal-guard
	$(INSTALL_DATA) ./files/usr/share/thermal-guard/backends.sh $(1)/usr/share/thermal-guard/backends.sh
	$(INSTALL_DATA) ./files/usr/share/thermal-guard/trips.sh $(1)/usr/share/thermal-guard/trips.sh
	$(INSTALL_CONF) ./files/etc/config/thermal-guard $(1)/etc/config/thermal-guard
	$(INSTALL_BIN) ./files/etc/init.d/thermal-guard $(1)/etc/init.d/thermal-guard
	$(INSTALL_BIN) ./files/etc/uci-defaults/90-thermal-guard-trip-base $(1)/etc/uci-defaults/
	$(INSTALL_BIN) ./files/usr/libexec/thermal-guard-collectd $(1)/usr/libexec/thermal-guard-collectd
endef

$(eval $(call BuildPackage,thermal-guard))
