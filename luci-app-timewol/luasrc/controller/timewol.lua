-- Copyright (C) 2025 LWB1978

module("luci.controller.timewol", package.seeall)

local http = require "luci.http"
local uci = require "luci.model.uci".cursor()
local sys = require "luci.sys"
local json = require "luci.jsonc"
local util = require "luci.util"

function index()
	if not nixio.fs.access("/etc/config/timewol") then return end

	entry({"admin", "control"}, firstchild(), "Control", 44).dependent = false

	local page = entry({"admin", "control", "timewol"}, cbi("timewol"), _("Timed WOL"))
	page.order = 95
	page.dependent = true
	page.acl_depends = { "luci-app-timewol" }

	entry({"admin", "control", "timewol", "status"}, call("status")).leaf = true

	entry({"admin", "control", "timewol", "wakeup"}, call("wakeup")).leaf = true
end

local function http_write_json(content)
	http.prepare_content("application/json")
	http.write(json.stringify(content or {code = 1}))
end

function status()
	local e = {}
	e.status = sys.call("grep -v '^[ \t]*#' /etc/crontabs/root | grep etherwake >/dev/null") == 0
	http_write_json(e)
end

function wakeup()
	uci:revert("timewol")
	local section = http.formvalue("section") or ""
	if section == "" then
		http_write_json({ success = false, msg = "Missing section" })
		return
	end
	local maceth = uci:get("timewol", section, "maceth") or ""
	local macaddr = uci:get("timewol", section, "macaddr") or ""
	if maceth == "" or macaddr == "" then
		http_write_json({ success = false, msg = "Missing MAC or interface" })
		return
	end
	local cmd = string.format(
		"/usr/bin/etherwake -D -i %s %s",
		util.shellquote(maceth),
		util.shellquote(macaddr)
	)
	if sys.call(cmd) ~= 0 then
		http_write_json({ success = false, msg = "Wake failed" })
		return
	end
	http_write_json({ success = true })
end
