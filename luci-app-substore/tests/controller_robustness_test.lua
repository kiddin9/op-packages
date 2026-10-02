-- controller_robustness_test.lua — 控制器健壮性回归测试
-- 用法：lua5.1 tests/controller_robustness_test.lua
--
-- 覆盖两项：
--   L3  重复表单字段（POST）会让 formvalue 返回 **table** 而非 string，
--       控制器直接对它 :gsub / util.trim 会抛错 → HTTP 500。
--       依据上游 luci/http.lua 的 urldecode_message_body：
--         elseif what == parser.VALUE and name then
--             local val = msg.params[name]
--             if type(val) == "table" then val[#val+1] = ...
--             elseif val ~= nil then msg.params[name] = { val, ... }  -- ← 变 table
--       注意 GET 查询串走的是 urldecode_params，它只做覆盖、不建表，
--       所以触发条件是 POST 重复字段。
--   L4  combo_save / delete / update / node_delete 的失败被静默吞掉，
--       违反项目 §18（失败必须让用户看见）。
--
-- 不需要真实 LuCI：用最小 stub 提供 luci.http / luci.dispatcher / luci.util，
-- substore.core 换成可控假实现，然后直接调用控制器的 action_* 函数。

package.path = "./root/usr/share/?.lua;" .. package.path

local passed, failed = 0, 0
local function check(name, cond)
	if cond then passed = passed + 1; print("PASS " .. name)
	else failed = failed + 1; print("FAIL " .. name) end
end

-- ---------- luci stub ----------
local FORM = {}
local LAST_REDIRECT = nil
local LAST_WRITE = nil

_G.luci = {
	http = {
		formvalue = function(k) return FORM[k] end,
		redirect = function(url) LAST_REDIRECT = url end,
		write = function(s) LAST_WRITE = s end,
		status = function() end,
		header = function() end,
		prepare_content = function() end,
	},
	dispatcher = {
		build_url = function(...)
			local t = { ... }
			return "/" .. table.concat(t, "/")
		end,
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

-- ---------- substore 依赖 stub ----------
local CORE = {}
package.loaded["substore.core"] = CORE
-- 控制器在 read_rules_fields 里会调用 node.validate_rename_map 校验重命名规则
-- （非法正则要在保存时报错，而不是静默不生效）。stub 必须提供同名函数，
-- 否则整条保存路径都会因 nil 调用而 500 —— 那是 stub 缺口，不是产品代码缺陷。
local NODE = {
	filter = function(ns) return ns end,
	sort = function(ns) return ns end,
	validate_rename_map = function() return true end,
}
package.loaded["substore.node"] = NODE
package.loaded["substore.probe"] = {
	probe = function() return {} end,
}

local function core_reset()
	CORE.add = function() return "s0000000a" end
	CORE.add_local = function() return "s0000000a" end
	CORE.remove = function() return true end
	CORE.add_combo = function() return "s0000000a" end
	CORE.save_combo = function() return "s0000000a" end
	CORE.get = function() return { id = "s00000001", name = "x" } end
	CORE.list = function() return {} end
	CORE.read_nodes = function() return {} end
	CORE.write_nodes = function() return true end
	CORE.save_meta = function() return true end
	CORE.refresh_combos = function() end
	CORE.sync = function() return true end
	CORE.write_cron = function() end
	CORE.cron_time_valid = function() return true end
	-- 控制器在 read_ua_fields 里调用它解析「订阅客户端类型」（预设 key → UA 字符串）。
	-- 与上面的 validate_rename_map 同理：stub 缺这个函数会让整条保存路径 nil 调用。
	-- 这里返回 ""（不设置 UA），让用例聚焦各自要覆盖的字段。
	CORE.resolve_user_agent = function() return "" end
	CORE.UA_PRESETS = { { key = "clash-verge", label = "Clash Verge", ua = "clash-verge/v2.5.0" } }
	CORE.generate_link = function() return "body", "text/plain", "f.txt" end
	CORE.RULE_PROTOS = { "vmess", "trojan" }
end
core_reset()

local CTL_PATH = os.getenv("SUBSTORE_CONTROLLER")
	or "root/usr/lib/lua/luci/controller/admin/substore.lua"
local ok, err = pcall(dofile, CTL_PATH)
check("controller loads under stub", ok)
if not ok then print("  load error: " .. tostring(err)) end
local ctl = package.loaded["luci.controller.admin.substore"] or {}

local function reset()
	FORM = {}
	LAST_REDIRECT = nil
	LAST_WRITE = nil
	core_reset()
end

local function has_err()
	return type(LAST_REDIRECT) == "string" and LAST_REDIRECT:find("err=", 1, true) ~= nil
end

-- 所有 action 的入口清单（带一组能走到底的合法表单）
local ACTIONS = {
	{ "action_create", { token = "t", name = "n", url = "http://e.com/s" } },
	{ "action_save", { token = "t", id = "s00000001", name = "n", url = "http://e.com/s" } },
	{ "action_local_create", { token = "t", name = "n", content = "vmess://x" } },
	{ "action_local_save", { token = "t", id = "s00000001", name = "n", content = "vmess://x" } },
	{ "action_delete", { token = "t", id = "s00000001" } },
	{ "action_node_save", { token = "t", id = "s00000001", idx = "1", content = "[]" } },
	{ "action_node_delete", { token = "t", id = "s00000001", idx = "1" } },
	{ "action_node_set_group", { token = "t", id = "s00000001", idx = "1", group = "g" } },
	{ "action_combo_save", { token = "t", name = "n" } },
	{ "action_update", { token = "t", id = "s00000001" } },
	{ "action_probe", { token = "t", id = "s00000001", mode = "ping" } },
	{ "action_download", { token = "t", target = "ClashMeta" } },
}

-- ---------- L3：每个字段都重复提交一次，action 不得抛错 ----------
-- 真实场景：POST body 里同名字段出现两次（表单里出现同名 input，
-- 或攻击者手工构造）。此时 formvalue 返回 {v1, v2}。
for _, a in ipairs(ACTIONS) do
	local action, form = a[1], a[2]
	reset()
	local dup = {}
	for k, v in pairs(form) do dup[k] = { v, v .. "2" } end
	FORM = dup
	local ok2, e = pcall(ctl[action])
	check(action .. " survives duplicated form fields" .. (ok2 and "" or (" (" .. tostring(e) .. ")")), ok2)
end

-- 同一个 action 里全部字段都重复（最坏情况）
reset()
FORM = {}
for k, v in pairs(ACTIONS[1][2]) do FORM[k] = { v, v } end
FORM.id = { "s00000001", "s00000002" }
local ok3, e3 = pcall(ctl.action_save)
check("action_save survives all-duplicated fields" .. (ok3 and "" or (" (" .. tostring(e3) .. ")")), ok3)

-- 重复字段取值语义：取最后一个（后者覆盖前者），而不是报错或取第一个
reset()
FORM = { token = "t", id = "s00000001", name = { "first", "second" }, url = "http://e.com/s" }
local seen_name = nil
CORE.save_meta = function(_, patch) seen_name = patch.name; return true end
pcall(ctl.action_save)
check("duplicated field keeps last value", seen_name == "second")

-- ---------- L4：失败必须回显 ----------
-- action_delete：core.remove 返回 false
reset()
CORE.remove = function() return false, "订阅不存在" end
FORM = { token = "t", id = "s00000001" }
ctl.action_delete()
check("delete failure reports error", has_err())

-- action_delete：成功路径不带 err
reset()
FORM = { token = "t", id = "s00000001" }
ctl.action_delete()
check("delete success has no err", not has_err())

-- ---------- 勾选批量删除：id 支持逗号分隔多个 ----------
-- 行内删除按钮提交单个 id（上面两条覆盖）；表头的「删除」按钮把勾选的多个
-- id 用逗号拼起来提交，走同一个 action —— 与节点页 action_node_delete 的
-- idx 是同一套约定。
reset()
local seen_ids = {}
CORE.remove = function(id) seen_ids[#seen_ids + 1] = id; return true end
FORM = { token = "t", id = "s00000001,s00000002,s00000003" }
ctl.action_delete()
check("multi delete removes every id",
	#seen_ids == 3 and seen_ids[1] == "s00000001" and seen_ids[3] == "s00000003")
check("multi delete success has no err", not has_err())

-- 逗号两侧的空格不影响切分（浏览器不会加空格，手工构造 / 复制粘贴会）
reset()
seen_ids = {}
CORE.remove = function(id) seen_ids[#seen_ids + 1] = id; return true end
FORM = { token = "t", id = " s00000001 , s00000002 " }
ctl.action_delete()
check("delete tolerates spaces around ids",
	#seen_ids == 2 and seen_ids[1] == "s00000001" and seen_ids[2] == "s00000002")

-- 批量删除成功后写一次 cron：删掉的订阅不能继续留在 /etc/cron.d/substore 里
-- 断言里同时数 core.remove 的调用次数：只断言 write_cron 的话，改动前的实现
-- （把整串 id 当成一个 id 传下去）也会通过 —— stub 对任何 id 都返回 true。
reset()
local cron_writes, rm_calls = 0, {}
CORE.remove = function(id) rm_calls[#rm_calls + 1] = id; return true end
CORE.write_cron = function() cron_writes = cron_writes + 1 end
FORM = { token = "t", id = "s00000001,s00000002" }
ctl.action_delete()
check("multi delete rewrites cron once after removing both",
	cron_writes == 1 and #rm_calls == 2)

-- 部分失败必须回显：勾了 3 个只删掉 1 个，不能显示成「成功」。
-- 同样要数调用次数，否则改动前的实现也会「通过」。
--
-- 同时断言 cron 被重写：删掉的那 1 个订阅的 cron 行必须清掉，
-- 否则 substore-cron.sh 会拿着已不存在的 id 反复失败（退出码非 0）。
reset()
local partial_calls, partial_cron = 0, 0
CORE.remove = function(id) partial_calls = partial_calls + 1; return id == "s00000001" end
CORE.write_cron = function() partial_cron = partial_cron + 1 end
FORM = { token = "t", id = "s00000001,s00000002,s00000003" }
ctl.action_delete()
check("partial delete attempts every id and reports error",
	has_err() and partial_calls == 3)
check("partial delete rewrites cron for the removed ones", partial_cron == 1)

-- 全部失败：一个都没删掉 → 没有任何订阅的 cron 行需要清理，不重写
reset()
local none_cron = 0
CORE.remove = function() return false, "订阅不存在" end
CORE.write_cron = function() none_cron = none_cron + 1 end
FORM = { token = "t", id = "s00000001,s00000002" }
ctl.action_delete()
check("all-failed delete does not rewrite cron", none_cron == 0)

-- 全部失败：回显 core.remove 给出的原因
reset()
CORE.remove = function() return false, "订阅不存在" end
FORM = { token = "t", id = "s00000001,s00000002" }
ctl.action_delete()
check("all-failed delete reports core reason", has_err())

-- 一个可用 id 都没有：不能静默跳回（否则用户以为删了）
reset()
FORM = { token = "t", id = "  ,  " }
ctl.action_delete()
check("delete with no usable id reports error", has_err())

-- 只有分隔符的 id 不得被当成「一个叫 ',' 的订阅」交给 core
reset()
local called = 0
CORE.remove = function() called = called + 1; return true end
FORM = { token = "t", id = ",,," }
ctl.action_delete()
check("delete does not pass empty ids to core", called == 0)

-- action_combo_save：名称为空
reset()
FORM = { token = "t", name = "" }
ctl.action_combo_save()
check("combo_save empty name reports error", has_err())

-- action_combo_save：add_combo 失败
reset()
CORE.add_combo = function() return nil, "请选择至少一个订阅" end
FORM = { token = "t", name = "n" }
ctl.action_combo_save()
check("combo_save create failure reports error", has_err())

-- action_combo_save：save_combo 失败
reset()
CORE.save_combo = function() return nil, "非法 ID" end
FORM = { token = "t", id = "s00000001", name = "n" }
ctl.action_combo_save()
check("combo_save update failure reports error", has_err())

-- action_combo_save：成功路径不带 err
reset()
FORM = { token = "t", name = "n" }
ctl.action_combo_save()
check("combo_save success has no err", not has_err())

-- action_update：订阅不存在
reset()
CORE.get = function() return nil end
FORM = { token = "t", id = "s00000001" }
ctl.action_update()
check("update missing subscription reports error", has_err())

-- action_update：sync 失败仍然写回 error（原有行为，加守卫）
reset()
local written = nil
CORE.sync = function() return nil, "无法识别的订阅格式" end
CORE.save_meta = function(_, patch) written = patch; return true end
FORM = { token = "t", id = "s00000001" }
ctl.action_update()
check("update sync failure writes error to meta",
	written ~= nil and written.error == "无法识别的订阅格式")

-- action_node_delete：没有可解析的下标
reset()
FORM = { token = "t", id = "s00000001", idx = "abc" }
ctl.action_node_delete()
check("node_delete no valid idx reports error", has_err())

-- action_node_delete：下标越界（节点不存在）
reset()
CORE.read_nodes = function() return { { name = "only" } } end
FORM = { token = "t", id = "s00000001", idx = "9" }
ctl.action_node_delete()
check("node_delete out-of-range idx reports error", has_err())

-- action_node_delete：写盘失败
reset()
CORE.read_nodes = function() return { { name = "a" }, { name = "b" } } end
CORE.write_nodes = function() return false end
FORM = { token = "t", id = "s00000001", idx = "1" }
ctl.action_node_delete()
check("node_delete write failure reports error", has_err())

-- action_node_delete：成功路径不带 err
reset()
CORE.read_nodes = function() return { { name = "a" }, { name = "b" } } end
FORM = { token = "t", id = "s00000001", idx = "1" }
ctl.action_node_delete()
check("node_delete success has no err", not has_err())

-- ---------- M28：CSRF token 必须真的校验 ----------
-- 上游 LuCI 渲染表单时模板变量 `token` 就是 luci.dispatcher.context.authtoken
-- （luci-lua-runtime/luasrc/template.lua 的 viewns 元表），
-- 所以「提交的 token == authtoken」正是框架自己那套判定，不会误拒合法表单。
-- 此前的判定是 `token ~= nil`：`token=`（空串）也能通过，等于没有校验。
_G.luci.dispatcher.context = { authtoken = "secret" }

-- 合法表单必须照常通过（这条是关键：改了校验不能把正常提交挡在门外）
reset()
local ok_calls = 0
CORE.remove = function() ok_calls = ok_calls + 1; return true end
FORM = { token = "secret", id = "s00000001" }
ctl.action_delete()
check("M28 valid token accepted", ok_calls == 1 and not has_err())

-- 空串 token：此前被 `~= nil` 放过，现在必须拒绝
reset()
local empty_calls = 0
CORE.remove = function() empty_calls = empty_calls + 1; return true end
FORM = { token = "", id = "s00000001" }
ctl.action_delete()
check("M28 empty token rejected", empty_calls == 0)
check("M28 empty token reports error", has_err())

-- 不匹配的 token 同样拒绝
reset()
local bad_calls = 0
CORE.remove = function() bad_calls = bad_calls + 1; return true end
FORM = { token = "wrong", id = "s00000001" }
ctl.action_delete()
check("M28 mismatched token rejected", bad_calls == 0)
check("M28 mismatched token reports error", has_err())

-- 校验失败必须对所有动作生效（此前 9 个动作都是静默重定向）
reset()
local created = 0
CORE.add = function() created = created + 1; return "s0000000a" end
FORM = { token = "", name = "n", url = "http://e.com/s" }
ctl.action_create()
check("M28 create rejects empty token", created == 0 and has_err())

reset()
local updated = 0
CORE.sync = function() updated = updated + 1; return true end
FORM = { token = "wrong", id = "s00000001" }
ctl.action_update()
check("M28 update rejects bad token", updated == 0 and has_err())

-- 节点页动作走 back_to_nodes，同样要带 err
reset()
local wrote = 0
CORE.read_nodes = function() return { { name = "a" } } end
CORE.write_nodes = function() wrote = wrote + 1; return true end
FORM = { token = "", id = "s00000001", idx = "1", content = "[]" }
ctl.action_node_save()
check("M28 node_save rejects empty token",
	wrote == 0 and LAST_REDIRECT:find("err=", 1, true) ~= nil)

-- 取不到 authtoken（老版本 LuCI / 非标准上下文）时退回原判定，
-- 不能因为拿不到框架内部字段就把所有表单都拒掉。
_G.luci.dispatcher.context = nil
reset()
local legacy_calls = 0
CORE.remove = function() legacy_calls = legacy_calls + 1; return true end
FORM = { token = "t", id = "s00000001" }
ctl.action_delete()
check("M28 falls back when authtoken unavailable",
	legacy_calls == 1 and not has_err())

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
