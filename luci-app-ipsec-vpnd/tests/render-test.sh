#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
#
# luci-ipsec-vpnd-render 的离线回归测试。
#
# 渲染器把 /etc/config/ipsec-vpnd 翻译成 strongSwan 的 ipsec.conf / ipsec.secrets，
# 这里用一个临时根目录 + 假的 lib/functions.sh 桩件来跑它，不碰真实配置。
#
# 覆盖：
#   1. enabled=1 时生成 conn，rightsourceip/rightdns 与 UCI 一致
#   2. ipsec.secrets 权限 0600，且含 PSK 与 XAuth 两行
#   3. enabled=0 时不生成 conn，并清掉遗留的 ipsec.secrets
#   4. 依赖自检不通过时不生成任何文件、退出码非 0
#
# 用法：sh tests/render-test.sh [渲染器路径]

set -u

RENDER="${1:-root/usr/lib/ipsec/luci-ipsec-vpnd-render}"
# 在设备上跑时仓库路径不存在，退回安装后的路径
[ -f "$RENDER" ] || RENDER="/usr/lib/ipsec/luci-ipsec-vpnd-render"
[ -f "$RENDER" ] || { echo "找不到渲染器: $RENDER"; exit 1; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/render-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

fail=0
check() {
	# check <名称> <期望> <实际>
	if [ "$2" = "$3" ]; then
		echo "ok   - $1"
	else
		echo "FAIL - $1"
		echo "       期望: [$2]"
		echo "       实际: [$3]"
		fail=1
	fi
}

count_matches() {
	# count_matches <正则> <文件>：匹配行数，文件不存在或无匹配都返回 0
	if [ -f "$2" ]; then
		grep -c "$1" "$2" 2>/dev/null | head -1
	else
		echo 0
	fi
}

file_mode() {
	# 跨平台取权限（macOS / Linux / busybox 的 stat 参数都不一样，统一走 ls -l）
	ls -l "$1" 2>/dev/null | awk '{
		p = substr($1, 2, 9)
		v = 0
		for (i = 1; i <= 3; i++) {
			d = 0
			c = substr(p, i * 3 - 2, 1); if (c == "r") d += 4
			c = substr(p, i * 3 - 1, 1); if (c == "w") d += 2
			c = substr(p, i * 3,     1); if (c == "x") d += 1
			v = v * 10 + d
		}
		print v
	}'
}

# --- 桩件环境 ---------------------------------------------------------------
mkdir -p "$TMP/lib" "$TMP/etc" "$TMP/bin" "$TMP/usr/lib/ipsec"

cat > "$TMP/lib/functions.sh" <<'EOF'
config_load() { :; }
config_get() {
	# config_get <var> <section> <option> <default>
	_v="$(sed -n "s/^$3=//p" "$TEST_UCI" 2>/dev/null | head -n1)"
	[ -n "$_v" ] || _v="$4"
	eval "$1=\$_v"
}
EOF

cat > "$TMP/bin/logger" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod 0755 "$TMP/bin/logger"
PATH="$TMP/bin:$PATH"
export PATH

# 渲染器里的绝对路径统统换成临时目录
sed -e "s|/etc/ipsec.conf|$TMP/etc/ipsec.conf|g" \
    -e "s|/etc/ipsec.secrets|$TMP/etc/ipsec.secrets|g" \
    -e "s|/usr/lib/ipsec/luci-ipsec-vpnd-deps|$TMP/usr/lib/ipsec/luci-ipsec-vpnd-deps|g" \
    "$RENDER" > "$TMP/render"
chmod 0755 "$TMP/render"

run_render() {
	TEST_UCI="$1" IPKG_INSTROOT="$TMP" "$TMP/render" >"$TMP/out" 2>&1
	echo $?
}

# --- 1. enabled=1 ----------------------------------------------------------
cat > "$TMP/uci" <<'EOF'
enabled=1
clientip=10.9.8.10/24
clientdns=10.9.8.1
account=acc1
password=pw1
secret=psk1
EOF

rc="$(run_render "$TMP/uci")"
check "enabled=1 时渲染成功" "0" "$rc"
check "生成 conn xauth_psk" "1" "$(count_matches '^conn xauth_psk$' "$TMP/etc/ipsec.conf")"
check "rightsourceip 取自 UCI" "1" "$(count_matches 'rightsourceip=10.9.8.10/24' "$TMP/etc/ipsec.conf")"
check "rightdns 取自 UCI" "1" "$(count_matches 'rightdns=10.9.8.1' "$TMP/etc/ipsec.conf")"
check "secrets 含 PSK" "1" "$(count_matches '^: PSK "psk1"$' "$TMP/etc/ipsec.secrets")"
check "secrets 含 XAuth" "1" "$(count_matches '^acc1 : XAUTH "pw1"$' "$TMP/etc/ipsec.secrets")"
check "secrets 权限 0600" "600" "$(file_mode "$TMP/etc/ipsec.secrets")"
check "首次渲染报告 changed" "changed" "$(cat "$TMP/out")"

# 幂等：同样的配置再渲染一次，报告 unchanged 且不改动文件
before="$(cksum "$TMP/etc/ipsec.conf")"
rc="$(run_render "$TMP/uci")"
check "重复渲染退出码 0" "0" "$rc"
check "重复渲染报告 unchanged" "unchanged" "$(cat "$TMP/out")"
check "重复渲染不改文件" "$before" "$(cksum "$TMP/etc/ipsec.conf")"

# --- 2. enabled=0 ----------------------------------------------------------
cat > "$TMP/uci" <<'EOF'
enabled=0
clientip=10.9.8.10/24
clientdns=10.9.8.1
account=acc1
password=pw1
secret=psk1
EOF

rc="$(run_render "$TMP/uci")"
check "enabled=0 时渲染成功" "0" "$rc"
check "enabled=0 时不生成 conn" "0" "$(count_matches '^conn xauth_psk$' "$TMP/etc/ipsec.conf")"
check "enabled=0 时清掉遗留 secrets" "0" "$([ -e "$TMP/etc/ipsec.secrets" ] && echo 1 || echo 0)"
check "enabled=0 时报告 changed" "changed" "$(cat "$TMP/out")"

# --- 3. 依赖自检不通过 -----------------------------------------------------
cat > "$TMP/uci" <<'EOF'
enabled=1
clientip=10.9.8.10/24
clientdns=10.9.8.1
account=acc1
password=pw1
secret=psk1
EOF

cat > "$TMP/usr/lib/ipsec/luci-ipsec-vpnd-deps" <<'EOF'
#!/bin/sh
[ "$1" = "files" ] && echo "starter|missing|/usr/lib/ipsec/starter"
exit 1
EOF
chmod 0755 "$TMP/usr/lib/ipsec/luci-ipsec-vpnd-deps"

rm -f "$TMP/etc/ipsec.conf" "$TMP/etc/ipsec.secrets"
rc="$(run_render "$TMP/uci")"
check "依赖缺失时退出码非 0" "1" "$([ "$rc" != "0" ] && echo 1 || echo 0)"
check "依赖缺失时不生成 ipsec.conf" "0" "$([ -e "$TMP/etc/ipsec.conf" ] && echo 1 || echo 0)"
check "依赖缺失时不生成 ipsec.secrets" "0" "$([ -e "$TMP/etc/ipsec.secrets" ] && echo 1 || echo 0)"

if [ "$fail" -eq 0 ]; then
	echo "render-test: 全部通过"
	exit 0
fi
echo "render-test: 有失败项"
exit 1
