include $(TOPDIR)/rules.mk

LUCI_TITLE:=LuCI support for 51DDNS remote access
LUCI_URL:=https://github.com/21hkcloud/51ddns-openwrt
LUCI_DESCRIPTION:=Configure and monitor the 51DDNS remote access agent.
LUCI_DEPENDS:=+luci-base +51ddns-agent
LUCI_EXTRA_DEPENDS:=51ddns-agent (>=0.6.5-r3)
LUCI_PKGARCH:=all

PKG_VERSION:=0.1.5
PKG_RELEASE:=2
PKG_LICENSE:=Apache-2.0
PKG_MAINTAINER:=Jinshuan Wang <21hkcloud@gmail.com>

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
