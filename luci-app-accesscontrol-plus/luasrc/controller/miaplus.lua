module("luci.controller.miaplus",package.seeall)

function index()
	if not nixio.fs.access("/etc/config/miaplus") then
		return
	end

	entry({"admin", "services", "miaplus"}, cbi("base"), _("Internet Access Schedule Control Plus"), 30).dependent = true
	entry({"admin", "services", "miaplus", "status"}, call("act_status")).leaf = true

	entry({"admin", "services", "miaplus", "base"}, cbi("base"), _("Base Setting"), 40).leaf = true
	entry({"admin", "services", "miaplus", "advanced"}, cbi("advanced"), _("Advance Setting"), 50).leaf = true
	entry({"admin", "services", "miaplus", "template"}, cbi("template"), nil).leaf = true
end

function act_status()
	local e = {}
	-- 交给 init 脚本的 status 方法判断：它会按 fw3(iptables)/fw4(nft) 自动分发
	e.running = luci.sys.call("/etc/init.d/miaplus status >/dev/null 2>&1") == 0
	luci.http.prepare_content("application/json")
	luci.http.write_json(e)
end
