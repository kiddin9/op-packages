-- node_converter_test.lua — 协议转换单元测试
-- 用法：lua5.1 tests/node_converter_test.lua

package.path = "./root/usr/share/?.lua;" .. package.path

local converter = require("substore.node_converter")

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

-- ---------- 基本功能测试 ----------
check("module exists", converter ~= nil)
check("convert method exists", type(converter.convert) == "function")
check("get_field_mapping method exists", type(converter.get_field_mapping) == "function")

-- ---------- vmess 转换测试 ----------
local vmess_node = {
	proto = "vmess",
	server = "1.1.1.1",
	port = 443,
	uuid = "test-uuid-vmess",
	alterId = 0,
	cipher = "auto",
	network = "ws",
}

local vless_converted = converter.convert(vmess_node, "vless")
check("vmess to vless proto", vless_converted and vless_converted.proto == "vless")
check("vmess to vless uuid", vless_converted and vless_converted.uuid == "test-uuid-vmess")
check("vmess to vless server", vless_converted and vless_converted.server == "1.1.1.1")
check("vmess to vless port", vless_converted and vless_converted.port == 443)

local trojan_converted = converter.convert(vmess_node, "trojan")
check("vmess to trojan proto", trojan_converted and trojan_converted.proto == "trojan")
check("vmess to trojan password", trojan_converted and trojan_converted.password == "test-uuid-vmess")
check("vmess to trojan server", trojan_converted and trojan_converted.server == "1.1.1.1")

local ss_converted = converter.convert(vmess_node, "shadowsocks")
check("vmess to ss proto", ss_converted and ss_converted.proto == "shadowsocks")
check("vmess to ss password", ss_converted and ss_converted.password == "test-uuid-vmess")

-- ---------- vless 转换测试 ----------
local vless_node = {
	proto = "vless",
	server = "2.2.2.2",
	port = 8443,
	uuid = "test-uuid-vless",
	security = "tls",
}

local vmess_from_vless = converter.convert(vless_node, "vmess")
check("vless to vmess proto", vmess_from_vless and vmess_from_vless.proto == "vmess")
check("vless to vmess uuid", vmess_from_vless and vmess_from_vless.uuid == "test-uuid-vless")

local trojan_from_vless = converter.convert(vless_node, "trojan")
check("vless to trojan proto", trojan_from_vless and trojan_from_vless.proto == "trojan")
check("vless to trojan password", trojan_from_vless and trojan_from_vless.password == "test-uuid-vless")

-- ---------- trojan 转换测试 ----------
local trojan_node = {
	proto = "trojan",
	server = "3.3.3.3",
	port = 443,
	password = "trojan-pass",
	sni = "example.com",
}

local vmess_from_trojan = converter.convert(trojan_node, "vmess")
check("trojan to vmess proto", vmess_from_trojan and vmess_from_trojan.proto == "vmess")
check("trojan to vmess uuid", vmess_from_trojan and vmess_from_trojan.uuid == "trojan-pass")

local vless_from_trojan = converter.convert(trojan_node, "vless")
check("trojan to vless proto", vless_from_trojan and vless_from_trojan.proto == "vless")
check("trojan to vless uuid", vless_from_trojan and vless_from_trojan.uuid == "trojan-pass")

-- ---------- shadowsocks 转换测试 ----------
local ss_node = {
	proto = "shadowsocks",
	server = "4.4.4.4",
	port = 8388,
	method = "aes-256-gcm",
	password = "ss-pass",
}

local vmess_from_ss = converter.convert(ss_node, "vmess")
check("ss to vmess proto", vmess_from_ss and vmess_from_ss.proto == "vmess")
check("ss to vmess uuid", vmess_from_ss and vmess_from_ss.uuid == "ss-pass")

local vless_from_ss = converter.convert(ss_node, "vless")
check("ss to vless proto", vless_from_ss and vless_from_ss.proto == "vless")
check("ss to vless uuid", vless_from_ss and vless_from_ss.uuid == "ss-pass")

local trojan_from_ss = converter.convert(ss_node, "trojan")
check("ss to trojan proto", trojan_from_ss and trojan_from_ss.proto == "trojan")
check("ss to trojan password", trojan_from_ss and trojan_from_ss.password == "ss-pass")

-- ---------- 字段映射测试 ----------
local mapping = converter.get_field_mapping("vmess", "vless")
check("vmess to vless mapping exists", mapping ~= nil)
check("vmess to vless has uuid", mapping and mapping.uuid == "uuid")
check("vmess to vless has server", mapping and mapping.server == "server")

local mapping2 = converter.get_field_mapping("vless", "trojan")
check("vless to trojan mapping exists", mapping2 ~= nil)
check("vless to trojan uuid to password", mapping2 and mapping2.uuid == "password")

-- ---------- 不支持的转换 ----------
local result = converter.convert(vmess_node, "unsupported_proto")
check("unsupported target returns nil", result == nil)

-- ---------- 字段兼容性测试 ----------
local vmess_with_net = {
	proto = "vmess",
	server = "5.5.5.5",
	port = 443,
	uuid = "uuid-1",
	network = "tcp",
	security = "tls",
}
local vless_with_net = converter.convert(vmess_with_net, "vless")
check("network preserved", vless_with_net and vless_with_net.network == "tcp")
check("security preserved", vless_with_net and vless_with_net.security == "tls")

-- ---------- hysteria2 测试 ----------
local hysteria_node = {
	proto = "hysteria2",
	server = "6.6.6.6",
	port = 443,
	password = "hysteria-pass",
}
local singbox_from_hysteria = converter.convert(hysteria_node, "sing-box")
check("hysteria2 to sing-box proto", singbox_from_hysteria and singbox_from_hysteria.proto == "sing-box")

-- ---------- tuic 测试 ----------
local tuic_node = {
	proto = "tuic",
	server = "7.7.7.7",
	port = 443,
	uuid = "tuic-uuid",
	password = "tuic-pass",
}
local singbox_from_tuic = converter.convert(tuic_node, "sing-box")
check("tuic to sing-box proto", singbox_from_tuic and singbox_from_tuic.proto == "sing-box")

-- ---------- wireguard 测试 ----------
local wg_node = {
	proto = "wireguard",
	server = "8.8.8.8",
	port = 51820,
	private_key = "wg-private",
	public_key = "wg-public",
}
local singbox_from_wg = converter.convert(wg_node, "sing-box")
check("wireguard to sing-box proto", singbox_from_wg and singbox_from_wg.proto == "sing-box")

-- ---------- 结果 ----------
print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
