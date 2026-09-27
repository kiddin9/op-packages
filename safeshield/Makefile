# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 3
# of the License, or (at your option) any later version.

include $(TOPDIR)/rules.mk

PKG_NAME:=safeshield
PKG_VERSION:=0.3.24
PKG_RELEASE:=1

PKG_MAINTAINER:=Beomjun Kang <kals323@gmail.com>
PKG_LICENSE:=GPL-3.0-or-later
PKG_LICENSE_FILES:=LICENSE

include $(INCLUDE_DIR)/package.mk

define Package/safeshield
  SECTION:=net
  CATEGORY:=Network
  TITLE:=SafeShield DNS Block Service
  URL:=https://github.com/Junatum/safeshield
  DEPENDS:= \
	+jshn \
	+jsonfilter \
	+uci \
	+uclient-fetch \
	+dnsmasq \
	+gzip \
	+coreutils-sort \
	+coreutils-cksum \
	+!BUSYBOX_DEFAULT_SHA256SUM:coreutils-sha256sum \
	+!BUSYBOX_DEFAULT_AWK:gawk \
	+!BUSYBOX_DEFAULT_GREP:grep \
	+!BUSYBOX_DEFAULT_SED:sed \
	+procd \
	+rpcd \
	+rpcd-mod-ucode \
	+ucode \
	+ucode-mod-fs \
	+ucode-mod-ubus \
	+ucode-mod-uci
  EXTRA_DEPENDS:=dnsmasq (>=2.93)
  PKGARCH:=all
endef

define Package/safeshield/description
SafeShield is a Lightweight, DNS-based protection for OpenWrt — block ads and phishing sites.
endef

