-- output_clash_meta_test.lua — Clash.Meta / Mihomo 输出单元测试
-- 用法：lua5.1 tests/output_clash_meta_test.lua

package.path = "./root/usr/share/?.lua;" .. package.path

local output_clash_meta = require("substore.output_clash_meta")

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
check("module exists", output_clash_meta ~= nil)
check("generate method exists", type(output_clash_meta.generate) == "function")

-- ---------- 测试节点 ----------
local test_nodes = {
	{
		proto = "vmess",
		name = "TestVMess",
		server = "1.1.1.1",
		port = 443,
		uuid = "abc-123",
		net = "ws",
		security = "tls",
		sni = "example.com",
		path = "/ws",
		host = "example.com",
	},
	{
		proto = "vless",
		name = "TestVLESS",
		server = "2.2.2.2",
		port = 443,
		uuid = "vless-uuid-123",
		net = "tcp",
		security = "tls",
		sni = "example.org",
		alpn = "h2,http/1.1",
		fp = "chrome",
	},
	{
		proto = "trojan",
		name = "TestTrojan",
		server = "3.3.3.3",
		port = 443,
		password = "trojan-pass",
		sni = "example.com",
		["skip-cert-verify"] = true,
		udp = true,
	},
	{
		proto = "shadowsocks",
		name = "TestSS",
		server = "4.4.4.4",
		port = 8388,
		method = "aes-256-gcm",
		password = "ss-pass",
	},
	{
		proto = "hysteria2",
		name = "TestHysteria2",
		server = "5.5.5.5",
		port = 443,
		password = "hy2-pass",
		sni = "hy2.example.com",
		alpn = "h3",
	},
	{
		proto = "tuic",
		name = "TestTUIC",
		server = "6.6.6.6",
		port = 443,
		uuid = "tuic-uuid",
		password = "tuic-pass",
		["udp-relay-mode"] = "native",
	},
	{
		proto = "wireguard",
		name = "TestWireGuard",
		server = "7.7.7.7",
		port = 51820,
		["private-key"] = "wg-private",
		["peer-public-key"] = "wg-peer",
		["preshared-key"] = "wg-psk",
	},
	{
		proto = "socks",
		name = "TestSocks",
		server = "8.8.8.8",
		port = 1080,
		username = "user",
		password = "pass",
	},
}

-- ---------- 生成测试 ----------
local options = {
	name = "TestGroup",
	latency_test = true,
	health_check = true,
}

local yaml_output = output_clash_meta.generate(test_nodes, options)

check("generate returns string", type(yaml_output) == "string")
check("output contains proxies", yaml_output and yaml_output:find("proxies:") ~= nil)
check("output contains proxy-groups", yaml_output and yaml_output:find("proxy%-groups:") ~= nil)
check("output contains vmess node", yaml_output and yaml_output:find("TestVMess") ~= nil)
check("output contains vless node", yaml_output and yaml_output:find("TestVLESS") ~= nil)
check("output contains trojan node", yaml_output and yaml_output:find("TestTrojan") ~= nil)
check("output contains shadowsocks node", yaml_output and yaml_output:find("TestSS") ~= nil)
check("output contains hysteria2 node", yaml_output and yaml_output:find("TestHysteria2") ~= nil)
check("output contains tuic node", yaml_output and yaml_output:find("TestTUIC") ~= nil)
check("output contains wireguard node", yaml_output and yaml_output:find("TestWireGuard") ~= nil)
check("output contains socks node", yaml_output and yaml_output:find("TestSocks") ~= nil)

-- 检查协议类型映射
check("vmess type present", yaml_output and yaml_output:find("type: vmess") ~= nil)
check("vless type present", yaml_output and yaml_output:find("type: vless") ~= nil)
check("trojan type present", yaml_output and yaml_output:find("type: trojan") ~= nil)
check("ss type present", yaml_output and yaml_output:find("type: ss") ~= nil)

-- 检查特殊字段
check("skip-cert-verify present", yaml_output and yaml_output:find("skip%-cert%-verify") ~= nil)
check("udp present", yaml_output and yaml_output:find("udp:") ~= nil)
check("alpn present", yaml_output and yaml_output:find("alpn:") ~= nil)
check("fp present", yaml_output and yaml_output:find("fp:") ~= nil)

-- 检查 proxy-groups
check("SELECT group present", yaml_output and yaml_output:find("type: select") ~= nil)
check("URL-TEST group present", yaml_output and yaml_output:find("type: url%-test") ~= nil)
check("LOAD-BALANCE group present", yaml_output and yaml_output:find("type: load%-balance") ~= nil)

-- 检查选项
check("name option used", yaml_output and yaml_output:find("TestGroup") ~= nil)

-- ---------- 空节点测试 ----------
local empty_output = output_clash_meta.generate({}, {})
check("empty nodes handled", type(empty_output) == "string")

-- ---------- 结果 ----------
print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
