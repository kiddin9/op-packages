include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-gately
PKG_VERSION:=0.6.6
PKG_RELEASE:=4

PKG_MAINTAINER:=wangwanjie <https://github.com/wangwanjie/gately>
PKG_LICENSE:=Apache-2.0

PKG_SOURCE:=gately-$(PKG_VERSION).tar.gz
PKG_SOURCE_URL:=https://codeload.github.com/wangwanjie/gately/tar.gz/refs/tags/v$(PKG_VERSION)?
PKG_HASH:=skip

include $(INCLUDE_DIR)/package.mk

define Package/luci-app-gately
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  TITLE:=LuCI support for Gately
  URL:=https://github.com/wangwanjie/gately
  DEPENDS:=+luci-base +gately
  PKGARCH:=all
endef

define Package/luci-app-gately/description
  LuCI support for Gately: service status, start / stop, start on boot,
  admin port and a shortcut to the Gately admin interface.
endef

define Package/luci-app-gately/conffiles
/etc/config/gately
/etc/gately
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)/_core
	tar -xzf $(DL_DIR)/$(PKG_SOURCE) -C $(PKG_BUILD_DIR) --strip-components=1 \
			gately-$(PKG_VERSION)/deploy/openwrt/luci \
			gately-$(PKG_VERSION)/deploy/openwrt/gately.init
endef

define Build/Configure
endef

define Build/Compile
endef

# 2. 安装与打包：铺装 LuCI 页面、rpcd 脚本以及 procd 启动脚本
define Package/luci-app-gately/install
	$(CP) $(PKG_BUILD_DIR)/deploy/openwrt/luci/root/* $(1)/
	chmod 0755 $(1)/usr/libexec/rpcd/luci.gately

	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/deploy/openwrt/gately.init $(1)/etc/init.d/gately

	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/i18n
	$(STAGING_DIR_HOSTPKG)/bin/po2lmo $(PKG_BUILD_DIR)/deploy/openwrt/luci/po/zh-cn/gately.po $(1)/usr/lib/lua/luci/i18n/gately.zh-cn.lmo
endef

define Package/luci-app-gately/postinst
#!/bin/sh
if [ ! -f "$${IPKG_INSTROOT}/etc/config/gately" ]; then
	mkdir -p "$${IPKG_INSTROOT}/etc/config"
	printf "\nconfig gately 'main'\n" > "$${IPKG_INSTROOT}/etc/config/gately"
fi
[ -n "${IPKG_INSTROOT}" ] || { rm -f /tmp/luci-indexcache.*
	rm -rf /tmp/luci-modulecache/
	/etc/init.d/rpcd reload 2>/dev/null
}
exit 0
endef

$(eval $(call BuildPackage,luci-app-gately))
