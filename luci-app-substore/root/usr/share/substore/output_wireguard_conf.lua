-- output_wireguard_conf.lua — wg-quick / AmneziaWG .conf 输出（纯 Lua）
-- luci-app-substore
-- 与 parser.parse_wireguard_conf 互为逆操作：导入解析 [Interface] / [Peer]，此处按同格式写回。

local M = {}

-- 仅 wireguard 节点可用 .conf 表达；其余协议无法落到单行/单段，直接丢弃
-- （与 output_formats.surge_config 丢弃 wireguard 的处理对称）
local function is_wireguard(n)
	local p = (n.proto or ""):lower()
	return p == "wireguard" or p == "wg"
end

-- amnezia-wg-option 键 → .conf 键：首字母大写（jc → Jc，jmin → Jmin，itime → Itime）
local function conf_key(k)
	return (k:gsub("^%l", string.upper))
end

-- 值可能是标量或数组，统一转为 "a, b, c"
local function join_list(v)
	if v == nil then return nil end
	if type(v) == "table" then
		local t = {}
		for _, x in ipairs(v) do
			if x ~= nil and tostring(x) ~= "" then t[#t + 1] = tostring(x) end
		end
		if #t == 0 then return nil end
		return table.concat(t, ", ")
	end
	if tostring(v) == "" then return nil end
	return tostring(v)
end

-- Endpoint：IPv6 主机需加方括号（wg-quick 语法）
local function endpoint_of(n)
	local host = n.server
	local port = n.port
	if not host or host == "" or not port then return nil end
	if host:find(":", 1, true) and host:sub(1, 1) ~= "[" then
		host = "[" .. host .. "]"
	end
	return host .. ":" .. tostring(port)
end

-- 单个节点 → .conf 文本行数组
local function build_section(n)
	local out = {}
	local function put(k, v)
		if v ~= nil and v ~= "" then out[#out + 1] = k .. " = " .. v end
	end

	out[#out + 1] = "[Interface]"
	put("PrivateKey", n["private-key"] or n.private_key)
	-- Address 合并 IPv4 / IPv6
	local addr = {}
	if n.ip then addr[#addr + 1] = n.ip end
	if n.ipv6 then addr[#addr + 1] = n.ipv6 end
	put("Address", join_list(addr))
	put("ListenPort", n["listen-port"] or n.listen_port)
	put("MTU", n.mtu)
	put("DNS", join_list(n.dns))

	-- AmneziaWG 参数：按 .conf 键名排序输出，保证可 diff
	local opt = n["amnezia-wg-option"]
	if type(opt) == "table" then
		local keys = {}
		for k in pairs(opt) do keys[#keys + 1] = k end
		table.sort(keys)
		for _, k in ipairs(keys) do
			put(conf_key(k), tostring(opt[k]))
		end
	end

	out[#out + 1] = ""
	out[#out + 1] = "[Peer]"
	put("PublicKey", n["public-key"] or n.public_key or n["peer-public-key"] or n.peer_public_key)
	put("PresharedKey", n["pre-shared-key"] or n.pre_shared_key or n["preshared-key"] or n.preshared_key)
	put("AllowedIPs", join_list(n["allowed-ips"]))
	put("Endpoint", endpoint_of(n))
	put("PersistentKeepalive", n["persistent-keepalive"])

	-- 说明：不输出 Reserved —— 它不是 wg-quick 标准键，写进 .conf 可能被客户端拒绝。
	-- reserved 仍保留在 clash.meta / sing-box / URI 输出中。
	return out
end

-- nodes → wg-quick .conf 文本
-- 注意：wg-quick / AmneziaWG 客户端一个文件导入一条隧道。单节点时输出即为标准单接口
-- .conf；多节点时各段以 "# <名称>" 注释分隔，便于查看与手工拆分。
function M.generate(nodes, options)
	local blocks = {}
	for _, n in ipairs(nodes or {}) do
		if type(n) == "table" and is_wireguard(n) then
			local sec = build_section(n)
			local named = { "# " .. (n.name or ((n.server or "") .. ":" .. tostring(n.port or ""))) }
			for _, line in ipairs(sec) do named[#named + 1] = line end
			blocks[#blocks + 1] = table.concat(named, "\n")
		end
	end
	if #blocks == 0 then
		-- 明确报错优于返回空文件：用户能知道是"没有 WireGuard 节点"而非订阅坏了
		return nil, "没有可导出的 WireGuard 节点"
	end
	return table.concat(blocks, "\n\n") .. "\n"
end

return M
