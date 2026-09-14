# SPDX-License-Identifier: Apache-2.0
#
# Copyright (C) 2026 Dante <dante@seckv.com>
#
# This is free software, licensed under the Apache License, Version 2.0 .
#

include $(TOPDIR)/rules.mk

PKG_NAME:=linkback
PKG_VERSION:=1.0.0
PKG_RELEASE:=1
PKG_MAINTAINER:=Dante

PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)

include $(INCLUDE_DIR)/package.mk

define Package/$(PKG_NAME)
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=Routing and Redirection
  TITLE:=LinkBack gateway switch daemon
  DEPENDS:=+libuci +libubus +libubox +libblobmsg-json +ip-full
  MAINTAINER:=Dante
endef

define Package/$(PKG_NAME)/description
  LinkBack: A highly efficient and lightweight C-based Multi-WAN link health monitoring
  and dynamic route metric failover/failback daemon. Supports Ping, DNS, and TCP probes.
endef

define Package/$(PKG_NAME)/conffiles
/etc/config/linkback
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
	$(CP) ./src/* $(PKG_BUILD_DIR)/
endef

define Build/Compile
	$(MAKE) -C $(PKG_BUILD_DIR) \
		CC="$(TARGET_CC)" \
		CFLAGS="$(TARGET_CFLAGS)" \
		LDFLAGS="$(TARGET_LDFLAGS)"
endef

define Package/$(PKG_NAME)/install
	# Install C daemon binary
	$(INSTALL_DIR) $(1)/usr/sbin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/linkbackd $(1)/usr/sbin/linkbackd

	# Install config and init files
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./files/linkback.config $(1)/etc/config/linkback
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/linkback.init $(1)/etc/init.d/linkback
endef

define Package/$(PKG_NAME)/postinst
#!/sh
[ -n "$${IPKG_INSTROOT}" ] || {
	/etc/init.d/linkback enable
	/etc/init.d/linkback restart
}
exit 0
endef

$(eval $(call BuildPackage,$(PKG_NAME)))
