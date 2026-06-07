
module("luci.controller.gecoosac", package.seeall)

local fs = require "nixio.fs"
local sys = require "luci.sys"
local uci = require "luci.model.uci"

function index()
	if not fs.access("/etc/config/gecoosac") then
		return
	end
	local page
	page = entry({"admin", "services", "gecoosac"}, cbi("gecoosac"), _("Gecoos AC"), 100)
	page.dependent = true
	page = entry({"admin", "services", "gecoosac", "status"}, call("act_status"))
	page.leaf = true
end

function act_status()
	local cur = uci.cursor()
	local enabled = cur:get("gecoosac", "config", "enabled") == "1"
	local e = {
		running = enabled and sys.call("pidof gecoosac >/dev/null 2>&1") == 0
	}
	luci.http.prepare_content("application/json")
	luci.http.write_json(e)
end
