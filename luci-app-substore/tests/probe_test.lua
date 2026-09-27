-- probe_test.lua — 节点探测模块单元测试
-- 用法：lua5.1 tests/probe_test.lua

package.path = "./root/usr/share/?.lua;" .. package.path

local probe = require("substore.probe")

local passed, failed = 0, 0
local function check(name, cond)
	if cond then passed = passed + 1; print("PASS " .. name)
	else failed = failed + 1; print("FAIL " .. name) end
end

-- ---------- 解析函数 ----------
check("parse_ping time", probe.parse_ping("64 bytes from 1.1.1.1: seq=0 ttl=54 time=12.345 ms") == 12.345)
check("parse_ping loss", probe.parse_ping("100% packet loss") == nil)
check("parse_ping empty", probe.parse_ping("") == nil)
check("parse_delta ok", math.abs((probe.parse_delta("100.00 100.05") or 0) - 50) < 1)
check("parse_delta empty", probe.parse_delta("") == nil)
check("parse_delta single", probe.parse_delta("100.00") == nil)

-- ---------- 注入防护（在启动子进程前被拒绝，返回 nil）----------
check("ping empty host", probe.ping("") == nil)
check("ping injection", probe.ping("1.1.1.1; rm -rf /") == nil)
check("tcping bad port", probe.tcping("1.1.1.1", "abc") == nil)
check("tcping port overflow", probe.tcping("1.1.1.1", 99999) == nil)
check("url injection", probe.url_test("example.com; touch /tmp/x", 80) == nil)

-- ---------- 本地回环 ----------
check("ping loopback numeric", type(probe.ping("127.0.0.1")) == "number")
check("tcping closed port nil", probe.tcping("127.0.0.1", 1) == nil)
check("url closed port nil", probe.url_test("127.0.0.1", 1) == nil)

-- ---------- 批量探测结果结构 ----------
local r = probe.probe({
	{ name = "a", server = "127.0.0.1", port = 80 },
	{ name = "bad", server = "bad host", port = 80 },
	{ name = "b", server = "127.0.0.1", port = 1 },
}, "ping")
check("probe returns 3 results", #r == 3)
check("probe name preserved", r[1].name == "a" and r[2].name == "bad" and r[3].name == "b")
check("probe invalid host latency nil", r[2].latency == nil)
check("probe shape fields", r[1].server == "127.0.0.1" and r[1].port == 80)

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
