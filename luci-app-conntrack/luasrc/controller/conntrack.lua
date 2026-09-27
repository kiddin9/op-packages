module("luci.controller.conntrack", package.seeall)

function index()
	if not nixio.fs.access("/proc/net/nf_conntrack") then
		return
	end
	entry({"admin", "network", "conntrack"}, template("conntrack/conntrack"), _("ConnTrack"), 90).dependent = true
	entry({"admin", "network", "conntrack", "get_settings"}, call("action_get_settings"))
	entry({"admin", "network", "conntrack", "set_settings"}, call("action_set_settings"))
	entry({"admin", "network", "conntrack_stream"}, call("action_stream")).dependent = true
end

function action_get_settings()
	local uci = require("luci.model.uci").cursor()
	local jsonc = require("luci.jsonc")
	luci.http.prepare_content("application/json")
	
	local res = {
		interval = uci:get("conntrack", "settings", "interval") or "1500",
		rows = uci:get("conntrack", "settings", "rows") or "50",
		filter_local = uci:get("conntrack", "settings", "filter_local") or "true",
		show_appname = uci:get("conntrack", "settings", "show_appname") or "false"
	}
	luci.http.write(jsonc.stringify(res))
end

function action_set_settings()
	local uci = require("luci.model.uci").cursor()
	local jsonc = require("luci.jsonc")
	luci.http.prepare_content("application/json")
	
	local raw_body = luci.http.content()
	if raw_body then
		local data = jsonc.parse(raw_body)
		if data and type(data) == "table" then
			local has_settings = false
			uci:foreach("conntrack", "global", function(s)
				if s[".name"] == "settings" then
					has_settings = true
					return false
				end
			end)
			
			if not has_settings then
				uci:section("conntrack", "global", "settings")
			end
			
			if data.interval then uci:set("conntrack", "settings", "interval", tostring(data.interval)) end
			if data.rows then uci:set("conntrack", "settings", "rows", tostring(data.rows)) end
			if data.filter_local ~= nil then uci:set("conntrack", "settings", "filter_local", tostring(data.filter_local)) end
			if data.show_appname ~= nil then uci:set("conntrack", "settings", "show_appname", tostring(data.show_appname)) end
			
			local commit_ok = uci:commit("conntrack")
			if commit_ok then
				luci.http.write('{"status":"ok"}')
			else
				luci.http.write('{"status":"commit_failed"}')
			end
			return
		end
	end
	luci.http.write('{"status":"error"}')
end

local function nixio_lines_fast(path)
	local nixio = require("nixio")
	local fd = nixio.open(path, "r")
	if not fd then return function() return nil end end

	local chunks = {}
	while true do
		local chunk = fd:read(65536)
		if not chunk or #chunk == 0 then break end
		table.insert(chunks, chunk)
	end
	fd:close()

	local content = table.concat(chunks)
	local pos = 1
	local content_len = #content

	return function()
		if pos > content_len then
			return nil
		end

		local newline = content:find("\n", pos, true)
		if newline then
			local line = content:sub(pos, newline - 1)
			pos = newline + 1
			if #line > 0 and line:sub(-1) == "\r" then line = line:sub(1, -2) end
			return line
		else
			local line = content:sub(pos)
			pos = content_len + 1
			if #line > 0 and line:sub(-1) == "\r" then line = line:sub(1, -2) end
			return #line > 0 and line or nil
		end
	end
end

local function file_exists(path)
	local f = io.open(path, "r")
	if f then f:close() return true else return false end
end

local function create_file(path)
	local file, err = io.open(path, "w")
	if not file then return false else file:close() return true end
end

local function remove_file(path)
	if file_exists(path) then
		os.remove(path)
	end
end

-- Experiment: the performance wouldn't be quite good than realtime 'action_strem'
function action_stream_ubus()
        local nixio = require "nixio"
        local jsonc = require "luci.jsonc"
        local http = require "luci.http"

	local conntrack_lock_file = '/tmp/conntrack_event.lock'

        local interval = tonumber(http.formvalue("interval")) or 1000
        local max_rows = tonumber(http.formvalue("rows")) or 50
        local filter_src = http.formvalue("filter_src") or "all"
        local filter_dst = http.formvalue("filter_dst") or "all"
        local filter_local = http.formvalue("filter_local") or "false"

	http.header("Content-Type", "text/event-stream; charset=utf-8")
	http.header("Cache-Control", "no-cache")
	http.header("Connection", "keep-alive")
	http.context.redirect = false

	http.write("retry: 1000\n\n")
	io.flush()

	if not file_exists(conntrack_lock_file) then
		create_file(conntrack_lock_file)
	end
	local stat = nixio.fs.stat(conntrack_lock_file)
	nixio.fs.utimes(conntrack_lock_file, os.time(), stat.atime)

	local handle = io.popen("ubus listen conntrack_event 2>/dev/null")
	if not handle then return end

	for line in handle:lines() do
		nixio.fs.utimes(conntrack_lock_file, os.time(), stat.atime)
		local ct = jsonc.parse(line)
		if ct and ct.conntrack_event then
			for _, value in ipairs(ct.conntrack_event) do
				-- [Your custom code goes here]
			end

			local success = pcall(function()
				io.write("data: " .. jsonc.stringify(ct.conntrack_event) .. "\n\n")
				io.flush()
			end)
			if not success then
				break
			end
		end

                if luci.http.getenv("HTTP_CONNECTION") == "close" then
                        break
                end
	end

	handle:close()
