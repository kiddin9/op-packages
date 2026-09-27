-- output_uri.lua — 分享链接（URI）输出：Shadowrocket / V2Ray URI（纯 Lua）
-- luci-app-substore
-- 生成 vmess:// / vless:// / trojan:// / ss:// / hysteria2:// / tuic:// / ssr:// 分享链接

local util = require("substore.util")

local M = {}

-- URL 编码：保留字母数字 - . _ ~，其余转 %XX
local function url_encode(s)
	s = tostring(s or "")
	return (s:gsub("([^%w%-%.%_%~])", function(c)
		return string.format("%%%02X", c:byte())
	end))
end

-- 生成单节点分享链接；无法生成时返回 nil
function M.to_share_uri(n)
	if type(n) ~= "table" or not n.server or not n.port then return nil end
	local server = n.server
	local port = tonumber(n.port) or 0
	local name = url_encode(n.name or (server .. ":" .. tostring(port)))
	local proto = (n.proto or ""):lower()

	if proto == "ss" then proto = "shadowsocks" end

	if proto == "shadowsocks" then
		local method = n.method or n.cipher or "aes-256-gcm"
		local password = n.password or ""
		local userinfo = util.base64_encode(method .. ":" .. password)
		return "ss://" .. userinfo .. "@" .. server .. ":" .. tostring(port) .. "#" .. name
	end

	if proto == "vmess" then
		local json = {
			v = "2",
			ps = n.name or (server .. ":" .. tostring(port)),
			add = server,
			port = tostring(port),
			id = n.uuid or "",
			aid = tostring(n.alterId or n.aid or 0),
			scy = n.security or "auto",
			net = n.net or n.network or "tcp",
			type = n.type or n.headerType or "none",
			host = n.host or "",
			path = n.path or "",
			tls = (n.tls and n.tls ~= "none" and n.tls ~= false) and "tls" or "",
		}
		return "vmess://" .. util.base64_encode(util.json_encode(json))
	end

	if proto == "vless" then
		local q = {}
		q[#q + 1] = "encryption=none"
		q[#q + 1] = "type=" .. url_encode(n.net or n.network or "tcp")
		q[#q + 1] = "security=" .. url_encode(n.security or "none")
		if n.sni then q[#q + 1] = "sni=" .. url_encode(n.sni) end
		if n.fp then q[#q + 1] = "fp=" .. url_encode(n.fp) end
		if n.alpn then
			local alpn = type(n.alpn) == "table" and table.concat(n.alpn, ",") or n.alpn
			q[#q + 1] = "alpn=" .. url_encode(alpn)
		end
		if n.path then q[#q + 1] = "path=" .. url_encode(n.path) end
		if n.host then q[#q + 1] = "host=" .. url_encode(n.host) end
		if n.flow then q[#q + 1] = "flow=" .. url_encode(n.flow) end
		return "vless://" .. (n.uuid or "") .. "@" .. server .. ":" .. tostring(port)
			.. "?" .. table.concat(q, "&") .. "#" .. name
	end

	if proto == "trojan" then
		local q = {}
		q[#q + 1] = "security=" .. url_encode(n.security or "tls")
		if n.sni then q[#q + 1] = "sni=" .. url_encode(n.sni) end
		if n.alpn then q[#q + 1] = "alpn=" .. url_encode(n.alpn) end
		if n.fp then q[#q + 1] = "fp=" .. url_encode(n.fp) end
		return "trojan://" .. url_encode(n.password or "") .. "@" .. server .. ":" .. tostring(port)
			.. "?" .. table.concat(q, "&") .. "#" .. name
	end

	if proto == "hysteria2" or proto == "hysteria" then
		local q = {}
		if n.sni then q[#q + 1] = "sni=" .. url_encode(n.sni) end
		if n.insecure ~= nil then q[#q + 1] = "insecure=" .. tostring(n.insecure) end
		-- 混淆（salamander）：hy2 URI 标准参数 obfs / obfs-password
		if n.obfs and n.obfs ~= "" and n.obfs ~= "plain" then
			q[#q + 1] = "obfs=" .. url_encode(n.obfs)
			local opw = n["obfs-password"] or n.obfs_password
			if opw and opw ~= "" then q[#q + 1] = "obfs-password=" .. url_encode(opw) end
		end
		local suffix = #q > 0 and ("?" .. table.concat(q, "&")) or ""
		return (proto == "hysteria2" and "hysteria2://" or "hysteria://")
			.. url_encode(n.password or "") .. "@" .. server .. ":" .. tostring(port)
			.. suffix .. "#" .. name
	end

	if proto == "tuic" then
		local userinfo = (n.uuid or "") .. ":" .. url_encode(n.password or "")
		local q = {}
		if n.congestion_control then q[#q + 1] = "congestion_control=" .. url_encode(n.congestion_control) end
		if n.alpn then q[#q + 1] = "alpn=" .. url_encode(n.alpn) end
		if n.sni then q[#q + 1] = "sni=" .. url_encode(n.sni) end
		local suffix = #q > 0 and ("?" .. table.concat(q, "&")) or ""
		return "tuic://" .. userinfo .. "@" .. server .. ":" .. tostring(port)
			.. suffix .. "#" .. name
	end

	if proto == "socks5" or proto == "socks" then
		local userinfo = ""
		if n.username then userinfo = url_encode(n.username)
			if n.password then userinfo = userinfo .. ":" .. url_encode(n.password) end
			userinfo = userinfo .. "@"
		end
		return "socks5://" .. userinfo .. server .. ":" .. tostring(port) .. "#" .. name
	end

	if proto == "ssr" then
		return M.to_ssr_uri(n)
	end

	if proto == "wireguard" then
		-- wireguard://base64(json)#name —— 本项目自定义 scheme（wireguard 无统一 URI 标准）
		local json = {
			server = server,
			port = tostring(port),
			["private-key"] = n["private-key"] or n.private_key,
			["peer-public-key"] = n["peer-public-key"] or n.peer_public_key,
			["preshared-key"] = n["preshared-key"] or n.preshared_key,
		}
		if n.mtu then json.mtu = tostring(n.mtu) end
		if n.name then json.name = n.name end
		return "wireguard://" .. util.base64_encode(util.json_encode(json)) .. "#" .. name
	end

	return nil
end

-- 生成 ssr:// 分享链接（外层与密码为标准 base64，参数为 base64url）
function M.to_ssr_uri(n)
	if type(n) ~= "table" or not n.server then return nil end
	local server = n.server
	local port = tostring(tonumber(n.port) or 0)
	local protocol = n.protocol or "origin"
	local method = n.method or n.cipher or "aes-128-cfb"
	local obfs = n.obfs or "plain"
	local password = n.password or ""
	local main = table.concat({ server, port, protocol, method, obfs, util.base64_encode(password) }, ":")
	local q = {}
	local op = n.obfs_param or n["obfs-param"]
	local pp = n.protocol_param or n["protocol-param"]
	if op and op ~= "" then q[#q + 1] = "obfsparam=" .. util.base64_url_encode(op) end
	if pp and pp ~= "" then q[#q + 1] = "protoparam=" .. util.base64_url_encode(pp) end
	q[#q + 1] = "remarks=" .. util.base64_url_encode(n.name or server)
	if n.group and n.group ~= "" then q[#q + 1] = "group=" .. util.base64_url_encode(n.group) end
	return "ssr://" .. util.base64_encode(main .. "/?" .. table.concat(q, "&"))
end

-- 生成 URI 列表（每行一条，丢弃无法生成 URI 的节点）
function M.to_uri_list(nodes)
	local out = {}
	for _, n in ipairs(nodes or {}) do
		local u = M.to_share_uri(n)
		if u then out[#out + 1] = u end
	end
	return table.concat(out, "\n")
end

-- Shadowrocket 订阅：base64 编码的 URI 列表
function M.to_shadowrocket(nodes)
	return util.base64_encode(M.to_uri_list(nodes))
end

-- V2Ray URI 订阅：明文 URI 列表
function M.to_v2ray_uri(nodes)
	return M.to_uri_list(nodes)
end

return M