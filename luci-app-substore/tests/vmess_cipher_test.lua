-- vmess_cipher_test.lua — vmess 加密方式（cipher）与 TLS 层（security）不得混淆
-- 用法：lua5.1 tests/vmess_cipher_test.lua
--
-- 背景：经典 vmess 分享链接 vmess://base64(json) 用 scy 表示**加密方式**
-- （auto / aes-128-gcm / chacha20-poly1305 / none / zero），用 tls 表示 **TLS 层**
-- （"tls" 启用，"" 不启用）。而统一模型里 security 一直是 TLS 层
-- （node.lua DEFAULTS、vless/trojan URI 的 security=、Xray streamSettings.security、
-- Clash tls: true）。此前解析器把 scy 写进了 security，导致一个不启用 TLS 的节点
-- 被三个目标同时误判为启用 TLS：
--   sing-box  → "tls":{}            （多余且错误）
--   V2Ray     → streamSettings.security: "auto"（非法取值，Xray 拒绝启动）
--   Clash.Meta→ tls: true           （多余且错误）
-- 本测试锁定修复后的行为。

package.path = "./root/usr/share/?.lua;" .. package.path

local util = require("substore.util")
local node = require("substore.node")
local parser = require("substore.parser")
local json_parser = require("substore.parser_json_config")
local clash_parser = require("substore.parser_clash_yaml")
local output = require("substore.output")
local uri = require("substore.output_uri")

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

local function vmess_link(j)
	return "vmess://" .. util.base64_encode(util.json_encode(j))
end

-- ---------- 1. 不启用 TLS：scy=auto, tls="" ----------
-- 这是机场订阅最常见的形态
local plain = parser.parse_uri(vmess_link({
	v = "2", ps = "PLAIN", add = "1.1.1.1", port = "443",
	id = "11111111-1111-1111-1111-111111111111", aid = "0",
	scy = "auto", net = "tcp", type = "none", host = "", path = "", tls = "",
}))
check("plain parses", plain ~= nil and plain.proto == "vmess")
check("plain security is none (not the cipher)", plain.security == "none")
check("plain cipher is auto", plain.cipher == "auto")
check("plain tls normalized to nil", plain.tls == nil)

local sb = util.json_decode(output.generate({ plain }, "singbox"))
check("singbox no spurious tls", sb.outbounds[1].tls == nil)
check("singbox security is cipher auto", sb.outbounds[1].security == "auto")

local v2 = util.json_decode(output.generate({ plain }, "v2ray"))
check("v2ray no spurious streamSettings.security", v2.outbounds[1].streamSettings.security == nil)
check("v2ray users security is cipher auto", v2.outbounds[1].settings.vnext[1].users[1].security == "auto")

local cm = output.generate({ plain }, "clashmeta")
check("clashmeta no spurious tls: true", cm:find("tls: true", 1, true) == nil)
check("clashmeta cipher auto", cm:find("cipher: auto", 1, true) ~= nil)

local surge = output.generate({ plain }, "surge")
check("surge no spurious tls=true", surge:find("tls=true", 1, true) == nil)

-- ---------- 2. 启用 TLS + 非默认加密方式 ----------
local sec = parser.parse_uri(vmess_link({
	v = "2", ps = "SEC", add = "2.2.2.2", port = "443",
	id = "22222222-2222-2222-2222-222222222222", aid = "0",
	scy = "aes-128-gcm", net = "ws", type = "none", host = "", path = "/p",
	tls = "tls", sni = "a.example.com",
}))
check("tls security is tls", sec.security == "tls")
check("tls cipher is aes-128-gcm", sec.cipher == "aes-128-gcm")

local sb2 = util.json_decode(output.generate({ sec }, "singbox"))
check("singbox tls object present", type(sb2.outbounds[1].tls) == "table")
check("singbox security is the cipher", sb2.outbounds[1].security == "aes-128-gcm")

local v22 = util.json_decode(output.generate({ sec }, "v2ray"))
check("v2ray streamSettings.security is tls", v22.outbounds[1].streamSettings.security == "tls")
check("v2ray users security is the cipher", v22.outbounds[1].settings.vnext[1].users[1].security == "aes-128-gcm")

local cm2 = output.generate({ sec }, "clashmeta")
check("clashmeta tls: true", cm2:find("tls: true", 1, true) ~= nil)
check("clashmeta cipher preserved", cm2:find("cipher: aes-128-gcm", 1, true) ~= nil)

-- ---------- 3. 分享链接回环：加密方式与 TLS 层都要保住 ----------
local back = parser.parse_uri(uri.to_share_uri(sec))
check("roundtrip security tls", back.security == "tls")
check("roundtrip cipher aes-128-gcm", back.cipher == "aes-128-gcm")

