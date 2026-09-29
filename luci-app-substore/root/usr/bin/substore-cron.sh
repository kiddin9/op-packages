#!/bin/sh
# substore cron job — 按订阅定时更新
# 用法：substore-cron.sh [订阅ID]（不传则更新全部已启用订阅）
# 注意：显式设置 package.path，确保独立 cron 进程能找到 /usr/lib/lua 下的模块

# 数据目录可被环境变量覆盖，仅用于测试；生产环境仍为 /etc/substore
DATA_DIR="${SUBSTORE_DATA_DIR:-/etc/substore}"
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
OUT=$(
LUA_PATH="/usr/lib/lua/?.lua;/usr/share/lua/?.lua;${LUA_PATH:-}" \
"$LUA_BIN" -e '
local core = require("substore.core")
local sub_id = os.getenv("SUB_ID")
local ok_count, fail_count = 0, 0

-- core.sync 失败时是「返回 nil, err」而非抛异常，因此 pcall 必须处理两层结果：
-- pcall 返回 true 只说明没有抛错，第二个返回值才是 sync 自身的结果。
-- 只判断第一层会把「sync 返回 nil, err」统计成成功。
local function sync_one(id)
	local ok, res, err = pcall(core.sync, id)
	if ok and res then
		ok_count = ok_count + 1
	else
		fail_count = fail_count + 1
		local reason = ok and err or res
		io.stderr:write("Failed sync " .. tostring(id) .. ": " .. tostring(reason) .. "\n")
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
' 2>&1
)

# 输出到 stdout（cron 会按需邮件/记录），同时写 syslog
printf '%s\n' "$OUT"
if command -v logger >/dev/null 2>&1; then
	printf '%s\n' "$OUT" | logger -t luci-app-substore
fi
exit 0
