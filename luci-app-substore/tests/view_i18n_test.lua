-- view_i18n_test.lua — 视图模板的界面文本必须走 i18n（英文界面不得出现中文）
-- 用法：lua5.1 tests/view_i18n_test.lua
--
-- 背景：LuCI 的 <%:msgid%> 按当前语言查 .lmo，查不到就回退显示 msgid（英文）。
-- 而**直接写在模板里的中文字面量根本不进翻译表** —— 英文界面下原样显示中文。
-- 本仓库只有 zh-cn 一份 .lmo，所以「英文界面」等价于 translate() 恒等（msgid 原样输出）。
--
-- 三组断言：
--   A 真渲染：把模板按 LuCI 的方式重建成 Lua chunk，用恒等 translate 渲染一遍，
--     输出里不得出现 CJK。这直接复现「英文界面显示中文」这个缺陷 ——
--     中文字面量在输出里，而 <%:…%> 输出的是英文 msgid。
--   B po 覆盖：模板里每个 msgid 都必须在 po/zh_Hans/substore.po 里有条目，
--     否则中文界面会显示英文。
--   C 字面文本：去掉 <% %> 代码块与 HTML 注释后，剩下的字面 HTML 里不得有 CJK。
--     A 只覆盖能离线渲染的模板（需要数据 fixture 的 nodes.htm / output.htm 跳过），
--     C 用静态扫描补上这个缺口。
--
-- A 与 C 都只看「用户可见文本」：HTML 注释（<!-- -->）与 JS 行注释（//）会进
-- 渲染结果，但用户看不见，模板里写中文注释是允许的。

package.path = "./root/usr/share/?.lua;" .. package.path

local core = require("substore.core")
local util = require("substore.util")

local passed, failed = 0, 0
local function check(name, cond)
	if cond then passed = passed + 1; print("PASS " .. name)
	else failed = failed + 1; print("FAIL " .. name) end
end

