-- parser_local_link_test.lua — 局域网订阅链接解析单元测试
-- 用法：lua5.1 tests/parser_local_link_test.lua

package.path = "./root/usr/share/?.lua;" .. package.path

local parser = require("substore.parser")

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

-- ---------- 局域网链接检测 ----------
local local_url_1 = "http://192.168.5.15:31013/arthur/download/FeijiCloud?target=ClashMeta"
local local_url_2 = "http://192.168.1.100:8080/api/subscription?name=MySub&target=Surge"
local local_url_3 = "https://example.com/download" -- 非局域网，应该不识别

check("detect local link 192.168", parser.detect_local_link(local_url_1) ~= nil)
check("detect local link 192.168.1", parser.detect_local_link(local_url_2) ~= nil)
check("detect non-local link", parser.detect_local_link(local_url_3) == nil)

-- ---------- 解析局域网链接 ----------
local result1 = parser.parse_local_link(local_url_1)
check("parse_local_link host", result1 and result1.host == "192.168.5.15")
check("parse_local_link port", result1 and result1.port == "31013")
check("parse_local_link path", result1 and result1.path == "/arthur/download/FeijiCloud")
check("parse_local_link target", result1 and result1.target == "ClashMeta")
check("parse_local_link name", result1 and result1.name == "FeijiCloud")
check("parse_local_link user", result1 and result1.user == "arthur")

local result2 = parser.parse_local_link(local_url_2)
check("parse_local_link 2 host", result2 and result2.host == "192.168.1.100")
check("parse_local_link 2 port", result2 and result2.port == "8080")
check("parse_local_link 2 target", result2 and result2.target == "Surge")
check("parse_local_link 2 name", result2 and result2.name == "MySub")

-- 测试带查询参数的链接
local local_url_3 = "http://10.0.0.5:9000/sub?target=SingBox&name=TestSub&uid=user123"
local result3 = parser.parse_local_link(local_url_3)
check("parse_local_link 10.0.0", result3 and result3.host == "10.0.0.5")
check("parse_local_link target SingBox", result3 and result3.target == "SingBox")
check("parse_local_link name param", result3 and result3.name == "TestSub")
check("parse_local_link user param", result3 and result3.user == "user123")

-- ---------- L16：无路径、query 直接跟在 authority 后面 ----------
-- 旧模式 `^([^/]*)` 会把 "host?target=…" 整串当成 authority：
-- host 变成 "host?target=…"，query 里的 target/name/uid 全部丢失。
local q_url = "http://192.168.5.15:31013?target=ClashMeta&name=Foo"
local q = parser.parse_local_link(q_url)
check("no-path query host", q and q.host == "192.168.5.15")
check("no-path query port", q and q.port == "31013")
check("no-path query target kept", q and q.target == "ClashMeta")
check("no-path query name kept", q and q.name == "Foo")
check("no-path query path empty", q and q.path == "")

-- 带 userinfo 的 authority：host 不能被 "user:pw@" 污染（detect_local_link 一直会剥）
local u_url = "http://user:pw@192.168.5.15:31013/arthur/download/X?target=ClashMeta"
local u = parser.parse_local_link(u_url)
check("userinfo stripped host", u and u.host == "192.168.5.15")
check("userinfo stripped port", u and u.port == "31013")
check("userinfo stripped path", u and u.path == "/arthur/download/X")
check("userinfo stripped target", u and u.target == "ClashMeta")

-- ---------- L17：IPv6 内网判定必须展开后比较 ----------
-- `::1` / `0::1` / `0000::1` / `0:0:0:0:0:0:0:1` 是同一个地址的不同写法。
-- 旧实现比字符串前缀，`[0::1]` 被判成公网（SSRF 防护失效）。
local function is_local(u) return parser.detect_local_link(u) ~= nil end
check("v6 loopback ::1", is_local("http://[::1]:8080/"))
check("v6 loopback 0::1", is_local("http://[0::1]:8080/"))
check("v6 loopback 0000::1", is_local("http://[0000::1]:8080/"))
check("v6 loopback expanded", is_local("http://[0:0:0:0:0:0:0:1]/"))
check("v6 unspecified ::", is_local("http://[::]/"))
check("v6 unspecified 0::", is_local("http://[0::]/"))
check("v6 ula fc00::1", is_local("http://[fc00::1]/"))
check("v6 ula fd12:3456::1", is_local("http://[fd12:3456::1]/"))
check("v6 link-local fe80::1", is_local("http://[fe80::1]/"))
check("v6 link-local with zone", is_local("http://[fe80::1%25eth0]/"))
check("v6 mapped loopback", is_local("http://[::ffff:127.0.0.1]/"))
check("v6 mapped private", is_local("http://[::ffff:10.0.0.1]/"))
-- 公网地址不能被误判为内网（否则正常订阅链接会被 SSRF 防护拦下）
check("v6 public 2001:db8::1", not is_local("http://[2001:db8::1]/"))
check("v6 public 2606:4700::1111", not is_local("http://[2606:4700::1111]/"))
check("v6 mapped public", not is_local("http://[::ffff:8.8.8.8]/"))
check("v6 public fd-prefix neighbour", not is_local("http://[fe00::1]/"))

-- ---------- L18：纯空白 / 只有 BOM 的内容 ----------
-- detect 会 trim 并去 BOM 后判为 empty，而 parse 只挡了完全空串，
-- 于是「全是空白」的订阅会掉到末尾报「无法识别的订阅格式」（误导）。
for _, blank in ipairs({ "", "   ", "\n\t ", "\239\187\191", "\239\187\191  \n" }) do
	local bres, berr = parser.parse(blank)
	check("blank content is empty format", bres ~= nil and bres.format == "empty"
		and #bres.nodes == 0 and berr == nil)
end

-- ---------- 结果 ----------
print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
