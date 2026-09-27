-- parser_clash_yaml.lua — Clash YAML 解析 → 统一节点模型（纯 Lua 5.1）
-- luci-app-substore
-- 内置极简缩进式 YAML 解析器，处理 Clash proxies / proxy-groups 结构

local util = require("substore.util")
local node = require("substore.node")

local M = {}

-- Clash type → 统一 proto
local TYPE_MAP = {
	vmess = "vmess",
	vless = "vless",
	trojan = "trojan",
	ss = "shadowsocks",
	shadowsocks = "shadowsocks",
	socks5 = "socks",
	socks = "socks",
	hysteria2 = "hysteria2",
	hysteria = "hysteria",
	tuic = "tuic",
	wireguard = "wireguard",
	ssr = "ssr",
	http = "http",
}

-- 标量值转换：布尔 / 数字 / 去引号 / 保留字符串
local function scalar(raw)
	raw = raw or ""
	raw = raw:gsub("%s*$", "")
	if raw == "true" or raw == "True" or raw == "TRUE" then return true end
	if raw == "false" or raw == "False" or raw == "FALSE" then return false end
	if raw == "null" or raw == "~" or raw == "" then return nil end
	raw = raw:gsub('^"(.*)"$', "%1"):gsub("^'(.*)'$", "%1")
	local n = tonumber(raw)
	if n then return n end
	return raw
end

-- 预处理内容为 (indent, rest) 列表，跳过空行、注释、文档分隔符
local function preprocess(content)
	local items = {}
	for l in (content:gsub("\r\n", "\n")):gmatch("[^\n]+") do
		local s = l
		local ind = 0
		while s:sub(1, 1) == " " do ind = ind + 1; s = s:sub(2) end
		local t = s:gsub("%s*$", "")
		if t ~= "" and not t:match("^#") and t ~= "---" and t ~= "..." then
			items[#items + 1] = { ind = ind, rest = t }
		end
	end
	return items
end

local function parse_yaml(content)
	local items = preprocess(content)
	local pos = 1
	local n_items = #items

	local read_list
	local function read_map(min_indent)
		local map = {}
		while pos <= n_items do
			local it = items[pos]
			if it.ind < min_indent then break end
			if it.rest == "-" or it.rest:match("^-%s") then break end
			local k, v = it.rest:match("^([^:]+):%s*(.*)$")
			if not k then
				pos = pos + 1
			else
				k = k:gsub("%s*$", "")
				pos = pos + 1
				if v == "" or v == "|" or v == ">" then
					if pos <= n_items and items[pos].ind > it.ind then
						local nxt = items[pos]
						if nxt.rest == "-" or nxt.rest:match("^-%s") then
							map[k] = read_list(nxt.ind)
						else
							map[k] = read_map(nxt.ind)
						end
					else
						map[k] = {}
					end
				else
					map[k] = scalar(v)
				end
			end
		end
		return map
	end

	read_list = function(min_indent)
		local list = {}
		while pos <= n_items do
			local it = items[pos]
			if it.ind < min_indent then break end
			local dash
			if it.rest == "-" then dash = "" else dash = it.rest:match("^-%s*(.*)$") end
			if dash == nil then break end
			pos = pos + 1

			local m = nil
			-- 流式 JSON 对象：- {"name":"...","type":"vmess",...}（机场 clash 配置常见写法）
			if dash:sub(1, 1) == "{" then
				local obj = util.json_decode(dash)
				if type(obj) == "table" then m = obj end
			else
				local k, v = dash:match("^([^:]+):%s*(.*)$")
				if k and v ~= "" then
					m = { [k:gsub("%s*$", "")] = scalar(v) }
				end
			end

			if pos <= n_items and items[pos].ind > it.ind then
				local nxt = items[pos]
				if nxt.rest == "-" or nxt.rest:match("^-%s") then
					list[#list + 1] = m or (dash ~= "" and scalar(dash) or nil)
				else
					local sub = read_map(nxt.ind)
					if m then
						for sk, sv in pairs(sub) do m[sk] = sv end
						list[#list + 1] = m
					else
						list[#list + 1] = sub
					end
				end
			elseif m or dash ~= "" then
				list[#list + 1] = m or scalar(dash)
			end
		end
		return list
	end

	local doc = read_map(0)
	return doc
end

-- 将单个 Clash proxy 表映射为统一节点模型
local function map_clash_node(p)
	if type(p) ~= "table" then return nil end
	if not p.name or not p.server or not p.port then return nil end

	local proto = TYPE_MAP[p.type] or p.type or "vmess"
	local n = {
		proto = proto,
		name = p.name,
		server = p.server,
		port = tonumber(p.port),
		uuid = p.uuid or p.id,
		password = p.password,
		method = p.cipher or p.method,
		net = p.network or p.net,
		sni = p.sni or p.servername,
		tls = p.tls,
		fp = p.fp,
	}
	if p.alpn then n.alpn = p.alpn end
	if p.udp ~= nil then n.udp = p.udp end
	if p["skip-cert-verify"] ~= nil then
		local sk = p["skip-cert-verify"]
		n["skip-cert-verify"] = sk
		n.skip_cert_verify = sk
	end
	if p.alterId then n.alterId = tonumber(p.alterId) end
	if p.security then n.security = p.security end
	if p.flow then n.flow = p.flow end
	-- ws-opts（Clash 的 ws 传输参数）映射到统一模型的 path / host
	if type(p["ws-opts"]) == "table" then
		if p["ws-opts"].path then n.path = p["ws-opts"].path end
		local wh = p["ws-opts"].headers
		if type(wh) == "table" and wh.Host then n.host = wh.Host end
	end

	-- 保留其余字段（wireguard 的 private-key、peer-public-key 等）
	for k, v in pairs(p) do
		if n[k] == nil then n[k] = v end
	end

	return node.normalize(n)
end

-- 解析 Clash YAML，返回统一节点模型列表
function M.parse(content)
	if not content or content == "" then return {} end
	local doc = parse_yaml(content)
	local proxies = doc and doc.proxies
	if type(proxies) ~= "table" then return {} end

	local nodes = {}
	for _, p in ipairs(proxies) do
		local n = map_clash_node(p)
		if n then nodes[#nodes + 1] = n end
	end
	return nodes
end

return M