-- wireguard_conf_test.lua — wg-quick / AmneziaWG .conf 导入单元测试
-- 用法：lua5.1 tests/wireguard_conf_test.lua

package.path = "./root/usr/share/?.lua;" .. package.path

local parser = require("substore.parser")
local output_clash_meta = require("substore.output_clash_meta")
local output_singbox = require("substore.output_singbox")
local output_uri = require("substore.output_uri")

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

-- ---------- 标准 wg-quick .conf ----------
local WG_CONF = [[
[Interface]
PrivateKey = aGVsbG93b3JsZHByaXZhdGVrZXkwMDAwMDAwMDAwMDA=
Address = 10.7.0.2/32, fd00:7::2/128
DNS = 1.1.1.1
MTU = 1420
ListenPort = 51820

[Peer]
PublicKey = cGVlcnB1YmxpY2tleTAwMDAwMDAwMDAwMDAwMDAwMDAwMDA=
PresharedKey = cHJlc2hhcmVka2V5MDAwMDAwMDAwMDAwMDAwMDAwMDAwMDA=
AllowedIPs = 0.0.0.0/0, ::/0
Endpoint = wg.example.com:51820
PersistentKeepalive = 25
]]

check("detect wg conf", parser.detect(WG_CONF) == "wireguard-conf")

