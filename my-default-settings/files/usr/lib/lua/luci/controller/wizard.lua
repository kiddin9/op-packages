function landing_page()
	local uci = luci.model.uci.cursor()
	local page = uci:get("luci", "main", "landing_page")
	local target = {"admin", "status", "overview"}

	local istore_routes = {
		quickstart         = {"admin", "quickstart"},
		["istorex/nas"]      = {"admin", "istorex", "nas"},
		["istorex/next-nas"] = {"admin", "istorex", "next-nas"},
		["istorex/router"]   = {"admin", "istorex", "router"}
	}

	-- 1. 默认/自动模式
	if not page or page == "auto" then
		if is_running("quickstart") then
			target = {"admin", "quickstart"}
		elseif is_running("routergo") then
			target = {"admin", "routerdog"}
		elseif check_wifi(uci) then
			target = {"admin", "status", "dashboard"}
		else
			target = {"admin", "status", "overview"}
		end

	-- 2. 常规指定页面
	elseif page == "status/overview" then
		target = {"admin", "status", "overview"}
	elseif page == "status/dashboard" then
		target = {"admin", "status", "dashboard"}

	-- 3. Routerdog 模式（进程未运行时保留默认 overview，避免落入 else 跳转到失效页面）
	elseif page == "routerdog" then
		if is_running("routergo") then
			target = {"admin", "routerdog"}
		end

	-- 4. iStoreOS / iStoreX 增强页面（进程未运行时保留默认 overview，避免落入 else）
	elseif istore_routes[page] then
		if is_running("quickstart") then
			target = istore_routes[page]
		end

	-- 5. 兜底自定义路径（支持 xxx、xxx/yyy、xxx/yyy/zzz 等任意长度）
	else
		local custom = {"admin"}
		for part in string.gmatch(page, "[^/]+") do
			if part ~= "admin" or #custom > 1 then -- 兼容误填 "admin/xxx" 前缀的情况
				table.insert(custom, part)
			end
		end
		if #custom > 1 then
			target = custom
		end
	end

	http.redirect(luci.dispatcher.build_url(unpack(target)))
end
