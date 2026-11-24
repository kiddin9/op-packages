include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-open-box
PKG_VERSION:=0.1.482
PKG_RELEASE:=101

PKG_MAINTAINER:=liandu2024
PKG_LICENSE:=Proprietary GPL-3.0-or-later MIT

# 1. 自动映射目标架构至上游 Release 资产架构名
ifeq ($(ARCH),x86_64)
  OPENBOX_ARCH:=x64
else ifeq ($(ARCH),aarch64)
  OPENBOX_ARCH:=arm64
endif

OPENBOX_RELEASE_URL:=https://github.com/liandu2024/Open-Box/releases/download/v$(PKG_VERSION)/

OPENBOX_PANEL_PORT:=$(call qstrip,$(CONFIG_OPENBOX_PANEL_PORT))
ifeq ($(OPENBOX_PANEL_PORT),)
  OPENBOX_PANEL_PORT:=3036
endif
ifneq ($(filter $(OPENBOX_PANEL_PORT),22 53 80 443 7853 7854 7891 9095),)
  $(error OPENBOX_PANEL_PORT ($(OPENBOX_PANEL_PORT)) conflicts with reserved Open-Box or system ports)
endif

# 2. 按需模块化下载：默认使用带版本号的完整资产包（避免 dl/ 缓存污染）；自定义裁剪时按组件从上游拉取
OPENBOX_USE_MODULAR:=
ifeq ($(CONFIG_OPENBOX_CUSTOM_COMPONENTS),y)
  ifneq ($(CONFIG_OPENBOX_BUNDLE_SINGBOX)$(CONFIG_OPENBOX_BUNDLE_MIHOMO)$(CONFIG_OPENBOX_BUNDLE_GEODATA),yyy)
    OPENBOX_USE_MODULAR:=1
  endif
endif

ifdef OPENBOX_USE_MODULAR
  PKG_SOURCE:=open-box-v$(PKG_VERSION)-linux-$(OPENBOX_ARCH)-app.tar.gz
else
  PKG_SOURCE:=open-box-v$(PKG_VERSION)-linux-$(OPENBOX_ARCH).tar.gz
endif
PKG_SOURCE_URL:=$(OPENBOX_RELEASE_URL)
PKG_HASH:=skip

PKG_CONFIG_DEPENDS:= \
	CONFIG_OPENBOX_CUSTOM_COMPONENTS \
	CONFIG_OPENBOX_BUNDLE_SINGBOX \
	CONFIG_OPENBOX_BUNDLE_MIHOMO \
	CONFIG_OPENBOX_BUNDLE_GEODATA \
	CONFIG_OPENBOX_PANEL_PORT

OPENBOX_EXTRA_FILES:=

ifneq ($(OPENBOX_ARCH),)
ifdef OPENBOX_USE_MODULAR
  ifeq ($(CONFIG_OPENBOX_BUNDLE_SINGBOX),y)
    OPENBOX_SINGBOX_FILE:=open-box-v$(PKG_VERSION)-linux-$(OPENBOX_ARCH)-kernel.tar.gz
    OPENBOX_EXTRA_FILES+=$(OPENBOX_SINGBOX_FILE)
    define Download/openbox-singbox
      FILE:=$(OPENBOX_SINGBOX_FILE)
      URL:=$(OPENBOX_RELEASE_URL)
      HASH:=skip
    endef
  endif

  ifeq ($(CONFIG_OPENBOX_BUNDLE_MIHOMO),y)
    OPENBOX_MIHOMO_FILE:=open-box-v$(PKG_VERSION)-linux-$(OPENBOX_ARCH)-kernel-mihomo.tar.gz
    OPENBOX_EXTRA_FILES+=$(OPENBOX_MIHOMO_FILE)
    define Download/openbox-mihomo
      FILE:=$(OPENBOX_MIHOMO_FILE)
      URL:=$(OPENBOX_RELEASE_URL)
      HASH:=skip
    endef
  endif

  ifeq ($(CONFIG_OPENBOX_BUNDLE_GEODATA),y)
    OPENBOX_GEODATA_FILE:=open-box-v$(PKG_VERSION)-linux-$(OPENBOX_ARCH)-geo.tar.gz
    OPENBOX_EXTRA_FILES+=$(OPENBOX_GEODATA_FILE)
    define Download/openbox-geodata
      FILE:=$(OPENBOX_GEODATA_FILE)
      URL:=$(OPENBOX_RELEASE_URL)
      HASH:=skip
    endef
  endif
