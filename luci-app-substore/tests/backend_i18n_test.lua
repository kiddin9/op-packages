-- backend_i18n_test.lua — 后端返回的用户可见文案必须是「有译文的英文 msgid」
-- 用法：lua5.1 tests/backend_i18n_test.lua
--
-- 背景（LEGACY_ISSUES 7.7）：
--   root/usr/share/substore/*.lua 里的失败原因会经两条路到达用户 ——
--   控制器 back_to_list / back_to_nodes 的 ?err=，以及 meta.error
--   （视图里的 msg.translate）。而**后端模块不能 require("luci.i18n")**：
--   substore-cron.sh 在独立的 lua 进程里跑 core.sync，那里没有 LuCI 环境。
--   所以后端一律返回语言中立的英文 msgid，翻译只发生在显示边界。
--
-- 两件事必须同时成立，各有一组断言：
--   A 后端源码里不得再有中文字面量 —— 中文写死在后端，英文界面下就会冒出中文，
--     而且它永远进不了翻译表（这正是 7.7 要修的东西）。
--   B 后端返回/存入/拼接的每个 msgid 都必须在 po/zh_Hans/substore.po 里有条目 ——
--     漏条目时 translate 回退成 msgid，中文界面下冒出英文。
--
-- B 的「哪些字面量算用户可见」不靠猜：只认三种**语法位置**，它们穷举了后端的
-- 全部出口 ——
--   1) return 语句里的字面量（`return nil, "…"` / `return false, "…"` / 带 serr or）
--   2) `error = "…"` 字段（写进 meta.error，视图会显示）
--   3) msg.compose / msg.join / msg.compose_list 的参数（组合消息的各个片段）
-- 外加一个显式例外：parser.lua 的 FORMAT_LABELS 表值 —— 它会被拼进
-- 「混用多种格式」那条组合消息，所以同样要有译文，但形状不是上面三种。
--
-- 「三种位置上就是文案」这条规则并非在每个模块里都成立（见 NOT_MESSAGES 与
-- SCAN_FILES 的逐条说明），所以扫描面是显式列举的，不是「扫全部后端文件」。

package.path = "./root/usr/share/?.lua;" .. package.path

local util = require("substore.util")
local msg = require("substore.msg")

local passed, failed = 0, 0
local function check(name, cond)
	if cond then passed = passed + 1; print("PASS " .. name)
	else failed = failed + 1; print("FAIL " .. name) end
end

local BACKEND_DIR = "root/usr/share/substore/"
local CONTROLLER = "root/usr/lib/lua/luci/controller/admin/substore.lua"
local PO = "po/zh_Hans/substore.po"

-- ---------- CJK 判定（与 view_i18n_test.lua 同一套按字节的判据） ----------
local function has_cjk(s)
	for i = 1, #s - 2 do
		local b1, b2, b3 = s:byte(i), s:byte(i + 1), s:byte(i + 2)
		if b1 and b2 and b3 and b1 >= 0xE4 and b1 <= 0xE9
			and b2 >= 0x80 and b2 <= 0xBF and b3 >= 0x80 and b3 <= 0xBF then
			return true
		end
	end
	return false
end

-- 允许保留 CJK 的字面量。按**字面量内容**匹配，不按行号 ——
-- 行号会随编辑漂移，内容不会。每一条都必须给出理由。
local CJK_OK = {
	["[^,%s，]+"] = "node.lua 的关键词拆分正则：字符类里那个全角逗号是**匹配目标**，" ..
		"翻译它会让「香港，日本」这类全角分隔写法不再被拆开",
}

-- ---------- 源码扫描 ----------
-- 剥掉注释。**不**碰字符串 —— 注释里的中文不算用户可见文本，
-- 而字符串里的中文正是要抓的东西。
local function strip_comments(src)
	local out, i, n = {}, 1, #src
	while i <= n do
		local c = src:sub(i, i)
		if c == "-" and src:sub(i, i + 1) == "--" then
			-- 长注释 --[[ … ]] / --[==[ … ]==]
			local eq = src:match("^%[(=*)%[", i + 2)
			if eq then
				local close = "]" .. eq .. "]"
				local e = src:find(close, i + 4 + #eq, true)
				e = e and (e + #close - 1) or n
				out[#out + 1] = (src:sub(i, e):gsub("[^\n]", ""))
				i = e + 1
			else
				local e = src:find("\n", i, true) or (n + 1)
				out[#out + 1] = (src:sub(i, e - 1):gsub("[^\n]", ""))
				i = e
			end
		elseif c == '"' or c == "'" then
			local j, buf = i + 1, { c }
			while j <= n do
				local d = src:sub(j, j)
				if d == "\\" then buf[#buf + 1] = src:sub(j, j + 1); j = j + 2
				elseif d == c or d == "\n" then break
				else buf[#buf + 1] = d; j = j + 1 end
			end
			buf[#buf + 1] = c
			out[#out + 1] = table.concat(buf)
			i = j + 1
		else
			out[#out + 1] = c
			i = i + 1
		end
	end
	return table.concat(out)
end

-- 遍历源码，收集三种语法位置上的双引号字面量。
-- 用「当前语句种类」跟踪：遇到 return / error = / msg.*( 就置位，
-- 到 depth 为 0 的换行处复位（Lua 里没有分号，语句就是按行断的）。
-- 只收「含字母且含空格」的字面量：纯符号串（"%s"、":" 之类）不可能是文案，
-- 单字（"ok"、"/"）也不是 —— 这两条把噪声挡在外面，不是靠猜。
local function scan_msgids(src)
	local ids, seen = {}, {}
	local i, n, depth, kind = 1, #src, 0, nil
	local function at(k) return src:sub(i, i + #k - 1) == k end
	local function take(s)
		if kind and s:find("%a") and s:find(" ") and not seen[s] then
			seen[s] = true
			ids[#ids + 1] = s
		end
	end
	while i <= n do
		local c = src:sub(i, i)
		if c == '"' then
			local j, buf = i + 1, {}
			while j <= n do
				local d = src:sub(j, j)
				if d == "\\" then buf[#buf + 1] = src:sub(j, j + 1); j = j + 2
				elseif d == '"' or d == "\n" then break
				else buf[#buf + 1] = d; j = j + 1 end
			end
			take(table.concat(buf))
			i = j + 1
		elseif c == "\n" then
			if depth == 0 then kind = nil end
			i = i + 1
		else
			if at("return") and not src:sub(i - 1, i - 1):match("[%w_]") then kind = "return" end
			if at("error =") then kind = "error" end
			if at("msg.compose(") or at("msg.join(") or at("msg.compose_list(") then kind = "compose" end
			if c == "(" or c == "{" or c == "[" then depth = depth + 1
			elseif c == ")" or c == "}" or c == "]" then depth = depth - 1 end
			i = i + 1
		end
	end
	return ids
end

-- FORMAT_LABELS 表块内的**表值**（见文件头「显式例外」）。
-- 只取 `key = "value"` 里等号右边那一个 —— 左边是格式标识（"wireguard-conf"
-- 之类），它只用来查表，不会被拼进任何给用户看的句子。
local function scan_format_labels(src)
	local ids = {}
	local in_block = false
	for line in (src .. "\n"):gmatch("([^\n]*)\n") do
		if line:find("local FORMAT_LABELS", 1, true) then in_block = true
		elseif in_block then
			if line:match("^}") then in_block = false
			else
				local v = line:match('=%s*"([^"]*)"')
				if v then ids[#ids + 1] = v end
			end
		end
	end
	return ids
end

local po = util.read_file(PO) or ""

-- 全部后端模块（A 的扫描面：CJK 判定不挑模块）。
local FILES = {}
for _, name in ipairs({ "core", "http", "node", "parser", "output", "output_formats",
	"output_clash_meta", "output_egern", "output_wireguard_conf", "probe", "util", "msg" }) do
	FILES[#FILES + 1] = BACKEND_DIR .. name .. ".lua"
end
FILES[#FILES + 1] = CONTROLLER

-- B 的扫描面：上面那条「三种语法位置上的字面量就是用户可见文案」成立的模块。
-- util.lua **不在**其中 —— 它同样有这三种位置，但那 23 条命中全是 json_decode
-- 的内部诊断与 shell 片段（调用方一律丢弃，换成自己的 "Failed to parse JSON"），
-- 真正直达用户的只有 human_duration 的返回值，那一条下面**调用**它来断言（B2），
-- 比在源码里认字面量更接近事实。
local SCAN_FILES = {}
for _, name in ipairs({ "core", "http", "node", "parser", "output", "output_formats",
	"output_clash_meta", "output_egern", "output_wireguard_conf", "probe", "msg" }) do
	SCAN_FILES[#SCAN_FILES + 1] = BACKEND_DIR .. name .. ".lua"
end

-- 同样落在上面三种语法位置、但**不是**给用户看的字面量。逐条列出而不是按模式
-- 匹配 —— 新增一条就得在这里做一次有意识的判断；模式匹配会让新写的文案悄悄
-- 漏过去。下面还有一条断言：表里每一项都必须仍能在源码里找到，防止它腐烂成
-- 「什么都放行」。
local NOT_MESSAGES = {
	-- parser.lua：逐行宽容解析的丢弃原因。parse_lines 只取第一个返回值（节点表），
	-- M.parse_uri 的调用者同样如此 —— 原因串既不进 meta.error 也不进 ?err=，
	-- 用户看到的是 "Unrecognized subscription format" / "Failed to parse JSON"。
	-- （注意 "bad wireguard conf: …" 两条**不在**这里：它们由 M.parse 原样上抛，
	-- 是用户可见文案，已改写成完整的英文 msgid 并进了翻译表。）
	["bad ss"] = true, ["bad ss (no @)"] = true, ["bad ssr"] = true,
	["bad vless"] = true, ["bad trojan"] = true, ["bad vmess"] = true,
	["bad vmess b64"] = true, ["bad vmess json"] = true,
	["bad hysteria"] = true, ["bad hysteria2"] = true, ["bad anytls"] = true,
	["bad socks"] = true, ["bad tuic"] = true,
	["bad wireguard"] = true, ["bad wireguard json"] = true,
	["no scheme"] = true, ["unsupported proto "] = true,
	-- http.lua / probe.lua：拼给 shell 的命令行片段（探测 wget/curl、ping 连通性），
	-- 原样交给 io.popen，不是给人看的。
	["command -v "] = true, [" >/dev/null 2>&1"] = true, [" https_proxy="] = true,
	["ping -c 1 -W "] = true, [" 2>/dev/null"] = true,
	-- output_formats.lua / output_clash_meta.lua：YAML/INI 输出的模板片段
	-- （缩进、分隔符、小节名），会被写进配置文件正文，不是错误提示。
	["' .. v .. '"] = true, ["' .. n["] = true, ["[Proxy Group]"] = true,
	[" = select"] = true, [", DIRECT"] = true, [", tag="] = true,
	["' .. s .. '"] = true, ["proxies: []"] = true,
}

-- ---------- A：后端源码里不得再有中文字面量 ----------
local cjk_bad = {}
for _, file in ipairs(FILES) do
	local src = util.read_file(file)
	if src then
		for lit in strip_comments(src):gmatch('"([^"\n]*)"') do
			if has_cjk(lit) and not CJK_OK[lit] then
				cjk_bad[#cjk_bad + 1] = file .. ": " .. lit
			end
		end
	end
end
check("no CJK literals left in backend sources", #cjk_bad == 0)
if #cjk_bad > 0 then
	for _, b in ipairs(cjk_bad) do print("      CJK literal: " .. b) end
end

-- 例外表本身不能变成「什么都放行」：每条都必须真的还在源码里，
-- 否则它会悄悄掩盖掉一个本该被抓住的中文字面量。
for lit, why in pairs(CJK_OK) do
	local found = false
	for _, file in ipairs(FILES) do
		local src = util.read_file(file)
		if src and strip_comments(src):find('"' .. lit .. '"', 1, true) then found = true break end
	end
	check("CJK exception still present (" .. lit:sub(1, 12) .. "…): " .. why:sub(1, 20) .. "…", found)
end

-- ---------- B：每个后端 msgid 都要有 zh-cn 译文 ----------
local missing, checked = {}, 0
local scanned = {}   -- 扫描到的全部字面量（含被排除的），给 NOT_MESSAGES 的存在性检查用
for _, file in ipairs(SCAN_FILES) do
	local src = util.read_file(file)
	if src then
		local clean = strip_comments(src)
		local ids = scan_msgids(clean)
		if file:find("parser%.lua$") then
			for _, v in ipairs(scan_format_labels(clean)) do ids[#ids + 1] = v end
		end
		for _, id in ipairs(ids) do
			scanned[id] = true
			if not NOT_MESSAGES[id] then
				checked = checked + 1
				if po:find('msgid "' .. id .. '"', 1, true) == nil then
					missing[#missing + 1] = file .. ": " .. id
				end
			end
		end
	end
end
check("every backend msgid has a zh-cn translation", #missing == 0)
if #missing > 0 then
	for _, m in ipairs(missing) do print("      no po entry: " .. m) end
end

-- 排除表不能腐烂：每条都得仍能在源码里找到，否则它只是在无意义地放行。
local stale = {}
for id in pairs(NOT_MESSAGES) do
	if not scanned[id] then stale[#stale + 1] = id end
end
check("no stale entry in the NOT_MESSAGES table", #stale == 0)
if #stale > 0 then
	for _, s in ipairs(stale) do print("      stale exclusion: " .. s) end
end

-- ---------- B2：util.human_duration 的返回值逐段查表 ----------
-- 它是组合消息（数字 + 单位 msgid），且是 util.lua 唯一直达用户的输出 ——
-- 直接调用它，比在源码里认字面量更接近事实。
-- 判据与扫描器一致：含字母的段必须查得到译文；纯数字段原样显示，不查表。
local hd_cases = {
	{ 10 * 86400, " days" }, { 8 * 3600, " hours" }, { 30 * 60, " minutes" },
	{ -1, nil }, { 30, nil },
}
for _, case in ipairs(hd_cases) do
	local out = util.human_duration(case[1])
	local bad = {}
	for seg in (out .. msg.SEP):gmatch("(.-)" .. msg.SEP) do
		if seg:find("%a") and po:find('msgid "' .. seg .. '"', 1, true) == nil then
			bad[#bad + 1] = seg
		end
	end
	local label = ("human_duration(%d) segments are translated"):format(case[1])
	check(label, #bad == 0)
	if #bad > 0 then
		for _, b in ipairs(bad) do print("      no po entry: human_duration segment " .. b) end
	end
	if case[2] then
		check(("human_duration(%d) carries the unit msgid"):format(case[1]),
			out:find(msg.SEP .. case[2], 1, true) ~= nil)
	end
end

-- ---------- B3：控制器里裸写的 msgid 也要有译文 ----------
-- 控制器能 require("luci.i18n")，绝大多数文案在源头就 _() 掉了（那部分由
-- view_i18n_test 的 B2 覆盖）。但**存进 meta.error 的**那条必须留 msgid ——
-- 它会被持久化，读它的可能是另一个语言的会话，只能在显示时翻译。
-- 形状唯一且明确：`error = "…"`。
local ctl_src = util.read_file(CONTROLLER) or ""
local ctl_missing = {}
for i, line in ipairs((function()
	local t = {}
	for l in (ctl_src .. "\n"):gmatch("([^\n]*)\n") do t[#t + 1] = l end
	return t
end)()) do
	if not line:match("^%s*%-%-") then
		for id in line:gmatch('error = "([^"]*)"') do
			if po:find('msgid "' .. id .. '"', 1, true) == nil then
				ctl_missing[#ctl_missing + 1] = i .. " " .. id
			end
		end
	end
end
check("every persisted controller msgid has a zh-cn translation", #ctl_missing == 0)
if #ctl_missing > 0 then
	for _, m in ipairs(ctl_missing) do print("      no po entry: controller:" .. m) end
end

-- 扫描面不能退化成空集（正则写错时 #missing 也会是 0，那是假绿）。
-- 当前实际命中约 80 条；阈值取 70，留出正常增删的余量。
check("backend msgid scan is not vacuous", checked >= 70)

-- 反向：po 里为后端准备的那批条目不能是死条目 —— 每条都得真的被后端用到。
-- 只查本文件标记出来的那段（后端 msgid 段），模板/控制器的条目另有测试覆盖。
local backend_section = po:match("# 后端模块（root/usr/share/substore/%*%.lua）返回的失败原因(.*)$") or ""
local unused = {}
for id in backend_section:gmatch('msgid "([^"]*)"') do
	local used = false
	for _, file in ipairs(FILES) do
		local src = util.read_file(file)
		if src and strip_comments(src):find('"' .. id .. '"', 1, true) then used = true break end
	end
	if not used then unused[#unused + 1] = id end
end
check("no dead backend msgid in the po", #unused == 0)
if #unused > 0 then
	for _, u in ipairs(unused) do print("      dead po entry: " .. u) end
end

print("")
print(("backend_i18n_test: %d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