local function lines_of(s)
	local t = {}
	for l in (s .. "\n"):gmatch("([^\n]*)\n") do t[#t + 1] = l end
	return t
end

-- ---------- CJK 判定 ----------
-- UTF-8 里的 CJK 统一落在 U+4E00..U+9FFF（三字节 E4B8 80 .. E9BF BF）。
-- 按字节扫：任意一个三字节序列落在该区间即判定为中文。
local function cjk_snippet(s)
	for i = 1, #s - 2 do
		local b1, b2, b3 = s:byte(i), s:byte(i + 1), s:byte(i + 2)
		if b1 and b2 and b3 and b1 >= 0xE4 and b1 <= 0xE9
			and b2 >= 0x80 and b2 <= 0xBF and b3 >= 0x80 and b3 <= 0xBF then
			local from = math.max(1, i - 40)
			return (s:sub(from, math.min(#s, i + 40)):gsub("%s+", " "))
		end
	end
	return nil
end

-- 把一段标记里的「非可见文本」抹掉：HTML 注释、以及整行的 // 注释。
-- 抹成等量空白而不是删除 —— 保留换行才能让后面的行号对得上源码。
local function blank_nontext(s)
	s = s:gsub("<!%-%-.-%-%->", function(m) return (m:gsub("[^\n]", "")) end)
	local out = {}
	for _, line in ipairs(lines_of(s)) do
		out[#out + 1] = line:match("^%s*//") and (line:gsub("[^\n]", "")) or line
	end
	return table.concat(out, "\n")
end

local VIEW_DIR = "root/usr/lib/lua/luci/view/substore/"
local VIEWS = {
	"subscriptions.htm", "nodes.htm", "node_edit.htm", "local_form.htm",
	"form.htm", "combo.htm", "output.htm",
}

-- ---------- 数据目录改到 /tmp，绝不碰真实的 /etc/substore ----------
-- LIST_FILE / NODES_DIR 是 require 时算好的常量，必须一并改掉。
local TMPDIR = "/tmp/substore_i18n_" .. tostring(os.time()) .. "_" .. tostring(math.random(1e6))
os.execute("rm -rf " .. TMPDIR)
core.DATA_DIR = TMPDIR
core.LIST_FILE = TMPDIR .. "/subscriptions.json"
core.NODES_DIR = TMPDIR .. "/nodes"
core.ensure_dirs()

-- 造一条启用了定时更新的订阅：subscriptions.htm 只在「有订阅且 cron_enable 为真」时
-- 才渲染「定时: …」那一行，没有数据的话 Part A 覆盖不到它。
local cron_id = core.add("CronSub", "http://example.com/cron.yaml",
	{ cron_enable = "1", cron_time = "0 3 * * *" })
check("fixture: cron subscription created", type(cron_id) == "string" and cron_id ~= "")

-- ---------- 模板 → 可执行 chunk（与 tests/subscriptions_format_gate_test.lua 同构） ----------
-- <% %> 里的代码原样保留，字面 HTML 与 <%= %> / <%: %> 都变成 __w(...)。
-- 关键：<%:msgid%> 输出的是 **msgid 本身** —— 这正是英文界面（无 en .lmo）的行为。
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
-- translate 恒等 = 英文界面：msgid 原样输出，查不到译文时不额外加中文。
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
	formvalue = function() return nil end, -- 无 id ⇒ 各表单走「新增」分支，不需要 fixture
	getenv = function() return nil end,
}
local real_require = require
local function fake_require(name)
	if name == "luci.http" then return http_stub end
	if name == "luci.util" then return luci_stub.util end
	if name == "luci.i18n" then return luci_stub.i18n end
	return real_require(name)
end

local function render(file)
	local f = assert(io.open(VIEW_DIR .. file, "rb"))
	local src = f:read("*a")
	f:close()
	local chunk, cerr = build_chunk(src)
	if not chunk then return nil, cerr end
	local fn, lerr = loadstring(chunk, file)
	if not fn then return nil, lerr end
	local buf = {}
	local env = setmetatable({
		__substore_w = function(s) if s ~= nil then buf[#buf + 1] = tostring(s) end end,
		require = fake_require,
		luci = luci_stub,
		token = "TESTTOKEN", -- LuCI 注入的 CSRF token
	}, { __index = _G })
	setfenv(fn, env)
	local ok, err = pcall(fn)
	if not ok then return nil, err end
	return table.concat(buf)
end

-- ---------- A：渲染后不得出现 CJK ----------
-- 五个模板都能在「无数据」下渲染：form / combo / local_form / node_edit 走新增或
-- 「节点不存在」分支，subscriptions 走空列表分支。
for _, file in ipairs({ "form.htm", "combo.htm", "local_form.htm", "node_edit.htm", "subscriptions.htm" }) do
	local html, err = render(file)
	if not html then
		check(file .. " renders", false)
		print("      " .. tostring(err))
	else
		check(file .. " renders", true)
		local snip = cjk_snippet(blank_nontext(html))
		check(file .. " renders English only", snip == nil)
		if snip then print("      CJK in output: …" .. snip .. "…") end
	end
end

-- ---------- B：模板里的 msgid 必须都有 zh-cn 译文 ----------
local po = util.read_file("po/zh_Hans/substore.po") or ""
local missing = {}
for _, file in ipairs(VIEWS) do
	local src = util.read_file(VIEW_DIR .. file) or ""
	for i, line in ipairs(lines_of(src)) do
		if not line:match("^%s*%-%-") and not line:match("^%s*//") then
			local ids = {}
			for id in line:gmatch("<%%:(.-)%%>") do ids[#ids + 1] = id end
			for id in line:gmatch('luci%.i18n%.translate%("(.-)"%)') do ids[#ids + 1] = id end
			for id in line:gmatch("luci%.i18n%.translate%('(.-)'%)") do ids[#ids + 1] = id end
			for _, id in ipairs(ids) do
				if po:find('msgid "' .. id .. '"', 1, true) == nil then
					missing[#missing + 1] = file .. ":" .. i .. " " .. id
				end
			end
		end
	end
end
check("every view msgid has a zh-cn translation", #missing == 0)
if #missing > 0 then
	for _, m in ipairs(missing) do print("      no po entry: " .. m) end
end

-- ---------- B2：控制器里 _("…") 的 msgid 同样必须有 zh-cn 译文 ----------
-- 控制器的失败原因经 ?err= 带回页面显示，是用户可见文本。漏了 po 条目时
-- translate 回退成 msgid，中文界面下就冒出英文（与模板漏条目是同一个缺陷，
-- 只是入口不同）。控制器里的 msgid 一律写英文原文，见文件头的说明。
local ctl_src = util.read_file("root/usr/lib/lua/luci/controller/admin/substore.lua") or ""
local ctl_missing = {}
for i, line in ipairs(lines_of(ctl_src)) do
	if not line:match("^%s*%-%-") then
		for id in line:gmatch('_%("(.-)"%)') do
			if po:find('msgid "' .. id .. '"', 1, true) == nil then
				ctl_missing[#ctl_missing + 1] = i .. " " .. id
			end
		end
	end
end
check("every controller msgid has a zh-cn translation", #ctl_missing == 0)
if #ctl_missing > 0 then
	for _, m in ipairs(ctl_missing) do print("      no po entry: controller:" .. m) end
end

-- ---------- C：字面 HTML 文本里不得有 CJK ----------
-- <% %> 代码块抹成空白（保留换行，行号不漂）。剩下的是模板里写死的界面文本，
-- 它不会进翻译表 —— 英文界面下原样输出中文。
local literal_bad = {}
for _, file in ipairs(VIEWS) do
	local src = util.read_file(VIEW_DIR .. file) or ""
	local text = blank_nontext(src:gsub("<%%.-%%>", function(m) return (m:gsub("[^\n]", "")) end))
	for i, line in ipairs(lines_of(text)) do
		local snip = cjk_snippet(line)
		if snip then literal_bad[#literal_bad + 1] = file .. ":" .. i .. " …" .. snip .. "…" end
	end
end
check("no hardcoded CJK in template literal text", #literal_bad == 0)
if #literal_bad > 0 then
	for _, b in ipairs(literal_bad) do print("      " .. b) end
end

os.execute("rm -rf " .. TMPDIR)

print("")
print(("view_i18n_test: %d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
