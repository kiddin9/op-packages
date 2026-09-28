-- output_singbox.lua — sing-box JSON 配置输出（纯 Lua）
-- luci-app-substore

local util = require("substore.util")

local M = {}

local function bool(v)
	if v == nil then return nil end
	if v == false or v == "false" or v == 0 or v == "0" then return false end
	return true
end

-- sing-box type 映射
local TYPE_MAP = {
	vmess = "vmess",
	vless = "vless",
	trojan = "trojan",
	shadowsocks = "shadowsocks",
	ss = "shadowsocks",
	hysteria2 = "hysteria2",
	hysteria = "hysteria",
	tuic = "tuic",
	wireguard = "wireguard",
	socks = "socks",
	socks5 = "socks",
	http = "http",
}

-- 构建 TLS 字段
local function build_tls(n)
	local tls
	if n.security and n.security ~= "none" then
		tls = {}
		if n.sni or n.servername then tls.server_name = n.sni or n.servername end
		if n.alpn then
			if type(n.alpn) == "string" then
				local list = {}
				for p in n.alpn:gmatch("[^,]+") do list[#list + 1] = p:match("^%s*(.-)%s*$") end
				tls.alpn = list
			else
				tls.alpn = n.alpn
			end
		end
		if n["skip-cert-verify"] ~= nil then
			tls.insecure = bool(n["skip-cert-verify"])
		elseif n.skip_cert_verify ~= nil then
			tls.insecure = bool(n.skip_cert_verify)
		end
		return tls
	end
	return nil
end

-- 构建传输（transport）字段
local function build_transport(n)
	local net = n.net or n.network
	if not net or net == "tcp" then return nil end
	if net == "ws" then
		local t = { type = "ws" }
		if n.path then t.path = n.path end
		if n.host then
			t.headers = { Host = n.host }
		end
		return t
	end
	if net == "grpc" then
		local t = { type = "grpc" }
		if n.path then t.service_name = n.path end
		return t
	end
	if net == "http" or net == "h2" then
		local t = { type = "http" }
		if n.host then t.host = { n.host } end
		if n.path then t.path = n.path end
		return t
	end
	return nil
end

-- 单节点 → sing-box outbound 表
function M.to_outbound(n)
	local stype = TYPE_MAP[n.proto] or n.proto
	if stype == "ssr" then return nil end -- sing-box 不支持 SSR，跳过
	local o = {
		type = stype,
		tag = n.name or ((n.server or "") .. ":" .. tostring(n.port or "")),
		server = n.server or "",
		server_port = tonumber(n.port) or 0,
	}

	if stype == "vmess" then
		o.uuid = n.uuid or ""
		if n.alterId ~= nil then o.alter_id = tonumber(n.alterId) end
		if n.security then o.security = n.security end
		if n.flow then o.flow = n.flow end
	elseif stype == "vless" then
		o.uuid = n.uuid or ""
		if n.flow then o.flow = n.flow end
	elseif stype == "trojan" then
		o.password = n.password or ""
	elseif stype == "shadowsocks" then
		o.method = n.method or n.cipher or "aes-256-gcm"
		o.password = n.password or ""
	elseif stype == "hysteria2" or stype == "hysteria" then
		o.password = n.password or ""
		-- 混淆（salamander）
		if n.obfs and n.obfs ~= "" and n.obfs ~= "plain" then
			o.obfs = { type = n.obfs, password = n["obfs-password"] or n.obfs_password or "" }
		end
	elseif stype == "tuic" then
		o.uuid = n.uuid or ""
		o.password = n.password or ""
		if n.congestion_control then o.congestion_control = n.congestion_control end
	elseif stype == "wireguard" then
		local pk = n["private-key"] or n.private_key
		local ppk = n["peer-public-key"] or n.peer_public_key or n["public-key"] or n.public_key
		local psk = n["pre-shared-key"] or n.pre_shared_key or n["preshared-key"] or n.preshared_key
		if pk then o.private_key = pk end
		if ppk then o.peer_public_key = ppk end
		if psk then o.pre_shared_key = psk end
		-- sing-box 的 local_address 接受字符串或字符串数组；同时有 IPv4/IPv6 时必须用数组，
		-- 逗号拼接（"a,b"）不是合法值
		local addr = {}
		if n.ip then addr[#addr + 1] = n.ip end
		if n.ipv6 then addr[#addr + 1] = n.ipv6 end
		if #addr == 1 then o.local_address = addr[1]
		elseif #addr > 1 then o.local_address = addr end
		if n["allowed-ips"] then o.allowed_ips = n["allowed-ips"] end
		if n.reserved then o.reserved = n.reserved end
		if n["persistent-keepalive"] then o.persistent_keepalive_interval = tonumber(n["persistent-keepalive"]) end
		if n["listen-port"] then o.listen_port = tonumber(n["listen-port"]) end
		if n.mtu then o.mtu = tonumber(n.mtu) end
		if n.dns then o.dns = n.dns end
	elseif stype == "socks" then
		if n.username then o.username = n.username end
		if n.password then o.password = n.password end
	end

	local tls = build_tls(n)
	if tls then o.tls = tls end
	local transport = build_transport(n)
	if transport then o.transport = transport end

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