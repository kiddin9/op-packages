-- subscriptions_bulk_delete_test.lua — 订阅列表页的勾选批量删除
-- 用法：lua5.1 tests/subscriptions_bulk_delete_test.lua
--
-- 需求（用户提出）：
--   1) 「名称」列前面要有选择框，表头的选择框能全选，每条订阅也能单独勾选；
--   2) 「添加组合订阅」后面要有「删除」按钮，勾选后删单条或多条，
--      一个都没勾选时点击不得删除任何东西。
--
-- .htm 需要 LuCI 运行时才能渲染，本机没有。做法与 subscriptions_format_gate_test.lua
-- 相同：把模板按 LuCI 的方式重建成 Lua chunk（<% %> 里的代码原样，文本变 __w(...)），
-- 用替身环境**真的渲染一遍**，再对生成的 HTML 断言。这比「源码里有没有某个字符串」
-- 强：它同时验证了模板语法、循环/分支与最终输出。
--
-- 有两类断言只能退化成字符串匹配（本机没有 JS 引擎，跑不了页面里的脚本）：
--   删除按钮的 JS 行为。这类断言一律在**渲染结果**上做（而不是读 .htm 源码），
--   至少能保证脚本真的被输出、且关键顺序（先判空、后提交）没被写反。

package.path = "./root/usr/share/?.lua;" .. package.path

local core = require("substore.core")

local passed, failed = 0, 0
local function check(name, cond)
	if cond then passed = passed + 1; print("PASS " .. name)
	else failed = failed + 1; print("FAIL " .. name) end
end

-- ---------- 数据目录改到 /tmp，绝不碰真实的 /etc/substore ----------
-- LIST_FILE / NODES_DIR 是 require 时算好的常量，必须一并改掉。
local TMPDIR = "/tmp/substore_bulkdel_" .. tostring(os.time()) .. "_" .. tostring(math.random(1e6))
os.execute("rm -rf " .. TMPDIR)
core.DATA_DIR = TMPDIR
core.LIST_FILE = TMPDIR .. "/subscriptions.json"
core.NODES_DIR = TMPDIR .. "/nodes"
core.ensure_dirs()

local VIEW = "root/usr/lib/lua/luci/view/substore/subscriptions.htm"

-- 与 tests/subscriptions_format_gate_test.lua 的 build_chunk 同构：
-- 字面 HTML 也要 __w 出来，否则标签属性（class / value / onclick）全丢，断言无从谈起。
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

local function count_of(html, pat)
	local n = 0
	for _ in html:gmatch(pat) do n = n + 1 end
	return n
end

-- ---------- 造三条订阅 ----------
local id1 = core.add("SubOne", "http://example.com/1.yaml", {})
local id2 = core.add("SubTwo", "http://example.com/2.yaml", {})
local id3 = core.add("SubThree", "http://example.com/3.yaml", {})
check("fixtures created", id1 and id2 and id3 and id1 ~= id2 and id2 ~= id3)

local html = render()
check("template renders", #html > 0)

-- ---------- 1) 选择框列在「名称」之前，且每行一个 ----------
local pos_toggle = html:find("substore_toggle_all(this)", 1, true)
local pos_name_th = html:find("<th>Name</th>", 1, true)
check("header select-all checkbox exists", pos_toggle ~= nil)
check("Name column header exists", pos_name_th ~= nil)
check("select-all sits before the Name column",
	pos_toggle ~= nil and pos_name_th ~= nil and pos_toggle < pos_name_th)

-- 表头那个选择框必须在**第一行数据之前** —— 否则它会落到某一行的单元格里
local pos_first_row = html:find('class="cbi-section-table-row"', 1, true)
check("select-all is inside the header row",
	pos_toggle ~= nil and pos_first_row ~= nil and pos_toggle < pos_first_row)

-- 每条订阅一个独立选择框，value 是订阅 id
for _, id in ipairs({ id1, id2, id3 }) do
	check("row checkbox for " .. id,
		html:find('<input type="checkbox" class="sub-check" value="' .. id .. '"/>', 1, true) ~= nil)
end
check("one checkbox per subscription", count_of(html, 'class="sub%-check"') == 3)

-- 选择框必须是该行的**第一个**单元格：出现在「名称」单元格之前
local row_start = html:find('class="cbi-section-table-row"', 1, true) or 0
local row_cb = html:find('class="sub-check"', row_start, true) or 0
local row_name = html:find("<td>", row_cb + 1, true) or 0
check("row checkbox is the first cell of the row", row_cb > row_start and row_name > row_cb)

