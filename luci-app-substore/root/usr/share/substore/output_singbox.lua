-- output_singbox.lua — sing-box JSON 配置输出（纯 Lua）
-- luci-app-substore

local util = require("substore.util")

local M = {}

local function bool(v)
	if v == nil then return nil end
	if v == false or v == "false" or v == 0 or v == "0" then return false end
	return true
end

-- 把「数组或逗号分隔字符串」统一成数组（空项丢弃）。
-- 节点模型里 wireguard 的 allowed-ips / reserved / dns 形态取决于来源：Clash YAML
-- 的嵌套列表解析后是 table，表单导入 / URI 导入后是 "0.0.0.0/0, ::/0" 这样的
-- 字符串。字符串原样写进 JSON 会得到 `"allowed_ips":"0.0.0.0/0"`，而 sing-box
-- 这几个字段是 []string / []uint8，反序列化失败 → 整份配置拒绝启动。
local function as_list(v)
	local out = {}
	if type(v) == "table" then
		for _, x in ipairs(v) do
			if x ~= nil and tostring(x) ~= "" then out[#out + 1] = x end
		end
	else
		for x in tostring(v or ""):gmatch("[^,]+") do
			x = x:match("^%s*(.-)%s*$")
			if x ~= "" then out[#out + 1] = x end
		end
	end
	return out
end

-- 同 as_list，但把每项转成数字（非数字项丢弃）。
-- reserved 在 sing-box 里是 []uint8：JSON 里写成 ["1","2","3"]（字符串）同样
-- 反序列化失败，必须输出 [1,2,3]。
local function as_num_list(v)
	local out = {}
	for _, x in ipairs(as_list(v)) do
		local num = tonumber(x)
		if num then out[#out + 1] = num end
	end
	return out
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

-- 该协议能否落到 sing-box outbound（SSR 无法表达，跳过）
local function supported(proto)
	return (TYPE_MAP[proto] or proto) ~= "ssr"
end

-- 构建 TLS 字段
--
-- enabled 必须显式写 true：sing-box 的 OutboundTLSOptions.Enabled 是
-- `bool` + `json:"enabled,omitempty"`（option/tls.go），缺省值即 false。
-- 上游 common/tls/client.go 里 `if !options.Enabled { return dialer, nil }`
-- 会直接按明文拨号，hysteria2 / tuic 更会因为 `options.TLS == nil ||
-- !options.TLS.Enabled` 返回 C.ErrTLSRequired 而拒绝启动。只输出
-- server_name / insecure 而不带 enabled 等于没配 TLS。
local function build_tls(n)
	if not (n.security and n.security ~= "none") then return nil end
	local tls = { enabled = true }
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
-- tag 可选：完整配置里由 util.unique_tags 统一分配，避免节点重名导致 tag 冲突
function M.to_outbound(n, tag)
	local stype = TYPE_MAP[n.proto] or n.proto
	if stype == "ssr" then return nil end -- sing-box 不支持 SSR，跳过
	local o = {
		type = stype,
		tag = tag or n.name or ((n.server or "") .. ":" .. tostring(n.port or "")),
		server = n.server or "",
		server_port = tonumber(n.port) or 0,
	}

	if stype == "vmess" then
		o.uuid = n.uuid or ""
		if n.alterId ~= nil then o.alter_id = tonumber(n.alterId) end
		-- 此处的 security 是 vmess 加密方式，取 cipher 而非 TLS 层
		o.security = n.cipher or "auto"
		if n.flow then o.flow = n.flow end
	elseif stype == "vless" then
		o.uuid = n.uuid or ""
		if n.flow then o.flow = n.flow end
	elseif stype == "trojan" then
		o.password = n.password or ""
	elseif stype == "shadowsocks" then
		o.method = n.method or n.cipher or "aes-256-gcm"
		o.password = n.password or ""
		-- SIP003 插件。sing-box 的 shadowsocks 出站只有 plugin（字符串）与
		-- plugin_opts（字符串）两个字段，plugin_opts 就是 SIP003 的原始参数串
		-- （`obfs=http;obfs-host=x`），不做任何翻译 —— 与 mihomo 的映射式
		-- plugin-opts 正好相反。
		-- 官方文档明确「Only two are supported: obfs-local and v2ray-plugin」，
		-- 其余名字（kcptun / shadow-tls / restls / gost-plugin …）sing-box
		-- 认不出来，会拒绝加载整份配置，所以按白名单过滤。
		-- 丢掉这一项时服务端只接受带插件的握手，导出的配置必然连不上且不报错。
		local pname, popts = util.parse_sip003_plugin(n.plugin)
		if pname == "obfs-local" or pname == "v2ray-plugin" then
			o.plugin = pname
			if popts and popts ~= "" then o.plugin_opts = popts end
		end
	elseif stype == "hysteria2" then
		o.password = n.password or ""
		-- 混淆（salamander）：hysteria2 的 obfs 是 { type, password } 对象
		if n.obfs and n.obfs ~= "" and n.obfs ~= "plain" then
			o.obfs = { type = n.obfs, password = n["obfs-password"] or n.obfs_password or "" }
		end
	elseif stype == "hysteria" then
		-- hysteria(v1) 与 hysteria2 在 sing-box 里的字段名并不相同（已对照上游文档确认）：
		--   * 认证字段是 auth_str，不是 password（parser_json_config 也是按
		--     outbound.password or outbound.auth_str or outbound.auth 回读的）
		--   * obfs 是普通字符串，不是 { type, password } 对象
		-- 注意：sing-box 的 hysteria 出站还要求 up/down（带宽），本项目的节点模型
		-- 不承载该字段，需用户在自己的配置里补上（见 CHANGELOG 已知限制）。
		o.auth_str = n.password or ""
		if n.obfs and n.obfs ~= "" and n.obfs ~= "plain" then
			o.obfs = n.obfs
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
		-- 三个字段在 sing-box 里都是列表（allowed_ips/dns 是 []string，reserved 是
		-- []uint8），字符串形态必须归一后再写，否则整份配置起不来
		local aips = as_list(n["allowed-ips"])
		if #aips > 0 then o.allowed_ips = aips end
		local rsv = as_num_list(n.reserved)
		if #rsv > 0 then o.reserved = rsv end
		if n["persistent-keepalive"] then o.persistent_keepalive_interval = tonumber(n["persistent-keepalive"]) end
		if n["listen-port"] then o.listen_port = tonumber(n["listen-port"]) end
		if n.mtu then o.mtu = tonumber(n.mtu) end
		local dns = as_list(n.dns)
		if #dns > 0 then o.dns = dns end
	elseif stype == "socks" or stype == "http" then
		-- socks 与 http 出站的认证字段相同（username / password）
		if n.username then o.username = n.username end
		if n.password then o.password = n.password end
	end

	local tls = build_tls(n)
	if tls then o.tls = tls end
	local transport = build_transport(n)
	if transport then o.transport = transport end

	return o
end

-- 保留 tag：节点名不得与之重名（util.unique_tags 负责消解）
local RESERVED_TAGS = { select = true, auto = true, direct = true, block = true }

-- 生成完整 sing-box 配置（outbounds + route）。
-- 不含 inbounds / dns：这两项会绑定本地监听端口、覆盖用户既有 DNS 设置，
-- 由用户在自己的配置里维护，本输出只负责节点与分流。
--
-- 版本兼容说明：route 规则里的 action 字段自 1.11.0 起才存在，其默认值即 "route"，
-- 因此这里刻意省略 action —— 未知字段会被 sing-box 拒绝，而省略默认值在
-- 1.10 与 1.11+ 上都能工作。
function M.generate(nodes, options)
	local usable = {}
	for _, n in ipairs(nodes or {}) do
		if type(n) == "table" and supported(n.proto) then usable[#usable + 1] = n end
	end
	local tags = util.unique_tags(usable, RESERVED_TAGS)

	local outbounds, proxy_tags = {}, {}
	for i, n in ipairs(usable) do
		outbounds[#outbounds + 1] = M.to_outbound(n, tags[i])
		proxy_tags[#proxy_tags + 1] = tags[i]
	end

	local final
	if #proxy_tags > 0 then
		-- select 供手工切换，auto 自动测速选优
		local sel = { type = "selector", tag = "select", outbounds = { "auto", "direct" } }
		for _, t in ipairs(proxy_tags) do sel.outbounds[#sel.outbounds + 1] = t end
		sel.default = "auto"
		outbounds[#outbounds + 1] = sel
		outbounds[#outbounds + 1] = { type = "urltest", tag = "auto", outbounds = proxy_tags }
		final = "select"
	else
		-- 无可用节点时不能生成 selector / urltest（outbounds 不允许为空）
		final = "direct"
	end
	outbounds[#outbounds + 1] = { type = "direct", tag = "direct" }
	outbounds[#outbounds + 1] = { type = "block", tag = "block" }

	return util.json_encode({
		outbounds = outbounds,
		route = {
			rules = { { ip_is_private = true, outbound = "direct" } },
			final = final,
			auto_detect_interface = true,
		},
	})
end

return M