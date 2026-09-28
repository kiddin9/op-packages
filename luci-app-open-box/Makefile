include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-open-box
PKG_VERSION:=0.1.263
PKG_RELEASE:=2

PKG_MAINTAINER:=liandu2024
PKG_LICENSE:=GPL-3.0-or-later

# 1. 自动判断目标编译架构，映射至 Open-Box Release 预编译资产名
ifeq ($(ARCH),x86_64)
  OPENBOX_ARCH:=x64
endif
ifeq ($(ARCH),aarch64)
  OPENBOX_ARCH:=arm64
endif

PKG_SOURCE:=open-box-linux-$(OPENBOX_ARCH).tar.gz
PKG_SOURCE_URL:=https://github.com/liandu2024/Open-Box/releases/download/v$(PKG_VERSION)/
PKG_HASH:=skip

include $(INCLUDE_DIR)/package.mk

define Package/luci-app-open-box
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  TITLE:=LuCI support for Open-Box Transparent Proxy (Full Core Included)
  # 架构约束：仅在目标平台为 x86_64 或 aarch64 时在 menuconfig 中展示，防止误选到不支持的 MIPS/ARMv7 平台
  DEPENDS:=@(x86_64||aarch64) +kmod-tun +kmod-nft-queue +kmod-nft-nat +kmod-veth +ip-full +ca-bundle +luci-base
endef

define Package/luci-app-open-box/description
  Open-Box all-in-one transparent proxy management suite for OpenWrt.
  Pre-packaged with full sing-box core, embedded Node.js runtime, GeoSite/GeoIP databases and web dashboard.
endef

define Package/luci-app-open-box/conffiles
/etc/config/openbox
/opt/open-box/data/
endef

# 2. 构建准备：解压下载的对应架构核心资产包至构建目录
define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)/_core
	tar -xzf $(DL_DIR)/$(PKG_SOURCE) -C $(PKG_BUILD_DIR)/_core
endef

define Build/Configure
endef

define Build/Compile
endef

# 3. 安装与打包：同时铺装 LuCI 页面、系统脚本以及 /opt/open-box 核心
define Package/luci-app-open-box/install
	# 安装 LuCI 菜单与权限声明
	$(INSTALL_DIR) $(1)/usr/share/luci/menu.d
	$(INSTALL_DATA) ./root/usr/share/luci/menu.d/luci-app-openbox.json $(1)/usr/share/luci/menu.d/

	$(INSTALL_DIR) $(1)/usr/share/rpcd/acl.d
	$(INSTALL_DATA) ./root/usr/share/rpcd/acl.d/luci-app-openbox.json $(1)/usr/share/rpcd/acl.d/

	$(INSTALL_DIR) $(1)/www/luci-static/resources/view/openbox
	$(INSTALL_DATA) ./root/www/luci-static/resources/view/openbox/main.js $(1)/www/luci-static/resources/view/openbox/

	# 安装系统服务与默认配置
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./root/etc/init.d/openbox $(1)/etc/init.d/openbox
	$(INSTALL_BIN) ./root/etc/init.d/openbox-panel $(1)/etc/init.d/openbox-panel

	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./root/etc/config/openbox $(1)/etc/config/openbox

	$(INSTALL_DIR) $(1)/etc/uci-defaults
	$(INSTALL_BIN) ./root/etc/uci-defaults/99-luci-app-openbox $(1)/etc/uci-defaults/99-luci-app-openbox

	# 创建 CLI 管理命令软链接（直接指向 /opt/open-box/openwrt/bin/open-box 原版脚本）
	$(INSTALL_DIR) $(1)/usr/bin
	ln -sf /opt/open-box/openwrt/bin/open-box $(1)/usr/bin/open-box

	# 仅复制 _core 子目录内容，避免递归包含
	$(INSTALL_DIR) $(1)/opt/open-box $(1)/opt/open-box/data
	$(CP) $(PKG_BUILD_DIR)/_core/* $(1)/opt/open-box/
	chmod -R 0755 $(1)/opt/open-box/bin $(1)/opt/open-box/node/bin $(1)/opt/open-box/openwrt/bin 2>/dev/null || true
	chmod +x $(1)/opt/open-box/update.sh $(1)/opt/open-box/uninstall.sh 2>/dev/null || true
	echo "3036" > $(1)/opt/open-box/data/panel-port
endef

define Package/luci-app-open-box/extra_provides
    echo "libc.musl-x86_64.so.1";
endef

define Package/luci-app-open-box/prerm
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || {
	/etc/init.d/openbox stop >/dev/null 2>&1 || true
	/etc/init.d/openbox-panel stop >/dev/null 2>&1 || true
}
exit 0
endef

define Package/luci-app-open-box/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || {
	rm -rf /tmp/luci-*cache* 2>/dev/null || true
	/etc/init.d/rpcd restart >/dev/null 2>&1 || true
	/etc/init.d/openbox-panel restart >/dev/null 2>&1 || true
}
exit 0
endef

# 6. 包卸载后钩子：清理残留静态资源与防火墙规则
define Package/luci-app-open-box/postrm
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || {
	rm -rf /tmp/luci-*cache* 2>/dev/null || true
	rm -rf /www/luci-static/resources/view/openbox 2>/dev/null || true
	uci -q delete firewall.openbox_panel || true
	uci -q delete firewall.openbox_dns || true
	uci -q delete firewall.openbox_tun_forward || true
	uci -q delete firewall.openbox_tun_input || true
	uci -q delete firewall.openbox_v6block || true
	for _ob_rule in $$(uci -q show firewall 2>/dev/null | sed -n 's/^firewall\.\(openbox_srv_[A-Za-z0-9_]*\)=rule$$/\1/p'); do
		uci -q delete "firewall.$$_ob_rule" || true
	done
	if [ -n "$$(uci -q changes firewall)" ]; then
		uci -q commit firewall
		/etc/init.d/firewall reload >/dev/null 2>&1 || true
	fi
}
exit 0
endef

$(eval $(call BuildPackage,luci-app-open-box))
