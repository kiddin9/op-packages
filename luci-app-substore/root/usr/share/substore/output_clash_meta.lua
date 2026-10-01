-- output_clash_meta.lua — Clash.Meta / Mihomo 格式输出（纯 Lua）
-- luci-app-substore

local M = {}

local function esc_yaml(s)
	s = tostring(s or "")
	-- 是否需要双引号必须在转义之前判定：转义之后的 \t / \r 只剩「反斜杠 + 字母」，
	-- 落在 plain scalar 里会被 YAML 当成两个字面字符而不是制表符/回车。含任何控制
	-- 字符（\n \r \t 等）时必须加引号 —— 未加引号的换行/回车会直接破坏文档结构。
	local need_quote = s:find("%c") ~= nil
		-- 注意：这里必须用 Lua 模式（不能传 plain=true），否则整串被当作字面量、永不匹配
		or s:find("[ :#{}%[%],&*?|>'\"%@`]") ~= nil
		or s:match("^[-?]*:") ~= nil
	-- 转义只在**加引号时**做：未加引号的 plain scalar 里反斜杠就是字面反斜杠，
	-- 提前翻倍会让回读得到两个反斜杠（`pa\ss` → 输出 `pa\\ss` → 读回 `pa\\ss`，
	-- 密码/路径直接错）。\ 本身不在上面的 need_quote 触发集里，所以含反斜杠的
	-- 值恰恰是最容易走到这条路径的一类。
	if need_quote then
		s = s:gsub("\\", "\\\\"):gsub("\"", "\\\""):gsub("\n", "\\n"):gsub("\r", "\\r"):gsub("\t", "\\t")
		return '"' .. s .. '"'
	end
	return s
end

local function indent(level)
	return string.rep("  ", level)
end

