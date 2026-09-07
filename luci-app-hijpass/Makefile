include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-hijpass
PKG_VERSION:=26.9.6
PKG_RELEASE:=1
LUCI_TITLE:=LuCI support for HiJpass
LUCI_PKGARCH:=all

PKG_CONFIG_DEPENDS:= \
	CONFIG_PACKAGE_$(PKG_NAME)_INCLUDE_Hysteria \
	CONFIG_PACKAGE_$(PKG_NAME)_INCLUDE_NaiveProxy \
	CONFIG_PACKAGE_$(PKG_NAME)_INCLUDE_Shadowsocks_Libev_Client \
	CONFIG_PACKAGE_$(PKG_NAME)_INCLUDE_Shadowsocks_Libev_Server \
	CONFIG_PACKAGE_$(PKG_NAME)_INCLUDE_Shadowsocks_Rust_Client \
	CONFIG_PACKAGE_$(PKG_NAME)_INCLUDE_Shadowsocks_Rust_Server \
	CONFIG_PACKAGE_$(PKG_NAME)_INCLUDE_Shadow_TLS \
	CONFIG_PACKAGE_$(PKG_NAME)_INCLUDE_Trojan_Plus \
	CONFIG_PACKAGE_$(PKG_NAME)_INCLUDE_tuic_client

LUCI_DEPENDS:= +ca-bundle +curl +file +firewall4 +ip-full +luci-lua-runtime \
	+sing-box +unzip +xray-core \
	+kmod-nft-socket +kmod-nft-tproxy +kmod-nft-nat \
	+v2ray-geosite +v2ray-geoip +geoview +chinadns-ng +jq

define Package/$(PKG_NAME)/config
menu "Configuration"
	depends on PACKAGE_$(PKG_NAME)

config PACKAGE_$(PKG_NAME)_INCLUDE_Hysteria
	bool "Include Hysteria"
	select PACKAGE_hysteria
	default y if aarch64||x86_64

config PACKAGE_$(PKG_NAME)_INCLUDE_NaiveProxy
	bool "Include NaiveProxy"
	depends on !(arc||armeb||loongarch64||mips||mips64||powerpc||TARGET_gemini)
	select PACKAGE_naiveproxy
	default n

config PACKAGE_$(PKG_NAME)_INCLUDE_Shadowsocks_Libev_Client
	bool "Include Shadowsocks Libev Client"
	select PACKAGE_shadowsocks-libev-ss-local
	select PACKAGE_shadowsocks-libev-ss-redir
	default y

config PACKAGE_$(PKG_NAME)_INCLUDE_Shadowsocks_Libev_Server
	bool "Include Shadowsocks Libev Server"
	select PACKAGE_shadowsocks-libev-ss-server
	default y

config PACKAGE_$(PKG_NAME)_INCLUDE_Shadowsocks_Rust_Client
	bool "Include Shadowsocks Rust Client"
	depends on !i386
	select PACKAGE_shadowsocks-rust-sslocal
	default n

config PACKAGE_$(PKG_NAME)_INCLUDE_Shadowsocks_Rust_Server
	bool "Include Shadowsocks Rust Server"
	depends on !i386
	select PACKAGE_shadowsocks-rust-ssserver
	default n

config PACKAGE_$(PKG_NAME)_INCLUDE_Shadow_TLS
	bool "Include Shadow-TLS"
	select PACKAGE_shadow-tls
	depends on aarch64||arm||x86_64
	default n

config PACKAGE_$(PKG_NAME)_INCLUDE_Trojan_Plus
	bool "Include Trojan-Plus"
	select PACKAGE_trojan-plus
	default y

config PACKAGE_$(PKG_NAME)_INCLUDE_tuic_client
	bool "Include tuic-client"
	depends on aarch64||arm||i386||x86_64
	select PACKAGE_tuic-client
	default n

endmenu
endef

define Package/$(PKG_NAME)/conffiles
/etc/hijpass/fw4-template.nft
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

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
