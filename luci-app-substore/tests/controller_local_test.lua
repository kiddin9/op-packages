-- controller_local_test.lua — 控制器错误反馈回归测试（§18/§19）
-- 用法：lua5.1 tests/controller_local_test.lua
--
-- 不需要真实 LuCI：用最小 stub 提供 luci.http / luci.dispatcher / luci.util，
-- 把 substore.core 换成可控的假实现，然后直接调用控制器的 action_* 函数，
-- 断言「失败必须体现在 redirect 的 ?err= 上」，而不是静默跳回列表页。

package.path = "./root/usr/share/?.lua;" .. package.path

local passed, failed = 0, 0
local function check(name, cond)
	if cond then passed = passed + 1; print("PASS " .. name)
	else failed = failed + 1; print("FAIL " .. name) end
end

-- ---------- luci stub ----------
local FORM = {}          -- formvalue 数据
local LAST_REDIRECT = nil
local URLENC = {}

_G.luci = {
	http = {
		formvalue = function(k) return FORM[k] end,
		redirect = function(url) LAST_REDIRECT = url end,
	},
	dispatcher = {
		build_url = function(...)
			local t = { ... }
			return "/" .. table.concat(t, "/")
		end,
	},
	util = {
		urlencode = function(s)
			s = tostring(s or "")
			URLENC[#URLENC + 1] = s
			return (s:gsub("[^%w%-%._~]", function(c)
				return string.format("%%%02X", string.byte(c))
			end))
		end,
		pcdata = function(s) return tostring(s or "") end,
	},
	i18n = { translate = function(s) return s end },
}
_G.luci.controller = { admin = {} }

-- 控制器内部用的是 require("luci.http") 而非全局，因此同时登记进 package.loaded
package.loaded["luci.http"] = _G.luci.http
package.loaded["luci.dispatcher"] = _G.luci.dispatcher
package.loaded["luci.util"] = _G.luci.util
package.loaded["luci.i18n"] = _G.luci.i18n

-- ---------- substore.core stub ----------
local CORE_RESULT = { add_local = { "s00000001" }, save_meta = { true }, sync = { true } }
local SYNC_CALLS = 0

package.loaded["substore.core"] = {
	add_local = function() return CORE_RESULT.add_local[1], CORE_RESULT.add_local[2] end,
	save_meta = function() return CORE_RESULT.save_meta[1], CORE_RESULT.save_meta[2] end,
	sync = function() SYNC_CALLS = SYNC_CALLS + 1; return CORE_RESULT.sync[1], CORE_RESULT.sync[2] end,
	write_cron = function() end,
	cron_time_valid = function() return true end,
}

-- 载入控制器（module() 会在 package.loaded 里建表，不需要真实 luci 模块）
-- 路径可用 SUBSTORE_CONTROLLER 覆盖，便于对「修复前」的副本跑同一套断言
local CTL_PATH = os.getenv("SUBSTORE_CONTROLLER")
	or "root/usr/lib/lua/luci/controller/admin/substore.lua"
local ok, err = pcall(dofile, CTL_PATH)
check("controller loads under stub", ok)
if not ok then print("  load error: " .. tostring(err)) end
local ctl = package.loaded["luci.controller.admin.substore"] or {}

local function reset()
	FORM = {}
	LAST_REDIRECT = nil
	CORE_RESULT.add_local = { "s00000001" }
	CORE_RESULT.save_meta = { true }
	CORE_RESULT.sync = { true }
	SYNC_CALLS = 0
end

local function has_err()
	return type(LAST_REDIRECT) == "string" and LAST_REDIRECT:find("err=", 1, true) ~= nil
end

-- ---------- §19 空名称 / 空内容 ----------
reset()
FORM = { token = "t", name = "", content = "vmess://x" }
ctl.action_local_create()
check("local_create empty name redirects", type(LAST_REDIRECT) == "string")
check("local_create empty name reports error", has_err())
check("local_create empty name does not create", CORE_RESULT.add_local[1] == "s00000001" and SYNC_CALLS == 0)

reset()
FORM = { token = "t", name = "test", content = "" }
ctl.action_local_create()
check("local_create empty content reports error", has_err())

reset()
FORM = { token = "t", name = "", content = "" }
ctl.action_local_create()
check("local_create both empty reports error", has_err())

-- ---------- §18 core 失败必须传到 UI ----------
reset()
CORE_RESULT.add_local = { nil, "写入失败" }
FORM = { token = "t", name = "ok", content = "vmess://x" }
ctl.action_local_create()
check("local_create core failure redirects", type(LAST_REDIRECT) == "string")
check("local_create core failure reports error", has_err())
check("local_create core failure surfaces reason",
	LAST_REDIRECT:find("err=", 1, true) ~= nil and URLENC[#URLENC] == "写入失败")

-- local_save: save_meta 失败
reset()
CORE_RESULT.save_meta = { nil, "订阅不存在" }
FORM = { token = "t", id = "s00000001", name = "ok", content = "vmess://x" }
ctl.action_local_save()
check("local_save save failure reports error", has_err())
check("local_save save failure surfaces reason", URLENC[#URLENC] == "订阅不存在")
check("local_save save failure skips sync", SYNC_CALLS == 0)

-- local_save: sync 失败（解析失败）
reset()
CORE_RESULT.sync = { nil, "无法识别的订阅格式" }
FORM = { token = "t", id = "s00000001", name = "ok", content = "garbage" }
ctl.action_local_save()
check("local_save sync failure reports error", has_err())
check("local_save sync failure surfaces reason", URLENC[#URLENC] == "无法识别的订阅格式")
check("local_save sync was attempted", SYNC_CALLS == 1)

-- local_save: 缺 id
reset()
FORM = { token = "t", id = "", name = "ok", content = "vmess://x" }
ctl.action_local_save()
check("local_save missing id reports error", has_err())

-- ---------- 成功路径：不应带 err ----------
reset()
FORM = { token = "t", name = "ok", content = "vmess://x" }
ctl.action_local_create()
check("local_create success redirects", type(LAST_REDIRECT) == "string")
check("local_create success has no err", not has_err())

reset()
FORM = { token = "t", id = "s00000001", name = "ok", content = "vmess://x" }
ctl.action_local_save()
check("local_save success has no err", not has_err())
check("local_save success ran sync", SYNC_CALLS == 1)

-- ---------- 无 CSRF token：不做任何事，也不报错 ----------
reset()
FORM = { name = "", content = "" }
ctl.action_local_create()
check("no token still redirects", type(LAST_REDIRECT) == "string")
check("no token no error banner", not has_err())

-- ---------- §18 单节点保存：解析/写入失败必须可见 ----------
-- 修复前 action_node_save 只在成功分支做事，其余情况一律静默重定向，
-- 用户提交了坏数据却看到「已保存」的样子。
local NODES = {}
local WRITE_CALLS = 0
local CORE_STUB = package.loaded["substore.core"]
CORE_STUB.read_nodes = function() return NODES end
CORE_STUB.write_nodes = function(_, ns)
	WRITE_CALLS = WRITE_CALLS + 1
	NODES = ns
	return true
end
CORE_STUB.refresh_combos = function() end
-- 真实的 merge_form_node 在 substore.core 里（会碰 /etc/substore），这里只要
-- 「表单字段覆盖原节点」的语义即可
CORE_STUB.merge_form_node = function(orig, form)
	local out = {}
	for k, v in pairs(orig or {}) do out[k] = v end
	for k, v in pairs(form or {}) do out[k] = v end
	return out
end

local VALID_NODE = '[{"type":"vmess","server":"1.2.3.4","port":"443","uuid":"u1"}]'

reset()
NODES = { { name = "old", proto = "vmess", server = "1.2.3.4", port = 443 } }
WRITE_CALLS = 0
FORM = { token = "t", id = "s00000001", idx = "1", content = VALID_NODE }
ctl.action_node_save()
check("node_save valid writes", WRITE_CALLS == 1)
check("node_save valid has no err", not has_err())

-- 解析失败：必须报错且不写盘
reset()
NODES = { { name = "old", proto = "vmess", server = "1.2.3.4", port = 443 } }
WRITE_CALLS = 0
FORM = { token = "t", id = "s00000001", idx = "1", content = "not json at all" }
ctl.action_node_save()
check("node_save bad json reports error", has_err())
check("node_save bad json does not write", WRITE_CALLS == 0)

-- 下标无效
reset()
NODES = { { name = "old" } }
WRITE_CALLS = 0
FORM = { token = "t", id = "s00000001", idx = "9", content = VALID_NODE }
ctl.action_node_save()
check("node_save bad idx reports error", has_err())
check("node_save bad idx does not write", WRITE_CALLS == 0)

-- 缺 idx
reset()
NODES = { { name = "old" } }
WRITE_CALLS = 0
FORM = { token = "t", id = "s00000001", content = VALID_NODE }
ctl.action_node_save()
check("node_save missing idx reports error", has_err())
check("node_save missing idx does not write", WRITE_CALLS == 0)

-- 空内容
reset()
NODES = { { name = "old" } }
WRITE_CALLS = 0
FORM = { token = "t", id = "s00000001", idx = "1", content = "" }
ctl.action_node_save()
check("node_save empty content reports error", has_err())
check("node_save empty content does not write", WRITE_CALLS == 0)

-- 写入失败
reset()
NODES = { { name = "old" } }
WRITE_CALLS = 0
CORE_STUB.write_nodes = function() WRITE_CALLS = WRITE_CALLS + 1; return false end
FORM = { token = "t", id = "s00000001", idx = "1", content = VALID_NODE }
ctl.action_node_save()
check("node_save write failure reports error", has_err())
check("node_save write failure surfaced reason", URLENC[#URLENC] == "写入节点数据失败")

-- 无 token：不做任何事，也不报错
reset()
NODES = { { name = "old" } }
WRITE_CALLS = 0
FORM = { id = "s00000001", idx = "1", content = VALID_NODE }
ctl.action_node_save()
check("node_save no token redirects", type(LAST_REDIRECT) == "string")
check("node_save no token no error banner", not has_err())
check("node_save no token does not write", WRITE_CALLS == 0)

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
