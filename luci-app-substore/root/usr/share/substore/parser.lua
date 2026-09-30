-- parser.lua — 订阅格式解析 → 统一节点模型（纯 Lua）
-- luci-app-substore

local util = require("substore.util")
local node = require("substore.node")
local parser_yaml = require("substore.parser_yaml")
local parser_clash_yaml = require("substore.parser_clash_yaml")
local parser_json_config = require("substore.parser_json_config")
local parser_surge = require("substore.parser_surge")

local M = {}

-- URI 文本导入支持的 scheme。
-- 必须覆盖 output_uri.to_share_uri 能生成的全部 scheme，否则「导出→导入」回环会
-- 丢节点：之前 hysteria / socks 只出不进（导出为 hysteria:// / socks5://，
-- 再导入却报 "unsupported proto"），含这两类节点的订阅文本也会被整行丢弃。
-- socks5 与 socks 都接受，统一归一为 proto="socks"（见 node.normalize）。
local SUPPORTED = {
	vmess = true, vless = true, trojan = true, ss = true, ssr = true,
	hysteria = true, hysteria2 = true, tuic = true, wireguard = true,
	socks = true, socks5 = true,
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
	-- Surge / Loon：必须排在下面的 URI 兜底判断之前。
	-- Surge 配置头部的 "#!MANAGED-CONFIG https://…" 含 "://"，排在后面会被判成 uri，
	-- 于是整份订阅解析出 0 个节点，且因为 parse 返回的是合法表，同步还会报成功。
	if parser_surge.is_config(content) then return "surge" end
	-- JSON 数组（节点数组）：必须排在 .conf 判断之后，否则 "[Interface]" 会被当成数组
	if stripped:sub(1, 1) == "[" then return "json" end
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

-- SSR 参数值可能为 base64url、标准 base64 或纯文本：优先 base64url 解码，失败回退 URL 解码。
-- util.base64_url_decode 永远不会「失败」——它把非 base64 字符直接剔掉再解码，
-- 所以纯文本也会解出乱码字节而不是空串，原来的 `if v ~= ""` 回退分支根本不可达，
-- 节点名 / obfsparam / group 会被解成乱码（并写盘、下发）。
-- 可靠的判据是往返一致性：合法 base64url 重新编码后与原文逐字符相同，纯文本不会。
local function b64u_decode(s)
	s = s or ""
	local v = util.base64_url_decode(s)
	if v ~= "" and util.base64_url_encode(v) == (s:gsub("=+$", "")) then
		return v
	end
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
	-- path / host / flow 以前没有回读：output_uri 会写出这三个参数，读不回来就造成
	-- 往返丢字段。丢 path/host 的后果尤其严重——Clash 输出会得到 network: ws 却没有
	-- ws-opts.path，客户端请求 "/" 而非真实路径，节点直接连不上。
	-- flow 是 XTLS Vision（xtls-rprx-vision）的必需参数，丢了同样握手失败。
	if query.path then out.path = query.path end
	if query.host then out.host = query.host end
	if query.flow then out.flow = query.flow end
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
	-- trojan 同样支持 ws/grpc 等传输：output_uri 会写出 type/path/host/fp，
	-- 以前只回读 sni/security/alpn，造成往返丢字段
	if query.type then out.net = query.type end
	if query.path then out.path = query.path end
	if query.host then out.host = query.host end
	if query.fp then out.fp = query.fp end
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
		if query.fp then out.fp = query.fp end
		if query.alpn then out.alpn = query.alpn end
		-- 同上：vmess 新版 URI 也带 host / path / headerType
		if query.host then out.host = query.host end
		if query.path then out.path = query.path end
		if query.headerType then out.headerType = query.headerType end
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
		uuid = j.id, alterId = tonumber(j.aid),
		net = j.net, type = j.type,
		-- scy 是 vmess 加密方式（cipher），不是 TLS 层；TLS 由 tls 字段表达
		-- （"tls" 表示启用，"" 表示不启用）
		cipher = j.scy or j.security,
		security = (j.tls == "tls" or j.tls == true) and "tls" or nil,
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
	-- hysteria2 / hysteria 在 sing-box 与 mihomo 里都是 TLS-only，而 hy2 URI 不带
	-- security 参数。不补上的话 output_singbox.build_tls 直接返回 nil，
	-- sni / insecure 全部丢失，生成的 outbound 不可用。
	out.security = "tls"
	-- insecure 是 URI 参数名，模型里的权威字段是 skip-cert-verify
	-- （parser_json_config 也把 sing-box 的 tls.insecure 映射到它）。
	-- 两个都保留：skip-cert-verify 供各输出消费，insecure 供 URI 回写。
	if query.insecure ~= nil then
		out.insecure = query.insecure
		out["skip-cert-verify"] = not (query.insecure == "0" or query.insecure == "false")
	end
	-- 混淆参数回读，保证导出→导入回环不丢字段
	if query.obfs then out.obfs = query.obfs end
	if query["obfs-password"] then out["obfs-password"] = query["obfs-password"] end
	return out
end

-- hysteria://password@host:port/?sni=..&insecure=..&obfs=..#name（v1）
-- 与 hysteria2 的区别（均已对照上游确认）：
--   * v1 的 obfs 是普通字符串，没有 obfs-password（obfs-password 是 hysteria2 的 salamander）
--   * 两者在 mihomo / sing-box 里都是 TLS-only，因此同样补 security="tls"
-- 认不出的查询参数一律忽略（不报错），保证第三方生成的链接仍能解析出 server/port/password。
local function parse_hysteria(uri, body)
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
	if not at then return nil, "bad hysteria" end
	local password = util.url_decode(hp:sub(1, at - 1))
	local host, port = util.split_hostport(hp:sub(at + 1))
	if not host or host == "" then return nil, "bad hysteria" end
	local out = node.normalize({
		proto = "hysteria", name = name, server = host, port = tonumber(port),
		password = password, raw = uri,
	})
	if query.sni then out.sni = query.sni end
	out.security = "tls"
	if query.insecure ~= nil then
		out.insecure = query.insecure
		out["skip-cert-verify"] = not (query.insecure == "0" or query.insecure == "false")
	end
	if query.obfs and query.obfs ~= "" then out.obfs = query.obfs end
	return out
end

-- socks5://user:pass@host:port#name（socks:// 同义）
-- 认证信息可选：没有 userinfo 时是无认证 socks。统一归一为 proto="socks"。
local function parse_socks(uri, body)
	local name, rest = "", body
	local hash = rest:find("#", 1, true)
	if hash then
		name = util.url_decode(rest:sub(hash + 1))
		rest = rest:sub(1, hash - 1)
	end
	-- socks 没有标准查询参数，但第三方链接可能带 ? 尾巴，截掉以免污染 host:port
	local qpos = rest:find("?", 1, true)
	local hp = qpos and rest:sub(1, qpos - 1) or rest

	local username, password
	-- 取**最后**一个 @ 作为 userinfo 与 authority 的分界：未编码的 @ 只可能出现在
	-- 密码里（userinfo 不允许裸 @），按第一个 @ 切会把 "p@ss" 这类密码切坏，
	-- 而且失败是静默的（解析出一个错的密码）。
	local userinfo, hostport = hp:match("^(.*)@([^@]*)$")
	if not userinfo then
		hostport = hp
	else
		userinfo = util.url_decode(userinfo)
		local cpos = userinfo:find(":", 1, true)
		if cpos then
			username = userinfo:sub(1, cpos - 1)
			password = userinfo:sub(cpos + 1)
		else
			username = userinfo
		end
		if username == "" then username = nil end
	end

	local host, port = util.split_hostport(hostport)
	if not host or host == "" then return nil, "bad socks" end
	local out = node.normalize({
		proto = "socks", name = name, server = host, port = tonumber(port), raw = uri,
	})
	if username then out.username = username end
	if password then out.password = password end
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

-- AmneziaWG 参数。字段名与类型逐字段核对自两份一手来源，不靠推断：
--   .conf 键名 → amneziawg-tools src/config.c（process_line，大小写不敏感）
--   规范名/类型 → mihomo adapter/outbound/wireguard.go 的 AmneziaWGOption（proxy tag）
-- 内部规范名 = mihomo 的 proxy tag（小写连字符）：Clash 输出直接透传这些键名，
-- 所以必须与 mihomo 一致；.conf 导出时再用显式映射换成 CamelCase。
-- 未列入的键一律丢弃（不猜语义，§110）。
local AWG_CONF_FIELDS = {
	-- v1.0
	jc = "jc", jmin = "jmin", jmax = "jmax",
	s1 = "s1", s2 = "s2",
	h1 = "h1", h2 = "h2", h3 = "h3", h4 = "h4",
	-- v1.5
	s3 = "s3", s4 = "s4",
	i1 = "i1", i2 = "i2", i3 = "i3", i4 = "i4", i5 = "i5",
	j1 = "j1", j2 = "j2", j3 = "j3", itime = "itime",
	-- v3.0
	headerprotectionkey = "header-protection-key",
	contentpaddingaddition = "content-padding-addition",
	rekeyaftertime = "rekey-after-time",
	rekeytimeout = "rekey-timeout",
	rejectaftertime = "reject-after-time",
	keepalivetimeout = "keepalive-timeout",
	maxhandshakeattempts = "max-handshake-attempts",
	-- v3.1
	randomtrailers = "random-trailers",
	disablecookies = "disable-cookies",
}

-- 布尔字段（mihomo 侧类型为 bool）。amneziawg-tools 的 parse_bool 只认
-- on/off（大小写不敏感）或十进制数（0 假、非 0 真）；true/false/yes/no 都是非法值。
-- 非法值一律丢弃：留着会让 mihomo 解析该字段时报错。
local AWG_BOOL_FIELDS = {
	["random-trailers"] = true,
	["disable-cookies"] = true,
}

-- on/off 或十进制数 → 布尔；其余返回 nil（非法值，丢弃）
local function awg_bool(raw)
	local s = tostring(raw or ""):lower()
	if s == "on" then return true end
	if s == "off" then return false end
	if s:match("^%d+$") then return tonumber(s) ~= 0 end
	return nil
end

-- wg-quick / AmneziaWG .conf 解析（[Interface] / [Peer] 分段，Key = Value）
-- AmneziaWG 客户端导出的 .conf 即标准 wg-quick 格式 + Jc/Jmin/Jmax/S1/S2/H1..H4 等键
-- 一个 .conf 可以含多个 [Peer]（wg-quick 的多对端隧道）。本项目的节点模型是
-- 「一个节点 = 一个对端」，无法表达多对端隧道；旧实现把所有 [Peer] 写进同一个表，
-- 后一段覆盖前一段，结果既丢掉前面的对端，又可能把 A 段的 PresharedKey 和
-- B 段的 Endpoint 拼成一个并不存在的节点。这里改为每个 [Peer] 生成一个节点，
-- 共享同一份 [Interface] 设置。返回 nodes 数组；失败返回 nil, err。
local function parse_wireguard_conf(content)
	local iface = {}
	local peers = {}
	local section = nil
	for line in content:gmatch("[^\r\n]+") do
		local s = util.trim(line)
		if s == "" or s:sub(1, 1) == "#" or s:sub(1, 1) == ";" then
			-- 空行 / 注释
		elseif s:sub(1, 1) == "[" then
			local name = s:match("^%[%s*(.-)%s*%]")
			name = name and name:lower() or ""
			if name == "interface" then
				section = iface
			elseif name == "peer" then
				local p = {}
				peers[#peers + 1] = p
				section = p
			else
				section = nil
			end
		elseif section then
			local k, v = s:match("^([^=]+)=(.*)$")
			if k then
				k = util.trim(k):lower()
				v = util.trim(v)
				if v ~= "" then section[k] = v end
			end
		end
	end

	if #peers == 0 then return nil, "bad wireguard conf: no [Peer]" end

	-- [Interface] 由各节点共享
	local common = {
		proto = "wireguard",
		["private-key"] = iface["privatekey"],
		["listen-port"] = tonumber(iface["listenport"]),
		mtu = tonumber(iface["mtu"]),
	}

	-- Address 可含多个地址（逗号分隔），按是否含 ":" 分别归入 ip / ipv6
	for a in (iface["address"] or ""):gmatch("[^,]+") do
		a = util.trim(a)
		if a ~= "" then
			if a:find(":", 1, true) then
				if common.ipv6 == nil then common.ipv6 = a end
			else
				if common.ip == nil then common.ip = a end
			end
		end
	end

	-- DNS 拆分：单值存字符串，多值存数组
	local dns = {}
	for a in (iface["dns"] or ""):gmatch("[^,]+") do
		a = util.trim(a)
		if a ~= "" then dns[#dns + 1] = a end
	end
	if #dns == 1 then common.dns = dns[1]
	elseif #dns > 1 then common.dns = dns end

	-- Reserved（部分客户端写法，逗号或空格分隔）
	local reserved = {}
	for a in (iface["reserved"] or ""):gmatch("[^,%s]+") do
		reserved[#reserved + 1] = tonumber(a) or a
	end
	if #reserved > 0 then common.reserved = reserved end

	-- AmneziaWG [Interface] 参数：按 AWG_CONF_FIELDS 映射成规范名
	local awg = {}
	for ck, canon in pairs(AWG_CONF_FIELDS) do
		local raw = iface[ck]
		if raw ~= nil and raw ~= "" then
			if AWG_BOOL_FIELDS[canon] then
				local b = awg_bool(raw)
				if b ~= nil then awg[canon] = b end
			else
				awg[canon] = tonumber(raw) or raw
			end
		end
	end

	local nodes = {}
	for _, p in ipairs(peers) do
		local host, port = util.split_hostport(p["endpoint"] or "")
		if not host or host == "" or not port then return nil, "bad wireguard conf: no endpoint" end

		local out = {}
		for k, v in pairs(common) do out[k] = v end
		out.server = host
		out.port = tonumber(port)
		out["public-key"] = p["publickey"]
		out["pre-shared-key"] = p["presharedkey"]
		out["persistent-keepalive"] = tonumber(p["persistentkeepalive"])

		-- AllowedIPs 拆分数组
		local allowed = {}
		for a in (p["allowedips"] or ""):gmatch("[^,]+") do
			a = util.trim(a)
			if a ~= "" then allowed[#allowed + 1] = a end
		end
		if #allowed > 0 then out["allowed-ips"] = allowed end

		-- [Peer] 段的 AmneziaWG 参数（AdvancedSecurity）不在此处解析：
		-- 它属于 [Peer] 段，而本项目的 amnezia-wg-option 只对应 [Interface] 段，
		-- 合并进来会在导出时被写到 [Interface] 下（错误段落）。宁可不支持，
		-- 也不要产出一份键位置错误的 .conf（§110）。
		-- 每个节点各拿一份副本：共享同一个表会让后续修改一处影响全部节点。
		if next(awg) then
			local o = {}
			for k, v in pairs(awg) do o[k] = v end
			out["amnezia-wg-option"] = o
		end

		nodes[#nodes + 1] = node.normalize(out)
	end

	return nodes
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
	if proto == "hysteria" then return parse_hysteria(uri, body) end
	if proto == "hysteria2" then return parse_hysteria2(uri, body) end
	if proto == "tuic" then return parse_tuic(uri, body) end
	if proto == "wireguard" then return parse_wireguard(uri, body) end
	if proto == "socks" or proto == "socks5" then return parse_socks(uri, body) end
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

	-- 协议映射：Clash type -> proto。
	-- 复用 parser_clash_yaml 的权威表（单一事实来源），本处曾自维护一份，缺
	-- hysteria2/hysteria/tuic/wireguard 且 socks5 未归一，后果是：
	--   * 认不出的 type 被 `or "vmess"` 兜底成 vmess —— 一份 sing-box YAML 里的
	--     hysteria2/tuic/wireguard 出站会变成 4 个没有 uuid 的假 vmess 节点（静默数据损坏）
	--   * socks5 原样保留，而节点页筛选/规则 proto_filter 用的是规范名 socks，节点查不到
	local proto_map = parser_clash_yaml.TYPE_MAP

	-- 转换字段名并归一化
	local result = {}
	for _, n in ipairs(raw_nodes) do
		local proto = proto_map[n.type or n.proto]
		-- 上面的 in_proxies 分支同时接受 `proxies:`（Clash）与 `outbounds:`（sing-box）
		-- 两种段名，但两者字段名并不相同：Clash 用 port / name，sing-box 用
		-- server_port / tag。此前只读 port / name，导致 sing-box YAML 的 outbounds
		-- 全部卡在下面的 `not port` 判断上被静默丢弃（识别了段名却一个节点都拿不到）。
		-- 下列别名逐字对照 parser_json_config.parse_singbox_json 读取的键名，
		-- 那是本项目读取 sing-box 出站的权威实现，不另立一套。
		local port = n.port or n.server_port
		if not n or not n.server or not port or not proto then
			-- 跳过无效节点 / 未知协议。
			-- 未知协议不能兜底成 vmess：那是凭空造出一个字段全错的节点，
			-- 比丢弃更糟（用户看到"导入成功"，实际拿到一批不可用的假节点）。
		else
			-- vmess 的加密方式：Clash 写 cipher，sing-box 写 security。
			-- security 在 node.normalize 里是 TLS 层，两者语义冲突，因此仅当取值
			-- 落在 vmess 加密方式白名单内时才当作 cipher 消费掉，否则留给 TLS 层。
			local vmess_cipher
			if proto == "vmess" then
				vmess_cipher = n.cipher
				if vmess_cipher == nil and n.security ~= nil
					and node.VMESS_CIPHERS[n.security] then
					vmess_cipher = n.security
				end
			end
			-- 同上的字符串真值问题：只认明确的真值写法
			local scv = n["skip-cert-verify"] or n.insecure
			local skip_cert_verify = nil
			if scv == true or scv == "true" or scv == "1" then skip_cert_verify = true
			elseif scv == false or scv == "false" or scv == "0" then skip_cert_verify = false end
			-- 注意不能用 `(cond) and nil or x` 写法：Lua 的 and/or 在 cond 为真时
			-- 结果是 nil，会被后面的 or 继续兜底，等于没生效
			local tls_security = n.security
			if vmess_cipher ~= nil then tls_security = nil end
			local node_data = {
				proto = proto,
				name = n.name or n.Name or n.tag or (n.server .. ":" .. tostring(port)),
				server = n.server,
				port = tonumber(port),
				uuid = n.uuid or n.id,
				-- sing-box 的 hysteria/hysteria2 认证字段是 password / auth_str / auth
				password = n.password or n.auth_str or n.auth,
				method = n.cipher or n.method,
				-- Clash 的 cipher 是 vmess 加密方式；tls 才是 TLS 层，
				-- 交由 node.normalize 归一到 security
				cipher = vmess_cipher,
				tls = n.tls,
				-- sing-box 的 vmess.security 已被上面消费为 cipher，不再当 TLS 层
				security = tls_security,
				-- Clash 写 sni / servername，sing-box 的 tls 子块写 server_name
				sni = n.sni or n.servername or n.server_name,
				-- sing-box 的 tls.insecure 对应 skip-cert-verify。
				-- 行解析器读出来的是字符串，而 "false" / "0" 在 Lua 里也是真值，
				-- 直接透传会让 skip-cert-verify=false 变成「跳过证书校验」，故显式判假。
				["skip-cert-verify"] = skip_cert_verify,
				net = n.net or n.network,
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
		-- 解出来的内容本身可能是 YAML / JSON：机场把整份 Clash 配置或 sing-box
		-- 配置 base64 后直接下发是很常见的做法。原先一律按 URI 列表解析，这类
		-- 订阅会得到 0 个节点且不报错（用户只看到「订阅为空」）。
		-- 递归走一遍 detect/parse 复用既有分支；inner == "base64" 时不再递归，
		-- 避免 base64 套 base64 时无限递归。外层容器格式仍是 base64。
		local inner = M.detect(decoded)
		if inner ~= "base64" and inner ~= "empty" and inner ~= "unknown" then
			local res, err = M.parse(decoded)
			if res then res.format = "base64" end
			return res, err
		end
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
		local nodes, err = parse_wireguard_conf(content)
		if not nodes then return nil, err end
		return { nodes = nodes, format = "wireguard-conf" }
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

				-- 表单里所有输入框的值都是字符串，但统一模型里这几个字段是数组
				-- （见 parse_wireguard_conf：AllowedIPs/Reserved/DNS 都拆成数组）。
				-- 不归一的话，从 UI 编辑 WireGuard 节点会把数组写成标量字符串，
				-- 而 mihomo / sing-box 的对应字段是列表类型，导出结果非法。
				for _, lk in ipairs({ "allowed-ips", "reserved", "dns" }) do
					if type(n[lk]) == "string" then
						local arr = {}
						for piece in n[lk]:gmatch("[^,%s]+") do
							if piece ~= "" then arr[#arr + 1] = piece end
						end
						-- reserved 是端口保留位，语义上是数字
						if lk == "reserved" then
							for i, piece in ipairs(arr) do arr[i] = tonumber(piece) or piece end
						end
						if #arr == 0 then
							n[lk] = nil
						elseif #arr == 1 and lk == "dns" then
							n[lk] = arr[1] -- 单值 DNS 保持字符串，与 .conf 解析一致
						else
							n[lk] = arr
						end
					end
				end

				-- amnezia-wg-option 在表单里是一个 JSON 文本框，提交上来是字符串。
				-- 下游（output_wireguard_conf / output_clash_meta / output_uri）
				-- 一律要求它是 table，字符串会被静默忽略 —— 即从 UI 编辑
				-- WireGuard 节点会丢掉全部 AmneziaWG 参数。这里统一解码；
				-- 解不开就明确报错，而不是留个字符串让它在导出时无声消失。
				if type(n["amnezia-wg-option"]) == "string" then
					local s = util.trim(n["amnezia-wg-option"])
					if s == "" then
						n["amnezia-wg-option"] = nil
					else
						local opt = util.json_decode(s)
						if type(opt) ~= "table" then
							return nil, "AmneziaWG 参数必须是合法的 JSON 对象"
						end
						n["amnezia-wg-option"] = opt
					end
				end

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