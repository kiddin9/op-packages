#
# meow —— OpenWrt 包定义
#
# 本文件由 patches/0001-*.patch 提供；meow/ 下其余文件全部来自上游快照
# upstream/openwrt/meow/，由 scripts/apply-patches.sh 生成，请勿手工维护。
#
# 安装清单与安装/卸载动作逐条对齐上游 openwrt/build-ipk.sh 生成的 opkg control：
#   /usr/bin/meow、/etc/init.d/meow、/etc/init.d/meow-arp、/etc/config/meow、
#   /etc/meow/config.yaml、/usr/share/meow/{gateway.sh,arp-hijack.sh}、
#   /etc/uci-defaults/80_meow、conffiles、postinst、prerm
#
include $(TOPDIR)/rules.mk

# version.env 位于 feed 根目录；feed 会被 stage 成 feeds/<name>/，
# 所以本包目录的上一级就是它。
-include $(CURDIR)/../version.env

MEOW_UPSTREAM_REPO?=meow-rs/meow-rs

ifeq ($(strip $(MEOW_TAG)),)
  $(error version.env 缺失或 MEOW_TAG 为空；请先执行 scripts/update-meow-version.sh)
endif
ifeq ($(strip $(MEOW_TARBALL_SHA256)),)
  $(error version.env 中 MEOW_TARBALL_SHA256 为空；请重新执行 scripts/update-meow-version.sh)
endif

PKG_NAME:=meow
PKG_VERSION:=$(MEOW_VERSION)
PKG_RELEASE:=3

# 直接用上游 release 的 aarch64 静态 musl 二进制，不在 buildroot 内交叉编译 Rust
PKG_SOURCE:=$(MEOW_TARBALL_FILE)
PKG_SOURCE_URL:=https://github.com/$(MEOW_UPSTREAM_REPO)/releases/download/$(MEOW_TAG)
PKG_HASH:=skip

PKG_LICENSE:=MIT
PKG_MAINTAINER:=zow2023 <https://github.com/zow2023/luci-app-meow>

include $(INCLUDE_DIR)/package.mk

define Package/meow
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=Web Servers/Proxies
  TITLE:=meow - a mihomo (Clash Meta) compatible proxy kernel in Rust
  URL:=https://github.com/$(MEOW_UPSTREAM_REPO)
  DEPENDS:=+libc
endef

define Package/meow/description
 meow 是 mihomo (Clash Meta) 的 Rust 实现：规则分流、透明代理 (TPROXY/REDIRECT)、
 DNS snooping 与 DNS 劫持、REST API、内置 Web 面板。
 本包使用上游 release 提供的 aarch64 静态 musl 二进制，不在 buildroot 内重新编译。
 上游 ipk 的 control 声明为 Depends: libc
 透明代理 / 网关模式需自行选中内核模块：kmod-nft-tproxy kmod-nft-socket
endef

预编译二进制：解包后定位 meow 并安装到 $(PKG_BUILD_DIR)/meow

注意 1：配方里的 shell 变量与命令替换必须写成 $$ 形式（$$BIN、$$(find ...)）。
  写成单个 $ 时 make 会先做变量展开：$B 展开为空、$(find ...) 展开为空，
  命令退化成 BIN=; ... install -m 0755 "IN" ...，报错 install: cannot stat 'IN'。

注意 2：OpenWrt 的解包命令为 tar -C $(PKG_BUILD_DIR)/.. -xf -，不带
  --strip-components，tarball 顶层目录会落在 $(PKG_BUILD_DIR) 的同级位置。
  上游 release 顶层目录是 meow-v<ver>-aarch64-unknown-linux-musl；自建扁平
  结构 tarball 的 meow 会直接落在 $(PKG_BUILD_DIR)/.. 下。故搜索范围必须
  同时覆盖 $(PKG_BUILD_DIR) 与其父目录，否则会误报未找到 meow 二进制。
define Build/Prepare
	$(call Build/Prepare/Default)
	if [ ! -f $(PKG_BUILD_DIR)/meow ]; then \
		BIN=$$(find $(PKG_BUILD_DIR) $(PKG_BUILD_DIR)/.. -maxdepth 3 -type f -name meow 2>/dev/null | head -n1); \
		[ -n "$$BIN" ] || { echo "ERROR: $(PKG_SOURCE) 内未找到 meow 二进制"; exit 1; }; \
		echo "meow binary: $$BIN"; \
		install -m 0755 "$$BIN" $(PKG_BUILD_DIR)/meow; \
	fi
endef

define Build/Compile
endef

define Package/meow/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/meow $(1)/usr/bin/meow

	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/meow.init $(1)/etc/init.d/meow
	$(INSTALL_BIN) ./files/meow-arp.init $(1)/etc/init.d/meow-arp

	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./files/meow.config $(1)/etc/config/meow

	$(INSTALL_DIR) $(1)/etc/meow
	$(INSTALL_CONF) ./files/config.yaml $(1)/etc/meow/config.yaml

	$(INSTALL_DIR) $(1)/usr/share/meow
	$(INSTALL_BIN) ./files/gateway.sh $(1)/usr/share/meow/gateway.sh
	$(INSTALL_BIN) ./files/arp-hijack.sh $(1)/usr/share/meow/arp-hijack.sh

	$(INSTALL_DIR) $(1)/etc/uci-defaults
	$(INSTALL_BIN) ./files/meow.uci-defaults $(1)/etc/uci-defaults/80_meow
endef

define Package/meow/conffiles
/etc/config/meow
/etc/meow/config.yaml
endef

define Package/meow/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] && exit 0
[ -f /etc/uci-defaults/80_meow ] && { sh /etc/uci-defaults/80_meow; rm -f /etc/uci-defaults/80_meow; }
/etc/init.d/meow enable || true
# meow-arp 自身按 (默认关闭的) arp_hijack 段自锁，启用它不会真的引流
/etc/init.d/meow-arp enable || true
exit 0
endef

define Package/meow/prerm
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] && exit 0
/etc/init.d/meow-arp stop 2>/dev/null || true
/etc/init.d/meow-arp disable 2>/dev/null || true
/etc/init.d/meow stop 2>/dev/null || true
/etc/init.d/meow disable 2>/dev/null || true
exit 0
endef

$(eval $(call BuildPackage,meow))