define Package/safeshield/conffiles
/etc/config/safeshield
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/safeshield/install
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/etc/init.d/safeshield $(1)/etc/init.d/safeshield

	$(INSTALL_DIR) $(1)/usr/libexec
	$(INSTALL_BIN) ./files/usr/libexec/safeshield-refreshd $(1)/usr/libexec/safeshield-refreshd
	$(INSTALL_BIN) ./files/usr/libexec/safeshield-statsd $(1)/usr/libexec/safeshield-statsd
	$(INSTALL_BIN) ./files/usr/libexec/safeshield-stats-poll $(1)/usr/libexec/safeshield-stats-poll
	$(INSTALL_BIN) ./files/usr/libexec/safeshield-stats-identities $(1)/usr/libexec/safeshield-stats-identities
	$(INSTALL_BIN) ./files/usr/libexec/safeshield-statistics-uploader $(1)/usr/libexec/safeshield-statistics-uploader

	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./files/etc/config/safeshield $(1)/etc/config/safeshield
	$(INSTALL_DIR) $(1)/etc/uci-defaults
	$(INSTALL_BIN) ./files/etc/uci-defaults/90_safeshield_identity $(1)/etc/uci-defaults/90_safeshield_identity

	$(INSTALL_DIR) $(1)/usr/lib/safeshield
	$(INSTALL_BIN) ./files/usr/lib/safeshield/core.sh $(1)/usr/lib/safeshield/core.sh
	$(INSTALL_BIN) ./files/usr/lib/safeshield/log.sh $(1)/usr/lib/safeshield/log.sh
	$(INSTALL_BIN) ./files/usr/lib/safeshield/status.sh $(1)/usr/lib/safeshield/status.sh
	$(INSTALL_BIN) ./files/usr/lib/safeshield/utils.sh $(1)/usr/lib/safeshield/utils.sh
	$(INSTALL_DATA) ./files/usr/lib/safeshield/config.sh $(1)/usr/lib/safeshield/config.sh
	$(INSTALL_BIN) ./files/usr/lib/safeshield/identity.sh $(1)/usr/lib/safeshield/identity.sh
	$(INSTALL_DATA) ./files/usr/lib/safeshield/dns.sh $(1)/usr/lib/safeshield/dns.sh
	$(INSTALL_DATA) ./files/usr/lib/safeshield/blocklist.sh $(1)/usr/lib/safeshield/blocklist.sh
	$(INSTALL_DATA) ./files/usr/lib/safeshield/status-store.uc $(1)/usr/lib/safeshield/status-store.uc
	$(INSTALL_DATA) ./files/usr/lib/safeshield/statistics.sh $(1)/usr/lib/safeshield/statistics.sh
	$(INSTALL_DIR) $(1)/usr/lib/safeshield/statistics
	$(INSTALL_DATA) ./files/usr/lib/safeshield/statistics/*.awk $(1)/usr/lib/safeshield/statistics/
	echo '$(PKG_VERSION)-r$(PKG_RELEASE)' > $(1)/usr/lib/safeshield/version

	$(INSTALL_DIR) $(1)/usr/share/rpcd/ucode
	$(INSTALL_BIN) ./files/usr/share/rpcd/ucode/safeshield.uc $(1)/usr/share/rpcd/ucode/safeshield.uc
	$(INSTALL_DIR) $(1)/usr/share/rpcd/ucode/safeshield
	$(INSTALL_DATA) ./files/usr/share/rpcd/ucode/safeshield/*.uc $(1)/usr/share/rpcd/ucode/safeshield/
	$(INSTALL_DIR) $(1)/usr/share/rpcd/acl.d
	$(INSTALL_DATA) ./files/usr/share/rpcd/acl.d/safeshield.json $(1)/usr/share/rpcd/acl.d/safeshield.json
	$(INSTALL_DIR) $(1)/lib/upgrade/keep.d
	$(INSTALL_DATA) ./files/lib/upgrade/keep.d/safeshield $(1)/lib/upgrade/keep.d/safeshield

	$(INSTALL_DIR) $(1)/usr/share/licenses/safeshield
	$(INSTALL_DATA) ./LICENSE $(1)/usr/share/licenses/safeshield/GPL-3.0.txt
	$(INSTALL_DATA) ./THIRD_PARTY_NOTICES.md $(1)/usr/share/licenses/safeshield/THIRD_PARTY_NOTICES.md
endef

define Package/safeshield/postinst
#!/bin/sh
IPKG_INSTROOT="$${IPKG_INSTROOT:-}"
export IPKG_INSTROOT
PKG_NAME='safeshield'
export PKG_NAME
if [ -z "$${IPKG_INSTROOT}" ]; then
	mkdir -p /etc/safeshield
	if [ -r /usr/lib/safeshield/identity.sh ]; then
		(
			# apk may execute package lifecycle scripts with nounset enabled.
			# Runtime helpers are intentionally compatible with normal OpenWrt
			# /bin/sh semantics, so isolate them from the package-manager shell.
			set +u
			. /lib/functions.sh 2>/dev/null || true
			. /lib/functions/system.sh 2>/dev/null || true
			. /usr/lib/safeshield/utils.sh 2>/dev/null || true
			. /usr/lib/safeshield/log.sh 2>/dev/null || true
			. /usr/lib/safeshield/status.sh 2>/dev/null || true
			. /usr/lib/safeshield/config.sh 2>/dev/null || true
			. /usr/lib/safeshield/identity.sh 2>/dev/null || true
			. /usr/lib/safeshield/blocklist.sh 2>/dev/null || true
			ss_load_config >/dev/null 2>&1 || true
			model="$(ss_detect_device_model 2>/dev/null || cat /tmp/sysinfo/model 2>/dev/null || echo OpenWrt)"
			arch="$(ss_detect_device_arch 2>/dev/null || uname -m 2>/dev/null || echo unknown)"
			ss_identity_ensure "$model" "$arch" >/dev/null 2>&1 || true
		)
	fi
	if [ ! -f /etc/safeshield/allowlist ]; then
		cat << 'EOF' > /etc/safeshield/allowlist
# SafeShield allowlist
# Add domains to always allow (one per line)
EOF
	fi

	# Create default blocklist if not exists
	if [ ! -f /etc/safeshield/blocklist ]; then
		cat << 'EOF' > /etc/safeshield/blocklist
# SafeShield blocklist
# Add domains to always block (one per line)
EOF
	fi

	chmod 644 /etc/safeshield/allowlist
	chmod 644 /etc/safeshield/blocklist

	# Enable and restart service
	/etc/init.d/safeshield enable >/dev/null 2>&1 || true
	/etc/init.d/safeshield restart >/dev/null 2>&1 || true

	# Reload rpcd for LuCI integration
	if [ -x /etc/init.d/rpcd ]; then
		/etc/init.d/rpcd reload >/dev/null 2>&1 || \
		/etc/init.d/rpcd restart >/dev/null 2>&1 || true
	fi
fi
exit 0
endef

define Package/safeshield/prerm
#!/bin/sh
IPKG_INSTROOT="$${IPKG_INSTROOT:-}"
export IPKG_INSTROOT
if [ -z "$${IPKG_INSTROOT}" ]; then
	echo -n "Stopping safeshield service... "
	/etc/init.d/safeshield stop >/dev/null 2>&1 && echo "OK" || echo "FAIL"

	echo -n "Removing rc.d symlink for safeshield... "
	/etc/init.d/safeshield disable >/dev/null 2>&1 && echo "OK" || echo "FAIL"
fi
exit 0
endef

$(eval $(call BuildPackage,safeshield))
