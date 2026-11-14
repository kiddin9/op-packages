#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
#
# rpcd 后端 ipsec-vpnd 的解析逻辑回归测试。
#
# 后端里有两段 awk：
#   parse_statusall()  —— 把 `ipsec statusall` 解析成 TSV
#   sessions() 里的合并 awk —— 合并历史与在线行、输出 JSON、裁剪历史
# 这里把这两段从脚本里抽出来，喂合成数据，验证：
#   1. P1-1 控制字符用户名被清洗（不会把 TSV 行撕开、字段错位）
#   2. P1-1 旧版本被污染的脏行（字段数不对）被丢弃
#   3. P1-3 在线但没有地址时输出 vip_pending 标记
#   4. P1-6 历史上限 200 条，超出的被淘汰
#
# 用法：sh tests/sessions-parse-test.sh [rpcd 脚本路径]

set -u

RPCD="${1:-root/usr/libexec/rpcd/ipsec-vpnd}"
# 在设备上跑时仓库路径不存在，退回安装后的路径
[ -f "$RPCD" ] || RPCD="/usr/libexec/rpcd/ipsec-vpnd"
[ -f "$RPCD" ] || { echo "找不到 rpcd 脚本: $RPCD"; exit 1; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sessions-test.XXXXXX")"
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

# --- 抽出 parse_statusall() ------------------------------------------------
# 用 grep 定位行号再 sed 取区间，避免在 awk 里写带引号的正则
fn_start="$(grep -n '^parse_statusall() {' "$RPCD" | head -1 | cut -d: -f1)"
fn_end="$(grep -nFx "}'" "$RPCD" | cut -d: -f1 | awk -v s="$fn_start" '$1 > s { print $1; exit }')"
sed -n "${fn_start},$((fn_end + 1))p" "$RPCD" > "$TMP/fn.sh"
if ! grep -q '^parse_statusall() {' "$TMP/fn.sh"; then
	echo "FAIL - 没能从 rpcd 脚本里抽出 parse_statusall()"
	exit 1
fi
. "$TMP/fn.sh"

# --- 抽出 sessions() 里的合并 awk -------------------------------------------
awk '
	/-v state="/ && /awk -F/ {g=1}
	g{print}
	g && /\$online_tmp"/ {exit}
' "$RPCD" > "$TMP/merge.sh"
if ! grep -q "awk -F" "$TMP/merge.sh"; then
	echo "FAIL - 没能从 rpcd 脚本里抽出合并用的 awk"
	exit 1
fi

# --- 1. 控制字符用户名被清洗 ------------------------------------------------
# 用户名 "ev<TAB>il" 由客户端完全可控，不清洗的话 TSV 行会被撕成两段。
TAB="$(printf '\t')"
STATUS="xauth_psk[3]: ESTABLISHED 10 seconds ago, 192.168.1.139[192.168.1.139]...203.0.113.9[203.0.113.9]
   xauth_psk[3]: Remote XAuth identity: ev${TAB}il
   xauth_psk{1}:   192.168.1.139/32 === 10.9.8.10/32"

out="$(printf '%s\n' "$STATUS" | parse_statusall)"
check "控制字符用户名被清洗" "evil|203.0.113.9	evil	203.0.113.9	10.9.8.10	10 seconds" "$out"
check "清洗后仍是 5 个字段（key/user/remote/vip/age）" "5" "$(printf '%s\n' "$out" | awk -F'\t' '{print NF}')"

# --- 2. IKE ID 与 XAuth 用户名相同（无 identity 行）时用 IKE ID 兜底 -------
STATUS2="xauth_psk[3]: ESTABLISHED 5 seconds ago, 192.168.1.139[192.168.1.139]...203.0.113.9[alice]
   xauth_psk{1}:   192.168.1.139/32 === 10.9.8.10/32"
out2="$(printf '%s\n' "$STATUS2" | parse_statusall)"
check "缺 identity 行时用远端 IKE ID 兜底" "alice|203.0.113.9	alice	203.0.113.9	10.9.8.10	5 seconds" "$out2"

# --- 3. 合并 awk：脏行丢弃 + vip_pending + 历史上限 ------------------------
now=1000000
STATE_FILE="$TMP/state"
SESSIONS_TMP="$TMP/state.new"
online_tmp="$TMP/online"

# 历史文件里塞一行被污染的脏行（字段数 7，不是一行合法记录）
{
	printf 'good|10.0.0.1\tgood\t10.0.0.1\t10.9.8.10\t10 seconds\t100\n'
	printf 'ev\til|10.0.0.2\tev\til\t10.0.0.2\t100\t100\n'
	printf 'bad|10.0.0.3\tbad\t10.0.0.3\t10.9.8.11\t20 seconds\t200\n'
} > "$STATE_FILE"

# 在线行：一个有地址，一个在线但没地址（CHILD_SA 还没装上）
{
	printf 'good|10.0.0.1\tgood\t10.0.0.1\t10.9.8.10\t10 seconds\n'
	printf 'pending|10.0.0.9\tpending\t10.0.0.9\t\t3 seconds\n'
} > "$online_tmp"

now=2000000
STATE_FILE="$STATE_FILE" SESSIONS_TMP="$SESSIONS_TMP" online_tmp="$online_tmp" now="$now" \
	. "$TMP/merge.sh" > "$TMP/json"

json="$(cat "$TMP/json")"
check "脏行被丢弃" "0" "$(printf '%s\n' "$json" | grep -c '"user":"ev"')"
check "合法历史行仍在" "1" "$(printf '%s\n' "$json" | grep -c '"user":"bad"')"
check "vip_pending 标记存在" "1" "$(printf '%s\n' "$json" | grep -c '"vip_pending":true')"
check "有地址的在线行不带 vip_pending" "1" "$(printf '%s\n' "$json" | grep -c '"vip":"10.9.8.10"')"

# --- 4. 历史上限 200 --------------------------------------------------------
: > "$STATE_FILE"
i=1
while [ "$i" -le 250 ]; do
	printf 'u%s|10.1.0.1\tu%s\t10.1.0.1\t10.9.8.20\t1 seconds\t%s\n' "$i" "$i" "$i" >> "$STATE_FILE"
	i=$((i + 1))
done
: > "$online_tmp"
now=3000000
STATE_FILE="$STATE_FILE" SESSIONS_TMP="$SESSIONS_TMP" online_tmp="$online_tmp" now="$now" \
	. "$TMP/merge.sh" > "$TMP/json"

check "返回条数被限制到 200" "200" "$(printf '%s\n' "$(cat "$TMP/json")" | grep -o '"user"' | wc -l | tr -d ' ')"
check "落盘的历史也被限制到 200" "200" "$(wc -l < "$SESSIONS_TMP" | tr -d ' ')"

if [ "$fail" -eq 0 ]; then
	echo "sessions-parse-test: 全部通过"
	exit 0
fi
echo "sessions-parse-test: 有失败项"
exit 1
