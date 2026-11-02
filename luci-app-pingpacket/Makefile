include $(TOPDIR)/rules.mk

LUCI_TITLE:=LuCI web interface for Pingpacket monitoring
LUCI_DEPENDS:=+luci-base +luci-lua-runtime +luci-compat +curl
LUCI_PKGARCH:=all

PKG_NAME:=luci-app-pingpacket
PKG_VERSION:=1.0.0
PKG_RELEASE:=3
PKG_LICENSE:=Apache-2.0

include $(TOPDIR)/feeds/luci/luci.mk

define Package/$(PKG_NAME)/install
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/controller
	$(INSTALL_DATA) ./luasrc/controller/pingpacket.lua $(1)/usr/lib/lua/luci/controller/pingpacket.lua

	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/view/pingpacket
	$(INSTALL_DATA) ./luasrc/view/pingpacket/status.htm $(1)/usr/lib/lua/luci/view/pingpacket/status.htm
	$(INSTALL_DATA) ./luasrc/view/pingpacket/logs.htm $(1)/usr/lib/lua/luci/view/pingpacket/logs.htm

	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./root/etc/config/pingpacket $(1)/etc/config/pingpacket

	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./root/etc/init.d/pingpacket $(1)/etc/init.d/pingpacket

	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) ./root/usr/bin/pingpacket.sh $(1)/usr/bin/pingpacket.sh

	$(INSTALL_DIR) $(1)/usr/share/rpcd/acl.d
	$(INSTALL_DATA) ./root/usr/share/rpcd/acl.d/luci-app-pingpacket.json \
		$(1)/usr/share/rpcd/acl.d/luci-app-pingpacket.json
endef

define Package/$(PKG_NAME)/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] && exit 0

# 丢包历史数据目录（按天分文件保存，最多保留 35 天）
mkdir -p /etc/pingpacket/history

# 升级时 opkg 会把新的默认配置文件留成 pingpacket-opkg，
# 这里只补齐旧配置中缺失的选项，已有取值保持不变。
merge_pingpacket_options() {
	local source_file="/etc/config/pingpacket-opkg"
	local key
	local value

	[ -f "$$source_file" ] || return 0

	if [ ! -f /etc/config/pingpacket ]; then
		mv -f "$$source_file" /etc/config/pingpacket
		return 0
	fi

	sed -n "s/^[[:space:]]*option[[:space:]]\+\([A-Za-z0-9_]*\)[[:space:]]\+\(.*\)$$/\1=\2/p" "$$source_file" | tr -d "'" |
	while IFS='=' read -r key value; do
		[ -n "$$key" ] || continue
		if [ -z "$$(uci -q get "pingpacket.config.$$key")" ]; then
			uci -q set "pingpacket.config.$$key=$$value"
		fi
	done

	uci -q commit pingpacket
	rm -f "$$source_file"
}

merge_pingpacket_options

rm -f /tmp/luci-indexcache.*
rm -rf /tmp/luci-modulecache/
/etc/init.d/rpcd reload 2>/dev/null
exit 0
endef

define Package/$(PKG_NAME)/prerm
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] && exit 0
[ -f /etc/init.d/pingpacket ] && {
	/etc/init.d/pingpacket disable 2>/dev/null
	/etc/init.d/pingpacket stop 2>/dev/null
}
exit 0
endef

$(eval $(call BuildPackage,$(PKG_NAME)))
