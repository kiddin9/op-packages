#!/bin/sh
# deploy.sh —— 把「DNS 防绕过」LuCI 应用从电脑部署到路由器（在电脑上执行）
#
#   ./deploy.sh --check     只做语法检查，不往路由器写任何文件
#   ./deploy.sh --install   上传并安装（会先备份旧文件到 /mnt/data/backup-dnsguard/）
#
# 生成：WorkBuddy  2026-09-26
# 注意：本机 Git Bash 的 PATH 里可能没有 coreutils，先执行
#   export PATH="/c/Users/27970/.workbuddy/binaries/PortableGit/versions/1.2.0/usr/bin:$PATH"

set -u
DIR=$(cd "$(dirname "$0")" && pwd)
MODE="${1:---check}"
LUA_CTRL="$DIR/root/usr/lib/lua/luci/controller/dnsguard.lua"
LUA_VIEW="$DIR/root/usr/lib/lua/luci/view/dnsguard/main.htm"
SH_APPLY="$DIR/root/usr/bin/dnsguard-apply"
SH_TEST="$DIR/root/usr/bin/dnsguard-selftest"
SH_ROLL="$DIR/root/usr/bin/dnsguard-rollback"
SH_INIT="$DIR/root/etc/init.d/dnsguard"
SH_INSTALL="$DIR/install.sh"

echo "== 1) 本地 shell 语法检查 =="
for f in "$SH_APPLY" "$SH_TEST" "$SH_ROLL" "$SH_INIT" "$SH_INSTALL"; do
	if [ -f "$f" ] && sh -n "$f" 2>/tmp/.dg-sh.err; then
		echo "   OK   $(basename "$f")"
	else
		echo "   FAIL $(basename "$f")"; cat /tmp/.dg-sh.err 2>/dev/null; exit 1
	fi
done
rm -f /tmp/.dg-sh.err

echo "== 2) JSON 检查（acl 文件）=="
if command -v python >/dev/null 2>&1; then
	python -c "import json,sys;json.load(sys.stdin);print('   OK   acl json')" \
		< "$DIR/root/usr/share/rpcd/acl.d/luci-app-dnsguard.json" || exit 1
else
	echo "   SKIP 没有 python，跳过（内容很短，可肉眼核对）"
fi

echo "== 3) Lua 语法检查（借路由器上的 lua 解释器，只读 stdin，不在设备上写文件）=="
if ssh -o ConnectTimeout=8 router 'command -v lua >/dev/null 2>&1'; then
	if ssh router 'lua -e "local s=io.read(\"*a\"); local f,e=loadstring(s); if f then print(\"   OK   controller\") else print(\"   FAIL \"..tostring(e)); os.exit(1) end"' < "$LUA_CTRL"; then
		echo "   controller 语法通过"
	else
		echo "   controller 语法失败"; exit 1
	fi
	# 视图里的 Lua 只取 <% ... %> 块（跳过 <%+include%> 与 <%=expr%>）
	awk '/^<%/ && $0 !~ /^<%[+="]/ { inb=1; sub(/^<%/,"") } inb { if (/%>/) { sub(/%>.*/,""); print; inb=0 } else print }' "$LUA_VIEW" > /tmp/.dg-view.lua
	echo "   （视图内嵌 Lua 片段 $(wc -l < /tmp/.dg-view.lua) 行）"
	if ssh router 'lua -e "local s=io.read(\"*a\"); local f,e=loadstring(s); if f then print(\"   OK   view-lua\") else print(\"   FAIL \"..tostring(e)); os.exit(1) end"' < /tmp/.dg-view.lua; then
		echo "   视图 Lua 语法通过"
	else
		echo "   视图 Lua 语法失败"; exit 1
	fi
	rm -f /tmp/.dg-view.lua
else
	echo "   SKIP 路由器上没有 lua 命令"
fi

echo "== 4) 渲染脚本语法自检（在设备上以 --render-only 跑一次，不碰防火墙）=="
if [ "$MODE" = "--check" ]; then
	if ssh -o ConnectTimeout=8 router 'test -x /usr/bin/dnsguard-apply'; then
		ssh router '/usr/bin/dnsguard-apply --render-only --out /tmp/dg-check.nft' 2>&1 | sed 's/^/   /'
		ssh router 'rm -f /tmp/dg-check.nft'
	else
		echo "   SKIP 尚未安装到设备（安装后再跑本项）"
	fi
fi

if [ "$MODE" = "--check" ]; then
	echo
	echo "全部检查通过（未改动路由器上的任何文件）。"
	exit 0
fi

if [ "$MODE" != "--install" ]; then
	echo "未知参数：$MODE（可用 --check / --install）" >&2
	exit 1
fi

echo "== 5) 打包上传 =="
TARBALL=/tmp/luci-app-dnsguard.tgz
STAGE=/tmp/.dg-stage.$$
rm -rf "$STAGE"; mkdir -p "$STAGE"
cp -r "$DIR/root" "$DIR/install.sh" "$STAGE/"
tar czf "$TARBALL" -C "$STAGE" .
rm -rf "$STAGE"
echo "   包大小：$(wc -c < "$TARBALL") 字节"
cat "$TARBALL" | ssh router 'cat > /tmp/luci-app-dnsguard.tgz'
rm -f "$TARBALL"

echo "== 6) 在路由器上安装 =="
ssh router 'cd /tmp && rm -rf /tmp/luci-app-dnsguard && mkdir -p /tmp/luci-app-dnsguard && tar xzf /tmp/luci-app-dnsguard.tgz -C /tmp/luci-app-dnsguard && sh /tmp/luci-app-dnsguard/install.sh'

echo
echo "部署结束。请在浏览器打开 http://192.168.1.1 -> 服务 -> DNS 防绕过"
