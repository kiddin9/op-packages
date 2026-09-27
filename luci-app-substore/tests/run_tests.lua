-- run_tests.lua — 纯 Lua 核心库单元测试（在目标设备或装有 Lua 5.1 的环境运行）
-- 用法：lua5.1 tests/run_tests.lua
-- 说明：本仓库开发环境无 Lua 运行时，脚本未在本地执行；请在有 Lua 的设备/环境验证。

package.path = "./root/usr/share/?.lua;" .. package.path

local util = require("substore.util")
local parser = require("substore.parser")
local node = require("substore.node")

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

-- ---------- base64 ----------
check("b64 decode hello", util.base64_decode("aGVsbG8=") == "hello")
check("b64 encode hello", util.base64_encode("hello") == "aGVsbG8=")
check("b64 roundtrip unicode", util.base64_decode(util.base64_encode("机场节点中文")) == "机场节点中文")
check("b64 paddingless", util.base64_decode("aGVsbG8") == "hello")
check("b64 skip whitespace", util.base64_decode("aGVs\nbG8=") == "hello")

-- ---------- JSON ----------
local sample = { _seq = 2, items = { s1 = { name = "机场", url = "https://x.test/sub", node_count = 3, enabled = true, last_update = nil } } }
local encoded = util.json_encode(sample)
local decoded = util.json_decode(encoded)
check("json roundtrip", eq(decoded, sample))
check("json decode unicode escape", util.json_decode('{"name":"\\u4e2d\\u6587"}').name == "中文")
check("json array", #util.json_decode("[1,2,3]") == 3)
check("json nested", util.json_decode('{"a":{"b":[true,false,null,1.5]}}').a.b[4] == 1.5)

-- ---------- URL ----------
local h1, p1 = util.split_hostport("1.2.3.4:443")
check("split_hostport v4", h1 == "1.2.3.4" and p1 == "443")
local h2, p2 = util.split_hostport("[::1]:80")
check("split_hostport v6", h2 == "::1" and p2 == "80")
check("url_extract", util.url_extract("?type=tcp&security=none", "security") == "none")
check("url_decode", util.url_decode("%E6%9C%BA%E5%9C%BA") == "机场")

-- ---------- node.normalize ----------
check("normalize ss alias", node.normalize({ proto = "ss", name = "x", server = "h", port = 1 }).proto == "shadowsocks")
local nm = node.normalize({ proto = "vmess", server = "h", port = 443 })
check("normalize default net", nm.net == "tcp")
check("normalize default name", node.normalize({ proto = "vless", server = "h" }).name == "h:")

-- ---------- parser.parse_uri ----------
local vmess_json = util.json_encode({ add = "1.1.1.1", port = 443, id = "uuid1", net = "ws", scy = "auto", ps = "测试节点" })
local n1 = parser.parse_uri("vmess://" .. util.base64_encode(vmess_json))
check("vmess classic", n1 and n1.server == "1.1.1.1" and n1.port == 443 and n1.uuid == "uuid1" and n1.net == "ws")
check("vmess name", n1 and n1.name == "测试节点")

local n2 = parser.parse_uri("vless://uuid1@1.1.1.1:443?type=ws&security=tls&sni=example.com#VLESS")
check("vless", n2 and n2.proto == "vless" and n2.uuid == "uuid1" and n2.server == "1.1.1.1" and n2.net == "ws" and n2.sni == "example.com" and n2.name == "VLESS")

local n3 = parser.parse_uri("trojan://pass1@2.2.2.2:443?security=tls&sni=abc.com#TROJAN")
check("trojan", n3 and n3.password == "pass1" and n3.server == "2.2.2.2" and n3.sni == "abc.com")

local n4 = parser.parse_uri("ss://" .. util.base64_encode("aes-256-gcm:password1") .. "@3.3.3.3:8388#SS")
check("ss b64-userinfo", n4 and n4.method == "aes-256-gcm" and n4.password == "password1" and n4.server == "3.3.3.3" and n4.port == 8388)

local n5 = parser.parse_uri("ss://aes-256-gcm:password2@4.4.4.4:8388#SS2")
check("ss plain", n5 and n5.method == "aes-256-gcm" and n5.password == "password2" and n5.server == "4.4.4.4")

local n6 = parser.parse_uri("ss://" .. util.base64_encode("aes-256-gcm:password3") .. "@5.5.5.5:8388/?plugin=obfs-local%3Bobfs%3Dhttp")
check("ss plugin", n6 and n6.plugin ~= nil and n6.server == "5.5.5.5")

-- ss://base64(whole "method:password@host:port")#name
local n7 = parser.parse_uri("ss://" .. util.base64_encode("chacha20-ietf-poly1305:passw@6.6.6.6:443") .. "#SSW")
check("ss b64-whole", n7 and n7.method == "chacha20-ietf-poly1305" and n7.password == "passw" and n7.server == "6.6.6.6" and n7.port == 443)

check("unsupported proto", parser.parse_uri("foobar://x") == nil)

-- ---------- parser.detect / parse ----------
check("detect base64", parser.detect("aGVsbG8vZGVjb2RlZC1zc3Nzc3Nzc3M=") == "base64")
check("detect uri", parser.detect("vless://uuid1@1.1.1.1:443#x") == "uri")
check("detect json", parser.detect('{"server":"1.1.1.1","port":443}') == "json")
check("detect unknown", parser.detect("garbage content here") == "unknown")

local uri_sub = "vless://uuid1@1.1.1.1:443#A\ntrojan://pass@2.2.2.2:443#B\nss://aes-128-gcm:pass@3.3.3.3:8388#C"
local res = parser.parse(uri_sub)
check("parse uri sub count", res and #res.nodes == 3)
check("parse uri sub format", res and res.format == "uri")

-- base64 订阅：内容是若干 URI 的 base64
local plain = "vless://uuid1@1.1.1.1:443#A\nss://aes-128-gcm:pass@2.2.2.2:8388#B"
local res2 = parser.parse(util.base64_encode(plain))
check("parse base64 sub count", res2 and #res2.nodes == 2)
check("parse base64 sub format", res2 and res2.format == "base64")

-- base64url（URL-safe base64：- _ 替代 + /，无 padding）订阅
check("detect base64url literal", parser.detect("eyJ-abc_def") == "base64")
local vmess_link = "vmess://" .. util.base64_encode(util.json_encode({ v = "2", ps = "B64U", add = "9.9.9.9", port = "443", id = "u-1", aid = "0", net = "tcp" }))
local b64u_sub = util.base64_url_encode(vmess_link .. "\nvless://uuid2@8.8.8.8:443#V")
check("detect base64url sub", parser.detect(b64u_sub) == "base64")
local b64u_res = parser.parse(b64u_sub)
check("parse base64url count", b64u_res and #b64u_res.nodes == 2)
check("parse base64url proto", b64u_res and b64u_res.nodes[1] and b64u_res.nodes[1].proto == "vmess")
check("parse base64url server", b64u_res and b64u_res.nodes[1] and b64u_res.nodes[1].server == "9.9.9.9")

-- UTF-8 BOM 前缀的订阅
local bom_sub = "\239\187\191" .. util.base64_encode(vmess_link)
check("detect BOM prefix", parser.detect(bom_sub) == "base64")
local bom_res = parser.parse(bom_sub)
check("parse BOM count", bom_res and #bom_res.nodes == 1)

-- ---------- 结果 ----------
print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)