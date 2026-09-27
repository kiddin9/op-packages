-- 简单的 YAML 解析逻辑验证（无依赖）
-- 验证解析器的核心逻辑

-- 模拟 util.trim
local function trim(s)
	return s:match("^%s*(.-)%s*$")
end

-- 模拟 split_lines
local function split_lines(content)
	local out = {}
	for line in content:gmatch("[^\r\n]+") do
		out[#out + 1] = line
	end
	return out
end

-- 测试 YAML 解析逻辑
local function test_yaml_parsing()
	local yaml_sample = [[
proxies:
  - name: TestVMess
    type: vmess
    server: 1.1.1.1
    port: 443
    uuid: abc-123
  - name: TestSS
    type: ss
    server: 2.2.2.2
    port: 8388
    cipher: aes-256-gcm
    password: pass123
]]

	local lines = split_lines(yaml_sample)
	local raw_nodes = {}
	local current_node = nil
	local in_proxies = false
	local proxies_indent = 0

	for i, line in ipairs(lines) do
		local trimmed = trim(line)
		if trimmed == "" or trimmed:sub(1, 1) == "#" then
		elseif trimmed:match("^proxies:%s*$") or trimmed:match("^outbounds:%s*$") then
			in_proxies = true
			proxies_indent = line:match("^%s*") and #line:match("^%s*") or 0
			current_node = nil
		elseif in_proxies then
			local list_match = line:match("^%s*%-%s*(.*)$")
			if list_match then
				if current_node then
					raw_nodes[#raw_nodes + 1] = current_node
				end
				current_node = {}
				if list_match:match("^([^:]+):%s*(.+)$") then
					local k, v = list_match:match("^([^:]+):%s*(.+)$")
					current_node[k] = trim(v)
				end
			else
				local indent = line:match("^%s*") and #line:match("^%s*") or 0
				if current_node and indent > proxies_indent then
					local k, v = trimmed:match("^([^:]+):%s*(.+)$")
					if k then
						k = trim(k)
						v = trim(v)
						v = v:gsub('^["\'](.*)["\']$', '%1')
						current_node[k] = v
					end
				else
					if current_node then
						raw_nodes[#raw_nodes + 1] = current_node
						current_node = nil
					end
					in_proxies = false
				end
			end
		end
	end

	if current_node then
		raw_nodes[#raw_nodes + 1] = current_node
	end

	print("Parsed nodes: " .. #raw_nodes)
	for i, n in ipairs(raw_nodes) do
		print("Node " .. i .. ":")
		for k, v in pairs(n) do
			print("  " .. k .. " = " .. tostring(v))
		end
	end

	-- 验证
	assert(#raw_nodes == 2, "Should have 2 nodes")
	assert(raw_nodes[1].name == "TestVMess", "First node name")
	assert(raw_nodes[1].type == "vmess", "First node type")
	assert(raw_nodes[1].server == "1.1.1.1", "First node server")
	assert(raw_nodes[1].port == "443", "First node port")
	assert(raw_nodes[1].uuid == "abc-123", "First node uuid")

	assert(raw_nodes[2].name == "TestSS", "Second node name")
	assert(raw_nodes[2].type == "ss", "Second node type")
	assert(raw_nodes[2].server == "2.2.2.2", "Second node server")
	assert(raw_nodes[2].port == "8388", "Second node port")
	assert(raw_nodes[2].cipher == "aes-256-gcm", "Second node cipher")
	assert(raw_nodes[2].password == "pass123", "Second node password")

	print("All tests passed!")
end

test_yaml_parsing()
