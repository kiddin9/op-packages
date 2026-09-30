-- parser_json_config.lua — JSON 配置解析 → 统一节点模型（纯 Lua）
-- luci-app-substore
-- 支持 Sing-box、V2Ray、Clash JSON 配置解析（Lua 5.1 兼容，无 goto）

local util = require("substore.util")
local node = require("substore.node")

local M = {}

-- 协议映射（与 parser_clash_yaml 的 TYPE_MAP 保持一致）
local proto_map = {
	vmess = "vmess",
	vless = "vless",
	trojan = "trojan",
	shadowsocks = "shadowsocks",
	ss = "shadowsocks",
	socks = "socks",
	socks5 = "socks",
	http = "http",
	hysteria2 = "hysteria2",
	hysteria = "hysteria",
	tuic = "tuic",
	wireguard = "wireguard",
	ssr = "ssr",
}

local SUPPORTED = {
	vmess = true, vless = true, trojan = true, shadowsocks = true,
	hysteria2 = true, hysteria = true, tuic = true, wireguard = true,
	socks = true, http = true, ssr = true,
}

-- ---------- Sing-box JSON 解析 ----------
function M.parse_singbox_json(content)
	if not content or content == "" then return {} end

	local data = util.json_decode(content)
	if type(data) ~= "table" then return {} end

	local nodes = {}
	local outbounds = data.outbounds or {}

	for _, outbound in ipairs(outbounds) do
		if type(outbound) == "table" then
			local proto = proto_map[outbound.type] or outbound.type
			if proto and SUPPORTED[proto] then
				local server = outbound.server
				local port = outbound.server_port
				if server and port then
					local node_data = {
						proto = proto,
						name = outbound.tag or (server .. ":" .. tostring(port)),
						server = server,
						port = tonumber(port),
					}

					if proto == "vmess" or proto == "vless" then
						node_data.uuid = outbound.uuid
						if outbound.flow then node_data.flow = outbound.flow end
					elseif proto == "trojan" then
						node_data.password = outbound.password
					elseif proto == "shadowsocks" then
						node_data.method = outbound.method
						node_data.password = outbound.password
					elseif proto == "hysteria2" or proto == "hysteria" then
						node_data.password = outbound.password or outbound.auth_str or outbound.auth
					elseif proto == "tuic" then
						node_data.uuid = outbound.uuid
						node_data.password = outbound.password
						if outbound.congestion_control then node_data.congestion_control = outbound.congestion_control end
					elseif proto == "wireguard" then
						node_data["private-key"] = outbound["private-key"] or outbound.private_key
						node_data["peer-public-key"] = outbound["peer-public-key"] or outbound.peer_public_key or outbound["public-key"] or outbound.public_key
						node_data["public-key"] = outbound["public-key"] or outbound.public_key or outbound["peer-public-key"] or outbound.peer_public_key
						node_data["preshared-key"] = outbound["preshared-key"] or outbound.preshared_key or outbound["pre-shared-key"] or outbound.pre_shared_key
						node_data["pre-shared-key"] = outbound["pre-shared-key"] or outbound.pre_shared_key or outbound["preshared-key"] or outbound.preshared_key
						-- local_address 允许字符串或字符串数组；数组时按是否含 ":" 分归 ip / ipv6
						local la = outbound["local-address"] or outbound.local_address
						if type(la) == "table" then
							for _, a in ipairs(la) do
								if type(a) == "string" and a ~= "" then
									if a:find(":", 1, true) then
										if node_data.ipv6 == nil then node_data.ipv6 = a end
									else
										if node_data.ip == nil then node_data.ip = a end
									end
								end
							end
						elseif type(la) == "string" and la ~= "" then
							if la:find(":", 1, true) then node_data.ipv6 = la else node_data.ip = la end
						end
						node_data["allowed-ips"] = outbound["allowed-ips"] or outbound.allowed_ips
						node_data.reserved = outbound.reserved
						node_data["persistent-keepalive"] = outbound["persistent-keepalive"] or outbound.persistent_keepalive
							or outbound.persistent_keepalive_interval
						node_data["listen-port"] = outbound["listen-port"] or outbound.listen_port
						if outbound.mtu then node_data.mtu = outbound.mtu end
						node_data.dns = outbound.dns
						node_data["amnezia-wg-option"] = outbound["amnezia-wg-option"] or outbound.amnezia_wg_option
					elseif proto == "socks" or proto == "http" then
						node_data.username = outbound.username
						node_data.password = outbound.password
					end

					-- sing-box 用 tls 对象表达 TLS 层。注意 enabled 的缺省值是 false
					-- （option/tls.go: `Enabled bool` + omitempty），本输出模块因此总是
					-- 显式写 enabled=true。读取侧这里放宽为「只要不是显式 false 就当作
					-- 启用」，以便导入那些省略 enabled 的第三方配置时仍能保留 TLS 层。
					if outbound.tls and type(outbound.tls) == "table" then
						if outbound.tls.server_name then
							node_data.sni = outbound.tls.server_name
						end
						if outbound.tls.enabled ~= false then
							node_data.security = "tls"
						end
						if outbound.tls.alpn then
							node_data.alpn = outbound.tls.alpn
						end
						if outbound.tls.insecure ~= nil then
							node_data["skip-cert-verify"] = outbound.tls.insecure
						end
					end

					-- sing-box 只有 vmess 出站有 security 字段，且它是加密方式
					-- （cipher），不是 TLS 层；TLS 由上面的 tls 对象表达
					if outbound.security and proto == "vmess" then
						node_data.cipher = outbound.security
					end
					if outbound.network then
						node_data.net = outbound.network
					end

					nodes[#nodes + 1] = node.normalize(node_data)
				end
			end
		end
	end

	return nodes
end

-- ---------- V2Ray JSON 解析 ----------
function M.parse_v2ray_json(content)
	if not content or content == "" then return {} end

	local data = util.json_decode(content)
	if type(data) ~= "table" then return {} end

	local nodes = {}
	local outbounds = data.outbounds or {}

	for _, outbound in ipairs(outbounds) do
		if type(outbound) == "table" then
			local proto = proto_map[outbound.protocol] or outbound.protocol
			if proto and SUPPORTED[proto] then
				local settings = outbound.settings
				if type(settings) == "table" then
					local server, port, uuid, password, method, flow, username

					if proto == "vmess" or proto == "vless" then
						local vnext = settings.vnext
						if type(vnext) == "table" and #vnext > 0 then
							local sc = vnext[1]
							server = sc.address
							port = sc.port
							if type(sc.users) == "table" and #sc.users > 0 then
								local user = sc.users[1]
								uuid = user.id
								if user.flow then flow = user.flow end
							end
						end
					elseif proto == "trojan" then
						local servers = settings.servers
						if type(servers) == "table" and #servers > 0 then
							server = servers[1].address
							port = servers[1].port
							password = servers[1].password
						end
					elseif proto == "shadowsocks" then
						local servers = settings.servers
						if type(servers) == "table" and #servers > 0 then
							server = servers[1].address
							port = servers[1].port
							method = servers[1].method
							password = servers[1].password
						end
					elseif proto == "socks" or proto == "http" then
						local servers = settings.servers
						if type(servers) == "table" and #servers > 0 then
							server = servers[1].address
							port = servers[1].port
							if type(servers[1].users) == "table" and #servers[1].users > 0 then
								username = servers[1].users[1].user
								password = servers[1].users[1].pass
							end
						end
					end

					if server and port then
						local node_data = {
							proto = proto,
							name = outbound.tag or (server .. ":" .. tostring(port)),
							server = server,
							port = tonumber(port),
							uuid = uuid,
							password = password,
							method = method,
							flow = flow,
							username = username,
						}

						local ss2 = outbound.streamSettings
						if type(ss2) == "table" then
							if ss2.network then node_data.net = ss2.network end
							if ss2.security then node_data.security = ss2.security end
							if ss2.tlsSettings and type(ss2.tlsSettings) == "table" then
								if ss2.tlsSettings.serverName then node_data.sni = ss2.tlsSettings.serverName end
							end
							if ss2.realitySettings and type(ss2.realitySettings) == "table" then
								if ss2.realitySettings.serverName then node_data.sni = ss2.realitySettings.serverName end
							end
						end

						nodes[#nodes + 1] = node.normalize(node_data)
					end
				end
			end
		end
	end

	return nodes
end

-- ---------- Clash JSON 解析 ----------
function M.parse_clash_json(content)
	if not content or content == "" then return {} end

	local data = util.json_decode(content)
	if type(data) ~= "table" then return {} end

	local nodes = {}
	local proxies = data.proxies or {}

	for _, proxy in ipairs(proxies) do
		if type(proxy) == "table" then
			local proto = proto_map[proxy.type] or proxy.type
			if proto and SUPPORTED[proto] then
				local server = proxy.server
				local port = proxy.port
				if server and port then
					local node_data = {
						proto = proto,
						name = proxy.name or (server .. ":" .. tostring(port)),
						server = server,
						port = tonumber(port),
					}

					if proto == "vmess" or proto == "vless" then
						node_data.uuid = proxy.uuid
						if proxy.alterId then node_data.alterId = tonumber(proxy.alterId) end
					elseif proto == "trojan" then
						node_data.password = proxy.password
					elseif proto == "shadowsocks" then
						node_data.method = proxy.cipher or proxy.method
						node_data.password = proxy.password
					elseif proto == "hysteria2" or proto == "hysteria" then
						node_data.password = proxy.password or proxy["auth-str"] or proxy.auth_str
					elseif proto == "tuic" then
						node_data.uuid = proxy.uuid
						node_data.password = proxy.password
					elseif proto == "wireguard" then
						node_data["private-key"] = proxy["private-key"] or proxy.private_key
						node_data["peer-public-key"] = proxy["peer-public-key"] or proxy.peer_public_key or proxy["public-key"] or proxy.public_key
						node_data["public-key"] = proxy["public-key"] or proxy.public_key or proxy["peer-public-key"] or proxy.peer_public_key
						node_data["preshared-key"] = proxy["preshared-key"] or proxy.preshared_key or proxy["pre-shared-key"] or proxy.pre_shared_key
						node_data["pre-shared-key"] = proxy["pre-shared-key"] or proxy.pre_shared_key or proxy["preshared-key"] or proxy.preshared_key
						node_data.ip = proxy.ip or proxy["local-address"] or proxy.local_address
						node_data.ipv6 = proxy.ipv6
						node_data["allowed-ips"] = proxy["allowed-ips"] or proxy.allowed_ips
						node_data.reserved = proxy.reserved
						node_data["persistent-keepalive"] = proxy["persistent-keepalive"] or proxy.persistent_keepalive
						node_data["listen-port"] = proxy["listen-port"] or proxy.listen_port
						if proxy.mtu then node_data.mtu = proxy.mtu end
						node_data.dns = proxy.dns
						node_data["amnezia-wg-option"] = proxy["amnezia-wg-option"] or proxy.amnezia_wg_option
					elseif proto == "socks" or proto == "http" then
						node_data.username = proxy.username
						node_data.password = proxy.password
					elseif proto == "ssr" then
						node_data.method = proxy.cipher or proxy.method
						node_data.password = proxy.password
						node_data.protocol = proxy.protocol
						node_data.obfs = proxy.obfs
						if proxy["obfs-param"] then node_data.obfs_param = proxy["obfs-param"] end
						if proxy["protocol-param"] then node_data.protocol_param = proxy["protocol-param"] end
					end

					if proxy.network then node_data.net = proxy.network end
					if proxy.sni then
						node_data.sni = proxy.sni
					elseif proxy.servername then
						node_data.sni = proxy.servername
					end
					if proxy.tls then node_data.tls = proxy.tls end

					nodes[#nodes + 1] = node.normalize(node_data)
				end
			end
		end
	end

	return nodes
end

return M