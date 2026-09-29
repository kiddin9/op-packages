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

-- ---------- 导出：wg-quick .conf 单接口约束（§55/§56） ----------
local wgconf = require("substore.output_wireguard_conf")

local c1 = wgconf.generate({ n })
check("wgconf single node returns text", type(c1) == "string")
check("wgconf single node has one Interface", select(2, c1:gsub("%[Interface%]", "")) == 1)
check("wgconf single node has one Peer", select(2, c1:gsub("%[Peer%]", "")) == 1)

-- 多节点：必须明确报错，绝不把多个 [Interface] 拼进一个文件
local multi = wgconf.generate({
	{ proto = "wireguard", name = "w1", server = "a.example.com", port = 51820, ["public-key"] = "K1" },
	{ proto = "wireguard", name = "w2", server = "b.example.com", port = 51820, ["public-key"] = "K2" },
})
check("wgconf multi node returns nil", multi == nil)
local _, multi_err = wgconf.generate({
	{ proto = "wireguard", name = "w1", server = "a.example.com", port = 51820, ["public-key"] = "K1" },
	{ proto = "wireguard", name = "w2", server = "b.example.com", port = 51820, ["public-key"] = "K2" },
})
check("wgconf multi node error is string", type(multi_err) == "string")
check("wgconf multi node error names the count", multi_err:find("2", 1, true) ~= nil)
check("wgconf multi node error mentions single tunnel", multi_err:find("一条隧道", 1, true) ~= nil)

-- 无 WireGuard 节点：仍是「没有可导出节点」而非拼接
local none, none_err = wgconf.generate({ { proto = "vmess", server = "x", port = 443 } })
check("wgconf no wg node returns nil", none == nil)
check("wgconf no wg node error", type(none_err) == "string" and none_err:find("没有可导出", 1, true) ~= nil)
local empty, empty_err = wgconf.generate({})
check("wgconf empty list returns nil", empty == nil)
check("wgconf empty list error", type(empty_err) == "string")

