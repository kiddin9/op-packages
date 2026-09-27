-- converter_template_test.lua — URL 模板渲染单元测试
-- 用法：lua5.1 tests/converter_template_test.lua

package.path = "./root/usr/share/?.lua;" .. package.path

local converter = require("substore.converter")

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

-- ---------- 基础功能测试 ----------
check("module exists", converter ~= nil)
check("render_template method exists", type(converter.render_template) == "function")
check("render_url_template method exists", type(converter.render_url_template) == "function")

-- ---------- 变量替换测试 ----------
local node1 = { name = "TestNode", server = "1.1.1.1", port = 443, proto = "vmess", uuid = "abc-123", password = "pass" }
check("render_template variable name", converter.render_template("{name}", node1) == "TestNode")
check("render_template variable server", converter.render_template("{server}", node1) == "1.1.1.1")
check("render_template variable port", converter.render_template("{port}", node1) == "443")
check("render_template variable proto", converter.render_template("{proto}", node1) == "vmess")
check("render_template variable uuid", converter.render_template("{uuid}", node1) == "abc-123")
check("render_template variable password", converter.render_template("{password}", node1) == "pass")
check("render_template multiple vars", converter.render_template("{name}@{server}:{port}", node1) == "TestNode@1.1.1.1:443")

-- ---------- 函数调用测试 ----------
check("render_template upper", converter.render_template("{upper:name}", node1) == "TESTNODE")
check("render_template lower", converter.render_template("{lower:server}", node1) == "1.1.1.1")
check("render_template upper server", converter.render_template("{upper:server}", node1) == "1.1.1.1")
check("render_template lower proto", converter.render_template("{lower:proto}", node1) == "vmess")

-- ---------- 默认值测试 ----------
check("render_template default missing", converter.render_template("{name|DefaultName}", {}) == "DefaultName")
check("render_template default present", converter.render_template("{name|DefaultName}", node1) == "TestNode")
check("render_template default empty", converter.render_template("{missing|fallback}", node1) == "fallback")

-- ---------- 条件渲染测试 ----------
check("render_template conditional true", converter.render_template("{if:proto?vmess:vless}", node1) == "vmess")
check("render_template conditional false", converter.render_template("{if:missing?yes:no}", node1) == "no")
check("render_template conditional with value", converter.render_template("{if:server?has-server:no-server}", node1) == "has-server")

-- ---------- 批量渲染测试 ----------
local nodes = {
	{ name = "Node1", server = "1.1.1.1", port = 443 },
	{ name = "Node2", server = "2.2.2.2", port = 8443 },
}
local urls = converter.render_url_template(nodes, "{name}-{server}:{port}")
check("render_url_template count", type(urls) == "table" and #urls == 2)
check("render_url_template first", urls[1] == "Node1-1.1.1.1:443")
check("render_url_template second", urls[2] == "Node2-2.2.2.2:8443")

-- ---------- 协议 URL 模板测试 ----------
local vmess_node = {
	name = "VMessTest",
	server = "1.1.1.1",
	port = 443,
	uuid = "uuid-vmess",
	security = "tls",
}
local vless_node = {
	name = "VLESS Test",
	server = "2.2.2.2",
	port = 8443,
	uuid = "uuid-vless",
}
local trojan_node = {
	name = "TrojanTest",
	server = "3.3.3.3",
	port = 443,
	password = "trojan-pass",
}
local ss_node = {
	name = "SSTest",
	server = "4.4.4.4",
	port = 8388,
	method = "aes-256-gcm",
	password = "ss-pass",
}

-- 检查模板常量存在
check("vmess template exists", converter.URL_TEMPLATES and converter.URL_TEMPLATES.vmess ~= nil)
check("vless template exists", converter.URL_TEMPLATES and converter.URL_TEMPLATES.vless ~= nil)
check("trojan template exists", converter.URL_TEMPLATES and converter.URL_TEMPLATES.trojan ~= nil)
check("ss template exists", converter.URL_TEMPLATES and converter.URL_TEMPLATES.ss ~= nil)

-- 使用模板渲染
local vmess_url = converter.render_template(converter.URL_TEMPLATES.vmess, vmess_node)
check("vmess url contains uuid", vmess_url:find("uuid-vmess", 1, true) ~= nil)
check("vmess url contains server", vmess_url:find("1.1.1.1") ~= nil)
check("vmess url contains name", vmess_url:find("VMessTest") ~= nil)

local vless_url = converter.render_template(converter.URL_TEMPLATES.vless, vless_node)
check("vless url contains uuid", vless_url:find("uuid-vless", 1, true) ~= nil)
check("vless url contains server", vless_url:find("2.2.2.2") ~= nil)

local trojan_url = converter.render_template(converter.URL_TEMPLATES.trojan, trojan_node)
check("trojan url contains password", trojan_url:find("trojan-pass", 1, true) ~= nil)
check("trojan url contains server", trojan_url:find("3.3.3.3") ~= nil)

local ss_url = converter.render_template(converter.URL_TEMPLATES.ss, ss_node)
check("ss url contains method", ss_url:find("aes-256-gcm", 1, true) ~= nil)
check("ss url contains password", ss_url:find("ss-pass", 1, true) ~= nil)

-- ---------- 结果 ----------
print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
