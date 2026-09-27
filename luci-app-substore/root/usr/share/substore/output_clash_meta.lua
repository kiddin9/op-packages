-- output_clash_meta.lua — Clash.Meta / Mihomo 格式输出（纯 Lua）
-- luci-app-substore

local M = {}

local function esc_yaml(s)
	s = tostring(s or "")
	s = s:gsub("\\", "\\\\"):gsub("\"", "\\\""):gsub("\n", "\\n")
	if s:find("[ :#{}[\],&*?|>'\"%@`]", 1, true) or s:match("^[-?]*:") then
		return '"' .. s .. '"'
	end
	return s
end

local function indent(level)
	return string.rep("  ", level)
end

local function yaml_list(items, level)
	local out = {}
	for _, v in ipairs(items) do
		out[#out + 1] = indent(level) .. "- " .. esc_yaml(v)
	end
	return table.concat(out, "\n")
end

local PROTOCOL_TYPE_MAP = {
	vmess = "vmess",
	vless = "vless",
	trojan = "trojan",
	shadowsocks = "ss",
	ss = "ss",
	hysteria2 = "hysteria2",
	tuic = "tuic",
	wireguard = "wireguard",
	socks = "socks5",
	socks5 = "socks5",
	ssr = "ssr",
}

local function get_clash_type(proto)
	return PROTOCOL_TYPE_MAP[proto] or proto
end

local function format_node(node)
	local lines = {}
	local ctype = get_clash_type(node.proto)
	lines[#lines + 1] = "  - name: " .. esc_yaml(node.name or "")
	lines[#lines + 1] = "    type: " .. esc_yaml(ctype)
	lines[#lines + 1] = "    server: " .. esc_yaml(node.server or "")
	lines[#lines + 1] = "    port: " .. tostring(node.port or 0)

	-- 协议通用字段
	if node.uuid then
		lines[#lines + 1] = "    uuid: " .. esc_yaml(node.uuid)
	end
	if node.password then
		lines[#lines + 1] = "    password: " .. esc_yaml(node.password)
	end
	if node.method then
		if ctype == "ss" then
			lines[#lines + 1] = "    cipher: " .. esc_yaml(node.method)
		end
	end
	if node.cipher then
		if ctype == "vmess" or ctype == "vless" then
			lines[#lines + 1] = "    cipher: " .. esc_yaml(node.cipher)
		end
	end
	if node.net or node.network then
		local net = node.net or node.network
		lines[#lines + 1] = "    network: " .. esc_yaml(net)
		-- ws 特殊处理
		if net == "ws" then
			if node.path then
				lines[#lines + 1] = "    ws-opts:"
				lines[#lines + 1] = "      path: " .. esc_yaml(node.path)
			end
			if node.host then
				lines[#lines + 1] = "      headers:"
				lines[#lines + 1] = "        Host: " .. esc_yaml(node.host)
			end
		end
	end

	-- TLS 相关
	local tls = false
	if node.security and node.security ~= "none" then
		tls = true
	elseif node.tls then
		tls = true
	end
	if tls then
		lines[#lines + 1] = "    tls: true"
	end

	-- servername / sni
	if node.sni then
		lines[#lines + 1] = "    servername: " .. esc_yaml(node.sni)
	end
	if node.servername then
		lines[#lines + 1] = "    servername: " .. esc_yaml(node.servername)
	end

	-- 特殊字段
	if node["skip-cert-verify"] ~= nil then
		lines[#lines + 1] = "    skip-cert-verify: " .. tostring(node["skip-cert-verify"])
	end
	if node.udp ~= nil then
		lines[#lines + 1] = "    udp: " .. tostring(node.udp)
	end
	if node.alpn then
		lines[#lines + 1] = "    alpn:"
		local alpn_list = {}
		if type(node.alpn) == "string" then
			for part in node.alpn:gmatch("[^,]+") do
				alpn_list[#alpn_list + 1] = part:match("^%s*(.-)%s*$")
			end
		elseif type(node.alpn) == "table" then
			alpn_list = node.alpn
		end
		for _, v in ipairs(alpn_list) do
			lines[#lines + 1] = "      - " .. esc_yaml(v)
		end
	end
	if node.fp then
		lines[#lines + 1] = "    fp: " .. esc_yaml(node.fp)
	end

	-- 协议特定字段
	if ctype == "vmess" then
		if node.alterId ~= nil then
			lines[#lines + 1] = "    alterId: " .. tostring(node.alterId)
		end
		if not node.cipher then
			lines[#lines + 1] = "    cipher: auto"
		end
	end

	if ctype == "hysteria2" then
		if node.sni then
			lines[#lines + 1] = "    sni: " .. esc_yaml(node.sni)
		end
		-- 混淆（salamander）
		if node.obfs and node.obfs ~= "" and node.obfs ~= "plain" then
			lines[#lines + 1] = "    obfs: " .. esc_yaml(node.obfs)
			local opw = node["obfs-password"] or node.obfs_password
			if opw and opw ~= "" then
				lines[#lines + 1] = "    obfs-password: " .. esc_yaml(opw)
			end
		end
	end

	if ctype == "tuic" then
		if node["udp-relay-mode"] then
			lines[#lines + 1] = "    udp-relay-mode: " .. esc_yaml(node["udp-relay-mode"])
		end
	end

	if ctype == "wireguard" then
		if node["private-key"] then
			lines[#lines + 1] = "    private-key: " .. esc_yaml(node["private-key"])
		end
		if node["peer-public-key"] then
			lines[#lines + 1] = "    peer-public-key: " .. esc_yaml(node["peer-public-key"])
		end
		if node["preshared-key"] then
			lines[#lines + 1] = "    preshared-key: " .. esc_yaml(node["preshared-key"])
		end
		if node.uuid then
			lines[#lines + 1] = "    uuid: " .. esc_yaml(node.uuid)
		end
	end

	if ctype == "socks5" then
		if node.username then
			lines[#lines + 1] = "    username: " .. esc_yaml(node.username)
		end
		if node.password then
			lines[#lines + 1] = "    password: " .. esc_yaml(node.password)
		end
	end

	if ctype == "ssr" then
		lines[#lines + 1] = "    cipher: " .. esc_yaml(node.method or node.cipher or "aes-128-cfb")
		lines[#lines + 1] = "    protocol: " .. esc_yaml(node.protocol or "origin")
		lines[#lines + 1] = "    obfs: " .. esc_yaml(node.obfs or "plain")
		local op = node.obfs_param or node["obfs-param"]
		local pp = node.protocol_param or node["protocol-param"]
		if op and op ~= "" then lines[#lines + 1] = "    obfs-param: " .. esc_yaml(op) end
		if pp and pp ~= "" then lines[#lines + 1] = "    protocol-param: " .. esc_yaml(pp) end
	end

	return table.concat(lines, "\n")
end

local function generate_proxies(nodes)
	if not nodes or #nodes == 0 then
		return "proxies: []"
	end
	local out = {}
	out[#out + 1] = "proxies:"
	for _, node in ipairs(nodes) do
		out[#out + 1] = format_node(node)
	end
	return table.concat(out, "\n")
end

local function generate_groups(nodes, options)
	local out = {}
	out[#out + 1] = "proxy-groups:"

	local names = {}
	for _, n in ipairs(nodes) do
		names[#names + 1] = n.name or ""
	end

	local group_name = (options and options.name) or "Proxy"

	-- SELECT
	out[#out + 1] = "  - name: " .. esc_yaml(group_name)
	out[#out + 1] = "    type: select"
	out[#out + 1] = "    proxies:"
	if #names > 0 then
		for _, n in ipairs(names) do
			out[#out + 1] = "      - " .. esc_yaml(n)
		end
	else
		out[#out + 1] = "      - REJECT"
	end

	-- URL-TEST
	out[#out + 1] = "  - name: URL-Test"
	out[#out + 1] = "    type: url-test"
	out[#out + 1] = "    url: http://www.gstatic.com/generate_204"
	out[#out + 1] = "    interval: 300"
	out[#out + 1] = "    tolerance: 50"
	out[#out + 1] = "    proxies:"
	if #names > 0 then
		for _, n in ipairs(names) do
			out[#out + 1] = "      - " .. esc_yaml(n)
		end
	else
		out[#out + 1] = "      - REJECT"
	end

	-- LOAD-BALANCE
	out[#out + 1] = "  - name: Load-Balance"
	out[#out + 1] = "    type: load-balance"
	out[#out + 1] = "    strategy: round-robin"
	out[#out + 1] = "    proxies:"
	if #names > 0 then
		for _, n in ipairs(names) do
			out[#out + 1] = "      - " .. esc_yaml(n)
		end
	else
		out[#out + 1] = "      - REJECT"
	end

	return table.concat(out, "\n")
end

function M.generate(nodes, options)
	options = options or {}
	local parts = {}

	-- 生成 proxies
	parts[#parts + 1] = generate_proxies(nodes or {})

	-- 生成 proxy-groups
	parts[#parts + 1] = generate_groups(nodes or {}, options)

	return table.concat(parts, "\n\n")
end

return M
