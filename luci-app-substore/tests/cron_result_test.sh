#!/bin/sh
# cron_result_test.sh — 回归测试：substore-cron.sh 必须正确区分三层结果
#   (a) core.sync 抛异常
#   (b) core.sync 返回 nil, err  ← pcall 第一层仍为 true（修复前被统计成成功）
#   (c) core.sync 返回节点数（成功，含 0）
# 以及退出码必须反映本轮结果（有失败 → 非 0），供 cron MAILTO / 外部监控判断。
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

OUT=""
RC=0

run_case() {
	# $1 = M.sync 的 Lua 实现体
	cat >"$TMP/stub/substore/core.lua" <<EOF
local M = {}
M.list = function() return { { id = "s00000001", enabled = true } } end
M.sync = function(id) $1 end
return M
EOF
	OUT=$(SUBSTORE_DATA_DIR="$TMP/data" LUA_PATH="$TMP/stub/?.lua" \
		sh "$SCRIPT" 2>/dev/null)
	RC=$?
}

last_line() { printf '%s\n' "$OUT" | tail -1; }

# (a) 抛异常 → 失败
run_case 'error("boom")'
check "exception counted as failure" "$(last_line)" "substore cron done: 0 ok, 1 failed"
check "exception yields non-zero exit" "$RC" "1"

# (b) 返回 nil, err → 失败（这是修复的核心：pcall 第一层为 true）
run_case 'return nil, "下载失败"'
check "nil,err counted as failure" "$(last_line)" "substore cron done: 0 ok, 1 failed"
check "nil,err yields non-zero exit" "$RC" "1"

# (b2) 失败原因必须被打印出来
if contains "failure reason surfaced" "$OUT" "下载失败"; then
	pass=$((pass + 1))
	echo "PASS failure reason surfaced"
else
	fail=$((fail + 1))
	echo "FAIL failure reason surfaced"
fi

# (c) 成功返回节点数 → 成功
run_case 'return 3'
check "node count counted as success" "$(last_line)" "substore cron done: 1 ok, 0 failed"
check "success yields zero exit" "$RC" "0"

# (c2) 成功但 0 节点 → 仍然是成功（0 在 Lua 中为真）
run_case 'return 0'
check "zero nodes still success" "$(last_line)" "substore cron done: 1 ok, 0 failed"
check "zero nodes yields zero exit" "$RC" "0"

# (d) 缺少 lua 解释器 → 必须非 0（整条链路不可用，不能静默成功）
#     用空 PATH 让 command -v 找不到任何解释器。注意此时连 sh 本身都无法按名
#     解析，必须用绝对路径调用，否则拿到的是「找不到 sh」的 127 而非脚本退出码。
#     logger 也一并消失，脚本对 logger 已做 command -v 保护，不会因此报错。
mkdir -p "$TMP/emptybin"
OUT=$(SUBSTORE_DATA_DIR="$TMP/data" PATH="$TMP/emptybin" /bin/sh "$SCRIPT" 2>/dev/null)
RC=$?
check "missing interpreter yields non-zero exit" "$RC" "1"

# (e) 订阅文件不存在 → 无事可做，仍是 0
OUT=$(SUBSTORE_DATA_DIR="$TMP/nodata" LUA_PATH="$TMP/stub/?.lua" sh "$SCRIPT" 2>/dev/null)
RC=$?
check "no subscriptions file yields zero exit" "$RC" "0"

# (f) Lua 层致命失败 → 必须非 0
#     core.list() 在 pcall **之外**调用，抛异常会让整个 Lua 进程带着 traceback
#     退出，结果行根本没被打印。此时 FAILED 变量为空 —— 旧实现的 case 分支
#     `''|0) exit 0` 把它和成功混为一谈，一次彻底失败的更新在 cron 看来与成功
#     无异。这里必须与 (c) 的「0 failed」严格区分开。
cat >"$TMP/stub/substore/core.lua" <<'EOF'
local M = {}
M.list = function() error("list exploded") end
M.sync = function(id) return 1 end
return M
EOF
# 这里刻意把 stderr 一并收进 OUT：诊断信息就写在 stderr 上
OUT=$(SUBSTORE_DATA_DIR="$TMP/data" LUA_PATH="$TMP/stub/?.lua" sh "$SCRIPT" 2>&1)
RC=$?
check "lua fatal error yields non-zero exit" "$RC" "1"
if contains "no result line reported" "$OUT" "no result line"; then
	pass=$((pass + 1))
	echo "PASS no result line reported"
else
	fail=$((fail + 1))
	echo "FAIL no result line reported"
fi

# (f2) 模块加载失败（require 不到）同样是致命失败
cat >"$TMP/stub/substore/core.lua" <<'EOF'
this is not valid lua ((
EOF
OUT=$(SUBSTORE_DATA_DIR="$TMP/data" LUA_PATH="$TMP/stub/?.lua" sh "$SCRIPT" 2>/dev/null)
RC=$?
check "module load failure yields non-zero exit" "$RC" "1"

echo ""
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
