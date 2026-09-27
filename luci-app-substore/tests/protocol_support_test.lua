-- protocol_support_test.lua — hysteria2 / tuic / wireguard 导入、JSON 配置导入放开、Surge 家族输出单元测试
-- 用法：lua5.1 tests/protocol_support_test.lua

package.path = "./root/usr/share/?.lua;" .. package.path

local parser = require("substore.parser")
local parser_json_config = require("substore.parser_json_config")
local output = require("substore.output")
local output_uri = require("substore.output_uri")
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

-- ---------- hysteria2:// 分享链接导入 ----------
local hy2 = parser.parse_uri("hysteria2://my-secret@1.2.3.4:443/?sni=sni.example.com&insecure=1#HY2节点")
check("hy2 parses", hy2 ~= nil)
check("hy2 proto", hy2 and hy2.proto == "hysteria2")
check("hy2 server", hy2 and hy2.server == "1.2.3.4")
check("hy2 port", hy2 and hy2.port == 443)
check("hy2 password", hy2 and hy2.password == "my-secret")
check("hy2 sni", hy2 and hy2.sni == "sni.example.com")
check("hy2 insecure", hy2 and hy2.insecure == "1")
check("hy2 name", hy2 and hy2.name == "HY2节点")

-- ---------- tuic:// 分享链接导入 ----------
local tuic = parser.parse_uri("tuic://uuid-1234:tuic-pass@5.6.7.8:8443/?congestion_control=bbr&alpn=h3&sni=t.example.com#TUIC节点")
check("tuic parses", tuic ~= nil)
check("tuic proto", tuic and tuic.proto == "tuic")
check("tuic server", tuic and tuic.server == "5.6.7.8")
check("tuic port", tuic and tuic.port == 8443)
check("tuic uuid", tuic and tuic.uuid == "uuid-1234")
check("tuic password", tuic and tuic.password == "tuic-pass")
check("tuic congestion_control", tuic and tuic.congestion_control == "bbr")
check("tuic alpn", tuic and tuic.alpn == "h3")
check("tuic sni", tuic and tuic.sni == "t.example.com")
check("tuic name", tuic and tuic.name == "TUIC节点")

-- ---------- wireguard:// 导入（固定 base64 外部样本，非本实现生成） ----------
-- base64 内容：{"server":"10.0.0.9","port":"51820","private-key":"privkey123","peer-public-key":"pubkey456","preshared-key":"psk789","mtu":"1420"}
local wg_uri = "wireguard://eyJzZXJ2ZXIiOiIxMC4wLjAuOSIsInBvcnQiOiI1MTgyMCIsInByaXZhdGUta2V5IjoicHJpdmtleTEyMyIsInBlZXItcHVibGljLWtleSI6InB1YmtleTQ1NiIsInByZXNoYXJlZC1rZXkiOiJwc2s3ODkiLCJtdHUiOiIxNDIwIn0=#WG节点"
check("detect wg = uri", parser.detect(wg_uri) == "uri")
local wg = parser.parse_uri(wg_uri)
check("wg parses", wg ~= nil)
check("wg proto", wg and wg.proto == "wireguard")
check("wg server", wg and wg.server == "10.0.0.9")
check("wg port", wg and wg.port == 51820)
check("wg private-key", wg and wg["private-key"] == "privkey123")
check("wg peer-public-key", wg and wg["peer-public-key"] == "pubkey456")
check("wg preshared-key", wg and wg["preshared-key"] == "psk789")
check("wg mtu", wg and wg.mtu == 1420)
check("wg name", wg and wg.name == "WG节点")

