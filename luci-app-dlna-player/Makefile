#
# Copyright (C) 2026
#
# This is free software, licensed under the GNU General Public License v3.0
#

include $(TOPDIR)/rules.mk

LUCI_TITLE:=LuCI DLNA Music Player
LUCI_DESCRIPTION:=Turn an OpenWrt device into a music player: auto-detect the sound card, \
configure MPD and upmpdcli (DLNA casting), browse and play local music.
#
# 依赖说明：
#   mpd-full / mpc / upmpdcli / alsa-utils  → 播放与 DLNA 核心
#   中文翻译：lmo 已内置在主包 root/usr/lib/lua/luci/i18n/ 里，
#            勾上插件即带中文，无需额外选包
#            （翻译源文件在 i18n-src/，改名是为了避免 luci.mk 重复生成 i18n 包）
#   kmod-sound-*                            → 声卡驱动（覆盖常见板载 HDA + USB 声卡）
#
LUCI_DEPENDS:=+mpd-full +mpc +upmpdcli +alsa-utils \
	+kmod-sound-core +kmod-sound-seq \
	+kmod-sound-hda-core +kmod-sound-hda-intel \
	+kmod-sound-hda-codec-realtek +kmod-sound-hda-codec-conexant \
	+kmod-sound-hda-codec-analog +kmod-sound-hda-codec-hdmi \
	+kmod-sound-hda-codec-via +kmod-sound-hda-codec-idt \
	+kmod-sound-hda-codec-cirrus +kmod-sound-hda-codec-cmedia \
	+kmod-sound-hda-codec-ca0132 +kmod-sound-hda-codec-ca0110 \
	+kmod-usb-audio

PKG_NAME:=luci-app-dlna-player
PKG_VERSION:=1.0.0
PKG_RELEASE:=1
PKG_MAINTAINER:=sakura-builder1 <sakura-builder1@users.noreply.github.com>
PKG_LICENSE:=GPL-3.0

# 配置文件：安装/升级时保留用户修改
# 注意：必须在 include luci.mk 之前定义（luci.mk 内部会 eval 包定义）
define Package/luci-app-dlna-player/conffiles
/etc/config/dlna-player
endef

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
