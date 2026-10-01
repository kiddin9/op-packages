-- parser_surge.lua — Surge 系 / Loon / QX 配置文件解析 → 统一节点模型（纯 Lua 5.1）
-- luci-app-substore

local util = require("substore.util")
local node = require("substore.node")
-- 协议白名单复用 Clash YAML 那张表：两边都是「外部格式的类型名 → 统一模型 proto」，
-- 各维护一份必然漂移。TYPE_MAP 的键就是这里要判定的原始类型名。
local TYPE_MAP = require("substore.parser_clash_yaml").TYPE_MAP

local M = {}

-- 把 Surge / QX 行里的类型名映射到统一模型 proto，未知类型返回 nil。
-- 与 parser_clash_yaml 的未知协议处理保持一致（见那边的长注释）：snell / ssh /
-- shadowtls / mieru 这类在统一模型里没有对应字段，原样透传会在输出端变成
-- sing-box 的 type: "snell"、Xray 的 protocol: "snell" 这类非法取值，
-- 客户端会拒绝加载整份配置；兜底成 vmess 更糟（凭空造出字段全错的假节点）。
-- 两者都比丢弃差，所以丢弃。
local function map_proto(raw)
	if type(raw) ~= "string" then return nil end
	return TYPE_MAP[raw:lower()]
end

-- 解析 Surge 风格行：Name = proto, server, port, k=v, ...
local function parse_surge_line(name, rest)
	local parts = {}
	for part in rest:gmatch("[^,]+") do
		parts[#parts + 1] = util.trim(part)
	end
	if #parts < 3 then return nil end

	local proto = map_proto(parts[1])
	if not proto then return nil end
	local server = parts[2]
	local port = tonumber(parts[3])

	local kv = {}
	for i = 4, #parts do
		local k, v = parts[i]:match("^([%w%-]+)%s*=%s*(.*)$")
		if k then kv[k] = util.trim(v) end
	end

	local data = {
		proto = proto, name = util.trim(name), server = server, port = port,
	}
	if proto == "shadowsocks" then
		data.method = kv["encrypt-method"] or kv.cipher or kv.method
		data.password = kv.password
	elseif proto == "vmess" or proto == "vless" then
		data.uuid = kv.username or kv.uuid
		if kv.flow then data.flow = kv.flow end
	elseif proto == "trojan" then
		data.password = kv.password
	elseif proto == "hysteria2" or proto == "hysteria" then
		data.password = kv.password
	end

	-- 传输/TLS 通用字段
	if kv.net or kv.network then data.net = kv.net or kv.network end
	if kv["ws"] == "true" then data.net = "ws" end
	if kv["ws-path"] then data.path = kv["ws-path"] end
	if kv["ws-headers"] and kv["ws-headers"]:match("^Host:") then
		data.host = kv["ws-headers"]:match("^Host:%s*(.*)$")
	end
	if kv.sni then data.sni = kv.sni end
	if kv.tls and kv.tls ~= "false" and kv.tls ~= "none" then data.security = "tls" end
	if kv["skip-cert-verify"] and kv["skip-cert-verify"] ~= "0" and kv["skip-cert-verify"] ~= "false" then
		data["skip-cert-verify"] = true
	end
	return node.normalize(data)
end

-- 解析 QX server_local 行：proto=server:port, k=v, ..., tag=Name
local function parse_qx_line(content)
	local proto, rest = content:match("^([%w_]+)%s*=%s*(.+)$")
	if not proto then return nil end
	local parts = {}
	for part in rest:gmatch("[^,]+") do
		parts[#parts + 1] = util.trim(part)
	end
	if #parts < 1 then return nil end

	local hostport = parts[1]
	local host, port = util.split_hostport(hostport)
	local kv = {}
	for i = 2, #parts do
		local k, v = parts[i]:match("^([%w%-]+)%s*=%s*(.*)$")
		if k then kv[k] = v end
	end

	local name = kv.tag or (host .. ":" .. tostring(port or ""))
	local proto = map_proto(proto)
	if not proto then return nil end

	local data = { proto = proto, name = name, server = host, port = tonumber(port) }
	if proto == "shadowsocks" then
		data.method = kv.method
		data.password = kv.password
	elseif proto == "vmess" or proto == "vless" then
		data.uuid = kv.password or kv.uuid
	elseif proto == "trojan" then
		data.password = kv.password
	end
	if kv["obfs"] == "ws" then data.net = "ws" end
	if kv["obfs-uri"] then data.path = kv["obfs-uri"] end
	if kv["obfs-host"] then data.host = kv["obfs-host"] end
	if kv["tls-host"] then data.sni = kv["tls-host"] end
	if kv["tls-verification"] == "true" or kv["over-tls"] == "true" then data.security = "tls" end
	return node.normalize(data)
end

-- 解析客户端配置，返回节点列表（自动识别 Surge/Loon 与 QX 风格）
function M.parse(content)
	if not content or content == "" then return {} end
	local nodes = {}
	local section = ""
	for line in content:gmatch("[^\r\n]+") do
		local t = util.trim(line)
		if t == "" or t:sub(1, 1) == "#" or t:sub(1, 1) == ";" then
			-- 跳过空行/注释
		elseif t:match("^%[") then
			section = t:match("^%[([^%]]+)%]") or ""
			section = section:lower()
		elseif section == "proxy" then
			local name, rest = t:match("^([^=]-)%s*=%s*(.+)$")
			if name and rest then
				local n = parse_surge_line(name, rest)
				if n then nodes[#nodes + 1] = n end
			end
		elseif section == "server_local" then
			local n = parse_qx_line(t)
			if n then nodes[#nodes + 1] = n end
		end
	end
	return nodes
end

-- 判断内容是否为客户端配置文件。
-- 段名大小写不敏感：Surge 官方配置写 `[Proxy]`，但 Loon / 第三方转换器常写
-- `[PROXY]` / `[General]` 这类全大写段名。原来的 find("%[Proxy%]") 只认大小写
-- 完全一致的写法，于是 detect 不认为这是 Surge 配置，继续往下走——
-- 而 `[` 开头的内容会被判成 JSON 数组，整份订阅报「JSON 解析失败」，
-- 一个节点都拿不到（M.parse 本身是按小写段名匹配的，本来就能解析）。
function M.is_config(content)
	content = content or ""
	local lower = content:lower()
	return lower:find("[proxy]", 1, true) ~= nil
		or lower:find("[server_local]", 1, true) ~= nil
end

return M