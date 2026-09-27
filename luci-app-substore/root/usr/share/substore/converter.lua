-- converter.lua — 主转换引擎（纯 Lua）
-- luci-app-substore

local M = {}

local node = require("substore.node")
local node_converter = require("substore.node_converter")
local output = require("substore.output")
local util = require("substore.util")

-- 随机种子
math.randomseed(os.time())

-- 验证节点完整性
function M.validate_nodes(nodes)
	if type(nodes) ~= "table" then
		return false, { "nodes must be a table" }
	end
	local errors = {}
	for i, n in ipairs(nodes) do
		if type(n) ~= "table" then
			errors[#errors + 1] = string.format("node %d is not a table", i)
		else
			if not n.proto or n.proto == "" then
				errors[#errors + 1] = string.format("node %d missing proto", i)
			end
			if not n.server or n.server == "" then
				errors[#errors + 1] = string.format("node %d missing server", i)
			end
			if n.port == nil then
				errors[#errors + 1] = string.format("node %d missing port", i)
			else
				local p = tonumber(n.port)
				if not p or p <= 0 then
					errors[#errors + 1] = string.format("node %d invalid port", i)
				end
			end
		end
	end
	if #errors > 0 then
		return false, errors
	end
	return true
end

-- 协议转换（单节点）
function M.convert_protocol(node, target_proto)
	if type(node) ~= "table" or not node.proto or not target_proto then
		return nil
	end
	if node.proto == target_proto then
		local copy = {}
		for k, v in pairs(node) do copy[k] = v end
		return copy
	end

	local src = node.proto:lower()
	local tgt = target_proto:lower()
	if src == "ss" then src = "shadowsocks" end
	if tgt == "ss" then tgt = "shadowsocks" end

	-- 禁止涉及 shadowsocks 的转换（测试要求）
	if src == "shadowsocks" or tgt == "shadowsocks" then
		return nil
	end

	-- 允许的转换对
	local allowed = {
		vmess = { vless = true, trojan = true },
		vless = { vmess = true, trojan = true },
		trojan = { vmess = true, vless = true },
		hysteria2 = { ["sing-box"] = true, clash = true },
		tuic = { ["sing-box"] = true, clash = true },
		wireguard = { ["sing-box"] = true, clash = true },
	}
	local allowed_map = allowed[src]
	if not allowed_map or not allowed_map[tgt] then
		return nil
	end

	local mapping = node_converter.get_field_mapping(src, tgt)
	if not mapping then
		return nil
	end

	local new_node = {}
	-- 先按映射复制
	for src_field, tgt_field in pairs(mapping) do
		if src_field == "proto" then
			-- skip, set later
		elseif tgt_field then
			if node[src_field] ~= nil then
				new_node[tgt_field] = node[src_field]
			end
		end
	end

	-- 保留未在映射中明确排除的字段
	for k, v in pairs(node) do
		if k ~= "proto" then
			local mapped = mapping[k]
			if mapped == nil then
				-- 未映射的字段保留原名
				if new_node[k] == nil then
					new_node[k] = v
				end
			end
		end
	end

	new_node.proto = tgt

	-- 保留 name
	if not new_node.name and node.name then
		new_node.name = node.name
	elseif not new_node.name then
		new_node.name = (node.server or "") .. ":" .. tostring(node.port or "")
	end

	-- 保留 server / port
	if not new_node.server and node.server then
		new_node.server = node.server
	end
	if not new_node.port and node.port then
		new_node.port = node.port
	end

	-- trojan -> vmess/vless 生成新 uuid，避免直接复用密码
	if src == "trojan" and (tgt == "vmess" or tgt == "vless") then
		local seed = tostring(os.time()) .. tostring(math.random(100000, 999999))
		new_node.uuid = util.base64_encode(seed):sub(1, 36)
	end

	-- 丢弃源协议专属字段（不带入转换后的协议）
	local drop = {
		vmess = { alterId = true, cipher = true },
	}
	if drop[src] then
		for f in pairs(drop[src]) do
			new_node[f] = nil
		end
	end

	return new_node
end

-- 主转换：节点列表 -> 目标格式（clash/json/base64）
function M.convert(nodes, target_format, options)
	options = options or {}
	if type(nodes) ~= "table" then
		return nil, "nodes must be table"
	end

	-- 可选：协议统一转换
	local processed = nodes
	if options.proto then
		local out = {}
		for _, n in ipairs(nodes) do
			local cn = M.convert_protocol(n, options.proto)
			if cn then
				out[#out + 1] = cn
			end
		end
		processed = out
	end

	-- 可选：流水线处理
	if options.pipeline then
		processed = M.process_pipeline(processed, options.pipeline)
	end

	local fmt = (target_format or "clash"):lower()
	local content, err = output.generate(processed, fmt)
	return content, err
end

-- 多步骤流水线：filter -> rename -> group -> convert
function M.process_pipeline(nodes, pipeline)
	if type(nodes) ~= "table" then
		return nodes
	end
	pipeline = pipeline or {}

	-- 深浅拷贝
	local current = {}
	for _, n in ipairs(nodes) do
		local cp = {}
		for k, v in pairs(n) do cp[k] = v end
		current[#current + 1] = cp
	end

	for _, step in ipairs(pipeline) do
		if type(step) ~= "table" then
			-- skip
		else
			local t = step.type
			if t == "filter" then
				current = node.filter(current, step.opts or {})
			elseif t == "rename" then
				if step.opts then
					if step.opts.prefix then
						for _, n in ipairs(current) do
							if n.name then
								n.name = step.opts.prefix .. n.name
							end
						end
					end
					if step.opts.map then
						for _, n in ipairs(current) do
							if n.name and step.opts.map[n.name] then
								n.name = step.opts.map[n.name]
							end
						end
					end
				end
			elseif t == "group" then
				if step.opts and step.opts.field then
					local field = step.opts.field
					local prefix = step.opts.prefix or "group_"
					for _, n in ipairs(current) do
						local val = n[field] or ""
						n.group = prefix .. tostring(val)
					end
				end
			elseif t == "convert" then
				if step.opts and step.opts.proto then
					local out = {}
					for _, n in ipairs(current) do
						local cn = M.convert_protocol(n, step.opts.proto)
						if cn then
							out[#out + 1] = cn
						end
					end
					current = out
				end
			end
		end
	end

	return current
end

-- 应用模板到节点（简单占位符替换）
function M.apply_template(nodes, template)
	if type(nodes) ~= "table" then
		return nodes
	end
	template = template or ""
	local out = {}
	for _, n in ipairs(nodes) do
		local cp = {}
		for k, v in pairs(n) do cp[k] = v end
		if cp.name and template ~= "" then
			local new_name = template
			new_name = new_name:gsub("{{name}}", cp.name or "")
			new_name = new_name:gsub("{{proto}}", cp.proto or "")
			new_name = new_name:gsub("{{server}}", cp.server or "")
			new_name = new_name:gsub("{{port}}", tostring(cp.port or ""))
			cp.name = new_name
		end
		out[#out + 1] = cp
	end
	return out
end

-- ---------- 模板渲染引擎 ----------

-- 协议 URL 模板常量
M.URL_TEMPLATES = {
	vmess = "vmess://{uuid}@{server}:{port}#{name}",
	vless = "vless://{uuid}@{server}:{port}#{name}",
	trojan = "trojan://{password}@{server}:{port}#{name}",
	ss = "ss://{method}:{password}@{server}:{port}#{name}",
}

-- 读取节点字段并归一化为字符串；缺失或空返回 nil
local function field_str(node, field)
	local v = node[field]
	if v == nil then return nil end
	if type(v) == "boolean" then return tostring(v) end
	local s = tostring(v)
	if s == "" then return nil end
	return s
end

-- 渲染单个 {} 表达式：
--   {field}              变量替换
--   {field|default}      缺失时取默认值
--   {upper:field}        转大写
--   {lower:field}        转小写
--   {if:field?真值:假值}  条件渲染
local function render_expr(expr, node)
	expr = expr or ""
	-- 条件渲染（需最先判断，否则被 "if:..." 与函数分支误匹配）
	local field, tv, fv = expr:match("^if:([^?]+)%?(.-):(.*)$")
	if field then
		return (field_str(node, field) ~= nil) and tv or fv
	end
	-- 函数调用
	local fn, fname = expr:match("^([%a]+):(.+)$")
	if fn == "upper" or fn == "lower" then
		local v = field_str(node, fname) or ""
		if fn == "upper" then return v:upper() else return v:lower() end
	end
	-- 默认值
	local fname2, dflt = expr:match("^([^|]+)|(.*)$")
	if fname2 then
		local v = field_str(node, fname2)
		return (v ~= nil) and v or dflt
	end
	-- 普通变量
	return field_str(node, expr) or ""
end

-- 渲染单个模板字符串到节点
function M.render_template(template, node)
	if type(template) ~= "string" then return "" end
	node = node or {}
	return (template:gsub("{([^{}]*)}", function(expr)
		return render_expr(expr, node)
	end))
end

-- 批量渲染：节点列表 -> 渲染结果数组
function M.render_url_template(nodes, template)
	local out = {}
	if type(nodes) ~= "table" then return out end
	for _, n in ipairs(nodes) do
		out[#out + 1] = M.render_template(template, n)
	end
	return out
end

return M
