# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 3
# of the License, or (at your option) any later version.

include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-smartsafehub
PKG_VERSION:=0.2.23
PKG_RELEASE:=2

PKG_MAINTAINER:=Beomjun Kang <kals323@gmail.com>
PKG_LICENSE:=GPL-3.0-or-later
PKG_LICENSE_FILES:=LICENSE

LUCI_TITLE:=SmartSafeHub
LUCI_URL:=https://github.com/Junatum/luci-app-smartsafehub
LUCI_DESCRIPTION:=A modern, user-friendly OpenWrt management platform with Wi-Fi control, device management, system monitoring, and SafeShield DNS protection.
LUCI_DEPENDS:=+luci-base +rpcd-mod-ucode +ucode +ucode-mod-ubus +ucode-mod-fs +ucode-mod-uci +procd +uclient-fetch +jsonfilter +igmpproxy +safeshield
LUCI_EXTRA_DEPENDS:=safeshield (>=0.3.24)
LUCI_PKGARCH:=all

define Package/luci-app-smartsafehub/conffiles
/etc/config/smartsafehub
endef

define Package/luci-app-smartsafehub/preinst
#!/bin/sh
if [ -z "$${IPKG_INSTROOT}" ]; then
	# SmartSafeHub Reset Policy v1 requires the firmware build to remove the
	# stock OpenWrt /etc/rc.button/reset before this package owns that path.
	# Refuse live upgrades on older firmware rather than risking a package file
	# collision or showing 5-9 second recovery guidance while OpenWrt still
	# interprets the same hold as an immediate factory reset.
	if [ -f /etc/rc.button/reset ] && ! grep -Fq "SMARTSAFEHUB_RESET_POLICY='smartsafehub-v1'" /etc/rc.button/reset 2>/dev/null; then
		echo "luci-app-smartsafehub: firmware update required for SmartSafeHub Reset Policy v1" >&2
		exit 1
	fi
	# r18 and earlier had Cloud activity sync enabled implicitly whenever the
	# device was eligible. Preserve that behavior across the r19 upgrade even
	# if opkg replaces an otherwise-unmodified conffile with the new default-off
	# package config. Fresh installs have no existing activity-sync helper and
	# therefore keep the new explicit opt-in default.
	if [ -x /usr/libexec/smartsafehub-activity-sync ] && ! uci -q get smartsafehub.activity.cloud_sync_enabled >/dev/null 2>&1; then
		mkdir -p /tmp/smartsafehub
		: > /tmp/smartsafehub/activity-cloud-sync-upgrade-enable
	fi
fi
exit 0
endef

define Package/luci-app-smartsafehub/postinst
#!/bin/sh
if [ -z "$${IPKG_INSTROOT}" ]; then
	mkdir -p /tmp/smartsafehub
	uci -q delete smartsafehub.firmware.check_enabled >/dev/null 2>&1 || true
	if [ -f /tmp/smartsafehub/activity-cloud-sync-upgrade-enable ]; then
		uci -q set smartsafehub.activity.cloud_sync_enabled='1' >/dev/null 2>&1 || true
		rm -f /tmp/smartsafehub/activity-cloud-sync-upgrade-enable
	fi
	uci -q commit smartsafehub >/dev/null 2>&1 || true
	if [ -x /etc/init.d/smartsafehub-events ]; then
		/etc/init.d/smartsafehub-events enable
		/etc/init.d/smartsafehub-events restart >/dev/null 2>&1 || true
	fi
	if [ -x /etc/init.d/smartsafehub-activity-sync ]; then
		/etc/init.d/smartsafehub-activity-sync enable
		/etc/init.d/smartsafehub-activity-sync restart >/dev/null 2>&1 || true
	fi
	if [ -x /etc/init.d/smartsafehub-updater ]; then
		/etc/init.d/smartsafehub-updater enable
	fi
	if [ -x /etc/init.d/smartsafehub-firmware ]; then
		/etc/init.d/smartsafehub-firmware enable
	fi
	if [ -x /etc/init.d/smartsafehub-maintenance ]; then
		/etc/init.d/smartsafehub-maintenance enable
	fi
	if [ -x /etc/init.d/smartsafehub-password-recovery ]; then
		/etc/init.d/smartsafehub-password-recovery enable
		/etc/init.d/smartsafehub-password-recovery start >/dev/null 2>&1 || true
	fi
	if [ -x /etc/init.d/smartsafehub-health ]; then
		/etc/init.d/smartsafehub-health enable
		/etc/init.d/smartsafehub-health restart >/dev/null 2>&1 || true
	fi
	if [ -x /etc/init.d/smartsafehub-license ]; then
		/etc/init.d/smartsafehub-license enable
		/etc/init.d/smartsafehub-license restart >/dev/null 2>&1 || true
	fi
	if [ -x /etc/init.d/igmpproxy ]; then
		if [ "$$(uci -q get smartsafehub.iptv.enabled 2>/dev/null)" = "1" ]; then
			/etc/init.d/igmpproxy enable >/dev/null 2>&1 || true
		else
			/etc/init.d/igmpproxy stop >/dev/null 2>&1 || true
			/etc/init.d/igmpproxy disable >/dev/null 2>&1 || true
		fi
	fi
	if [ -f /usr/libexec/smartsafehub-root-entry ]; then
		/bin/sh /usr/libexec/smartsafehub-root-entry --install --reconcile
	fi
	rm -f /tmp/luci-indexcache
	if [ -f /usr/libexec/smartsafehub-rpcd-reconcile ]; then
		/bin/sh /usr/libexec/smartsafehub-rpcd-reconcile >/dev/null 2>&1 || true
	fi
fi
exit 0
endef

define Package/luci-app-smartsafehub/prerm
#!/bin/sh
if [ -z "$${IPKG_INSTROOT}" ] && [ -f /usr/libexec/smartsafehub-root-entry ]; then
	/bin/sh /usr/libexec/smartsafehub-root-entry --remove --reconcile
fi
exit 0
endef

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
