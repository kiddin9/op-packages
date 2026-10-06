-- p2_batch7_test.lua — P2 批次七回归测试（L1 / L6 / L8 / L9 / L23 / L24 / L25 / L26）
-- 用法：lua5.1 tests/p2_batch7_test.lua
--
-- 全部离线：涉及子进程的地方一律替换 io.popen / os.execute 为记录桩。
-- L5（视图 < 转义）的断言在 tests/view_injection_test.lua 里，不在此重复。

package.path = "./root/usr/share/?.lua;" .. package.path

local util = require("substore.util")
local node = require("substore.node")
local output = require("substore.output")
local probe = require("substore.probe")
local msg = require("substore.msg")

local passed, failed = 0, 0
local function check(name, cond)
	if cond then passed = passed + 1; print("PASS " .. name)
	else failed = failed + 1; print("FAIL " .. name) end
end

local function read(p)
	return util.read_file(p) or ""
end

-- ---------- L1：界面 msgid 一律用英文（中文只在 po 里做译文） ----------
--
-- 用中文当 msgid 且 po 里没有对应条目时，LuCI 在英文界面会**原样显示中文**。
-- 这里直接扫模板：`<%:...%>` 与 `luci.i18n.translate("...")` 里的字符串不得含 CJK。
local function has_cjk(s)
	-- UTF-8 里的 CJK 统一落在 U+4E00..U+9FFF（三字节 E4B8 80 .. E9BF BF）。
	-- 按字节扫：任意一个三字节序列落在该区间即判定为中文。
	for i = 1, #s - 2 do
		local b1, b2, b3 = s:byte(i), s:byte(i + 1), s:byte(i + 2)
		if b1 and b2 and b3 and b1 >= 0xE4 and b1 <= 0xE9
			and b2 >= 0x80 and b2 <= 0xBF and b3 >= 0x80 and b3 <= 0xBF then
			return true
		end
	end
	return false
end