-- 单节点 .conf 必须能被自家解析器读回（往返一致）
local rt = parser.parse(c1)
check("wgconf roundtrip parses", rt ~= nil and rt.nodes and #rt.nodes == 1)
if rt and rt.nodes and rt.nodes[1] then
	local r = rt.nodes[1]
	check("wgconf roundtrip server", r.server == n.server)
	check("wgconf roundtrip port", r.port == n.port)
	check("wgconf roundtrip public-key", r["public-key"] == n["public-key"])
	check("wgconf roundtrip ip", r.ip == n.ip)
end

-- ---------- 导出：AmneziaWG 参数写入 .conf 的键名（§110） ----------
-- 已知键必须写成客户端认得的 .conf 名；无法确定名字的键绝不能靠「首字母大写」
-- 猜一个出来（header-protection-key → Header-protection-key 会被客户端拒）
local awg_out = wgconf.generate({ {
	proto = "wireguard", name = "awg", server = "wg.example.com", port = 51820,
	["private-key"] = "PRIV", ["public-key"] = "PUB", ip = "10.0.0.1/32",
	["allowed-ips"] = "0.0.0.0/0",
	["amnezia-wg-option"] = {
		jc = 5, jmin = 50, jmax = 1000,
		s1 = 86, s2 = 574, h1 = "1000-2000", h4 = "7000-8000", itime = 30,
		["header-protection-key"] = "c2VjcmV0",
		["random-trailers"] = "on",
	},
} })
check("awg conf export returns text", type(awg_out) == "string")
check("awg conf Jc", awg_out and awg_out:find("Jc = 5", 1, true) ~= nil)
check("awg conf Jmin", awg_out and awg_out:find("Jmin = 50", 1, true) ~= nil)
check("awg conf S1", awg_out and awg_out:find("S1 = 86", 1, true) ~= nil)
check("awg conf Itime", awg_out and awg_out:find("Itime = 30", 1, true) ~= nil)
-- range 必须原样保留（不能变成数字）
check("awg conf H1 range kept", awg_out and awg_out:find("H1 = 1000-2000", 1, true) ~= nil)
check("awg conf H4 range kept", awg_out and awg_out:find("H4 = 7000-8000", 1, true) ~= nil)
-- 多词键：名字必须与 amneziawg-tools 的写法逐字符一致，不能靠「首字母大写」猜
check("awg conf no mangled Header-protection-key",
	awg_out and awg_out:find("Header-protection-key", 1, true) == nil)
check("awg conf no mangled Random-trailers",
	awg_out and awg_out:find("Random-trailers", 1, true) == nil)
-- AWG 3.0/3.1 多词键名核对自 amneziawg-tools src/config.c，因此应当输出
check("awg conf HeaderProtectionKey",
	awg_out and awg_out:find("HeaderProtectionKey = c2VjcmV0", 1, true) ~= nil)
check("awg conf RandomTrailers on/off", awg_out and awg_out:find("RandomTrailers = on", 1, true) ~= nil)
-- 真正未知的键仍然必须丢弃（不猜语义）
local awg_unknown = wgconf.generate({ {
	proto = "wireguard", name = "awg", server = "wg.example.com", port = 51820,
	["private-key"] = "PRIV", ["public-key"] = "PUB",
	["amnezia-wg-option"] = { jc = 5, ["totally-unknown-key"] = "SECRETVALUE" },
} })
check("awg conf unknown key dropped",
	awg_unknown and awg_unknown:find("SECRETVALUE", 1, true) == nil)
check("awg conf unknown key name absent",
	awg_unknown and awg_unknown:find("totally-unknown-key", 1, true) == nil)
-- 已知键按 .conf 名排序，保证可 diff
local iH1 = awg_out and awg_out:find("H1 = ", 1, true)
local iJc = awg_out and awg_out:find("Jc = ", 1, true)
local iS1 = awg_out and awg_out:find("S1 = ", 1, true)
check("awg conf sorted H1<Jc<S1", iH1 and iJc and iS1 and iH1 < iJc and iJc < iS1)

-- 导出的 .conf 必须能被自家解析器读回（AWG 参数往返一致）
local art = parser.parse(awg_out)
check("awg conf roundtrip parses", art ~= nil and art.nodes and #art.nodes == 1)
if art and art.nodes and art.nodes[1] then
	local ao = art.nodes[1]["amnezia-wg-option"] or {}
	check("awg conf roundtrip jc", ao.jc == 5)
	check("awg conf roundtrip s1", ao.s1 == 86)
	check("awg conf roundtrip h1 range is string",
		ao.h1 == "1000-2000" and type(ao.h1) == "string")
	check("awg conf roundtrip itime", ao.itime == 30)
end

-- ---------- AmneziaWG 3.0 / 3.1 字段导入 ----------
-- 键名与类型核对自 amneziawg-tools src/config.c 与 mihomo AmneziaWGOption：
-- 规范名用 mihomo 的 proxy tag（小写连字符），布尔键只认 on/off/十进制数。
local AWG3_CONF = [[
[Interface]
PrivateKey = PRIV3
Address = 10.0.0.2/32
Jc = 4
HeaderProtectionKey = AAAA
ContentPaddingAddition = 16
RekeyAfterTime = 120
RekeyTimeout = 5
RejectAfterTime = 180
KeepaliveTimeout = 10
MaxHandshakeAttempts = 18
RandomTrailers = on
DisableCookies = off

[Peer]
PublicKey = PUB3
AllowedIPs = 0.0.0.0/0
Endpoint = 1.2.3.4:51820
]]
local r3 = parser.parse(AWG3_CONF, "wireguard-conf")
check("awg3 parses", r3 ~= nil and r3.nodes and #r3.nodes == 1)
local o3 = r3 and r3.nodes[1] and r3.nodes[1]["amnezia-wg-option"] or {}
check("awg3 HeaderProtectionKey", o3["header-protection-key"] == "AAAA")
check("awg3 ContentPaddingAddition", o3["content-padding-addition"] == 16)
check("awg3 RekeyAfterTime", o3["rekey-after-time"] == 120)
check("awg3 RekeyTimeout", o3["rekey-timeout"] == 5)
check("awg3 RejectAfterTime", o3["reject-after-time"] == 180)
check("awg3 KeepaliveTimeout", o3["keepalive-timeout"] == 10)
check("awg3 MaxHandshakeAttempts", o3["max-handshake-attempts"] == 18)
check("awg3 RandomTrailers bool true", o3["random-trailers"] == true)
check("awg3 DisableCookies bool false", o3["disable-cookies"] == false)
check("awg3 legacy jc still parsed", o3.jc == 4)
-- 大小写不敏感（config.c 的 process_line）
check("awg3 case-insensitive key",
	(parser.parse((AWG3_CONF:gsub("RandomTrailers", "RANDOMTRAILERS")), "wireguard-conf")
		or {}).nodes[1]["amnezia-wg-option"]["random-trailers"] == true)
-- 十进制布尔（0 假 / 非 0 真）
local r3d = parser.parse((AWG3_CONF:gsub("RandomTrailers = on", "RandomTrailers = 1")
	:gsub("DisableCookies = off", "DisableCookies = 0")), "wireguard-conf")
check("awg3 decimal bool true",
	r3d.nodes[1]["amnezia-wg-option"]["random-trailers"] == true)
check("awg3 decimal bool false",
	r3d.nodes[1]["amnezia-wg-option"]["disable-cookies"] == false)
-- 非法布尔值（true/false/yes/no 都不是 config.c 认的写法）必须丢弃，不能留给 mihomo 报错
local r3b = parser.parse((AWG3_CONF:gsub("RandomTrailers = on", "RandomTrailers = yes")),
	"wireguard-conf")
check("awg3 invalid bool dropped",
	r3b.nodes[1]["amnezia-wg-option"]["random-trailers"] == nil)
-- 往返：导出后能被自家解析器读回，值一致
local r3out = wgconf.generate({ r3.nodes[1] })
check("awg3 export HeaderProtectionKey",
	r3out and r3out:find("HeaderProtectionKey = AAAA", 1, true) ~= nil)
check("awg3 export RandomTrailers on",
	r3out and r3out:find("RandomTrailers = on", 1, true) ~= nil)
check("awg3 export DisableCookies off",
	r3out and r3out:find("DisableCookies = off", 1, true) ~= nil)
check("awg3 export MaxHandshakeAttempts",
	r3out and r3out:find("MaxHandshakeAttempts = 18", 1, true) ~= nil)
local r3back = parser.parse(r3out)
check("awg3 roundtrip bool preserved",
	r3back.nodes[1]["amnezia-wg-option"]["random-trailers"] == true
	and r3back.nodes[1]["amnezia-wg-option"]["disable-cookies"] == false)
check("awg3 roundtrip string preserved",
	r3back.nodes[1]["amnezia-wg-option"]["header-protection-key"] == "AAAA")
-- [Peer] 段独有的 AdvancedSecurity 不得被并进 amnezia-wg-option：
-- 并进来会在导出时写到 [Interface] 下（错误段落），宁可不支持
local r3peer = parser.parse(AWG3_CONF:gsub("Endpoint = 1%.2%.3%.4:51820",
	"Endpoint = 1.2.3.4:51820\nAdvancedSecurity = on"), "wireguard-conf")
check("awg3 peer-only key not merged",
	r3peer.nodes[1]["amnezia-wg-option"]["advanced-security"] == nil)
check("awg3 peer-only key not exported",
	(wgconf.generate({ r3peer.nodes[1] }) or ""):find("AdvancedSecurity", 1, true) == nil)

-- ---------- 多个 [Peer]：每个对端一个节点 ----------
local MULTI_PEER = [[
[Interface]
PrivateKey = PRIVM
Address = 10.0.0.2/32
Jc = 7

[Peer]
PublicKey = PEER1
PresharedKey = PSK1
AllowedIPs = 0.0.0.0/0
Endpoint = 1.2.3.4:51820

[Peer]
PublicKey = PEER2
AllowedIPs = 10.0.0.0/8
Endpoint = 5.6.7.8:51820
]]
local mp = parser.parse(MULTI_PEER, "wireguard-conf")
check("multi-peer yields two nodes", mp ~= nil and mp.nodes and #mp.nodes == 2)
if mp and mp.nodes and #mp.nodes == 2 then
	local a, b = mp.nodes[1], mp.nodes[2]
	check("multi-peer peer1 server", a.server == "1.2.3.4" and a.port == 51820)
	check("multi-peer peer2 server", b.server == "5.6.7.8" and b.port == 51820)
	check("multi-peer peer1 public-key", a["public-key"] == "PEER1")
	check("multi-peer peer2 public-key", b["public-key"] == "PEER2")
	-- 关键回归：不能把 A 段的 PresharedKey 拼到 B 段上
	check("multi-peer peer1 psk", a["pre-shared-key"] == "PSK1")
	check("multi-peer peer2 psk not inherited", b["pre-shared-key"] == nil)
	check("multi-peer peer1 allowed-ips", table.concat(a["allowed-ips"], ",") == "0.0.0.0/0")
	check("multi-peer peer2 allowed-ips", table.concat(b["allowed-ips"], ",") == "10.0.0.0/8")
	-- [Interface] 设置由两个节点共享
	check("multi-peer shared private-key", a["private-key"] == "PRIVM" and b["private-key"] == "PRIVM")
	check("multi-peer shared ip", a.ip == "10.0.0.2/32" and b.ip == "10.0.0.2/32")
	check("multi-peer shared awg", a["amnezia-wg-option"].jc == 7 and b["amnezia-wg-option"].jc == 7)
	-- 不能共享同一个表：改一个不能影响另一个
	check("multi-peer awg tables distinct",
		a["amnezia-wg-option"] ~= b["amnezia-wg-option"])
	-- 多节点导出仍按 §55/§56 明确报错，而不是静默拼接
	local merr = wgconf.generate({ a, b })
	check("multi-peer export still refuses", merr == nil)
end
check("conf with no Peer rejected",
	(parser.parse("[Interface]\nPrivateKey = X\n", "wireguard-conf")) == nil)

-- ---------- LuCI 表单路径：字符串 → 统一模型 ----------
-- 表单里所有输入框的值都是字符串，而统一模型（见 .conf 解析）里
-- allowed-ips / reserved / dns 是数组、amnezia-wg-option 是 table。
-- 不归一就会出现两种症状：
--   (a) amnezia-wg-option 是字符串 → 下游三处 type(...)=="table" 全部失败，
--       UI 里编辑过的 WireGuard 节点导出时丢掉全部 AmneziaWG 参数（静默）
--   (b) allowed-ips / reserved / dns 是标量字符串 → mihomo / sing-box
--       的对应字段是列表类型，导出结果非法
do
	local util = require("substore.util")
	local wgconf = require("substore.output_wireguard_conf")
	local payload = util.json_encode({ {
		type = "wireguard", name = "wgform", server = "1.2.3.4", port = "51820",
		["private-key"] = "PRIVF", ["public-key"] = "PUBF",
		ip = "10.0.0.2/32", ipv6 = "fd00::2/128",
		["allowed-ips"] = "0.0.0.0/0, ::/0",
		reserved = "1, 2, 3",
		dns = "1.1.1.1, 8.8.8.8",
		["amnezia-wg-option"] = '{"jc":4,"jmin":40,"jmax":70,"s1":30,"s2":40,"h1":1234,"random-trailers":true}',
	} })
	local res = parser.parse_local(payload, "form")
	local n = res and res.nodes and res.nodes[1]
	check("form: node parsed", n ~= nil)
	check("form: awg decoded to table", type(n["amnezia-wg-option"]) == "table")
	check("form: awg jc value", n["amnezia-wg-option"].jc == 4)
	check("form: awg bool preserved", n["amnezia-wg-option"]["random-trailers"] == true)
	check("form: allowed-ips is array",
		type(n["allowed-ips"]) == "table" and #n["allowed-ips"] == 2)
	check("form: reserved is numeric array",
		type(n.reserved) == "table" and n.reserved[3] == 3)
	check("form: dns multi becomes array", type(n.dns) == "table" and #n.dns == 2)

	-- (a) 导出 .conf：AmneziaWG 参数必须在
	local conf = wgconf.generate({ n })
	check("form: .conf keeps Jc", conf ~= nil and conf:find("Jc = 4", 1, true) ~= nil)
	check("form: .conf keeps RandomTrailers as on/off",
		conf ~= nil and conf:find("RandomTrailers = on", 1, true) ~= nil)

	-- (b) 导出 clash：必须是 YAML 列表而不是带引号的标量
	local cm = output_clash_meta.generate({ n })
	check("form: clash allowed-ips is a list",
		cm:find("allowed%-ips:%s*\n%s+%- 0%.0%.0%.0/0") ~= nil)
	check("form: clash has no scalar allowed-ips",
		cm:find('allowed%-ips: "') == nil)
	check("form: clash amnezia-wg-option emitted",
		cm:find("amnezia%-wg%-option:") ~= nil and cm:find("jc: 4") ~= nil)

	-- sing-box 的 allowed_ips / reserved / dns 都是数组
	local sb = output_singbox.generate({ n })
	check("form: singbox allowed_ips array", sb:find('"allowed_ips":%[') ~= nil)
	check("form: singbox reserved array", sb:find('"reserved":%[1,2,3%]') ~= nil)
	check("form: singbox dns array", sb:find('"dns":%[') ~= nil)

	-- 单值 DNS 仍保持字符串（与 .conf 解析一致）
	local single = parser.parse_local(util.json_encode({ {
		type = "wireguard", server = "1.2.3.4", port = "51820", dns = "1.1.1.1",
	} }), "form").nodes[1]
	check("form: single dns stays string", single.dns == "1.1.1.1")

	-- 非法 JSON 必须明确报错，不能留个字符串让它在导出时无声消失
	local bad, berr = parser.parse_local(util.json_encode({ {
		type = "wireguard", server = "1.2.3.4", port = "51820",
		["amnezia-wg-option"] = "{not json",
	} }), "form")
	check("form: invalid awg json rejected", bad == nil)
	check("form: invalid awg json error message", type(berr) == "string" and #berr > 0)

	-- 空字符串等于「未设置」
	local empty = parser.parse_local(util.json_encode({ {
		type = "wireguard", server = "1.2.3.4", port = "51820",
		["amnezia-wg-option"] = "",
	} }), "form").nodes[1]
	check("form: empty awg json cleared", empty["amnezia-wg-option"] == nil)
end

-- ---------- 结果 ----------
print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
