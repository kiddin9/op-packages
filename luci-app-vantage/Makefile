#
# Vantage dashboard for LuCI: a live, read-only overview of the device,
# its uplink, radios, SSIDs and stations. The only write is the station
# alias, stored in /etc/config/vantage (own ACL group).
#
# This is free software, licensed under the GNU General Public License,
# version 3 or (at your option) any later version.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-vantage
PKG_VERSION:=1.0.1
PKG_RELEASE:=1
PKG_LICENSE:=GPL-3.0-or-later

LUCI_TITLE:=Vantage dashboard
LUCI_DESCRIPTION:=Live network dashboard (landing page under admin/dashboard): device, \
	uplink, radios, SSIDs and stations with health and experience scores. \
	Read-only except for station names, which are kept in /etc/config/vantage.
# rpcd-mod-iwinfo provides the station lists (iwinfo info/assoclist).
# rpcd-mod-ucode runs the app's plugin (/usr/share/rpcd/ucode/luci.vantage:
# key-free wireless status, validated alias writes), which imports the uci
# and ubus ucode modules; luci-base pulls all three in already, they are
# listed because the plugin needs them.
# Optional at runtime, degrade when absent: rpcd-mod-rrdns (reverse DNS
# names), umdns (mDNS names), hostapd ubus objects (WPS names, client
# capabilities).
LUCI_DEPENDS:=+luci-base +rpcd +rpcd-mod-iwinfo +rpcd-mod-ucode +ucode-mod-uci +ucode-mod-ubus
LUCI_PKGARCH:=all
LUCI_MAINTAINER:=anothaDev <10740588+anothaDev@users.noreply.github.com>
LUCI_URL:=https://github.com/anothaDev/luci-theme-vantage

# app.css uses custom properties, color-mix() and container queries,
# which csstidy (a CSS2-era minifier) mangles; ship it byte for byte.
LUCI_MINIFY_CSS:=0

# Language packages (po/<lang>/vantage.po) are luci-i18n-vantage-<lang>
# (luci.mk's default name) and carry the package version instead of one
# derived from git history.
PKG_PO_VERSION:=$(PKG_VERSION)-r$(PKG_RELEASE)

define Package/luci-app-vantage/conffiles
/etc/config/vantage
endef

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