end

function action_stream()
	local nixio = require "nixio"
	local jsonc = require "luci.jsonc"
	local http = require "luci.http"

	local interval = tonumber(http.formvalue("interval")) or 1000
	local max_rows = tonumber(http.formvalue("rows")) or 50
	local filter_src = http.formvalue("filter_src") or "all"
	local filter_dst = http.formvalue("filter_dst") or "all"
	local filter_local = http.formvalue("filter_local") or "false"
	local sort = http.formvalue("sort") or "rate"

	local lan_prefix = "192.168.1."
	local lan_ip = luci.util.exec("uci -q get network.lan.ipaddr"):gsub("%s+", "")
	if lan_ip and lan_ip ~= "" then
		if lan_ip:match("^192%.168%.") or lan_ip:match("^10%.") or lan_ip:match("^172%.") then
			lan_prefix = lan_ip:match("^([%d%.]+%.)%d+$") or "192.168.1."
		end
	end

        local function is_local_ip(ip)
                if not ip then return true end
                local clean_ip = ip:lower():gsub("%s+", ""):gsub("%[", ""):gsub("%]", "")
                if clean_ip == "127.0.0.1" or clean_ip == "0.0.0.0" or clean_ip == "::1" or clean_ip == "::" then return true end
                local no_zeros = clean_ip:gsub("0", "")
                if no_zeros == ":::::::1" or no_zeros == "::::::::" then return true end
                if clean_ip:find("^192%.168%.") or clean_ip:find("^10%.") or clean_ip:find("^172%.1[6-9]%.") or clean_ip:find("^172%.2%d%.") or clean_ip:find("^172%.3%.") then
                        return true
                end
                if clean_ip:find("^fc") or clean_ip:find("^fd") then
                        return true
                end
                if clean_ip:find("^fe[89ab]") then
                        return true
                end
                return false
        end

	local function normalize_ipv6(ip)
		if not ip or not ip:find(":") then return ip end
		local clean_ip = ip:lower():gsub("%s+", "")
		if clean_ip:find("::") then
			local _, count = clean_ip:gsub(":", "")
			local colons_to_add = 8 - count
			local replacement = ":"
			for i = 1, colons_to_add do replacement = replacement .. ":" end
			clean_ip = clean_ip:gsub("::", replacement)
		end
		local parts = {}
		for part in clean_ip:gmatch("([^:]+)") do
			while #part < 4 do part = "0" .. part end
			table.insert(parts, part)
		end
		while #parts < 8 do table.insert(parts, "0000") end
		return table.concat(parts, ":")
	end

	local lease_map = {}
	local mac_host_map = {}
	local ipv6_mac_map = {}

	local lf = io.open("/tmp/dhcp.leases", "r")
	if lf then
		for line in lf:lines() do
			local mac, ip, host = line:match("^%d+%s+([%a%d%:]+)%s+([%d%.%a%d%:]+)%s+([%w%-_]+)")
			if not mac or not host then
				ip, host = line:match("^%d+%s+[%a%d%:]+%s+([%d%.]+)%s+([%w%-_]+)")
			end
			if ip and host and host ~= "*" then
				lease_map[ip] = host
			end
			if mac and host and host ~= "*" then
				mac_host_map[mac:lower()] = host
			end
		end
		lf:close()
	end

	local sys_host = luci.util.exec("uci -q get system.@system[0].hostname"):gsub("%s+", "")
	if sys_host == "" then sys_host = "lan" end
	if lan_ip and lan_ip ~= "" then
		lease_map[lan_ip] = sys_host
	end

	-- adding ipv6 <-> host mapping
	local np = io.popen("ip -6 neighbor | grep -E -v 'FAILED'")
	if np then
		for line in np:lines() do
			local ip, mac = line:match("^([%a%d%:]+).-lladdr%s+([%a%d%:]+)")
			if ip and mac then
				local clean_ip = ip:lower():gsub("%s+", "")
				if not is_local_ip(clean_ip) then
					local norm_ip = normalize_ipv6(clean_ip)
					ipv6_mac_map[norm_ip] = mac:lower()
				end
			end
		end
		np:close()
	end

	for ipv6, mac in pairs(ipv6_mac_map) do
		local host = mac_host_map[mac]
		if host then
			lease_map[ipv6] = host
		end
	end

	if interval < 500 then interval = 500 end
	if interval > 10000 then interval = 10000 end

	http.header("Content-Type", "text/event-stream; charset=utf-8")
	http.header("Cache-Control", "no-cache")
	http.header("Connection", "keep-alive")
	http.context.redirect = false

	http.write("retry: 1000\n\n")
	io.flush()

	local function get_current_time()
		local sec, usec = nixio.gettimeofday()
		return sec + (usec / 1000000)
	end

	local last_connections = {}
	local last_timestamp = get_current_time()
	local layer3, proto, state, src1, dst1, sport1, dport1, bytes1, src2, dst2, sport2, dport2, bytes2, remain
	local type1, code1, id1, type2, code2, id2
	local srckey1, dstkey1, srckey2, dstkey2

	while true do
		local sec = math.floor(interval / 1000)
		local nsec = (interval % 1000) * 1000000
		-- nixio.nanosleep(sec, nsec)

		local current_timestamp = get_current_time()
		local current_connections = {}
		local ip_map = {}
		
		-- local f = io.open("/proc/net/nf_conntrack", "r")
		-- if not f then break end

		-- for line in f:lines() do
		for line in nixio_lines_fast("/proc/net/nf_conntrack") do
			local s_end = line:find("src=", 1, true)
			local has_state = true
			local remain = ""
			local payload = ""
			if s_end and line:byte(s_end-2) >= 48 and line:byte(s_end-2) <= 57 then
				has_state = false
			end
			if has_state then
				layer3, proto, state, src1, dst1, sport1, dport1, bytes1, src2, dst2, sport2, dport2, bytes2, remain = line:match("^(%w+)%s+%d+%s+(%w+)%s+%d+%s+%d+%s+(%S+)%s+src=([%a%d%.%:]+)%s+dst=([%a%d%.%:]+)%s+sport=(%d+)%s+dport=(%d+).-bytes=(%d+).-src=([%a%d%.%:]+)%s+dst=([%a%d%.%:]+)%s+sport=(%d+)%s+dport=(%d+).-bytes=(%d+)(.*)")
			else
				state = 'UNTRACKED'	
				layer3, proto, src1, dst1, sport1, dport1, bytes1, src2, dst2, sport2, dport2, bytes2, remain = line:match("^(%w+)%s+%d+%s+(%w+)%s+%d+%s+%d+%s+src=([%a%d%.%:]+)%s+dst=([%a%d%.%:]+)%s+sport=(%d+)%s+dport=(%d+).-bytes=(%d+).-src=([%a%d%.%:]+)%s+dst=([%a%d%.%:]+)%s+sport=(%d+)%s+dport=(%d+).-bytes=(%d+)(.*)")
			end
			if not layer3 then -- icmp
				layer3, proto, src1, dst1, type1, code1, id1, bytes1, src2, dst2, type2, code2, id2, bytes2, remain = line:match("^(%w+)%s+%d+%s+(%w+)%s+%d+%s+%d+%s+src=([%a%d%.%:]+)%s+dst=([%a%d%.%:]+)%s+type=(%d+)%s+code=(%d+)%s+id=(%d+).-bytes=(%d+).-src=([%a%d%.%:]+)%s+dst=([%a%d%.%:]+)%s+type=(%d+)%s+code=(%d+)%s+id=(%d+).-bytes=(%d+)(.*)")
				if not layer3 then -- gre
					layer3, proto, src1, dst1, srckey1, dstkey1, bytes1, src2, dst2, srckey2, dstkey2, bytes2, remain = line:match("^(%w+)%s+%d+%s+(%w+)%s+%d+%s+%d+%s+src=([%a%d%.%:]+)%s+dst=([%a%d%.%:]+)%s+srckey=(%S+)%s+dstkey=(%S+).-bytes=(%d+).-src=([%a%d%.%:]+)%s+dst=([%a%d%.%:]+)%s+srckey=(%S+)%s+dstkey=(%S+).-bytes=(%d+)(.*)")
				end
				if layer3 then
					sport1, dport1, sport2, dport2 = "", "", "", ""
				end
			end

			if remain then payload = remain:match("payload=(%S+)") or "" end

			if layer3 then
				if bytes1 and bytes2 then
					local display_proto = proto
					if proto == "udp" and (sport1 == "443" or dport1 == "443" or sport2 == "443" or dport2 == "443") then
						display_proto = "quic"
					end

				      if filter_local == "true" and is_local_ip(src1) and is_local_ip(dst1) then
						-- do nothing
				      else
					if layer3 == "ipv4" then
						-- IPv4 DNAT revert --
						if src2 == lan_ip or src2 == '127.0.0.1' then src2 = dst1 sport2 = dport1 end
						-- IPv4 SNAT revert --
						if dst2 ~= src1 then dst2 = src1 dport2 = sport1 end
					end

					ip_map[src1] = true
					ip_map[dst1] = true
					ip_map[src2] = true
					ip_map[dst2] = true

					local pass_orig = true
					if filter_src ~= "all" and src1 ~= filter_src then pass_orig = false end
					if filter_dst ~= "all" and dst1 ~= filter_dst then pass_orig = false end

					if pass_orig then
						local key_orig = string.format("%s_%s_%s:%s->%s:%s_ORIG", layer3, display_proto, src1, sport1, dst1, dport1)
						current_connections[key_orig] = {
							l3 = layer3, proto = display_proto, state = state,
							src = src1, sport = sport1, dst = dst1, dport = dport1, bytes = tonumber(bytes1), speed = 0, payload = payload
						}
					end

					local pass_repl = true
					if filter_src ~= "all" and src2 ~= filter_src then pass_repl = false end
					if filter_dst ~= "all" and dst2 ~= filter_dst then pass_repl = false end

					if pass_repl then
						local key_repl = string.format("%s_%s_%s:%s->%s:%s_REPL", layer3, display_proto, src2, sport2, dst2, dport2)
						current_connections[key_repl] = {
							l3 = layer3, proto = display_proto, state = state,
							src = src2, sport = sport2, dst = dst2, dport = dport2, bytes = tonumber(bytes2), speed = 0, payload = payload
						}
					end
				      end
				end
			end
		end
		-- f:close()
		local lines_proc_time = get_current_time() - current_timestamp

		local delta_time = current_timestamp - last_timestamp
		if delta_time > 0 then
			for key, curr in pairs(current_connections) do
				local prev = last_connections[key]
				if prev then
					local diff = curr.bytes - prev.bytes
					curr.speed = diff >= 0 and math.floor(diff / delta_time) or 0
				else
					curr.speed = 0
				end
			end
		end

		local sorted_list = current_connections
		local sorted_list = {}
		for _, conn in pairs(current_connections) do
			-- if conn.speed > 0 then
				table.insert(sorted_list, conn)
			-- end
		end

		if sort == 'rate' then
			table.sort(sorted_list, function(a, b) return a.speed > b.speed end)
		elseif sort == 'flow' then
			table.sort(sorted_list, function(a, b) return a.bytes > b.bytes end)
		end

		local output_list = {}
		for i = 1, math.min(#sorted_list, max_rows) do
			table.insert(output_list, sorted_list[i])
		end

		local lan_ips = {}
		local v4_ips = {}
		local v6_ips = {}
		local lan_pattern = "^" .. lan_prefix:gsub("%.", "%%.")

		for ip in pairs(ip_map) do
			if ip:find(":") then
				table.insert(v6_ips, ip)
			elseif ip:match(lan_pattern) then
				table.insert(lan_ips, ip)
			else
				table.insert(v4_ips, ip)
			end
		end
		table.sort(lan_ips)
		table.sort(v4_ips)
		table.sort(v6_ips)

		local unique_ips = {}
		for _, ip in ipairs(lan_ips) do table.insert(unique_ips, ip) end
		for _, ip in ipairs(v4_ips) do table.insert(unique_ips, ip) end
		for _, ip in ipairs(v6_ips) do table.insert(unique_ips, ip) end

		local response = {
			lines_proc_time = string.format("%.2f", lines_proc_time),
			delta = string.format("%.2f", delta_time),
			connections = output_list,
			unique_ips = unique_ips,
			host_map = lease_map
		}

		local json_str = jsonc.stringify(response)
		local ok = pcall(function()
			io.write("data: " .. json_str .. "\n\n")
			io.flush()
		end)

		if not ok then break end

		if luci.http.getenv("HTTP_CONNECTION") == "close" then
                        break
                end

		last_connections = current_connections
		last_timestamp = current_timestamp

		nixio.nanosleep(sec, nsec)
	end
end
