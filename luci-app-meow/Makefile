#
# luci-app-meow —— OpenWrt 包定义
#
# 本文件由 patches/0002-*.patch 提供；htdocs/ 与 root/ 全部来自上游快照
# upstream/openwrt/luci-app-meow/，由 scripts/apply-patches.sh 生成，请勿手工维护。
#
# 关键点：从 feed 引入 luci.mk 必须写 $(TOPDIR)/feeds/luci/luci.mk
# （上游旧写法 ../../luci.mk 只在包位于 feeds/luci/applications/ 内时才成立）。
# luci.mk 负责把 root/ 覆盖到 /、把 htdocs/ 映射到 /www 并生成 LuCI 菜单项，
# 因此本仓库不需要任何自定义 install 规则。
#
include $(TOPDIR)/rules.mk

-include $(CURDIR)/../version.env

PKG_NAME:=luci-app-meow
PKG_VERSION:=$(if $(MEOW_VERSION),$(MEOW_VERSION),0.0.0)
PKG_RELEASE:=3
PKG_LICENSE:=MIT
PKG_MAINTAINER:=zow2023 <https://github.com/zow2023/luci-app-meow>

LUCI_TITLE:=LuCI app for meow
LUCI_DEPENDS:=+luci-base +meow +curl
LUCI_PKGARCH:=all

# 无源码下载：前端资源在上游仓库中已构建并提交（htdocs/）
PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)-$(PKG_VERSION)

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
endef

define Build/Compile
endef

include $(TOPDIR)/feeds/luci/luci.mk

$(eval $(call BuildPackage,luci-app-meow))
