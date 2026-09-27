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
	local d = DEFAULTS[node.proto] or {}
	for k, v in pairs(d) do
		if node[k] == nil then node[k] = v end
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

-- 去重：按 proto+server+port 唯一
function M.dedup(nodes)
	local seen = {}
	local out = {}
	for _, n in ipairs(nodes) do
		local key = (n.proto or "") .. "|" .. (n.server or "") .. "|" .. tostring(n.port or "")
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
		local av = a[by] or ""
		local bv = b[by] or ""
		if by == "port" then av, bv = tonumber(av) or 0, tonumber(bv) or 0 end
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
		for p in rules.proto_filter:gmatch("[^,]+") do set[p]=true end
		local out = {}
		for _,n in ipairs(nodes) do
			if set[n.proto] then out[#out+1]=n end
		end
		nodes = out
	end
	-- 分组过滤
	if rules.group_filter and rules.group_filter ~= "" then
		local set = {}
		for g in rules.group_filter:gmatch("[^,]+") do set[g]=true end
		local out = {}
		for _,n in ipairs(nodes) do
			if set[n.group] then out[#out+1]=n end
		end
		nodes = out
	end
	-- 标签包含
	if rules.tags_include and rules.tags_include ~= "" then
		local set = {}
		for t in rules.tags_include:gmatch("[^,]+") do set[t]=true end
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
		for tmpl in rules.template_filter:gmatch("[^,]+") do set[tmpl]=true end
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
local function expand_template(template, n)
	local out = template
	out = out:gsub("{server}", n.server or "")
	out = out:gsub("{port}", tostring(n.port or ""))
	out = out:gsub("{proto}", n.proto or "")
	out = out:gsub("{name}", n.name or "")
	out = out:gsub("{uuid}", n.uuid or "")
	out = out:gsub("{password}", n.password or "")
	out = out:gsub("{group}", n.group or "")
	return out
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
				-- 正则风格 → Lua pattern：\d -> %d、$1 -> %1
				local pat = (r.pattern or ""):gsub("\\", "%%")
				local repl = (r.replacement or ""):gsub("%$", "%%")
				local ok, result = pcall(function()
					return string.gsub(name, pat, repl)
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