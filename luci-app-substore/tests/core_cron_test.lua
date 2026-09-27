-- core_cron_test.lua — 按订阅定时更新（cron）单元测试
-- 用法：lua5.1 tests/core_cron_test.lua

package.path = "./root/usr/share/?.lua;" .. package.path

local core = require("substore.core")
local util = require("substore.util")

local passed, failed = 0, 0
local function check(name, cond)
	if cond then passed = passed + 1; print("PASS " .. name)
	else failed = failed + 1; print("FAIL " .. name) end
end

-- 重定向数据目录与 cron 文件到临时目录，避免污染系统
local tmp = os.tmpname() .. "_substore_cron"
os.execute("mkdir -p " .. string.format("%q", tmp .. "/nodes"))
core.DATA_DIR = tmp
core.LIST_FILE = tmp .. "/subscriptions.json"
core.NODES_DIR = tmp .. "/nodes"
core.CRON_FILE = tmp .. "/cron.d.substore"

-- ---------- cron_time_valid ----------
check("valid cron", core.cron_time_valid("0 3 * * *"))
check("valid all wildcard", core.cron_time_valid("* * * * *"))
check("valid single digit", core.cron_time_valid("30 4 1 12 6"))
check("invalid too many fields", not core.cron_time_valid("0 3 * * * extra"))
check("invalid too few fields", not core.cron_time_valid("0 3 * *"))
check("invalid empty", not core.cron_time_valid(""))
check("invalid injection semicolon", not core.cron_time_valid("0 3 * * *;rm -rf /"))
check("invalid injection pipe", not core.cron_time_valid("0 3 * * * | reboot"))
check("invalid non-digit", not core.cron_time_valid("0 3 * * abc"))

-- ---------- add 带 cron ----------
local id1 = core.add("带定时", "http://example.com/a", { cron_enable = "1", cron_time = "0 4 * * *" })
local m1 = core.get(id1)
check("add with cron enabled", m1.cron_enable == true and m1.cron_time == "0 4 * * *")

local id2 = core.add("无定时", "http://example.com/b")
local m2 = core.get(id2)
check("add default cron disabled", m2.cron_enable ~= true and m2.cron_time == "")

local id3 = core.add("无效定时", "http://example.com/c", { cron_enable = "1", cron_time = "0 0 * * ;evil" })
local m3 = core.get(id3)
check("add invalid cron sanitized", m3.cron_enable ~= true and m3.cron_time == "")

-- ---------- write_cron ----------
core.write_cron()
local raw = util.read_file(core.CRON_FILE) or ""
check("cron file has enabled sub", raw:find(id1, 1, true) ~= nil)
check("cron file excludes disabled", raw:find(id2, 1, true) == nil)
check("cron file has header comment", raw:find("# luci-app-substore cron", 1, true) ~= nil)

-- 全部关闭后：cron 文件应被移除
core.save_meta(id1, { cron_enable = "0" })
core.write_cron()
check("cron file removed when none enabled", util.read_file(core.CRON_FILE) == nil)

-- 清理
os.execute("rm -rf " .. string.format("%q", tmp))

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
