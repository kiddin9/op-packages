-- network_security_test.lua — 网络安全与健壮性修复（L10 / L11 / L12 / L14）回归测试
-- 用法：lua5.1 tests/network_security_test.lua
--
-- 覆盖本轮修复：
--   L10  http.check_public 在 DNS 解析失败时改为 fail-closed
--   L11  http.parse_url 校验端口范围（1-65535）
--   L12  probe.safe_host 拒绝以 "-" 开头的主机名（busybox getopt 选项注入）
--   L14  http.fetch_curl 在**每一条**退出路径上清理 /tmp 临时文件
--
-- 全部用例不触网：需要子进程的地方一律用 io.popen / os.execute 替身。

package.path = "./root/usr/share/?.lua;" .. package.path

local util = require("substore.util")
local http = require("substore.http")
local probe = require("substore.probe")

local passed, failed = 0, 0
local function check(name, cond)
	if cond then passed = passed + 1; print("PASS " .. name)
	else failed = failed + 1; print("FAIL " .. name) end
end

-- ---------- 子进程替身 ----------
-- probe / http 都在**调用时**查全局 io.popen、os.execute，替换即可生效。
local real_popen, real_execute = io.popen, os.execute

-- 记录被启动的命令行，返回一个「输出固定」的假文件句柄
local spawned
local function spy_popen(output)
	spawned = {}
	local out = output or ""
	io.popen = function(cmd)
		spawned[#spawned + 1] = cmd
		return { read = function() return out end, close = function() end }
	end
end
local function restore_popen() io.popen = real_popen end

-- ---------- L10：DNS 解析失败必须 fail-closed ----------
-- .invalid 是 RFC 2606 保留 TLD，保证解析不出 IP。
-- 修复前这里是 fail-open（放行），于是 127.0.0.1.nip.io 这类「公网可解析到内网」
-- 的域名只要本机这一刻解析失败（nixio 缺失 / 解析器故障 / 超时）就能绕过全部
-- SSRF 检查，而 curl 自己仍会把它解析到 127.0.0.1 并连上去。
local ok10, reason10 = http.check_public("no-such-host.invalid")
check("L10 unresolvable host rejected", ok10 == false)
check("L10 unresolvable host reason", reason10 == "无法解析目标主机名")

-- 数值型内网地址仍然被拦（与 DNS 无关的分支，确保没有把检查整体关掉）
check("L10 loopback still rejected", http.check_public("127.0.0.1") == false)
check("L10 private still rejected", http.check_public("10.0.0.1") == false)
check("L10 ipv6 loopback still rejected", http.check_public("::1") == false)
-- 合法公网字面量仍然放行（不依赖 DNS）
check("L10 public literal still allowed", http.check_public("1.1.1.1") == true)

-- ---------- L11：parse_url 端口范围 ----------
-- `(%d+)` 只保证是数字，`:0` 与 `:99999` 都能通过；这两个端口连不出去，
-- 下载必然失败，却会先经过一轮 DNS/SSRF 检查，报出「连接失败」这种指错方向的原因。
check("L11 port 0 rejected", http.parse_url("http://example.com:0/") == nil)
check("L11 port 65536 rejected", http.parse_url("http://example.com:65536/") == nil)
check("L11 port 99999 rejected", http.parse_url("http://example.com:99999/") == nil)
check("L11 port 1 accepted", (http.parse_url("http://example.com:1/") or {}).port == "1")
check("L11 port 65535 accepted", (http.parse_url("http://example.com:65535/") or {}).port == "65535")
check("L11 default port 80 accepted", (http.parse_url("http://example.com/") or {}).port == "80")
check("L11 https default port 443 accepted", (http.parse_url("https://example.com/") or {}).port == "443")
-- IPv6 字面量分支走的是另一条赋值路径，同样要校验
check("L11 ipv6 bad port rejected", http.parse_url("http://[::1]:0/") == nil)
check("L11 ipv6 good port accepted", (http.parse_url("http://[::1]:8080/") or {}).port == "8080")

-- ---------- L12：以 "-" 开头的主机名 ----------
-- 命令形如 `ping -c 1 -W 2 <host>`；host="--help" 会被 busybox 的 getopt 当成**选项**。
-- util.shq 的引号由 shell 剥掉，getopt 看到的仍是 -x，挡不住。
-- 合法主机名（RFC 1123 首字符为字母或数字）与 IP 都不会以 "-" 开头。
--
-- 断言方式：替身记录被启动的命令行 —— 修复前会真的启动子进程（spawned 非空），
-- 修复后 safe_host 提前返回 nil，一个进程都不起。
spy_popen("")
check("L12 ping dash host rejected", probe.ping("-c") == nil)
check("L12 ping dash host spawns nothing", #spawned == 0)
restore_popen()

spy_popen("")
check("L12 tcping dash host rejected", probe.tcping("--help", 80) == nil)
check("L12 tcping dash host spawns nothing", #spawned == 0)
restore_popen()

spy_popen("")
check("L12 url_test dash host rejected", probe.url_test("-x", 80) == nil)
check("L12 url_test dash host spawns nothing", #spawned == 0)
restore_popen()

-- 批量探测走的是 build_job，同样要拦住
spy_popen("")
local r12 = probe.probe({ { name = "a", server = "-c", port = 80 } }, "ping")
check("L12 probe dash host latency nil", r12[1] and r12[1].latency == nil)
check("L12 probe dash host spawns nothing", #spawned == 0)
restore_popen()

-- 替身本身有效：合法主机名必须真的启动子进程（否则上面的断言是假阳性）
spy_popen("")
probe.ping("127.0.0.1")
check("L12 valid host still spawns", #spawned == 1)
restore_popen()

-- 单测一下校验边界：只有开头是 "-" 才拒绝，中间的 "-" 是合法主机名字符
spy_popen("")
probe.ping("my-host.example.com")
check("L12 interior dash still allowed", #spawned == 1)
restore_popen()

-- ---------- L14：fetch_curl 的临时文件清理 ----------
-- 固定随机标记，让测试能预先造出与实现完全一致的文件名。
local real_rnd = util.rnd_hex
util.rnd_hex = function() return "TESTTAG" end
os.execute = function() return 0 end -- have("curl") 恒真 → detect_tool() 选 curl

-- 注意文件名：hdr / errf 是在 tmp 之上再拼后缀，而 tmp 本身以 ".tmp" 结尾，
-- 所以实际是 "...._0.tmp.hdr" / "...._0.tmp.err"（与实现逐字一致）。
local TMP = "/tmp/substore_dl_TESTTAG_0"
local HDR = TMP .. ".tmp.hdr"
local ERRF = TMP .. ".tmp.err"
local function touch(path, data)
	local f = assert(io.open(path, "wb"))
	f:write(data or "")
	f:close()
end
local function exists(path)
	local f = io.open(path, "rb")
	if f then f:close(); return true end
	return false
end
local function clear_tmp()
	os.remove(TMP .. ".tmp"); os.remove(HDR); os.remove(ERRF)
end

-- 模拟 curl 真实写盘：从命令行里解析出 -o / -D / 2> 的目标路径并把文件建出来。
-- 这一步是必需的 —— 若替身只返回一个输出字符串而不落盘，那么「失败后 /tmp 无残留」
-- 在**修复前后都成立**（文件从没被创建过），断言恒真，等于没测。
local function spy_curl(code, errtext, hdrdata)
	spawned = {}
	io.popen = function(cmd)
		spawned[#spawned + 1] = cmd
		local o = cmd:match("%-o '([^']+)'")
		local d = cmd:match("%-D '([^']+)'")
		local e = cmd:match("2>'([^']+)'")
		if o then touch(o, "partial body") end
		if d then touch(d, hdrdata or "") end
		if e then touch(e, errtext or "") end
		return { read = function() return code end, close = function() end }
	end
end

-- 失败路径 1：curl 报错（http_code=000）。修复前直接 return，三个文件都留在 tmpfs 上。
clear_tmp()
spy_curl("000", "curl: (7) Failed to connect")
local body14, _, err14 = http.download("http://1.1.1.1/sub")
restore_popen()
check("L14 failure reported", body14 == nil and err14 == "curl: (7) Failed to connect")
check("L14 000 path removes .tmp", not exists(TMP .. ".tmp"))
check("L14 000 path removes .hdr", not exists(HDR))
check("L14 000 path removes .err", not exists(ERRF))

-- 失败路径 2：3xx 但响应头里没有 Location。修复前同样把文件留在 /tmp。
clear_tmp()
spy_curl("302", "", "HTTP/1.1 302 Found\r\n")
local body14b, _, err14b = http.download("http://1.1.1.1/sub")
restore_popen()
check("L14 no-Location reported", body14b == nil and err14b == "重定向无 Location")
check("L14 no-Location removes .tmp", not exists(TMP .. ".tmp"))
check("L14 no-Location removes .hdr", not exists(HDR))
check("L14 no-Location removes .err", not exists(ERRF))

-- 失败路径 3：HTTP 4xx/5xx。修复前把文件留在 /tmp。
clear_tmp()
spy_curl("500", "", "HTTP/1.1 500 Error\r\n")
local body14c, _, err14c = http.download("http://1.1.1.1/sub")
restore_popen()
check("L14 http-error reported", body14c == nil and err14c == "HTTP 错误 500")
check("L14 http-error removes .tmp", not exists(TMP .. ".tmp"))
check("L14 http-error removes .hdr", not exists(HDR))
check("L14 http-error removes .err", not exists(ERRF))

-- 替身本身有效：证明上面的「无残留」不是空断言 —— 若清理逻辑被移除，文件必须还在。
-- 直接调用一次「不清理」的对照：手工建出文件后不跑 download，断言它们确实可见。
touch(TMP .. ".tmp", "x")
check("L14 control: files are observable", exists(TMP .. ".tmp"))
clear_tmp()
util.rnd_hex = real_rnd
os.execute = real_execute

print("")
print(passed .. " passed, " .. failed .. " failed")
os.exit(failed == 0 and 0 or 1)
