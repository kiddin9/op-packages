-- dnsguard.lua —— LuCI 控制器：DNS 防绕过（53 透明重定向 / 观察计数 / 853·DoH 阻断 / 健康自检 / 回滚）
--
-- 实现方式与同机第三方应用 luci-app-lmclient、以及本机 luci-app-routerreport 一致：
--   控制器只做「校验参数 -> uci set/commit -> 调本机脚本」，真正写防火墙的动作全在 dnsguard-apply 里。
-- 生成：WorkBuddy  2026-09-26

module("luci.controller.dnsguard", package.seeall)

local sys  = require "luci.sys"
local http = require "luci.http"
local uci  = require "luci.model.uci".cursor()

local APPLY    = "/usr/bin/dnsguard-apply"
local SELFTEST = "/usr/bin/dnsguard-selftest"
local ROLLBACK = "/usr/bin/dnsguard-rollback"
local NFTPREV  = "/tmp/dg-preview.nft"
local LOGFILE  = "/mnt/data/logs/messages"
local NFTOUT   = "/etc/nftables.d/20-dns-guard.nft"

-- ---------- 小工具 ----------

local function jesc(s)
	s = tostring(s or "")
	s = s:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\r", "")
	s = s:gsub("\n", "\\n"):gsub("\t", " ")
	return s
end

local function jstr(s) return '"' .. jesc(s) .. '"' end

local function num(s) return tonumber(s or "") or 0 end

local function exec(cmd)
	local out = sys.exec(cmd .. " 2>/dev/null")
	return out or ""
end

