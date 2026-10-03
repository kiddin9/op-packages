-- rules_fields_test.lua — 订阅规则的「协议筛选 / 重命名」字段必须端到端可达
-- 用法：lua5.1 tests/rules_fields_test.lua
--
-- 覆盖 M30：`proto_filter_*` 与 `rename_map` 被控制器读取并落盘，但三个表单
-- （form.htm / local_form.htm / combo.htm）都没有提交它们的控件 ——
--   1. UI 不可达：用户永远无法设置这两项；
--   2. **静默数据丢失**：控制器每次都把 formvalue 的 nil 落成 ""，
--      于是通过 UCI 手工设过的值在下一次保存时被抹掉。
--
-- .htm 需要 LuCI 运行时才能渲染，lua5.1 跑不了模板，因此这里分两层：
--   * 静态检查：模板确实提交了这两个字段，且协议清单与控制器同源；
--   * 行为检查：用同一份 RULE_PROTOS 复刻控制器的收集逻辑，
--     验证它生成的 proto_filter 真的能被 node.apply_rules 用上。

package.path = "./root/usr/share/?.lua;" .. package.path

local util = require("substore.util")
local core = require("substore.core")
local node = require("substore.node")

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

local TEMPLATES = {
	"root/usr/lib/lua/luci/view/substore/form.htm",
	"root/usr/lib/lua/luci/view/substore/local_form.htm",
	"root/usr/lib/lua/luci/view/substore/combo.htm",
}
local CONTROLLER = "root/usr/lib/lua/luci/controller/admin/substore.lua"

