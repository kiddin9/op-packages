-- luci-app-hermes — LuCI Controller (18.06 compat)
module("luci.controller.hermes", package.seeall)

function index()
	-- luci 24.10+ uses menu.d JSON for registration; skip Lua menu
	if nixio.fs.access("/usr/share/luci/menu.d/luci-app-hermes.json") then
		return
	end

	local page = entry({"admin", "services", "hermes"},
		alias("admin", "services", "hermes", "basic"), _("Hermes Agent"), 90)
	page.dependent = false

	entry({"admin", "services", "hermes", "basic"},
		cbi("hermes"), _("Basic Settings"), 10).leaf = true
	entry({"admin", "services", "hermes", "console"},
		template("hermes/console"), _("Web Console"), 20).leaf = true
	entry({"admin", "services", "hermes", "terminal"},
		template("hermes/terminal"), _("Config Terminal"), 30).leaf = true

	-- API endpoints (used by status.htm XHR)
	entry({"admin", "services", "hermes", "status_api"},
		call("action_status"), nil).leaf = true
	entry({"admin", "services", "hermes", "service_ctl"},
		call("action_service_ctl"), nil).leaf = true
	entry({"admin", "services", "hermes", "get_token"},
		call("action_get_token"), nil).leaf = true
end

-- ── Status API ──
function action_status()
	local http = require "luci.http"
	local sys  = require "luci.sys"

	local raw = sys.exec("/usr/share/hermes/luci-helper status 2>/dev/null")
	http.prepare_content("application/json")
	http.write(raw ~= "" and raw or '{}')
end

-- ── Service Control API ──
function action_service_ctl()
	local http = require "luci.http"
	local sys  = require "luci.sys"

	local action = http.formvalue("action") or ""
	local allowed = { start = true, stop = true, restart = true, enable = true, disable = true }

	if not allowed[action] then
		http.prepare_content("application/json")
		http.write_json({ status = "error", message = "invalid action" })
		return
	end

	if action == "stop" then
		sys.exec("/etc/init.d/hermes stop >/dev/null 2>&1")
	elseif action == "restart" then
		sys.exec("/etc/init.d/hermes stop >/dev/null 2>&1")
		sys.exec("sleep 2")
		sys.exec("/etc/init.d/hermes start >/dev/null 2>&1 &")
	else
		sys.exec("/etc/init.d/hermes " .. action .. " >/dev/null 2>&1 &")
	end

	http.prepare_content("application/json")
	http.write_json({ status = "ok", action = action })
end

-- ── Get Token API ──
function action_get_token()
	local http = require "luci.http"
	local uci  = require "luci.model.uci".cursor()

	http.prepare_content("application/json")
	http.write_json({
		token     = uci:get("hermes", "main", "token") or "",
		pty_token = uci:get("hermes", "main", "pty_token") or ""
	})
end
