#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
#
# luci-ipsec-vpnd-sanitize 的回归测试。
#
# 这个小工具负责剥掉用户名里的控制字符。它必须在 busybox（OpenWrt 自带）
# 上正确工作：busybox 的 `tr` 不认 `[:cntrl:]` 字符类，会把字面字符删掉
# （实测 "testuser" 被删成 "esuse"），所以这里逐项验证。
#
# 用法：sh tests/sanitize-test.sh [脚本路径]

set -u

SAN="${1:-root/usr/lib/ipsec/luci-ipsec-vpnd-sanitize}"
# 在设备上跑时仓库路径不存在，退回安装后的路径
[ -f "$SAN" ] || SAN="/usr/lib/ipsec/luci-ipsec-vpnd-sanitize"
[ -f "$SAN" ] || { echo "找不到脚本: $SAN"; exit 1; }

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

TAB="$(printf '\t')"
NL="$(printf '\n')"
CR="$(printf '\r')"

check "普通用户名原样保留" "testuser" "$(printf '%s' 'testuser' | sh "$SAN")"
check "制表符被剥掉" "evil" "$(printf '%s' "ev${TAB}il" | sh "$SAN")"
check "换行被剥掉" "evil" "$(printf '%s' "ev${NL}il" | sh "$SAN")"
check "回车被剥掉" "evil" "$(printf '%s' "ev${CR}il" | sh "$SAN")"
check "不能误删普通字母" "testuser" "$(printf '%s' 'testuser' | sh "$SAN")"
check "不能误删含 n/t/r/o/l 的名字" "notroll" "$(printf '%s' 'notroll' | sh "$SAN")"
check "多个控制字符一起剥掉" "abc" "$(printf '%s' "a${TAB}b${NL}c${CR}" | sh "$SAN")"
check "空输入输出为空" "" "$(printf '%s' '' | sh "$SAN")"

if [ "$fail" -eq 0 ]; then
	echo "sanitize-test: 全部通过"
	exit 0
fi
echo "sanitize-test: 有失败项"
exit 1
