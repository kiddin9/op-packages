-- output_new_formats_test.lua — 新增输出格式（Clash 原版 / wg-quick .conf）与格式注册表一致性
-- 用法：lua5.1 tests/output_new_formats_test.lua

package.path = "./root/usr/share/?.lua;" .. package.path

local output = require("substore.output")
local parser = require("substore.parser")
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

-- ---------- 格式注册表一致性（防止只加了一半） ----------
-- 每个 UI 选项都必须能被 generate 解析、并有 content-type 与扩展名
local all_resolve = true
for _, fo in ipairs(output.FORMAT_OPTIONS) do
	local v = fo[1]
	local norm = output.FORMAT_ALIASES[v]
	if not norm then
		all_resolve = false
		print("       no alias:", v)
	end
	if not output.content_type_for(v) then
		all_resolve = false
		print("       no content-type:", v)
	end
	if not output.extension_for(v) then
		all_resolve = false
		print("       no extension:", v)
	end
end
check("every FORMAT_OPTIONS entry resolves", all_resolve)
check("FORMAT_OPTIONS has 15 entries", #output.FORMAT_OPTIONS == 15)

-- 每个规范名都必须有分发分支。
-- 用空节点表探测：未注册的格式会返回 "unsupported format: ..."，
-- 而注册过的格式可能返回空串或业务错误（如 wgconf 无 WireGuard 节点），都算已分发。
local dispatch_ok = true
for _, fo in ipairs(output.FORMAT_OPTIONS) do
	local content, err = output.generate({}, fo[1])
	if type(content) ~= "string" and tostring(err):find("unsupported format", 1, true) then
		dispatch_ok = false
		print("       dispatch fail:", fo[1], tostring(err))
	end
end
check("every FORMAT_OPTIONS entry dispatches", dispatch_ok)

-- 旧别名仍可用
check("alias mihomo -> clashmeta", output.FORMAT_ALIASES["mihomo"] == "clashmeta")
check("alias yaml -> clashmeta", output.FORMAT_ALIASES["yaml"] == "clashmeta")
check("alias clash -> clash (原版)", output.FORMAT_ALIASES["clash"] == "clash")
check("alias amneziawg -> wgconf", output.FORMAT_ALIASES["amneziawg"] == "wgconf")
check("alias wireguard -> wgconf", output.FORMAT_ALIASES["wireguard"] == "wgconf")

-- 默认格式仍是 Clash.Meta（未指定 target 时行为不变）
check("default content-type is clashmeta", output.content_type_for(nil) == "text/plain; charset=utf-8")
local def = output.generate({ { proto = "vless", name = "D", server = "1.1.1.1", port = 443, uuid = "u" } })
check("default keeps vless (clashmeta)", def:find("type: vless") ~= nil)

-- 死代码已移除
check("to_clash_yaml removed", output.to_clash_yaml == nil)
check("to_json removed", output.to_json == nil)
check("to_base64 removed", output.to_base64 == nil)

-- ---------- Clash 原版：过滤原版不支持的协议 ----------
local mixed = {
	{ proto = "vmess", name = "V", server = "1.1.1.1", port = 443, uuid = "u1", net = "tcp" },
	{ proto = "shadowsocks", name = "S", server = "2.2.2.2", port = 8388, method = "aes-256-gcm", password = "p" },
	{ proto = "trojan", name = "T", server = "3.3.3.3", port = 443, password = "p" },
	{ proto = "ssr", name = "R", server = "4.4.4.4", port = 443, method = "aes-128-cfb", password = "p", protocol = "origin", obfs = "plain" },
	{ proto = "vless", name = "VL", server = "5.5.5.5", port = 443, uuid = "u2" },
	{ proto = "hysteria2", name = "H2", server = "6.6.6.6", port = 443, password = "p" },
	{ proto = "tuic", name = "TU", server = "7.7.7.7", port = 443, uuid = "u3", password = "p" },
	{ proto = "wireguard", name = "WG", server = "8.8.8.8", port = 51820, ["private-key"] = "K", ["public-key"] = "P", ip = "10.0.0.1/32" },
}

local cl = output.generate(mixed, "clash")
check("clash legacy keeps vmess", cl:find("- name: V\n") ~= nil)
check("clash legacy keeps shadowsocks", cl:find("- name: S\n") ~= nil)
check("clash legacy keeps trojan", cl:find("- name: T\n") ~= nil)
check("clash legacy keeps ssr", cl:find("- name: R\n") ~= nil)
check("clash legacy drops vless", cl:find("- name: VL\n") == nil)
check("clash legacy drops hysteria2", cl:find("- name: H2\n") == nil)
check("clash legacy drops tuic", cl:find("- name: TU\n") == nil)
check("clash legacy drops wireguard", cl:find("- name: WG\n") == nil)
check("clash legacy ss type is ss", cl:find("type: ss") ~= nil)

-- Clash.Meta 保留全部
local cm = output.generate(mixed, "clashmeta")
check("clashmeta keeps vless", cm:find("- name: VL\n") ~= nil)
check("clashmeta keeps wireguard", cm:find("- name: WG\n") ~= nil)

-- ---------- wg-quick / AmneziaWG .conf 输出 ----------
local wg_nodes = {
	{ proto = "vmess", name = "NOTWG", server = "1.1.1.1", port = 443, uuid = "u" },
	{ proto = "wireguard", name = "WG HK 01", server = "wg.example.com", port = 51820,
		["private-key"] = "PRIV", ["public-key"] = "PUB", ["pre-shared-key"] = "PSK",
		ip = "10.7.0.2/32", ipv6 = "fd00:7::2/128",
		["allowed-ips"] = { "0.0.0.0/0", "::/0" }, ["persistent-keepalive"] = 25,
		["listen-port"] = 51820, mtu = 1420, dns = { "1.1.1.1", "8.8.8.8" },
		["amnezia-wg-option"] = { jc = 5, jmin = 50, jmax = 1000, s1 = 86, s2 = 574, h1 = 1234567 } },
}

local wc = output.generate(wg_nodes, "wgconf")
check("wgconf has Interface", wc:find("%[Interface%]") ~= nil)
check("wgconf has Peer", wc:find("%[Peer%]") ~= nil)
check("wgconf drops non-wireguard", wc:find("NOTWG") == nil)
check("wgconf comment header", wc:find("# WG HK 01") ~= nil)
check("wgconf PrivateKey", wc:find("PrivateKey = PRIV") ~= nil)
check("wgconf Address joined", wc:find("Address = 10%.7%.0%.2/32, fd00:7::2/128") ~= nil)
check("wgconf ListenPort", wc:find("ListenPort = 51820") ~= nil)
check("wgconf MTU", wc:find("MTU = 1420") ~= nil)
check("wgconf DNS joined", wc:find("DNS = 1%.1%.1%.1, 8%.8%.8%.8") ~= nil)
check("wgconf PublicKey", wc:find("PublicKey = PUB") ~= nil)
check("wgconf PresharedKey", wc:find("PresharedKey = PSK") ~= nil)
check("wgconf AllowedIPs joined", wc:find("AllowedIPs = 0%.0%.0%.0/0, ::/0") ~= nil)
check("wgconf Endpoint", wc:find("Endpoint = wg%.example%.com:51820") ~= nil)
check("wgconf PersistentKeepalive", wc:find("PersistentKeepalive = 25") ~= nil)

-- AmneziaWG 参数：.conf 键名首字母大写，且排序稳定
check("wgconf awg Jc", wc:find("Jc = 5") ~= nil)
check("wgconf awg Jmin", wc:find("Jmin = 50") ~= nil)
check("wgconf awg Jmax", wc:find("Jmax = 1000") ~= nil)
check("wgconf awg S1", wc:find("S1 = 86") ~= nil)
check("wgconf awg H1", wc:find("H1 = 1234567") ~= nil)
local i_h1, i_jc, i_s1 = wc:find("\nH1 = "), wc:find("\nJc = "), wc:find("\nS1 = ")
check("wgconf awg sorted", i_h1 and i_jc and i_s1 and i_h1 < i_jc and i_jc < i_s1)
check("wgconf deterministic", output.generate(wg_nodes, "wgconf") == wc)

-- 无 wireguard 节点时明确报错（而非返回空文件）
local none, nerr = output.generate({ { proto = "vmess", name = "x", server = "1.1.1.1", port = 1 } }, "wgconf")
check("wgconf errors when no wireguard", none == nil and type(nerr) == "string" and nerr:find("WireGuard") ~= nil)

-- IPv6 Endpoint 需加方括号
local v6 = output.generate({ { proto = "wireguard", name = "v6", server = "2001:db8::1", port = 51821, ["private-key"] = "K", ["public-key"] = "P", ip = "10.9.0.2/32" } }, "wgconf")
check("wgconf ipv6 endpoint bracketed", v6:find("Endpoint = %[2001:db8::1%]:51821") ~= nil)

-- ---------- 往返：wgconf 导出 → 重新导入 ----------
local rt = parser.parse(wc)
check("roundtrip parses", rt ~= nil and #rt.nodes == 1)
check("roundtrip format", rt and rt.format == "wireguard-conf")

local r = rt and rt.nodes[1] or {}
check("roundtrip proto", r.proto == "wireguard")
check("roundtrip server", r.server == "wg.example.com")
check("roundtrip port", r.port == 51820)
check("roundtrip private-key", r["private-key"] == "PRIV")
check("roundtrip public-key", r["public-key"] == "PUB")
check("roundtrip pre-shared-key", r["pre-shared-key"] == "PSK")
check("roundtrip ip", r.ip == "10.7.0.2/32")
check("roundtrip ipv6", r.ipv6 == "fd00:7::2/128")
check("roundtrip allowed-ips", type(r["allowed-ips"]) == "table" and #r["allowed-ips"] == 2 and r["allowed-ips"][2] == "::/0")
check("roundtrip persistent-keepalive", r["persistent-keepalive"] == 25)
check("roundtrip listen-port", r["listen-port"] == 51820)
check("roundtrip mtu", r.mtu == 1420)
check("roundtrip dns", type(r.dns) == "table" and #r.dns == 2)
local ro = r["amnezia-wg-option"]
check("roundtrip awg jc", ro and ro.jc == 5)
check("roundtrip awg h1", ro and ro.h1 == 1234567)
check("roundtrip awg s1", ro and ro.s1 == 86)

-- 已知有损项：reserved 不在 wg-quick 标准键内，导出时不写出
check("roundtrip reserved dropped (documented)", r.reserved == nil)

-- ---------- 结果 ----------
print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