-- ---------- 订阅（URI 列表 / base64）含 hy2 / tuic / wg ----------
local sub = "hysteria2://p@1.1.1.1:8443#A\ntuic://u:p@2.2.2.2:8443#B\nvless://uuid1@3.3.3.3:443#C"
local res = parser.parse(sub)
check("sub format uri", res and res.format == "uri")
check("sub 3 nodes", res and #res.nodes == 3)

local b64sub = util.base64_encode("hysteria2://p@1.1.1.1:8443#A\ntuic://u:p@2.2.2.2:8443#B")
local res2 = parser.parse(b64sub)
check("base64 sub 2 nodes", res2 and #res2.nodes == 2)
check("base64 sub proto hy2", res2 and res2.nodes[1] and res2.nodes[1].proto == "hysteria2")

-- ---------- URI 输出（Shadowrocket / V2Ray URI）含 hy2 / tuic / wg ----------
local hy2node = { proto = "hysteria2", name = "HY", server = "1.1.1.1", port = 443, password = "p", sni = "s.example.com" }
local tuicnode = { proto = "tuic", name = "TC", server = "2.2.2.2", port = 8443, uuid = "u", password = "p" }
local wgnode = { proto = "wireguard", name = "WG", server = "10.0.0.9", port = 51820,
	["private-key"] = "pk", ["peer-public-key"] = "ppk", ["preshared-key"] = "psk" }

local uri_out = output.generate({ hy2node, tuicnode, wgnode }, "v2rayuri")
check("uri has hysteria2", uri_out and uri_out:find("hysteria2://") ~= nil)
check("uri has tuic", uri_out and uri_out:find("tuic://") ~= nil)
check("uri has wireguard", uri_out and uri_out:find("wireguard://") ~= nil)

local rocket = output.generate({ hy2node, tuicnode, wgnode }, "shadowrocket")
local decoded = util.base64_decode(rocket)
check("shadowrocket has hysteria2", decoded:find("hysteria2://") ~= nil)
check("shadowrocket has wireguard", decoded:find("wireguard://") ~= nil)

-- ---------- wireguard 回环（输出 -> 解析） ----------
local wg_round = parser.parse_uri(uri_out:match("wireguard://[^\n]*"))
check("wg roundtrip proto", wg_round and wg_round.proto == "wireguard")
check("wg roundtrip server", wg_round and wg_round.server == "10.0.0.9")
check("wg roundtrip private", wg_round and wg_round["private-key"] == "pk")
check("wg roundtrip peer", wg_round and wg_round["peer-public-key"] == "ppk")

-- ---------- JSON 配置导入放开：sing-box JSON ----------
local singbox = [[
{
  "outbounds": [
    { "type": "hysteria2", "tag": "sb-hy2", "server": "1.1.1.1", "server_port": 443, "password": "hy2pw", "tls": { "server_name": "h.sni.com" } },
    { "type": "tuic", "tag": "sb-tuic", "server": "2.2.2.2", "server_port": 8443, "uuid": "sb-uuid", "password": "sb-tuicpw", "congestion_control": "bbr" },
    { "type": "wireguard", "tag": "sb-wg", "server": "3.3.3.3", "server_port": 51820, "private_key": "sb-priv", "peer_public_key": "sb-pub", "preshared_key": "sb-psk", "mtu": 1400 },
    { "type": "socks", "tag": "sb-socks", "server": "4.4.4.4", "server_port": 1080, "username": "suser", "password": "spass" }
  ]
}
]]
local sbnodes = parser_json_config.parse_singbox_json(singbox)
check("singbox 4 nodes", sbnodes and #sbnodes == 4)
check("singbox hy2", sbnodes and sbnodes[1] and sbnodes[1].proto == "hysteria2" and sbnodes[1].password == "hy2pw" and sbnodes[1].sni == "h.sni.com")
check("singbox tuic", sbnodes and sbnodes[2] and sbnodes[2].proto == "tuic" and sbnodes[2].uuid == "sb-uuid" and sbnodes[2].password == "sb-tuicpw")
check("singbox wg kebab", sbnodes and sbnodes[3] and sbnodes[3].proto == "wireguard" and sbnodes[3]["private-key"] == "sb-priv" and sbnodes[3]["peer-public-key"] == "sb-pub" and sbnodes[3]["preshared-key"] == "sb-psk")
check("singbox socks", sbnodes and sbnodes[4] and sbnodes[4].proto == "socks" and sbnodes[4].username == "suser" and sbnodes[4].password == "spass")

-- ---------- JSON 配置导入放开：Clash JSON（含 ssr） ----------
local clashjson = [[
{
  "proxies": [
    { "name": "c-ssr", "type": "ssr", "server": "1.1.1.1", "port": 8388, "cipher": "aes-128-cfb", "password": "ssrpw", "protocol": "auth_sha1_v4", "obfs": "http_simple", "obfs-param": "obfshost.com" },
    { "name": "c-hy2", "type": "hysteria2", "server": "2.2.2.2", "port": 443, "password": "hy2pw", "sni": "h2.example.com" },
    { "name": "c-tuic", "type": "tuic", "server": "3.3.3.3", "port": 8443, "uuid": "c-uuid", "password": "c-tuicpw" },
    { "name": "c-wg", "type": "wireguard", "server": "4.4.4.4", "port": 51820, "private-key": "c-priv", "peer-public-key": "c-pub", "preshared-key": "c-psk" },
    { "name": "c-socks", "type": "socks5", "server": "5.5.5.5", "port": 1080, "username": "cu", "password": "cp" }
  ]
}
]]
local cnodes = parser_json_config.parse_clash_json(clashjson)
check("clash json 5 nodes", cnodes and #cnodes == 5)
check("clash json ssr", cnodes and cnodes[1] and cnodes[1].proto == "ssr" and cnodes[1].method == "aes-128-cfb" and cnodes[1].protocol == "auth_sha1_v4" and cnodes[1].obfs == "http_simple" and cnodes[1].obfs_param == "obfshost.com")
check("clash json hy2", cnodes and cnodes[2] and cnodes[2].proto == "hysteria2" and cnodes[2].password == "hy2pw")
check("clash json tuic", cnodes and cnodes[3] and cnodes[3].proto == "tuic" and cnodes[3].uuid == "c-uuid")
check("clash json wg", cnodes and cnodes[4] and cnodes[4].proto == "wireguard" and cnodes[4]["private-key"] == "c-priv" and cnodes[4]["peer-public-key"] == "c-pub")
check("clash json socks5->socks", cnodes and cnodes[5] and cnodes[5].proto == "socks" and cnodes[5].username == "cu" and cnodes[5].password == "cp")

-- ---------- Surge 家族：tuic 输出 / wireguard 丢弃 ----------
local surge = output.generate({ tuicnode, wgnode }, "surge")
check("surge has tuic line", surge and surge:find("tuic, 2%.2%.2%.2, 8443") ~= nil)
check("surge tuic username", surge and surge:find("username=u") ~= nil)
check("surge drops wireguard", surge and surge:find("10%.0%.0%.9") == nil and surge:find("wireguard") == nil)

local loon = output.generate({ wgnode }, "loon")
check("loon drops wireguard too", loon and loon:find("wireguard") == nil)

-- ---------- sing-box 输出 wireguard 使用 kebab 字段（导入后可正确输出） ----------
local sb_out = output.generate({ wgnode }, "singbox")
local sb_decoded = util.json_decode(sb_out)
check("singbox wg private_key", sb_decoded and sb_decoded.outbounds[1] and sb_decoded.outbounds[1].private_key == "pk")
check("singbox wg peer_public_key", sb_decoded and sb_decoded.outbounds[1] and sb_decoded.outbounds[1].peer_public_key == "ppk")

-- ---------- 结果 ----------
print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)