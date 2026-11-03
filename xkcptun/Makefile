#
# Copyright (C) 2026 Dengfeng Liu <liudf0716@gmail.com>
#
# This is free software, licensed under the GNU General Public License v3.
# See /LICENSE for more information.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=xkcptun
PKG_RELEASE:=10

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/liudf0716/xkcptun.git
PKG_SOURCE_DATE:=2026-11-03
PKG_SOURCE_VERSION:=cddcd5e6d5dfa5d376dec0d2e8ef35fdc9409967
PKG_MIRROR_HASH:=skip

PKG_MAINTAINER:=Dengfeng Liu <liudf0716@gmail.com>
PKG_LICENSE:=GPL-3.0-or-later
PKG_LICENSE_FILES:=LICENSE

include $(INCLUDE_DIR)/package.mk
include $(INCLUDE_DIR)/cmake.mk

define Package/xkcptun
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=Web Servers/Proxies
  TITLE:=KCP-based Secure Tunnel in C
  URL:=https://github.com/liudf0716/xkcptun
  DEPENDS:=+libevent2
endef

define Package/xkcptun/description
  xkcptun is a lightweight and high-performance C language implementation of kcptun.
  This package contains the client and server binaries as well as the
  xkcp_spy monitoring tool.
endef

define Package/xkcptun/conffiles
/etc/config/xkcptun
endef

CMAKE_OPTIONS += \
	-DAUTO_INSTALL_DEPS=OFF

define Package/xkcptun/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_INSTALL_DIR)/usr/bin/xkcp_client $(1)/usr/bin/xkcp_client
	$(LN) xkcp_client $(1)/usr/bin/xkcptun-client
	$(INSTALL_BIN) $(PKG_INSTALL_DIR)/usr/bin/xkcp_server $(1)/usr/bin/xkcp_server
	$(LN) xkcp_server $(1)/usr/bin/xkcptun-server
	$(INSTALL_BIN) $(PKG_INSTALL_DIR)/usr/bin/xkcp_spy $(1)/usr/bin/xkcp_spy
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./files/xkcptun.config $(1)/etc/config/xkcptun
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/xkcptun.init $(1)/etc/init.d/xkcptun
endef

$(eval $(call BuildPackage,xkcptun))
