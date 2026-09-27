-- 控制器打桩测试 v2：直调 action_api，覆盖各分支（含「关->开自动挂回滚」）
-- 用 ssh router 'lua -' < 本文件 执行；不在设备上落任何文件
package.path = "/usr/lib/lua/?.lua;" .. package.path

local F = {}
local http = require "luci.http"
local cap = {}
http.formvalue       = function(k) return F[k] end
http.prepare_content = function(t) cap.ct = t end
http.write           = function(s) cap.body = s end

local ucic = require("luci.model.uci").cursor()
local function cur(sec, opt) return ucic:get("dnsguard", sec, opt) or "" end

local ctrl = require "luci.controller.dnsguard"

local function run(name)
	cap.body = nil
	local ok, err = pcall(ctrl.action_api)
	print("###CASE:" .. name .. "###")
	if not ok then print("LUA_ERROR: " .. tostring(err)) else print(cap.body or "(nil)") end
	print("###END###")
end

local function clear() for k in pairs(F) do F[k] = nil end end

-- 用设备上当前值填表，避免测试数据漂移
local function fill(redirect)
	clear()
	F.action           = "save"
	F.enabled          = "1"
	F.redirect53       = redirect or cur("main", "redirect53")
	F.watch            = "1"
	F.block853         = "0"
	F.blockdoh         = "0"
	F.target_port      = cur("main", "target_port")
	F.ifaces           = cur("main", "ifaces")
	F.skip_devices     = cur("main", "skip_devices")
	F.log_limit        = cur("main", "log_limit")
	F.rollback_minutes = "1"
	F.never_hijack4    = cur("limits", "never_hijack4")
	F.never_hijack6    = cur("limits", "never_hijack6")
	F.doh_servers      = cur("limits", "doh_servers")
end

clear(); F.action = "status";   run("status")
clear(); F.action = "selftest"; run("selftest")
clear(); F.action = "rules";    run("rules")

fill();                        run("save-same")
fill("0");                     run("save-off")
fill("1");                     run("save-on-arm")     -- 这里应挂上回滚
clear(); F.action = "disarm";  run("disarm")

-- 校验分支
clear(); F.action="save"; F.target_port="70000"; run("bad-port")
clear(); F.action="save"; F.target_port="53"; F.ifaces=""; run("bad-iface")
clear(); F.action="save"; F.target_port="53"; F.ifaces="br-lan"; F.log_limit="0"; run("bad-loglimit")
clear(); F.action="save"; F.target_port="53"; F.ifaces="br-lan"; F.log_limit="5"; F.rollback_minutes="999"; run("bad-rollmin")
clear(); F.action="rollback"; F.ts="; rm -rf /";  run("bad-ts")
clear(); F.action="nope";                        run("unknown")
clear(); F.action="bad action!; x";              run("bad-action")
