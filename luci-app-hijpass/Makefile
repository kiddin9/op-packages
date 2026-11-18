include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-hijpass
PKG_VERSION:=26.11.12
PKG_RELEASE:=2
LUCI_TITLE:=LuCI support for HiJpass
LUCI_PKGARCH:=all
# esbuild 已压缩 JS；再次经过 jsmin 会改写 CodeMirror 中的正则表达式。
LUCI_MINIFY_JS:=0

LUCI_DEPENDS:= +ca-bundle +curl +firewall4 +ip-full +rpcd +jshn \
	+sing-box +unzip +xray-core \
	+kmod-nft-socket +kmod-nft-tproxy +kmod-nft-nat \
	+v2ray-geosite +v2ray-geoip +geoview +chinadns-ng \
	+ucode +ucode-mod-fs +ucode-mod-uci +ucode-mod-resolv +ucode-mod-ubus +cgi-io

define Package/$(PKG_NAME)/conffiles
/etc/hijpass/firewall.ut
/etc/hijpass/hook/dns-hook.sh
/etc/hijpass/hook/nft-hook.sh
/etc/hijpass/rules/chn-list.txt
/etc/hijpass/rules/chn-route.txt
/etc/hijpass/rules/chn-route6.txt
/etc/hijpass/rules/domain-direct.txt
/etc/hijpass/rules/domain-proxy.txt
/etc/hijpass/rules/gfw-list.txt
/etc/hijpass/rules/ip-direct.txt
/etc/hijpass/rules/ip-proxy.txt
/etc/hijpass/shunt.json
/etc/config/hijpass
/etc/config/hijserver
endef

define Package/$(PKG_NAME)/prerm
#!/bin/sh
/etc/init.d/hijpass stop
/etc/init.d/hijserver stop
exit 0
endef

define Package/$(PKG_NAME)/postrm
#!/bin/sh
uci -q batch <<-EOF >/dev/null
	delete firewall.hijpass
	commit firewall
EOF
exit 0
endef

# 默认副本不列入 conffiles；恢复默认始终读取当前软件包版本的模板。
define Build/FirewallDefault
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/root/etc/hijpass/firewall.ut $(PKG_BUILD_DIR)/root/usr/lib/hijpass/firewall/default.ut
endef
Hooks/Compile/Post += Build/FirewallDefault

# ucode 源文件由 LuCI 的 root 安装流程直接复制，整个包保持架构无关。
include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
