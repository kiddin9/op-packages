-- subscriptions_format_gate_test.lua — 订阅列表页「选择格式」下拉的启用条件
-- 用法：lua5.1 tests/subscriptions_format_gate_test.lua
--
-- 需求：刚添加、还没点「更新」的订阅（以及更新失败 / 解析结果为空的订阅），
-- node_count 为 0，此时「订阅链接转换」列的格式下拉必须是灰色不可选的 ——
-- 否则用户会选出一个必然为空的订阅链接，等于引导他生成无效内容。
--
-- .htm 需要 LuCI 运行时才能渲染，本机没有。这里的做法是把模板按 LuCI 的方式
-- 重建成 Lua chunk（<% %> 里的代码原样，文本变成 __w(...)），用一套替身环境
-- **真的渲染一遍**，再对生成的 HTML 断言。比「源码里有没有某个字符串」强得多：
-- 它同时验证了模板语法、分支条件与最终输出。

package.path = "./root/usr/share/?.lua;" .. package.path

local core = require("substore.core")

local passed, failed = 0, 0
local function check(name, cond)
	if cond then passed = passed + 1; print("PASS " .. name)
	else failed = failed + 1; print("FAIL " .. name) end
end

-- ---------- 数据目录改到 /tmp，绝不碰真实的 /etc/substore ----------
-- LIST_FILE / NODES_DIR 是 require 时算好的常量，必须一并改掉。
local TMPDIR = "/tmp/substore_fmtgate_" .. tostring(os.time()) .. "_" .. tostring(math.random(1e6))
os.execute("rm -rf " .. TMPDIR)
core.DATA_DIR = TMPDIR
core.LIST_FILE = TMPDIR .. "/subscriptions.json"
core.NODES_DIR = TMPDIR .. "/nodes"
core.ensure_dirs()

-- ---------- 模板 → 可执行 chunk ----------
local VIEW = "root/usr/lib/lua/luci/view/substore/subscriptions.htm"

-- 与 tests/template_escape_test.lua 的 build_chunk 同构，有两处不同：
--   1) 首行从环境取 __w 的实现（那边是 `local __w = function() end`，只为过语法检查）
--   2) **字面 HTML 也要 __w 出来**。那边只关心 <% %> 里的代码，字面文本全部丢弃；
--      这里要断言渲染结果，丢了字面文本就等于丢了全部标签属性 —— 实测会漏掉
--      `disabled="disabled"`（它是字面 HTML，不是表达式），断言恒假。
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

-- 取出某个订阅那一行的 <select ...> 开标签
local function select_tag_of(html, id)
	local s = html:find('id="fmt_' .. id .. '"', 1, true)
	if not s then return nil end
	local e = html:find(">", s, true)
	if not e then return nil end
	return html:sub(s, e)
end

-- 数一数这一段里有多少个 <option>（禁用不应改变选项数量）
local function select_count(text)
	local n = 0
	for _ in text:gmatch("<option") do n = n + 1 end
	return n
end

local function body_of(html, id)
	local s = html:find('id="fmt_' .. id .. '"', 1, true)
	if not s then return nil end
	local e = html:find("</tr>", s, true) or #html
	return html:sub(s, e)
end

-- ---------- 造两个订阅：一个没解析出节点，一个有节点 ----------
local id_empty = core.add("EmptySub", "http://example.com/empty.yaml", {})
check("fixture: empty subscription created", type(id_empty) == "string" and id_empty ~= "")
core.save_meta(id_empty, { node_count = 0 })

local id_ok = core.add("GoodSub", "http://example.com/good.yaml", {})
check("fixture: good subscription created", type(id_ok) == "string" and id_ok ~= "")
core.save_meta(id_ok, { node_count = 5 })

-- 第三个：更新失败的订阅（error 非空、node_count 归 0）——同样不该让选格式
local id_err = core.add("ErrSub", "http://example.com/err.yaml", {})
core.save_meta(id_err, { node_count = 0, error = "下载失败" })

local html = render()
check("template renders", #html > 0)
check("both subscription rows present",
	select_tag_of(html, id_empty) ~= nil and select_tag_of(html, id_ok) ~= nil)

-- ---------- 核心断言 ----------
local tag_empty = select_tag_of(html, id_empty) or ""
local tag_ok = select_tag_of(html, id_ok) or ""
local tag_err = select_tag_of(html, id_err) or ""

check("0-node select is disabled", tag_empty:find('disabled="disabled"', 1, true) ~= nil)
check("0-node select is greyed out", tag_empty:find("opacity", 1, true) ~= nil)
check("0-node select keeps not-allowed cursor", tag_empty:find("not-allowed", 1, true) ~= nil)
check("0-node select carries a title hint", tag_empty:find("title=", 1, true) ~= nil)

check("parsed select is NOT disabled", tag_ok:find("disabled", 1, true) == nil)
check("parsed select is NOT greyed out", tag_ok:find("opacity", 1, true) == nil)

check("failed-update select is disabled", tag_err:find('disabled="disabled"', 1, true) ~= nil)

-- 提示文案随状态切换
local body_empty = body_of(html, id_empty) or ""
local body_ok = body_of(html, id_ok) or ""

-- 下拉里始终有格式选项，只是选不了（禁用不是把选项删掉）。
-- 断言要看整行而不是 <select> 开标签：select_tag_of 只取到开标签的 ">" 为止，
-- 选项在它之后，拿开标签找 <option 恒为假。
check("0-node row still lists formats", body_empty:find("<option", 1, true) ~= nil)
check("0-node row still has the placeholder option",
	body_empty:find('<option value=""', 1, true) ~= nil)
check("parsed row lists the same formats",
	select_count(body_empty) == select_count(body_ok) and select_count(body_ok) > 0)
check("0-node row shows the parse-first hint",
	body_empty:find("Update and parse nodes before choosing a format", 1, true) ~= nil)
check("0-node row hides the pick-a-format hint",
	body_empty:find("Pick a format to generate the subscription link", 1, true) == nil)
check("parsed row shows the pick-a-format hint",
	body_ok:find("Pick a format to generate the subscription link", 1, true) ~= nil)
check("parsed row hides the parse-first hint",
	body_ok:find("Update and parse nodes before choosing a format", 1, true) == nil)

-- ---------- 反面对照：断言不是恒真 ----------
-- 把 node_count 提到 3，同一个订阅的下拉必须立刻变为可选。
core.save_meta(id_empty, { node_count = 3 })
local html2 = render()
local tag_empty2 = select_tag_of(html2, id_empty) or ""
check("control: same row becomes enabled once nodes exist",
	tag_empty2:find("disabled", 1, true) == nil)
check("control: render actually varies with data", tag_empty ~= tag_empty2)

os.execute("rm -rf " .. TMPDIR)
print("")
print(passed .. " passed, " .. failed .. " failed")
os.exit(failed == 0 and 0 or 1)
