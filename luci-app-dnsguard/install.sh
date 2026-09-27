#!/bin/sh
# install.sh —— 在路由器上安装「DNS 防绕过」LuCI 应用（纯文件，无 apk 包管理）
#
# 前提：部署包已解到 /tmp/luci-app-dnsguard/（deploy.sh 会自动做）
# 重要：本脚本**不碰防火墙**。规则文件 /etc/nftables.d/20-dns-guard.nft 只会在
#       你在界面点「保存并应用」时由 dnsguard-apply 生成 —— 安装阶段零网络风险。
#
# 特性：① 覆盖前自动备份到 /mnt/data/backup-dnsguard/<时间戳>/
#       ② /etc/config/dnsguard 已存在则不覆盖
#       ③ 首次安装会读现有 nft 文件，把"现在到底开没开"回填进 UCI
#
# 生成：WorkBuddy  2026-09-26

SRC=/tmp/luci-app-dnsguard/root
TS=$(date +%Y%m%d-%H%M%S)
BAK=/mnt/data/backup-dnsguard/$TS
NFOUT=/etc/nftables.d/20-dns-guard.nft

if [ ! -d "$SRC" ]; then
	echo "错误：找不到 $SRC，请先运行 deploy.sh 上传" >&2
	exit 1
fi

FILES="etc/config/dnsguard etc/init.d/dnsguard usr/bin/dnsguard-apply usr/bin/dnsguard-selftest usr/bin/dnsguard-rollback usr/lib/lua/luci/controller/dnsguard.lua usr/lib/lua/luci/view/dnsguard/main.htm usr/share/rpcd/acl.d/luci-app-dnsguard.json"

# 从 br-lan 的 IPv4 地址推出网络地址 CIDR（掉主机位）。
# 为什么需要：仓库里带的默认配置用 192.168.1.0/24 作占位，装到别人的网络上必须自动纠正成真实网段，
# 否则「永不劫持」集合会写错，重定向可能把指向内网 DNS 的查询也一起改道。
lan_cidr() {
	l=$(ip -4 addr show dev br-lan 2>/dev/null | sed -n 's#.*inet \([0-9.]*/[0-9]*\).*#\1#p' | head -1)
	[ -n "$l" ] || return 1
	printf '%s\n' "$l" | awk -F'[./]' '{
		p = $5 + 0
		if (p < 0 || p > 32) { exit 1 }
		m = 0
		for (i = 0; i < p; i++) m += 2 ^ (31 - i)
		printf "%d.%d.%d.%d/%d\n", and($1, int(m/16777216) % 256), and($2, int(m/65536) % 256), and($3, int(m/256) % 256), and($4, m % 256), p
	}'
}

# ---------- 1. 备份 ----------
mkdir -p "$BAK"
for f in $FILES; do
	if [ -f "/$f" ]; then
		mkdir -p "$BAK/$(dirname "$f")"
		cp "/$f" "$BAK/$f"
	fi
done
echo "已备份旧文件 -> $BAK"

# ---------- 2. 拷文件 ----------
FIRST_INSTALL=0
if [ -f /etc/config/dnsguard ]; then
	echo "已存在 /etc/config/dnsguard —— 保留不动（你的配置不会被覆盖）"
else
	cp "$SRC/etc/config/dnsguard" /etc/config/dnsguard
	FIRST_INSTALL=1
	echo "已写入默认 UCI 配置"
fi
chmod 600 /etc/config/dnsguard

# 首次安装：把默认配置里的占位网段 192.168.1.0/24 换成本机真实 LAN 网段
if [ "$FIRST_INSTALL" = "1" ]; then
	LAN=$(lan_cidr)
	if [ -n "$LAN" ]; then
		OLD_NH4=$(uci -q get dnsguard.limits.never_hijack4)
		NEW_NH4=$(printf '%s' "$OLD_NH4" | sed "s#192\.168\.1\.0/24#$LAN#")
		if [ "$NEW_NH4" != "$OLD_NH4" ]; then
			uci -q set dnsguard.limits.never_hijack4="$NEW_NH4"
			uci -q commit dnsguard
			echo "已按本机网段修正「永不劫持」：$LAN"
		fi
	else
		echo "警告：未能探测 br-lan 网段，请到界面确认「永不劫持（IPv4）」是否为你真实的 LAN 网段" >&2
	fi
