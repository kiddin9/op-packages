-- http_proxy_test.lua — 代理地址校验单元测试
-- 用法：lua5.1 tests/http_proxy_test.lua

package.path = "./root/usr/share/?.lua;" .. package.path

local http = require("substore.http")

local passed, failed = 0, 0
local function check(name, cond)
	if cond then passed = passed + 1; print("PASS " .. name)
	else failed = failed + 1; print("FAIL " .. name) end
end

-- ---------- parse_proxy 合法输入 ----------
check("empty proxy", http.parse_proxy("") == "")
check("http proxy", http.parse_proxy("http://192.168.5.1:8080") == "http://192.168.5.1:8080")
check("socks5 proxy", http.parse_proxy("socks5://192.168.5.1:1080") == "socks5://192.168.5.1:1080")
check("socks5h proxy", http.parse_proxy("socks5h://10.0.0.1:1080") == "socks5h://10.0.0.1:1080")
check("https proxy", http.parse_proxy("https://proxy.example.com:8443") == "https://proxy.example.com:8443")
check("auth proxy", http.parse_proxy("http://user:pass@192.168.5.1:8080") == "http://user:pass@192.168.5.1:8080")
check("trim spaces", http.parse_proxy("  socks5://192.168.5.1:1080  ") == "socks5://192.168.5.1:1080")
check("strip path", http.parse_proxy("http://192.168.5.1:8080/") == "http://192.168.5.1:8080")

-- ---------- parse_proxy 非法输入 ----------
check("bad scheme", http.parse_proxy("ftp://x:80") == nil)
check("no scheme", http.parse_proxy("192.168.5.1:1080") == nil)
check("bad port", http.parse_proxy("http://x:99999") == nil)
check("port zero", http.parse_proxy("http://x:0") == nil)
check("injection host", http.parse_proxy("http://192.168.5.1:1080; rm -rf /") == nil)
check("injection userinfo", http.parse_proxy("http://user;ls@192.168.5.1:1080") == nil)
local _, e = http.parse_proxy("ftp://x:80")
check("err is string", type(e) == "string")

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)