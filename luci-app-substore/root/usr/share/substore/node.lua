-- node.lua — 统一节点模型（纯 Lua）
-- luci-app-substore

local M = {}

M.PROTOS = {
	"vmess", "vless", "trojan", "shadowsocks", "ssr", "hysteria2", "tuic", "hysteria", "wireguard", "socks",
}

-- 协议默认值，用于补全缺省字段
local DEFAULTS = {
	vmess = { net = "tcp", security = "none" },
	vless = { net = "tcp", security = "none" },
	trojan = { security = "tls" },
}

-- vmess 加密方式（cipher）白名单。sing-box 的 vmess.security、Xray 的
-- users[].security、Clash 的 vmess.cipher 取同一组值；写入非法值会让客户端
-- 拒绝整份配置，因此归一化时丢弃未知取值，由输出端回退到 "auto"。
M.VMESS_CIPHERS = {
	auto = true, none = true, zero = true,
	["aes-128-gcm"] = true, ["chacha20-poly1305"] = true,
}

-- 判断节点是否拥有某标签；兼容 tags 为数组（{"fast"}）或 set（{fast=true}）
local function has_tag(node, tag)
	local t = node and node.tags
	if type(t) ~= "table" then return false end
	if t[tag] == true then return true end
	for _, v in ipairs(t) do
		if v == tag then return true end
	end
	return false
end

