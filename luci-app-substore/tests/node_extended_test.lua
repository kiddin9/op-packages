-- node_extended_test.lua — 扩展字段单元测试
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

-- ---------- normalize ----------
local n1 = { proto = "vmess", server = "1.1.1.1", port = 443, group = "HK", tags = {"fast","vip"}, remarks = "test", template = "vmess://{uuid}@{server}:{port}", url = "https://example.com" }
node.normalize(n1)
check("normalize preserves group", n1.group == "HK")
check("normalize preserves tags", type(n1.tags) == "table" and n1.tags[1] == "fast" and n1.tags[2] == "vip")
check("normalize preserves remarks", n1.remarks == "test")
check("normalize preserves template", n1.template == "vmess://{uuid}@{server}:{port}")
check("normalize preserves url", n1.url == "https://example.com")

-- tags as string should be converted to table? Optional
local n2 = { proto = "vless", server = "2.2.2.2", port = 443, tags = "fast,vip" }
node.normalize(n2)
-- If we choose to normalize tags string to table
-- For now just check preservation
check("normalize keeps tags string", n2.tags == "fast,vip" or (type(n2.tags)=="table" and n2.tags[1]=="fast"))

-- ---------- filter ----------
local nodes = {
	{ proto = "vmess", server = "1.1.1.1", port = 443, group = "HK", tags = {"fast"} },
	{ proto = "vless", server = "2.2.2.2", port = 443, group = "JP", tags = {"slow"} },
	{ proto = "vmess", server = "3.3.3.3", port = 443, group = "HK", tags = {"fast","vip"} },
}
local f1 = node.filter(nodes, { group = "HK" })
check("filter by group count", #f1 == 2)
check("filter by group values", f1[1].group == "HK" and f1[2].group == "HK")

local f2 = node.filter(nodes, { tags = "vip" })
check("filter by tags count", #f2 == 1)
check("filter by tags value", f2[1].server == "3.3.3.3")

-- ---------- apply_rules ----------
local nodes2 = {
	{ proto = "vmess", name = "A", group = "HK" },
	{ proto = "vless", name = "B", group = "JP" },
	{ proto = "vmess", name = "C", group = "HK" },
}
local rules = { group_filter = "HK" }
local r1 = node.apply_rules(nodes2, rules)
check("apply_rules group_filter count", #r1 == 2)
check("apply_rules group_filter values", r1[1].group == "HK" and r1[2].group == "HK")

local nodes3 = {
	{ proto = "vmess", name = "A", tags = {"fast"} },
	{ proto = "vmess", name = "B", tags = {"slow"} },
}
local rules2 = { tags_include = "fast" }
local r2 = node.apply_rules(nodes3, rules2)
check("apply_rules tags_include count", #r2 == 1)
check("apply_rules tags_include value", r2[1].name == "A")

-- ---------- group_nodes ----------
local nodes4 = {
	{ name = "A", group = "HK" },
	{ name = "B", group = "JP" },
	{ name = "C", group = "HK" },
}
local groups = node.group_nodes(nodes4)
check("group_nodes HK count", groups["HK"] and #groups["HK"] == 2)
check("group_nodes JP count", groups["JP"] and #groups["JP"] == 1)

-- ---------- add_tags ----------
local nodes5 = {
	{ name = "A", tags = {"fast"} },
	{ name = "B" },
}
node.add_tags(nodes5, {"vip"})
check("add_tags existing", nodes5[1].tags and #nodes5[1].tags == 2 and nodes5[1].tags[2] == "vip")
check("add_tags new", nodes5[2].tags and #nodes5[2].tags == 1 and nodes5[2].tags[1] == "vip")

-- ---------- dedup ----------
-- 非 WireGuard：行为不变，仍按 proto+server+port
local d0 = node.dedup({
	{ proto = "vmess", server = "1.1.1.1", port = 443, uuid = "a" },
	{ proto = "vmess", server = "1.1.1.1", port = 443, uuid = "b" },
	{ proto = "vless", server = "1.1.1.1", port = 443, uuid = "c" },
})
check("dedup keeps first of identical vmess", #d0 == 2)
check("dedup treats different proto as distinct", d0[2].proto == "vless")

-- WireGuard（§32/§43）：同 server+port 但 peer 公钥不同 → 不能合并
local d1 = node.dedup({
	{ proto = "wireguard", server = "wg.example.com", port = 51820, ["public-key"] = "KEY_A" },
	{ proto = "wireguard", server = "wg.example.com", port = 51820, ["public-key"] = "KEY_B" },
})
check("wg dedup keeps different public keys", #d1 == 2)
check("wg dedup first key kept", d1[1]["public-key"] == "KEY_A")
check("wg dedup second key kept", d1[2]["public-key"] == "KEY_B")

-- WireGuard：公钥相同 → 仍应去重
local d2 = node.dedup({
	{ proto = "wireguard", server = "wg.example.com", port = 51820, ["public-key"] = "KEY_A" },
	{ proto = "wireguard", server = "wg.example.com", port = 51820, ["public-key"] = "KEY_A" },
})
check("wg dedup removes identical peer", #d2 == 1)

-- WireGuard：公钥别名（导入/历史写法）同样参与去重键
local d3 = node.dedup({
	{ proto = "wireguard", server = "wg.example.com", port = 51820, public_key = "KEY_A" },
	{ proto = "wireguard", server = "wg.example.com", port = 51820, ["peer-public-key"] = "KEY_A" },
	{ proto = "wireguard", server = "wg.example.com", port = 51820, peer_public_key = "KEY_B" },
})
check("wg dedup honours public_key aliases", #d3 == 2)

-- proto 别名 "wg"
local d4 = node.dedup({
	{ proto = "wg", server = "wg.example.com", port = 51820, ["public-key"] = "KEY_A" },
	{ proto = "wg", server = "wg.example.com", port = 51820, ["public-key"] = "KEY_B" },
})
check("wg alias proto keeps different peers", #d4 == 2)

-- 双方都没有公钥：退化为 server+port 去重（保持旧行为）
local d5 = node.dedup({
	{ proto = "wireguard", server = "wg.example.com", port = 51820 },
	{ proto = "wireguard", server = "wg.example.com", port = 51820 },
})
check("wg dedup without keys falls back to endpoint", #d5 == 1)

-- 不同端口仍是不同节点
local d6 = node.dedup({
	{ proto = "wireguard", server = "wg.example.com", port = 51820, ["public-key"] = "KEY_A" },
	{ proto = "wireguard", server = "wg.example.com", port = 51821, ["public-key"] = "KEY_A" },
})
check("wg dedup keeps different ports", #d6 == 2)

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
