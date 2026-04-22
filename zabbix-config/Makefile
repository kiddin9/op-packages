
include $(TOPDIR)/rules.mk

PKG_NAME:=zabbix-config
PKG_VERSION:=1
PKG_RELEASE:=1
PKG_BUILD_DIR:=$(BUILD_DIR)/zabbix-config

include $(INCLUDE_DIR)/package.mk

define Package/zabbix-config
  SECTION:=admin
  CATEGORY:=Administration
  SUBMENU:=Zabbix
  TITLE:=Zabbix-config
  TITLE:=Additional configuration and init for zabbix-agent
  PKGARCH:=all
endef

define Package/zabbix-config/description
	 This package contains a changed config and init file for zabbix_agentd
endef

define Build/Prepare
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/zabbix-config/install
	$(INSTALL_DIR) $(1)/etc
	$(INSTALL_BIN) ./files/zabbix_agentd.conf $(1)/etc/zabbix_agentd.conf
	$(INSTALL_DIR) $(1)/etc/zabbix_agentd.conf.d
	$(INSTALL_BIN) ./files/device_template.conf $(1)/etc/zabbix_agentd.conf.d/
	$(INSTALL_DIR) $(1)/etc/config
	$(CP) ./files/zabbix.config $(1)/etc/config/zabbix
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/zabbix_agentd.init $(1)/etc/init.d/zabbix_agentd
endef

$(eval $(call BuildPackage,zabbix-config))