local function trim(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end

local function json_out(s)
	http.prepare_content("application/json")
	http.write(s)
	return
end

local function fv(name, maxlen)
	local v = http.formvalue(name)
	if v == nil then return nil end
	v = v:gsub("[\r\n\t]", " ")
	if maxlen and #v > maxlen then v = v:sub(1, maxlen) end
	return v
end

-- 只保留 IP/CIDR 里合法出现的字符（写入 nft 前的第一道清洗；dnsguard-apply 里还有第二道）
-- ⚠️ 白名单必须含 `/`，否则 CIDR 会被洗成 192.168.1.024 这种怪物（联调时真踩到过）
local function clean_set(s)
	s = tostring(s or "")
	return trim(s:gsub("[^%w%.%:%-/%s%,]", ""))
end

-- 接口名：字母数字点下划线连字符 + 空格
local function clean_ifaces(s)
	s = tostring(s or "")
	return trim(s:gsub("[^%w%._%-%s]", ""))
end

local function digits(s)
	s = tostring(s or "")
	return s:gsub("[^%d]", "")
end

-- ---------- 菜单 ----------

function index()
	entry({ "admin", "services", "dnsguard" },
		template("dnsguard/main"), _("DNS 防绕过"), 82).acl_depends = { "luci-app-dnsguard" }
	entry({ "admin", "services", "dnsguard", "api" },
		call("action_api"), nil).acl_depends = { "luci-app-dnsguard" }
end

-- ---------- 动作分发 ----------

function action_api()
	local action = fv("action") or ""
	if not action:match("^[%w_]+$") then
		return json_out('{"status":"error","message":"invalid action"}')
	end
	if action == "save" then
		return action_save()
	elseif action == "apply" then
		return action_apply()
	elseif action == "status" then
		return action_status()
	elseif action == "selftest" then
		return action_selftest()
	elseif action == "rules" then
		return action_rules()
	elseif action == "disarm" then
		return action_rollback_cmd("--disarm", "")
	elseif action == "rollback" then
		return action_restore()
	end
	return json_out('{"status":"error","message":"unknown action"}')
end

-- ---------- 保存配置 ----------

function action_save()
	local function flag(n) return (fv(n) == "1") and "1" or "0" end

	local new_enabled  = flag("enabled")
	local new_redirect = flag("redirect53")
	local watch        = flag("watch")
	local block853     = flag("block853")
	local blockdoh     = flag("blockdoh")

	local target_port  = digits(fv("target_port", 6))
	local log_limit    = digits(fv("log_limit", 4))
	local roll_min     = digits(fv("rollback_minutes", 4))
	local ifaces       = clean_ifaces(fv("ifaces", 200))
	local skip         = clean_set(fv("skip_devices", 400))
	local nh4          = clean_set(fv("never_hijack4", 600))
	local nh6          = clean_set(fv("never_hijack6", 600))
	local doh          = clean_set(fv("doh_servers", 900))

	-- 校验
	if target_port == "" or num(target_port) < 1 or num(target_port) > 65535 then
		return json_out('{"status":"error","message":"重定向目标端口必须是 1-65535 的数字"}')
	end
	if ifaces == "" then
		return json_out('{"status":"error","message":"入接口不能为空（默认 br-lan）"}')
	end
	if log_limit == "" then log_limit = "5" end
	if num(log_limit) < 1 or num(log_limit) > 999 then
		return json_out('{"status":"error","message":"日志限速必须是 1-999（每分钟条数）"}')
	end
	if roll_min == "" then roll_min = "10" end
	if num(roll_min) < 1 or num(roll_min) > 120 then
		return json_out('{"status":"error","message":"自动回滚倒计时必须是 1-120 分钟"}')
	end

	local c = uci
	local OLD_REDIRECT = c:get("dnsguard", "main", "redirect53") or "0"

	c:set("dnsguard", "main", "enabled", new_enabled)
	c:set("dnsguard", "main", "redirect53", new_redirect)
	c:set("dnsguard", "main", "watch", watch)
	c:set("dnsguard", "main", "block853", block853)
	c:set("dnsguard", "main", "blockdoh", blockdoh)
	c:set("dnsguard", "main", "target_port", target_port)
	c:set("dnsguard", "main", "ifaces", ifaces)
	c:set("dnsguard", "main", "skip_devices", skip)
	c:set("dnsguard", "main", "log_limit", log_limit)
	c:set("dnsguard", "main", "rollback_minutes", roll_min)

	c:set("dnsguard", "limits", "never_hijack4", nh4)
	c:set("dnsguard", "limits", "never_hijack6", nh6)
	c:set("dnsguard", "limits", "doh_servers", doh)
	c:commit("dnsguard")

	-- 关 -> 开 的那一刻，自动挂一个回滚倒计时（DNS 改错会让全家上不了网，留条后路）
	local armed = ""
	if new_enabled == "1" and new_redirect == "1" and OLD_REDIRECT ~= "1" then
		local r = exec(ROLLBACK .. " --arm " .. roll_min)
		if r:match('"ts":"([%d%-]+)"') then
			armed = r:match('"ts":"([%d%-]+)"')
		end
	end

	-- 渲染并应用
	local out = trim(exec(APPLY))
	local j = out:match("({.*})")
	if not j then
		return json_out('{"status":"error","message":"配置已保存，但应用失败：' .. jesc(out) .. '"}')
	end

	local st  = j:match('"status":"([%w]+)"') or "error"
	local msg = j:match('"message":"(.-)","enabled"') or ""

	if st ~= "ok" then
		return json_out('{"status":"error","message":' .. jstr(msg) .. ',"apply":' .. jstr(j) .. '}')
	end

	local red_ok  = (j:match('"redirect_active":"(%d)"') == "1")
	local file_st = j:match('"file":"([%w]+)"') or ""

	local head = "配置已保存"
	if file_st == "unchanged" then
		head = head .. "（规则无变化，未重载防火墙）"
	else
		head = head .. "并生效"
	end
	head = head .. " · 53 重定向：" .. ((new_enabled == "1" and new_redirect == "1") and (red_ok and "已生效" or "未生效") or "关闭")

	if armed ~= "" then
		head = head .. " · 已挂 " .. roll_min .. " 分钟自动回滚（快照 " .. armed .. "），未确认将自动还原"
	end

	return json_out('{"status":"ok","message":' .. jstr(head) ..
		',"at":' .. jstr(os.date("%H:%M:%S")) ..
		',"armed":' .. jstr(armed) ..
		',"redirect_active":' .. (red_ok and "true" or "false") ..
		',"apply":' .. jstr(j) .. '}')
end

-- ---------- 只重新应用（不改配置）----------

function action_apply()
	local out = trim(exec(APPLY .. " --quiet"))
	local j = out:match("({.*})")
	if not j then
		return json_out('{"status":"error","message":"应用失败：' .. jesc(out) .. '"}')
	end
	local st  = j:match('"status":"([%w]+)"') or "error"
	local msg = j:match('"message":"(([^"\\]|\\.)*)"') or ""
	if st ~= "ok" then
		return json_out('{"status":"error","message":' .. jstr(msg) .. ',"apply":' .. jstr(j) .. '}')
	end
	return json_out('{"status":"ok","message":' .. jstr(msg) ..
		',"at":' .. jstr(os.date("%H:%M:%S")) .. ',"apply":' .. jstr(j) .. '}')
end

-- ---------- 状态 ----------

local function nft_chain_summary(name)
	local t = exec("nft list chain inet fw4 " .. name)
	local active = t:find("chain " .. name) ~= nil
	local pk, by, list = 0, 0, {}
	for a, b in t:gmatch("counter packets (%d+) bytes (%d+)") do
		pk = pk + num(a); by = by + num(b)
		list[#list + 1] = '{"packets":' .. num(a) .. ',"bytes":' .. num(b) .. '}'
	end
	return active, pk, by, "[" .. table.concat(list, ",") .. "]"
end

function action_status()
	local c = uci
	local function g(sec, opt, def)
		local v = c:get("dnsguard", sec, opt)
		if v == nil or v == "" then return def or "" end
		return v
	end

	local agh = trim(exec("pidof AdGuardHome"))
	local listen = trim(exec("netstat -lntup 2>/dev/null | grep ':53 ' | head -2 | tr -s ' ' ' '"))

	local r_active, r_pk, r_by, r_list = nft_chain_summary("dns_guard_redirect")
	local o_active, o_pk, o_by, o_list = nft_chain_summary("dns_guard_pre_forward")
	local b_active = nft_chain_summary("dns_guard_block")

	-- 规则文件是否由本应用托管
	local managed = "0"
	local mtime = ""
	local fh = io.open(NFTOUT, "r")
	if fh then
		local body = fh:read("*a") or ""
		fh:close()
		if body:find("DNS 防绕过", 1, true) then managed = "1" end
	end
	mtime = trim(exec("stat -c '%y' " .. NFTOUT .. " 2>/dev/null | cut -c1-19"))

	-- 观察日志条数
	local logs = trim(exec("grep -c 'DNS-BYPASS' " .. LOGFILE))

	-- 回滚状态
	local rb = exec(ROLLBACK .. " --status")
	local pending = (rb:find('"pending":true', 1, true) ~= nil)
	local pts = rb:match('"pending_ts":"([%d%-]*)"') or ""
	local pleft = num(rb:match('"pending_left":(%d+)'))
	local backups = rb:match('"backups":%[([^%]]*)%]') or ""

	local resp = {
		'{"status":"ok"',
		'"enabled":' .. jstr(g("main", "enabled", "0")),
		'"redirect53":' .. jstr(g("main", "redirect53", "0")),
		'"watch":' .. jstr(g("main", "watch", "0")),
		'"block853":' .. jstr(g("main", "block853", "0")),
		'"blockdoh":' .. jstr(g("main", "blockdoh", "0")),
		'"target_port":' .. jstr(g("main", "target_port", "53")),
		'"ifaces":' .. jstr(g("main", "ifaces", "br-lan")),
		'"skip_devices":' .. jstr(g("main", "skip_devices", "")),
		'"log_limit":' .. jstr(g("main", "log_limit", "5")),
		'"rollback_minutes":' .. jstr(g("main", "rollback_minutes", "10")),
		'"never_hijack4":' .. jstr(g("limits", "never_hijack4", "")),
		'"never_hijack6":' .. jstr(g("limits", "never_hijack6", "")),
		'"doh_servers":' .. jstr(g("limits", "doh_servers", "")),
		'"agh_pid":' .. jstr(agh),
		'"listen53":' .. jstr(listen),
		'"redirect_active":' .. (r_active and "true" or "false"),
		'"redirect_packets":' .. r_pk,
		'"redirect_bytes":' .. r_by,
		'"redirect_rules":' .. r_list,
		'"watch_active":' .. (o_active and "true" or "false"),
		'"watch_packets":' .. o_pk,
		'"watch_bytes":' .. o_by,
		'"watch_rules":' .. o_list,
		'"block_active":' .. (b_active and "true" or "false"),
		'"managed":' .. jstr(managed),
		'"file_mtime":' .. jstr(mtime),
		'"bypass_lines":' .. jstr(logs),
		'"pending":' .. (pending and "true" or "false"),
		'"pending_ts":' .. jstr(pts),
		'"pending_left":' .. pleft,
		'"backups":[' .. backups .. ']'
	}
	return json_out(table.concat(resp, ",") .. "}")
end

-- ---------- 健康自检 ----------

function action_selftest()
	local out = trim(exec(SELFTEST))
	local j = out:match("({.*})")
	if not j then
		return json_out('{"status":"error","message":"自检脚本执行失败","raw":' .. jstr(out) .. '}')
	end
	return json_out(j)
end

-- ---------- 预览将要生成的规则 ----------

function action_rules()
	exec(APPLY .. " --render-only --out " .. NFTPREV .. " --quiet")
	local fh = io.open(NFTPREV, "r")
	local text = ""
	if fh then
		text = fh:read("*a") or ""
		fh:close()
	end
	if text == "" then
		return json_out('{"status":"error","message":"渲染预览失败：未取到内容（请查看 dnsguard-apply 是否可执行）"}')
	end
	local n = select(2, text:gsub("\n", "\n"))
	return json_out('{"status":"ok","lines":' .. n .. ',"text":' .. jstr(text) .. '}')
end

-- ---------- 取消自动回滚（确认保留）----------

function action_rollback_cmd(opt, extra)
	local out = trim(exec(ROLLBACK .. " " .. opt .. " " .. extra))
	local j = out:match("({.*})")
	if not j then
		return json_out('{"status":"error","message":' .. jstr(out) .. '}')
	end
	return json_out(j)
end

-- ---------- 还原到指定回滚点 ----------

function action_restore()
	local ts = fv("ts", 40) or ""
	if ts ~= "latest" and not ts:match("^[%d%-]+$") then
		return json_out('{"status":"error","message":"时间戳格式不正确"}')
	end
	local out = trim(exec(ROLLBACK .. " " .. ts))
	return json_out('{"status":"ok","message":' .. jstr(out ~= "" and out or ("已回滚到 " .. ts)) ..
		',"at":' .. jstr(os.date("%H:%M:%S")) .. '}')
end
