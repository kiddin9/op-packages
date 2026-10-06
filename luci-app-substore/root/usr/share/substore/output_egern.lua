-- output_egern.lua — Egern 配置输出（YAML，纯 Lua）
-- luci-app-substore
--
-- Egern 的配置是 YAML，不是 Surge 的逗号行（LEGACY_ISSUES 的 7.2）。结构：
--
--   proxies:        节点列表；每一项是**单键映射**，键名即协议名（小写）
--   policy_groups:  策略组列表；同样是单键映射（select / auto_test / fallback …）
--
-- 字段名一律 snake_case（user_id / peer_public_key / skip_tls_verify / udp_relay），
-- 而统一模型混用 kebab-case 与 camelCase（public-key / skip-cert-verify / udp），
-- 所以每个字段都要逐项翻译 —— 既不能照抄 Clash 的 network: + ws-opts，
-- 也不能照抄 Surge 家族的逗号行。
--
-- 依据（逐字段核对官方文档，无推测项）：
--   * egernapp.com/docs/configuration/example/ —— 完整的官方配置示例，
--     proxies / policy_groups 的真实结构与字段名；
--   * egernapp.com/docs/configuration/proxies/ —— 每个协议的字段表，以及
--     vmess / vless 的 transport 子对象（tls / ws / wss / http1 / http2 / grpc）
--     与 Reality 的嵌套位置（transport.<类型>.reality）。
--
-- 与 Surge 家族的分工：Egern **不再**是 surge_config 的一个 flavor。它的协议清单
-- 与 Surge 不同（有 VLESS 与 WireGuard，没有 SSR 与 Hysteria v1），可表达的参数
-- 也不同（WireGuard 在 Surge 的单行 [Proxy] 里表达不了，在 YAML 里可以）。

local util = require("substore.util")
local clash_meta = require("substore.output_clash_meta")

local M = {}

-- YAML 标量转义与 Clash.Meta 输出共用一份实现（引号触发集、控制字符、
-- c-indicator 的处理完全相同）。
local esc_yaml = clash_meta.esc_yaml

-- 节点字段的缩进。YAML 层级：
--   proxies:            0
--     - shadowsocks:    2
--         name: …       6
local P = "      "

-- 统一模型的协议名 → Egern 的协议键。
--
-- 官方协议清单（egernapp.com/docs/configuration/proxies/）：
--   Shadowsocks / Snell / Trojan / AnyTLS / Hysteria2 / TUIC / SOCKS5 /
--   SOCKS5 over TLS / SSH / HTTP / HTTPS / Vmess / Vless / WireGuard
--
-- 清单里**没有**的两个协议必须整条丢弃（返回 nil），否则写出去的就是客户端
-- 读不懂的节点 —— 与 surge_line 对未知协议的处置同一约定：
--   * ssr（ShadowsocksR）：清单里没有 SSR；
--   * hysteria（v1）：清单里只有 Hysteria2。两者的字段结构不同
--     （v1 的 obfs 是普通字符串、没有 obfs_password），拿 Hysteria2 的键去顶
--     只会让客户端按错误的协议去连。
local EGERN_KEY = {
	shadowsocks = "shadowsocks",
	vmess       = "vmess",
	vless       = "vless",
	trojan      = "trojan",
	anytls      = "anytls",
	hysteria2   = "hysteria2",
	tuic        = "tuic",
	socks       = "socks5",
	socks5      = "socks5",
	http        = "http",
	wireguard   = "wireguard",
}

-- 有 udp_relay 字段的协议。取自官方字段表：Hysteria2（本身就是 UDP）与 TUIC
-- （用 udp_relay_mode）没有这个键，HTTP 也没有；写了就是客户端读不懂的键。
local UDP_RELAY = {
	shadowsocks = true, vmess = true, vless = true,
	trojan = true, anytls = true, socks5 = true,
}