-- ---------- 2) 「删除」按钮在「添加组合订阅」之后 ----------
local pos_combo = html:find("/admin/services/substore/combo", 1, true)
local pos_del_btn = html:find('onclick="substore_delete_selected()"', 1, true)
check("toolbar delete button exists", pos_del_btn ~= nil)
check("delete button comes after the Add-combination button",
	pos_combo ~= nil and pos_del_btn ~= nil and pos_del_btn > pos_combo)

-- 批量删除表单：提交到 delete 动作，带 token 与 id，且**不在表格里**
-- （每一行已经各有一个删除表单，HTML 不允许表单嵌套）
local form_pos = html:find('id="batch_delete_form"', 1, true)
local table_pos = html:find('class="cbi-section-table"', 1, true)
check("hidden batch form exists", form_pos ~= nil)
check("batch form is outside the table", form_pos ~= nil and table_pos ~= nil and form_pos < table_pos)
local form_html = form_pos and html:sub(form_pos, (html:find("</form>", form_pos, true) or #html)) or ""
check("batch form posts to the delete action",
	form_html:find('action="/cgi-bin/luci/admin/services/substore/delete"', 1, true) ~= nil)
check("batch form carries the CSRF token",
	form_html:find('name="token" value="TESTTOKEN"', 1, true) ~= nil)
check("batch form carries the id field", form_html:find('name="id"', 1, true) ~= nil)

-- ---------- 3) 一个都没勾选时不得删除 ----------
-- 页面里的 JS 本机跑不了，只能对**渲染出来的脚本**做结构断言。
local js_start = html:find("function substore_delete_selected()", 1, true)
check("delete JS is emitted", js_start ~= nil)
local js = js_start and html:sub(js_start, (html:find("</script>", js_start, true) or #html)) or ""

check("delete JS reads the checked boxes", js:find(".sub-check:checked", 1, true) ~= nil)
-- 关键：判空必须存在，且早于提交 —— 写反了就会「没勾选也提交」，即删空列表
local pos_empty_guard = js:find("boxes.length === 0", 1, true)
local pos_submit = js:find("form.submit()", 1, true)
check("delete JS has an empty-selection guard", pos_empty_guard ~= nil)
check("empty-selection guard runs before submitting",
	pos_empty_guard ~= nil and pos_submit ~= nil and pos_empty_guard < pos_submit)
-- 空选时只提示，不提交
local guard = (pos_empty_guard and pos_submit)
	and js:sub(pos_empty_guard, pos_submit) or ""
check("empty selection alerts instead of deleting", guard:find("alert(", 1, true) ~= nil)
check("empty selection does not submit", guard:find("form.submit", 1, true) == nil)

-- 多个 id 以逗号拼接后写入表单（控制器按逗号切分）
check("delete JS joins ids with a comma", js:find("ids.join(',')", 1, true) ~= nil)
check("delete JS writes the joined ids into the form",
	js:find("form.elements['id'].value", 1, true) ~= nil)

-- 全选：表头选择框要把所有 .sub-check 都同步
local all_start = html:find("function substore_toggle_all(", 1, true)
local all_js = all_start and html:sub(all_start, (html:find("</script>", all_start, true) or #html)) or ""
check("toggle-all JS is emitted", all_start ~= nil)
check("toggle-all targets the row checkboxes",
	all_js:find("querySelectorAll('.sub-check')", 1, true) ~= nil)
check("toggle-all copies the header state",
	all_js:find("boxes[i].checked = el.checked", 1, true) ~= nil)

-- ---------- 空列表：colspan 必须等于表头列数 ----------
-- 少一列会让「暂无订阅」提示错位；多一列在部分浏览器上会撑出多余格。
local header_cells = count_of(html, "<th[ >]")
check("header has 8 columns", header_cells == 8)
for _, id in ipairs({ id1, id2, id3 }) do core.remove(id) end
local html_empty = render()
check("empty render still renders", #html_empty > 0)
local colspan = html_empty:match('colspan="(%d+)"')
check("empty-row colspan matches the header column count",
	colspan ~= nil and tonumber(colspan) == header_cells)
check("empty state message still shown",
	html_empty:find("No subscriptions yet.", 1, true) ~= nil)

-- ---------- 反面对照：断言不是恒真 ----------
-- 改回旧的 colspan 时上面的断言必须失败（证明它真的在检查）
check("control: colspan assertion is not vacuous", tonumber(colspan) ~= 7)

os.execute("rm -rf " .. TMPDIR)
print("")
print(passed .. " passed, " .. failed .. " failed")
os.exit(failed == 0 and 0 or 1)
