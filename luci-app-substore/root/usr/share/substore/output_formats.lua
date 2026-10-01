-- output_formats.lua — Surge 系 / Loon / QX / Egern / Stash / Plain JSON 输出（纯 Lua）
-- luci-app-substore

local util = require("substore.util")
local clash_meta = require("substore.output_clash_meta")

local M = {}

-- 规范化协议名
local function props(n)
	local proto = (n.proto or ""):lower()
	if proto == "ss" then proto = "shadowsocks" end
	return proto
end

-- 生成 Surge 风格代理行（Surge / Surfboard / SurgeMac / Loon / Egern 通用）
function M.surge_line(n)
	local proto = props(n)
	local head = proto .. ", " .. (n.server or "") .. ", " .. tostring(n.port or 0)
	local e = {}
	local tls = (n.security and n.security ~= "none") or (n.tls and n.tls ~= false and n.tls ~= "none")

	if proto == "shadowsocks" then
		e[#e + 1] = "encrypt-method=" .. (n.method or n.cipher or "aes-256-gcm")
		e[#e + 1] = "password=" .. (n.password or "")
	elseif proto == "vmess" then
		e[#e + 1] = "username=" .. (n.uuid or "")
		if tls then e[#e + 1] = "tls=true" end
		if n.sni then e[#e + 1] = "sni=" .. n.sni end
		if n.net == "ws" then
			e[#e + 1] = "ws=true"
			if n.path then e[#e + 1] = "ws-path=" .. n.path end
			if n.host then e[#e + 1] = "ws-headers=Host:" .. n.host end
		end
	elseif proto == "vless" then
		e[#e + 1] = "username=" .. (n.uuid or "")
		if tls then e[#e + 1] = "tls=true" end
		if n.sni then e[#e + 1] = "sni=" .. n.sni end
		if n.flow then e[#e + 1] = "flow=" .. n.flow end
	elseif proto == "trojan" then
		e[#e + 1] = "password=" .. (n.password or "")
		e[#e + 1] = "tls=true"
		if n.sni then e[#e + 1] = "sni=" .. n.sni end
	elseif proto == "ssr" then
		e[#e + 1] = "encrypt-method=" .. (n.method or n.cipher or "aes-128-cfb")
		e[#e + 1] = "password=" .. (n.password or "")
		e[#e + 1] = "protocol=" .. (n.protocol or "origin")
		e[#e + 1] = "obfs=" .. (n.obfs or "plain")
		local op = n.obfs_param or n["obfs-param"]
		local pp = n.protocol_param or n["protocol-param"]
		if op and op ~= "" then e[#e + 1] = "obfs-param=" .. op end
		if pp and pp ~= "" then e[#e + 1] = "protocol-param=" .. pp end
	elseif proto == "hysteria2" or proto == "hysteria" then
		e[#e + 1] = "password=" .. (n.password or "")
		if n.sni then e[#e + 1] = "sni=" .. n.sni end
	elseif proto == "tuic" then
		e[#e + 1] = "username=" .. (n.uuid or "")
		if n.password then e[#e + 1] = "password=" .. n.password end
		if n.sni then e[#e + 1] = "sni=" .. n.sni end
		if n.alpn then
			-- alpn 可能是数组：sing-box JSON 与 Clash YAML 的 alpn 列表导入后就是 table，
			-- 直接拼接会 "attempt to concatenate a table value" 让整次导出失败
			local alpn = n.alpn
			if type(alpn) == "table" then alpn = table.concat(alpn, ",") end
			if alpn ~= "" then e[#e + 1] = "alpn=" .. alpn end
		end
	elseif proto == "socks5" or proto == "socks" or proto == "http" then
		-- socks5 / http 在 Surge 家族里都用 username= / password= 具名参数
		-- （Surge 手册：Name = http, <host>, <port>[, <username>, <password>]
		--   "may be given positionally after the port, or as named parameters"）
		if n.username then
			e[#e + 1] = "username=" .. n.username
			if n.password then e[#e + 1] = "password=" .. n.password end
		end
	end

	if n["skip-cert-verify"] then e[#e + 1] = "skip-cert-verify=1" end
	if n.udp then e[#e + 1] = "udp-relay=true" end

	local line = (n.name or "") .. " = " .. head
	if #e > 0 then line = line .. ", " .. table.concat(e, ", ") end
	-- 节点名与各参数值都来自订阅（不可信）：含换行会截断本行并伪造出一条新的代理行
	return util.one_line(line)
end

-- 收集可用于「逗号分隔成员列表」的节点名（Surge 家族 [Proxy Group] / QX [policy]）。
--
-- 两类名字必须排除，否则生成的配置整体非法：
--   * 含逗号：这些格式的成员列表就是 `NAME = select, X, Y, DIRECT`，语法里没有
--     引号 / 转义机制，名字里的逗号会被当成成员分隔符 —— `A,B` 被读成两个成员
--     `A` 与 `B`，两个都不存在，Surge / QX 会因引用不存在的代理而拒绝加载整份
--     配置。节点定义本身仍留在 [Proxy] / [server_local] 中，只是不进成员列表。
--   * 换行：定义行经过 util.one_line（换行→空格），成员列表若用原始名就对不上
--     定义行，同样成为悬空引用。这里统一先 one_line 再比对，保证两边一致。
local function names_of(nodes)
	local out = {}
	for _, n in ipairs(nodes or {}) do
		local nm = util.one_line(n.name)
		if nm and nm ~= "" and not nm:find(",", 1, true) then
			out[#out + 1] = nm
		end
	end
	return out
end

-- Surge 家族配置（Surge / Surfboard / SurgeMac / Loon / Egern 通用）
-- supports_ssr：Loon / Egern 支持 SSR；Surge / Surfboard / SurgeMac 不支持，跳过 ssr 节点
local function surge_config(nodes, group_name, supports_ssr)
	local list = nodes or {}
	-- 过滤 Surge 家族无法用单行 [Proxy] 表达的协议：
	--   ssr：仅 Loon / Egern 支持（supports_ssr），Surge/Surfboard/SurgeMac 丢
	--   wireguard：Surge 需专用多段 [WireGuard] 配置，单行无法表达，统一丢弃（不输出损坏行）
	local kept = {}
	for _, n in ipairs(list) do
		local p = (n.proto or ""):lower()
		if p == "wireguard" then
			-- drop
		elseif not supports_ssr and p == "ssr" then
			-- drop
		else
			kept[#kept + 1] = n
		end
	end
	list = kept
	local out = {}
	out[#out + 1] = "[Proxy]"
	for _, n in ipairs(list) do
		out[#out + 1] = M.surge_line(n)
	end
	out[#out + 1] = ""
	out[#out + 1] = "[Proxy Group]"
	local names = names_of(list)
	local select = group_name .. " = select"
	for _, nm in ipairs(names) do select = select .. ", " .. nm end
	select = select .. ", DIRECT"
	out[#out + 1] = util.one_line(select)
	return table.concat(out, "\n")
end

function M.to_surge(nodes, options)
	options = options or {}
	return surge_config(nodes, options.name or "PROXY", false)
end

function M.to_surfboard(nodes, options)
	options = options or {}
	return surge_config(nodes, options.name or "PROXY", false)
end

function M.to_surgemac(nodes, options)
	options = options or {}
	return surge_config(nodes, options.name or "PROXY", false)
end

-- Loon / Egern：Surge 兼容语法（支持 SSR）
function M.to_loon(nodes, options)
	options = options or {}
	return surge_config(nodes, options.name or "PROXY", true)
end

function M.to_egern(nodes, options)
	options = options or {}
	return surge_config(nodes, options.name or "PROXY", true)
end

-- Stash：Clash 兼容 YAML
function M.to_stash(nodes, options)
	return clash_meta.generate(nodes, options)
end

-- Clash 原版（Dreamacro Clash / ClashX / Clash for Windows）不支持的协议类型。
-- 只排除"确定不支持"的，不做白名单，避免误丢原版其实支持的类型。
local CLASH_LEGACY_UNSUPPORTED = {
	vless = true, hysteria2 = true, hysteria = true, tuic = true, wireguard = true,
}

-- Clash 原版：过滤掉原版不认识的协议后，复用 Clash.Meta 的 YAML 生成
function M.to_clash(nodes, options)
	local kept = {}
	for _, n in ipairs(nodes or {}) do
		local p = props(n)
		if not CLASH_LEGACY_UNSUPPORTED[p] then kept[#kept + 1] = n end
	end
	return clash_meta.generate(kept, options)
end

-- Quantumult X
function M.to_qx(nodes, options)
	options = options or {}
	local out = {}
	-- 真正写出了 [server_local] 行的节点。QX 只支持下面这 4 类协议，其余节点
	-- （hysteria2 / hysteria / tuic / socks / wireguard / ssr …）没有定义行；
	-- [policy] 若把它们也列进去，就成了引用不存在服务器的悬空条目。
	local emitted = {}
	out[#out + 1] = "[server_local]"
	for _, n in ipairs(nodes or {}) do
		local proto = props(n)
		local host = (n.server or "") .. ":" .. tostring(n.port or 0)
		local tag = n.name or host
		local before = #out
		if proto == "shadowsocks" then
			out[#out + 1] = string.format(
				"shadowsocks=%s, method=%s, password=%s, tag=%s",
				host, n.method or n.cipher or "aes-256-gcm", n.password or "", tag)
		elseif proto == "vmess" then
			out[#out + 1] = string.format(
				"vmess=%s, method=none, password=%s, tag=%s",
				host, n.uuid or "", tag)
			if n.net == "ws" then
				local esc = out[#out]
				esc = esc .. ", obfs=ws"
				if n.path then esc = esc .. ", obfs-uri=" .. n.path end
				if n.host then esc = esc .. ", obfs-host=" .. n.host end
				out[#out] = esc
			end
			if n.sni then out[#out] = out[#out] .. ", tls-host=" .. n.sni end
			if n.security and n.security ~= "none" then out[#out] = out[#out] .. ", tls-verification=true" end
		elseif proto == "vless" then
			out[#out + 1] = string.format(
				"vless=%s, method=none, password=%s, tag=%s",
				host, n.uuid or "", tag)
		elseif proto == "trojan" then
			out[#out + 1] = string.format(
				"trojan=%s, password=%s, over-tls=true, tag=%s",
				host, n.password or "", tag)
			if n.sni then out[#out] = out[#out] .. ", tls-host=" .. n.sni end
		end
		-- 节点名 / sni / path / host 全部来自订阅（不可信），含换行会截断本行
		-- 并伪造出一条新的 server_local 行
		for i = before + 1, #out do out[i] = util.one_line(out[i]) end
		-- 上面的 if/elseif 命中时必定追加一行，未命中时一行不加
		if #out > before then emitted[#emitted + 1] = n end
	end
	out[#out + 1] = ""
	out[#out + 1] = "[policy]"
	local names = names_of(emitted)
	local policy = "static=" .. (options.name or "PROXY") .. ", DIRECT"
	for _, nm in ipairs(names) do policy = policy .. ", " .. nm end
	out[#out + 1] = util.one_line(policy)
	out[#out + 1] = ""
	out[#out + 1] = "[server_remote]"
	return table.concat(out, "\n")
end

-- Plain JSON：节点统一模型 JSON 数组
function M.to_plain(nodes)
	return util.json_encode(nodes or {})
end

-- 统一分发
function M.generate(nodes, format, options)
	format = (format or ""):lower()
	if format == "surge" then return M.to_surge(nodes, options) end
	if format == "surfboard" then return M.to_surfboard(nodes, options) end
	if format == "surgemac" then return M.to_surgemac(nodes, options) end
	if format == "loon" then return M.to_loon(nodes, options) end
	if format == "egern" then return M.to_egern(nodes, options) end
	if format == "qx" then return M.to_qx(nodes, options) end
	if format == "stash" then return M.to_stash(nodes, options) end
	if format == "clash" then return M.to_clash(nodes, options) end
	if format == "plain" then return M.to_plain(nodes) end
	return nil, "unsupported format: " .. tostring(format)
end

return M