-- `key: value`。值为 nil / 空串时不输出（Egern 的必填字段由协议本身保证，
-- 可选字段缺失时省略键即取默认值）。
local function kv(lines, ind, k, v)
	if v == nil then return end
	v = tostring(v)
	if v == "" then return end
	lines[#lines + 1] = ind .. k .. ": " .. esc_yaml(v)
end

-- 数组或逗号分隔字符串 → 数组。与 output_clash_meta 的 as_list 同源：
-- alpn / dns / reserved 在统一模型里的形态取决于来源（Clash YAML / sing-box JSON
-- 解析后是 table，表单导入后是 "h3,h2" 这样的字符串）。
local function as_list(v)
	local out = {}
	if type(v) == "table" then
		for _, x in ipairs(v) do
			if x ~= nil and tostring(x) ~= "" then out[#out + 1] = x end
		end
	elseif type(v) == "string" then
		for x in v:gmatch("[^,]+") do
			x = x:match("^%s*(.-)%s*$")
			if x ~= "" then out[#out + 1] = x end
		end
	end
	return out
end

-- `key:` 后跟块序列。空列表直接不输出该键（Egern 的可选数组字段省略即默认）。
local function kv_list(lines, ind, k, v)
	local items = as_list(v)
	if #items == 0 then return end
	lines[#lines + 1] = ind .. k .. ":"
	for _, x in ipairs(items) do
		lines[#lines + 1] = ind .. "  - " .. esc_yaml(x)
	end
end

-- 布尔值按 YAML 的裸 true / false 输出（加引号会变成字符串，语义不同）。
local function yaml_bool(v)
	if v == nil then return nil end
	if v == false or v == "false" or v == "0" or v == 0 then return "false" end
	return "true"
end

-- Reality 子对象：`reality: { public_key, short_id }`。
--
-- 键名是 snake_case 的 public_key / short_id —— 既不是统一模型的
-- public-key / short-id，也不是 Clash 的 reality-opts。写错键名客户端不报错，
-- 只是 Reality 静默失效（退回普通 TLS），所以这里逐字对照官方示例。
--
-- 判据取「有没有 public-key」而不是 security == "reality"：公钥就是 Reality 的
-- 凭据，缺了它客户端连不上；而 security 在两种来源里含义不同（分享链接写
-- reality，Loon 的行只写 over-tls + public-key）。
local function reality_block(lines, ind, n)
	if not n["public-key"] then return end
	lines[#lines + 1] = ind .. "reality:"
	lines[#lines + 1] = ind .. "  public_key: " .. esc_yaml(n["public-key"])
	if n["short-id"] then
		lines[#lines + 1] = ind .. "  short_id: " .. esc_yaml(n["short-id"])
	end
end

-- vmess / vless 的传输层。
--
-- Egern 用 transport 子映射，键名是传输类型本身：tls / ws / wss / http1 /
-- http2 / grpc。TLS 也是其中一种（transport.tls），**没有**顶层 tls 开关 ——
-- 所以「明文 tcp」就是完全不写 transport。
-- 这与 Clash 的 `network: ws` + `ws-opts` 是两套完全不同的写法。
local function transport_block(lines, n)
	local net = (n.net or n.network or ""):lower()
	local tls = (n.security and n.security ~= "none")
		or (n.tls and n.tls ~= false and n.tls ~= "none")
	local sni = n.sni or n.servername
	local verify = yaml_bool(n["skip-cert-verify"])

	local sub
	if net == "ws" then
		-- wss = ws 之上再套 TLS；官方文档把两者列为两个传输类型
		sub = tls and "wss" or "ws"
	elseif net == "grpc" then
		-- gRPC 恒定走 TLS（官方原文："The TLS layer is always applied"）
		sub = "grpc"
	elseif net == "h2" or net == "http" then
		sub = "http2"
	elseif tls or n["public-key"] then
		sub = "tls"
	else
		-- 明文 tcp：不写 transport
		return
	end

	lines[#lines + 1] = P .. "transport:"
	local S = P .. "  "    -- transport 的子键（传输类型）
	local F = P .. "    "  -- 传输类型的字段

	lines[#lines + 1] = S .. sub .. ":"
	if sub == "ws" or sub == "wss" then
		kv(lines, F, "path", n.path)
		if n.host then
			lines[#lines + 1] = F .. "headers:"
			lines[#lines + 1] = F .. "  Host: " .. esc_yaml(n.host)
		end
		if sub == "wss" then
			kv(lines, F, "sni", sni)
			kv(lines, F, "skip_tls_verify", verify)
			reality_block(lines, F, n)
		end
	elseif sub == "grpc" then
		-- 服务名在 Egern 里叫 service_name（Clash 叫 grpc-service-name，
		-- sing-box 叫 service_name）。丢了这个参数客户端用默认服务名去连，
		-- 握手必然失败且不报错。
		kv(lines, F, "service_name", n.path)
		kv(lines, F, "sni", sni)
		kv(lines, F, "skip_tls_verify", verify)
		reality_block(lines, F, n)
	elseif sub == "http2" then
		kv(lines, F, "path", n.path)
		if n.host then
			lines[#lines + 1] = F .. "headers:"
			lines[#lines + 1] = F .. "  Host: " .. esc_yaml(n.host)
		end
		kv(lines, F, "sni", sni)
		kv(lines, F, "skip_tls_verify", verify)
	else -- tls
		kv(lines, F, "sni", sni)
		kv(lines, F, "skip_tls_verify", verify)
		reality_block(lines, F, n)
	end
end

-- SIP003 插件 → Egern 的 Shadowsocks 混淆三件套 obfs / obfs_host / obfs_uri。
--
-- Egern 的 Shadowsocks 只有这三个混淆字段（官方字段表），**没有**任何插件字段：
-- v2ray-plugin 的节点在 Egern 里无法表达，只能丢掉插件按明文 SS 输出
-- （丢参数、保留节点 —— 与 surge_line 对多值 alpn 的处置同一约定）。
-- 参数不全（mode 不是 http/tls）时同样整个不输出：宁可不要混淆，
-- 也不能写出一个客户端认不出的 obfs 值。
local function add_ss_obfs(lines, n)
	local name, _, opts = util.parse_sip003_plugin(n.plugin)
	if not name then return end
	if name ~= "obfs-local" and name ~= "simple-obfs" and name ~= "obfs" then return end
	local mode = opts.obfs or opts.mode
	if mode ~= "tls" and mode ~= "http" then return end
	kv(lines, P, "obfs", mode)
	kv(lines, P, "obfs_host", opts["obfs-host"] or opts.host)
	kv(lines, P, "obfs_uri", opts["obfs-uri"] or opts.uri)
end

-- 单个节点 → YAML 片段。协议不在 Egern 的清单里时返回 nil，由调用方整条剔除。
local function format_node(n, name)
	local key = EGERN_KEY[(n.proto or ""):lower()]
	if not key then return nil end

	local lines = {}
	lines[#lines + 1] = "  - " .. key .. ":"
	kv(lines, P, "name", name)
	kv(lines, P, "server", n.server)
	-- 端口必须是数字：Egern 的 port 是 integer，`port: abc` 这类非数字值
	-- 会被拒绝。与 clash_meta 的 `tonumber() or 0` 兜底对齐。
	lines[#lines + 1] = P .. "port: " .. tostring(tonumber(n.port) or 0)

	if key == "shadowsocks" then
		kv(lines, P, "method", n.method or n.cipher or "aes-256-gcm")
		kv(lines, P, "password", n.password)
		add_ss_obfs(lines, n)

	elseif key == "vmess" then
		kv(lines, P, "user_id", n.uuid)
		-- security 的取值域（auto / aes-128-gcm / chacha20-poly1305 / none / zero）
		-- 与 node.VMESS_CIPHERS 完全一致，不需要像 Loon 那样映射拼写；
		-- 缺省按输出端的既有约定回退到 auto。
		kv(lines, P, "security", n.cipher or "auto")
		if n.legacy ~= nil then kv(lines, P, "legacy", yaml_bool(n.legacy)) end
		transport_block(lines, n)

	elseif key == "vless" then
		kv(lines, P, "user_id", n.uuid)
		-- flow 是 XTLS Vision 的必需参数，缺了服务端要求 vision 时握手失败
		kv(lines, P, "flow", n.flow)
		transport_block(lines, n)

	elseif key == "trojan" then
		kv(lines, P, "password", n.password)
		kv(lines, P, "sni", n.sni or n.servername)
		kv(lines, P, "skip_tls_verify", yaml_bool(n["skip-cert-verify"]))
		reality_block(lines, P, n)
		-- Trojan 的 WebSocket 是**独立**的 websocket 子对象（path / host），
		-- 不在 transport 里 —— 与 vmess / vless 的写法不同。
		if (n.net or n.network or ""):lower() == "ws" then
			lines[#lines + 1] = P .. "websocket:"
			kv(lines, P .. "  ", "path", n.path)
			kv(lines, P .. "  ", "host", n.host)
		end

	elseif key == "anytls" then
		-- AnyTLS 建立在 TLS 之上，没有明文模式，也就没有 TLS 开关；
		-- 密码字段名是 password（Hysteria2 才叫 auth）。
		kv(lines, P, "password", n.password)
		kv(lines, P, "sni", n.sni or n.servername)
		kv(lines, P, "skip_tls_verify", yaml_bool(n["skip-cert-verify"]))
		reality_block(lines, P, n)

	elseif key == "hysteria2" then
		-- 密码在 Hysteria2 里叫 auth（不是 password）
		kv(lines, P, "auth", n.password)
		kv(lines, P, "sni", n.sni)
		if n.obfs and n.obfs ~= "" and n.obfs ~= "plain" then
			kv(lines, P, "obfs", n.obfs)
			kv(lines, P, "obfs_password", n["obfs-password"] or n.obfs_password)
		end
		kv(lines, P, "skip_tls_verify", yaml_bool(n["skip-cert-verify"]))

	elseif key == "tuic" then
		kv(lines, P, "uuid", n.uuid)
		kv(lines, P, "password", n.password)
		kv(lines, P, "udp_relay_mode", n["udp-relay-mode"])
		kv_list(lines, P, "alpn", n.alpn)
		kv(lines, P, "sni", n.sni)
		kv(lines, P, "skip_tls_verify", yaml_bool(n["skip-cert-verify"]))

	elseif key == "socks5" then
		kv(lines, P, "username", n.username)
		kv(lines, P, "password", n.password)

	elseif key == "http" then
		kv(lines, P, "username", n.username)
		kv(lines, P, "password", n.password)

	elseif key == "wireguard" then
		-- Egern 的 WireGuard 是**必填** private_key + peer_public_key，且
		-- local_ipv4 / local_ipv6 至少要有一个（官方原文）。统一模型里
		-- public-key 对 wireguard 而言就是对端公钥（与 Reality 无关），
		-- 与 clash_meta 的取值口径一致。
		kv(lines, P, "private_key", n["private-key"])
		kv(lines, P, "peer_public_key", n["public-key"] or n["peer-public-key"])
		kv(lines, P, "preshared_key", n["pre-shared-key"] or n["preshared-key"])
		kv(lines, P, "local_ipv4", n.ip)
		kv(lines, P, "local_ipv6", n.ipv6)
		kv_list(lines, P, "reserved", n.reserved)
		kv_list(lines, P, "dns_servers", n.dns)
		kv(lines, P, "mtu", n.mtu)
		kv(lines, P, "keepalive", n["persistent-keepalive"])
	end

	if UDP_RELAY[key] then
		kv(lines, P, "udp_relay", yaml_bool(n.udp))
	end

	return table.concat(lines, "\n")
end

-- nodes → Egern 配置（YAML）
function M.generate(nodes, options)
	options = options or {}
	nodes = nodes or {}
	local group_name = options.name or "PROXY"

	-- Egern 要求节点名全局唯一（官方文档原文 "must be globally unique"），
	-- 与 mihomo 同一约束，所以复用 util.unique_tags —— 两个输出端的改名规则
	-- 保持一致。组名与内置策略（DIRECT / REJECT / PROXY）一并占位，
	-- 否则节点名撞上内置策略时引用会指向内置项。
	local tags = util.unique_tags(nodes, {
		[group_name] = true,
		DIRECT = true,
		REJECT = true,
		PROXY = true,
	})

	local blocks, names = {}, {}
	for i, n in ipairs(nodes) do
		local block = format_node(n, tags[i])
		if block then
			blocks[#blocks + 1] = block
			names[#names + 1] = tags[i]
		end
	end

	local out = {}
	if #blocks == 0 then
		-- 空列表写 `proxies: []`：只写 `proxies:` 的话 YAML 里它是 null，
		-- 不是「空列表」。与 clash_meta 的处置一致。
		out[#out + 1] = "proxies: []"
	else
		out[#out + 1] = "proxies:"
		for _, b in ipairs(blocks) do out[#out + 1] = b end
	end

	out[#out + 1] = "policy_groups:"
	out[#out + 1] = "  - select:"
	out[#out + 1] = "      name: " .. esc_yaml(group_name)
	out[#out + 1] = "      policies:"
	if #names > 0 then
		for _, nm in ipairs(names) do
			out[#out + 1] = "        - " .. esc_yaml(nm)
		end
	else
		-- 没有节点时也要给出一个合法成员：空的 policies 列表在 Egern 里
		-- 没有可选项（与 clash_meta 兜底 REJECT 同一约定，Egern 的内置直连
		-- 策略是 DIRECT）。
		out[#out + 1] = "        - DIRECT"
	end

	return table.concat(out, "\n")
end

return M
