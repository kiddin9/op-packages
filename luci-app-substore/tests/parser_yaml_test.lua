-- parser_yaml_test.lua — YAML 解析单元测试
-- 用法：lua5.1 tests/parser_yaml_test.lua

package.path = "./root/usr/share/?.lua;" .. package.path

local parser = require("substore.parser")

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

-- ---------- YAML 检测 ----------
local yaml_clash = [[
proxies:
  - name: TestVMess
    type: vmess
    server: 1.1.1.1
    port: 443
    uuid: abc-123
    alterId: 0
    cipher: auto
]]

check("detect yaml proxies", parser.detect(yaml_clash) == "yaml")

local yaml_outbounds = [[
outbounds:
  - tag: direct
    type: http
]]

check("detect yaml outbounds", parser.detect(yaml_outbounds) == "yaml")

-- ---------- YAML 解析 ----------
local yaml_sample = [[
proxies:
  - name: TestVMess
    type: vmess
    server: 1.1.1.1
    port: 443
    uuid: abc-123
    alterId: 0
    cipher: auto
    network: ws
    ws-opts:
      path: /ws
  - name: TestSS
    type: ss
    server: 2.2.2.2
    port: 8388
    cipher: aes-256-gcm
    password: pass123
  - name: TestTrojan
    type: trojan
    server: 3.3.3.3
    port: 443
    password: trojan-pass
    sni: example.com
]]

local result = parser.parse(yaml_sample)
check("parse yaml result exists", result ~= nil)
check("parse yaml format", result and result.format == "yaml")
check("parse yaml node count", result and #result.nodes == 3)

if result and #result.nodes >= 1 then
	local n1 = result.nodes[1]
	check("yaml vmess name", n1.name == "TestVMess")
	check("yaml vmess proto", n1.proto == "vmess")
	check("yaml vmess server", n1.server == "1.1.1.1")
	check("yaml vmess port", n1.port == 443)
	check("yaml vmess uuid", n1.uuid == "abc-123")
	check("yaml vmess net", n1.net == "ws")
end

if result and #result.nodes >= 2 then
	local n2 = result.nodes[2]
	check("yaml ss name", n2.name == "TestSS")
	check("yaml ss proto", n2.proto == "shadowsocks")
	check("yaml ss server", n2.server == "2.2.2.2")
	check("yaml ss port", n2.port == 8388)
	check("yaml ss method", n2.method == "aes-256-gcm")
	check("yaml ss password", n2.password == "pass123")
end

if result and #result.nodes >= 3 then
	local n3 = result.nodes[3]
	check("yaml trojan name", n3.name == "TestTrojan")
	check("yaml trojan proto", n3.proto == "trojan")
	check("yaml trojan server", n3.server == "3.3.3.3")
	check("yaml trojan port", n3.port == 443)
	check("yaml trojan password", n3.password == "trojan-pass")
	check("yaml trojan sni", n3.sni == "example.com")
end

-- ---------- YAML parse_yaml 直接调用 ----------
local yaml_simple = [[
proxies:
  - name: SimpleNode
    type: vless
    server: 4.4.4.4
    port: 443
    uuid: vless-uuid
]]

local nodes = parser.parse_yaml(yaml_simple)
check("parse_yaml direct", nodes and #nodes == 1)
check("parse_yaml direct name", nodes and nodes[1].name == "SimpleNode")
check("parse_yaml direct proto", nodes and nodes[1].proto == "vless")

-- ---------- 结果 ----------
print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