local VIEW_DIR = "root/usr/lib/lua/luci/view/substore/"
local view_files = {
	"subscriptions.htm", "nodes.htm", "node_edit.htm", "local_form.htm",
	"form.htm", "combo.htm", "output.htm",
}
local bad_msgids = {}
for _, f in ipairs(view_files) do
	local src = read(VIEW_DIR .. f)
	for i, line in ipairs((function()
		local t = {}
		for l in (src .. "\n"):gmatch("([^\n]*)\n") do t[#t + 1] = l end
		return t
	end)()) do
		-- 跳过 Lua 注释行（模板里 <%% 之外的 -- 行），注释里可以写中文
		if not line:match("^%s*%-%-") then
			for msgid in line:gmatch("<%%:(.-)%%>") do
				if has_cjk(msgid) then
					bad_msgids[#bad_msgids + 1] = f .. ":" .. i .. " " .. msgid
				end
			end
			for msgid in line:gmatch('luci%.i18n%.translate%("(.-)"%)') do
				if has_cjk(msgid) then
					bad_msgids[#bad_msgids + 1] = f .. ":" .. i .. " " .. msgid
				end
			end
		end
	end
end
check("no CJK msgid left in view templates", #bad_msgids == 0)
if #bad_msgids > 0 then
	for _, b in ipairs(bad_msgids) do print("      " .. b) end
end

-- 新英文 msgid 必须在 zh-cn 译文表里有条目，否则中文界面会显示英文
local po = read("po/zh_Hans/substore.po")
check("po has Operation failed", po:find('msgid "Operation failed"', 1, true) ~= nil)
check("po has Pick a format msgid",
	po:find("Pick a format to generate the subscription link", 1, true) ~= nil)
check("po Operation failed translated", po:find('msgstr "操作失败"', 1, true) ~= nil)
-- 反向对照：这两个 msgid 在改动前是中文的，确认它们确实来自本轮改动
check("po still has Type", po:find('msgid "Type"', 1, true) ~= nil)

-- ---------- L6：批量探测必须限制并发 ----------
--
-- 原来「先起完全部 io.popen 再统一读取」，节点数上千时进程/fd 无界增长。
-- 用记录桩统计**同时存活**的句柄峰值。
check("MAX_PARALLEL defined", type(probe.MAX_PARALLEL) == "number" and probe.MAX_PARALLEL > 0)

local real_popen = io.popen
local live, peak, opened = 0, 0, 0
io.popen = function()
	live = live + 1
	opened = opened + 1
	if live > peak then peak = live end
	return {
		read = function() return "64 bytes from 127.0.0.1: time=1.5 ms" end,
		close = function() live = live - 1 end,
	}
end
local many = {}
for i = 1, 100 do
	many[i] = { name = "n" .. i, server = "127.0.0.1", port = 80 }
end
local res = probe.probe(many, "ping")
io.popen = real_popen

check("probe returns one result per node", #res == 100)
check("probe spawned one process per node", opened == 100)
-- 用局部变量兜住 nil：MAX_PARALLEL 不存在时（改动前）下面两条断言要能报 FAIL
-- 而不是让整个脚本因「compare number with nil」中断，否则后面的断言全看不到。
local cap = tonumber(probe.MAX_PARALLEL) or -1
check("probe concurrency capped", peak <= cap)
check("probe actually parallel (not serial)", peak == cap)
check("probe closed every handle", live == 0)
check("probe parsed latency", res[1].latency == 1.5)
check("probe keeps order", res[1].name == "n1" and res[100].name == "n100")

-- ---------- L8：空 format 不能被当成合法格式名 ----------
local tpl_nodes = { {
	name = "n", proto = "vmess", server = "1.1.1.1", port = 443,
	uuid = "11111111-1111-4111-8111-111111111111", alterId = 0,
} }
local def_body, def_err = output.generate(tpl_nodes, "clashmeta")
check("baseline format works", type(def_body) == "string" and def_err == nil)

local empty_body, empty_err = output.generate(tpl_nodes, "")
check("empty format does not error", empty_err == nil)
check("empty format equals default", empty_body == def_body)
check("whitespace format equals default", output.generate(tpl_nodes, "   ") == def_body)
check("tab/newline format equals default", output.generate(tpl_nodes, "\t\n ") == def_body)
-- nil 与非法名仍按原语义走
check("nil format equals default", output.generate(tpl_nodes, nil) == def_body)
local _, bad_err = output.generate(tpl_nodes, "nosuchformat")
check("unknown format still errors", type(bad_err) == "string" and bad_err:find("nosuchformat", 1, true) ~= nil)

-- ---------- L9：output.htm / combo.htm 的安装位置 ----------
--
-- 这两行原来挂在 /www/luci-static 的 INSTALL_DIR 块下面 —— 目标路径本身是对的，
-- 但归错了块，一旦有人调整块顺序就会被装到错误的目录。
local mk = read("Makefile")
local view_dir_at = mk:find("$(INSTALL_DIR) $(1)/usr/lib/lua/luci/view/substore", 1, true)
local static_dir_at = mk:find("$(INSTALL_DIR) $(1)/www/luci-static/resources/substore", 1, true)
local out_htm_at = mk:find("view/substore/output.htm", 1, true)
local combo_htm_at = mk:find("view/substore/combo.htm", 1, true)
check("Makefile has view INSTALL_DIR", view_dir_at ~= nil)
check("Makefile has luci-static INSTALL_DIR", static_dir_at ~= nil)
check("output.htm installed in view block",
	out_htm_at ~= nil and out_htm_at > view_dir_at and out_htm_at < static_dir_at)
check("combo.htm installed in view block",
	combo_htm_at ~= nil and combo_htm_at > view_dir_at and combo_htm_at < static_dir_at)

-- ---------- L23：trojan → vmess/vless 必须生成合法 UUID ----------
local UUID_RE = "^%x%x%x%x%x%x%x%x%-%x%x%x%x%-4%x%x%x%-[89ab]%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$"

-- 这几个函数是本轮新增的，在改动前的代码上并不存在。用局部兜底而不是直接调用：
-- 否则整个脚本会在第一次 nil 调用处中断，后面所有断言都跑不到，
-- 反向验证就只剩半份报告（看不清哪些新断言真的失败）。
local uuid = util.uuid or function() return nil end
local gsub_literal = util.gsub_literal or function() return nil end
local validate_rename_map = node.validate_rename_map or function() return true end

local u = uuid()
check("util.uuid shape", type(u) == "string" and u:match(UUID_RE) ~= nil)
check("util.uuid unique-ish", uuid() ~= uuid())

-- L25 原先经 converter.convert_protocol 验证「转换时生成的 UUID 不是
-- base64(seed) 的形状」。converter / node_converter 已作为死代码删除
-- （见 docs/LEGACY_ISSUES.md 1.4），这里改为直接验证 util.uuid 本身 ——
-- 那才是唯一在用的实现，形状要求与当初一致：36 字符、只含十六进制与连字符。
-- 反向对照：旧实现是 base64(seed) 的前 36 字符，而 base64 只产出 24 个字符，
-- 长度必然不等于 36 且含非十六进制字符。
check("util.uuid not base64-shaped",
	u:find("[+/=]", 1) == nil and #u == 36)

-- ---------- L24：gsub 替换串必须按字面处理 ----------
check("gsub_literal escapes percent", gsub_literal("100%") == "100%%")
check("gsub_literal empty", gsub_literal(nil) == "")

-- node.apply_rules 的 {server} 模板占位符同样要按字面替换。
-- 该分支由 rules.template_apply 开关控制，必须显式打开。
local TMPL_ON = { template_apply = true }
local tmpl_nodes = { {
	name = "tpl", proto = "vmess", server = "1.2.3.4", port = 443,
	template = "https://sub.example.com/{server}:{port}",
} }
local applied = node.apply_rules(tmpl_nodes, TMPL_ON)
check("apply_rules template expands server",
	applied[1].url == "https://sub.example.com/1.2.3.4:443")
local tmpl_nodes2 = { {
	name = "tpl", proto = "vmess", server = "100%host", port = 443,
	template = "https://x/{server}",
} }
check("apply_rules template keeps percent literal",
	node.apply_rules(tmpl_nodes2, TMPL_ON)[1].url == "https://x/100%host")
-- 已有 url 的节点不得被模板覆盖（模板只是「补一个 url」，不是改写）
local tmpl_nodes3 = { {
	name = "tpl", proto = "vmess", server = "1.2.3.4", port = 443,
	template = "https://x/{server}", url = "https://keep.me/",
} }
check("apply_rules template leaves existing url alone",
	node.apply_rules(tmpl_nodes3, TMPL_ON)[1].url == "https://keep.me/")

-- ---------- L25：非法重命名正则必须在保存时报错 ----------
local ok_valid, err_valid = validate_rename_map("a -> b")
check("valid regex accepted", ok_valid == true and err_valid == nil)
check("empty rules accepted", validate_rename_map("") == true)
check("exact rule accepted", validate_rename_map("OLD=NEW") == true)
check("placeholder rule accepted", validate_rename_map("{server}_{port}_{proto}") == true)

local ok_bad, err_bad = validate_rename_map("[abc -> x")
check("invalid regex rejected", ok_bad == false)
-- 报错是 msg.compose 拼出来的**组合消息**（后端不能 require luci.i18n，见 msg.lua）：
-- 行号是独立一段，整串直接 find 会跨不过分隔符。按显示边界的方式还原成用户看到的文案再断言。
local function rendered(s) return msg.translate(s, function(k) return k end) end
check("invalid regex error names the line",
	type(err_bad) == "string" and rendered(err_bad):find("line 1", 1, true) ~= nil)
check("invalid regex error quotes the pattern",
	type(err_bad) == "string" and err_bad:find("[abc", 1, true) ~= nil)

-- 行号要指向真正出错的那一行，而不是恒为 1
local ok_multi, err_multi = validate_rename_map("good -> ok\n[bad -> x\nlast -> y")
check("line number points at the bad rule",
	ok_multi == false and type(err_multi) == "string"
		and rendered(err_multi):find("line 2", 1, true) ~= nil)

-- 校验必须覆盖**每一条**备选分支（split_alternatives 展开后的每一项）
check("invalid alternative rejected", validate_rename_map("[a|b -> x") == false)

-- ---------- L26：数据文件与目录权限 ----------
--
-- Lua 5.1 没有 os.chmod，实现走 busybox chmod；这里替换 os.execute 记录命令行。
local real_execute = os.execute
local exec_log = {}
os.execute = function(cmd)
	exec_log[#exec_log + 1] = cmd
	return 0
end

local tmpfile = "/tmp/substore_l26_probe.json"
os.remove(tmpfile)
local wok = util.atomic_write(tmpfile, "{}", "600")
os.remove(tmpfile)
check("atomic_write with mode succeeds", wok == true)

local chmod_after_rename = false
for _, cmd in ipairs(exec_log) do
	if cmd:find("chmod 600", 1, true) and cmd:find(tmpfile, 1, true) then
		chmod_after_rename = true
	end
end
check("atomic_write chmods the target 600", chmod_after_rename)

-- 不带 mode 时不得额外 chmod（cron 文件走的就是这条路，权限语义要保持不变）
exec_log = {}
os.remove(tmpfile)
util.atomic_write(tmpfile, "{}")
os.remove(tmpfile)
local stray = false
for _, cmd in ipairs(exec_log) do
	if cmd:find("chmod", 1, true) then stray = true end
end
check("atomic_write without mode does not chmod", stray == false)

-- ensure_dir 的 mode 只在**新建**时由 mkdir -m 生效
exec_log = {}
util.ensure_dir("/tmp/substore_l26_dir", "700")
local saw_mkdir_m = false
for _, cmd in ipairs(exec_log) do
	if cmd:find("mkdir -p -m 700", 1, true) then saw_mkdir_m = true end
end
check("ensure_dir passes -m 700", saw_mkdir_m)

exec_log = {}
util.ensure_dir("/tmp/substore_l26_dir")
local saw_plain_mkdir = false
for _, cmd in ipairs(exec_log) do
	if cmd:find("mkdir -p ", 1, true) and not cmd:find(" -m ", 1, true) then saw_plain_mkdir = true end
end
check("ensure_dir without mode stays plain", saw_plain_mkdir)

-- core.ensure_dirs：新建目录带 700，且对**已存在**的目录补一次 chmod 700
package.loaded["substore.core"] = nil
local core = require("substore.core")
exec_log = {}
core.ensure_dirs()
local saw_data_chmod, saw_nodes_chmod = false, false
for _, cmd in ipairs(exec_log) do
	if cmd:find("chmod 700", 1, true) then
		if cmd:find(core.DATA_DIR, 1, true) then saw_data_chmod = true end
		if cmd:find(core.NODES_DIR, 1, true) then saw_nodes_chmod = true end
	end
end
check("ensure_dirs chmods DATA_DIR 700", saw_data_chmod)
check("ensure_dirs chmods NODES_DIR 700", saw_nodes_chmod)

-- 第二次调用不得重复 chmod（load() 每次读列表都会走到这里）
local before = #exec_log
core.ensure_dirs()
local chmods_again = 0
for i = before + 1, #exec_log do
	if exec_log[i]:find("chmod", 1, true) then chmods_again = chmods_again + 1 end
end
check("ensure_dirs chmods only once per process", chmods_again == 0)

os.execute = real_execute

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
