-- converter_protocol_test.lua — 协议转换单元测试
-- 用法：lua5.1 tests/converter_protocol_test.lua

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

local function eq(a, b)
	if type(a) ~= type(b) then return false end
	if type(a) == "table" then
		for k, v in pairs(a) do if not eq(v, b[k]) then return false end end
		for k in pairs(b) do if a[k] == nil then return false end end
		return true
	end
	return a == b
end

-- ---------- 基础功能测试 ----------
check("module exists", converter ~= nil)
check("convert_protocol method exists", type(converter.convert_protocol) == "function")

-- ---------- vmess 转换测试 ----------
local vmess_node = {
	proto = "vmess",
	server = "1.1.1.1",
	port = 443,
	uuid = "test-uuid-vmess",
	alterId = 0,
	cipher = "auto",
	network = "ws",
	security = "tls",
	sni = "example.com",
	path = "/ws",
	host = "example.com",
}

-- vmess → vless
local vless_converted = converter.convert_protocol(vmess_node, "vless")
check("vmess to vless proto", vless_converted and vless_converted.proto == "vless")
check("vmess to vless uuid", vless_converted and vless_converted.uuid == "test-uuid-vmess")
check("vmess to vless server", vless_converted and vless_converted.server == "1.1.1.1")
check("vmess to vless port", vless_converted and vless_converted.port == 443)
check("vmess to vless network", vless_converted and vless_converted.network == "ws")
check("vmess to vless security", vless_converted and vless_converted.security == "tls")
check("vmess to vless sni", vless_converted and vless_converted.sni == "example.com")
check("vmess to vless path", vless_converted and vless_converted.path == "/ws")
check("vmess to vless host", vless_converted and vless_converted.host == "example.com")
check("vmess to vless no alterId", vless_converted and vless_converted.alterId == nil)
check("vmess to vless no cipher", vless_converted and vless_converted.cipher == nil)

-- vmess → trojan
local trojan_converted = converter.convert_protocol(vmess_node, "trojan")
check("vmess to trojan proto", trojan_converted and trojan_converted.proto == "trojan")
check("vmess to trojan password", trojan_converted and trojan_converted.password == "test-uuid-vmess")
check("vmess to trojan server", trojan_converted and trojan_converted.server == "1.1.1.1")
check("vmess to trojan network", trojan_converted and trojan_converted.network == "ws")

-- vmess → shadowsocks (不支持)
local ss_converted = converter.convert_protocol(vmess_node, "shadowsocks")
check("vmess to ss unsupported", ss_converted == nil)

-- ---------- vless 转换测试 ----------
local vless_node = {
	proto = "vless",
	server = "2.2.2.2",
	port = 8443,
	uuid = "test-uuid-vless",
	security = "tls",
	sni = "vless.example.com",
	network = "grpc",
}

-- vless → vmess
local vmess_from_vless = converter.convert_protocol(vless_node, "vmess")
check("vless to vmess proto", vmess_from_vless and vmess_from_vless.proto == "vmess")
check("vless to vmess uuid", vmess_from_vless and vmess_from_vless.uuid == "test-uuid-vless")
check("vless to vmess server", vmess_from_vless and vmess_from_vless.server == "2.2.2.2")
check("vless to vmess network", vmess_from_vless and vmess_from_vless.network == "grpc")

-- vless → trojan
local trojan_from_vless = converter.convert_protocol(vless_node, "trojan")
check("vless to trojan proto", trojan_from_vless and trojan_from_vless.proto == "trojan")
check("vless to trojan password", trojan_from_vless and trojan_from_vless.password == "test-uuid-vless")
check("vless to trojan sni", trojan_from_vless and trojan_from_vless.sni == "vless.example.com")

-- ---------- trojan 转换测试 ----------
local trojan_node = {
	proto = "trojan",
	server = "3.3.3.3",
	port = 443,
	password = "trojan-pass",
	sni = "example.com",
	network = "tcp",
}

-- trojan → vmess (password → uuid 生成)
local vmess_from_trojan = converter.convert_protocol(trojan_node, "vmess")
check("trojan to vmess proto", vmess_from_trojan and vmess_from_trojan.proto == "vmess")
check("trojan to vmess uuid exists", vmess_from_trojan and vmess_from_trojan.uuid ~= nil)
check("trojan to vmess uuid not password", vmess_from_trojan and vmess_from_trojan.uuid ~= "trojan-pass")
check("trojan to vmess server", vmess_from_trojan and vmess_from_trojan.server == "3.3.3.3")

-- trojan → vless
local vless_from_trojan = converter.convert_protocol(trojan_node, "vless")
check("trojan to vless proto", vless_from_trojan and vless_from_trojan.proto == "vless")
check("trojan to vless uuid exists", vless_from_trojan and vless_from_trojan.uuid ~= nil)
check("trojan to vless sni", vless_from_trojan and vless_from_trojan.sni == "example.com")

-- ---------- shadowsocks 转换测试 (不支持) ----------
local ss_node = {
	proto = "shadowsocks",
	server = "4.4.4.4",
	port = 8388,
	method = "aes-256-gcm",
	password = "ss-pass",
}

local vmess_from_ss = converter.convert_protocol(ss_node, "vmess")
check("ss to vmess unsupported", vmess_from_ss == nil)

local vless_from_ss = converter.convert_protocol(ss_node, "vless")
check("ss to vless unsupported", vless_from_ss == nil)

-- ---------- 特殊字段转换测试 ----------
local vmess_with_special = {
	proto = "vmess",
	server = "5.5.5.5",
	port = 443,
	uuid = "uuid-special",
	network = "h2",
	security = "reality",
	sni = "sni.example.com",
	alpn = "h2,http/1.1",
	fp = "chrome",
	headerType = "none",
}

local vless_special = converter.convert_protocol(vmess_with_special, "vless")
check("network h2 preserved", vless_special and vless_special.network == "h2")
check("security reality preserved", vless_special and vless_special.security == "reality")
check("sni preserved", vless_special and vless_special.sni == "sni.example.com")
check("alpn preserved", vless_special and vless_special.alpn == "h2,http/1.1")
check("fp preserved", vless_special and vless_special.fp == "chrome")

-- ---------- 字段缺失处理测试 ----------
local vmess_minimal = {
	proto = "vmess",
	server = "6.6.6.6",
	port = 443,
	uuid = "uuid-minimal",
}

local vless_minimal = converter.convert_protocol(vmess_minimal, "vless")
check("minimal vmess to vless works", vless_minimal ~= nil)
check("minimal server preserved", vless_minimal and vless_minimal.server == "6.6.6.6")
check("minimal uuid preserved", vless_minimal and vless_minimal.uuid == "uuid-minimal")

-- ---------- 不支持的转换 ----------
local result = converter.convert_protocol(vmess_node, "unsupported_proto")
check("unsupported target returns nil", result == nil)

-- ---------- 结果 ----------
print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
