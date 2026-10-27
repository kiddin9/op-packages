include $(TOPDIR)/rules.mk

PKG_NAME:=isp-split
PKG_VERSION:=0.1.3
PKG_RELEASE:=4
PKG_LICENSE:=MIT
PKG_MAINTAINER:=jihebube <jihebube@users.noreply.github.com>

include $(INCLUDE_DIR)/package.mk

define Package/isp-split
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=Routing and Redirection
  TITLE:=ISP-aware policy routing for mwan3 (nftables)
# 注意：这里故意不写 +mwan3 依赖。
#   官方 feed 的 mwan3 是 iptables 版（2.12.5），写 +mwan3 会错误地拉进它；
#   Kwrt 源里 nft 版的包名是 mwan3-nft，与其他源命名不一致。
#   nftables 版 mwan3 是硬性前提，由 install.sh 与 router-preflight 检查，
#   并在 description 里说明。
  DEPENDS:=+nftables +curl
  PKGARCH:=all
endef

define Package/isp-split/description
  Route traffic by the ISP that owns the destination address.
  Builds mutually exclusive nftables sets from daily-updated
  Chinese ISP CIDR data and wires them into mwan3-nft rules.

  REQUIRES the nftables port of mwan3 (>= 3.6.0):
    - Kwrt:  apk add mwan3-nft        (软件源里自带)
    - 上游:  用 https://github.com/dl12345/mwan3 替换官方 feed 的
             iptables 版 mwan3 (2.12.5)，或从 Release 下载
endef

define Build/Compile
endef

define Package/isp-split/conffiles
/etc/isp-split.conf
endef

# opkg 升级会以 prerm upgrade 调用；apk 的 prerm 只映射到 pre-deinstall。
# 升级时绝不能 uninstall：数据目录、mwan3 规则都必须保留。
define Package/isp-split/prerm
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] && exit 0
case "$${1:-}" in
	upgrade|pre-upgrade|*upgrade*) exit 0 ;;
esac
if [ -x /usr/sbin/isp-split ]; then
	/usr/sbin/isp-split uninstall >/dev/null 2>&1 || true
fi
exit 0
endef

# 卸载后的兜底清理：cron、命名计数器、dnsmasq confdir、数据目录。
# 正常路径由 prerm 的 isp-split uninstall 完成，这里防止二进制先被删掉。
define Package/isp-split/postrm
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] && exit 0
case "$${1:-}" in
	upgrade|pre-upgrade|*upgrade*) exit 0 ;;
esac
if [ -f /etc/crontabs/root ]; then
	grep -v 'isp-split' /etc/crontabs/root > /tmp/.ispcron.$$$$ 2>/dev/null || true
	mv /tmp/.ispcron.$$$$ /etc/crontabs/root 2>/dev/null || true
	/etc/init.d/cron restart >/dev/null 2>&1 || true
fi
nft delete counter inet mwan3 isp_fallback >/dev/null 2>&1 || true
_state=/etc/isp-split/state/dnsmasq.confdir.orig
if [ -f "$$_state" ]; then
	_orig=$$(cat "$$_state" 2>/dev/null)
	if [ -n "$$_orig" ]; then
		uci -q set "dhcp.@dnsmasq[0].confdir=$$_orig" 2>/dev/null || true
	else
		uci -q delete dhcp.@dnsmasq[0].confdir 2>/dev/null || true
	fi
	uci -q commit dhcp 2>/dev/null || true
	rm -f "$$_state"
fi
# BUG-6：OpenClash 接管时 dnsmasq 实际加载的是 /var/etc/dnsmasq.conf.*
# 里 conf-dir= 指向的目录，必须按同一来源清理，不能只删 /tmp/dnsmasq.d。
for _f in /var/etc/dnsmasq.conf.*; do
	[ -f "$$_f" ] || continue
	sed -n 's/^[[:space:]]*conf-dir=//p' "$$_f" 2>/dev/null |
	while IFS= read -r _line; do
		for _d in $$_line; do
			_d=$${_d%%,*}
			while [ "$$_d" != "/" ] && [ "$${_d%/}" != "$$_d" ]; do
				_d=$${_d%/}
			done
			[ -n "$$_d" ] && rm -f "$$_d/isp-split.conf" 2>/dev/null || true
		done
	done
done
rm -f /tmp/dnsmasq.d/isp-split.conf /etc/isp-split/dnsmasq.d/isp-split.conf 2>/dev/null || true
rm -rf /etc/isp-split 2>/dev/null || true
exit 0
endef

# 显式指定权限，不依赖源文件的权限位——固件里脚本不可执行会很难查
define Package/isp-split/install
	$(INSTALL_DIR) $(1)/usr/sbin
	$(INSTALL_DIR) $(1)/usr/lib/isp-split
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_DIR) $(1)/etc/uci-defaults
	$(INSTALL_DIR) $(1)/etc/isp-split/data

	$(INSTALL_BIN) ./files/usr/sbin/isp-split $(1)/usr/sbin/isp-split
	$(INSTALL_BIN) ./files/etc/init.d/isp-split $(1)/etc/init.d/isp-split
	$(INSTALL_BIN) ./files/usr/lib/isp-split/build.sh $(1)/usr/lib/isp-split/build.sh
	$(INSTALL_BIN) ./files/etc/uci-defaults/99-isp-split $(1)/etc/uci-defaults/99-isp-split

	$(INSTALL_DATA) ./files/usr/lib/isp-split/cidr2range.awk $(1)/usr/lib/isp-split/cidr2range.awk
	$(INSTALL_DATA) ./files/usr/lib/isp-split/merge.awk $(1)/usr/lib/isp-split/merge.awk
	$(INSTALL_DATA) ./files/usr/lib/isp-split/exclude.awk $(1)/usr/lib/isp-split/exclude.awk
	$(INSTALL_DATA) ./files/usr/lib/isp-split/range2cidr.awk $(1)/usr/lib/isp-split/range2cidr.awk
	$(INSTALL_DATA) ./files/usr/lib/isp-split/rules-splice.awk $(1)/usr/lib/isp-split/rules-splice.awk
	$(INSTALL_DATA) ./files/usr/lib/isp-split/badcidr.awk $(1)/usr/lib/isp-split/badcidr.awk
	$(INSTALL_CONF) ./files/etc/isp-split.conf $(1)/etc/isp-split.conf
endef

$(eval $(call BuildPackage,isp-split))
