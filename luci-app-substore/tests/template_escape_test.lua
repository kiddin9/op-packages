-- template_escape_test.lua — 模板转义回归测试（§38）
-- 用法：lua5.1 tests/template_escape_test.lua
--
-- 两件事：
--   1) 语法：把模板按 LuCI 的方式重建成一个 Lua chunk 并 loadstring，
--      确保 <% %> 里的代码没有语法错误（本机没有 LuCI，跑不了真实模板）。
--   2) 转义：找出所有 <% %> 输出表达式，凡是包含「用户可控」变量的，
--      必须经过 pcdata / urlencode / json_encode / build_url 之一，
--      否则就是 §38 的注入点。

package.path = "./root/usr/share/?.lua;" .. package.path

local VIEW_DIR = os.getenv("SUBSTORE_VIEW_DIR") or "root/usr/lib/lua/luci/view/substore"
local TEMPLATES = {
	"subscriptions.htm", "nodes.htm", "form.htm", "local_form.htm",
	"combo.htm", "node_edit.htm", "output.htm",
}

local passed, failed = 0, 0
local function check(name, cond)
	if cond then passed = passed + 1; print("PASS " .. name)
	else failed = failed + 1; print("FAIL " .. name) end
end

local function read_file(p)
	local f = io.open(p, "rb")
	if not f then return nil end
	local s = f:read("*a")
	f:close()
	return s
end

-- 用户可控（或源自订阅内容）的变量，出现在输出位置就必须转义
local TAINTED_NAMES = {
	"it.name", "it.url", "it.proxy", "it.error",
	"meta.name", "n.name", "n.server", "n.proto",
	"keyword", "group", "sort_by", "proto",
	"flash_err", "err", "content", "ki", "ke", "local_mode",
}
local SAFE_WRAPPERS = { "pcdata", "urlencode", "json_encode", "build_url", "tostring" }

-- 词边界匹配：避免 "ke" 命中 "token"、"keyword" 命中 "keyword_include"
local function taint_pattern(name)
	local esc = name:gsub("[%p]", "%%%0")
	return "%f[%w_]" .. esc .. "%f[^%w_]"
end

-- 去掉字符串字面量与比较表达式后再找污染变量：
-- `dedup and "checked" or ""`、`local_mode=="text" and "x" or ""` 这类
-- 只输出静态字符串的写法不是注入点。
-- 注意：Lua pattern 没有 | 交替，且必须先去掉比较、再去字面量，
-- 否则 `x=="lit"` 会先变成 `x==""` 而漏掉。
local function strip_static(e)
	local VAR = "[%w_%.%[%]]+"
	e = e:gsub(VAR .. '%s*[=~]=%s*"[^"]*"', " ")
	e = e:gsub(VAR .. "%s*[=~]=%s*" .. VAR, " ")
	e = e:gsub('"[^"]*"%s*[=~]=%s*' .. VAR, " ")
	e = e:gsub('"[^"]*"', '""')
	e = e:gsub("'[^']*'", "''")
	return e
end

local function is_tainted(e)
	e = strip_static(e)
	for _, v in ipairs(TAINTED_NAMES) do
		if e:find(taint_pattern(v)) then return true, v end
	end
	return false
end

-- 把模板重建成可 loadstring 的 Lua chunk（LuCI 的做法：文本变 __w，代码原样）
local function build_chunk(src)
	local out = { "local __w = function() end" }
	local i = 1
	local n = #src
	while i <= n do
		local s = src:find("<%", i, true)
		if not s then break end
		local e = src:find("%>", s + 2, true)
		if not e then return nil, "unclosed <% at " .. s end
		local tag = src:sub(s + 2, e - 1)
		local kind = tag:sub(1, 1)
		local body = tag:sub(2)
		if kind == "=" then
			out[#out + 1] = "__w(" .. body .. ")"
		elseif kind == ":" then
			-- <%:文本%> 等价于 translate("文本")，内容是字符串字面量而非代码
			out[#out + 1] = "__w(" .. string.format("%q", body) .. ")"
		elseif kind == "+" then
			out[#out + 1] = "__w()"
		else
			out[#out + 1] = tag
		end
		out[#out + 1] = "\n"  -- 保留行数，便于报错定位
		i = e + 2
	end
	return table.concat(out, "\n")
end

-- 收集所有输出表达式 <% %> 与 <%= %>
local function outputs(src)
	local list = {}
	local i = 1
	while true do
		local s = src:find("<%", i, true)
		if not s then break end
		local e = src:find("%>", s + 2, true)
		if not e then break end
		local tag = src:sub(s + 2, e - 1)
		if tag:sub(1, 1) == "=" then
			local line = 1
			for _ in src:sub(1, s):gmatch("\n") do line = line + 1 end
			list[#list + 1] = { expr = tag:sub(2), line = line }
		end
		i = e + 2
	end
	return list
end

for _, t in ipairs(TEMPLATES) do
	local path = VIEW_DIR .. "/" .. t
	local src = read_file(path)
	check("read " .. t, src ~= nil)
	if src then
		-- 1) 语法
		local chunk, cerr = build_chunk(src)
		if not chunk then
			check(t .. " template structure", false)
			print("  " .. tostring(cerr))
		else
			local fn, lerr = loadstring(chunk, t)
			check(t .. " compiles", fn ~= nil)
			if not fn then print("  " .. tostring(lerr)) end
		end

		-- 2) 转义
		local bad = {}
		for _, o in ipairs(outputs(src)) do
			local e = o.expr
			local tainted, which = is_tainted(e)
			if tainted then
				local wrapped = false
				for _, w in ipairs(SAFE_WRAPPERS) do
					if e:find(w, 1, true) then wrapped = true; break end
				end
				if not wrapped then
					bad[#bad + 1] = string.format("%s:%d  <%%=%s%%>   (tainted: %s)", t, o.line, e, which)
				end
			end
		end
		check(t .. " no unescaped user data", #bad == 0)
		for _, b in ipairs(bad) do print("  UNESCAPED " .. b) end
	end
end

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
