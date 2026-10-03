-- subscriptions_combo_row_test.lua — 订阅列表页「组合订阅」行的显示
-- 用法：lua5.1 tests/subscriptions_combo_row_test.lua
--
-- 需求（用户提出）：
--   列表页里组合订阅原先把「[组合]」徽标放在**名称**列（显示成「[组合]Test123」），
--   来源订阅名放在「订阅地址」列。要求改为：
--     名称列只显示名称（Test123）；
--     「[组合]」徽标移到「订阅地址」列、放在来源列表之前（[组合] Fatiao + Feijiyundu），
--     与同一列里「[本地]」徽标的呈现方式一致。
--
-- 覆盖缺口：本文件新增前，渲染 subscriptions.htm 的三个测试
-- （subscriptions_format_gate_test / subscriptions_bulk_delete_test / view_i18n_test）
-- fixture 全是普通订阅 —— **组合行与本地行的渲染此前零覆盖**。
--
-- .htm 需要 LuCI 运行时才能渲染，本机没有。做法与 subscriptions_format_gate_test.lua
-- 相同：把模板按 LuCI 的方式重建成 Lua chunk（<% %> 里的代码原样，文本变 __w(...)），
-- 用替身环境**真的渲染一遍**，再对生成的 HTML 断言。这比「源码里有没有某个字符串」
-- 强：它同时验证了模板语法、分支条件与最终输出。

package.path = "./root/usr/share/?.lua;" .. package.path

local core = require("substore.core")

local passed, failed = 0, 0
local function check(name, cond)
	if cond then passed = passed + 1; print("PASS " .. name)
	else failed = failed + 1; print("FAIL " .. name) end
end

-- ---------- 数据目录改到 /tmp，绝不碰真实的 /etc/substore ----------
-- LIST_FILE / NODES_DIR 是 require 时算好的常量，必须一并改掉。
local TMPDIR = "/tmp/substore_comborow_" .. tostring(os.time()) .. "_" .. tostring(math.random(1e6))
os.execute("rm -rf " .. TMPDIR)
core.DATA_DIR = TMPDIR
core.LIST_FILE = TMPDIR .. "/subscriptions.json"
core.NODES_DIR = TMPDIR .. "/nodes"
core.ensure_dirs()

local VIEW = "root/usr/lib/lua/luci/view/substore/subscriptions.htm"

