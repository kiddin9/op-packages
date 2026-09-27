-- ssr_test.lua — SSR（ShadowsocksR）解析与输出单元测试
-- 用法：lua5.1 tests/ssr_test.lua

package.path = "./root/usr/share/?.lua;" .. package.path

local util = require("substore.util")
local parser = require("substore.parser")
local output = require("substore.output")
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

-- 独立构造的已知 SSR 分享链接（由 Python base64 生成，非本实现生成，避免循环验证）：
-- server=127.0.0.1 port=8388 protocol=auth_aes128_md5 method=aes-128-cfb obfs=http_simple
-- password=test-password obfsparam=download.windowsupdate.com remarks=测试节点 group=测试组
local link = "ssr://MTI3LjAuMC4xOjgzODg6YXV0aF9hZXMxMjhfbWQ1OmFlcy0xMjgtY2ZiOmh0dHBfc2ltcGxlOmRHVnpkQzF3WVhOemQyOXlaQT09Lz9vYmZzcGFyYW09Wkc5M2JteHZZV1F1ZDJsdVpHOTNjM1Z3WkdGMFpTNWpiMjAmcmVtYXJrcz01cldMNkstVjZJcUM1NEs1Jmdyb3VwPTVyV0w2Sy1WNTd1RQ=="

check("detect ssr = uri", parser.detect(link) == "uri")
local n = parser.parse_uri(link)
check("ssr parses", n ~= nil)
check("ssr proto", n and n.proto == "ssr")
check("ssr server", n and n.server == "127.0.0.1")
check("ssr port", n and n.port == 8388)
check("ssr protocol", n and n.protocol == "auth_aes128_md5")
check("ssr method", n and n.method == "aes-128-cfb")
check("ssr obfs", n and n.obfs == "http_simple")
check("ssr password", n and n.password == "test-password")
check("ssr obfs_param", n and n.obfs_param == "download.windowsupdate.com")
check("ssr name", n and n.name == "测试节点")
check("ssr group", n and n.group == "测试组")

-- ---------- 订阅解析（URI 列表含 ssr） ----------
local res = parser.parse(link .. "\nvless://uuid1@1.1.1.1:443#V")
check("parse ssr sub count", res and res.nodes and #res.nodes == 2)
check("parse ssr sub proto", res and res.nodes[1] and res.nodes[1].proto == "ssr")

-- ---------- ssr:// 分享链接回环 ----------
local re = output_uri.to_ssr_uri(n)
check("to_ssr_uri returns link", re and re:sub(1, 6) == "ssr://")
local n2 = parser.parse_uri(re)
check("ssr roundtrip proto", n2 and n2.proto == "ssr")
check("ssr roundtrip server", n2 and n2.server == "127.0.0.1")
check("ssr roundtrip port", n2 and n2.port == 8388)
check("ssr roundtrip method", n2 and n2.method == "aes-128-cfb")
check("ssr roundtrip password", n2 and n2.password == "test-password")
check("ssr roundtrip protocol", n2 and n2.protocol == "auth_aes128_md5")
check("ssr roundtrip obfs", n2 and n2.obfs == "http_simple")
check("ssr roundtrip obfs_param", n2 and n2.obfs_param == "download.windowsupdate.com")
check("ssr roundtrip name", n2 and n2.name == "测试节点")
check("ssr roundtrip group", n2 and n2.group == "测试组")

-- ---------- Clash.Meta / Mihomo 输出 ----------
local cm = output.generate({ n }, "clashmeta")
check("clashmeta type ssr", cm and cm:find("type: ssr") ~= nil)
check("clashmeta cipher", cm and cm:find("cipher: aes%-128%-cfb") ~= nil)
check("clashmeta password", cm and cm:find("password: test%-password") ~= nil)
check("clashmeta protocol", cm and cm:find("protocol: auth_aes128_md5") ~= nil)
check("clashmeta obfs", cm and cm:find("obfs: http_simple") ~= nil)
check("clashmeta obfs-param", cm and cm:find("obfs%-param: download%.windowsupdate%.com") ~= nil)

-- ---------- Shadowrocket（base64 URI）输出包含 ssr:// ----------
local shr = output.generate({ n }, "shadowrocket")
check("shadowrocket has ssr", shr and util.base64_decode(shr):find("ssr://") ~= nil)

-- ---------- Loon 保留 SSR，Surge 丢弃 ----------
local loon = output.generate({ n }, "loon")
check("loon has ssr", loon and loon:find("ssr, 127%.0%.0%.1, 8388") ~= nil)
check("loon encrypt-method", loon and loon:find("encrypt%-method=aes%-128%-cfb") ~= nil)
check("loon protocol", loon and loon:find("protocol=auth_aes128_md5") ~= nil)
local surge = output.generate({ n }, "surge")
check("surge drops ssr", surge and surge:find("127%.0%.0%.1") == nil)

-- ---------- sing-box / V2Ray 丢弃 SSR ----------
local sb = output.generate({ n }, "singbox")
check("singbox drops ssr", sb and util.json_decode(sb) and #util.json_decode(sb).outbounds == 0)
local v2 = output.generate({ n }, "v2ray")
check("v2ray drops ssr", v2 and util.json_decode(v2) and #util.json_decode(v2).outbounds == 0)

-- ---------- 最小 ssr（无参数，默认 origin/plain） ----------
local minimal = parser.parse_uri("ssr://" .. util.base64_encode("1.2.3.4:80:origin:aes-256-cfb:plain:" .. util.base64_encode("p")))
check("ssr minimal", minimal and minimal.proto == "ssr" and minimal.server == "1.2.3.4" and minimal.password == "p")

-- ---------- base64url 参数解码回退 ----------
local b64u = util.base64_url_encode("香港节点")
check("base64url bare", b64u == "6aaZ5riv6IqC54K5")
check("base64url roundtrip", util.base64_url_decode(b64u) == "香港节点")

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)