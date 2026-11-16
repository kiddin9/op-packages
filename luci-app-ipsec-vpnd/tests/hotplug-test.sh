#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
#
# /etc/hotplug.d/iface/90-ipsec-vpnd 的离线测试。
#
# 用 sed 把脚本里的绝对路径换成临时目录，配合桩件 uci / logger / ipsec
# 验证：只在 WAN 地址真的变化时才重启，普通 ifup/lan 事件不动作。

set -u

HOTPLUG="${1:-root/etc/hotplug.d/iface/90-ipsec-vpnd}"
[ -f "$HOTPLUG" ] || HOTPLUG="/etc/hotplug.d/iface/90-ipsec-vpnd"
[ -f "$HOTPLUG" ] || { echo "找不到 hotplug 脚本: $HOTPLUG"; exit 1; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/hotplug-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/lib" "$TMP/init" "$TMP/bin"

fail=0
check() {
	if [ "$2" = "$3" ]; then
		echo "ok   - $1"
	else
		echo "FAIL - $1"
		echo "       期望: [$2]"
		echo "       实际: [$3]"
		fail=1
	fi
}

cat > "$TMP/lib/network.sh" <<EOF
network_get_ipaddr() {
	eval "\$1=\$(cat "$TMP/ip")"
}
EOF

cat > "$TMP/init/ipsec" <<EOF
#!/bin/sh
[ "\$1" = "restart" ] && echo restart >> "$TMP/restarts"
exit 0
EOF
chmod 0755 "$TMP/init/ipsec"

cat > "$TMP/bin/uci" <<'EOF'
#!/bin/sh
# uci -q get ipsec-vpnd.ipsec.enabled
[ "$1" = "-q" ] && shift
[ "$1" = "get" ] && [ "$2" = "ipsec-vpnd.ipsec.enabled" ] && {
	[ "${TEST_ENABLED:-1}" = "1" ] && { echo 1; exit 0; }
	exit 1
}
exit 1
EOF
chmod 0755 "$TMP/bin/uci"

cat > "$TMP/bin/logger" <<EOF
#!/bin/sh
echo "\$*" >> "$TMP/log"
exit 0
EOF
chmod 0755 "$TMP/bin/logger"

sed -e "s|/lib/functions/network.sh|$TMP/lib/network.sh|g" \
    -e "s|/etc/init.d/ipsec|$TMP/init/ipsec|g" \
    -e "s|/tmp/.ipsec-vpnd-wan-ip|$TMP/wan-ip|g" \
    "$HOTPLUG" > "$TMP/hotplug"
chmod 0755 "$TMP/hotplug"
PATH="$TMP/bin:$PATH"
export PATH

run() {
	# run <action> <interface> <ip> [enabled]
	: > "$TMP/restarts"; : > "$TMP/log"
	printf '%s\n' "$3" > "$TMP/ip"
	TEST_ENABLED="${4:-1}" ACTION="$1" INTERFACE="$2" "$TMP/hotplug"
	echo "$(wc -l < "$TMP/restarts" | tr -d ' ')"
}

check "首次 ifup 只记录地址、不重启" "0" "$(run ifup wan 1.1.1.1)"
check "首次记录写入状态文件" "1.1.1.1" "$(cat "$TMP/wan-ip")"

check "同一地址再次 ifup 不重启" "0" "$(run ifup wan 1.1.1.1)"
check "地址变化时重启一次" "1" "$(run ifup wan 2.2.2.2)"
check "地址变化写入日志" "1" "$(grep -c 'WAN 地址变化' "$TMP/log")"
check "变化后状态文件更新" "2.2.2.2" "$(cat "$TMP/wan-ip")"

printf '%s\n' "2.2.2.2" > "$TMP/wan-ip"
check "非 WAN 接口不动作" "0" "$(run ifup lan 3.3.3.3)"
check "WAN 地址变化但服务未启用：不重启" "0" "$(run ifup wan 4.4.4.4 0)"
check "action=ifdown 不动作" "0" "$(run ifdown wan 5.5.5.5)"

if [ "$fail" -eq 0 ]; then
	echo "hotplug-test: 全部通过"
	exit 0
fi
echo "hotplug-test: 有失败项"
exit 1
