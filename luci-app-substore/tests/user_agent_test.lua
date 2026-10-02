-- user_agent_test.lua — 订阅客户端类型（User-Agent）支持
-- 用法：lua5.1 tests/user_agent_test.lua
--
-- 背景：部分机场（如 Allblue 加速器）按 User-Agent 区分客户端 —— 同一个订单链接，
-- 只有用**该订单绑定的客户端**的 UA 去请求才返回真实节点，其它 UA（含不传 UA 时
-- curl 自带的 curl/x.y.z）拿到的是「与您使用客户端不兼容」的占位内容。
-- 占位内容本身是**合法**的 ss 节点（7 个指向 127.0.0.1:1080 的假节点），
-- 所以解析不会报错，症状是「订阅更新成功但只有 7 个用不了的节点」。
--
-- 本文件覆盖：
--   - http.validate_user_agent 的取值校验（控制字符 / 长度 / 去空白）
--   - UA 确实以 -A（curl）/ -U（wget）进入命令行，且经过 shell 引用
--   - 重定向的**每一跳**都带 UA
--   - core.resolve_user_agent 的预设解析与错误回显
--   - core.add / core.sync 的字段存储与透传；非法 UA 必须明确失败（禁止 silent fallback）
--
-- 全部用例不触网：目标一律用**公网 IP 字面量**（不经过 DNS，结论与本机解析器无关），
-- 子进程一律用 io.popen / os.execute 替身。

package.path = "./root/usr/share/?.lua;" .. package.path

local http = require("substore.http")
local core = require("substore.core")
local util = require("substore.util")

local passed, failed = 0, 0
local function check(name, cond)
	if cond then passed = passed + 1; print("PASS " .. name)
	else failed = failed + 1; print("FAIL " .. name) end
end

-- ---------- 子进程替身 ----------
local real_popen, real_execute = io.popen, os.execute
local spawned

-- 强制 detect_tool 选中指定后端：have() 用 os.execute("command -v X") == 0 判定。
-- 其余命令（wget 本体、logger）一律返回 0（成功）。
local function spy_execute_for(tool)
	os.execute = function(cmd)
		if cmd:find("command %-v ") then
			return cmd:find("command %-v " .. tool .. " ") and 0 or 1
		end
		return 0
	end
end

