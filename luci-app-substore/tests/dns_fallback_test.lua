-- dns_fallback_test.lua — [2.6.12-r1] DNS 解析回退与连接时对端校验回归测试
-- 用法：lua5.1 tests/dns_fallback_test.lua
--
-- 背景（用户实测的回归）：[2.6.8-r1] 把 check_public 里「解析不出 IP」一律
-- fail-closed 之后，在**缺少 luci-lib-nixio** 的设备上 resolve() 恒返回 nil，
-- 于是所有域名订阅都报「无法解析目标主机名」——而 curl 自带 libc 解析器，
-- 2.6.7-r1 上同样的订阅是能正常下载的。
--
-- 根因：resolve() 只有 nixio 一条路，「本机没有解析手段」和「这个域名解析不出来」
-- 被合并成了同一个 nil，而两者的处置完全相反。
--
-- 覆盖：
--   A  nslookup 回退：nixio 不可用时改用 busybox nslookup 解析
--   B  nslookup 输出的 Server/Address 段**不能**被当成解析结果
--   C  有解析手段但解析失败（NXDOMAIN）→ 仍然 fail-closed
--   D  本机完全无解析手段 → 放行，但标记 unverified
--   E  连接时对端校验：curl 回报的 %{remote_ip} 为内网 → 拒绝并清理临时文件
--   F  unverified 且拿不到对端 IP → 拒绝（「无法校验」不等于「放行」）
--   G  走代理时不校验对端（%{remote_ip} 是代理地址，多半就在内网）
--   H  unverified + wget 后端 → 拒绝，且不发起下载（wget 拿不到对端地址）
--   H2 对照：有解析能力时 wget 后端照常工作
--
-- 全部用例不触网：nixio / nslookup / curl 一律用替身。

package.path = "./root/usr/share/?.lua;" .. package.path

local util = require("substore.util")
local http = require("substore.http")
local msg = require("substore.msg")

local passed, failed = 0, 0
local function check(name, cond)
	if cond then passed = passed + 1; print("PASS " .. name)
	else failed = failed + 1; print("FAIL " .. name) end
end

local real_popen, real_execute = io.popen, os.execute
local real_try = util.try_require
local real_rnd = util.rnd_hex

local function restore()
	io.popen, os.execute, util.try_require, util.rnd_hex =
		real_popen, real_execute, real_try, real_rnd
end