fi

# 配置自检：整个文件必须能被 UCI 解析。
# 踩过的坑：两个节的「名字」相同会让整个文件直接不可用，而 uci -q set 是静默失败 ——
# 结果就是"配了等于没配"，必须在这里拦住。
if ! uci -q show dnsguard >/dev/null 2>&1; then
	echo "错误：/etc/config/dnsguard 无法被 UCI 解析（多半是分节名重复）—— 已中止安装" >&2
	uci show dnsguard >&2
	exit 1
fi
echo "配置解析自检通过"

for f in usr/bin/dnsguard-apply usr/bin/dnsguard-selftest usr/bin/dnsguard-rollback; do
	cp "$SRC/$f" "/$f"
	chmod 755 "/$f"
done
cp "$SRC/etc/init.d/dnsguard" /etc/init.d/dnsguard
chmod 755 /etc/init.d/dnsguard

mkdir -p /usr/lib/lua/luci/controller /usr/lib/lua/luci/view/dnsguard /usr/share/rpcd/acl.d
cp "$SRC/usr/lib/lua/luci/controller/dnsguard.lua" /usr/lib/lua/luci/controller/dnsguard.lua
cp "$SRC/usr/lib/lua/luci/view/dnsguard/main.htm" /usr/lib/lua/luci/view/dnsguard/main.htm
cp "$SRC/usr/share/rpcd/acl.d/luci-app-dnsguard.json" /usr/share/rpcd/acl.d/luci-app-dnsguard.json
echo "程序文件已安装"

# 让 /etc/init.d/dnsguard 进入启动序列（boot() 是空实现，开机不做任何动作）
/etc/init.d/dnsguard enable >/dev/null 2>&1

# ---------- 3. 首次安装：读现有 nft 文件，回填 UCI ----------
SEEDED=0
if [ -f "$NFOUT" ]; then
	if grep -q 'dns_guard_redirect' "$NFOUT" 2>/dev/null; then
		uci -q set dnsguard.main.redirect53='1'; SEEDED=1
	fi
	if grep -q 'dns_guard_pre_forward' "$NFOUT" 2>/dev/null; then
		uci -q set dnsguard.main.watch='1'; SEEDED=1
	fi
	if grep -q 'dns_guard_block' "$NFOUT" 2>/dev/null; then
		uci -q set dnsguard.main.block853='1'; SEEDED=1
	fi
	if [ "$SEEDED" = "0" ]; then
		# 文件存在但不含任何我们的链 -> 认为这是纯观察期的老文件
		uci -q set dnsguard.main.watch='1'; SEEDED=1
	fi
fi

if [ "$SEEDED" = "1" ]; then
	uci -q commit dnsguard
	chmod 600 /etc/config/dnsguard
	echo "已把现有防火墙状态回填进 UCI（WebUI 打开即可看到当前值）"
	echo "  自检 enabled='$(uci -q get dnsguard.main.enabled)'  redirect53='$(uci -q get dnsguard.main.redirect53)'  watch='$(uci -q get dnsguard.main.watch)'"
fi

# ---------- 4. 让 LuCI 认到新菜单 ----------
rm -f /tmp/luci-indexcache* 2>/dev/null
/etc/init.d/rpcd reload >/dev/null 2>&1
/etc/init.d/uhttpd reload >/dev/null 2>&1

echo
echo "安装完成（未改动任何防火墙规则）。入口：LuCI -> 服务 -> DNS 防绕过"
echo "回滚：cp -r $BAK/* / && rm -f /usr/lib/lua/luci/controller/dnsguard.lua && rm -rf /usr/lib/lua/luci/view/dnsguard /usr/share/rpcd/acl.d/luci-app-dnsguard.json /etc/init.d/dnsguard && rm -f /tmp/luci-indexcache*"
exit 0
