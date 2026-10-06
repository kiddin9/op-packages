#!/bin/sh
set -e
D="$(cd "$(dirname "$0")" && pwd)"
echo ""; echo "==== MiniGate 安装 ===="; echo ""
[ "$(id -u)" = "0" ] || { echo "[!] 需要root"; exit 1; }

dependency_ready() {
    case "$1" in
        openssl-util)
            command -v openssl >/dev/null 2>&1 && openssl version >/dev/null 2>&1
            ;;
        *)
            return 1
            ;;
    esac
}

install_dependencies() {
    local p
    if command -v opkg >/dev/null 2>&1; then
        PKG="opkg"
        for p in curl jsonfilter nftables nginx-mod-stream openssl-util; do
            dependency_ready "$p" && continue
            opkg list-installed 2>/dev/null | grep -q "^${p} " || { opkg update 2>/dev/null; opkg install "$p" 2>/dev/null; }
        done
    elif command -v apk >/dev/null 2>&1; then
        PKG="apk"
        for p in curl jsonfilter nftables nginx-mod-stream openssl-util; do
            dependency_ready "$p" && continue
            apk info -e "$p" >/dev/null 2>&1 || apk add "$p" 2>/dev/null
        done
    fi
}

# 检测包管理器 + 安装依赖（stream 用于同端口 HTTP/HTTPS 识别）
install_dependencies

[ -f /etc/init.d/minigate ] && /etc/init.d/minigate stop 2>/dev/null || true

# 清理旧的独立 login-guard 部署（如有）
[ -f /etc/init.d/login-guard ] && {
    /etc/init.d/login-guard stop 2>/dev/null || true
    /etc/init.d/login-guard disable 2>/dev/null || true
    rm -f /etc/init.d/login-guard
    rm -f /usr/sbin/login-guard /usr/sbin/login-guard.sh
    # 迁移 bans.txt（如有）
    [ -f /etc/login-guard/bans.txt ] && {
        mkdir -p /etc/minigate/login-guard
        cp /etc/login-guard/bans.txt /etc/minigate/login-guard/bans.txt
    }
    echo "[*] 已清理旧的独立 login-guard"
}

mkdir -p /usr/lib/minigate
mkdir -p /etc/minigate/acme /etc/minigate/certs /etc/minigate/nginx/sites /etc/minigate/nginx/streams /etc/minigate/login-guard
cp "$D"/root/usr/lib/minigate/*.sh /usr/lib/minigate/; chmod +x /usr/lib/minigate/*.sh
cp "$D"/root/etc/init.d/minigate /etc/init.d/; chmod +x /etc/init.d/minigate

# 配置：保留旧的，但确保有 login_guard 区段
if [ -f /etc/config/minigate ]; then
    echo "[*] 保留现有配置"
    grep -q "config login_guard" /etc/config/minigate || cat >> /etc/config/minigate <<EOF

config login_guard 'login_guard'
	option enabled '0'
	option threshold '3'
	option window '600'
	option bantime '43200'
EOF
else
    cp "$D"/root/etc/config/minigate /etc/config/
fi

# v1.3.11 起由每条 HTTPS 规则的监听端口直接承担 HTTP 跳转。
uci -q delete minigate.global.http_redirect_port 2>/dev/null || true
uci -q commit minigate 2>/dev/null || true

mkdir -p /usr/lib/lua/luci/controller
mkdir -p /usr/lib/lua/luci/model/cbi/minigate
mkdir -p /usr/lib/lua/luci/view/minigate
cp "$D"/luasrc/controller/minigate.lua /usr/lib/lua/luci/controller/
cp "$D"/luasrc/model/cbi/minigate/*.lua /usr/lib/lua/luci/model/cbi/minigate/
cp "$D"/luasrc/view/minigate/*.htm /usr/lib/lua/luci/view/minigate/
rm -rf /tmp/luci-* 2>/dev/null
/etc/init.d/minigate enable 2>/dev/null
/etc/init.d/minigate start 9>&- 2>/dev/null || true
echo ""; echo "==== 安装完成 ===="
echo "LuCI -> 服务 -> MiniGate"
echo "登录防护 tab 默认关闭，到 LuCI 启用即可。"
echo ""
