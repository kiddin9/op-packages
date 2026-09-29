-- security_fixes_test.lua — 安全/健壮性修复的回归测试
-- 用法：lua5.1 tests/security_fixes_test.lua
--
-- 覆盖本轮修复：
--   1. util.shq 单引号转义（string.format("%q") 不是 shell 安全的）
--   2. http.parse_url 剥离 query / fragment（SSRF fail-open 绕过）
--   3. core.save_meta 的 CLEAR 语义（无法表达「清空字段」）
--   4. node 改名：Lua 模式里的 `-` 是惰性量词、`|` 无 alternation
--   5. 模板改名：替换值里的 `%` 必须转义

package.path = "./root/usr/share/?.lua;" .. package.path

local util = require("substore.util")
local http = require("substore.http")
local node = require("substore.node")
local core = require("substore.core")

local passed, failed = 0, 0
local function check(name, cond)
	if cond then passed = passed + 1; print("PASS " .. name)
	else failed = failed + 1; print("FAIL " .. name) end
end

-- ---------- 1. util.shq ----------
-- 关键性质：拼进 shell 命令行后，命令替换不会发生。
-- 用真实的 sh -c 验证，而不是只看字符串长相。
local function sh_echo(s)
	local f = os.tmpname()
	-- 两层转义：外层 shq 把「echo <内层 shq(s)>」整体交给 sh -c，
	-- 内层 shq 才是被测对象。若 shq 失效，内层替换就会真的执行。
	os.execute("sh -c " .. util.shq("echo " .. util.shq(s)) .. " > " .. util.shq(f))
	local fh = io.open(f, "r")
	local out = fh and fh:read("*a") or ""
	if fh then fh:close() end
	os.remove(f)
	return (out:gsub("\n$", ""))
end

check("shq wraps in single quotes", util.shq("abc") == "'abc'")
check("shq escapes embedded single quote", util.shq("a'b") == "'a'\\''b'")
check("shq nil becomes empty", util.shq(nil) == "''")
check("shq number coerced", util.shq(42) == "'42'")

-- 双引号包裹（format("%q") 的做法）在 /bin/sh 里仍会做 $() 与 `` 替换
check("shq neutralizes $() substitution", sh_echo("$(echo pwned)") == "$(echo pwned)")
check("shq neutralizes backtick substitution", sh_echo("`echo pwned`") == "`echo pwned`")
check("shq neutralizes quote breakout", sh_echo("'; echo pwned; '") == "'; echo pwned; '")
check("shq neutralizes semicolon", sh_echo("a; echo pwned") == "a; echo pwned")

-- ---------- 2. http.parse_url：query / fragment ----------
-- 这些 URL 的 host 是回环/内网，必须解析成回环/内网地址，
-- 交给 check_public 时才会被拦下；解析成 "127.0.0.1?a=1" 会因 DNS 失败而放行。
local u1 = http.parse_url("http://127.0.0.1?a=1")
check("query stripped from host", u1 and u1.host == "127.0.0.1")
check("query stripped keeps default port", u1 and u1.port == "80")

local u2 = http.parse_url("http://127.0.0.1#frag")
check("fragment stripped from host", u2 and u2.host == "127.0.0.1")

local u3 = http.parse_url("http://127.0.0.1:8080/path?x=1#y")
check("port survives path/query/fragment", u3 and u3.host == "127.0.0.1" and u3.port == "8080")

local u4 = http.parse_url("http://evil@127.0.0.1/")
check("userinfo stripped", u4 and u4.host == "127.0.0.1")

local u5 = http.parse_url("http://user:pw@127.0.0.1:8080/")
check("userinfo with password stripped", u5 and u5.host == "127.0.0.1" and u5.port == "8080")

local u6 = http.parse_url("https://example.com/x")
check("https default port", u6 and u6.host == "example.com" and u6.port == "443")

local u7 = http.parse_url("http://[::1]:8080/x")
check("ipv6 literal parsed", u7 and u7.host == "::1" and u7.port == "8080")

local u8 = http.parse_url("ftp://example.com/")
check("non-http scheme rejected", u8 == nil)

