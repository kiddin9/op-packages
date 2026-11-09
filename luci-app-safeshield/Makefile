# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 3
# of the License, or (at your option) any later version.

include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-safeshield
PKG_VERSION:=0.2.2
PKG_RELEASE:=1

PKG_LICENSE:=GPL-3.0-or-later
PKG_MAINTAINER:=Beomjun Kang <kals323@gmail.com>

LUCI_TITLE:=SafeShield Web UI
LUCI_URL:=https://github.com/Junatum/luci-app-safeshield
LUCI_DESCRIPTION:=SafeShield Web UI for OpenWrt
LUCI_DEPENDS:=+luci-base +rpcd +ucode +safeshield
LUCI_EXTRA_DEPENDS:=safeshield (>=0.3.20)

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
