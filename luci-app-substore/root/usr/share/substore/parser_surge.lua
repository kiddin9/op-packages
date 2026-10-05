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

-- 剥掉 Loon 位置参数外面的双引号：`"password"` → `password`。
-- Loon 的节点行一律把凭据写成带引号的位置参数，Surge 家族的具名参数则不带引号；
-- 只剥一层（`""x""` → `"x"`），没有引号时原样返回。
local function unquote(v)
	v = util.trim(v or "")
	local inner = v:match('^"(.*)"$')
	return inner or v
end

-- 按逗号切分字段，但**引号内的逗号不作为分隔符**。
--
-- Loon 把凭据写成双引号包裹的位置参数（nsloon.app/docs/Node/）：
--   Trojan = Trojan,trojan.example.com,443,"password",transport=tcp,...
-- 密码里含逗号时，`rest:gmatch("[^,]+")` 会把它切成两段 ——
--   Trojan = Trojan,h,443,"pa,ss",sni=x
-- 的密码会静默变成 `"pa`（连引号一起、少掉后半段），用户拿到的不是他填的凭据，
-- 而且没有任何提示。生成端早就有「值里含逗号就整条丢弃」的防护（output_formats
-- 的 surge_line），解析端此前没有对应处理。
--
-- 两条边界：
--   * 引号个数为奇数时（订阅内容不可信，可能是落单的引号）**不做引号感知**，
--     退回按逗号切分。否则那个引号会一直「开着」，把后面的 sni= / over-tls=
--     全吞进同一个字段，比按逗号切更糟。
--   * 只跟踪引号开合，不做转义处理 —— Surge / Loon / QX 的行语法里都没有转义
--     机制（Loon 文档只把引号列为位置参数的写法，未提及任何转义序列）。
--
-- 无引号的输入与旧的 `gmatch("[^,]+")` 逐字符等价：都按逗号切、都丢弃空字段、
-- 都对每段做 trim（旧的 `[^,]+` 会保留纯空白段，trim 后成空串，这里同样保留）。
local function split_fields(s)
	local nquote = 0
	for _ in s:gmatch('"') do nquote = nquote + 1 end
	if nquote % 2 == 1 then
		local out = {}
		for part in s:gmatch("[^,]+") do out[#out + 1] = util.trim(part) end
		return out
	end
	local out, buf, quoted = {}, {}, false
	for i = 1, #s do
		local c = s:sub(i, i)
		if c == '"' then
			quoted = not quoted
			buf[#buf + 1] = c
		elseif c == "," and not quoted then
			if #buf > 0 then out[#out + 1] = util.trim(table.concat(buf)) end
			buf = {}
		else
			buf[#buf + 1] = c
		end
	end
	if #buf > 0 then out[#out + 1] = util.trim(table.concat(buf)) end
	return out
end

-- 解析 Surge 风格行：Name = proto, server, port, k=v, ...
local function parse_surge_line(name, rest)
	local parts = split_fields(rest)
	if #parts < 3 then return nil end

	local proto = map_proto(parts[1])
	if not proto then return nil end
	local server = parts[2]
	local port = tonumber(parts[3])

	-- 具名参数（Surge 家族：`password=pwd`）与位置参数（Loon：`,443,"pwd",`）并存。
	-- Loon 的凭据一律写成端口之后的位置参数并用双引号包起来：
	--   Trojan       = Trojan,trojan.example.com,443,"password",transport=tcp,...
	--   VLESS-Reality= VLESS,vless.example.com,443,"ae521383-...",transport=tcp,...
	--   AnyTLS       = AnyTLS,anytls.example.com,443,"password",sni=...
	--   VMess        = VMess,vmess.example.com,443,aes-128-gcm,"52396e06-...",transport=...
	-- 此前只认具名参数，Loon 配置导入后 uuid / password 全丢，节点因缺凭据被
	-- 下游静默丢弃。位置参数只收集「不含 = 的字段」，具名行完全不受影响。
	-- 切分走 split_fields：引号内的逗号不再被当作分隔符，`"pa,ss"` 这种位置
	-- 参数能原样保留（见该函数的说明）。
	local kv, pos = {}, {}
	for i = 4, #parts do
		local k, v = parts[i]:match("^([%w%-]+)%s*=%s*(.*)$")
		if k then
			kv[k] = util.trim(v)
		else
			pos[#pos + 1] = unquote(parts[i])
		end
	end

	local data = {
		proto = proto, name = util.trim(name), server = server, port = port,
	}
	if proto == "shadowsocks" then
		data.method = kv["encrypt-method"] or kv.cipher or kv.method
		data.password = kv.password
	elseif proto == "vmess" or proto == "vless" then
		-- Loon 的 VMess 位置参数是「加密方式, UUID」两个字段；VLESS 只有一个 UUID
		if proto == "vmess" and pos[2] then
			data.cipher = pos[1]
			data.uuid = kv.username or kv.uuid or pos[2]
		else
			data.uuid = kv.username or kv.uuid or pos[1]
		end
		if kv.flow then data.flow = kv.flow end
	elseif proto == "trojan" then
		data.password = kv.password or pos[1]
	elseif proto == "anytls" then
		data.password = kv.password or pos[1]
	elseif proto == "hysteria2" or proto == "hysteria" then
		data.password = kv.password
	end

	-- Reality 参数。Loon 的 VLESS / VMess / Trojan / AnyTLS Reality 行共用
	-- public-key（Base64 公钥）与 short-id（十六进制）两个参数名，公钥取值带引号：
	--   public-key="LgJ9bNTyUqBLFkDA12-QgEL7c1yQ1ztk-V1Q-3OLXSk",short-id=164168844958a16d
	-- 原样带过去即可 —— node.normalize 会据 public-key 把 security 定为 reality。
	if kv["public-key"] then data["public-key"] = unquote(kv["public-key"]) end
	if kv["short-id"] then data["short-id"] = unquote(kv["short-id"]) end

	-- 传输/TLS 通用字段
	if kv.net or kv.network then data.net = kv.net or kv.network end
	if kv["ws"] == "true" then data.net = "ws" end
	if kv["ws-path"] then data.path = kv["ws-path"] end
	if kv["ws-headers"] and kv["ws-headers"]:match("^Host:") then
		data.host = kv["ws-headers"]:match("^Host:%s*(.*)$")
	end
	-- Loon 的传输写法是 transport=<tcp|ws|http> + path= + host=
	-- （nsloon.app/docs/Node/ 的示例行），与 Surge 家族的 net= / ws=true /
	-- ws-path / ws-headers=Host: 是同一组语义的两代写法 —— Loon 文档明说
	-- 「旧参数 ws=true、ws-path、ws-headers=Host:域名 分别对应 transport=ws、
	-- path、host」，即旧写法只是兼容别名。只认旧写法时，别人给的 Loon 配置
	-- 导入后 net 保持默认 tcp、path / host 全丢，导出到任何格式都按 tcp 去连一个
	-- 只开了 ws 的端口 —— 握手失败且不报错。
	-- transport=http 按同一段文档「兼容配置中的 transport=http 会按 WebSocket
	-- 处理」同样落成 ws。
	-- 放在 ws=true / ws-path / ws-headers 之后：同一行两种写法都出现时以新写法为准。
	if kv.transport then
		data.net = (kv.transport == "http") and "ws" or kv.transport
	end
	if kv.path then data.path = kv.path end
	if kv.host then data.host = kv.host end
	if kv.sni then data.sni = kv.sni end
	-- Surge 家族写 tls=true，Loon 写 over-tls=true，两种都是「启用 TLS」
	if kv.tls and kv.tls ~= "false" and kv.tls ~= "none" then data.security = "tls" end
	if kv["over-tls"] and kv["over-tls"] ~= "false" and kv["over-tls"] ~= "none" then
		data.security = "tls"
	end
	if kv["skip-cert-verify"] and kv["skip-cert-verify"] ~= "0" and kv["skip-cert-verify"] ~= "false" then
		data["skip-cert-verify"] = true
	end
	return node.normalize(data)
end

-- 解析 QX server_local 行：proto=server:port, k=v, ..., tag=Name
local function parse_qx_line(content)
	local proto, rest = content:match("^([%w_]+)%s*=%s*(.+)$")
	if not proto then return nil end
	local parts = split_fields(rest)
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
	elseif proto == "anytls" then
		data.password = kv.password
	end
	-- QX 用 obfs= 表示传输 / TLS 模式（官方 sample.conf）：over-tls 是「纯 TLS」、
	-- wss 是「ws + TLS」、ws 是明文 ws。obfs-host 在 ws 下是 Host 头、在 over-tls
	-- 下是 SNI —— 语义不同，必须分别落到 host / sni，否则 vless + over-tls 的节点
	-- 导入后 SNI 被写进 host，Reality 那条更是连不上。
	if kv["obfs"] == "over-tls" then
		data.security = "tls"
		if kv["obfs-host"] then data.sni = kv["obfs-host"] end
	else
		if kv["obfs"] == "ws" or kv["obfs"] == "wss" then data.net = "ws" end
		if kv["obfs"] == "wss" then data.security = "tls" end
		if kv["obfs-uri"] then data.path = kv["obfs-uri"] end
		if kv["obfs-host"] then data.host = kv["obfs-host"] end
	end
	if kv["tls-host"] then data.sni = kv["tls-host"] end
	if kv["tls-verification"] == "true" or kv["over-tls"] == "true" then data.security = "tls" end
	-- flow：QX 的 vless 写 vless-flow=xtls-rprx-vision（sample.conf 的 Reality 条目）
	if kv["vless-flow"] then data.flow = kv["vless-flow"] end
	-- Reality：QX 的键名与分享链接 / Clash 都不同 —— Base64 公钥是
	-- reality-base64-pubkey，十六进制 short id 是 reality-hex-shortid。
	-- node.normalize 会据 public-key 把 security 定为 reality。
	if kv["reality-base64-pubkey"] then data["public-key"] = kv["reality-base64-pubkey"] end
	if kv["reality-hex-shortid"] then data["short-id"] = kv["reality-hex-shortid"] end
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