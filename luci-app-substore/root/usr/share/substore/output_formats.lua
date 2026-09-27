-- output_formats.lua — Surge 系 / Loon / QX / Egern / Stash / Plain JSON 输出（纯 Lua）
-- luci-app-substore

local util = require("substore.util")
local clash_meta = require("substore.output_clash_meta")

local M = {}

-- 规范化协议名
local function props(n)
	local proto = (n.proto or ""):lower()
	if proto == "ss" then proto = "shadowsocks" end
	return proto
end

-- 生成 Surge 风格代理行（Surge / Surfboard / SurgeMac / Loon / Egern 通用）
function M.surge_line(n)
	local proto = props(n)
	local head = proto .. ", " .. (n.server or "") .. ", " .. tostring(n.port or 0)
	local e = {}
	local tls = (n.security and n.security ~= "none") or (n.tls and n.tls ~= false and n.tls ~= "none")

	if proto == "shadowsocks" then
		e[#e + 1] = "encrypt-method=" .. (n.method or n.cipher or "aes-256-gcm")
		e[#e + 1] = "password=" .. (n.password or "")
	elseif proto == "vmess" then
		e[#e + 1] = "username=" .. (n.uuid or "")
		if tls then e[#e + 1] = "tls=true" end
		if n.sni then e[#e + 1] = "sni=" .. n.sni end
		if n.net == "ws" then
			e[#e + 1] = "ws=true"
			if n.path then e[#e + 1] = "ws-path=" .. n.path end
			if n.host then e[#e + 1] = "ws-headers=Host:" .. n.host end
		end
	elseif proto == "vless" then
		e[#e + 1] = "username=" .. (n.uuid or "")
		if tls then e[#e + 1] = "tls=true" end
		if n.sni then e[#e + 1] = "sni=" .. n.sni end
		if n.flow then e[#e + 1] = "flow=" .. n.flow end
	elseif proto == "trojan" then
		e[#e + 1] = "password=" .. (n.password or "")
		e[#e + 1] = "tls=true"
		if n.sni then e[#e + 1] = "sni=" .. n.sni end
	elseif proto == "ssr" then
		e[#e + 1] = "encrypt-method=" .. (n.method or n.cipher or "aes-128-cfb")
		e[#e + 1] = "password=" .. (n.password or "")
		e[#e + 1] = "protocol=" .. (n.protocol or "origin")
		e[#e + 1] = "obfs=" .. (n.obfs or "plain")
		local op = n.obfs_param or n["obfs-param"]
		local pp = n.protocol_param or n["protocol-param"]
		if op and op ~= "" then e[#e + 1] = "obfs-param=" .. op end
		if pp and pp ~= "" then e[#e + 1] = "protocol-param=" .. pp end
	elseif proto == "hysteria2" or proto == "hysteria" then
		e[#e + 1] = "password=" .. (n.password or "")
		if n.sni then e[#e + 1] = "sni=" .. n.sni end
	elseif proto == "tuic" then
		e[#e + 1] = "username=" .. (n.uuid or "")
		if n.password then e[#e + 1] = "password=" .. n.password end
		if n.sni then e[#e + 1] = "sni=" .. n.sni end
		if n.alpn then e[#e + 1] = "alpn=" .. n.alpn end
	elseif proto == "socks5" or proto == "socks" then
		if n.username then
			e[#e + 1] = "username=" .. n.username
			if n.password then e[#e + 1] = "password=" .. n.password end
		end
	end

	if n["skip-cert-verify"] then e[#e + 1] = "skip-cert-verify=1" end
	if n.udp then e[#e + 1] = "udp-relay=true" end

	local line = (n.name or "") .. " = " .. head
	if #e > 0 then line = line .. ", " .. table.concat(e, ", ") end
	return line
end

-- 收集节点名列表
local function names_of(nodes)
	local out = {}
	for _, n in ipairs(nodes or {}) do
		if n.name then out[#out + 1] = n.name end
	end
	return out
end

-- Surge 家族配置（Surge / Surfboard / SurgeMac / Loon / Egern 通用）
-- supports_ssr：Loon / Egern 支持 SSR；Surge / Surfboard / SurgeMac 不支持，跳过 ssr 节点
local function surge_config(nodes, group_name, supports_ssr)
	local list = nodes or {}
	-- 过滤 Surge 家族无法用单行 [Proxy] 表达的协议：
	--   ssr：仅 Loon / Egern 支持（supports_ssr），Surge/Surfboard/SurgeMac 丢
	--   wireguard：Surge 需专用多段 [WireGuard] 配置，单行无法表达，统一丢弃（不输出损坏行）
	local kept = {}
	for _, n in ipairs(list) do
		local p = (n.proto or ""):lower()
		if p == "wireguard" then
			-- drop
		elseif not supports_ssr and p == "ssr" then
			-- drop
		else
			kept[#kept + 1] = n
		end
	end
	list = kept
	local out = {}
	out[#out + 1] = "[Proxy]"
	for _, n in ipairs(list) do
		out[#out + 1] = M.surge_line(n)
	end
	out[#out + 1] = ""
	out[#out + 1] = "[Proxy Group]"
	local names = names_of(list)
	local select = group_name .. " = select"
	for _, nm in ipairs(names) do select = select .. ", " .. nm end
	select = select .. ", DIRECT"
	out[#out + 1] = select
	return table.concat(out, "\n")
end

function M.to_surge(nodes, options)
	options = options or {}
	return surge_config(nodes, options.name or "PROXY", false)
end

function M.to_surfboard(nodes, options)
	options = options or {}
	return surge_config(nodes, options.name or "PROXY", false)
end

function M.to_surgemac(nodes, options)
	options = options or {}
	return surge_config(nodes, options.name or "PROXY", false)
end

-- Loon / Egern：Surge 兼容语法（支持 SSR）
function M.to_loon(nodes, options)
	options = options or {}
	return surge_config(nodes, options.name or "PROXY", true)
end

function M.to_egern(nodes, options)
	options = options or {}
	return surge_config(nodes, options.name or "PROXY", true)
end

-- Stash：Clash 兼容 YAML
function M.to_stash(nodes, options)
	return clash_meta.generate(nodes, options)
end

-- Quantumult X
function M.to_qx(nodes, options)
	options = options or {}
	local out = {}
	out[#out + 1] = "[server_local]"
	for _, n in ipairs(nodes or {}) do
		local proto = props(n)
		local host = (n.server or "") .. ":" .. tostring(n.port or 0)
		local tag = n.name or host
		if proto == "shadowsocks" then
			out[#out + 1] = string.format(
				"shadowsocks=%s, method=%s, password=%s, tag=%s",
				host, n.method or n.cipher or "aes-256-gcm", n.password or "", tag)
		elseif proto == "vmess" then
			out[#out + 1] = string.format(
				"vmess=%s, method=none, password=%s, tag=%s",
				host, n.uuid or "", tag)
			if n.net == "ws" then
				local esc = out[#out]
				esc = esc .. ", obfs=ws"
				if n.path then esc = esc .. ", obfs-uri=" .. n.path end
				if n.host then esc = esc .. ", obfs-host=" .. n.host end
				out[#out] = esc
			end
			if n.sni then out[#out] = out[#out] .. ", tls-host=" .. n.sni end
			if n.security and n.security ~= "none" then out[#out] = out[#out] .. ", tls-verification=true" end
		elseif proto == "vless" then
			out[#out + 1] = string.format(
				"vless=%s, method=none, password=%s, tag=%s",
				host, n.uuid or "", tag)
		elseif proto == "trojan" then
			out[#out + 1] = string.format(
				"trojan=%s, password=%s, over-tls=true, tag=%s",
				host, n.password or "", tag)
			if n.sni then out[#out] = out[#out] .. ", tls-host=" .. n.sni end
		end
	end
	out[#out + 1] = ""
	out[#out + 1] = "[policy]"
	local names = names_of(nodes)
	local policy = "static=" .. (options.name or "PROXY") .. ", DIRECT"
	for _, nm in ipairs(names) do policy = policy .. ", " .. nm end
	out[#out + 1] = policy
	out[#out + 1] = ""
	out[#out + 1] = "[server_remote]"
	return table.concat(out, "\n")
end

-- Plain JSON：节点统一模型 JSON 数组
function M.to_plain(nodes)
	return util.json_encode(nodes or {})
end

-- 统一分发
function M.generate(nodes, format, options)
	format = (format or ""):lower()
	if format == "surge" then return M.to_surge(nodes, options) end
	if format == "surfboard" then return M.to_surfboard(nodes, options) end
	if format == "surgemac" then return M.to_surgemac(nodes, options) end
	if format == "loon" then return M.to_loon(nodes, options) end
	if format == "egern" then return M.to_egern(nodes, options) end
	if format == "qx" then return M.to_qx(nodes, options) end
	if format == "stash" then return M.to_stash(nodes, options) end
	if format == "plain" then return M.to_plain(nodes) end
	return nil, "unsupported format: " .. tostring(format)
end

return M