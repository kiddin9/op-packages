# SPDX-License-Identifier: GPL-3.0-only
#
# Copyright (C) 2021 ImmortalWrt.org
# Copyright (C) 2026 Amr Fateem <amr.fateem@yahoo.com>
#
# GeoSite database used by v2rayA.  The package is architecture independent
# and is updated independently of the v2rayA release by
# scripts/update-version.sh.

include $(TOPDIR)/rules.mk

PKG_NAME:=v2raya-geosite
PKG_VERSION:=20261118141523
PKG_RELEASE:=6

PKG_LICENSE:=MIT
PKG_MAINTAINER:=Amr Fateem <amr.fateem@yahoo.com>

include $(INCLUDE_DIR)/package.mk

GEOSITE_FILE:=dlc.dat.$(PKG_VERSION)
GEOSITE_HASH:=a033da583af17f15c9743f0b29aa5c073e9c1b8018a99ab4e69bc9ed5248a086

define Download/geosite
	URL:=https://github.com/v2fly/domain-list-community/releases/download/$(PKG_VERSION)/
	URL_FILE:=dlc.dat
	FILE:=$(GEOSITE_FILE)
	HASH:=skip
endef

define Package/v2raya-geosite
  TITLE:=GeoSite database for v2rayA
  SECTION:=net
  CATEGORY:=Network
  PKGARCH:=all
  URL:=https://github.com/v2fly/domain-list-community
endef

define Package/v2raya-geosite/description
  GeoSite database (geosite.dat) used by v2rayA and v2raya_core for routing.
endef

define Package/v2raya-geosite/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || {
	if [ -x /etc/init.d/v2raya ] && /etc/init.d/v2raya enabled; then
		/etc/init.d/v2raya restart
	fi
}
endef

define Build/Prepare
	$(call Build/Prepare/Default)
	$(call Download,geosite)
endef

define Build/Compile
endef

define Package/v2raya-geosite/install
	$(INSTALL_DIR) $(1)/usr/share/v2raya
	$(INSTALL_DATA) $(DL_DIR)/$(GEOSITE_FILE) $(1)/usr/share/v2raya/geosite.dat
endef

$(eval $(call Download,geosite))
$(eval $(call BuildPackage,v2raya-geosite))
