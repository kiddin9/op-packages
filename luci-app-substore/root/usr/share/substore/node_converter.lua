-- node_converter.lua — 协议字段映射表（纯 Lua）
-- luci-app-substore

local M = {}

-- 协议字段映射配置
-- 格式：source_proto -> target_proto -> { source_field = target_field, ... }
M.FIELD_MAPPINGS = {
	vmess = {
		vless = {
			server = "server",
			port = "port",
			uuid = "uuid",
			network = "network",
			security = "security",
			sni = "sni",
			fingerprint = "fingerprint",
			path = "path",
			host = "host",
			name = "name",
		},
		trojan = {
			server = "server",
			port = "port",
			uuid = "password",
			network = "network",
			security = "security",
			sni = "sni",
			fingerprint = "fingerprint",
			path = "path",
			host = "host",
			name = "name",
		},
		shadowsocks = {
			server = "server",
			port = "port",
			uuid = "password",
			network = "network",
			name = "name",
		},
		["sing-box"] = {
			server = "server",
			port = "port",
			uuid = "uuid",
			network = "network",
			security = "security",
			sni = "sni",
			name = "name",
		},
		clash = {
			server = "server",
			port = "port",
			uuid = "uuid",
			network = "network",
			security = "security",
			sni = "sni",
			name = "name",
		},
	},
	vless = {
		vmess = {
			server = "server",
			port = "port",
			uuid = "uuid",
			security = "security",
			sni = "sni",
			fingerprint = "fingerprint",
			network = "network",
			path = "path",
			host = "host",
			name = "name",
		},
		trojan = {
			server = "server",
			port = "port",
			uuid = "password",
			security = "security",
			sni = "sni",
			fingerprint = "fingerprint",
			network = "network",
			path = "path",
			host = "host",
			name = "name",
		},
		shadowsocks = {
			server = "server",
			port = "port",
			uuid = "password",
			network = "network",
			name = "name",
		},
	},
	trojan = {
		vmess = {
			server = "server",
			port = "port",
			password = "uuid",
			security = "security",
			sni = "sni",
			fingerprint = "fingerprint",
			network = "network",
			path = "path",
			host = "host",
			name = "name",
		},
		vless = {
			server = "server",
			port = "port",
			password = "uuid",
			security = "security",
			sni = "sni",
			fingerprint = "fingerprint",
			network = "network",
			path = "path",
			host = "host",
			name = "name",
		},
		shadowsocks = {
			server = "server",
			port = "port",
			password = "password",
			network = "network",
			name = "name",
		},
	},
	shadowsocks = {
		vmess = {
			server = "server",
			port = "port",
			password = "uuid",
			network = "network",
			name = "name",
		},
		vless = {
			server = "server",
			port = "port",
			password = "uuid",
			network = "network",
			name = "name",
		},
		trojan = {
			server = "server",
			port = "port",
			password = "password",
			network = "network",
			name = "name",
		},
	},
	hysteria2 = {
		["sing-box"] = {
			server = "server",
			port = "port",
			password = "password",
			name = "name",
		},
		clash = {
			server = "server",
			port = "port",
			password = "password",
			name = "name",
		},
	},
	tuic = {
		["sing-box"] = {
			server = "server",
			port = "port",
			uuid = "uuid",
			password = "password",
			name = "name",
		},
		clash = {
			server = "server",
			port = "port",
			uuid = "uuid",
			password = "password",
			name = "name",
		},
	},
	wireguard = {
		["sing-box"] = {
			server = "server",
			port = "port",
			private_key = "private_key",
			public_key = "public_key",
			name = "name",
		},
		clash = {
			server = "server",
			port = "port",
			private_key = "private_key",
			public_key = "public_key",
			name = "name",
		},
	},
}

-- 目标协议默认字段
M.DEFAULTS = {
	shadowsocks = {
		method = "aes-256-gcm",
	},
}

-- 获取字段映射
function M.get_field_mapping(source_proto, target_proto)
	if not source_proto or not target_proto then
		return nil
	end
	-- 标准化协议名称
	source_proto = source_proto:lower()
	target_proto = target_proto:lower()

	-- 处理别名
	if source_proto == "ss" then source_proto = "shadowsocks" end
	if target_proto == "ss" then target_proto = "shadowsocks" end

	local source_map = M.FIELD_MAPPINGS[source_proto]
	if not source_map then
		return nil
	end

	local mapping = source_map[target_proto]
	return mapping
end

-- 转换节点协议
function M.convert(node, target_proto)
	if type(node) ~= "table" then
		return nil
	end

	local source_proto = node.proto
	if not source_proto then
		return nil
	end

	-- 标准化协议名称
	source_proto = source_proto:lower()
	target_proto = target_proto:lower()

	if source_proto == "ss" then source_proto = "shadowsocks" end
	if target_proto == "ss" then target_proto = "shadowsocks" end

	-- 如果目标协议与源协议相同，直接返回副本
	if source_proto == target_proto then
		local copy = {}
		for k, v in pairs(node) do
			copy[k] = v
		end
		return copy
	end

	local mapping = M.get_field_mapping(source_proto, target_proto)
	if not mapping then
		return nil
	end

	-- 创建新节点
	local new_node = {}

	-- 根据映射转换字段
	for source_field, target_field in pairs(mapping) do
		if node[source_field] ~= nil then
			new_node[target_field] = node[source_field]
		end
	end

	-- 设置协议
	new_node.proto = target_proto

	-- 应用默认字段
	local defaults = M.DEFAULTS[target_proto]
	if defaults then
		for k, v in pairs(defaults) do
			if new_node[k] == nil then
				new_node[k] = v
			end
		end
	end

	-- 保留 name，如果不存在则生成
	if not new_node.name and node.name then
		new_node.name = node.name
	elseif not new_node.name then
		new_node.name = (node.server or "") .. ":" .. tostring(node.port or "")
	end

	-- 保留 server 和 port（如果映射中没有）
	if not new_node.server and node.server then
		new_node.server = node.server
	end
	if not new_node.port and node.port then
		new_node.port = node.port
	end

	return new_node
end

-- 批量转换
function M.convert_batch(nodes, target_proto)
	if type(nodes) ~= "table" then
		return {}
	end

	local result = {}
	for _, node in ipairs(nodes) do
		local converted = M.convert(node, target_proto)
		if converted then
			result[#result + 1] = converted
		end
	end
	return result
end

return M
