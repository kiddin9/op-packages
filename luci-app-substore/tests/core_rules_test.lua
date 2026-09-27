-- core_rules_test.lua — 订阅级规则单元测试
-- 用法：lua5.1 tests/core_rules_test.lua

package.path = "./root/usr/share/?.lua;" .. package.path

local core = require("substore.core")
local util = require("substore.util")

local passed, failed = 0, 0
local function check(name, cond)
	if cond then passed = passed + 1; print("PASS " .. name)
	else failed = failed + 1; print("FAIL " .. name) end
end

-- 重定向数据目录与 cron 文件到临时目录，避免污染系统
local tmp = os.tmpname() .. "_substore_rules"
os.execute("mkdir -p " .. string.format("%q", tmp .. "/nodes"))
core.DATA_DIR = tmp
core.LIST_FILE = tmp .. "/subscriptions.json"
core.NODES_DIR = tmp .. "/nodes"
core.CRON_FILE = tmp .. "/cron.d.substore"

local nodes = {
	{ name = "HK-vmess",     proto = "vmess",  server = "1.1.1.1", port = 443 },
	{ name = "US-vless",     proto = "vless",  server = "2.2.2.2", port = 443 },
	{ name = "HK-trojan",    proto = "trojan", server = "3.3.3.3", port = 443 },
	{ name = "HK-vmess-dup", proto = "vmess",  server = "1.1.1.1", port = 443 },
}

-- ---------- add 存储规则字段 ----------
local id = core.add("规则订阅", "http://example.com/r", {
	rules_enable = "1", proto_filter = "vmess,vless",
	keyword_include = "HK", keyword_exclude = "US",
	dedup = "1", rename_map = "HK-vmess=香港节点",
})
local m = core.get(id)
check("add stores rules_enable", m.rules_enable == true)
check("add stores proto_filter", m.proto_filter == "vmess,vless")
check("add stores keyword_include", m.keyword_include == "HK")
check("add stores dedup", m.dedup == "1")

-- ---------- apply_rules 禁用时不变 ----------
local r0 = core.apply_rules(nodes, { rules_enable = "0" })
check("disabled returns unchanged", #r0 == #nodes)

-- ---------- apply_rules 协议过滤 ----------
local r1 = core.apply_rules(nodes, { rules_enable = "1", proto_filter = "vmess" })
check("proto_filter keeps only vmess", #r1 == 2)

-- ---------- 关键词包含 / 排除 ----------
local r2 = core.apply_rules(nodes, { rules_enable = "1", keyword_include = "HK" })
check("keyword_include HK", #r2 == 3)
local r3 = core.apply_rules(nodes, { rules_enable = "1", keyword_exclude = "US" })
check("keyword_exclude US", #r3 == 3)

-- ---------- 多关键词（逗号分隔）----------
local rm1 = core.apply_rules(nodes, { rules_enable = "1", keyword_include = "HK,trojan" })
check("multi keyword_include HK,trojan", #rm1 == 3)
local rm2 = core.apply_rules(nodes, { rules_enable = "1", keyword_exclude = "US,vless" })
check("multi keyword_exclude US,vless", #rm2 == 3)
local rm3 = core.apply_rules(nodes, { rules_enable = "1", keyword_include = "HK，trojan" })
check("multi keyword Chinese comma", #rm3 == 3)

-- ---------- 去重 ----------
local r4 = core.apply_rules(nodes, { rules_enable = "1", dedup = "1" })
check("dedup removes duplicate", #r4 == 3)

-- ---------- 重命名 ----------
local r5 = core.apply_rules(nodes, { rules_enable = "1", rename_map = "HK-vmess=香港节点" })
local renamed = false
for _, n in ipairs(r5) do if n.name == "香港节点" then renamed = true end end
check("rename_map applies", renamed)

-- ---------- 组合规则 ----------
local r6 = core.apply_rules(nodes, { rules_enable = "1", proto_filter = "vmess", dedup = "1", keyword_include = "HK" })
check("combined filter+dedup+keyword", #r6 == 1)

-- 清理
os.execute("rm -rf " .. string.format("%q", tmp))

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