-- ---------- RULE_PROTOS 本身 ----------
check("RULE_PROTOS is a table", type(core.RULE_PROTOS) == "table")
check("RULE_PROTOS non-empty", #core.RULE_PROTOS > 0)

local seen, dup = {}, nil
for _, p in ipairs(core.RULE_PROTOS) do
	if seen[p] then dup = p end
	seen[p] = true
end
check("RULE_PROTOS has no duplicate" .. (dup and (" (" .. dup .. ")") or ""), dup == nil)

-- 名字必须是 node.normalize 产出的**规范**协议名，否则 proto_filter 匹配不到任何
-- 节点（node.apply_rules 用 set[n.proto] 精确比对），症状是「勾了没用」。
local bad = {}
for _, p in ipairs(core.RULE_PROTOS) do
	local n = node.normalize({ proto = p, server = "1.2.3.4", port = 443 })
	if n.proto ~= p then bad[#bad + 1] = p .. "->" .. tostring(n.proto) end
end
check("RULE_PROTOS are canonical proto names" .. (#bad > 0 and (" (" .. table.concat(bad, ",") .. ")") or ""),
	#bad == 0)

-- socks5 是解析阶段的归一目标（parser 把它写成 socks），勾选框里不该出现 socks5
check("RULE_PROTOS has no socks5 alias", seen["socks5"] == nil)
check("RULE_PROTOS has socks", seen["socks"] == true)

-- ---------- 静态：三个模板都必须提交这两个字段 ----------
for _, path in ipairs(TEMPLATES) do
	local src = util.read_file(path)
	local name = path:match("[^/]+$")
	check(name .. " readable", src ~= nil)
	src = src or ""
	check(name .. " submits rename_map", src:find('name="rename_map"', 1, true) ~= nil)
	check(name .. " submits proto_filter_*", src:find('name="proto_filter_', 1, true) ~= nil)
	-- 协议清单必须来自 core.RULE_PROTOS，模板里不得再抄一份
	check(name .. " iterates core.RULE_PROTOS",
		src:find("ipairs(core.RULE_PROTOS)", 1, true) ~= nil)
	-- 已有值必须回填，否则打开编辑页看不到当前设置，一保存就被覆盖
	check(name .. " preloads proto_filter", src:find("proto_sel", 1, true) ~= nil)
	check(name .. " preloads rename_map", src:find("local rm =", 1, true) ~= nil)
end

-- ---------- 静态：协议复选框不得嵌在 <label> 里 ----------
-- Argon 主题有一条 `label > input[type="checkbox"] { position:relative; top:0.4rem }`，
-- 把复选框视觉下移 0.4rem（6.4px）却**不改变布局占位** —— 复选框于是探出所在行，
-- 压到下一行（症状：协议筛选的复选框底部盖住「重命名」输入框；原生 bootstrap 无此规则，
-- 所以只在 Argon 下复现）。改用 for/id 关联，让 input 不再是 label 的子元素即可绕开；
-- 外面套 <span style="white-space:nowrap"> 分组，避免复选框与协议名被折行拆散。
for _, path in ipairs(TEMPLATES) do
	local src = util.read_file(path) or ""
	local name = path:match("[^/]+$")
	local blk = src:match("ipairs%(core%.RULE_PROTOS%)%s*do(.-)<%% end %%>") or ""
	check(name .. " proto block extractable", blk ~= "")
	check(name .. " proto checkbox not nested in <label>", blk:find("<label[^>]*>%s*<input") == nil)
	check(name .. " proto checkbox associated by for/id",
		blk:find('id="pf_', 1, true) ~= nil and blk:find('for="pf_', 1, true) ~= nil)
end

-- ---------- 静态：控制器不再自己抄一份协议清单 ----------
local ctl = util.read_file(CONTROLLER) or ""
check("controller uses core.RULE_PROTOS", ctl:find("RULE_PROTOS", 1, true) ~= nil)
-- 旧的硬编码写法：ipairs({"vmess","vless",...})
check("controller has no hardcoded proto list",
	ctl:find('ipairs({"vmess"', 1, true) == nil)

-- ---------- 行为：复刻控制器的收集逻辑，验证它真的能过滤 ----------
-- 与 controller 的 read_rules_fields 保持一致：按 RULE_PROTOS 顺序遍历，
-- 表单里出现即为勾选（未勾选的 checkbox 浏览器不会提交）。
local function collect_proto_filter(form)
	local list = {}
	for _, p in ipairs(core.RULE_PROTOS) do
		if form["proto_filter_" .. p] then list[#list + 1] = p end
	end
	return table.concat(list, ",")
end

check("no checkbox ticked -> empty filter", collect_proto_filter({}) == "")
check("ticked protocols -> csv in RULE_PROTOS order",
	collect_proto_filter({ proto_filter_vmess = "1", proto_filter_trojan = "1" }) == "vmess,trojan")

-- 空串 = 不筛选（node.apply_rules 只在非空时过滤）
local all_nodes = {
	node.normalize({ proto = "vmess", server = "1.1.1.1", port = 443, uuid = "a" }),
	node.normalize({ proto = "trojan", server = "2.2.2.2", port = 443, password = "p" }),
	node.normalize({ proto = "hysteria2", server = "3.3.3.3", port = 443, password = "p" }),
}
local kept_all = node.apply_rules(all_nodes, { proto_filter = collect_proto_filter({}) })
check("empty filter keeps everything", #kept_all == 3)

local kept = node.apply_rules(all_nodes, {
	proto_filter = collect_proto_filter({ proto_filter_trojan = "1" }),
})
check("filter keeps only ticked protocol", #kept == 1 and kept[1].proto == "trojan")

-- 每一个可选协议都必须真的能选中它自己（清单写错时这里会失败）
for _, p in ipairs(core.RULE_PROTOS) do
	local n = node.normalize({ proto = p, server = "9.9.9.9", port = 443,
		uuid = "u", password = "p", ["public-key"] = "k" })
	local f = collect_proto_filter({ ["proto_filter_" .. p] = "1" })
	local r = node.apply_rules({ n }, { proto_filter = f })
	check("filter selects " .. p, #r == 1)
end

-- ---------- 行为：rename_map 经控制器落盘后确实生效 ----------
local renamed = node.apply_rules(
	{ node.normalize({ proto = "trojan", server = "1.2.3.4", port = 443,
		password = "p", name = "OldName" }) },
	{ rename_map = "OldName=NewName" })
check("rename_map applies", renamed[1].name == "NewName")

-- 未设置 rename_map（控制器此前会把它写成 ""）时不得改动名字
local untouched = node.apply_rules(
	{ node.normalize({ proto = "trojan", server = "1.2.3.4", port = 443,
		password = "p", name = "OldName" }) },
	{ rename_map = "" })
check("empty rename_map leaves names alone", untouched[1].name == "OldName")

-- ---------- 结果 ----------
print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
