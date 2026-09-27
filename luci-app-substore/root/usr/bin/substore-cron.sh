#!/bin/sh
# substore cron job — 按订阅定时更新
# 用法：substore-cron.sh [订阅ID]（不传则更新全部已启用订阅）
# 注意：显式设置 package.path，确保独立 cron 进程能找到 /usr/lib/lua 下的模块

DATA_DIR="/etc/substore"
LIST_FILE="$DATA_DIR/subscriptions.json"
SUB_ID="${1:-}"
LUA_BIN=""

for c in lua5.1 lua; do
	if command -v "$c" >/dev/null 2>&1; then
		LUA_BIN="$c"
		break
	fi
done

if [ -z "$LUA_BIN" ]; then
	logger -t luci-app-substore "cron: no lua interpreter found"
	exit 0
fi

[ -f "$LIST_FILE" ] || exit 0

export SUB_ID
LUA_PATH="/usr/lib/lua/?.lua;/usr/share/lua/?.lua;${LUA_PATH:-}" \
"$LUA_BIN" -e '
local core = require("substore.core")
local sub_id = os.getenv("SUB_ID")
local ok_count, fail_count = 0, 0

local function sync_one(id)
	local ok, err = pcall(function() return core.sync(id) end)
	if ok then
		ok_count = ok_count + 1
	else
		fail_count = fail_count + 1
		io.stderr:write("Failed sync " .. tostring(id) .. ": " .. tostring(err) .. "\n")
	end
end

if sub_id and sub_id ~= "" then
	sync_one(sub_id)
else
	for _, it in ipairs(core.list()) do
		if it.enabled then sync_one(it.id) end
	end
end
io.stdout:write(string.format("substore cron done: %d ok, %d failed\n", ok_count, fail_count))
' 2>&1 | logger -t luci-app-substore
