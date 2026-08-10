#
# Copyright (C) 2006-2015 OpenWrt.org
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=zabbix-ssl
PKG_VERSION:=5.0.8
PKG_RELEASE:=1

PKG_SOURCE:=zabbix-$(PKG_VERSION).tar.gz
PKG_SOURCE_URL:=https://cdn.zabbix.com/zabbix/sources/stable/5.0/
PKG_HASH:=skip

PKG_BUILD_DIR=$(BUILD_DIR)/zabbix-$(PKG_VERSION)
PKG_MAINTAINER:=Etienne CHAMPETIER <champetier.etienne@gmail.com>
PKG_LICENSE:=GPL-2.0
PKG_LICENSE_FILES:=COPYING
PKG_CPE_ID:=cpe:/a:zabbix:zabbix

PKG_INSTALL:=1
PKG_BUILD_PARALLEL:=1

include $(INCLUDE_DIR)/package.mk
include $(INCLUDE_DIR)/nls.mk

define Package/zabbix-ssl/Default
  SECTION:=admin
  CATEGORY:=Administration
  SUBMENU:=Zabbix
  TITLE:=Zabbix-ssl
  URL:=https://www.zabbix.com/
  USERID:=zabbix=53:zabbix=53
  DEPENDS += $(ICONV_DEPENDS) +libpcre2 +zlib +libopenssl +libmariadbclient
endef

define Package/zabbix-agentd-ssl
  $(call Package/zabbix-ssl/Default)
  TITLE+= agentd-ssl
  DEPENDS += +libpq
endef

CONFIGURE_ARGS+= \
	--enable-agent \
	--enable-proxy \
	$(call autoconf_bool,CONFIG_IPV6,ipv6) \
	--disable-java \
	--with-mysql \
	--with-libevent=$(STAGING_DIR)/usr/include/libevent \
	--with-libpcre=$(STAGING_DIR)/usr/include \
	--with-zlib=$(STAGING_DIR)/usr/include \
	--with-openssl="$(STAGING_DIR)/usr"

CONFIGURE_VARS += \
	ac_cv_header_sys_sysinfo_h=no

MAKE_FLAGS += ARCH="linux"

define Package/zabbix-ssl/install/sbin
	$(INSTALL_DIR) \
		$(1)/usr/sbin

	$(INSTALL_BIN) \
		$(PKG_INSTALL_DIR)/usr/sbin/zabbix_$(2) \
		$(1)/usr/sbin/
endef

define Package/zabbix-ssl/install/bin
	$(INSTALL_DIR) \
		$(1)/usr/bin

	$(INSTALL_BIN) \
		$(PKG_INSTALL_DIR)/usr/bin/zabbix_$(2) \
		$(1)/usr/bin/
endef

define Package/zabbix-ssl/install/etc
	$(INSTALL_DIR) \
		$(1)/etc

	$(INSTALL_CONF) \
		$(PKG_INSTALL_DIR)/etc/zabbix_$(2).conf \
		$(1)/etc/
endef

define Build/Prepare
	$(call Build/Prepare/Default)
endef

define Build/Compile
	$(call Build/Compile/Default)
endef

define Package/zabbix-agentd-ssl/install
	$(INSTALL_DIR) $(1)/etc/zabbix_agentd.conf.d
	$(call Package/zabbix-ssl/install/sbin,$(1),agentd)
endef

$(eval $(call BuildPackage,zabbix-agentd-ssl))
