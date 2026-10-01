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
package.loaded["substore.node"] = {
	filter = function(ns) return ns end,
	sort = function(ns) return ns end,
}
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

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
