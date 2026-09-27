-- node_group_test.lua — 节点分组与标签测试
package.path = "./root/usr/share/?.lua;" .. package.path

local node = require("substore.node")

local passed, failed = 0, 0

local function check(name, cond)
	if cond then
		passed = passed + 1
		print("PASS " .. name)
	else
		failed = failed + 1
		print("FAIL " .. name)
	end
end

local function eq(a, b)
	if type(a) ~= type(b) then return false end
	if type(a) == "table" then
		for k, v in pairs(a) do if not eq(v, b[k]) then return false end end
		for k in pairs(b) do if a[k] == nil then return false end end
		return true
	end
	return a == b
end

-- 测试数据
local nodes = {
	{ name = "HK VMESS 1", proto = "vmess", server = "1.1.1.1", port = 443 },
	{ name = "HK VMESS 2", proto = "vmess", server = "1.1.1.2", port = 443 },
	{ name = "US TROJAN 1", proto = "trojan", server = "2.2.2.2", port = 443 },
	{ name = "JP SS 1", proto = "shadowsocks", server = "3.3.3.3", port = 8388 },
	{ name = "HK TROJAN 2", proto = "trojan", server = "1.1.1.1", port = 443 },
}

-- ---------- group_by ----------
check("group_by proto exists", type(node.group_by) == "function")
if type(node.group_by) == "function" then
	local groups = node.group_by(nodes, "proto")
	check("group_by proto count", groups ~= nil and groups.vmess ~= nil and #groups.vmess == 2)
	check("group_by proto trojan", groups ~= nil and groups.trojan ~= nil and #groups.trojan == 2)
	check("group_by proto shadowsocks", groups ~= nil and groups.shadowsocks ~= nil and #groups.shadowsocks == 1)

	local groups_server = node.group_by(nodes, "server")
	check("group_by server 1.1.1.1", groups_server ~= nil and groups_server["1.1.1.1"] ~= nil and #groups_server["1.1.1.1"] == 2)
	check("group_by server 2.2.2.2", groups_server ~= nil and groups_server["2.2.2.2"] ~= nil and #groups_server["2.2.2.2"] == 1)
end

-- ---------- add_group ----------
check("add_group exists", type(node.add_group) == "function")
if type(node.add_group) == "function" then
	local nodes_copy = {}
	for _, n in ipairs(nodes) do
		nodes_copy[#nodes_copy + 1] = { name = n.name, proto = n.proto, server = n.server, port = n.port }
	end

	-- 按协议分组
	local rules_proto = {
		{ field = "proto", prefix = "proto_" }
	}
	local result = node.add_group(nodes_copy, rules_proto)
	check("add_group proto field exists", result[1].group ~= nil)
	check("add_group proto value", result[1].group == "proto_vmess")

	-- 按服务器分组
	local nodes_copy2 = {}
	for _, n in ipairs(nodes) do
		nodes_copy2[#nodes_copy2 + 1] = { name = n.name, proto = n.proto, server = n.server, port = n.port }
	end
	local rules_server = {
		{ field = "server", prefix = "server_" }
	}
	local result2 = node.add_group(nodes_copy2, rules_server)
	check("add_group server field exists", result2[1].group ~= nil)
	check("add_group server value", result2[1].group == "server_1.1.1.1")
end

-- ---------- add_tags ----------
check("add_tags exists", type(node.add_tags) == "function")
if type(node.add_tags) == "function" then
	local nodes_copy = {}
	for _, n in ipairs(nodes) do
		nodes_copy[#nodes_copy + 1] = { name = n.name, proto = n.proto, server = n.server, port = n.port }
	end

	-- 按关键词添加标签
	local rules_keyword = {
		{ type = "keyword", value = "HK", tag = "hongkong" }
	}
	local result = node.add_tags(nodes_copy, rules_keyword)
	check("add_tags keyword exists", result[1].tags ~= nil and type(result[1].tags) == "table")
	check("add_tags keyword value", result[1].tags ~= nil and result[1].tags.hongkong == true)
	check("add_tags keyword not match", result[3].tags ~= nil and result[3].tags.hongkong == nil)
end

-- ---------- filter_by_group ----------
check("filter_by_group exists", type(node.filter_by_group) == "function")
if type(node.filter_by_group) == "function" then
	local nodes_copy = {}
	for _, n in ipairs(nodes) do
		nodes_copy[#nodes_copy + 1] = { name = n.name, proto = n.proto, server = n.server, port = n.port, group = (n.proto == "vmess") and "proto_vmess" or "other" }
	end

	local filtered = node.filter_by_group(nodes_copy, "proto_vmess")
	check("filter_by_group count", filtered ~= nil and #filtered == 2)

	local filtered_none = node.filter_by_group(nodes_copy, "proto_trojan")
	check("filter_by_group none", filtered_none ~= nil and #filtered_none == 0)
end

-- ---------- filter_by_tags ----------
check("filter_by_tags exists", type(node.filter_by_tags) == "function")
if type(node.filter_by_tags) == "function" then
	local nodes_copy = {}
	for _, n in ipairs(nodes) do
		nodes_copy[#nodes_copy + 1] = { name = n.name, proto = n.proto, server = n.server, port = n.port, tags = {} }
	end
	nodes_copy[1].tags.hongkong = true
	nodes_copy[2].tags.hongkong = true
	nodes_copy[3].tags.usa = true

	local filtered = node.filter_by_tags(nodes_copy, { "hongkong" })
	check("filter_by_tags count", filtered ~= nil and #filtered == 2)

	local filtered_none = node.filter_by_tags(nodes_copy, { "japan" })
	check("filter_by_tags none", filtered_none ~= nil and #filtered_none == 0)
end

-- 结果
print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