-- 让 resolve() 走 nslookup 分支：nixio 取不到、nslookup 命令存在、输出固定。
local spawned
local function stub_nslookup(output)
	spawned = {}
	util.try_require = function() return nil end
	os.execute = function() return 0 end -- have("nslookup") 恒真
	io.popen = function(cmd)
		spawned[#spawned + 1] = cmd
		return { read = function() return output end, close = function() end }
	end
end

-- ---------- A：nslookup 回退 ----------
-- Server 段故意写 8.8.8.8（公网）、应答段写内网地址：
-- 若实现误把 Server 段的 Address 也当解析结果，就会因为「有一个公网 IP」
-- 而放行 —— 这条断言因此能真正区分对错，不是恒真。
local NS_MIXED = "Server:\t\t8.8.8.8\nAddress:\t8.8.8.8:53\n\n" ..
	"Name:\tintranet.example\nAddress: 192.168.1.10\n"

stub_nslookup(NS_MIXED)
local okA, rA = http.check_public("intranet.example")
restore()
check("A nslookup fallback used", #spawned == 1)
check("A nslookup command quotes host", spawned[1] == "nslookup 'intranet.example' 2>/dev/null")
check("A domain resolving to private rejected", okA == false)
check("A reason is private-address", rA == "Target resolves only to private/reserved addresses")

-- 应答段是公网地址 → 放行
local NS_PUBLIC = "Server:\t\t192.168.1.1\nAddress:\t192.168.1.1:53\n\n" ..
	"Name:\texample.com\nAddress: 93.184.216.34\n"
stub_nslookup(NS_PUBLIC)
local okA2 = http.check_public("example.com")
restore()
check("A public domain allowed via nslookup", okA2 == true)

-- 多 A 记录：只要有一个公网地址就放行（与 nixio 分支同语义）
local NS_MULTI = "Server:\t\t192.168.1.1\nAddress:\t192.168.1.1:53\n\n" ..
	"Name:\tmulti.example\nAddress: 10.0.0.5\nAddress: 93.184.216.34\n"
stub_nslookup(NS_MULTI)
local okA3 = http.check_public("multi.example")
restore()
check("A multi-A with one public allowed", okA3 == true)

-- IPv6 应答：%zone 后缀必须去掉，否则 fe80::1%eth0 匹配不上 link-local 前缀
local NS_V6 = "Server:\t\t192.168.1.1\nAddress:\t192.168.1.1:53\n\n" ..
	"Name:\tv6.example\nAddress: fe80::1%eth0\n"
stub_nslookup(NS_V6)
local okA4, rA4 = http.check_public("v6.example")
restore()
check("A ipv6 zone suffix stripped", okA4 == false and rA4 == "Target resolves only to private/reserved addresses")

-- ---------- B：Server 段的 Address 不是解析结果 ----------
-- 解析失败时 busybox 只把错误写到 stderr，stdout 里只有 Server/Address 段。
-- 应答段为空 → 必须判为「解析不出来」，而不是把 8.8.8.8（DNS 服务器自己）当成结果。
local NS_NXDOMAIN = "Server:\t\t8.8.8.8\nAddress:\t8.8.8.8:53\n\n" ..
	"** server can't find nope.invalid: NXDOMAIN\n"
stub_nslookup(NS_NXDOMAIN)
local okB, rB = http.check_public("nope.invalid")
restore()
check("B server-block address not used as answer", okB == false)
check("B empty answer is unresolvable", rB == "Cannot resolve the target hostname")

-- 空输出（nslookup 不存在 / 立刻失败）同样算解析不出来
stub_nslookup("")
local okB2, rB2 = http.check_public("nope.invalid")
restore()
check("B empty output is unresolvable", okB2 == false and rB2 == "Cannot resolve the target hostname")

-- ---------- C：有解析手段但解析失败 → fail-closed ----------
-- 这是 [2.6.8-r1] 引入的行为，必须保留：127.0.0.1.nip.io 这类
-- 「公网可解析到内网」的域名，只要本机解析不出来就能绕过全部检查，
-- 而 curl 自己仍会把它解析到 127.0.0.1 并连上去。
stub_nslookup(NS_NXDOMAIN)
local okC, rC, unC = http.check_public("127.0.0.1.nip.io")
restore()
check("C unresolvable with resolver rejected", okC == false)
check("C unresolvable reason", rC == "Cannot resolve the target hostname")
check("C not marked unverified", unC == nil)

-- ---------- D：本机完全无解析手段 → 放行 + unverified ----------
-- os.execute 恒返回 1 → command -v 一律「找不到」→ nixio 与 nslookup 都没有。
util.try_require = function() return nil end
os.execute = function() return 1 end
spawned = {}
io.popen = function(cmd) spawned[#spawned + 1] = cmd; return nil end
local okD, rD, unD = http.check_public("example.com")
local spawnedD = #spawned
restore()
check("D no resolver allows", okD == true)
check("D reason explains fallback", rD == "No local DNS resolution; the peer address will be verified at connect time")
check("D marked unverified", unD == true)
check("D spawns no resolver process", spawnedD == 0)

-- 无解析手段也不能放过 IP 字面量与 localhost（这些分支不经过 DNS）
util.try_require = function() return nil end
os.execute = function() return 1 end
io.popen = function() return nil end
local dLit = http.check_public("127.0.0.1")
local dLit6 = http.check_public("::1")
local dName = http.check_public("localhost")
local dPub = http.check_public("1.1.1.1")
restore()
check("D loopback literal still rejected", dLit == false)
check("D ipv6 loopback still rejected", dLit6 == false)
check("D localhost name still rejected", dName == false)
check("D public literal still allowed", dPub == true)

-- ---------- E/F/G：连接时对端校验 ----------
-- fetch_curl 通过 -w 取 %{http_code} 与 %{remote_ip}，据此复核真正连上的地址。
-- 替身按命令行里 -o/-D/2> 的目标把文件建出来，让「失败后 /tmp 无残留」
-- 成为真断言（文件确实被创建过）。
util.rnd_hex = function() return "DNSTAG" end
local TMP = "/tmp/substore_dl_DNSTAG_0"
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

-- curl 替身：code 是 -w 的完整输出（形如 "200 93.184.216.34"）
local function spy_curl(code)
	os.execute = function() return 0 end -- have("curl") 恒真 → 选 curl 后端
	io.popen = function(cmd)
		local o = cmd:match("%-o '([^']+)'")
		local d = cmd:match("%-D '([^']+)'")
		local e = cmd:match("2>'([^']+)'")
		if o then touch(o, "body") end
		if d then touch(d, "HTTP/1.1 200 OK\r\n") end
		if e then touch(e, "") end
		return { read = function() return code end, close = function() end }
	end
end

local function clear_tmp()
	os.remove(TMP .. ".tmp"); os.remove(HDR); os.remove(ERRF)
end

-- E1：公网对端 → 正常返回
clear_tmp()
spy_curl("200 93.184.216.34")
local bodyE, _, errE = http.download("http://1.1.1.1/sub")
restore()
check("E1 public peer accepted", bodyE == "body" and errE == nil)

-- E2：对端是内网 → 拒绝，且临时文件全部清理
clear_tmp()
spy_curl("200 127.0.0.1")
local bodyE2, _, errE2 = http.download("http://1.1.1.1/sub")
restore()
check("E2 private peer rejected", bodyE2 == nil)
check("E2 reason names the peer ip", errE2 == msg.compose("Target actually connects to a private/reserved address (", "127.0.0.1", ")"))
check("E2 removes .tmp", not exists(TMP .. ".tmp"))
check("E2 removes .hdr", not exists(HDR))
check("E2 removes .err", not exists(ERRF))

-- E3：3xx 的第一跳就连到内网 → 同样拒绝
-- （Location 检查只能拦第二跳，拦不住第一跳本身）
clear_tmp()
spy_curl("302 192.168.1.1")
local bodyE3, _, errE3 = http.download("http://1.1.1.1/sub")
restore()
check("E3 redirect hop private rejected", bodyE3 == nil)
check("E3 reason names the peer ip", errE3 == msg.compose("Target actually connects to a private/reserved address (", "192.168.1.1", ")"))

-- E4：link-local 对端同样拦
clear_tmp()
spy_curl("200 fe80::1")
local bodyE4, _, errE4 = http.download("http://1.1.1.1/sub")
restore()
check("E4 link-local peer rejected", bodyE4 == nil and errE4 ~= nil)

-- E5：对照 —— 替身确实落盘，所以上面的「无残留」不是空断言
clear_tmp()
touch(TMP .. ".tmp", "x")
check("E5 control: temp files are observable", exists(TMP .. ".tmp"))
clear_tmp()

-- F：预检无解析能力（unverified）且拿不到对端 IP → 拒绝。
-- 「无法校验」必须等于「拒绝」，否则这条新的放行路径就是个洞。
util.rnd_hex = function() return "DNSTAG" end
util.try_require = function() return nil end
spy_curl("200") -- 只有状态码，没有对端 IP
os.execute = function(cmd)
	-- have("curl") 为真、have("nslookup") 为假 → 无解析能力 + 用 curl 下载
	if cmd:find("curl", 1, true) then return 0 end
	return 1
end
clear_tmp()
-- 这里必须用**域名**：只有走 resolve() 分支才会得到 unverified=true。
local bodyF, _, errF = http.download("http://example.com/sub")
restore()
check("F unverified without peer ip rejected", bodyF == nil)
check("F reason explains missing peer ip",
	errF == "Cannot verify the target address (no local DNS resolution and no peer IP obtained)")

-- F2：有解析能力时拿不到对端 IP → 不额外拒绝（预检已经查过一轮）
clear_tmp()
spy_curl("200")
local bodyF2, _, errF2 = http.download("http://1.1.1.1/sub")
restore()
check("F2 resolved target without peer ip accepted", bodyF2 == "body" and errF2 == nil)

-- G：走代理时不校验对端（%{remote_ip} 是代理地址，多半就在内网）
clear_tmp()
spy_curl("200 192.168.1.1")
local bodyG, _, errG = http.download("http://1.1.1.1/sub", { proxy = "http://192.168.1.1:1080" })
restore()
check("G proxied private peer accepted", bodyG == "body" and errG == nil)

-- G2：代理参数确实进了 curl 命令行（否则 G 可能是假阳性）
local saw_proxy
os.execute = function() return 0 end
io.popen = function(cmd)
	saw_proxy = cmd:find("%-x 'http://192.168.1.1:1080'", 1) ~= nil
	local o = cmd:match("%-o '([^']+)'")
	local d = cmd:match("%-D '([^']+)'")
	local e = cmd:match("2>'([^']+)'")
	if o then touch(o, "body") end
	if d then touch(d, "HTTP/1.1 200 OK\r\n") end
	if e then touch(e, "") end
	return { read = function() return "200 192.168.1.1" end, close = function() end }
end
clear_tmp()
http.download("http://1.1.1.1/sub", { proxy = "http://192.168.1.1:1080" })
restore()
check("G2 proxy flag passed to curl", saw_proxy == true)

-- ---------- H：unverified + wget 后端 → 拒绝，且不发起下载 ----------
-- curl 后端靠 %{remote_ip} 在连接后复核对端地址；wget 拿不到对端地址，
-- busybox wget 也没有可用的重定向拦截。预检 fail-open 放行之后这条路径上
-- 再无任何校验 —— 与 verify_peer_ip 同处置：校验不了就拒绝，而不是放行。
-- 拒绝还必须发生在 wget **之前**：否则请求已经发出去，拒绝就只是事后补救。
local WGET_TMP = "/tmp/substore_dl_wget_DNSTAGW.tmp"
local execsH = {}
util.rnd_hex = function() return "DNSTAGW" end
util.try_require = function() return nil end
os.execute = function(cmd)
	execsH[#execsH + 1] = cmd
	if cmd:find("command %-v wget") then return 0 end -- 有 wget
	if cmd:find("command %-v") then return 1 end -- 没有 curl / nslookup → 无解析能力
	-- 真正的下载命令：**照常落盘**，模拟一个成功的下载。
	-- 不落盘的话，旧实现会因为「内容为空」而返回 nil，
	-- 断言就在错误的理由上通过，测不出「本该拒绝却把内容交付了」。
	local o = cmd:match("%-O '([^']+)'")
	if o then touch(o, "evilbody") end
	return 0
end
io.popen = function() return nil end
os.remove(WGET_TMP)
local bodyH, _, errH = http.download("http://example.com/sub")
restore()
check("H unverified wget rejected", bodyH == nil)
check("H reason names the wget backend",
	errH == "No local DNS resolution: the wget backend cannot verify the target address and refused the download (install curl and retry)")
local ran_wget = false
for _, c in ipairs(execsH) do
	if c:find("%-O ", 1) then ran_wget = true end
end
check("H wget never invoked", ran_wget == false)
check("H no temp file left", not exists(WGET_TMP))

-- H2：对照 —— 有解析能力（unverified 为 nil）时 wget 后端照常下载，
-- 证明 H 拒绝的是「无法校验」，不是把 wget 后端整个废掉。
local WGET_TMP2 = "/tmp/substore_dl_wget_DNSTAGW2.tmp"
local ran_wget2 = false
util.rnd_hex = function() return "DNSTAGW2" end
util.try_require = function() return nil end
os.execute = function(cmd)
	if cmd:find("command %-v curl") then return 1 end -- 没有 curl
	if cmd:find("command %-v") then return 0 end -- 有 wget / nslookup
	local o = cmd:match("%-O '([^']+)'")
	if o then ran_wget2 = true; touch(o, "wgetbody") end
	return 0
end
io.popen = function() return { read = function() return NS_PUBLIC end, close = function() end } end
os.remove(WGET_TMP2)
local bodyH2, _, errH2 = http.download("http://example.com/sub")
restore()
check("H2 resolved target via wget accepted", bodyH2 == "wgetbody" and errH2 == nil)
check("H2 wget really ran", ran_wget2 == true)
check("H2 no temp file left", not exists(WGET_TMP2))

clear_tmp()
print("")
print(passed .. " passed, " .. failed .. " failed")
os.exit(failed == 0 and 0 or 1)