-- 归一化：协议别名统一、补默认值、保证 name 非空
function M.normalize(node)
	if type(node) ~= "table" then return node end
	if node.proto == "ss" then node.proto = "shadowsocks" end
	-- socks5 与 socks 是同一个协议，只是各客户端写法不同（Clash 写 socks5、
	-- sing-box 写 socks、分享链接写 socks5://）。统一成 socks：
	-- 各输出模块本来就同时认这两种写法，但 node.filter / rules.proto_filter
	-- 是精确比较，两种写法会互相看不见——节点页按协议筛选和规则过滤都会漏。
	if node.proto == "socks5" then node.proto = "socks" end
	local d = DEFAULTS[node.proto] or {}
	for k, v in pairs(d) do
		if node[k] == nil then node[k] = v end
	end

	-- tls 的空串 / "none" / "false" 在 Lua 里都是真值，会被下游的
	-- `if node.tls then` 误判为「启用 TLS」（经典 vmess JSON 的 tls:"" 即此例），
	-- 统一归一为 nil
	if node.tls == "" or node.tls == "none" or node.tls == "false" then
		node.tls = nil
	elseif node.tls == "true" then
		-- 简易 YAML 解析器把 tls: true 读成字符串 "true"
		node.tls = true
	end

	-- tls 与 security 是同一语义（TLS 层）的两种写法，统一落到 security；
	-- 已显式给出 security（含 DEFAULTS 补的 "none"）时不覆盖
	if node.security == nil or node.security == "none" then
		if node.tls == true then
			node.security = "tls"
		elseif node.tls == "tls" or node.tls == "reality" then
			node.security = node.tls
		end
	end

	-- vmess 的加密方式存于 cipher，与 TLS 层（security）无关；
	-- 非白名单取值（例如被误写成 "tls"）直接丢弃，避免输出非法配置
	if node.proto == "vmess" and node.cipher ~= nil and not M.VMESS_CIPHERS[node.cipher] then
		node.cipher = nil
	end

	if node.name == nil or node.name == "" then
		node.name = (node.server or "") .. ":" .. tostring(node.port or "")
	end
	-- tags 字符串自动拆分为数组（逗号分隔）
	if type(node.tags) == "string" then
		local t = {}
		for tag in node.tags:gmatch("[^,]+") do
			tag = tag:match("^%s*(.-)%s*$")
			if tag ~= "" then t[#t + 1] = tag end
		end
		node.tags = t
	end
	-- 保持 group、remarks、template、url 字段原样
	return node
end

-- 过滤：支持 proto、keyword（name/server）、server、port、group、tags
function M.filter(nodes, opts)
	opts = opts or {}
	local out = {}
	for _, n in ipairs(nodes) do
		if opts.proto and n.proto ~= opts.proto then
		else
			local ok = true
			if opts.keyword and opts.keyword ~= "" then
				local kw = opts.keyword:lower()
				if not ( (n.name or ""):lower():find(kw, 1, true) or (n.server or ""):lower():find(kw, 1, true) ) then
					ok = false
				end
			end
			if ok and opts.server and n.server ~= opts.server then ok = false end
			if ok and opts.port and tonumber(n.port) ~= tonumber(opts.port) then ok = false end
			if ok and opts.group and n.group ~= opts.group then ok = false end
			if ok and opts.tags then
				local wanted = opts.tags
				if type(wanted) == "string" then wanted = wanted:gsub("^%s*(.-)%s*$", "%1") end
				if not has_tag(n, wanted) then ok = false end
			end
			if ok then out[#out + 1] = n end
		end
	end
	return out
end

-- WireGuard peer 公钥。字段名以 parser 产出的 "public-key" 为准，
-- 其余为历史/导入别名（output_wireguard_conf 同样接受这几种写法）
local function wg_public_key(n)
	return n["public-key"] or n.public_key or n["peer-public-key"] or n.peer_public_key
end

-- 去重：按 proto+server+port 唯一。
-- WireGuard/AmneziaWG 例外：同一个 endpoint 上不同 peer 公钥是**不同**的节点，
-- 只按 server+port 去重会把它们错误合并（§32/§43），因此把公钥并入去重键。
function M.dedup(nodes)
	local seen = {}
	local out = {}
	for _, n in ipairs(nodes) do
		local key = (n.proto or "") .. "|" .. (n.server or "") .. "|" .. tostring(n.port or "")
		if n.proto == "wireguard" or n.proto == "wg" then
			key = key .. "|" .. tostring(wg_public_key(n) or "")
		end
		if not seen[key] then
			seen[key] = true
			out[#out + 1] = n
		end
	end
	return out
end

-- 排序：by = "name"|"server"|"proto"|"port"
function M.sort(nodes, by, desc)
	by = by or "name"
	desc = desc and true or false
	table.sort(nodes, function(a, b)
		local av, bv = a[by], b[by]
		if by == "port" then
			av, bv = tonumber(av) or 0, tonumber(bv) or 0
		else
			-- 字段值可能是数字（例如 Clash YAML 里 `- name: 123`），
			-- 数字和字符串直接比较会抛 "attempt to compare number with string"，
			-- 整个节点列表页就崩了；统一转成字符串再比。
			av = tostring(av == nil and "" or av)
			bv = tostring(bv == nil and "" or bv)
		end
		if av == bv then return false end
		if desc then return av > bv else return av < bv end
	end)
	return nodes
end

-- 重命名单个节点
function M.rename(node, new_name)
	if type(node) == "table" and new_name then
		node.name = new_name
	end
	return node
end

-- 逗号分隔列表 → 数组，逐项去空白。
-- 与 split_keywords 的区别：不做小写化（group / template 名是大小写敏感的）。
-- 原来各过滤器直接 gmatch("[^,]+") 不去空白，"vmess, vless" 会把 " vless"
-- （带前导空格）当成一个协议名，于是只剩 1 个节点且不报错。
local function split_list(s)
	local out = {}
	for item in (s or ""):gmatch("[^,]+") do
		item = item:match("^%s*(.-)%s*$")
		if item ~= "" then out[#out + 1] = item end
	end
	return out
end

-- 将关键词串拆分为数组（英文逗号/中文逗号/空白分隔），忽略空项，并统一小写
local function split_keywords(s)
	local out = {}
	for kw in (s or ""):gmatch("[^,%s，]+") do
		kw = kw:lower()
		if kw ~= "" then out[#out + 1] = kw end
	end
	return out
end

-- 判断节点 name/server 是否命中任一关键词
local function match_keywords(n, kws)
	local name = (n.name or ""):lower()
	local server = (n.server or ""):lower()
	for _, kw in ipairs(kws) do
		if name:find(kw, 1, true) or server:find(kw, 1, true) then
			return true
		end
	end
	return false
end

-- 应用规则集到节点列表
function M.apply_rules(nodes, rules)
	rules = rules or {}
	-- 协议过滤
	if rules.proto_filter and rules.proto_filter ~= "" then
		local set = {}
		for _, p in ipairs(split_list(rules.proto_filter)) do set[p] = true end
		local out = {}
		for _,n in ipairs(nodes) do
			if set[n.proto] then out[#out+1]=n end
		end
		nodes = out
	end
	-- 分组过滤
	if rules.group_filter and rules.group_filter ~= "" then
		local set = {}
		for _, g in ipairs(split_list(rules.group_filter)) do set[g]=true end
		local out = {}
		for _,n in ipairs(nodes) do
			if set[n.group] then out[#out+1]=n end
		end
		nodes = out
	end
	-- 标签包含
	if rules.tags_include and rules.tags_include ~= "" then
		local set = {}
		for _, t in ipairs(split_list(rules.tags_include)) do set[t]=true end
		local out = {}
		for _,n in ipairs(nodes) do
			local match = false
			for tag in pairs(set) do
				if has_tag(n, tag) then match = true; break end
			end
			if match then out[#out+1]=n end
		end
		nodes = out
	end
	-- 模板过滤
	if rules.template_filter and rules.template_filter ~= "" then
		local set = {}
		for _, tmpl in ipairs(split_list(rules.template_filter)) do set[tmpl]=true end
		local out = {}
		for _,n in ipairs(nodes) do
			if set[n.template] then out[#out+1]=n end
		end
		nodes = out
	end
	-- 关键词包含
	if rules.keyword_include and rules.keyword_include ~= "" then
		local kws = split_keywords(rules.keyword_include)
		local out = {}
		for _,n in ipairs(nodes) do
			if match_keywords(n, kws) then out[#out+1]=n end
		end
		nodes = out
	end
	-- 关键词排除
	if rules.keyword_exclude and rules.keyword_exclude ~= "" then
		local kws = split_keywords(rules.keyword_exclude)
		local out = {}
		for _,n in ipairs(nodes) do
			if not match_keywords(n, kws) then out[#out+1]=n end
		end
		nodes = out
	end
	-- 去重
	if rules.dedup == "1" or rules.dedup == true then
		nodes = M.dedup(nodes)
	end
	-- 重命名规则（精确匹配 / 正则 / 模板，统一走重命名引擎）
	if rules.rename_map and rules.rename_map ~= "" then
		nodes = M.rename_with_rules(nodes, M.parse_rename_rules(rules.rename_map))
	end
	-- 模板应用：若节点有 template，则生成 url（简单占位符替换）
	if rules.template_apply == true or rules.template_apply == "1" then
		for _,n in ipairs(nodes) do
			if n.template and n.template ~= "" and not n.url then
				local url = n.template
				url = url:gsub("{server}", n.server or "")
				url = url:gsub("{port}", tostring(n.port or ""))
				url = url:gsub("{uuid}", n.uuid or n.password or "")
				url = url:gsub("{name}", n.name or "")
				n.url = url
			end
		end
	end
	return nodes
end

-- ---------- 分组 ----------

-- 按字段分组：返回 { [字段值] = {节点...} }
function M.group_by(nodes, field)
	local groups = {}
	for _, n in ipairs(nodes) do
		local key = tostring(n[field] or "")
		if not groups[key] then groups[key] = {} end
		groups[key][#groups[key] + 1] = n
	end
	return groups
end

-- 按自身 group 字段分组（缺省组 ""）
function M.group_nodes(nodes)
	return M.group_by(nodes, "group")
end

-- 按规则为节点设置 group：rules = { {field=..., prefix=...}, ... }
function M.add_group(nodes, rules)
	rules = rules or {}
	for _, n in ipairs(nodes) do
		for _, r in ipairs(rules) do
			if type(r) == "table" and r.field then
				n.group = (r.prefix or "") .. tostring(n[r.field] or "")
			end
		end
	end
	return nodes
end

-- 按组名过滤
function M.filter_by_group(nodes, group_name)
	local out = {}
	for _, n in ipairs(nodes) do
		if n.group == group_name then out[#out + 1] = n end
	end
	return out
end

-- ---------- 标签 ----------

-- 为节点打标签。两种模式：
--   数组模式：add_tags(nodes, {"vip"}) 追加字符串标签（tags 存为数组）
--   规则模式：add_tags(nodes, {{type="keyword", value="HK", tag="hongkong"}}) 匹配后写 tag（tags 存为 set）
function M.add_tags(nodes, tags)
	tags = tags or {}
	if type(tags) == "string" then tags = { tags } end
	if type(tags) ~= "table" then return nodes end

	-- 规则模式：元素为 {type, value, tag}
	if tags[1] and type(tags[1]) == "table" then
		for _, n in ipairs(nodes) do
			if not n.tags or type(n.tags) ~= "table" then n.tags = {} end
			for _, rule in ipairs(tags) do
				local matched = false
				if rule.type == "keyword" then
					local kw = rule.value or ""
					if kw ~= "" and ((n.name or ""):find(kw, 1, true) or (n.server or ""):find(kw, 1, true)) then
						matched = true
					end
				end
				if matched and rule.tag then
					n.tags[rule.tag] = true
				end
			end
		end
		return nodes
	end

	-- 数组模式：追加字符串标签（去重）
	for _, n in ipairs(nodes) do
		if not n.tags then n.tags = {} end
		if type(n.tags) ~= "table" then n.tags = {} end
		local has = {}
		for _, t in ipairs(n.tags) do has[t] = true end
		for _, t in ipairs(tags) do
			if not has[t] then
				n.tags[#n.tags + 1] = t
				has[t] = true
			end
		end
	end
	return nodes
end

-- 按标签集合过滤：要求节点拥有 tags 中的所有标签
function M.filter_by_tags(nodes, tags)
	local out = {}
	for _, n in ipairs(nodes) do
		local match = true
		if type(tags) == "string" then tags = { tags } end
		for _, t in ipairs(tags) do
			if not has_tag(n, t) then match = false; break end
		end
		if match then out[#out + 1] = n end
	end
	return out
end

-- ---------- 重命名规则引擎 ----------

-- 解析重命名规则字符串为规则表列表
-- 支持格式（每行一条，支持 # 注释）：
--   "旧名称=新名称"（精确匹配，type="exact"）
--   "pattern -> replacement"（正则替换，type="regex"）
--   "{server}_{port}_{proto}"（含 {var} 占位符，type="template"）
function M.parse_rename_rules(rule_str)
	rule_str = rule_str or ""
	local rules = {}
	for line in rule_str:gmatch("[^\r\n]+") do
		line = line:match("^%s*(.-)%s*$")
		if line ~= "" and not line:match("^#") then
			local pat, repl = line:match("^(.-)%s*%-%>%s*(.+)$")
			if pat then
				rules[#rules + 1] = { type = "regex", pattern = pat, replacement = repl }
			elseif line:find("{", 1, true) then
				rules[#rules + 1] = { type = "template", template = line }
			else
				local k, v = line:match("^([^=]+)=(.*)$")
				if k and v then
					rules[#rules + 1] = { type = "exact", old = k:match("^%s*(.-)%s*$"), new = v:match("^%s*(.-)%s*$") }
				end
			end
		end
	end
	return rules
end

-- 展开模板：替换 {var} 占位符
-- gsub 的**替换串**里 % 有特殊含义（%1 反向引用、%% 转义），而节点数据是不可信输入：
-- 名字里带 "%" 时会被静默吞掉（"50% OFF" → "50 OFF"），更糟的是能拼出 %0，
-- 在结果里产生 NUL 字节并一路写进节点名、写盘、下发到各订阅文件。
-- 所以替换前必须先把值里的 % 转义成 %%。
local function expand_template(template, n)
	local function esc(v) return (tostring(v == nil and "" or v):gsub("%%", "%%%%")) end
	local out = template
	out = out:gsub("{server}", esc(n.server))
	out = out:gsub("{port}", esc(n.port))
	out = out:gsub("{proto}", esc(n.proto))
	out = out:gsub("{name}", esc(n.name))
	out = out:gsub("{uuid}", esc(n.uuid))
	out = out:gsub("{password}", esc(n.password))
	out = out:gsub("{group}", esc(n.group))
	return out
end

-- 正则风格 → Lua pattern 的转义映射。
-- Lua pattern 里转义符是 %，所以 \d 之类要改写；\d \D \w \W \s \S 与 Lua 的
-- %d %D %w %W %s %S 一一对应。
-- \b \B（词边界）在 Lua pattern 里**没有**对应写法：原来一律把 \ 换成 %，
-- 于是 \b 变成了 %b —— 那是「成对匹配」（%bxy 匹配 x…y），语义完全不同，
-- 而且经常直接抛错、被下面的 pcall 吞掉。这里按「无操作」处理。
local REGEX_ESCAPE = {
	d = "%d", D = "%D", w = "%w", W = "%W", s = "%s", S = "%S",
	b = "", B = "",
}

-- 把「正则里是普通字符、Lua pattern 里却是元字符」的字符转义。
-- 最要命的是 `-`：正则里在字符类外就是普通字符（"HK-01"、"Node-42"），
-- Lua pattern 里却是「懒惰量词」，于是 `Node-(\d+)` 被解释成 Nod + e- + 数字，
-- 永远匹配不上，而且不报错（pcall 也吞不掉，因为根本没抛错）。
-- 字符类 [...] 内的 - 是范围（[a-z]），两边语义一致，保持原样。
-- `\x` 按 REGEX_ESCAPE 映射（\d→%d，\b→空），其余转义字符按 Lua 写法 %x。
local function regex_to_lua(pat)
	local out, i, in_class = {}, 1, false
	local n = #pat
	while i <= n do
		local c = pat:sub(i, i)
		if c == "\\" and i < n then
			local nx = pat:sub(i + 1, i + 1)
			local m = REGEX_ESCAPE[nx]
			out[#out + 1] = (m ~= nil) and m or ("%" .. nx)
			i = i + 2
		elseif c == "[" then
			in_class = true; out[#out + 1] = c; i = i + 1
		elseif c == "]" then
			in_class = false; out[#out + 1] = c; i = i + 1
		elseif c == "-" and not in_class then
			out[#out + 1] = "%-"; i = i + 1
		else
			out[#out + 1] = c; i = i + 1
		end
	end
	return table.concat(out)
end

-- 把 `a|b` 拆成多个候选（**仅顶层** |）。
-- 正则的「或」在 Lua pattern 里不存在，原来整个规则会静默不匹配。
-- 只拆括号深度为 0、且不在字符类 [] 里的 |：
--   * `[...]` 里的 | 是字面字符（Lua 的 [a|b] 匹配 a、| 或 b），拆开会破坏字符类
--   * `(...)` 里的 | 属于分组内部。Lua pattern 的 () 只是捕获，没有「或」语义，
--     拆开只会得到 `^(HK` / `US` / `JP)%-(.*)$` 这种残缺模式——比不拆更糟：
--     每一段都匹配不上，还静默无提示。分组内的「或」明确不支持，按字面处理。
local function split_alternatives(pat)
	local alts, buf = {}, {}
	local depth, in_class, i = 0, false, 1
	local n = #pat
	-- 必须是 while 而不是 for：下面遇到 % 转义序列要一次吃掉两个字符，
	-- Lua 的数值 for 会在每轮重新赋值控制变量，循环体内改 i 不生效。
	-- 也不用 goto（Lua 5.1 没有）。
	while i <= n do
		local c = pat:sub(i, i)
		if c == "%" then
			-- Lua 转义序列整体保留（regex_to_lua 已产出 %d / %- 这类两字符序列）
			buf[#buf + 1] = c .. pat:sub(i + 1, i + 1)
			i = i + 2
		elseif c == "|" and depth == 0 and not in_class then
			alts[#alts + 1] = table.concat(buf)
			buf = {}
			i = i + 1
		else
			if in_class then
				if c == "]" then in_class = false end
			elseif c == "[" then
				in_class = true
			elseif c == "(" then
				depth = depth + 1
			elseif c == ")" and depth > 0 then
				depth = depth - 1
			end
			buf[#buf + 1] = c
			i = i + 1
		end
	end
	alts[#alts + 1] = table.concat(buf)
	return alts
end

-- 按规则链式重命名节点（就地修改）
function M.rename_with_rules(nodes, rules)
	rules = rules or {}
	for _, n in ipairs(nodes) do
		for _, r in ipairs(rules) do
			if r.type == "exact" then
				if n.name == r.old then n.name = r.new end
			elseif r.type == "template" and r.template then
				n.name = expand_template(r.template, n)
			elseif r.type == "regex" then
				local name = n.name or ""
				-- 正则风格 → Lua pattern：\d -> %d、$1 -> %1、HK-01 里的 - 转义成 %-
				local pat = regex_to_lua(r.pattern or "")
				local repl = (r.replacement or ""):gsub("%$", "%%")
				local ok, result = pcall(function()
					-- 顶层 | 拆成多个候选依次替换（Lua pattern 没有「或」）
					local s = name
					for _, alt in ipairs(split_alternatives(pat)) do
						s = s:gsub(alt, repl)
					end
					return s
				end)
				if ok then
					n.name = result
				end
			end
		end
	end
	return nodes
end

return M