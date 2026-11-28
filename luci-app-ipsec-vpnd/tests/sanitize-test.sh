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

# 长度上限：XAuth 用户名由客户端可控，不限长会撑大 /etc 状态文件与 JSON 响应。
# 默认 64；SANITIZE_MAXLEN 可覆盖。
LONG="$(awk 'BEGIN { s = ""; for (i = 0; i < 200; i++) s = s "A"; print s }')"
check "超长输入被截断到 64" "64" "$(printf '%s' "$LONG" | sh "$SAN" | wc -c | tr -d ' ')"
check "恰好 64 字符不被截断" "64" \
	"$(printf '%s' "$(printf '%s' "$LONG" | cut -c 1-64)" | sh "$SAN" | wc -c | tr -d ' ')"
check "不足 64 字符原样保留" "shortuser" "$(printf '%s' 'shortuser' | sh "$SAN")"
check "SANITIZE_MAXLEN 可覆盖上限" "16" \
	"$(printf '%s' "$LONG" | SANITIZE_MAXLEN=16 sh "$SAN" | wc -c | tr -d ' ')"
# 截断是字节语义（head -c），不是字符语义：busybox 的 cut/awk 按字节、
# macOS/BSD 的按字符，用 head -c 才能让测试与目标机行为一致。
# 多字节被切成半个字节序列不影响功能：该值只作为不透明字节串进出 TSV/JSON。
check "截断按字节计（6 个汉字 18 字节，上限 9 得 9 字节）" "9" \
	"$(printf '%s' '用户名测试' | SANITIZE_MAXLEN=9 sh "$SAN" | wc -c | tr -d ' ')"

if [ "$fail" -eq 0 ]; then
	echo "sanitize-test: 全部通过"
	exit 0
fi
echo "sanitize-test: 有失败项"
exit 1
