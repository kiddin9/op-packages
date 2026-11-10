# SPDX-License-Identifier: GPL-3.0-only
#
# Copyright (C) 2021 ImmortalWrt.org
# Copyright (C) 2026 Amr Fateem <amr.fateem@yahoo.com>
#
# GeoIP database used by v2rayA.  The package is architecture independent and
# is updated independently of the v2rayA release by scripts/update-version.sh.

include $(TOPDIR)/rules.mk

PKG_NAME:=v2raya-geoip
PKG_VERSION:=202611050539
PKG_RELEASE:=1

PKG_LICENSE:=CC-BY-SA-4.0
PKG_MAINTAINER:=Amr Fateem <amr.fateem@yahoo.com>

include $(INCLUDE_DIR)/package.mk

GEOIP_FILE:=geoip.dat.$(PKG_VERSION)
GEOIP_HASH:=eedb24b3b9fcba27e06b92c0428dab90d9496083091ae4cf39e11387fd99d0e2

define Download/geoip
	URL:=https://github.com/v2fly/geoip/releases/download/$(PKG_VERSION)/
	URL_FILE:=geoip.dat
	FILE:=$(GEOIP_FILE)
	HASH:=skip
endef

define Package/v2raya-geoip
  TITLE:=GeoIP database for v2rayA
  SECTION:=net
  CATEGORY:=Network
  PKGARCH:=all
  URL:=https://github.com/v2fly/geoip
endef

define Package/v2raya-geoip/description
  GeoIP database (geoip.dat) used by v2rayA and v2raya_core for routing.
endef

define Package/v2raya-geoip/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || {
	if [ -x /etc/init.d/v2raya ] && /etc/init.d/v2raya enabled; then
		/etc/init.d/v2raya restart
	fi
}
endef

define Build/Prepare
	$(call Build/Prepare/Default)
	$(call Download,geoip)
endef

define Build/Compile
endef

define Package/v2raya-geoip/install
	$(INSTALL_DIR) $(1)/usr/share/v2raya
	$(INSTALL_DATA) $(DL_DIR)/$(GEOIP_FILE) $(1)/usr/share/v2raya/geoip.dat
endef

$(eval $(call Download,geoip))
$(eval $(call BuildPackage,v2raya-geoip))
