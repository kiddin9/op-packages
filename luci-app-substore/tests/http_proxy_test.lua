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

-- ---------- wget 后端代理能力（§12 禁止 silent fallback） ----------
-- busybox wget 只能通过 http_proxy/https_proxy 使用 http(s) 代理；
-- socks* 必须明确报错，而不是丢掉代理直连。
check("wget env empty proxy", http.wget_proxy_env("") == "")
check("wget env nil proxy", http.wget_proxy_env(nil) == "")
local env_http = http.wget_proxy_env("http://192.168.5.1:8080")
check("wget env http proxy", type(env_http) == "string" and env_http:find("http_proxy=", 1, true) ~= nil)
local env_https = http.wget_proxy_env("https://proxy.example.com:8443")
check("wget env https proxy", type(env_https) == "string" and env_https:find("http_proxy=", 1, true) ~= nil)

local e5, m5 = http.wget_proxy_env("socks5://192.168.5.1:1080")
check("wget rejects socks5 (no silent direct)", e5 == nil)
check("wget socks5 err mentions SOCKS5", type(m5) == "string" and m5:find("SOCKS5", 1, true) ~= nil)
local e4 = http.wget_proxy_env("socks4://192.168.5.1:1080")
check("wget rejects socks4", e4 == nil)
local eh = http.wget_proxy_env("socks5h://192.168.5.1:1080")
check("wget rejects socks5h", eh == nil)

-- ---------- 日志脱敏（§39） ----------
check("redact proxy strips credentials",
	http.redact_proxy("http://user:pass@192.168.5.1:8080") == "http://192.168.5.1:8080")
check("redact proxy keeps credentials-free addr",
	http.redact_proxy("socks5://192.168.5.1:1080") == "socks5://192.168.5.1:1080")
check("redact proxy handles garbage", http.redact_proxy("nonsense") == "***")
check("redact proxy handles nil", http.redact_proxy(nil) == "***")

local scrubbed = http.scrub_credentials("curl: (7) failed http://user:pw@example.com/sub?token=abc")
check("scrub removes url credentials", scrubbed:find("user:pw", 1, true) == nil)
check("scrub keeps the rest", scrubbed:find("example.com", 1, true) ~= nil)
check("scrub leaves clean text alone",
	http.scrub_credentials("HTTP 错误 404") == "HTTP 错误 404")

-- ---------- 重定向链复检（§14/§16） ----------
-- 纯函数，不触网：日志文本按 wget -S 的真实输出格式构造
local function chain(...)
	local lines = {}
	for _, loc in ipairs({ ... }) do
		lines[#lines + 1] = "  HTTP/1.1 302 Found"
		lines[#lines + 1] = "  Location: " .. loc
	end
	lines[#lines + 1] = "  HTTP/1.1 200 OK"
	return table.concat(lines, "\n")
end

local BASE = "http://sub.example.com/api/sub"
check("chain public -> public allowed",
	http.validate_redirect_chain(BASE, chain("http://cdn.example.com/a")) == true)
check("chain no redirect allowed",
	http.validate_redirect_chain(BASE, "  HTTP/1.1 200 OK") == true)
check("chain relative location allowed",
	http.validate_redirect_chain(BASE, chain("/other/path")) == true)

-- 公网 → 内网：必须拒绝
local ok1, r1 = http.validate_redirect_chain(BASE, chain("http://127.0.0.1:8080/evil"))
check("chain to 127.0.0.1 rejected", ok1 == false)
check("chain 127.0.0.1 reason set", type(r1) == "string" and #r1 > 0)
check("chain to localhost rejected",
	http.validate_redirect_chain(BASE, chain("http://localhost/evil")) == false)
check("chain to 192.168.1.1 rejected",
	http.validate_redirect_chain(BASE, chain("http://192.168.1.1/evil")) == false)
check("chain to 10.0.0.1 rejected",
	http.validate_redirect_chain(BASE, chain("http://10.0.0.1/evil")) == false)
check("chain to 172.16.0.1 rejected",
	http.validate_redirect_chain(BASE, chain("http://172.16.0.1/evil")) == false)
check("chain to 169.254.169.254 rejected",
	http.validate_redirect_chain(BASE, chain("http://169.254.169.254/latest/meta-data/")) == false)
check("chain to ipv6 loopback rejected",
	http.validate_redirect_chain(BASE, chain("http://[::1]/evil")) == false)
check("chain to ipv6 link-local rejected",
	http.validate_redirect_chain(BASE, chain("http://[fe80::1]/evil")) == false)
-- 协议相对地址（//host/path）主机必须取自 Location，不能被当成同主机路径
check("chain protocol-relative to private rejected",
	http.validate_redirect_chain(BASE, chain("//127.0.0.1/evil")) == false)
check("chain protocol-relative to public allowed",
	http.validate_redirect_chain(BASE, chain("//cdn.example.com/a")) == true)
-- 多跳：只要有一跳不安全就整体拒绝
check("chain multi-hop second hop private rejected",
	http.validate_redirect_chain(BASE,
		chain("http://cdn.example.com/a", "http://192.168.1.1/b")) == false)
check("chain multi-hop all public allowed",
	http.validate_redirect_chain(BASE,
		chain("http://cdn.example.com/a", "http://cdn2.example.com/b")) == true)
-- 非法 Location
check("chain invalid location rejected",
	http.validate_redirect_chain(BASE, chain("ftp://example.com/x")) == false)

-- 用 busybox wget 1.37 `-S` 的真实输出（逐字节捕获）锁定日志格式，
-- 防止上游改变输出格式后校验静默失效
local REAL_LOG = [[Connecting to 127.0.0.1:18080 (127.0.0.1:18080)
  HTTP/1.1 302 Found
  Server: BaseHTTP/0.6 Python/3.14.4
  Date: Tue, 29 Sep 2026 11:42:19 GMT
  Location: http://127.0.0.1:18081/
Connecting to 127.0.0.1:18081 (127.0.0.1:18081)
  HTTP/1.1 200 OK
  Server: BaseHTTP/0.6 Python/3.14.4
  Date: Tue, 29 Sep 2026 11:42:19 GMT
  Content-Length: 11

saving to '/tmp/probe_out.bin'
probe_out.bin        100% |********************************|    11  0:00:00 ETA
]]
check("real wget -S log: private hop rejected",
	http.validate_redirect_chain(BASE, REAL_LOG) == false)

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)