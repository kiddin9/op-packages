-- core_link_test.lua — 订阅链接生成（core.generate_link）单元测试
-- 用法：lua5.1 tests/core_link_test.lua

package.path = "./root/usr/share/?.lua;" .. package.path

local core = require("substore.core")
local util = require("substore.util")

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

-- 重定向数据目录到临时目录，避免污染系统
local tmp = os.tmpname() .. "_substore"
os.execute("mkdir -p " .. string.format("%q", tmp .. "/nodes"))
core.DATA_DIR = tmp
core.LIST_FILE = tmp .. "/subscriptions.json"
core.NODES_DIR = tmp .. "/nodes"

check("module exists", core ~= nil)
check("generate_link exists", type(core.generate_link) == "function")
check("ensure_token exists", type(core.ensure_token) == "function")

-- 创建订阅并写入节点
local id, aerr = core.add("测试订阅", "http://example.com/sub")
check("add subscription", id ~= nil, aerr or "")

local token = core.ensure_token(id)
check("token generated", type(token) == "string" and #token == 16)
check("token idempotent", core.ensure_token(id) == token)

local nodes = {
	{ proto = "vmess", name = "NodeA", server = "1.1.1.1", port = 443, uuid = "u1", net = "tcp" },
	{ proto = "shadowsocks", name = "NodeB", server = "2.2.2.2", port = 8388, method = "aes-256-gcm", password = "p1" },
}
check("write nodes", core.write_nodes(id, nodes) == true)

-- 各格式生成
local ok = true
for _, target in ipairs({ "ClashMeta", "singbox", "v2ray", "Surge", "QX", "Shadowrocket", "V2RayURI", "Plain", "Stash", "Loon", "Egern", "Surfboard", "SurgeMac" }) do
	local content, ct, filename, err = core.generate_link(token, target)
	if type(content) == "string" and content ~= "" and ct and filename then
		-- ok
	else
		ok = false
		print("       fail:", target, tostring(err))
	end
end
check("all 13 targets generate", ok)

local yaml, ct, filename = core.generate_link(token, "ClashMeta")
check("clashmeta has proxies", yaml and yaml:find("proxies:") ~= nil)
check("clashmeta content-type", ct == "text/plain; charset=utf-8")
check("clashmeta filename .yaml", filename and filename:match("%.yaml$") ~= nil)

local sb = core.generate_link(token, "singbox")
check("singbox is json", sb and sb:sub(1, 1) == "{")

-- 错误 token
local bad, _, _, err = core.generate_link("deadbeef", "ClashMeta")
check("bad token returns nil", bad == nil)
check("bad token has err", err ~= nil)

-- 无节点订阅
local id2 = core.add("空订阅", "http://example.com/empty")
local token2 = core.ensure_token(id2)
local empty, _, _, err2 = core.generate_link(token2, "ClashMeta")
check("empty nodes returns nil", empty == nil)
check("empty nodes err", err2 ~= nil)

-- 清理
os.execute("rm -rf " .. string.format("%q", tmp))

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)