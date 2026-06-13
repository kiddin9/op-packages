module("luci.controller.gecoosac", package.seeall)

local fs = require "nixio.fs"
local sys = require "luci.sys"
local uci = require "luci.model.uci"

local ACL_DEPENDS = { "luci-app-gecoosac" }

local function service_running()
	if not fs.access("/etc/init.d/gecoosac") then
		return false
	end

	return sys.call("/etc/init.d/gecoosac status >/dev/null 2>&1") == 0
end

function index()
	if not fs.access("/etc/config/gecoosac") then
		return
	end
	local page
	page = entry({"admin", "services", "gecoosac"}, cbi("gecoosac"), _("Gecoos AC"), 100)
	page.dependent = true
	page.acl_depends = ACL_DEPENDS
	page = entry({"admin", "services", "gecoosac", "status"}, call("act_status"))
	page.leaf = true
	page.acl_depends = ACL_DEPENDS
end

function act_status()
	local cur = uci.cursor()
	local enabled = cur:get("gecoosac", "config", "enabled") == "1"
	local e = {
		enabled = enabled,
		running = enabled and service_running()
	}
	luci.http.prepare_content("application/json")
	luci.http.write_json(e)
end
