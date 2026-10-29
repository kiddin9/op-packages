include $(TOPDIR)/rules.mk

PKG_NAME:=isp-split
PKG_VERSION:=0.3.0
PKG_RELEASE:=4
PKG_LICENSE:=MIT
PKG_LICENSE_FILES:=LICENSE
PKG_MAINTAINER:=jihebube <jihebube@users.noreply.github.com>

include $(INCLUDE_DIR)/package.mk

# 线路体检（linecheck）自 0.3.0 起随包发货，默认 1。
#   1 = 完整功能（默认，正式发行版走这条路径）；
#   0 = 构建期物理剥离：实现、CLI、conf 键、LuCI 页/菜单、socat 依赖全部不进包。
#       小闪存 / 特殊渠道的可选剥离版，必须显式指定 FEATURE_LINECHECK=0。
# 这是构建期开关，不是运行时开关：0 的产物里没有可被重新打开的代码。
FEATURE_LINECHECK?=1

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
  DEPENDS:=+nftables +curl +mwan3-nft $(if $(filter 1,$(FEATURE_LINECHECK)),+socat)
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

define Build/Prepare
	rm -rf $(PKG_BUILD_DIR)
	mkdir -p $(PKG_BUILD_DIR)
	$(CP) ./files $(PKG_BUILD_DIR)/files
	# 只调用仓库里那一份 strip-linecheck.sh（随包内 strip-linecheck.sh 逐字节
	# 一致），不再手抄 sed：F7 的泄漏就是 SDK 侧另抄一份、覆盖不全造成的。
	# 脚本自己会做标记配对、零残留、CSS `.lc-*` 与 sh -n 断言。
	if [ "$(FEATURE_LINECHECK)" != "1" ]; then \
		sh $(CURDIR)/strip-linecheck.sh $(PKG_BUILD_DIR)/files; \
	fi
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

# 卸载后的兜底清理。正常路径是 prerm 里的 `isp-split uninstall`（它调
# /usr/lib/isp-split/teardown.sh，与 scripts/install.sh --uninstall 同一份实现）。
# 但 opkg/apk 会先删包文件再跑 postrm，那时 teardown.sh 已经不在盘上，
# 所以这里必须自带一份等价的内联清单 —— 这是"三条路径同源"的唯一例外，
# 由 tools/selftest.sh 第 21 节做锚点双向核对：teardown.sh 的 runtime 锚点
# 必须逐条出现在本块里，本块也不许出现清单外的清理动作。
define Package/isp-split/postrm
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] && exit 0
case "$${1:-}" in
	upgrade|pre-upgrade|*upgrade*) exit 0 ;;
esac
# 共享实现在盘上就用它（少数包管理器/强制删除会在删文件前跑 postrm）。
if [ -f /usr/lib/isp-split/teardown.sh ]; then
	sh /usr/lib/isp-split/teardown.sh all
	exit $$?
fi
if [ -f /etc/crontabs/root ]; then
	# mktemp 而不是固定 /tmp 名：PID 可预测，符号链接能抢占（SEC-1）
	_cron_tmp=$$(mktemp /etc/.isp-split-cron.XXXXXX) || _cron_tmp=""
	if [ -n "$$_cron_tmp" ]; then
		grep -v 'isp-split' /etc/crontabs/root > "$$_cron_tmp" 2>/dev/null || true
		mv -f "$$_cron_tmp" /etc/crontabs/root 2>/dev/null || rm -f "$$_cron_tmp"
	fi
	/etc/init.d/cron restart >/dev/null 2>&1 || true
fi
nft delete counter inet mwan3 isp_fallback >/dev/null 2>&1 || true
# B-5：状态文件已改名 dnsmasq.confdir.migrated（记的是迁移后的清理值）。
# 旧名 dnsmasq.confdir.orig 兼容读一次。
_state=/etc/isp-split/state/dnsmasq.confdir.migrated
[ -f "$$_state" ] || _state=/etc/isp-split/state/dnsmasq.confdir.orig
if [ -f "$$_state" ]; then
	_orig=$$(head -1 "$$_state" 2>/dev/null)
	if [ -n "$$_orig" ]; then
		uci -q set "dhcp.@dnsmasq[0].confdir=$$_orig" 2>/dev/null || true
	else
		uci -q delete dhcp.@dnsmasq[0].confdir 2>/dev/null || true
	fi
	uci -q commit dhcp 2>/dev/null || true
	rm -f /etc/isp-split/state/dnsmasq.confdir.migrated \
		/etc/isp-split/state/dnsmasq.confdir.orig 2>/dev/null || true
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
# F-14：install.sh 留下的 /etc/isp-split.conf.bak.* 与主配置一并清掉（与 teardown.sh
# 同策略：默认删，逐条打印由 teardown.sh 负责；这里只兜底）。
rm -f /etc/isp-split.conf /etc/isp-split.conf.bak.* 2>/dev/null || true
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

	$(INSTALL_BIN) $(PKG_BUILD_DIR)/files/usr/sbin/isp-split $(1)/usr/sbin/isp-split
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/files/etc/init.d/isp-split $(1)/etc/init.d/isp-split
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/files/usr/lib/isp-split/build.sh $(1)/usr/lib/isp-split/build.sh
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/files/etc/uci-defaults/99-isp-split $(1)/etc/uci-defaults/99-isp-split
	# F-14：卸载清理的唯一实现。prerm（isp-split uninstall）与
	# scripts/install.sh --uninstall 都调它；postrm 在二进制先被删掉时
	# 用内联等价清单兜底（锚点由 selftest 第 21 节双向核对）。
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/files/usr/lib/isp-split/teardown.sh $(1)/usr/lib/isp-split/teardown.sh

	$(INSTALL_DATA) $(PKG_BUILD_DIR)/files/usr/lib/isp-split/cidr2range.awk $(1)/usr/lib/isp-split/cidr2range.awk
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/files/usr/lib/isp-split/merge.awk $(1)/usr/lib/isp-split/merge.awk
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/files/usr/lib/isp-split/exclude.awk $(1)/usr/lib/isp-split/exclude.awk
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/files/usr/lib/isp-split/range2cidr.awk $(1)/usr/lib/isp-split/range2cidr.awk
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/files/usr/lib/isp-split/rules-splice.awk $(1)/usr/lib/isp-split/rules-splice.awk
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/files/usr/lib/isp-split/badcidr.awk $(1)/usr/lib/isp-split/badcidr.awk
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/files/usr/lib/isp-split/ispdiff.awk $(1)/usr/lib/isp-split/ispdiff.awk
	if [ -f $(PKG_BUILD_DIR)/files/usr/lib/isp-split/lc-run ]; then \
		$(INSTALL_BIN) $(PKG_BUILD_DIR)/files/usr/lib/isp-split/lc-run $(1)/usr/lib/isp-split/lc-run; \
	fi
	$(INSTALL_CONF) $(PKG_BUILD_DIR)/files/etc/isp-split.conf $(1)/etc/isp-split.conf
endef

$(eval $(call BuildPackage,isp-split))
