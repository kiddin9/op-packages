#
# Copyright (C) 2026 luci-app-substore
#
# This is free software, licensed under the GNU General Public License v2 or later.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-substore
# 版本约定：每次提交 PKG_RELEASE +1（2.1.2-r1 ~ r9）；
# 达到 r10 时 PKG_VERSION 末位 +1（2.1.2 -> 2.1.3），PKG_RELEASE 重置为 1。
PKG_VERSION:=2.6.0
PKG_RELEASE:=12

LUCI_DEPENDS:=+luci-lua-runtime +luci-compat

include $(INCLUDE_DIR)/package.mk
include $(TOPDIR)/feeds/luci/luci.mk

define Package/luci-app-substore
	SECTION:=luci
	CATEGORY:=LuCI
	SUBMENU:=3. Applications
	TITLE:=Airport subscription manager (Sub-Store like)
	PKG_MAINTAINER:=Arthur97172 <arthur97172@outlook.com>
	PKGARCH:=all
	DEPENDS:=$(LUCI_DEPENDS)
endef

define Package/luci-app-substore/description
	Native OpenWrt / ImmortalWrt LuCI application for managing
	airport subscriptions, parsing proxy nodes, filtering, deduplicating,
	merging and generating client subscription configs.
	Sub-Store like experience, without Docker or external services.
endef

define Build/Prepare
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/luci-app-substore/install
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./root/etc/config/substore $(1)/etc/config/substore

	$(INSTALL_DIR) $(1)/etc/uci-defaults
	$(INSTALL_BIN) ./root/etc/uci-defaults/99-substore $(1)/etc/uci-defaults/99-substore

	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) ./root/usr/bin/substore-cron.sh $(1)/usr/bin/substore-cron.sh

	$(INSTALL_DIR) $(1)/usr/lib/lua/substore
	$(INSTALL_DATA) ./root/usr/share/substore/*.lua $(1)/usr/lib/lua/substore/

	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/controller/admin
	$(INSTALL_DATA) ./root/usr/lib/lua/luci/controller/admin/substore.lua $(1)/usr/lib/lua/luci/controller/admin/substore.lua

	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/view/substore
	$(INSTALL_DATA) ./root/usr/lib/lua/luci/view/substore/subscriptions.htm $(1)/usr/lib/lua/luci/view/substore/subscriptions.htm
	$(INSTALL_DATA) ./root/usr/lib/lua/luci/view/substore/form.htm $(1)/usr/lib/lua/luci/view/substore/form.htm
	$(INSTALL_DATA) ./root/usr/lib/lua/luci/view/substore/local_form.htm $(1)/usr/lib/lua/luci/view/substore/local_form.htm
	$(INSTALL_DATA) ./root/usr/lib/lua/luci/view/substore/nodes.htm $(1)/usr/lib/lua/luci/view/substore/nodes.htm
	$(INSTALL_DATA) ./root/usr/lib/lua/luci/view/substore/node_edit.htm $(1)/usr/lib/lua/luci/view/substore/node_edit.htm

	$(INSTALL_DIR) $(1)/www/luci-static/resources/substore
	$(INSTALL_DATA) ./root/www/luci-static/resources/substore/nodeform.js $(1)/www/luci-static/resources/substore/nodeform.js
	$(INSTALL_DATA) ./root/usr/lib/lua/luci/view/substore/output.htm $(1)/usr/lib/lua/luci/view/substore/output.htm
	$(INSTALL_DATA) ./root/usr/lib/lua/luci/view/substore/combo.htm $(1)/usr/lib/lua/luci/view/substore/combo.htm

	$(INSTALL_DIR) $(1)/usr/share/luci/menu.d
	$(INSTALL_DATA) ./root/usr/share/luci/menu.d/luci-app-substore.json $(1)/usr/share/luci/menu.d/luci-app-substore.json

	# 简体中文翻译（运行时 zh-cn 时由 luci.template.parser 自动加载 *.zh-cn.lmo）
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/i18n
	po2lmo ./po/zh-cn/substore.po $(1)/usr/lib/lua/luci/i18n/substore.zh-cn.lmo
endef

define Package/luci-app-substore/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || {
	# 刷新 LuCI 缓存（现代 OpenWrt 已移除 lua 时代的 /lib/functions/luci.sh）
	rm -f /tmp/luci-indexcache
	[ -f /etc/init.d/luci ] && /etc/init.d/luci reload
	exit 0
}
endef

$(eval $(call BuildPackage,luci-app-substore))