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
	-- 空表必须用 util.JSON_EMPTY_OBJECT（编码成 {}）而不是裸 {}：json_encode 的
	-- is_array 会把空表判成数组编成 []，而 Xray 用标准库 json.Unmarshal 解析配置，
	-- wsSettings / grpcSettings / httpSettings 在它那边是结构体指针，把数组解进
	-- 结构体会直接 UnmarshalTypeError，Xray 拒绝启动。触发条件很普通：grpc 节点
	-- 没填服务名、ws 节点既没 path 也没 host。
	if net == "ws" then
		local ws = util.JSON_EMPTY_OBJECT
		if n.path or n.host then
			ws = {}
			if n.path then ws.path = n.path end
			if n.host then ws.headers = { Host = n.host } end
		end
		ss.wsSettings = ws
	elseif net == "grpc" then
		local g = util.JSON_EMPTY_OBJECT
		if n.path then g = { serviceName = n.path } end
		ss.grpcSettings = g
	elseif net == "http" or net == "h2" then
		local h = util.JSON_EMPTY_OBJECT
		if n.host or n.path then
			h = {}
			if n.host then h.host = { n.host } end
			if n.path then h.path = n.path end
		end
		ss.httpSettings = h
	elseif net == "kcp" then
		ss.kcpSettings = { header = { type = n.headerType or "none" } }
	end

	-- 安全层
	local security = n.security
	local sni = n.sni or n.servername
	if security == "reality" and n["public-key"] then
		-- Reality 必须写 realitySettings，**不是** tlsSettings。Xray 的 StreamConfig
		-- 校验是 `case "reality": if c.REALITYSettings == nil { return nil,
		-- errors.New(`REALITY: Empty "realitySettings".`) }` —— 写成 tlsSettings 的
		-- reality 节点会被直接拒绝，一个节点废掉整份配置。
		-- 客户端字段名取自 infra/conf/transport_security.go 的 REALITYConfig：
		-- fingerprint / serverName / publicKey / shortId / spiderX（外加 show）。
		-- 注意 publicKey 是**客户端**侧的键名（privateKey 只属于服务端），
		-- spiderX 在 Xray 侧缺省为 "/"。
		local rs = { show = false, fingerprint = n.fp or "chrome" }
		if sni then rs.serverName = sni end
		rs.publicKey = n["public-key"]
		if n["short-id"] then rs.shortId = n["short-id"] end
		if n["spider-x"] then rs.spiderX = n["spider-x"] end
		ss.security = "reality"
		ss.realitySettings = rs
	elseif security and security ~= "none" then
		-- security 声称 reality 却没有 public-key 时也走这里，但要把 security 降回
		-- tls：REALITYConfig.Build() 在公钥为空时直接报错（客户端分支是
		-- `empty "password"`，PublicKey 可由 Password 推导），而 StreamConfig 又要求
		-- security == "reality" 必须配 realitySettings —— 照抄写出去会让 Xray
		-- 拒绝加载**整份**配置。没有公钥就没有 Reality 可言，降级成普通 TLS
		-- 至少配置能加载（与 sing-box / mihomo / QX 三个输出端的行为一致：
		-- 它们同样只在有 public-key 时才写 Reality 配置）。
		ss.security = (security == "reality") and "tls" or security
		if sni then
			ss.tlsSettings = { serverName = sni, allowInsecure = false }
		end
	elseif n.tls and n.tls ~= "none" and n.tls ~= false then
		ss.security = "tls"
		if sni then ss.tlsSettings = { serverName = sni } end
	end

	return ss
end

-- 该协议能否落到 V2Ray / Xray outbound。
-- 白名单而不是「排除 ssr」：原来的 `proto ~= "ssr"` 会把 hysteria2 / hysteria /
-- tuic / wireguard / snell 一并放行，而 to_outbound 里没有它们的分支，全部落进
-- 末尾的 else —— 于是生成 `"protocol": "hysteria2"` 这种 Xray 根本不认识的
-- outbound，凭据还被塞进无意义的 users 字段。Xray 解析到未知 protocol 会拒绝
-- 整份配置，一个节点废掉整个订阅（与 parser 侧丢弃未知协议是同一个理由）。
local V2RAY_PROTOS = {
	vmess = true,
	vless = true,
	trojan = true,
	shadowsocks = true,
	ss = true,
	socks = true,
	socks5 = true,
	http = true,
}

