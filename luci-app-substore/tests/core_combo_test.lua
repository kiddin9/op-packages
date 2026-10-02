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

-- ---------- 删除源订阅：引用它的组合必须立刻重算（本轮修复） ----------
-- 此前只有 M.sync 与三个节点级控制器入口会调 refresh_combos，删除订阅这条路径
-- 漏了：组合的物化节点在 nodes/<combo>.json，只有 combo_refresh 会重写它，
-- 于是组合的下载链接会继续吐已删订阅的节点，直到别的源更新才被动纠正。
local srcD = core.add("订阅D", "http://example.com/d")
local srcE = core.add("订阅E", "http://example.com/e")
core.write_nodes(srcD, {
	{ proto = "vmess", name = "D-香港-01", server = "5.5.5.5", port = 443, uuid = "u5" },
	{ proto = "vmess", name = "D-美国-01", server = "6.6.6.6", port = 443, uuid = "u6" },
})
core.write_nodes(srcE, {
	{ proto = "vmess", name = "E-日本-01", server = "7.7.7.7", port = 443, uuid = "u7" },
})
local comboDE = core.add_combo("组合D+E", { srcD, srcE })
check("combo D+E node_count = 3", core.get(comboDE).node_count == 3)

check("remove source D returns true", core.remove(srcD) == true)

local deMeta = core.get(comboDE)
check("combo node_count drops right after source delete", deMeta.node_count == 1)
local deNodes = core.read_nodes(comboDE)
check("combo materialized nodes drop the deleted source", #deNodes == 1)
local leaked = false
for _, n in ipairs(deNodes) do
	if n.server == "5.5.5.5" or n.server == "6.6.6.6" then leaked = true end
end
check("no node from the deleted source survives", not leaked)

-- 死 id 必须从 sources 里摘掉，否则列表页「来源」列会显示裸 id
local deSrcs = deMeta.sources
local deadLeft = false
for _, s in ipairs(type(deSrcs) == "table" and deSrcs or {}) do
	if s == srcD then deadLeft = true end
end
check("deleted source pruned from combo sources",
	not deadLeft and type(deSrcs) == "table" and #deSrcs == 1 and deSrcs[1] == srcE)

-- 下载链接（真正被 Passwall / OpenClash 拉取的东西）也不该再有已删订阅的节点
local deToken = core.ensure_token(comboDE)
local deYaml = core.generate_link(deToken, "ClashMeta")
check("combo link drops the deleted source node",
	deYaml and deYaml:find("D-香港-01", 1, true) == nil)
check("combo link keeps the remaining source node",
	deYaml and deYaml:find("E-日本-01", 1, true) ~= nil)

-- 来源被删光：必须给出「请选择至少一个订阅」，而不是静默 0 节点
core.remove(srcE)
local deMeta2 = core.get(comboDE)
check("combo with all sources deleted reports an error",
	type(deMeta2.error) == "string" and deMeta2.error ~= "" and deMeta2.node_count == 0)
check("all-sources-deleted combo has empty sources",
	type(deMeta2.sources) == "table" and #deMeta2.sources == 0)

-- 删除一个只被某个组合引用的订阅：该组合被清空，其他组合不受影响
local srcF = core.add("订阅F", "http://example.com/f")
core.write_nodes(srcF, {
	{ proto = "vmess", name = "F-01", server = "8.8.8.8", port = 443, uuid = "u8" },
})
local comboF = core.add_combo("组合F", { srcF })
check("combo F node_count = 1", core.get(comboF).node_count == 1)
core.remove(srcF)
check("combo F emptied after its only source is deleted", core.get(comboF).node_count == 0)
-- c 的来源是 b（未被删除），不得被误伤
check("unrelated combo untouched", core.get(c).node_count == 1)

-- 清理
os.execute("rm -rf " .. string.format("%q", tmp))

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)