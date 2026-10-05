-- parser_clash_yaml.lua — Clash YAML 解析 → 统一节点模型（纯 Lua 5.1）
-- luci-app-substore
-- 内置极简缩进式 YAML 解析器，处理 Clash proxies / proxy-groups 结构

local util = require("substore.util")
local node = require("substore.node")

local M = {}

-- Clash type → 统一 proto。
-- 这是**权威映射表**：parser_json_config 与 parser.lua 的简易 YAML 兜底解析都复用同一份，
-- 避免各自维护一份而漂移（曾出现兜底那份缺 hysteria2/hysteria/tuic/wireguard，
-- 且把 socks5 原样留下，导致这些节点被误当成 vmess 或被筛选器静默丢弃）。
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
	anytls = "anytls",
}

-- 导出供 parser.lua 的简易 YAML 兜底解析复用（单一事实来源）
M.TYPE_MAP = TYPE_MAP

-- 标量值转换：布尔 / 数字 / 去引号 / 保留字符串
local function scalar(raw)
	raw = raw or ""
	raw = raw:gsub("%s*$", "")
	if raw == "true" or raw == "True" or raw == "TRUE" then return true end
	if raw == "false" or raw == "False" or raw == "FALSE" then return false end
	if raw == "null" or raw == "~" or raw == "" then return nil end
	raw = raw:gsub('^"(.*)"$', "%1"):gsub("^'(.*)'$", "%1")
	-- 内联数组 [1,2,3] / ['a','b']
	if raw:sub(1,1) == "[" and raw:sub(-1) == "]" then
		local arr = {}
		for item in raw:sub(2,-2):gmatch("[^,%s]+") do
			item = item:gsub('^"(.*)"$', "%1"):gsub("^'(.*)'$", "%1")
			local n = tonumber(item)
			if n then arr[#arr+1]=n else arr[#arr+1]=item end
		end
		return arr
	end
	local n = tonumber(raw)
	if n then return n end
	return raw
end

-- 去掉行尾注释。YAML 规定内联注释的 # 前必须有空白，引号内的 # 不算注释。
-- 不处理的话 `proxies: # 说明` 会把注释文本当成值，proxies 变成字符串，
-- 整份配置被判定为「没有 proxies」→ 0 个节点且不报错。
local function strip_comment(v)
	local in_s, in_d = false, false
	for i = 1, #v do
		local c = v:sub(i, i)
		if in_s then
			if c == "'" then in_s = false end
		elseif in_d then
			if c == '"' then in_d = false end
		elseif c == "'" then in_s = true
		elseif c == '"' then in_d = true
		elseif c == "#" and (i == 1 or v:sub(i - 1, i - 1):match("%s")) then
			return (v:sub(1, i - 1):gsub("%s*$", ""))
		end
	end
	return v
end

-- 按顶层分隔符切分，忽略引号内以及 {} / [] 内部的同级分隔符
local function split_top(s, sep)
	local parts, buf = {}, {}
	local depth, in_s, in_d = 0, false, false
	for i = 1, #s do
		local c = s:sub(i, i)
		if in_s then
			if c == "'" then in_s = false end
			buf[#buf + 1] = c
		elseif in_d then
			if c == '"' then in_d = false end
			buf[#buf + 1] = c
		elseif c == "'" then
			in_s = true; buf[#buf + 1] = c
		elseif c == '"' then
			in_d = true; buf[#buf + 1] = c
		elseif c == "{" or c == "[" then
			depth = depth + 1; buf[#buf + 1] = c
		elseif c == "}" or c == "]" then
			depth = depth - 1; buf[#buf + 1] = c
		elseif c == sep and depth == 0 then
			parts[#parts + 1] = table.concat(buf); buf = {}
		else
			buf[#buf + 1] = c
		end
	end
	parts[#parts + 1] = table.concat(buf)
	return parts
end

-- 解析 YAML 流式映射 {...}。Clash 机场配置常用
-- `- {name: A, type: vmess, server: 1.1.1.1, port: 443}` 这种写法：它是合法 YAML，
-- 但不是合法 JSON（键没有加引号），util.json_decode 必然失败，节点被整条静默
-- 丢弃（0 个节点且无报错）。
local function parse_flow_map(s)
	local body = s:match("^%s*{(.*)}%s*$")
	if not body then return nil end
	local map = {}
	for _, part in ipairs(split_top(body, ",")) do
		local k, v = part:match("^%s*([^:]+):%s*(.*)$")
		if k then
			map[k:gsub("%s*$", "")] = scalar(strip_comment(v))
		end
	end
	if next(map) == nil then return nil end
	return map
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
				-- 行尾注释必须先去掉，否则 `proxies: # 说明` 会把注释文本当成值，
				-- proxies 变成字符串，整份配置被判定为「没有 proxies」
				v = strip_comment(v)
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
			-- 列表项也要去掉行尾注释：`- {a: 1} # 说明`、`- "::/0" # 说明`
			-- 都会让注释文本混进值里（流式映射那条甚至会整项解析失败）
			dash = strip_comment(dash)

			local m = nil
			-- 流式 JSON 对象：- {"name":"...","type":"vmess",...}（机场 clash 配置常见写法）
			if dash:sub(1, 1) == "{" then
				-- 先按 JSON 解（键带引号的流式写法），失败再按 YAML 流式映射解
				local obj = util.json_decode(dash)
				if type(obj) == "table" then m = obj end
				if not m then m = parse_flow_map(dash) end
			else
				local k, v = dash:match("^([^:]+):%s*(.*)$")
				-- 引号开头的列表项是标量而非映射：避免把 "- \"::/0\"" 里的冒号
				-- 当成 key:value 分隔符，从而把整个标量解析成 table
				if k and v ~= "" and not dash:match("^[\"']") then
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

	-- 未知协议必须丢弃，不能原样透传、也不能兜底成 vmess：
	--   * 原样透传：统一模型承载不了 snell / shadowtls / mieru / ssh 等类型（认证
	--     方式与字段都不同），透传出去会在输出端变成 sing-box 的 type: "snell"、
	--     Xray 的 protocol: "snell" 这类非法取值，客户端会拒绝加载整份配置。
	--   * 兜底成 vmess：那是凭空造出一个字段全错的节点，比丢弃更糟（用户看到
	--     "导入成功"，实际拿到一批不可用的假节点）。
	-- parser.lua 的简易 YAML 兜底解析（复用同一张 TYPE_MAP）早已按此处理，此处对齐。
	local proto = TYPE_MAP[p.type]
	if not proto then return nil end
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
		-- uTLS 指纹：mihomo 的键是 client-fingerprint（全仓库没有任何结构体声明
		-- `proxy:"fp,..."`，详见 node.CLIENT_FP_PROTOS 的说明）。只读 p.fp 的话，
		-- 一份真正的 mihomo 配置导入后指纹全部丢失 —— 与输出端写 `fp:` 是同一个
		-- 错误的另一半。仍然读 p.fp 是为了兼容本项目旧版本自己导出的配置。
		-- 注意不要读 `fingerprint`：hysteria/hysteria2/tuic 上那是证书固定
		-- （SHA256 pin），与 uTLS 语义不同，映射过来是错的。
		fp = p["client-fingerprint"] or p.fp,
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
	-- 但 type 要排除：Clash 的 type 是协议判别字段（vmess/ss/trojan），
	-- 已经在上面映射成 proto；原样拷进来会让节点多出一个 type，
	-- 而 output_uri 把它当成 vmess 的 header type 写出（"type":"vmess"），
	-- 生成客户端无法识别的 vmess:// 链接。
	for k, v in pairs(p) do
		if k ~= "type" and n[k] == nil then n[k] = v end
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