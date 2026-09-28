-- amnezia_wg_test.lua — AmneziaWG 端到端：Clash YAML / JSON 导入 → clashmeta & sing-box 导出
-- 用法：lua5.1 tests/amnezia_wg_test.lua

package.path = "./root/usr/share/?.lua;" .. package.path

local util = require("substore.util")
local parser = require("substore.parser")
local output_clash_meta = require("substore.output_clash_meta")
local output_singbox = require("substore.output_singbox")

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

-- ---------- 1. Clash YAML（嵌套 map + 嵌套列表 + 内联数组） ----------
local CLASH_YAML = [[proxies:
  - name: awg-hk
    type: wireguard
    server: 203.0.113.9
    port: 51820
    private-key: PRIVKEY
    public-key: PUBKEY
    pre-shared-key: PSK
    ip: 10.8.1.5/32
    ipv6: fd00:8::5/128
    allowed-ips:
      - 0.0.0.0/0
      - "::/0"
    reserved: [1, 2, 3]
    persistent-keepalive: 25
    listen-port: 51820
    mtu: 1420
    dns:
      - 1.1.1.1
    amnezia-wg-option:
      jc: 5
      jmin: 50
      jmax: 1000
      s1: 86
      s2: 574
      h1: 1234567
      h2: 2345678
]]

