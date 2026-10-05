#
# Copyright (C) 2026 luci-app-substore
#
# This is free software, licensed under the GNU General Public License v3 or later.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-substore
# 版本约定：每次提交 PKG_RELEASE +1（2.1.2-r1 ~ r9）；
# 达到 r10 时 PKG_VERSION 末位 +1（2.1.2 -> 2.1.3），PKG_RELEASE 重置为 1。
PKG_VERSION:=2.7.2
PKG_RELEASE:=19

LUCI_DEPENDS:=+luci-lua-runtime +luci-compat

include $(INCLUDE_DIR)/package.mk
include $(TOPDIR)/feeds/luci/luci.mk

define Package/luci-app-substore
	SECTION:=luci
	CATEGORY:=LuCI
	SUBMENU:=3. Applications
	TITLE:=Airport subscription manager (Sub-Store like)
	PKG_MAINTAINER:=Arthur97172 <Arthur97172@users.noreply.github.com>
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
	$(INSTALL_DATA) ./root/usr/lib/lua/luci/view/substore/output.htm $(1)/usr/lib/lua/luci/view/substore/output.htm
	$(INSTALL_DATA) ./root/usr/lib/lua/luci/view/substore/combo.htm $(1)/usr/lib/lua/luci/view/substore/combo.htm

	$(INSTALL_DIR) $(1)/www/luci-static/resources/substore
	$(INSTALL_DATA) ./root/www/luci-static/resources/substore/nodeform.js $(1)/www/luci-static/resources/substore/nodeform.js

	$(INSTALL_DIR) $(1)/usr/share/luci/menu.d
	$(INSTALL_DATA) ./root/usr/share/luci/menu.d/luci-app-substore.json $(1)/usr/share/luci/menu.d/luci-app-substore.json

	# ACL 组：菜单 depends.acl 引用它，未授权的 LuCI 用户看不到本应用
	$(INSTALL_DIR) $(1)/usr/share/rpcd/acl.d
	$(INSTALL_DATA) ./root/usr/share/rpcd/acl.d/luci-app-substore.json $(1)/usr/share/rpcd/acl.d/luci-app-substore.json

	# 简体中文翻译**不打进本包**：luci.mk 会按 po/<lang>/ 目录自动生成独立的
	# 翻译包 luci-i18n-substore-zh-cn（见文件末尾的说明）。
	# 这里再 po2lmo 一份会把译文硬编译进 ipk/apk，与那个包安装同一个路径
	# /usr/lib/lua/luci/i18n/substore.zh-cn.lmo，装两个包时互相覆盖。
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

# 翻译包 luci-i18n-substore-zh-cn 由 luci.mk 自动生成，本文件不手写它的定义。
# 机制（feeds/luci/luci.mk）：
#   LUCI_LANGUAGES := po/ 下的目录名（去掉 templates）
#   逐个 lang：定义了 LUCI_LANG.<lang> 才生成，语言码取
#   $(firstword $(LUCI_LC_ALIAS.<lang>) <lang>)，包名 luci-i18n-<LUCI_BASENAME>-<语言码>
#   （LUCI_BASENAME = luci-app-substore 去掉 luci-app- 前缀 = substore）。
# 于是有两条硬约束：
#   1) 目录名必须叫 zh_Hans —— 那是 LUCI_LANG 的键。叫 zh-cn 时
#      LUCI_LANG.zh-cn 不存在，luci.mk 直接跳过，**不报错也不生成包**，
#      译文会悄无声息地消失。
#   2) 包名与 .lmo 文件名取的是别名 zh-cn（LUCI_LC_ALIAS.zh_Hans=zh-cn），
#      即 luci-i18n-substore-zh-cn / substore.zh-cn.lmo，正好等于运行时
#      luci.i18n 查找所用的语言代码，也等于改造前硬编译进主包的那份文件名。
$(eval $(call BuildPackage,luci-app-substore))