-- 与 tests/subscriptions_format_gate_test.lua 的 build_chunk 同构：
-- 字面 HTML 也要 __w 出来，否则标签属性（class / style）全丢，断言无从谈起。
local function build_chunk(src)
	local out = { "local __w = __substore_w" }
	local i, n = 1, #src
	while i <= n do
		local s = src:find("<%", i, true)
		if not s then
			out[#out + 1] = "__w(" .. string.format("%q", src:sub(i)) .. ")"
			break
		end
		if s > i then
			out[#out + 1] = "__w(" .. string.format("%q", src:sub(i, s - 1)) .. ")"
		end
		local e = src:find("%>", s + 2, true)
		if not e then return nil, "unclosed <% at " .. s end
		local tag = src:sub(s + 2, e - 1)
		local kind = tag:sub(1, 1)
		local body = tag:sub(2)
		if kind == "=" then
			out[#out + 1] = "__w(" .. body .. ")"
		elseif kind == ":" then
			out[#out + 1] = "__w(" .. string.format("%q", body) .. ")"
		elseif kind == "+" then
			out[#out + 1] = "__w()" -- header / footer 不参与断言
		else
			out[#out + 1] = tag
		end
		out[#out + 1] = "\n"
		i = e + 2
	end
	return table.concat(out, "\n")
end

-- ---------- LuCI 替身 ----------
local luci_stub = {
	util = {
		pcdata = function(s) return tostring(s or "") end,
		urlencode = function(s) return tostring(s or "") end,
	},
	i18n = { translate = function(s) return tostring(s or "") end },
	dispatcher = {
		context = { query = {} },
		build_url = function(...)
			return "/cgi-bin/luci/" .. table.concat({ ... }, "/")
		end,
	},
}
local http_stub = {
	formvalue = function() return nil end,
	getenv = function() return nil end,
}
local real_require = require
local function fake_require(name)
	if name == "luci.http" then return http_stub end
	if name == "luci.util" then return luci_stub.util end
	if name == "luci.i18n" then return luci_stub.i18n end
	return real_require(name)
end

local function render()
	local f = assert(io.open(VIEW, "rb"))
	local src = f:read("*a")
	f:close()
	local chunk, cerr = build_chunk(src)
	if not chunk then error(cerr) end
	local fn, lerr = loadstring(chunk, "subscriptions.htm")
	if not fn then error(lerr) end
	local buf = {}
	local env = setmetatable({
		__substore_w = function(s) if s ~= nil then buf[#buf + 1] = tostring(s) end end,
		require = fake_require,
		luci = luci_stub,
		token = "TESTTOKEN", -- LuCI 注入的 CSRF token
	}, { __index = _G })
	setfenv(fn, env)
	fn()
	return table.concat(buf)
end

-- 取某条订阅那一整行 <tr>…</tr>：以该订阅选择框的 value 定位，再向前找行首。
local function row_of(html, id)
	local at = html:find('<input type="checkbox" class="sub-check" value="' .. id .. '"/>', 1, true)
	if not at then return nil end
	local s, p = nil, html:find('<tr class="cbi-section-table-row">', 1, true)
	while p and p < at do
		s = p
		p = html:find('<tr class="cbi-section-table-row">', p + 1, true)
	end
	if not s then return nil end
	local e = html:find("</tr>", at, true) or #html
	return html:sub(s, e)
end

-- 单元格按出现顺序切分（单元格不嵌套，非贪婪匹配即可）：
--   1=选择框 2=名称 3=订阅地址 4=节点 5=更新 6=状态 7=订阅链接 8=操作
local function cells(row)
	local t = {}
	for c in row:gmatch("<td[^>]*>(.-)</td>") do t[#t + 1] = c end
	return t
end

local function trim(s)
	return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function count_of(html, pat)
	local n = 0
	for _ in html:gmatch(pat) do n = n + 1 end
	return n
end

-- ---------- fixture：两个来源订阅 + 一个组合 + 一个本地订阅 ----------
local idA = core.add("Fatiao", "http://example.com/a.yaml", {})
local idB = core.add("Feijiyundu", "http://example.com/b.yaml", {})
check("fixture: two source subscriptions", idA and idB and idA ~= idB)

local idC = core.add_combo("Test123", { idA, idB })
check("fixture: combo created", type(idC) == "string" and idC ~= "")

local idL = core.add_local("LocalOne", "trojan://p@example.com:443#N", "text")
check("fixture: local subscription created", type(idL) == "string" and idL ~= "")

local html = render()
check("template renders", #html > 0)

-- ---------- 1) 名称列只显示名称 ----------
local row_combo = row_of(html, idC) or ""
local c_combo = cells(row_combo)
check("combo row found with 8 cells", #c_combo == 8)

local name_cell = c_combo[2] or ""
local url_cell = c_combo[3] or ""

check("combo name cell shows only the name", trim(name_cell) == "Test123")
check("combo name cell has no Combination badge",
	name_cell:find("Combination", 1, true) == nil)
check("combo name cell has no bracket badge at all",
	name_cell:find("[", 1, true) == nil)

-- ---------- 2) 徽标移到「订阅地址」列，且在来源列表之前 ----------
check("combo url cell carries the [Combination] badge",
	url_cell:find("[Combination]", 1, true) ~= nil)
check("combo url cell lists the sources joined with +",
	url_cell:find("Fatiao + Feijiyundu", 1, true) ~= nil)

local pos_badge = url_cell:find("[Combination]", 1, true)
local pos_src = url_cell:find("Fatiao", 1, true)
check("badge sits before the source list",
	pos_badge ~= nil and pos_src ~= nil and pos_badge < pos_src)

-- ---------- 3) 徽标全页只出现一次（是「移走」而不是「复制一份」） ----------
check("badge appears exactly once in the page",
	count_of(html, "%[Combination%]") == 1)
check("control: count_of is not vacuous",
	count_of(html, "%[NoSuchBadge%]") == 0)

-- ---------- 4) 回归：普通订阅与本地订阅的渲染不受影响 ----------
local c_a = cells(row_of(html, idA) or "")
check("plain subscription name cell unchanged", trim(c_a[2] or "") == "Fatiao")
check("plain subscription url cell shows the url",
	(c_a[3] or ""):find("http://example.com/a.yaml", 1, true) ~= nil)
check("plain subscription url cell has no badge",
	(c_a[3] or ""):find("Combination", 1, true) == nil)

local c_l = cells(row_of(html, idL) or "")
check("local subscription name cell unchanged", trim(c_l[2] or "") == "LocalOne")
check("local subscription still badges [Local] in the url cell",
	(c_l[3] or ""):find("[Local]", 1, true) ~= nil)

-- ---------- 5) 反面对照：渲染结果确实随数据变化 ----------
core.save_combo(idC, "Renamed999", { idA, idB })
local html2 = render()
local name2 = trim((cells(row_of(html2, idC) or ""))[2] or "")
check("control: name cell follows the data", name2 == "Renamed999")
check("control: render actually varies with data", html ~= html2)

os.execute("rm -rf " .. TMPDIR)
print("")
print(passed .. " passed, " .. failed .. " failed")
os.exit(failed == 0 and 0 or 1)