-- ---------- 3. core.save_meta 的 CLEAR ----------
local tmp = os.tmpname() .. "_substore_sec"
os.remove(tmp)
core.DATA_DIR = tmp
core.LIST_FILE = tmp .. "/subscriptions.json"
core.NODES_DIR = tmp .. "/nodes"
core.ensure_dirs()

local id = core.add("sec", "http://example.com/sub")
check("add returns id", type(id) == "string")

core.save_meta(id, { upload = 100, download = 200, total = 300, expire = 400 })
local m1 = core.get(id)
check("save_meta writes fields", m1.upload == 100 and m1.expire == 400)

-- 传 nil 无法表达删除：pairs 永远不会给出 nil 值
core.save_meta(id, { upload = nil, download = nil, total = nil, expire = nil })
local m2 = core.get(id)
check("nil patch cannot clear (documents why CLEAR exists)", m2.upload == 100)

core.save_meta(id, {
	upload = core.CLEAR, download = core.CLEAR,
	total = core.CLEAR, expire = core.CLEAR,
})
local m3 = core.get(id)
check("CLEAR removes upload", m3.upload == nil)
check("CLEAR removes download", m3.download == nil)
check("CLEAR removes total", m3.total == nil)
check("CLEAR removes expire", m3.expire == nil)
check("CLEAR keeps other fields", m3.name == "sec" and m3.url == "http://example.com/sub")

os.execute("rm -rf " .. util.shq(tmp))

-- ---------- 4. 改名：`-` 与 `|` ----------
local function rename_one(name, rules)
	local ns = node.rename_with_rules({ { name = name, proto = "vmess", server = "1.2.3.4", port = 443 } }, rules)
	return ns[1].name
end

-- Lua 模式里 `-` 是惰性量词：不转义则 "Node-42" 永远匹配不上 "Node-(%d+)"
local r1 = { { type = "regex", pattern = "Node-(\\d+)", replacement = "N$1" } }
check("dash in pattern is literal", rename_one("Node-42", r1) == "N42")
check("dash pattern still matches without dash", rename_one("Node42", r1) == "Node42")

-- Lua 模式没有 alternation：顶层 `|` 必须拆成多条候选依次替换
local r2 = { { type = "regex", pattern = "^HK-|^US-", replacement = "R-" } }
check("alternation first branch", rename_one("HK-a", r2) == "R-a")
check("alternation second branch", rename_one("US-b", r2) == "R-b")
check("alternation non-matching branch untouched", rename_one("JP-c", r2) == "JP-c")

-- 分组内的 `|` 不支持（Lua 的 () 只是捕获，没有「或」语义）。
-- 关键是不能把它当顶层 | 拆开：拆开会产生 `^(HK` / `US` / `JP)%-(.*)$`
-- 这种残缺模式，三段都匹配不上；此处只要求「不误伤」——按字面处理、不匹配。
local r2b = { { type = "regex", pattern = "^(HK|US)-(.*)$", replacement = "R-$2" } }
check("group alternation is literal (unsupported)", rename_one("HK-a", r2b) == "HK-a")
check("group alternation does not corrupt name", rename_one("US-b", r2b) == "US-b")

-- 字符类里的 `|` 是字面字符，不能被当分隔符拆开
local r2c = { { type = "regex", pattern = "^[|]x$", replacement = "PIPE" } }
check("pipe inside class is literal", rename_one("|x", r2c) == "PIPE")

-- 字符类里的 `-` 是范围符号，不能被转义成 %-
local r3 = { { type = "regex", pattern = "^[a-z]+(\\d+)$", replacement = "X$1" } }
check("dash inside class stays a range", rename_one("abc123", r3) == "X123")

-- 反向引用仍然可用
local r4 = { { type = "regex", pattern = "^(.*):(\\d+)$", replacement = "$1" } }
check("backreference still works", rename_one("1.2.3.4:443", r4) == "1.2.3.4")

-- ---------- 5. 模板改名的 % 转义 ----------
local r5 = { { type = "template", template = "[50% OFF] {server}" } }
check("percent preserved in template", rename_one("x", r5) == "[50% OFF] 1.2.3.4")

local r6 = { { type = "template", template = "{name}-{port}" } }
check("template fields substituted", rename_one("zz", r6) == "zz-443")

print("")
print(passed .. " passed, " .. failed .. " failed")
os.exit(failed == 0 and 0 or 1)
