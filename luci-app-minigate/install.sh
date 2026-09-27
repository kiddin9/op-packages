#!/bin/sh
set -e
D="$(cd "$(dirname "$0")" && pwd)"
echo ""; echo "==== MiniGate 安装 ===="; echo ""
[ "$(id -u)" = "0" ] || { echo "[!] 需要root"; exit 1; }

# 检测包管理器
if command -v opkg >/dev/null 2>&1; then
    PKG="opkg"
    for p in curl jsonfilter; do opkg list-installed 2>/dev/null|grep -q "^${p} "||{ opkg update 2>/dev/null;opkg install "$p" 2>/dev/null; }; done
elif command -v apk >/dev/null 2>&1; then
    PKG="apk"
    for p in curl jsonfilter; do apk info -e "$p" >/dev/null 2>&1 || apk add "$p" 2>/dev/null; done
fi

[ -f /etc/init.d/minigate ] && /etc/init.d/minigate stop 2>/dev/null || true
mkdir -p /usr/lib/minigate /etc/minigate/{acme,certs,nginx/sites}
cp "$D"/root/usr/lib/minigate/*.sh /usr/lib/minigate/; chmod +x /usr/lib/minigate/*.sh
cp "$D"/root/etc/init.d/minigate /etc/init.d/; chmod +x /etc/init.d/minigate
[ -f /etc/config/minigate ]&&echo "[*] 保留配置"||cp "$D"/root/etc/config/minigate /etc/config/
mkdir -p /usr/lib/lua/luci/{controller,model/cbi/minigate,view/minigate}
cp "$D"/luasrc/controller/minigate.lua /usr/lib/lua/luci/controller/
cp "$D"/luasrc/model/cbi/minigate/*.lua /usr/lib/lua/luci/model/cbi/minigate/
cp "$D"/luasrc/view/minigate/*.htm /usr/lib/lua/luci/view/minigate/
rm -rf /tmp/luci-* 2>/dev/null; /etc/init.d/minigate enable 2>/dev/null
echo ""; echo "==== 安装完成 ===="; echo "LuCI -> 服务 -> MiniGate"; echo ""