local yres = parser.parse(CLASH_YAML)
check("yaml parse ok", yres ~= nil and #yres.nodes == 1)

local y = yres and yres.nodes[1] or {}
check("yaml proto wireguard", y.proto == "wireguard")
check("yaml name", y.name == "awg-hk")
check("yaml private-key", y["private-key"] == "PRIVKEY")
check("yaml public-key", y["public-key"] == "PUBKEY")
check("yaml pre-shared-key", y["pre-shared-key"] == "PSK")
check("yaml ip", y.ip == "10.8.1.5/32")
check("yaml ipv6", y.ipv6 == "fd00:8::5/128")
check("yaml listen-port", y["listen-port"] == 51820)
check("yaml allowed-ips is array", type(y["allowed-ips"]) == "table" and #y["allowed-ips"] == 2)
-- 引号标量不能被误解析成 table（"- \"::/0\"" 曾因冒号被当成 key:value）
check("yaml allowed-ips v6 is string", y["allowed-ips"] and y["allowed-ips"][2] == "::/0")
check("yaml reserved inline array", type(y.reserved) == "table" and #y.reserved == 3 and y.reserved[1] == 1)

local opt = y["amnezia-wg-option"]
check("yaml awg option is map", type(opt) == "table")
check("yaml awg jc", opt and opt.jc == 5)
check("yaml awg jmin", opt and opt.jmin == 50)
check("yaml awg jmax", opt and opt.jmax == 1000)
check("yaml awg s1", opt and opt.s1 == 86)
check("yaml awg s2", opt and opt.s2 == 574)
check("yaml awg h1", opt and opt.h1 == 1234567)
check("yaml awg h2", opt and opt.h2 == 2345678)

-- ---------- 2. 导出 clash.meta：字段名与列表结构必须合法 ----------
local cy = output_clash_meta.generate({ y })
check("clash yaml has public-key", cy:find("public%-key: PUBKEY") ~= nil)
check("clash yaml has pre-shared-key", cy:find("pre%-shared%-key: PSK") ~= nil)
check("clash yaml has ip", cy:find("ip: 10%.8%.1%.5/32") ~= nil)
check("clash yaml has listen-port", cy:find("listen%-port: 51820") ~= nil)
check("clash yaml no table dump", cy:find("table: 0x") == nil)
check("clash yaml allowed-ips list", cy:find('allowed%-ips:\n%s+%- 0%.0%.0%.0/0\n%s+%- "::/0"') ~= nil)
check("clash yaml reserved list", cy:find("reserved:\n%s+%- 1\n%s+%- 2\n%s+%- 3") ~= nil)
check("clash yaml dns list", cy:find("dns:\n%s+%- 1%.1%.1%.1") ~= nil)
check("clash yaml awg block", cy:find("amnezia%-wg%-option:") ~= nil)
check("clash yaml awg jc", cy:find("      jc: 5") ~= nil)
check("clash yaml awg h1", cy:find("      h1: 1234567") ~= nil)

-- 排序稳定：h1 < jc < s1（字典序）
local i_h1, i_jc, i_s1 = cy:find("      h1: 1234567"), cy:find("      jc: 5"), cy:find("      s1: 86")
check("clash yaml awg sorted", i_h1 ~= nil and i_jc ~= nil and i_s1 ~= nil and i_h1 < i_jc and i_jc < i_s1)

-- 同一节点导出两次必须完全一致（排序保证可 diff）
check("clash yaml deterministic", output_clash_meta.generate({ y }) == cy)

-- ---------- 3. 导出 sing-box：local_address 数组 + snake_case ----------
local sb = output_singbox.generate({ y })
check("singbox private_key", sb:find('"private_key":"PRIVKEY"') ~= nil)
check("singbox peer_public_key", sb:find('"peer_public_key":"PUBKEY"') ~= nil)
check("singbox pre_shared_key", sb:find('"pre_shared_key":"PSK"') ~= nil)
check("singbox local_address array", sb:find('"local_address":%["10%.8%.1%.5/32","fd00:8::5/128"%]') ~= nil)
check("singbox allowed_ips array", sb:find('"allowed_ips":%["0%.0%.0%.0/0","::/0"%]') ~= nil)
check("singbox reserved array", sb:find('"reserved":%[1,2,3%]') ~= nil)
check("singbox persistent_keepalive_interval", sb:find('"persistent_keepalive_interval":25') ~= nil)
check("singbox listen_port", sb:find('"listen_port":51820') ~= nil)
check("singbox mtu", sb:find('"mtu":1420') ~= nil)
-- 逗号拼接的 local_address 是非法值，必须彻底消失
check("singbox no comma-joined address", sb:find("10%.8%.1%.5/32,fd00") == nil)

-- ---------- 4. sing-box JSON 订阅导入（outbounds） ----------
local SB_JSON = util.json_encode({
	outbounds = {
		{
			type = "wireguard",
			tag = "awg-sb",
			server = "198.51.100.7",
			server_port = 51820,
			private_key = "SBPRIV",
			peer_public_key = "SBPUB",
			pre_shared_key = "SBPSK",
			local_address = { "10.9.0.9/32", "fd00:9::9/128" },
			allowed_ips = { "0.0.0.0/0" },
			reserved = { 9, 9, 9 },
			persistent_keepalive_interval = 25,
			listen_port = 51821,
			mtu = 1400,
		},
	},
})

local jres = parser.parse(SB_JSON)
check("json parse ok", jres ~= nil and #jres.nodes == 1)

local j = jres and jres.nodes[1] or {}
check("json proto wireguard", j.proto == "wireguard")
check("json server", j.server == "198.51.100.7")
check("json port", j.port == 51820)
check("json private-key", j["private-key"] == "SBPRIV")
check("json public-key", j["public-key"] == "SBPUB")
check("json pre-shared-key", j["pre-shared-key"] == "SBPSK")
check("json ip from array", j.ip == "10.9.0.9/32")
check("json ipv6 from array", j.ipv6 == "fd00:9::9/128")
check("json allowed-ips", type(j["allowed-ips"]) == "table" and j["allowed-ips"][1] == "0.0.0.0/0")
check("json reserved", type(j.reserved) == "table" and #j.reserved == 3)
check("json persistent-keepalive", j["persistent-keepalive"] == 25)
check("json listen-port", j["listen-port"] == 51821)
check("json mtu", j.mtu == 1400)

-- ---------- 5. 导出回 clash.meta：往返不丢字段 ----------
local cj = output_clash_meta.generate({ j })
check("roundtrip private-key", cj:find("private%-key: SBPRIV") ~= nil)
check("roundtrip public-key", cj:find("public%-key: SBPUB") ~= nil)
check("roundtrip pre-shared-key", cj:find("pre%-shared%-key: SBPSK") ~= nil)
check("roundtrip ip", cj:find("ip: 10%.9%.0%.9/32") ~= nil)
check("roundtrip ipv6", cj:find('ipv6: "fd00:9::9/128"') ~= nil)
check("roundtrip listen-port", cj:find("listen%-port: 51821") ~= nil)
check("roundtrip reserved", cj:find("reserved:\n%s+%- 9\n%s+%- 9\n%s+%- 9") ~= nil)
check("roundtrip no table dump", cj:find("table: 0x") == nil)

-- ---------- 6. esc_yaml：含特殊字符的值必须加引号 ----------
local NAME_NODE = { proto = "wireguard", name = "HK 01: 香港 #1", server = "1.2.3.4", port = 51820, ip = "10.0.0.1/32" }
local cn = output_clash_meta.generate({ NAME_NODE })
check("esc_yaml quotes name", cn:find('name: "HK 01: 香港 #1"') ~= nil)
-- 加引号后仍是合法 YAML：不含未转义的裸引号
check("esc_yaml escapes quote", output_clash_meta.generate({ { proto = "wireguard", name = 'a"b c', server = "1.2.3.4", port = 1 } }):find('name: "a\\"b c"') ~= nil)

-- ---------- 结果 ----------
print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
