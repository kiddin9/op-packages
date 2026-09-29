#!/bin/sh
# cron_result_test.sh — 回归测试：substore-cron.sh 必须正确区分三层结果
#   (a) core.sync 抛异常
#   (b) core.sync 返回 nil, err  ← pcall 第一层仍为 true（修复前被统计成成功）
#   (c) core.sync 返回节点数（成功，含 0）
#
# 通过桩 core 模块 + SUBSTORE_DATA_DIR 覆盖驱动真实脚本，不依赖公网。
# 用法：sh tests/cron_result_test.sh

set -u

REPO=$(cd "$(dirname "$0")/.." && pwd)
# 允许指向别的副本，用于验证本测试确实能捕获修复前的行为
SCRIPT="${SUBSTORE_CRON_SCRIPT:-$REPO/root/usr/bin/substore-cron.sh}"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/stub/substore" "$TMP/data"
: > "$TMP/data/subscriptions.json"

pass=0
fail=0

check() {
	if [ "$2" = "$3" ]; then
		pass=$((pass + 1))
		echo "PASS $1"
	else
		fail=$((fail + 1))
		echo "FAIL $1 (want '$3', got '$2')"
	fi
}

contains() {
	case "$2" in
	*"$3"*) return 0 ;;
	*) return 1 ;;
	esac
}

run_case() {
	# $1 = M.sync 的 Lua 实现体
	cat >"$TMP/stub/substore/core.lua" <<EOF
local M = {}
M.list = function() return { { id = "s00000001", enabled = true } } end
M.sync = function(id) $1 end
return M
EOF
	SUBSTORE_DATA_DIR="$TMP/data" LUA_PATH="$TMP/stub/?.lua" \
		sh "$SCRIPT" 2>/dev/null
}

# (a) 抛异常 → 失败
OUT=$(run_case 'error("boom")' | tail -1)
check "exception counted as failure" "$OUT" "substore cron done: 0 ok, 1 failed"

# (b) 返回 nil, err → 失败（这是修复的核心：pcall 第一层为 true）
OUT=$(run_case 'return nil, "下载失败"' | tail -1)
check "nil,err counted as failure" "$OUT" "substore cron done: 0 ok, 1 failed"

# (b2) 失败原因必须被打印出来
OUT=$(run_case 'return nil, "下载失败"')
if contains "failure reason surfaced" "$OUT" "下载失败"; then
	pass=$((pass + 1))
	echo "PASS failure reason surfaced"
else
	fail=$((fail + 1))
	echo "FAIL failure reason surfaced"
fi

# (c) 成功返回节点数 → 成功
OUT=$(run_case 'return 3' | tail -1)
check "node count counted as success" "$OUT" "substore cron done: 1 ok, 0 failed"

# (c2) 成功但 0 节点 → 仍然是成功（0 在 Lua 中为真）
OUT=$(run_case 'return 0' | tail -1)
check "zero nodes still success" "$OUT" "substore cron done: 1 ok, 0 failed"

echo ""
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