local back_plain = parser.parse_uri(uri.to_share_uri(plain))
check("roundtrip plain security none", back_plain.security == "none")
check("roundtrip plain cipher auto", back_plain.cipher == "auto")

-- ---------- 4. 非法加密方式必须丢弃，而不是写进配置 ----------
-- 历史脏数据 / 第三方工具可能把 TLS 层写进 scy
local bad = parser.parse_uri(vmess_link({
	v = "2", ps = "BAD", add = "3.3.3.3", port = "443",
	id = "33333333-3333-3333-3333-333333333333", aid = "0",
	scy = "tls", net = "tcp", tls = "",
}))
check("invalid cipher dropped", bad.cipher == nil)
check("invalid cipher does not become security", bad.security == "none")
check("invalid cipher falls back to auto on output",
	util.json_decode(output.generate({ bad }, "singbox")).outbounds[1].security == "auto")

-- ---------- 5. node.normalize 的 tls 归一化 ----------
local function norm(t)
	local n = node.normalize({ proto = "vmess", server = "s", port = 1, tls = t })
	return n.tls, n.security
end
local t1, s1 = norm("")
check("normalize tls \"\" -> nil", t1 == nil and s1 == "none")
local t2, s2 = norm("none")
check("normalize tls \"none\" -> nil", t2 == nil and s2 == "none")
local t3, s3 = norm("false")
check("normalize tls \"false\" -> nil", t3 == nil and s3 == "none")
local t4, s4 = norm(true)
check("normalize tls true -> security tls", t4 == true and s4 == "tls")
local t5, s5 = norm("true")
check("normalize tls \"true\" (flat yaml) -> security tls", t5 == true and s5 == "tls")
local t6, s6 = norm("reality")
check("normalize tls reality -> security reality", t6 == "reality" and s6 == "reality")

-- ---------- 6. sing-box JSON 导入：security 是 cipher，TLS 由 tls 对象表达 ----------
local sb_nodes = json_parser.parse_singbox_json([[{"outbounds":[
  {"tag":"a","type":"vmess","server":"1.1.1.1","server_port":443,"uuid":"u","security":"chacha20-poly1305",
   "tls":{"server_name":"a.example.com"}},
  {"tag":"b","type":"vmess","server":"2.2.2.2","server_port":443,"uuid":"u","security":"auto"}
]}]])
check("singbox import count", sb_nodes and #sb_nodes == 2)
check("singbox import cipher from security", sb_nodes[1].cipher == "chacha20-poly1305")
check("singbox import tls object -> security", sb_nodes[1].security == "tls")
check("singbox import sni from tls", sb_nodes[1].sni == "a.example.com")
check("singbox import no-tls node security none", sb_nodes[2].security == "none")
check("singbox import no-tls node has no tls", sb_nodes[2].tls == nil)
check("singbox import roundtrip keeps tls",
	util.json_decode(output.generate({ sb_nodes[1] }, "singbox")).outbounds[1].tls ~= nil)

-- ---------- 7. Clash YAML 导入：cipher 是加密方式，tls 是 TLS 层 ----------
local cy = clash_parser.parse([[
proxies:
  - name: CY
    type: vmess
    server: 4.4.4.4
    port: 443
    uuid: 44444444-4444-4444-4444-444444444444
    alterId: 0
    cipher: chacha20-poly1305
    tls: true
    network: ws
    ws-opts:
      path: /ws
]])
check("clash import count", cy and #cy == 1)
check("clash import cipher preserved", cy[1].cipher == "chacha20-poly1305")
check("clash import tls -> security", cy[1].security == "tls")
local cm3 = output.generate(cy, "clashmeta")
check("clash->clashmeta cipher preserved", cm3:find("cipher: chacha20-poly1305", 1, true) ~= nil)
check("clash->clashmeta tls: true", cm3:find("tls: true", 1, true) ~= nil)

-- ---------- 8. 简易 YAML 回退路径同样不得混淆 ----------
-- parse_yaml_content 把 tls: true 读成字符串 "true"
local flat = output.generate(parser.parse([[
proxies:
  - name: FLAT
    type: vmess
    server: 5.5.5.5
    port: 443
    uuid: 55555555-5555-5555-5555-555555555555
    cipher: auto
    tls: ""
]]).nodes, "v2ray")
local flatd = util.json_decode(flat)
check("flat yaml no invalid streamSettings.security", flatd.outbounds[1].streamSettings.security == nil)

-- ---------- 9. 非 vmess 协议不受影响 ----------
local tro = node.normalize({ proto = "trojan", server = "6.6.6.6", port = 443, password = "p" })
check("trojan default security is tls", tro.security == "tls")
local vless = node.normalize({ proto = "vless", server = "7.7.7.7", port = 443, uuid = "u" })
check("vless default security is none", vless.security == "none")

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
