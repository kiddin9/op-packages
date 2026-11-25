#
# Vantage traffic: an opt-in, experimental add-on to the Vantage dashboard
# (luci-app-vantage). The traffic of devices that share one of the
# router's ports (a switch or an access point behind it), which the
# dashboard cannot count per device otherwise, from the kernel's
# connection accounting: one executable rpcd plugin, which rpcd runs as a
# process of its own for each call, and its own ACL group
# (luci-app-vantage-traffic). No firewall rule, sysctl change, service or
# config file; its counters' state in /var/run/vantage-traffic (RAM).
#
# This is free software, licensed under the GNU General Public License,
# version 3 or (at your option) any later version.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-vantage-traffic
PKG_VERSION:=1.2.1
PKG_RELEASE:=1
PKG_LICENSE:=GPL-3.0-or-later

LUCI_TITLE:=Vantage per-device traffic (experimental)
LUCI_DESCRIPTION:=Shows on the Vantage dashboard the traffic of devices \
	that share a port of the router, counted from the router's connection \
	tracking: traffic through the router, not between devices of one \
	network. Changes nothing on the router. Experimental.
# The plugin (/usr/libexec/rpcd/luci.vantage.traffic, a ucode script)
# reads /proc/net/nf_conntrack and the
# accounting switch, both kmod-nf-conntrack's (accounting is on by
# default: net.netfilter.nf_conntrack_acct=1), the IPv4 and IPv6
# neighbour tables through rtnl, and the theme's Low-power router option
# through uci. kmod-nf-conntrack is not a dependency: on a device without
# it the answer says there is no table. luci-app-vantage pulls in ucode
# and its modules already; they are listed because the plugin needs them.
LUCI_DEPENDS:=+luci-app-vantage +rpcd +ucode +ucode-mod-fs +ucode-mod-rtnl +ucode-mod-uci
# the dashboard of this release or a newer one: an older one does not ask
LUCI_EXTRA_DEPENDS:=luci-app-vantage (>=$(PKG_VERSION))
LUCI_PKGARCH:=all
LUCI_MAINTAINER:=anothaDev <10740588+anothaDev@users.noreply.github.com>
LUCI_URL:=https://github.com/anothaDev/luci-theme-vantage

PKG_PO_VERSION:=$(PKG_VERSION)-r$(PKG_RELEASE)

# The counters' state is RAM (gone at a reboot) and goes with the package.
# rpcd keeps an executable plugin's object until it starts again: a hangup
# makes it, as luci.mk's postinst does on an install. No hangup on an
# upgrade. opkg runs the old package's postrm then ("postrm upgrade"), so
# the new plugin starts over; apk runs none, and the new plugin reads the
# old state, whose format carries a version.
define Package/luci-app-vantage-traffic/postrm
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || {
	rm -rf /var/run/vantage-traffic
	[ "$${1:-}" = upgrade ] || [ "$${PKG_UPGRADE:-}" = 1 ] || killall -HUP rpcd 2>/dev/null
}
exit 0
endef

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
