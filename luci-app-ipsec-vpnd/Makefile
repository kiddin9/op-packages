# SPDX-License-Identifier: Apache-2.0
#
# Original: ImmortalWrt LuCI applications/luci-app-ipsec-vpnd
# Maintained by: szwjp <szwjp@users.noreply.github.com>

include $(TOPDIR)/rules.mk

LUCI_TITLE:=LuCI support for IPSec VPN Server (IKEv1 with PSK and Xauth)
LUCI_DEPENDS:=+strongswan +strongswan-minimal +strongswan-mod-xauth-generic +strongswan-mod-kernel-libipsec +kmod-tun
LUCI_PKGARCH:=all

PKG_NAME:=luci-app-ipsec-vpnd
PKG_VERSION:=27.906.25.12
PKG_RELEASE:=2

define Package/luci-app-ipsec-vpnd/conffiles
/etc/config/ipsec-vpnd
endef

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
