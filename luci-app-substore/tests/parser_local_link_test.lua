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

-- ---------- 结果 ----------
print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
