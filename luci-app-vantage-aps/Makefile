#
# Vantage access points: an opt-in add-on to the Vantage dashboard
# (luci-app-vantage). Pairs devices over SSH so a router's dashboard shows
# its access points, their SSIDs, stations and wired hosts. Install it on
# the router and on every access point; pairing happens under Network ->
# Access points. Unlike the dashboard it writes outside its own config:
# its key and paired list in /etc/vantage, and, on an access point, a
# router's key in /etc/dropbear/authorized_keys, limited to a read-only
# report command (own ACL groups: luci-app-vantage-aps to pair,
# luci-app-vantage-aps-view to see the access points).
#
# This is free software, licensed under the GNU General Public License,
# version 3 or (at your option) any later version.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-vantage-aps
PKG_VERSION:=1.2.1
PKG_RELEASE:=1
PKG_LICENSE:=GPL-3.0-or-later

LUCI_TITLE:=Vantage access points (pairing over SSH)
LUCI_DESCRIPTION:=Shows the network's other access points on the Vantage \
	dashboard: each one is paired once, then the router reads its SSIDs, \
	stations and wired hosts over SSH, with a key that can only run the \
	access point's read-only report. Needs Dropbear (server on the access \
	points, dbclient on the router).
# The collector (/usr/libexec/vantage/collector) is a ucode daemon on uloop
# and ubus; the pairing plugin (luci.vantage-pair) reads dropbear's uci
# config and the shared checks in /usr/share/ucode/vantage/aps.uc. Dropbear
# is not a dependency: a device with another SSH server can still read
# access points if it has dbclient, and the page says what is missing.
LUCI_DEPENDS:=+luci-app-vantage +rpcd-mod-ucode +ucode-mod-fs +ucode-mod-ubus +ucode-mod-uci +ucode-mod-uloop
# the dashboard of this release or a newer one: an older one does not read
# what this add-on collects
LUCI_EXTRA_DEPENDS:=luci-app-vantage (>=$(PKG_VERSION))
LUCI_PKGARCH:=all
LUCI_MAINTAINER:=anothaDev <10740588+anothaDev@users.noreply.github.com>
LUCI_URL:=https://github.com/anothaDev/luci-theme-vantage

LUCI_MINIFY_CSS:=0

PKG_PO_VERSION:=$(PKG_VERSION)-r$(PKG_RELEASE)

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