endif
endif

include $(INCLUDE_DIR)/package.mk

# 上游面板与双内核均为已裁剪的纯静态 Go 二进制，跳过交叉 strip 提升打包速度并避免破坏内嵌资源
STRIP:=:
RSTRIP:=:

define Package/luci-app-open-box
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  TITLE:=LuCI support for Open-Box Transparent Proxy
  URL:=https://github.com/liandu2024/Open-Box
  PROVIDES:=open-box luci-app-openbox
  DEPENDS:=@(x86_64||aarch64) +kmod-tun +kmod-nft-queue +kmod-nft-nat +kmod-veth +ip-full +ca-bundle +curl +luci-base
endef

define Package/luci-app-open-box/description
  Open-Box all-in-one transparent proxy management suite for OpenWrt.
  Fetches upstream LuCI views, procd init scripts, pure-Go static web panel,
  sing-box/Mihomo cores, and GeoSite/GeoIP databases directly during build.
endef

define Package/luci-app-open-box/config
  source "$(SOURCE)/Config.in"
endef

# 3. 构建准备：解压上游包并剔除非 OpenWrt / 旧版 Node 遗留兼容文件，避免跨架构 ELF 依赖误报
define Build/Prepare
	rm -rf $(PKG_BUILD_DIR)/_core
	mkdir -p $(PKG_BUILD_DIR)/_core
	tar --no-same-owner -xzf $(DL_DIR)/$(PKG_SOURCE) -C $(PKG_BUILD_DIR)/_core
	$(foreach f,$(OPENBOX_EXTRA_FILES), \
		tar --no-same-owner -xzf $(DL_DIR)/$(f) -C $(PKG_BUILD_DIR)/_core; \
	)
	rm -rf $(PKG_BUILD_DIR)/_core/debian \
		$(PKG_BUILD_DIR)/_core/node \
		$(PKG_BUILD_DIR)/_core/openwrt/bin/compat
endef

define Build/Configure
endef

define Build/Compile
endef

