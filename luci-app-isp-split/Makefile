include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-isp-split
PKG_VERSION:=0.3.0
PKG_RELEASE:=4
PKG_LICENSE:=MIT
PKG_LICENSE_FILES:=LICENSE

include $(INCLUDE_DIR)/package.mk

# 与主包同一个构建期开关：默认 1（完整版，含体检页 / 菜单节点）；
# 0 = 剥离版，体检页与菜单节点不进包。
FEATURE_LINECHECK?=1

define Package/luci-app-isp-split
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  TITLE:=LuCI support for ISP-aware policy routing
  DEPENDS:=+isp-split +luci-base
  PKGARCH:=all
endef

define Package/luci-app-isp-split/description
  LuCI page for isp-split: shows per-ISP element counts and hit
  counters, and offers one-click sync, data refresh, and config
  editing (wire/apply/dns).
endef

define Build/Prepare
	rm -rf $(PKG_BUILD_DIR)
	mkdir -p $(PKG_BUILD_DIR)
	$(CP) ./htdocs $(PKG_BUILD_DIR)/htdocs
	$(CP) ./root $(PKG_BUILD_DIR)/root
	# 与主包同一份剥离实现（本目录自带 strip-linecheck.sh，与
	# scripts/strip-linecheck.sh 逐字节一致）。曾经在这里手抄三行 sed，
	# 只删 config.js，漏掉 isp-split.css 的 .lc-* 样式体 —— F7。
	if [ "$(FEATURE_LINECHECK)" != "1" ]; then \
		sh $(CURDIR)/strip-linecheck.sh $(PKG_BUILD_DIR); \
	fi
endef

define Build/Compile
endef

define Package/luci-app-isp-split/install
	$(INSTALL_DIR) $(1)/www/luci-static/resources/view/isp-split
	$(INSTALL_DIR) $(1)/www/luci-static/resources/isp-split
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/htdocs/luci-static/resources/isp-split/isp-split.css \
		$(1)/www/luci-static/resources/isp-split/isp-split.css
	$(INSTALL_DIR) $(1)/www/luci-static/resources/isp-split/logos
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/htdocs/luci-static/resources/isp-split/logos/*.svg \
		$(1)/www/luci-static/resources/isp-split/logos/
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/htdocs/luci-static/resources/view/isp-split/overview.js \
		$(1)/www/luci-static/resources/view/isp-split/overview.js
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/htdocs/luci-static/resources/view/isp-split/config.js \
		$(1)/www/luci-static/resources/view/isp-split/config.js
	if [ -f $(PKG_BUILD_DIR)/htdocs/luci-static/resources/view/isp-split/linecheck.js ]; then \
		$(INSTALL_DATA) $(PKG_BUILD_DIR)/htdocs/luci-static/resources/view/isp-split/linecheck.js \
			$(1)/www/luci-static/resources/view/isp-split/linecheck.js; \
	fi
	$(INSTALL_DIR) $(1)/usr/share/luci/menu.d
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/root/usr/share/luci/menu.d/luci-app-isp-split.json \
		$(1)/usr/share/luci/menu.d/luci-app-isp-split.json
	if [ -f $(PKG_BUILD_DIR)/root/usr/share/luci/menu.d/luci-app-isp-split-linecheck.json ]; then \
		$(INSTALL_DATA) $(PKG_BUILD_DIR)/root/usr/share/luci/menu.d/luci-app-isp-split-linecheck.json \
			$(1)/usr/share/luci/menu.d/luci-app-isp-split-linecheck.json; \
	fi
	$(INSTALL_DIR) $(1)/usr/share/rpcd/acl.d
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/root/usr/share/rpcd/acl.d/luci-app-isp-split.json \
		$(1)/usr/share/rpcd/acl.d/luci-app-isp-split.json
endef

define Package/luci-app-isp-split/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] && exit 0
rm -rf /tmp/luci-indexcache* /tmp/luci-modulecache* 2>/dev/null
/etc/init.d/rpcd restart >/dev/null 2>&1
exit 0
endef

$(eval $(call BuildPackage,luci-app-isp-split))