-- curl 替身：按顺序返回预设响应，并把响应体 / 响应头写进命令行里 -o / -D 指向的文件
-- （fetch_curl 会去读这两个文件，不写就永远走「读取响应失败」分支）。
local function spy_curl(responses)
	spawned = {}
	local n = 0
	io.popen = function(cmd)
		n = n + 1
		spawned[#spawned + 1] = cmd
		local r = responses[n] or responses[#responses]
		local out = cmd:match("%-o '([^']+)'")
		local hdr = cmd:match("%-D '([^']+)'")
		if out and r.body then
			local f = io.open(out, "w"); if f then f:write(r.body); f:close() end
		end
		if hdr and r.location then
			local f = io.open(hdr, "w")
			if f then
				f:write("HTTP/1.1 " .. r.code .. "\r\nLocation: " .. r.location .. "\r\n\r\n")
				f:close()
			end
		end
		local text = r.code .. " " .. (r.peer or "")
		return { read = function() return text end, close = function() end }
	end
end

-- wget 替身：把响应体写进 -O 指向的文件
local function spy_wget(body)
	spawned = {}
	os.execute = function(cmd)
		if cmd:find("command %-v ") then
			return cmd:find("command %-v wget ") and 0 or 1
		end
		spawned[#spawned + 1] = cmd
		local out = cmd:match("%-O '([^']+)'")
		if out and body then
			local f = io.open(out, "w"); if f then f:write(body); f:close() end
		end
		return 0
	end
end

local function restore()
	io.popen = real_popen
	os.execute = real_execute
end

-- ---------- 1. validate_user_agent ----------
check("ua nil -> empty", http.validate_user_agent(nil) == "")
check("ua empty -> empty", http.validate_user_agent("") == "")
check("ua blank -> empty", http.validate_user_agent("   ") == "")
check("ua trimmed", http.validate_user_agent("  clash-verge/v2.5.0  ") == "clash-verge/v2.5.0")
check("ua with spaces kept inside",
	http.validate_user_agent("mihomo.party/v2.0.0 (clash.meta)") == "mihomo.party/v2.0.0 (clash.meta)")
-- 控制字符必须拒绝：UA 最终进入 `-A <ua>`，util.shq 的单引号挡得住注入，
-- 但挡不住换行 —— curl 会把它当成额外的请求头拼进去（header injection），
-- 日志里也会被换行截断、伪造出额外行。
check("ua newline rejected", http.validate_user_agent("a\nb") == nil)
check("ua cr rejected", http.validate_user_agent("a\rb") == nil)
check("ua tab rejected", http.validate_user_agent("a\tb") == nil)
check("ua nul rejected", http.validate_user_agent("a\0b") == nil)
local _, uaerr = http.validate_user_agent("a\nb")
check("ua reject reason is string", type(uaerr) == "string" and #uaerr > 0)
check("ua 256 chars accepted", http.validate_user_agent(string.rep("x", 256)) ~= nil)
check("ua 257 chars rejected", http.validate_user_agent(string.rep("x", 257)) == nil)

-- ---------- 2. UA 进入 curl 命令行 ----------
local URL = "http://1.1.1.1/sub" -- 公网字面量，不走 DNS
spy_execute_for("curl")
spy_curl({ { code = "200", peer = "1.1.1.1", body = "trojan://pw@1.1.1.1:443#N" } })
local body = http.download(URL, { user_agent = "clash-verge/v2.5.0" })
check("curl download ok with ua", body ~= nil)
check("curl cmd has -A", spawned[1] and spawned[1]:find("%-A 'clash%-verge/v2%.5%.0'") ~= nil)
restore()

-- 不设 UA 时不能凭空多出 -A（否则等于把「默认」也钉死成某个客户端）
spy_execute_for("curl")
spy_curl({ { code = "200", peer = "1.1.1.1", body = "x" } })
http.download(URL, {})
check("curl cmd has no -A when unset", spawned[1] and spawned[1]:find("%-A ") == nil)
restore()

-- 空字符串与 nil 等价
spy_execute_for("curl")
spy_curl({ { code = "200", peer = "1.1.1.1", body = "x" } })
http.download(URL, { user_agent = "" })
check("curl cmd has no -A when empty", spawned[1] and spawned[1]:find("%-A ") == nil)
restore()

-- ---------- 3. UA 进入 wget 命令行 ----------
-- busybox wget 用 -U（已核对 busybox 1.37 的 --help：`-U STR  Use STR for User-Agent header`）
spy_wget("trojan://pw@1.1.1.1:443#N")
local wbody = http.download(URL, { user_agent = "v2rayN/7.22.0" })
check("wget download ok with ua", wbody ~= nil)
check("wget cmd has -U", spawned[1] and spawned[1]:find("%-U 'v2rayN/7%.22%.0'") ~= nil)
restore()

spy_wget("x")
http.download(URL, {})
check("wget cmd has no -U when unset", spawned[1] and spawned[1]:find("%-U ") == nil)
restore()

-- ---------- 4. shell 引用：单引号不能逃逸 ----------
-- UA 来自表单，属不可信输入。util.shq 把 ' 变成 '\''，整串仍是一个参数。
spy_execute_for("curl")
spy_curl({ { code = "200", peer = "1.1.1.1", body = "x" } })
http.download(URL, { user_agent = "evil'; rm -rf /; echo '" })
local c4 = spawned[1] or ""
check("quote ua is shq-escaped", c4:find("'evil'\\''; rm %-rf /; echo '\\'''") ~= nil)
check("quote ua has no raw injection", c4:find("'; rm %-rf /; echo ' ") == nil)
restore()

-- ---------- 5. 重定向的每一跳都带 UA ----------
-- 机场常用 302 跳到 CDN；只在第一跳带 UA 的话，第二跳拿回的仍是占位内容。
spy_execute_for("curl")
spy_curl({
	{ code = "302", peer = "1.1.1.1", location = "http://8.8.8.8/next" },
	{ code = "200", peer = "8.8.8.8", body = "trojan://pw@8.8.8.8:443#N" },
})
local rbody = http.download(URL, { user_agent = "mihomo.party/v2.0.0 (clash.meta)" })
check("redirect download ok", rbody ~= nil)
check("redirect followed (2 hops)", #spawned == 2)
check("hop1 carries ua", spawned[1] and spawned[1]:find("%-A 'mihomo%.party/v2%.0%.0 %(clash%.meta%)'") ~= nil)
check("hop2 carries ua", spawned[2] and spawned[2]:find("%-A 'mihomo%.party/v2%.0%.0 %(clash%.meta%)'") ~= nil)
restore()

-- ---------- 6. download 对非法 UA 必须拒绝，且一个进程都不起 ----------
-- 与代理一样：非法值静默忽略 = silent fallback（§12）。用户会以为 UA 已生效，
-- 实际拿到的还是占位节点。
spy_execute_for("curl")
spy_curl({ { code = "200", peer = "1.1.1.1", body = "x" } })
local db, _, derr = http.download(URL, { user_agent = "bad\nua" })
check("download rejects bad ua", db == nil)
check("download bad ua reason", type(derr) == "string" and derr:find("User%-Agent") ~= nil)
check("download bad ua spawns nothing", #spawned == 0)
restore()

-- ---------- 7. core.resolve_user_agent ----------
check("resolve empty preset -> empty", core.resolve_user_agent("", "") == "")
check("resolve nil preset -> empty", core.resolve_user_agent(nil, nil) == "")
-- 「自定义」留空 = 明确要求不设置 UA，不是错误
check("resolve custom empty -> empty", core.resolve_user_agent("custom", "  ") == "")
check("resolve custom value", core.resolve_user_agent("custom", " MyUA/1.0 ") == "MyUA/1.0")
check("resolve custom rejects control chars", core.resolve_user_agent("custom", "a\nb") == nil)
local _, rerr = core.resolve_user_agent("no-such-client", "")
check("resolve unknown preset -> nil", core.resolve_user_agent("no-such-client", "") == nil)
check("resolve unknown preset reason", type(rerr) == "string" and rerr:find("no%-such%-client") ~= nil)

-- 四个预设必须都能解析出非空且互不相同的 UA
local seen_ua = {}
local presets_ok = true
for _, p in ipairs(core.UA_PRESETS) do
	local ua = core.resolve_user_agent(p.key, "")
	if not ua or ua == "" or seen_ua[ua] then presets_ok = false end
	seen_ua[ua] = true
end
check("all presets resolve to distinct non-empty ua", presets_ok)
check("four presets defined", #core.UA_PRESETS == 4)

-- 锁定取自客户端源码的**确切** UA 形状（改错一个字就会退回占位内容）
check("clash-verge preset", core.resolve_user_agent("clash-verge", "") == "clash-verge/v2.5.0")
check("v2rayn preset", core.resolve_user_agent("v2rayn", "") == "v2rayN/7.22.0")
check("clash-party preset keeps (clash.meta) suffix",
	core.resolve_user_agent("clash-party", "") == "mihomo.party/v2.0.0 (clash.meta)")
local flc = core.resolve_user_agent("flclash", "") or ""
check("flclash preset has 3 space-joined tokens", select(2, flc:gsub(" ", "")) == 2)
check("flclash preset has clash-verge token", flc:find("clash%-verge", 1, false) ~= nil)
check("flclash preset has Platform token", flc:find("Platform/", 1, true) ~= nil)

-- ---------- 8. core.ua_preset_of 回显 ----------
check("preset_of empty", core.ua_preset_of("") == "")
check("preset_of nil", core.ua_preset_of(nil) == "")
check("preset_of known", core.ua_preset_of("clash-verge/v2.5.0") == "clash-verge")
check("preset_of unknown -> custom", core.ua_preset_of("SomeOtherClient/9.9") == "custom")
-- 往返：预设 -> UA -> 预设
local roundtrip_ok = true
for _, p in ipairs(core.UA_PRESETS) do
	if core.ua_preset_of(p.ua) ~= p.key then roundtrip_ok = false end
end
check("preset roundtrip", roundtrip_ok)

-- ---------- 9. core.add / core.sync 透传 ----------
local tmp = os.tmpname() .. "_substore_ua"
os.execute("mkdir -p " .. string.format("%q", tmp .. "/nodes"))
core.DATA_DIR = tmp
core.LIST_FILE = tmp .. "/subscriptions.json"
core.NODES_DIR = tmp .. "/nodes"
core.CRON_FILE = tmp .. "/cron.d.substore"

local id = core.add("UA 订阅", "http://1.1.1.1/sub", { user_agent = "clash-verge/v2.5.0" })
local m = core.get(id)
check("add stores user_agent", m.user_agent == "clash-verge/v2.5.0")

local id2 = core.add("无 UA 订阅", "http://1.1.1.1/sub2", {})
check("add defaults user_agent to empty", core.get(id2).user_agent == "")

-- sync 必须把 meta.user_agent 透传给 http.download
local seen_opts
local real_download = http.download
http.download = function(_, opts) seen_opts = opts; return "trojan://pw@1.1.1.1:443#N", {}, nil end
spy_execute_for("curl")
local cnt, serr = core.sync(id)
check("sync ok with ua", cnt ~= nil)
check("sync passes user_agent to download", seen_opts and seen_opts.user_agent == "clash-verge/v2.5.0")
restore()

-- 非法 UA：必须明确失败，且**不能**发起下载
seen_opts = nil
core.save_meta(id, { user_agent = "bad\nua" })
spy_execute_for("curl")
local cnt2, serr2 = core.sync(id)
check("sync fails on invalid ua", cnt2 == nil)
check("sync invalid ua reason", type(serr2) == "string" and serr2:find("User%-Agent") ~= nil)
check("sync invalid ua does not download", seen_opts == nil)
check("sync invalid ua recorded in meta",
	(core.get(id).error or ""):find("User%-Agent") ~= nil)
restore()
http.download = real_download

-- ---------- 10. 控制器接线：表单 → core.add / core.save_meta ----------
-- 上面各节证明了 http 会发 UA、core 会透传 UA。但整条链路上还有一段没被覆盖：
-- 表单提交的是 ua_preset / ua_custom，控制器必须把它解析成 user_agent 再存。
-- 这一段断了的话，用户在界面上选了客户端类型，保存后却什么都没发生 ——
-- 正是最难发现的「设置无效」类缺陷。
--
-- 这里用**真实的 core**（数据目录已在第 9 节重定向到临时目录）+ 最小 luci stub，
-- 走完整条 create / save 路径。
local FORM, LAST_REDIRECT = {}, nil
_G.luci = {
	http = {
		formvalue = function(k) return FORM[k] end,
		redirect = function(url) LAST_REDIRECT = url end,
	},
	dispatcher = {
		build_url = function(...) return "/" .. table.concat({ ... }, "/") end,
	},
	util = {
		urlencode = function(s)
			return (tostring(s or ""):gsub("[^%w%-%._~]", function(c)
				return string.format("%%%02X", string.byte(c))
			end))
		end,
		pcdata = function(s) return tostring(s or "") end,
	},
	i18n = { translate = function(s) return s end },
}
_G.luci.controller = { admin = {} }
package.loaded["luci.http"] = _G.luci.http
package.loaded["luci.dispatcher"] = _G.luci.dispatcher
package.loaded["luci.util"] = _G.luci.util
package.loaded["luci.i18n"] = _G.luci.i18n

local cok, cerr = pcall(dofile, "root/usr/lib/lua/luci/controller/admin/substore.lua")
check("controller loads under stub", cok)
if not cok then print("  load error: " .. tostring(cerr)) end
local ctl = package.loaded["luci.controller.admin.substore"] or {}

-- create：选预设 Clash Verge
FORM = { token = "t", name = "机场A", url = "http://1.1.1.1/a", ua_preset = "clash-verge" }
LAST_REDIRECT = nil
ctl.action_create()
local created
for _, it in pairs(require("substore.core").list()) do
	if it.name == "机场A" then created = it end
end
check("create stores preset ua", created and created.user_agent == "clash-verge/v2.5.0")

-- create：自定义 UA
FORM = { token = "t", name = "机场B", url = "http://1.1.1.1/b",
	ua_preset = "custom", ua_custom = "MyClient/3.1" }
LAST_REDIRECT = nil
ctl.action_create()
local created_b
for _, it in pairs(require("substore.core").list()) do
	if it.name == "机场B" then created_b = it end
end
check("create stores custom ua", created_b and created_b.user_agent == "MyClient/3.1")

-- create：不选 = 空
FORM = { token = "t", name = "机场C", url = "http://1.1.1.1/c" }
LAST_REDIRECT = nil
ctl.action_create()
local created_c
for _, it in pairs(require("substore.core").list()) do
	if it.name == "机场C" then created_c = it end
end
check("create defaults ua empty", created_c and created_c.user_agent == "")

-- create：非法自定义 UA 必须回显错误，且**不创建**订阅
FORM = { token = "t", name = "机场D", url = "http://1.1.1.1/d",
	ua_preset = "custom", ua_custom = "bad\nua" }
LAST_REDIRECT = nil
ctl.action_create()
local made_d = false
for _, it in pairs(require("substore.core").list()) do
	if it.name == "机场D" then made_d = true end
end
check("create invalid ua rejected", made_d == false)
check("create invalid ua redirects with err",
	LAST_REDIRECT ~= nil and LAST_REDIRECT:find("err=") ~= nil)

-- save：改预设必须落盘
FORM = { token = "t", id = created.id, name = "机场A", url = "http://1.1.1.1/a",
	ua_preset = "flclash" }
LAST_REDIRECT = nil
ctl.action_save()
local saved = require("substore.core").get(created.id)
check("save updates ua", saved and saved.user_agent == "FlClash/v0.8.93 clash-verge Platform/linux")

-- save：清回默认
FORM = { token = "t", id = created.id, name = "机场A", url = "http://1.1.1.1/a", ua_preset = "" }
LAST_REDIRECT = nil
ctl.action_save()
check("save clears ua", require("substore.core").get(created.id).user_agent == "")

-- ---------- 11. form.htm 真实渲染 ----------
-- .htm 是运行时才编译的模板，luac -p 检查不到它 —— 模板里的 Lua 语法错误
-- 只会在用户打开页面时 500。这里按 LuCI 的方式把模板重建成 Lua chunk 真渲染一遍，
-- 同时验证「下拉回显」这段分支逻辑。
local VIEW = "root/usr/lib/lua/luci/view/substore/form.htm"

local function build_chunk(src)
	local out = { "local __w = __substore_w" }
	local i, n = 1, #src
	while i <= n do
		local s = src:find("<%", i, true)
		if not s then
			out[#out + 1] = "__w(" .. string.format("%q", src:sub(i)) .. ")"
			break
		end
		if s > i then out[#out + 1] = "__w(" .. string.format("%q", src:sub(i, s - 1)) .. ")" end
		local e = src:find("%>", s + 2, true)
		if not e then return nil, "unclosed <% at " .. s end
		local tag = src:sub(s + 2, e - 1)
		local kind = tag:sub(1, 1)
		local body = tag:sub(2)
		if kind == "=" then out[#out + 1] = "__w(" .. body .. ")"
		elseif kind == ":" then out[#out + 1] = "__w(" .. string.format("%q", body) .. ")"
		elseif kind == "+" then out[#out + 1] = "__w()"
		else out[#out + 1] = tag end
		out[#out + 1] = "\n"
		i = e + 2
	end
	return table.concat(out, "\n")
end

local FORM_ID = nil
local view_http = { formvalue = function(k) if k == "id" then return FORM_ID end return nil end }
-- pcdata 按 LuCI 真实语义转义：模板若把 UA 原样吐出（没走 pcdata），
-- 输出里就会留下裸的 < > " &，下面的断言据此判定。
local function view_pcdata(s)
	return (tostring(s or ""):gsub('[&<>"]', function(c)
		return ({ ["&"] = "&amp;", ["<"] = "&lt;", [">"] = "&gt;", ['"'] = "&quot;" })[c]
	end))
end
local view_luci = {
	util = { pcdata = view_pcdata, urlencode = function(s) return tostring(s or "") end },
	i18n = { translate = function(s) return tostring(s or "") end },
	dispatcher = { build_url = function(...) return "/" .. table.concat({ ... }, "/") end },
}
local real_require2 = require
local function fake_require(name)
	if name == "luci.http" then return view_http end
	if name == "luci.util" then return view_luci.util end
	if name == "luci.i18n" then return view_luci.i18n end
	return real_require2(name)
end

local function render_form(id)
	FORM_ID = id
	local f = assert(io.open(VIEW, "rb"))
	local src = f:read("*a"); f:close()
	local chunk, cerr = build_chunk(src)
	if not chunk then return nil, cerr end
	local fn, lerr = loadstring(chunk, "form.htm")
	if not fn then return nil, lerr end
	local buf = {}
	local env = setmetatable({
		__substore_w = function(s) if s ~= nil then buf[#buf + 1] = tostring(s) end end,
		require = fake_require,
		luci = view_luci,
		token = "TESTTOKEN",
	}, { __index = _G })
	setfenv(fn, env)
	fn()
	return table.concat(buf)
end

local html_add, aerr = render_form(nil)
check("form.htm renders (add)", html_add ~= nil)
if not html_add then print("  render error: " .. tostring(aerr)) end
check("form has ua_preset select", html_add and html_add:find('name="ua_preset"', 1, true) ~= nil)
check("form has ua_custom input", html_add and html_add:find('name="ua_custom"', 1, true) ~= nil)
-- 4 个预设 + 「默认」+「自定义」。注意只能数 ua_preset 这一个 <select> 里的 ——
-- 页面上的 cron 下拉有几十个 <option>，整页计数会恒大于 6。
local function ua_select_html(html)
	local s = html:find('name="ua_preset"', 1, true)
	if not s then return nil end
	local e = html:find("</select>", s, true)
	return html:sub(s, e or #html)
end
local ua_sel = ua_select_html(html_add or "")
local nopt = 0
for _ in (ua_sel or ""):gmatch("<option") do nopt = nopt + 1 end
check("form has 6 ua options", nopt == 6)
check("form presets listed", html_add and html_add:find("Clash Verge", 1, true) ~= nil
	and html_add:find("v2rayN", 1, true) ~= nil
	and html_add:find("Clash Party", 1, true) ~= nil
	and html_add:find("FlClash", 1, true) ~= nil)
-- 新增页默认「不设置」，且自定义输入框隐藏
check("form add defaults to empty preset",
	html_add and html_add:find('<option value="" selected', 1, true) ~= nil)
check("form add hides custom row",
	html_add and html_add:find('id="ua_custom_row"', 1, true) ~= nil
	and html_add:find('id="ua_custom_row" class="cbi%-section%-descr" style="margin:0%.5em 0;display:none"') ~= nil)

-- 编辑页：已存预设必须回显为选中项
core.save_meta(created.id, { user_agent = "clash-verge/v2.5.0" })
local html_edit = render_form(created.id)
check("form edit renders", html_edit ~= nil)
check("form edit selects stored preset",
	html_edit and html_edit:find('<option value="clash%-verge" selected') ~= nil)
check("form edit hides custom row",
	html_edit and html_edit:find('id="ua_custom_row" class="cbi%-section%-descr" style="margin:0%.5em 0;display:none"') ~= nil)

-- 编辑页：非预设 UA 落到「自定义」，输入框显示且被转义
core.save_meta(created.id, { user_agent = 'Weird"UA<>&x' })
local html_custom = render_form(created.id)
check("form custom renders", html_custom ~= nil)
check("form custom selects custom option",
	html_custom and html_custom:find('<option value="custom" selected') ~= nil)
check("form custom row visible",
	html_custom and html_custom:find('id="ua_custom_row" class="cbi%-section%-descr" style="margin:0%.5em 0;display:block"') ~= nil)
check("form custom value escaped (no raw angle bracket)",
	html_custom and html_custom:find('value="Weird"UA<>&x"', 1, true) == nil
	and html_custom:find("Weird&quot;UA&lt;&gt;&amp;x", 1, true) ~= nil)

-- 收尾：清掉临时目录
os.execute("rm -rf " .. string.format("%q", tmp))

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