# 4. 安装与打包：从上游解压目录动态铺装 /opt/open-box、LuCI 资源、procd 服务与初始化脚本
define Package/luci-app-open-box/install
	$(INSTALL_DIR) $(1)/opt/open-box $(1)/opt/open-box/data $(1)/opt/open-box/etc

	# 铺装核心与面板资产，规范目录与可执行文件权限
	$(CP) $(PKG_BUILD_DIR)/_core/. $(1)/opt/open-box/
	chmod -R u+rwX,go+rX,go-w $(1)/opt/open-box
	for b in openbox-panel sing-box mihomo; do \
		[ -f "$(1)/opt/open-box/bin/$$b" ] && chmod 0755 "$(1)/opt/open-box/bin/$$b" || true; \
	done
	chmod 0755 $(1)/opt/open-box/openwrt/bin/* $(1)/opt/open-box/openwrt/initd/* 2>/dev/null || true
	for s in update.sh uninstall.sh; do \
		[ -f "$(1)/opt/open-box/$$s" ] && chmod 0755 "$(1)/opt/open-box/$$s" || true; \
	done

	# 从上游包提取 LuCI 菜单、rpcd ACL 与前端视图（强制 0755/0644 防止 uhttpd/rpcd 403）
	if [ -d "$(PKG_BUILD_DIR)/_core/openwrt/luci/root" ]; then \
		$(CP) $(PKG_BUILD_DIR)/_core/openwrt/luci/root/. $(1)/; \
	fi
	if [ -d "$(PKG_BUILD_DIR)/_core/openwrt/luci/htdocs" ]; then \
		$(INSTALL_DIR) $(1)/www; \
		$(CP) $(PKG_BUILD_DIR)/_core/openwrt/luci/htdocs/. $(1)/www/; \
	fi
	find $(1)/usr/share/luci $(1)/usr/share/rpcd $(1)/www -type d -exec chmod 0755 {} + 2>/dev/null || true
	find $(1)/usr/share/luci $(1)/usr/share/rpcd $(1)/www -type f -exec chmod 0644 {} + 2>/dev/null || true

	# 安装系统服务与 CLI 软链接
	$(INSTALL_DIR) $(1)/etc/init.d $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/_core/openwrt/initd/openbox $(1)/etc/init.d/openbox
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/_core/openwrt/initd/openbox-panel $(1)/etc/init.d/openbox-panel
	ln -sf /opt/open-box/openwrt/bin/open-box $(1)/usr/bin/open-box

	# 安装 sysupgrade 升级保留配置（兼容 opkg 与 apk）及 uci-defaults 初始化脚本
	$(INSTALL_DIR) $(1)/lib/upgrade/keep.d $(1)/etc/uci-defaults
	printf '%s\n' '/opt/open-box/data/' '/opt/open-box/etc/' > $(1)/lib/upgrade/keep.d/luci-app-open-box
	chmod 0644 $(1)/lib/upgrade/keep.d/luci-app-open-box
	printf '%s\n' \
		'#!/bin/sh' \
		'umask 022' \
		'INSTALL_ROOT="/opt/open-box"' \
		'mkdir -p "$$INSTALL_ROOT/data" "$$INSTALL_ROOT/etc"' \
		'[ -s "$$INSTALL_ROOT/data/panel-port" ] || printf "%s\n" "$(OPENBOX_PANEL_PORT)" > "$$INSTALL_ROOT/data/panel-port"' \
		'[ -s "$$INSTALL_ROOT/data/channel" ] || printf "direct\n" > "$$INSTALL_ROOT/data/channel"' \
		'if [ -f "$$INSTALL_ROOT/openwrt/bin/luci-compat.sh" ]; then' \
		'	( . "$$INSTALL_ROOT/openwrt/bin/luci-compat.sh" && openbox_install_luci_compat "$$INSTALL_ROOT" ) >/dev/null 2>&1 || true' \
		'fi' \
		'rm -rf /tmp/luci-*cache* 2>/dev/null || true' \
		'if [ -x /etc/init.d/rpcd ]; then' \
		'	/etc/init.d/rpcd reload >/dev/null 2>&1 || /etc/init.d/rpcd restart >/dev/null 2>&1 || true' \
		'fi' \
		'if [ -x /etc/init.d/openbox-panel ]; then' \
		'	/etc/init.d/openbox-panel enable >/dev/null 2>&1 || true' \
		'	/etc/init.d/openbox-panel restart >/dev/null 2>&1 || /etc/init.d/openbox-panel start >/dev/null 2>&1 || true' \
		'fi' \
		'if [ -x /etc/init.d/openbox ]; then' \
		'	if [ -f /tmp/.openbox_was_enabled ] || /etc/init.d/openbox enabled >/dev/null 2>&1; then' \
		'		rm -f /tmp/.openbox_was_enabled 2>/dev/null || true' \
		'		/etc/init.d/openbox enable >/dev/null 2>&1 || true' \
		'		/etc/init.d/openbox restart >/dev/null 2>&1 || true' \
		'	fi' \
		'fi' \
		'exit 0' \
		> $(1)/etc/uci-defaults/99-luci-app-open-box
	chmod 0755 $(1)/etc/uci-defaults/99-luci-app-open-box
endef

# 5. 卸载前钩子：区分升级与卸载，停止服务并还原 dnsmasq 接管
define Package/luci-app-open-box/prerm
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || {
	if [ "$${PKG_UPGRADE:-0}" = "1" ] || [ "$${1:-}" = "upgrade" ]; then
		if [ -x /etc/init.d/openbox ] && /etc/init.d/openbox enabled >/dev/null 2>&1; then
			touch /tmp/.openbox_was_enabled 2>/dev/null || true
		fi
		/etc/init.d/openbox-panel stop >/dev/null 2>&1 || true
		/etc/init.d/openbox stop >/dev/null 2>&1 || true
	else
		if [ -x /etc/init.d/openbox-panel ]; then
			/etc/init.d/openbox-panel stop >/dev/null 2>&1 || true
			/etc/init.d/openbox-panel disable >/dev/null 2>&1 || true
		fi
		if [ -x /etc/init.d/openbox ]; then
			/etc/init.d/openbox stop >/dev/null 2>&1 || true
			/etc/init.d/openbox disable >/dev/null 2>&1 || true
		fi
	fi
}
exit 0
endef

# 6. 安装后钩子：在线安装时立即执行初始化脚本（固件预编译时留待首次开机自动执行）
define Package/luci-app-open-box/postinst
#!/bin/sh
if [ -z "$${IPKG_INSTROOT}" ]; then
	if [ -x /etc/uci-defaults/99-luci-app-open-box ]; then
		/etc/uci-defaults/99-luci-app-open-box && rm -f /etc/uci-defaults/99-luci-app-open-box
	fi
fi
exit 0
endef

# 7. 卸载后钩子：仅在彻底卸载时清理 nftables 表、防火墙规则与在线升级残留，保留 /opt/open-box/data
define Package/luci-app-open-box/postrm
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || {
	rm -rf /tmp/luci-*cache* 2>/dev/null || true
	if [ ! -f /etc/init.d/openbox-panel ]; then
		rm -f /usr/lib/lua/luci/controller/openbox_compat.lua \
			/www/luci-static/resources/view/openbox/status.js 2>/dev/null || true
		rmdir /www/luci-static/resources/view/openbox 2>/dev/null || true
		if command -v nft >/dev/null 2>&1; then
			nft delete table inet openbox >/dev/null 2>&1 || true
			nft delete table inet openbox_dns_transition >/dev/null 2>&1 || true
		fi
		if command -v uci >/dev/null 2>&1; then
			uci -q delete firewall.openbox_panel || true
			uci -q delete firewall.openbox_dns || true
			uci -q delete firewall.openbox_tun_forward || true
			uci -q delete firewall.openbox_tun_docker_forward || true
			uci -q delete firewall.openbox_tun_input || true
			uci -q delete firewall.openbox_v6block || true
			for _ob_rule in $$(uci -q show firewall 2>/dev/null | sed -n 's/^firewall\.\(openbox_srv_[A-Za-z0-9_]*\)=rule$$/\1/p'); do
				uci -q delete "firewall.$$_ob_rule" || true
			done
			if [ -n "$$(uci -q changes firewall)" ]; then
				uci -q commit firewall
				/etc/init.d/firewall reload >/dev/null 2>&1 || true
			fi
		fi
		rm -rf /opt/open-box/etc \
			/opt/open-box/node \
			/opt/open-box/panel \
			/opt/open-box/bin \
			/opt/open-box/openwrt \
			/opt/open-box/debian \
			/opt/open-box/.old \
			/opt/open-box/.update-stage.* \
			/opt/open-box/.open-box-install.* \
			/opt/open-box/.open-box-update.* \
			/opt/open-box/meta.json \
			/opt/open-box/update.sh \
			/opt/open-box/uninstall.sh 2>/dev/null || true
	fi
}
exit 0
endef

ifneq ($(OPENBOX_ARCH),)
ifdef OPENBOX_USE_MODULAR
  ifeq ($(CONFIG_OPENBOX_BUNDLE_SINGBOX),y)
    $(eval $(call Download,openbox-singbox))
  endif
  ifeq ($(CONFIG_OPENBOX_BUNDLE_MIHOMO),y)
    $(eval $(call Download,openbox-mihomo))
  endif
  ifeq ($(CONFIG_OPENBOX_BUNDLE_GEODATA),y)
    $(eval $(call Download,openbox-geodata))
  endif
  $(STAMP_PREPARED): $(addprefix $(DL_DIR)/,$(OPENBOX_EXTRA_FILES))
endif
endif

$(eval $(call BuildPackage,luci-app-open-box))
