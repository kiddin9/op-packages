-- core_userinfo_test.lua — subscription-userinfo 解析与人性化格式单元测试
-- 用法：lua5.1 tests/core_userinfo_test.lua

package.path = "./root/usr/share/?.lua;" .. package.path

local core = require("substore.core")
local util = require("substore.util")

local passed, failed = 0, 0
local function check(name, cond)
	if cond then passed = passed + 1; print("PASS " .. name)
	else failed = failed + 1; print("FAIL " .. name) end
end

-- ---------- parse_userinfo ----------
local u = core.parse_userinfo("upload=1024; download=2048; total=107374182400; expire=1757951999")
check("userinfo upload", u and u.upload == 1024)
check("userinfo download", u and u.download == 2048)
check("userinfo total", u and u.total == 107374182400)
check("userinfo expire", u and u.expire == 1757951999)

check("userinfo trim spaces", core.parse_userinfo("upload = 1 ; download=2") ~= nil)
check("userinfo empty nil", core.parse_userinfo("") == nil)
check("userinfo nonstring nil", core.parse_userinfo(nil) == nil)
check("userinfo no fields nil", core.parse_userinfo("foo=bar") == nil)
local u2 = core.parse_userinfo("total=100")
check("userinfo partial", u2 ~= nil and u2.total == 100 and u2.upload == nil)

-- ---------- human_bytes ----------
check("human_bytes zero", util.human_bytes(0) == "0B")
check("human_bytes 20G", util.human_bytes(20 * 1024 * 1024 * 1024) == "20G")
check("human_bytes 512M", util.human_bytes(512 * 1024 * 1024) == "512M")
check("human_bytes 1.5G", util.human_bytes(1.5 * 1024 * 1024 * 1024) == "1.5G")
check("human_bytes bytes", util.human_bytes(512) == "512B")
check("human_bytes negative", util.human_bytes(-5) == "0B")

-- ---------- human_duration ----------
-- 返回的是**语言中立的组合消息**（数字 + 单位 msgid，见 msg.lua）：后端不能
-- require("luci.i18n")，翻译由显示边界（view/substore/form.htm）逐段完成。
local msg = require("substore.msg")
local function S(s) return s end  -- 便于阅读：msgid 就是它自己
check("human_duration 10 days", util.human_duration(10 * 86400) == msg.compose(10, S(" days")))
check("human_duration 8 hours", util.human_duration(8 * 3600) == msg.compose(8, S(" hours")))
check("human_duration 30 minutes", util.human_duration(30 * 60) == msg.compose(30, S(" minutes")))
check("human_duration expired", util.human_duration(-1) == S("Expired"))
check("human_duration under minute", util.human_duration(30) == S("Less than a minute"))
-- 中文译文把单位 msgid 译成不带空格的 "天" —— 英文 "3 days" / 中文 "3天" 都成立
check("human_duration 中文渲染 10天",
	msg.translate(util.human_duration(10 * 86400), function(k)
		return ({ [" days"] = "天", [" hours"] = "小时", [" minutes"] = "分钟" })[k] or k
	end) == "10天")

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)