local res = parser.parse(WG_CONF)
check("parse wg conf ok", res ~= nil and res.format == "wireguard-conf")
check("parse wg conf one node", res and #res.nodes == 1)

local n = res and res.nodes[1] or {}
check("conf proto", n.proto == "wireguard")
check("conf server", n.server == "wg.example.com")
check("conf port", n.port == 51820)
check("conf private-key", n["private-key"] == "aGVsbG93b3JsZHByaXZhdGVrZXkwMDAwMDAwMDAwMDA=")
check("conf public-key", n["public-key"] == "cGVlcnB1YmxpY2tleTAwMDAwMDAwMDAwMDAwMDAwMDAwMDA=")
check("conf pre-shared-key", n["pre-shared-key"] == "cHJlc2hhcmVka2V5MDAwMDAwMDAwMDAwMDAwMDAwMDAwMDA=")
check("conf ip", n.ip == "10.7.0.2/32")
check("conf ipv6", n.ipv6 == "fd00:7::2/128")
check("conf allowed-ips array", type(n["allowed-ips"]) == "table" and #n["allowed-ips"] == 2)
check("conf allowed-ips v4", n["allowed-ips"] and n["allowed-ips"][1] == "0.0.0.0/0")
check("conf allowed-ips v6", n["allowed-ips"] and n["allowed-ips"][2] == "::/0")
check("conf persistent-keepalive", n["persistent-keepalive"] == 25)
check("conf listen-port", n["listen-port"] == 51820)
check("conf mtu", n.mtu == 1420)
check("conf dns single is string", n.dns == "1.1.1.1")
check("conf default name", n.name == "wg.example.com:51820")

-- ---------- AmneziaWG .conf（含 Jc/Jmin/Jmax/S1/S2/H1..H4） ----------
local AWG_CONF = [[
[Interface]
PrivateKey = YW1uZXppYXByaXZhdGVrZXkwMDAwMDAwMDAwMDAwMDA=
Address = 10.8.1.5/32
DNS = 1.1.1.1, 8.8.8.8
Jc = 5
Jmin = 50
Jmax = 1000
S1 = 86
S2 = 574
H1 = 1234567
H2 = 2345678
H3 = 3456789
H4 = 4567890

[Peer]
PublicKey = YW1uZXppYXBlZXJrZXkwMDAwMDAwMDAwMDAwMDAwMDAwMDA=
AllowedIPs = 0.0.0.0/0
Endpoint = 203.0.113.9:51820
]]

check("detect awg conf", parser.detect(AWG_CONF) == "wireguard-conf")

local ares = parser.parse(AWG_CONF)
check("parse awg conf ok", ares ~= nil and #ares.nodes == 1)

local a = ares and ares.nodes[1] or {}
check("awg proto", a.proto == "wireguard")
check("awg server", a.server == "203.0.113.9")
check("awg port", a.port == 51820)
check("awg ip", a.ip == "10.8.1.5/32")
check("awg dns multi is array", type(a.dns) == "table" and #a.dns == 2)
check("awg dns first", type(a.dns) == "table" and a.dns[1] == "1.1.1.1")

local opt = a["amnezia-wg-option"]
check("awg option exists", type(opt) == "table")
check("awg jc", opt and opt.jc == 5)
check("awg jmin", opt and opt.jmin == 50)
check("awg jmax", opt and opt.jmax == 1000)
check("awg s1", opt and opt.s1 == 86)
check("awg s2", opt and opt.s2 == 574)
check("awg h1", opt and opt.h1 == 1234567)
check("awg h2", opt and opt.h2 == 2345678)
check("awg h3", opt and opt.h3 == 3456789)
check("awg h4", opt and opt.h4 == 4567890)

-- ---------- 大小写不敏感 / 注释 / 未知键丢弃 ----------
local LOOSE_CONF = [[
# AmneziaWG export
; another comment style
[interface]
privatekey = a2V5
address = 10.9.0.3/32
s3 = 12
s4 = 34
UnknownFutureKey = should-be-dropped

[peer]
publickey = cHVi
allowedips = 0.0.0.0/0
endpoint = [2001:db8::1]:51821
]]

check("detect loose conf", parser.detect(LOOSE_CONF) == "wireguard-conf")
local lres = parser.parse(LOOSE_CONF)
local l = lres and lres.nodes[1] or {}
check("loose private-key", l["private-key"] == "a2V5")
check("loose ipv6 endpoint host", l.server == "2001:db8::1")
check("loose ipv6 endpoint port", l.port == 51821)
check("loose s3", l["amnezia-wg-option"] and l["amnezia-wg-option"].s3 == 12)
check("loose s4", l["amnezia-wg-option"] and l["amnezia-wg-option"].s4 == 34)
check("loose unknown key dropped", l["amnezia-wg-option"] and l["amnezia-wg-option"].unknownfuturekey == nil)

-- ---------- 缺少 Endpoint 应失败，而不是产出半成品节点 ----------
local BAD_CONF = "[Interface]\nPrivateKey = a2V5\nAddress = 10.0.0.1/32\n"
check("bad conf no endpoint", parser.detect(BAD_CONF) == "wireguard-conf")
local bres, berr = parser.parse(BAD_CONF)
check("bad conf returns error", bres == nil and type(berr) == "string")

-- ---------- 导出：clash.meta ----------
local clash = output_clash_meta.generate({ n })
check("clash conf has private-key", clash:find("private%-key: aGVsbG93b3JsZHByaXZhdGVrZXkwMDAwMDAwMDAwMDA=") ~= nil)
check("clash conf has public-key", clash:find("public%-key: cGVlcnB1YmxpY2tleTAw") ~= nil)
check("clash conf has ip", clash:find("ip: 10%.7%.0%.2/32") ~= nil)
-- esc_yaml 对含 ":" 的值会加引号（合法且更安全的 YAML），故断言带引号形式
check("clash conf has ipv6", clash:find('ipv6: "fd00:7::2/128"') ~= nil)
check("clash conf has listen-port", clash:find("listen%-port: 51820") ~= nil)
-- allowed-ips 必须是合法 YAML 列表，不能出现 table: 0x...
check("clash allowed-ips not table-dump", clash:find("table: 0x") == nil)
check("clash allowed-ips list", clash:find('allowed%-ips:\n%s+%- 0%.0%.0%.0/0\n%s+%- "::/0"') ~= nil)

-- ---------- 导出：sing-box（local_address 必须是数组） ----------
local sb = output_singbox.generate({ n })
check("singbox local_address array", sb:find('"local_address":%["10%.7%.0%.2/32","fd00:7::2/128"%]') ~= nil)
check("singbox listen_port", sb:find('"listen_port":51820') ~= nil)
check("singbox allowed_ips array", sb:find('"allowed_ips":%["0%.0%.0%.0/0","::/0"%]') ~= nil)

-- 只有 IPv4 时 local_address 退化为字符串
local v4only = output_singbox.generate({ { proto = "wireguard", name = "v4", server = "1.2.3.4", port = 51820, ip = "10.0.0.1/32" } })
check("singbox single local_address string", v4only:find('"local_address":"10%.0%.0%.1/32"') ~= nil)

-- ---------- 导出：AmneziaWG 参数稳定排序 ----------
local awg_clash = output_clash_meta.generate({ a })
check("awg clash option block", awg_clash:find("amnezia%-wg%-option:") ~= nil)
check("awg clash no table-dump", awg_clash:find("table: 0x") == nil)
local i_h1 = awg_clash:find("      h1: 1234567")
local i_jc = awg_clash:find("      jc: 5")
local i_s1 = awg_clash:find("      s1: 86")
check("awg clash sorted h1<jc", i_h1 ~= nil and i_jc ~= nil and i_h1 < i_jc)
check("awg clash sorted jc<s1", i_jc ~= nil and i_s1 ~= nil and i_jc < i_s1)

-- ---------- 导出：URI 往返 ----------
local uri = output_uri.format_node and output_uri.format_node(n) or nil
if type(uri) == "string" then
	local rres = parser.parse(uri)
	local r = rres and rres.nodes[1] or {}
	check("uri roundtrip proto", r.proto == "wireguard")
	check("uri roundtrip server", r.server == "wg.example.com")
	check("uri roundtrip ip", r.ip == "10.7.0.2/32")
	check("uri roundtrip listen-port", r["listen-port"] == 51820)
end

-- ---------- 结果 ----------
print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
