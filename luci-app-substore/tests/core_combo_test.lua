-- core_combo_test.lua — 组合订阅（选择性合并 + 组合订阅链接）单元测试
-- 用法：lua5.1 tests/core_combo_test.lua

package.path = "./root/usr/share/?.lua;" .. package.path

local core = require("substore.core")

local passed, failed = 0, 0

local function check(name, cond)
	if cond then
		passed = passed + 1
		print("PASS " .. name)
	else
		failed = failed + 1
		print("FAIL " .. name)
	end
end

-- 重定向数据目录到临时目录，避免污染系统
local tmp = os.tmpname() .. "_substore"
os.execute("mkdir -p " .. string.format("%q", tmp .. "/nodes"))
core.DATA_DIR = tmp
core.LIST_FILE = tmp .. "/subscriptions.json"
core.NODES_DIR = tmp .. "/nodes"

check("add_combo exists", type(core.add_combo) == "function")
check("combo_refresh exists", type(core.combo_refresh) == "function")
check("refresh_combos exists", type(core.refresh_combos) == "function")
check("save_combo exists", type(core.save_combo) == "function")

-- 建两个源订阅
local a = core.add("订阅A", "http://example.com/a")
local b = core.add("订阅B", "http://example.com/b")
check("source A added", a ~= nil)
check("source B added", b ~= nil)

core.write_nodes(a, {
	{ proto = "vmess", name = "A-香港-01", server = "1.1.1.1", port = 443, uuid = "u1" },
	{ proto = "vmess", name = "A-美国-01", server = "2.2.2.2", port = 443, uuid = "u2" },
})
core.write_nodes(b, {
	{ proto = "shadowsocks", name = "B-日本-01", server = "3.3.3.3", port = 8388, method = "aes-256-gcm", password = "p" },
})

-- 创建组合：合并 A+B
local c = core.add_combo("我的组合", { a, b })
check("add_combo returns id", c ~= nil)

local cmeta = core.get(c)
check("combo flag set", cmeta.combo == true)
check("combo has 2 sources", type(cmeta.sources) == "table" and #cmeta.sources == 2)
check("combo node_count = 3", cmeta.node_count == 3)

local cnodes = core.read_nodes(c)
check("combo read_nodes = 3", #cnodes == 3)

-- 组合 token → 生成订阅链接，含两源节点
local token = core.ensure_token(c)
local yaml, ct, filename = core.generate_link(token, "ClashMeta")
check("combo generate_link ok", type(yaml) == "string" and yaml ~= "")
check("combo clashmeta contains A node", yaml and yaml:find("A-香港-01", 1, true) ~= nil)
check("combo clashmeta contains B node", yaml and yaml:find("B-日本-01", 1, true) ~= nil)

-- 关键词规则：只保留香港
local c2 = core.add_combo("香港组合", { a }, { rules_enable = "1", keyword_include = "香港" })
check("combo with keyword include node_count = 1", core.get(c2).node_count == 1)

-- 去重：A 与 B 含同 server:port 节点
core.write_nodes(b, {
	{ proto = "vmess", name = "A-香港-01", server = "1.1.1.1", port = 443, uuid = "u1" },
})
core.refresh_combos(a)
core.refresh_combos(b)
local c3 = core.add_combo("去重组合", { a, b }, { rules_enable = "1", dedup = "1" })
check("combo with dedup removes dup", core.get(c3).node_count == 2)

-- 陈旧性：源 A 追加节点后，refresh_combos 使组合跟随更新
core.write_nodes(a, {
	{ proto = "vmess", name = "A-香港-01", server = "1.1.1.1", port = 443, uuid = "u1" },
	{ proto = "vmess", name = "A-美国-01", server = "2.2.2.2", port = 443, uuid = "u2" },
	{ proto = "vmess", name = "A-新增-01", server = "4.4.4.4", port = 443, uuid = "u3" },
})
core.refresh_combos(a)
check("combo follows source refresh", core.get(c).node_count == 4)

-- 编辑组合：改名称、改来源为仅 B
local cnt = core.save_combo(c, "改名组合", { b }, {})
check("save_combo returns count", cnt == 1)
check("combo renamed", core.get(c).name == "改名组合")
check("combo sources updated", #core.get(c).sources == 1 and core.get(c).sources[1] == b)

-- 空 sources 报错
local e, eerr = core.add_combo("空组合", {})
check("empty sources returns nil", e == nil)
check("empty sources err", eerr ~= nil)

-- 非法源 id 被忽略 → 视为空，报错
local e2 = core.add_combo("坏源", { "not-a-valid-id!!!" })
check("invalid source returns nil", e2 == nil)

-- 清理
os.execute("rm -rf " .. string.format("%q", tmp))

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)