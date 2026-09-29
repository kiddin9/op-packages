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

-- amnezia-wg-option 子键 → .conf 键。
-- 只输出能**确定**名字的键：多词键并不是把首字母大写就能得到 .conf 名
-- （header-protection-key 的正确写法是 HeaderProtectionKey，不是 Header-protection-key），
-- 靠规则猜出来的名字会被 AmneziaWG 客户端当成未知键，可能整份配置被拒。
-- 因此用显式映射，映射不到的键一律不输出（§110：不输出未经验证的 AWG 字段）。
local AWG_CONF_KEY_MAP = {
	jc = "Jc", jmin = "Jmin", jmax = "Jmax",
	s1 = "S1", s2 = "S2", s3 = "S3", s4 = "S4",
	h1 = "H1", h2 = "H2", h3 = "H3", h4 = "H4",
	i1 = "I1", i2 = "I2", i3 = "I3", i4 = "I4", i5 = "I5",
	j1 = "J1", j2 = "J2", j3 = "J3", itime = "Itime",
}

local function conf_key(k)
	return AWG_CONF_KEY_MAP[k]
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

	-- AmneziaWG 参数：按 .conf 键名排序输出，保证可 diff；
	-- 无法确定 .conf 名的键直接跳过（见 AWG_CONF_KEY_MAP 说明）
	local opt = n["amnezia-wg-option"]
	if type(opt) == "table" then
		local mapped = {}
		for k, v in pairs(opt) do
			local ck = conf_key(k)
			if ck then mapped[#mapped + 1] = { ck, v } end
		end
		table.sort(mapped, function(x, y) return x[1] < y[1] end)
		for _, kv in ipairs(mapped) do
			put(kv[1], tostring(kv[2]))
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
-- §55/§56：一个 .conf 文件 = 一个 [Interface]。wg-quick / AmneziaWG 客户端按「单条隧道」
-- 导入，把多个 [Interface] 段拼进同一个文件会得到客户端无法导入（或只取首段）的畸形配置，
-- 因此多于一个 WireGuard 节点时明确报错，而不是静默拼接。
function M.generate(nodes, options)
	local wg = {}
	for _, n in ipairs(nodes or {}) do
		if type(n) == "table" and is_wireguard(n) then
			wg[#wg + 1] = n
		end
	end
	if #wg == 0 then
		-- 明确报错优于返回空文件：用户能知道是"没有 WireGuard 节点"而非订阅坏了
		return nil, "没有可导出的 WireGuard 节点"
	end
	if #wg > 1 then
		return nil, string.format(
			"WireGuard .conf 每个文件只能包含一条隧道，当前有 %d 个 WireGuard 节点；请只导出单个节点",
			#wg)
	end

	local n = wg[1]
	local lines = { "# " .. (n.name or ((n.server or "") .. ":" .. tostring(n.port or ""))) }
	for _, line in ipairs(build_section(n)) do lines[#lines + 1] = line end
	return table.concat(lines, "\n") .. "\n"
end

return M
