include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-cf-dns-speedtest
PKG_VERSION:=1.1.0
PKG_RELEASE:=1
PKG_LICENSE:=GPL-3.0-only
PKG_MAINTAINER:=xiaokeikei

include $(INCLUDE_DIR)/package.mk

define Package/luci-app-cf-dns-speedtest
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  TITLE:=Cloudflare DNS speed test and scoped mosdns integration
  DEPENDS:=+luci-base +mosdns
  PKGARCH:=x86_64
endef

define Package/luci-app-cf-dns-speedtest/description
 Selects a Cloudflare IPv4 address and serves it only for configured domains
 through an isolated local mosdns instance.
endef

define Package/luci-app-cf-dns-speedtest/conffiles
/etc/config/cf_dns_speedtest
endef

define Build/Compile
endef

define Package/luci-app-cf-dns-speedtest/install
	$(CP) ./root/* $(1)/
endef

define Package/luci-app-cf-dns-speedtest/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] && exit 0
chmod 0755 /usr/bin/cf-dns-speedtest /usr/share/cf-dns-speedtest/cfst /etc/init.d/cf-dns-speedtest
/etc/init.d/cf-dns-speedtest enable
rm -rf /tmp/luci-indexcache /tmp/luci-modulecache
[ "$$(uci -q get cf_dns_speedtest.config.enabled)" = 1 ] && /usr/bin/cf-dns-speedtest apply >/dev/null 2>&1
exit 0
endef

define Package/luci-app-cf-dns-speedtest/prerm
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] && exit 0
/etc/init.d/cf-dns-speedtest stop 2>/dev/null
if [ -s /var/lib/cf-dns-speedtest/routes.active ]; then
  while IFS= read -r route; do uci -q del_list dhcp.@dnsmasq[0].server="$${route}"; done < /var/lib/cf-dns-speedtest/routes.active
fi
uci -q commit dhcp
sed -i '/# cf-dns-speedtest$$/d' /etc/crontabs/root
/etc/init.d/dnsmasq restart 2>/dev/null
exit 0
endef

$(eval $(call BuildPackage,luci-app-cf-dns-speedtest))
