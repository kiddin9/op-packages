-- output_v2ray.lua — V2Ray / Xray JSON 配置输出（纯 Lua）
-- luci-app-substore

local util = require("substore.util")

local M = {}

-- 构建 streamSettings
local function build_stream_settings(n)
	local ss = {}
	local net = n.net or n.network or "tcp"
	ss.network = net

	-- 传输层
	if net == "ws" then
		local ws = {}
		if n.path then ws.path = n.path end
		if n.host then ws.headers = { Host = n.host } end
		ss.wsSettings = ws
	elseif net == "grpc" then
		local g = {}
		if n.path then g.serviceName = n.path end
		ss.grpcSettings = g
	elseif net == "http" or net == "h2" then
		local h = {}
		if n.host then h.host = { n.host } end
		if n.path then h.path = n.path end
		ss.httpSettings = h
	elseif net == "kcp" then
		ss.kcpSettings = { header = { type = n.headerType or "none" } }
	end

	-- 安全层
	local security = n.security
	if security and security ~= "none" then
		ss.security = security
		local sni = n.sni or n.servername
		if sni then
			ss.tlsSettings = { serverName = sni, allowInsecure = false }
		end
	elseif n.tls and n.tls ~= "none" and n.tls ~= false then
		ss.security = "tls"
		local sni = n.sni or n.servername
		if sni then ss.tlsSettings = { serverName = sni } end
	end

	return ss
end

-- 单节点 → V2Ray outbound 表
function M.to_outbound(n)
	local proto = n.proto or "vmess"
	if proto == "ssr" then return nil end -- V2Ray / Xray 不支持 SSR，跳过
	local o = {
		protocol = (proto == "ss" and "shadowsocks" or proto),
		tag = n.name or ((n.server or "") .. ":" .. tostring(n.port or "")),
		settings = {},
		streamSettings = build_stream_settings(n),
	}
	local server, port = n.server or "", tonumber(n.port) or 0

	if proto == "vmess" then
		o.settings.vnext = { {
			address = server,
			port = port,
			users = { {
				id = n.uuid or "",
				alterId = tonumber(n.alterId or n.aid or 0),
				security = n.security or "auto",
			} },
		} }
	elseif proto == "vless" then
		local user = { id = n.uuid or "", encryption = "none" }
		if n.flow then user.flow = n.flow end
		o.settings.vnext = { { address = server, port = port, users = { user } } }
	elseif proto == "trojan" then
		o.settings.servers = { { address = server, port = port, password = n.password or "" } }
	elseif proto == "shadowsocks" or proto == "ss" then
		o.settings.servers = { {
			address = server,
			port = port,
			method = n.method or n.cipher or "aes-256-gcm",
			password = n.password or "",
		} }
	else
		-- socks / http 等
		o.settings.servers = { {
			address = server,
			port = port,
			users = n.username and { { user = n.username, pass = n.password or "" } } or nil,
		} }
	end

	return o
end

function M.generate(nodes)
	local outbounds = {}
	for _, n in ipairs(nodes or {}) do
		if type(n) == "table" then
			local o = M.to_outbound(n)
			if o then outbounds[#outbounds + 1] = o end
		end
	end
	return util.json_encode({ outbounds = outbounds })
end

return M