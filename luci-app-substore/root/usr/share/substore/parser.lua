-- parser.lua — 订阅格式解析 → 统一节点模型（纯 Lua）
-- luci-app-substore

local util = require("substore.util")
local node = require("substore.node")
local parser_yaml = require("substore.parser_yaml")
local parser_clash_yaml = require("substore.parser_clash_yaml")
local parser_json_config = require("substore.parser_json_config")
local parser_surge = require("substore.parser_surge")

local M = {}

local SUPPORTED = {
	vmess = true, vless = true, trojan = true, ss = true, ssr = true,
	hysteria2 = true, tuic = true, wireguard = true,
}

local function split_lines(content)
	local out = {}
	for line in content:gmatch("[^\r\n]+") do
		out[#out + 1] = line
	end
	return out
end

-- 检测订阅格式：uri / base64 / json / yaml / empty / unknown
function M.detect(content)
	content = util.trim(content or "")
	content = content:gsub("^\239\187\191", "") -- 去除 UTF-8 BOM（部分机场/CDN 会在开头塞 BOM）
	if content == "" then return "empty" end
	local stripped = content:gsub("%s+", "")
	if stripped:sub(1, 1) == "{" then return "json" end
	-- YAML 检测：包含 proxies: 或 outbounds: 键
	if content:match("^[%s]*proxies:") or content:match("^[%s]*outbounds:") then
		return "yaml"
	end
	-- 检查内容中是否包含 proxies: 或 outbounds: 行
	for line in content:gmatch("[^\r\n]+") do
		if line:match("^%s*proxies:%s*$") or line:match("^%s*outbounds:%s*$") then
			return "yaml"
		end
	end
	-- wg-quick / AmneziaWG .conf：[Interface] 段 + PrivateKey 行（双条件收紧，避免误判普通文本）
	local lower = content:lower()
	if lower:match("%[interface%]") and lower:match("privatekey%s*=") then
		return "wireguard-conf"
	end
	if stripped:find("vmess://", 1, true) or stripped:find("vless://", 1, true)
		or stripped:find("trojan://", 1, true) or stripped:find("ssr://", 1, true)
		or stripped:find("ss://", 1, true) or content:find("://", 1, true) then
		return "uri"
	end
	if stripped:match("^[A-Za-z0-9+/_%-]*=*$") and #stripped > 10 then
		-- 更严格：需含 = / + - _ 之一，或长度为 4 的整数倍（避免把纯字母数字文本误判为 base64）
		-- 兼容 base64url（- _ 无 padding）：URL-safe 变体也常见于机场订阅
		if stripped:find("=", 1, true) or stripped:find("/", 1, true)
			or stripped:find("+", 1, true) or stripped:find("-", 1, true)
			or stripped:find("_", 1, true) or #stripped % 4 == 0 then
			return "base64"
		end
		-- 纯字母数字且长度非 4 倍数：可能是去掉 padding 的 base64url，尝试解码校验内容
		local decoded = util.base64_url_decode(stripped)
		if decoded ~= "" and (decoded:find("vmess://", 1, true) or decoded:find("vless://", 1, true)
			or decoded:find("trojan://", 1, true) or decoded:find("ss://", 1, true)
			or decoded:find("ssr://", 1, true)) then
			return "base64"
		end
	end
	if parser_surge.is_config(content) then return "surge" end
	return "unknown"
end

-- ---------- 协议解析 ----------
local function parse_ss(body)
	-- ss:// 兼容多种变体：base64(method:password@host:port)、method:password@host:port、
	-- base64(method:password)@host:port；可选 ?plugin=、#name
	local fragment, rest = "", body
	local hash = rest:find("#", 1, true)
	if hash then
		fragment = util.url_decode(rest:sub(hash + 1))
		rest = rest:sub(1, hash - 1)
	end
	local query = {}
	local qpos = rest:find("?", 1, true)
	local hp = rest
	if qpos then
		hp = rest:sub(1, qpos - 1)
		for k, v in rest:sub(qpos + 1):gmatch("([^&=]+)=([^&]*)") do
			query[k] = util.url_decode(v)
		end
	end
	if hp == "" then return nil, "bad ss" end

	local userinfo, hostport
	local at = hp:find("@", 1, true)
	if at then
		userinfo, hostport = hp:sub(1, at - 1), hp:sub(at + 1)
	else
		-- 整体可能是 base64(method:password@host:port)
		local decoded = util.base64_decode(hp)
		local d = decoded:find("@", 1, true)
		if d then
			userinfo, hostport = decoded:sub(1, d - 1), decoded:sub(d + 1)
		else
			return nil, "bad ss (no @)"
		end
	end
	-- userinfo 可能是 base64(method:password)
	if not userinfo:find(":", 1, true) then
		userinfo = util.base64_decode(userinfo) or ""
	end
	local method, password = userinfo:match("^([^:]+):(.*)$")
	local host, port = util.split_hostport(hostport)
	if not (method and password and host) then return nil, "bad ss" end
	local name = fragment ~= "" and fragment or (host .. ":" .. tostring(port or ""))
	local out = node.normalize({
		proto = "shadowsocks", name = name, server = host, port = tonumber(port),
		method = method, password = password, raw = ("ss://" .. body),
	})
	if query.plugin then out.plugin = query.plugin end
	return out
end

-- SSR 参数值可能为 base64url、标准 base64 或纯文本：优先 base64url 解码，失败回退 URL 解码
local function b64u_decode(s)
	s = s or ""
	local v = util.base64_url_decode(s)
	if v ~= "" then return v end
	return util.url_decode(s)
end

local function parse_ssr(body)
	-- ssr://base64(server:port:protocol:method:obfs:base64(password)/?obfsparam=..&protoparam=..&remarks=..&group=..)
	-- 外层为标准 base64；密码字段可为标准/base64url base64；obfsparam/protoparam/remarks/group 为 base64url
	if not body or body == "" then return nil, "bad ssr" end
	-- 容忍 #fragment 与 URL 转义（部分生成器会在末尾追加）
	local rest, frag = body, ""
	local hash = rest:find("#", 1, true)
	if hash then
		frag = util.url_decode(rest:sub(hash + 1))
		rest = rest:sub(1, hash - 1)
	end
	if rest:find("%", 1, true) then rest = util.url_decode(rest) end
	local decoded = util.base64_decode(rest)
	if decoded == "" then return nil, "bad ssr" end

	-- 以首个 '?' 切分主体与参数（密码 base64 可能含 '/'，故不能按 '/' 切分）
	local main, query = decoded:match("^([^?]*)%?(.*)$")
	if not main then main, query = decoded, "" end
	main = main:gsub("/+$", "")

	local server, port, protocol, method, obfs, pwd_b64 = main:match("^([^:]*):([^:]*):([^:]*):([^:]*):([^:]*):(.*)$")
	if not server or server == "" then return nil, "bad ssr" end
	local password = util.base64_url_decode(pwd_b64 or "")
	if password == "" then password = pwd_b64 or "" end

	local params = {}
	for k, v in (query or ""):gmatch("([^&=]+)=([^&]*)") do
		params[k] = v
	end

	local name = b64u_decode(params.remarks or "")
	if name == "" then name = frag end
	if name == "" then name = server .. ":" .. tostring(port or "") end

	local out = node.normalize({
		proto = "ssr", name = name, server = server, port = tonumber(port),
		method = method, password = password, protocol = protocol, obfs = obfs,
		raw = ("ssr://" .. body),
	})
	local op = b64u_decode(params.obfsparam or "")
	local pp = b64u_decode(params.protoparam or "")
	if op ~= "" then out.obfs_param = op end
	if pp ~= "" then out.protocol_param = pp end
	local grp = b64u_decode(params.group or "")
	if grp ~= "" then out.group = grp end
	return out
end

local function parse_vless(uri, body)
	local name, rest = "", body
	local hash = rest:find("#", 1, true)
	if hash then
		name = util.url_decode(rest:sub(hash + 1))
		rest = rest:sub(1, hash - 1)
	end
	local query = {}
	local qpos = rest:find("?", 1, true)
	local hp = rest
	if qpos then
		hp = rest:sub(1, qpos - 1)
		for k, v in rest:sub(qpos + 1):gmatch("([^&=]+)=([^&]*)") do
			query[k] = util.url_decode(v)
		end
	end
	local at = hp:find("@", 1, true)
	if not at then return nil, "bad vless" end
	local uuid = hp:sub(1, at - 1)
	local host, port = util.split_hostport(hp:sub(at + 1))
	local out = node.normalize({
		proto = "vless", name = name, server = host, port = tonumber(port), uuid = uuid, raw = uri,
	})
	if query.type then out.net = query.type end
	if query.security then out.security = query.security end
	if query.sni then out.sni = query.sni end
	if query.fp then out.fp = query.fp end
	if query.alpn then out.alpn = query.alpn end
	if query.headerType then out.headerType = query.headerType end
	return out
end

local function parse_trojan(uri, body)
	local name, rest = "", body
	local hash = rest:find("#", 1, true)
	if hash then
		name = util.url_decode(rest:sub(hash + 1))
		rest = rest:sub(1, hash - 1)
	end
	local query = {}
	local qpos = rest:find("?", 1, true)
	local hp = rest
	if qpos then
		hp = rest:sub(1, qpos - 1)
		for k, v in rest:sub(qpos + 1):gmatch("([^&=]+)=([^&]*)") do
			query[k] = util.url_decode(v)
		end
	end
	local at = hp:find("@", 1, true)
	if not at then return nil, "bad trojan" end
	local password = hp:sub(1, at - 1)
	local host, port = util.split_hostport(hp:sub(at + 1))
	local out = node.normalize({
		proto = "trojan", name = name, server = host, port = tonumber(port),
		password = password, raw = uri,
	})
	if query.sni then out.sni = query.sni end
	if query.security then out.security = query.security end
	if query.alpn then out.alpn = query.alpn end
	return out
end

local function parse_vmess(uri, body)
	local name, rest = "", body
	local hash = rest:find("#", 1, true)
	if hash then
		name = util.url_decode(rest:sub(hash + 1))
		rest = rest:sub(1, hash - 1)
	end
	-- v2rayN 新格式：vmess://uuid@host:port?type=tcp&security=none#name
	if rest:find("@", 1, true) then
		local query = {}
		local qpos = rest:find("?", 1, true)
		local hp = rest
		if qpos then
			hp = rest:sub(1, qpos - 1)
			for k, v in rest:sub(qpos + 1):gmatch("([^&=]+)=([^&]*)") do
				query[k] = util.url_decode(v)
			end
		end
		local at = hp:find("@", 1, true)
		local uuid = hp:sub(1, at - 1)
		local host, port = util.split_hostport(hp:sub(at + 1))
		local out = node.normalize({
			proto = "vmess", name = name, server = host, port = tonumber(port),
			uuid = uuid, raw = uri,
		})
		if query.type then out.net = query.type end
		if query.security then out.security = query.security end
		if query.sni then out.sni = query.sni end
		return out
	end
	-- 经典格式：vmess://base64(json)
	local decoded = util.base64_url_decode(rest)
	if decoded == "" then return nil, "bad vmess b64" end
	local j = util.json_decode(decoded)
	if type(j) ~= "table" or not j.add then return nil, "bad vmess json" end
	local out = node.normalize({
		proto = "vmess",
		name = j.ps or (j.add .. ":" .. tostring(j.port)),
		server = j.add, port = tonumber(j.port),
		uuid = j.id, aid = tonumber(j.aid),
		net = j.net, type = j.type, security = j.scy or j.security, tls = j.tls,
		raw = uri,
	})
	return out
end

-- hysteria2://password@host:port/?sni=..&insecure=..#name
local function parse_hysteria2(uri, body)
	local name, rest = "", body
	local hash = rest:find("#", 1, true)
	if hash then
		name = util.url_decode(rest:sub(hash + 1))
		rest = rest:sub(1, hash - 1)
	end
	local query = {}
	local qpos = rest:find("?", 1, true)
	local hp = rest
	if qpos then
		hp = rest:sub(1, qpos - 1)
		for k, v in rest:sub(qpos + 1):gmatch("([^&=]+)=([^&]*)") do
			query[k] = util.url_decode(v)
		end
	end
	local at = hp:find("@", 1, true)
	if not at then return nil, "bad hysteria2" end
	local password = util.url_decode(hp:sub(1, at - 1))
	local host, port = util.split_hostport(hp:sub(at + 1))
	local out = node.normalize({
		proto = "hysteria2", name = name, server = host, port = tonumber(port),
		password = password, raw = uri,
	})
	if query.sni then out.sni = query.sni end
	if query.insecure ~= nil then out.insecure = query.insecure end
	-- 混淆参数回读，保证导出→导入回环不丢字段
	if query.obfs then out.obfs = query.obfs end
	if query["obfs-password"] then out["obfs-password"] = query["obfs-password"] end
	return out
end

-- tuic://uuid:password@host:port/?congestion_control=..&alpn=..&sni=..#name
local function parse_tuic(uri, body)
	local name, rest = "", body
	local hash = rest:find("#", 1, true)
	if hash then
		name = util.url_decode(rest:sub(hash + 1))
		rest = rest:sub(1, hash - 1)
	end
	local query = {}
	local qpos = rest:find("?", 1, true)
	local hp = rest
	if qpos then
		hp = rest:sub(1, qpos - 1)
		for k, v in rest:sub(qpos + 1):gmatch("([^&=]+)=([^&]*)") do
			query[k] = util.url_decode(v)
		end
	end
	local at = hp:find("@", 1, true)
	if not at then return nil, "bad tuic" end
	local userinfo = util.url_decode(hp:sub(1, at - 1))
	local uuid, password = "", userinfo
	local cpos = userinfo:find(":", 1, true)
	if cpos then
		uuid = userinfo:sub(1, cpos - 1)
		password = userinfo:sub(cpos + 1)
	end
	local host, port = util.split_hostport(hp:sub(at + 1))
	local out = node.normalize({
		proto = "tuic", name = name, server = host, port = tonumber(port),
		uuid = uuid, password = password, raw = uri,
	})
	if query.congestion_control then out.congestion_control = query.congestion_control end
	if query.alpn then out.alpn = query.alpn end
	if query.sni then out.sni = query.sni end
	return out
end

-- wireguard://base64(json)#name —— 本项目自定义 scheme（wireguard 无统一 URI 标准）
local function parse_wireguard(uri, body)
	local name, rest = "", body
	local hash = rest:find("#", 1, true)
	if hash then
		name = util.url_decode(rest:sub(hash + 1))
		rest = rest:sub(1, hash - 1)
	end
	local decoded = util.base64_decode(rest)
	if decoded == "" then return nil, "bad wireguard" end
	local j = util.json_decode(decoded)
	if type(j) ~= "table" or not j.server or not j.port then return nil, "bad wireguard json" end
	local out = node.normalize({
		proto = "wireguard", name = name, server = j.server, port = tonumber(j.port),
		["private-key"] = j["private-key"] or j.private_key,
		["peer-public-key"] = j["peer-public-key"] or j.peer_public_key or j["public-key"] or j.public_key,
		["public-key"] = j["public-key"] or j.public_key or j["peer-public-key"] or j.peer_public_key,
		["preshared-key"] = j["preshared-key"] or j.preshared_key or j["pre-shared-key"] or j.pre_shared_key,
		["pre-shared-key"] = j["pre-shared-key"] or j.pre_shared_key or j["preshared-key"] or j.preshared_key,
		ip = j.ip or j["local-address"] or j.local_address,
		ipv6 = j.ipv6,
		["allowed-ips"] = j["allowed-ips"] or j.allowed_ips,
		reserved = j.reserved,
		["persistent-keepalive"] = j["persistent-keepalive"] or j.persistent_keepalive,
		mtu = tonumber(j.mtu),
		dns = j.dns,
		["amnezia-wg-option"] = j["amnezia-wg-option"] or j.amnezia_wg_option,
		raw = uri,
	})
	if out.name == "" and j.name then out.name = j.name end
	return out
end

-- AmneziaWG 参数随版本演进，未知键直接丢弃：不猜语义，避免把上游新参数错误映射到 mihomo 字段。
-- 取值统一走 tonumber-or-raw：数值型（jc/s1/h1…）转数字；非数值载荷（i1..i5、h1 的 "a-b" 区间）保留字符串。
local AWG_CONF_KEYS = {
	"jc", "jmin", "jmax", "s1", "s2", "s3", "s4",
	"h1", "h2", "h3", "h4",
	"i1", "i2", "i3", "i4", "i5",
	"j1", "j2", "j3", "itime",
}

-- wg-quick / AmneziaWG .conf 解析（[Interface] / [Peer] 分段，Key = Value）
-- AmneziaWG 客户端导出的 .conf 即标准 wg-quick 格式 + Jc/Jmin/Jmax/S1/S2/H1..H4 等键
local function parse_wireguard_conf(content)
	local iface, peer = {}, {}
	local section = nil
	for line in content:gmatch("[^\r\n]+") do
		local s = util.trim(line)
		if s == "" or s:sub(1, 1) == "#" or s:sub(1, 1) == ";" then
			-- 空行 / 注释
		elseif s:sub(1, 1) == "[" then
			local name = s:match("^%[%s*(.-)%s*%]")
			name = name and name:lower() or ""
			if name == "interface" then section = iface
			elseif name == "peer" then section = peer
			else section = nil end
		elseif section then
			local k, v = s:match("^([^=]+)=(.*)$")
			if k then
				k = util.trim(k):lower()
				v = util.trim(v)
				if v ~= "" then section[k] = v end
			end
		end
	end

	local host, port = util.split_hostport(peer["endpoint"] or "")
	if not host or host == "" or not port then return nil, "bad wireguard conf: no endpoint" end

	local out = {
		proto = "wireguard",
		server = host,
		port = tonumber(port),
		["private-key"] = iface["privatekey"],
		["public-key"] = peer["publickey"],
		["pre-shared-key"] = peer["presharedkey"],
		["persistent-keepalive"] = tonumber(peer["persistentkeepalive"]),
		["listen-port"] = tonumber(iface["listenport"]),
		mtu = tonumber(iface["mtu"]),
	}

	-- Address 可含多个地址（逗号分隔），按是否含 ":" 分别归入 ip / ipv6
	for a in (iface["address"] or ""):gmatch("[^,]+") do
		a = util.trim(a)
		if a ~= "" then
			if a:find(":", 1, true) then
				if out.ipv6 == nil then out.ipv6 = a end
			else
				if out.ip == nil then out.ip = a end
			end
		end
	end

	-- AllowedIPs 拆分数组
	local allowed = {}
	for a in (peer["allowedips"] or ""):gmatch("[^,]+") do
		a = util.trim(a)
		if a ~= "" then allowed[#allowed + 1] = a end
	end
	if #allowed > 0 then out["allowed-ips"] = allowed end

	-- DNS 拆分：单值存字符串，多值存数组
	local dns = {}
	for a in (iface["dns"] or ""):gmatch("[^,]+") do
		a = util.trim(a)
		if a ~= "" then dns[#dns + 1] = a end
	end
	if #dns == 1 then out.dns = dns[1]
	elseif #dns > 1 then out.dns = dns end

	-- Reserved（部分客户端写法，逗号或空格分隔）
	local reserved = {}
	for a in (iface["reserved"] or ""):gmatch("[^,%s]+") do
		reserved[#reserved + 1] = tonumber(a) or a
	end
	if #reserved > 0 then out.reserved = reserved end

	-- AmneziaWG 参数
	local awg = {}
	for _, k in ipairs(AWG_CONF_KEYS) do
		local raw = iface[k]
		if raw ~= nil and raw ~= "" then
			awg[k] = tonumber(raw) or raw
		end
	end
	if next(awg) then out["amnezia-wg-option"] = awg end

	return node.normalize(out)
end

-- 解析单条节点 URI，返回节点表或 nil, err
function M.parse_uri(uri)
	uri = util.trim(uri)
	local proto, body = uri:match("^([%w]+)://(.*)$")
	if not proto then return nil, "no scheme" end
	proto = proto:lower()
	if not SUPPORTED[proto] then return nil, "unsupported proto " .. proto end
	if proto == "ss" then return parse_ss(body) end
	if proto == "ssr" then return parse_ssr(body) end
	if proto == "vless" then return parse_vless(uri, body) end
	if proto == "trojan" then return parse_trojan(uri, body) end
	if proto == "vmess" then return parse_vmess(uri, body) end
	if proto == "hysteria2" then return parse_hysteria2(uri, body) end
	if proto == "tuic" then return parse_tuic(uri, body) end
	if proto == "wireguard" then return parse_wireguard(uri, body) end
	return nil, "unsupported"
end

local function parse_lines(lines)
	local nodes = {}
	for _, line in ipairs(lines) do
		line = util.trim(line)
		if line ~= "" and line:find("://", 1, true) then
			local n = M.parse_uri(line)
			if n then nodes[#nodes + 1] = n end
		end
	end
	return nodes
end

local function parse_json_content(content)
	local data = util.json_decode(content)
	if type(data) ~= "table" then return nil, "JSON 解析失败" end

	-- 客户端配置文件分发：sing-box / V2Ray / Clash JSON
	if type(data.outbounds) == "table" then
		local first = data.outbounds[1]
		if type(first) == "table" and first.protocol then
			return parser_json_config.parse_v2ray_json(content), nil
		end
		return parser_json_config.parse_singbox_json(content), nil
	end
	if type(data.proxies) == "table" then
		return parser_json_config.parse_clash_json(content), nil
	end

	-- 通用节点数组 / 单节点对象
	local list
	if data[1] then list = data else list = { data } end
	local nodes = {}
	for _, o in ipairs(list) do
		if type(o) == "table" and o.server and o.port then
			nodes[#nodes + 1] = node.normalize({
				proto = o.proto or "vmess",
				name = o.name or (o.server .. ":" .. o.port),
				server = o.server, port = tonumber(o.port),
				uuid = o.uuid, password = o.password, method = o.method,
				net = o.net, security = o.security, sni = o.sni,
				raw = o.raw,
			})
		end
	end
	return nodes, nil
end

-- 简易 YAML 解析器：处理 Clash YAML proxies 格式
-- 支持基本键值对和列表项，不处理复杂嵌套
local function parse_yaml_content(content)
	local raw_nodes = {}
	local lines = split_lines(content)
	local current_node = nil
	local in_proxies = false
	local proxies_indent = 0

	for i, line in ipairs(lines) do
		local trimmed = util.trim(line)
		if trimmed == "" or trimmed:sub(1, 1) == "#" then
			-- 跳过空行和注释
		elseif trimmed:match("^proxies:%s*$") or trimmed:match("^outbounds:%s*$") then
			in_proxies = true
			proxies_indent = line:match("^%s*") and #line:match("^%s*") or 0
			current_node = nil
		elseif in_proxies then
			-- 检测列表项开始：- name: xxx 或单独的 -
			local list_match = line:match("^%s*%-%s*(.*)$")
			if list_match then
				-- 保存上一个节点
				if current_node then
					raw_nodes[#raw_nodes + 1] = current_node
				end
				current_node = {}
				-- 检查列表项同一行是否有字段
				if list_match:match("^([^:]+):%s*(.+)$") then
					local k, v = list_match:match("^([^:]+):%s*(.+)$")
					current_node[k] = util.trim(v)
				end
			else
				-- 解析缩进的字段
				local indent = line:match("^%s*") and #line:match("^%s*") or 0
				if current_node and indent > proxies_indent then
					local k, v = trimmed:match("^([^:]+):%s*(.+)$")
					if k then
						k = util.trim(k)
						v = util.trim(v)
						-- 去掉引号
						v = v:gsub('^["\'](.*)["\']$', '%1')
						current_node[k] = v
					end
				else
					-- 遇到缩进减少，结束当前节点
					if current_node then
						raw_nodes[#raw_nodes + 1] = current_node
						current_node = nil
					end
					in_proxies = false
				end
			end
		end
	end

	-- 保存最后一个节点
	if current_node then
		raw_nodes[#raw_nodes + 1] = current_node
	end

	-- 协议映射：Clash type -> proto
	local proto_map = {
		vmess = "vmess",
		vless = "vless",
		trojan = "trojan",
		ss = "shadowsocks",
		ssr = "ssr",
		http = "http",
		socks5 = "socks5",
	}

	-- 转换字段名并归一化
	local result = {}
	for _, n in ipairs(raw_nodes) do
		if not n or not n.server or not n.port then
			-- 跳过无效节点
		else
			local proto = proto_map[n.type or n.proto] or "vmess"
			local node_data = {
				proto = proto,
				name = n.name or n.Name or (n.server .. ":" .. tostring(n.port or "")),
				server = n.server,
				port = tonumber(n.port),
				uuid = n.uuid or n.id,
				password = n.password,
				method = n.cipher or n.method,
				net = n.network or n.net,
				security = n.tls or n.security,
				sni = n.sni or n.servername,
				alterId = tonumber(n.alterId),
			}
			result[#result + 1] = node.normalize(node_data)
		end
	end

	return result
end

function M.parse_yaml(content)
	-- 优先使用完整 Clash YAML 解析器；失败/为空则回退简易解析
	local nodes = parser_clash_yaml.parse(content)
	if nodes and #nodes > 0 then return nodes end
	return parse_yaml_content(content)
end

-- ---------- 局域网订阅链接 ----------

-- 判断主机是否为内网 / 回环 / 链路本地地址（SSRF 防护）
local function is_private_host(host)
	if not host then return false end
	host = host:lower()
	if host == "localhost" or host == "::" then return true end
	-- IPv6：去掉方括号
	local v6 = host:match("^%[([^%]]+)%]$")
	if v6 then host = v6 end
	if host:find(":", 1, true) then
		local h = host:gsub("^0*", "")
		if h == "" or h == "1" then return true end -- :: 或 ::1
		return host:match("^::") ~= nil
			or host:match("^f[cd]") ~= nil
			or host:match("^fe[89ab]") ~= nil
	end
	local a, b, c, d = host:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
	if not a then return false end
	a, b, c, d = tonumber(a), tonumber(b), tonumber(c), tonumber(d)
	if a == 0 or a == 127 or a == 10 then return true end
	if a == 100 and b >= 64 and b <= 127 then return true end -- CGNAT 100.64/10
	if a == 192 and b == 168 then return true end
	if a == 172 and b >= 16 and b <= 31 then return true end
	if a == 169 and b == 254 then return true end
	return false
end

-- 检测是否为局域网订阅链接（http/https + 内网主机）
function M.detect_local_link(url)
	url = util.trim(url or "")
	local scheme, rest = url:match("^(%a+)://(.*)$")
	if not scheme then return nil end
	scheme = scheme:lower()
	if scheme ~= "http" and scheme ~= "https" then return nil end
	local authority = rest:match("^([^/]*)") or ""
	if authority == "" then return nil end
	-- 去除 userinfo@
	if authority:find("@", 1, true) then
		authority = authority:match("^.*@(.*)$") or ""
	end
	local host
	if authority:sub(1, 1) == "[" then
		host = authority:match("^(%[.-%])")
	else
		host = authority:match("^([^:]+)")
	end
	if is_private_host(host) then return true end
	return nil
end

-- 解析局域网订阅链接，返回 { scheme, host, port, path, target, name, user }（host/port/path 为字符串；缺失为 nil）
function M.parse_local_link(url)
	url = util.trim(url or "")
	local scheme, rest = url:match("^(%a+)://(.*)$")
	if not scheme then return nil end
	scheme = scheme:lower()

	local authority, remainder = rest:match("^([^/]*)(.*)$")
	if authority == nil then authority, remainder = rest, "" end

	-- 提取 host 与 port
	local host, port
	if authority:sub(1, 1) == "[" then
		host = authority:match("^%[([^%]]+)%]")
		port = authority:match("^%[[^%]]+%]:(%d+)")
	else
		host = authority:match("^([^:]+)")
		port = authority:match("^[^:]+:(%d+)")
	end

	-- 拆分 path 与 query
	local path, query = remainder:match("^([^?]*)(.*)$")
	if path == nil then path, query = remainder, "" end

	local params = {}
	if query and query ~= "" then
		for k, v in query:sub(2):gmatch("([^&=]+)=([^&]*)") do
			params[k] = util.url_decode(v)
		end
	end

	-- name：优先 ?name=；否则取路径最后一段
	local name = params.name
	if not name or name == "" then
		name = path and path:match("/([^/]+)$")
	end

	-- user：优先 ?uid= / ?user=；否则取 /<user>/download/ 路径中的用户名
	local user = params.uid or params.user
	if not user or user == "" then
		user = path and path:match("/([^/]+)/download/")
	end

	return {
		scheme = scheme, host = host, port = port, path = path,
		target = params.target, name = name, user = user,
	}
end

-- 解析订阅内容，返回 { nodes = {...}, format = "..." } 或 nil, err
function M.parse(content)
	if not content or content == "" then return { nodes = {}, format = "empty" } end
	local format = M.detect(content)
	if format == "uri" then
		return { nodes = parse_lines(split_lines(content)), format = "uri" }
	elseif format == "base64" then
		-- 兼容标准 base64 与 base64url（- _ 无 padding）：base64_url_decode 两者皆可
		local decoded = util.base64_url_decode(content)
		if decoded == "" then return nil, "Base64 解码失败" end
		return { nodes = parse_lines(split_lines(decoded)), format = "base64" }
	elseif format == "json" then
		local nodes, err = parse_json_content(content)
		if not nodes then return nil, err end
		return { nodes = nodes, format = "json" }
	elseif format == "yaml" then
		local nodes = M.parse_yaml(content)
		return { nodes = nodes, format = "yaml" }
	elseif format == "surge" then
		local nodes = parser_surge.parse(content)
		return { nodes = nodes, format = "surge" }
	elseif format == "wireguard-conf" then
		local n, err = parse_wireguard_conf(content)
		if not n then return nil, err end
		return { nodes = { n }, format = "wireguard-conf" }
	end
	return nil, "无法识别的订阅格式"
end

-- 本地订阅解析：支持文本模式和表单模式
function M.parse_local(content, mode)
	mode = mode or "text"
	if not content or content == "" then return { nodes = {}, format = "empty" } end
	if mode == "form" then
		-- 表单模式：content 为 JSON 数组
		local data = util.json_decode(content)
		if type(data) ~= "table" then return nil, "表单数据解析失败" end
		local node_mod = require("substore.node")
		local nodes = {}
		for _, item in ipairs(data) do
			if type(item) == "table" then
				-- 透传表单全部字段，仅做协议/别名/类型修正，避免白名单丢字段
				local n = {}
				for k, v in pairs(item) do n[k] = v end
				n.proto = item.type or item.proto or "vmess"
				n.type = nil
				if n.net == nil and n.network ~= nil then n.net = n.network end
				n.network = nil
				n.port = tonumber(n.port) or n.port
				if n.alterId ~= nil then n.alterId = tonumber(n.alterId) or n.alterId end
				-- 字符串布尔转布尔值
				for _, bk in ipairs({ "udp", "skip-cert-verify", "skip_cert_verify" }) do
					if type(n[bk]) == "string" then
						n[bk] = (n[bk] == "true" or n[bk] == "1")
					end
				end
				if n["skip-cert-verify"] ~= nil and n.skip_cert_verify == nil then
					n.skip_cert_verify = n["skip-cert-verify"]
				end
				-- shadowsocks 用 method；vmess/ssr 用 cipher，互为别名
				if n.method == nil and n.cipher ~= nil then n.method = n.cipher end
				if n.cipher == nil and n.method ~= nil then n.cipher = n.method end
				-- SSR 参数别名
				if n.obfs_param == nil and n["obfs-param"] ~= nil then n.obfs_param = n["obfs-param"] end
				if n.protocol_param == nil and n["protocol-param"] ~= nil then n.protocol_param = n["protocol-param"] end
				if n.name == nil or n.name == "" then
					n.name = (n.server or "") .. ":" .. tostring(n.port or "")
				end
				nodes[#nodes + 1] = node_mod.normalize(n)
			end
		end
		return { nodes = nodes, format = "local-form" }
	end
	-- 文本模式：使用通用解析
	return M.parse(content)
end

return M