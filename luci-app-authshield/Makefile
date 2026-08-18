# luci-app-authshield — multi-service login intrusion prevention for OpenWrt
# Packages a LuCI application that rate-limits failed logins and bans IPs
# using nftables set timeouts. Supports LuCI (rpcd/uhttpd) and optional Dropbear.

include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-authshield
PKG_VERSION:=1.17
PKG_RELEASE:=1
PKG_MAINTAINER:=iv7777 <hongba@rocketmail.com>
PKG_LICENSE:=MIT

# Display name in LuCI menu / package lists
LUCI_TITLE:=Multi-service login intrusion prevention
LUCI_DEPENDS:=
LUCI_PKGARCH:=all

include $(TOPDIR)/feeds/luci/luci.mk

# Post-install: run UCI defaults script to inject nft include and enable service
define Package/$(PKG_NAME)/postinst
#!/bin/sh
[ -n "$$IPKG_INSTROOT" ] || {
  [ -x //etc/uci-defaults/99-authshield-setup ] && /etc/uci-defaults/99-authshield-setup
}
exit 0
endef

# Pre-remove: stop the service quietly
define Package/$(PKG_NAME)/prerm
#!/bin/sh
/etc/init.d/authshield stop >/dev/null 2>&1 || true
exit 0
endef

# call BuildPackage - OpenWrt buildroot signature