local function yaml_list(items, level)
	local out = {}
	for _, v in ipairs(items) do
		out[#out + 1] = indent(level) .. "- " .. esc_yaml(v)
	end
	return table.concat(out, "\n")
end

-- 把「数组或逗号分隔字符串」统一成数组。
-- mihomo 的 wireguard 出站里 allowed-ips / dns 是 []string、reserved 是 []uint8，
-- 三者都**只接受列表**。节点模型里这些字段的形态取决于来源：Clash YAML 的嵌套
-- 列表解析后是 table，表单导入 / URI 导入后是 "0.0.0.0/0, ::/0" 这样的字符串。
-- 字符串原样输出会得到 `allowed-ips: 0.0.0.0/0` 这个标量，mihomo 反序列化
-- 到 []string 失败，**整份配置拒绝加载**。
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

-- 值可能是数组也可能是逗号分隔字符串：一律输出为 YAML 列表。
-- 空列表直接不输出该键（`allowed-ips: []` 同样是非法值）。
local function yaml_value(lines, key, v, level)
	local items = as_list(v)
	if #items == 0 then return end
	lines[#lines + 1] = indent(level) .. key .. ":"
	lines[#lines + 1] = yaml_list(items, level + 1)
end

local PROTOCOL_TYPE_MAP = {
	vmess = "vmess",
	vless = "vless",
	trojan = "trojan",
	shadowsocks = "ss",
	ss = "ss",
	hysteria2 = "hysteria2",
	tuic = "tuic",
	wireguard = "wireguard",
	socks = "socks5",
	socks5 = "socks5",
	ssr = "ssr",
}

local function get_clash_type(proto)
	return PROTOCOL_TYPE_MAP[proto] or proto
end

local function format_node(node)
	local lines = {}
	local ctype = get_clash_type(node.proto)
	lines[#lines + 1] = "  - name: " .. esc_yaml(node.name or "")
	lines[#lines + 1] = "    type: " .. esc_yaml(ctype)
	lines[#lines + 1] = "    server: " .. esc_yaml(node.server or "")
	-- 端口必须是数字：`port: abc` / `port: 443/tcp` 这类非数字值会让 mihomo 拒绝
	-- 加载整份配置。sing-box / v2ray 输出一直用 `tonumber() or 0` 兜底，此处对齐。
	lines[#lines + 1] = "    port: " .. tostring(tonumber(node.port) or 0)

	-- 协议通用字段
	if node.uuid then
		lines[#lines + 1] = "    uuid: " .. esc_yaml(node.uuid)
	end
	if node.password then
		lines[#lines + 1] = "    password: " .. esc_yaml(node.password)
	end
	if node.method then
		if ctype == "ss" then
			lines[#lines + 1] = "    cipher: " .. esc_yaml(node.method)
		end
	end
	if node.cipher then
		if ctype == "vmess" or ctype == "vless" then
			lines[#lines + 1] = "    cipher: " .. esc_yaml(node.cipher)
		end
	end
	if node.net or node.network then
		local net = node.net or node.network
		lines[#lines + 1] = "    network: " .. esc_yaml(net)
		-- ws 特殊处理
		if net == "ws" then
			if node.path then
				lines[#lines + 1] = "    ws-opts:"
				lines[#lines + 1] = "      path: " .. esc_yaml(node.path)
			end
			if node.host then
				lines[#lines + 1] = "      headers:"
				lines[#lines + 1] = "        Host: " .. esc_yaml(node.host)
			end
		elseif net == "grpc" then
			-- 服务名写在 grpc-opts 里。只写 network: grpc 的话客户端用默认服务名
			-- 去连，握手失败——与 ws 丢 path 是同一类问题（原来的实现只写了 network）。
			-- 键名对照上游 transport 文档：grpc-service-name，带 grpc- 前缀。
			-- 服务名取自 node.path，与 output_v2ray 的 serviceName、
			-- output_singbox 的 service_name 同源。
			if node.path then
				lines[#lines + 1] = "    grpc-opts:"
				lines[#lines + 1] = "      grpc-service-name: " .. esc_yaml(node.path)
			end
		elseif net == "h2" then
			-- 上游 transport 文档：h2-opts.host 是**列表**，h2-opts.path 是标量。
			if node.path or node.host then
				lines[#lines + 1] = "    h2-opts:"
				if node.host then
					lines[#lines + 1] = "      host:"
					lines[#lines + 1] = "        - " .. esc_yaml(node.host)
				end
				if node.path then
					lines[#lines + 1] = "      path: " .. esc_yaml(node.path)
				end
			end
		end
	end

	-- TLS 相关
	local tls = false
	if node.security and node.security ~= "none" then
		tls = true
	elseif node.tls then
		tls = true
	end
	if tls then
		lines[#lines + 1] = "    tls: true"
	end

	-- servername / sni
	-- vmess / vless / trojan 在 mihomo 里用 servername；hysteria / hysteria2 用 sni
	-- （已对照上游文档确认：hysteria 系列没有 servername 字段，写了会被忽略，
	-- 结果 SNI 丢失 → 客户端拿 IP 校验证书直接握手失败）。hysteria 系列的 sni
	-- 由下面的协议专属分支输出。
	-- sni 与 servername 是同一个字段的两种写法，必须只输出一个键：Clash YAML 导入
	-- 会同时填上两者（先 sni = p.sni or p.servername，随后的字段保留循环又原样复制了
	-- servername），各写一行会让 YAML 出现重复键 —— 严格解析器直接报错，宽松解析器
	-- 则取最后一个，行为不确定。
	local is_hysteria = (ctype == "hysteria" or ctype == "hysteria2")
	local tls_name = node.sni or node.servername
	if tls_name and not is_hysteria then
		lines[#lines + 1] = "    servername: " .. esc_yaml(tls_name)
	end

	-- 特殊字段
	if node["skip-cert-verify"] ~= nil then
		lines[#lines + 1] = "    skip-cert-verify: " .. tostring(node["skip-cert-verify"])
	end
	if node.udp ~= nil then
		lines[#lines + 1] = "    udp: " .. tostring(node.udp)
	end
	if node.alpn then
		lines[#lines + 1] = "    alpn:"
		local alpn_list = {}
		if type(node.alpn) == "string" then
			for part in node.alpn:gmatch("[^,]+") do
				alpn_list[#alpn_list + 1] = part:match("^%s*(.-)%s*$")
			end
		elseif type(node.alpn) == "table" then
			alpn_list = node.alpn
		end
		for _, v in ipairs(alpn_list) do
			lines[#lines + 1] = "      - " .. esc_yaml(v)
		end
	end
	if node.fp then
		lines[#lines + 1] = "    fp: " .. esc_yaml(node.fp)
	end

	-- 协议特定字段
	if ctype == "vmess" then
		if node.alterId ~= nil then
			lines[#lines + 1] = "    alterId: " .. tostring(node.alterId)
		end
		if not node.cipher then
			lines[#lines + 1] = "    cipher: auto"
		end
	end

	if ctype == "vless" then
		-- flow 是 XTLS Vision（xtls-rprx-vision）的必需参数。不写的话 mihomo 按
		-- 普通 vless 处理，服务端要求 vision 时握手失败。surge / v2ray / URI 三个
		-- 输出都写 flow，只有 clashmeta 漏了；parser_clash_yaml 也回读 flow，
		-- 所以「Clash YAML → 导出 clashmeta」这条路径上 flow 会凭空消失。
		if node.flow then
			lines[#lines + 1] = "    flow: " .. esc_yaml(node.flow)
		end
	end

	if ctype == "hysteria2" then
		if node.sni then
			lines[#lines + 1] = "    sni: " .. esc_yaml(node.sni)
		end
		-- 混淆（salamander）：hysteria2 的 obfs 是 { type, password } 两段
		if node.obfs and node.obfs ~= "" and node.obfs ~= "plain" then
			lines[#lines + 1] = "    obfs: " .. esc_yaml(node.obfs)
			local opw = node["obfs-password"] or node.obfs_password
			if opw and opw ~= "" then
				lines[#lines + 1] = "    obfs-password: " .. esc_yaml(opw)
			end
		end
	end

	if ctype == "hysteria" then
		-- hysteria(v1)：obfs 只是普通字符串，**没有** obfs-password
		-- （obfs-password 是 hysteria2 的 salamander 专属字段，写到 v1 上是非法键）
		if node.sni then
			lines[#lines + 1] = "    sni: " .. esc_yaml(node.sni)
		end
		if node.obfs and node.obfs ~= "" and node.obfs ~= "plain" then
			lines[#lines + 1] = "    obfs: " .. esc_yaml(node.obfs)
		end
	end

	if ctype == "tuic" then
		if node["udp-relay-mode"] then
			lines[#lines + 1] = "    udp-relay-mode: " .. esc_yaml(node["udp-relay-mode"])
		end
	end

	if ctype == "wireguard" then
		if node["private-key"] then
			lines[#lines + 1] = "    private-key: " .. esc_yaml(node["private-key"])
		end
		if node["public-key"] or node["peer-public-key"] then
			lines[#lines + 1] = "    public-key: " .. esc_yaml(node["public-key"] or node["peer-public-key"])
		end
		if node["pre-shared-key"] or node["preshared-key"] then
			lines[#lines + 1] = "    pre-shared-key: " .. esc_yaml(node["pre-shared-key"] or node["preshared-key"])
		end
		if node.ip then
			lines[#lines + 1] = "    ip: " .. esc_yaml(node.ip)
		end
		if node.ipv6 then
			lines[#lines + 1] = "    ipv6: " .. esc_yaml(node.ipv6)
		end
		if node["allowed-ips"] then
			yaml_value(lines, "allowed-ips", node["allowed-ips"], 2)
		end
		if node.reserved then
			yaml_value(lines, "reserved", node.reserved, 2)
		end
		if node["persistent-keepalive"] then
			lines[#lines + 1] = "    persistent-keepalive: " .. esc_yaml(node["persistent-keepalive"])
		end
		if node["listen-port"] then
			lines[#lines + 1] = "    listen-port: " .. esc_yaml(node["listen-port"])
		end
		if node.mtu then
			lines[#lines + 1] = "    mtu: " .. esc_yaml(node.mtu)
		end
		if node.dns then
			yaml_value(lines, "dns", node.dns, 2)
		end
		if type(node["amnezia-wg-option"]) == "table" then
			lines[#lines + 1] = "    amnezia-wg-option:"
			-- 排序输出，保证同一节点每次导出结果一致（便于 diff / 校验）
			local keys = {}
			for k in pairs(node["amnezia-wg-option"]) do keys[#keys + 1] = k end
			table.sort(keys)
			for _, k in ipairs(keys) do
				lines[#lines + 1] = "      " .. k .. ": " .. esc_yaml(node["amnezia-wg-option"][k])
			end
		end
	end

	-- socks5 / http 的认证字段都是 username + password（已对照上游 mihomo 文档确认）。
	-- password 已由上面的「协议通用字段」输出，这里只补 username——重复输出会让
	-- YAML 里出现两个 password 键，属于非法/歧义配置。
	if ctype == "socks5" or ctype == "http" then
		if node.username then
			lines[#lines + 1] = "    username: " .. esc_yaml(node.username)
		end
	end

	if ctype == "ssr" then
		lines[#lines + 1] = "    cipher: " .. esc_yaml(node.method or node.cipher or "aes-128-cfb")
		lines[#lines + 1] = "    protocol: " .. esc_yaml(node.protocol or "origin")
		lines[#lines + 1] = "    obfs: " .. esc_yaml(node.obfs or "plain")
		local op = node.obfs_param or node["obfs-param"]
		local pp = node.protocol_param or node["protocol-param"]
		if op and op ~= "" then lines[#lines + 1] = "    obfs-param: " .. esc_yaml(op) end
		if pp and pp ~= "" then lines[#lines + 1] = "    protocol-param: " .. esc_yaml(pp) end
	end

	return table.concat(lines, "\n")
end

local function generate_proxies(nodes)
	if not nodes or #nodes == 0 then
		return "proxies: []"
	end
	local out = {}
	out[#out + 1] = "proxies:"
	for _, node in ipairs(nodes) do
		out[#out + 1] = format_node(node)
	end
	return table.concat(out, "\n")
end

local function generate_groups(nodes, options)
	local out = {}
	out[#out + 1] = "proxy-groups:"

	local names = {}
	for _, n in ipairs(nodes) do
		names[#names + 1] = n.name or ""
	end

	local group_name = (options and options.name) or "Proxy"

	-- SELECT
	out[#out + 1] = "  - name: " .. esc_yaml(group_name)
	out[#out + 1] = "    type: select"
	out[#out + 1] = "    proxies:"
	if #names > 0 then
		for _, n in ipairs(names) do
			out[#out + 1] = "      - " .. esc_yaml(n)
		end
	else
		out[#out + 1] = "      - REJECT"
	end

	-- URL-TEST
	out[#out + 1] = "  - name: URL-Test"
	out[#out + 1] = "    type: url-test"
	out[#out + 1] = "    url: http://www.gstatic.com/generate_204"
	out[#out + 1] = "    interval: 300"
	out[#out + 1] = "    tolerance: 50"
	out[#out + 1] = "    proxies:"
	if #names > 0 then
		for _, n in ipairs(names) do
			out[#out + 1] = "      - " .. esc_yaml(n)
		end
	else
		out[#out + 1] = "      - REJECT"
	end

	-- LOAD-BALANCE
	out[#out + 1] = "  - name: Load-Balance"
	out[#out + 1] = "    type: load-balance"
	out[#out + 1] = "    strategy: round-robin"
	out[#out + 1] = "    proxies:"
	if #names > 0 then
		for _, n in ipairs(names) do
			out[#out + 1] = "      - " .. esc_yaml(n)
		end
	else
		out[#out + 1] = "      - REJECT"
	end

	return table.concat(out, "\n")
end

function M.generate(nodes, options)
	options = options or {}
	local parts = {}

	-- 生成 proxies
	parts[#parts + 1] = generate_proxies(nodes or {})

	-- 生成 proxy-groups
	parts[#parts + 1] = generate_groups(nodes or {}, options)

	return table.concat(parts, "\n\n")
end

return M
