
include $(TOPDIR)/rules.mk

PKG_NAME:=xl2tpd-ext
PKG_VERSION:=1
PKG_RELEASE:=1
PKG_BUILD_DIR:=$(BUILD_DIR)/xl2tpd-ext

include $(INCLUDE_DIR)/package.mk

define Package/xl2tpd-ext
  TITLE:=xl2tpd server additional scripts
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=VPN
  PKGARCH:=all
endef

define Package/xl2tpd-ext/description
	 This package contains additional scripts and configuration files for xl2tpd
endef

define Build/Prepare
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/xl2tpd-ext/install
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/xl2tpd.init $(1)/etc/init.d/xl2tpd

	$(INSTALL_DIR) $(1)/etc/xl2tpd
	$(INSTALL_BIN) ./files/l2tp-up $(1)/etc/xl2tpd/l2tp-up
	$(INSTALL_BIN) ./files/l2tp-down $(1)/etc/xl2tpd/l2tp-down
	$(CP) ./files/xl2tpd.conf $(1)/etc/xl2tpd/xl2tpd.conf

	$(INSTALL_DIR) $(1)/etc/ppp
	$(CP) ./files/options.xl2tpd $(1)/etc/ppp/options.xl2tpd

	$(INSTALL_DIR) $(1)/etc/config
	$(CP) ./files/xl2tpd.config $(1)/etc/config/xl2tpd

	$(INSTALL_DIR) $(1)/lib/netifd/proto
	$(INSTALL_BIN) ./files/l2tp.sh $(1)/lib/netifd/proto/l2tp.sh
endef

$(eval $(call BuildPackage,xl2tpd-ext))