local function supported(proto)
	return V2RAY_PROTOS[proto or "vmess"] == true
end

-- 单节点 → V2Ray outbound 表
-- tag 可选：完整配置里由 util.unique_tags 统一分配，避免节点重名导致 tag 冲突
function M.to_outbound(n, tag)
	local proto = n.proto or "vmess"
	if not supported(proto) then return nil end
	local o = {
		protocol = (proto == "ss" and "shadowsocks" or proto),
		tag = tag or n.name or ((n.server or "") .. ":" .. tostring(n.port or "")),
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
				-- users[].security 是 vmess 加密方式，取 cipher 而非 TLS 层
				security = n.cipher or "auto",
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

-- Xray 的 balancer / observatory selector 按「前缀」匹配 outbound tag。
-- 若某节点 tag 恰好是 "direct" / "block" / "auto" 的前缀（例如节点名就叫 "d"、"auto"），
-- selector 会把这些保留出站一并纳入负载均衡，导致流量被丢进 direct / block。
-- 因此把保留 tag 的所有真前缀也登记为冲突，交给 util.unique_tags 加后缀消解。
local function reserved_with_prefixes(names)
	local r = {}
	for _, s in ipairs(names) do
		r[s] = true
		for i = 1, #s - 1 do r[s:sub(1, i)] = true end
	end
	return r
end

-- 生成完整 V2Ray / Xray 配置（outbounds + observatory + routing）。
-- 不含 inbounds / dns：这两项会绑定本地监听端口、覆盖用户既有 DNS 设置，
-- 由用户在自己的配置里维护，本输出只负责节点与分流。
function M.generate(nodes, options)
	local usable = {}
	for _, n in ipairs(nodes or {}) do
		if type(n) == "table" and supported(n.proto) then usable[#usable + 1] = n end
	end
	local tags = util.unique_tags(usable, reserved_with_prefixes({ "direct", "block", "auto" }))

	local outbounds, proxy_tags = {}, {}
	for i, n in ipairs(usable) do
		outbounds[#outbounds + 1] = M.to_outbound(n, tags[i])
		proxy_tags[#proxy_tags + 1] = tags[i]
	end

	-- direct / block 必须存在：路由规则要按 tag 引用它们
	outbounds[#outbounds + 1] = { protocol = "freedom", tag = "direct", settings = util.JSON_EMPTY_OBJECT }
	outbounds[#outbounds + 1] = { protocol = "blackhole", tag = "block", settings = { response = { type = "none" } } }

	local routing = {
		domainStrategy = "IPIfNonMatch",
		rules = { { type = "field", ip = { "geoip:private" }, outboundTag = "direct" } },
	}
	local cfg = { log = { loglevel = "warning" }, outbounds = outbounds, routing = routing }

	if #proxy_tags > 0 then
		-- leastPing 依赖 observatory 的探测结果；不配 observatory 时该策略不生效
		cfg.observatory = {
			subjectSelector = proxy_tags,
			probeUrl = "https://www.gstatic.com/generate_204",
			probeInterval = "10s",
			enableConcurrency = true,
		}
		routing.balancers = { { tag = "auto", selector = proxy_tags, strategy = { type = "leastPing" } } }
		routing.rules[#routing.rules + 1] = { type = "field", network = "tcp,udp", balancerTag = "auto" }
	else
		-- 无可用节点时没有 balancer 可引用；首元素 direct 即默认出站
		routing.rules[#routing.rules + 1] = { type = "field", network = "tcp,udp", outboundTag = "direct" }
	end

	return util.json_encode(cfg)
end

return M