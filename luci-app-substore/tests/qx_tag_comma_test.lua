-- qx_tag_comma_test.lua — QX 节点名含逗号时的整条丢弃回归测试
-- 用法：lua5.1 tests/qx_tag_comma_test.lua
--
-- 缺陷（docs/LEGACY_ISSUES.md 1.5）：`[server_local]` 行是逗号分隔的
-- `key=value` 序列，语法里没有引号 / 转义。节点名 `A,B` 经 one_line 后仍含
-- 逗号，输出成 `..., tag=A,B` —— 按该语法会被读成 `tag=A` 加一个悬空字段，
-- 用户拿到的不是他填的那个名字。QX 对这种行的实际处置未经核实（本机没有
-- Quantumult X 可实测），因此按推荐方案 B 整条丢弃：定义行与 [policy] 成员
-- 一并去掉，与 Surge 家族丢 wireguard / ssr、Clash 原版丢不支持协议同一约定。
--
-- 反向对照：改动前 to_qx 只把 `tag=` 排在最后、由 names_of 挡成员列表，
-- 定义行照写 —— 下面「无 tag=Bad,Name 行」「无 Bad,Name 出现」两条会失败。

package.path = "./root/usr/share/?.lua;" .. package.path

local output = require("substore.output")

local passed, failed = 0, 0
local function check(name, cond)
	if cond then passed = passed + 1; print("PASS " .. name)
	else failed = failed + 1; print("FAIL " .. name) end
end

local function trojan(name, server)
	return {
		proto = "trojan", name = name, server = server or "1.2.3.4", port = 443,
		password = "pw", security = "tls", sni = "s.example.com",
	}
end

local function qx(nodes)
	local body, err = output.generate(nodes, "qx")
	return body, err
end

-- ---------- 基线：无逗号名字照常输出 ----------
local base, base_err = qx({ trojan("Good Node") })
check("baseline qx generates", type(base) == "string" and base_err == nil)
check("baseline emits definition line", base:find("tag=Good Node", 1, true) ~= nil)
check("baseline lists member in policy", base:find("static=PROXY, DIRECT, Good Node", 1, true) ~= nil)

-- ---------- 含逗号名字：整条丢弃 ----------
local mixed = qx({ trojan("Good Node", "1.1.1.1"), trojan("Bad,Name", "2.2.2.2") })
check("mixed qx generates", type(mixed) == "string")

check("no definition line for comma name", mixed:find("tag=Bad,Name", 1, true) == nil)
check("comma name absent entirely", mixed:find("Bad,Name", 1, true) == nil)
-- 单独查 `tag=Bad`：即使名字被截断成 `tag=Bad` 也必须不出现
check("no truncated tag=Bad either", mixed:find("tag=Bad", 1, true) == nil)
-- 该节点的服务器地址也必须消失（定义行整体没了）
check("dropped node server absent", mixed:find("2.2.2.2", 1, true) == nil)

-- 正常节点不受牵连
check("good node still emitted", mixed:find("tag=Good Node", 1, true) ~= nil)
check("good node still in policy", mixed:find("static=PROXY, DIRECT, Good Node", 1, true) ~= nil)
check("good node server present", mixed:find("1.1.1.1", 1, true) ~= nil)

-- 定义行只应有一条（[server_local] 段内）。
-- 段内为空时输出是 `[server_local]\n\n[policy]`，非空时是
-- `[server_local]\n<line>\n\n[policy]` —— 取两者之间即可，不要去数 `\n\n`。
local function def_count_of(body)
	local section = body:match("%[server_local%]\n(.-)\n%[policy%]") or ""
	local n = 0
	for line in (section .. "\n"):gmatch("([^\n]*)\n") do
		if line:match("^%a+=") then n = n + 1 end
	end
	return n
end
check("exactly one definition line left", def_count_of(mixed) == 1)

-- 成员列表里不得出现被丢弃的名字
local policy = mixed:match("static=[^\n]*") or ""
check("policy line has no dangling member",
	not policy:find("Bad", 1, true) and policy:find("Good Node", 1, true) ~= nil)

-- ---------- 全部节点都含逗号：仍产出合法骨架 ----------
local all_bad = qx({ trojan("A,B"), trojan("C,D") })
check("all-comma qx generates", type(all_bad) == "string")
check("all-comma has no definitions", def_count_of(all_bad) == 0)
check("all-comma policy is just the default",
	all_bad:find("static=PROXY, DIRECT\n", 1, true) ~= nil)
check("all-comma has no stray comma", all_bad:find("A,B", 1, true) == nil
	and all_bad:find("C,D", 1, true) == nil)

-- ---------- 判定必须基于 one_line 之后的名字 ----------
-- names_of 先 one_line 再比对；定义行也必须用同一个字符串，否则两边对不上。
-- `Bad\n,Name` 里的换行会被压成空格，逗号仍在 —— 仍须丢弃。
local nl = qx({ trojan("Bad\n,Name") })
check("newline+comma name dropped", nl:find("Bad", 1, true) == nil)
check("newline+comma name adds no lines",
	select(2, nl:gsub("\n", "\n")) == select(2, qx({}):gsub("\n", "\n")))

-- 换行但**无**逗号的名字：仍应输出（换行被压成空格，不触发本条规则），
-- 且不得比一个普通节点多出任何行（名字里的换行若漏了 one_line 会凭空多出一行）。
local nl_ok = qx({ trojan("Multi\nLine") })
check("newline-only name kept", nl_ok:find("tag=Multi Line", 1, true) ~= nil)
local function line_count(body)
	return select(2, body:gsub("\n", "\n"))
end
check("newline-only name flattened to one line",
	line_count(nl_ok) == line_count(qx({ trojan("Plain") })))

-- ---------- 值里的逗号仍按既有规则处理（不因本条改动而回归） ----------
local pwd = qx({ { proto = "trojan", name = "P", server = "3.3.3.3", port = 443,
	password = "pa,ss", security = "tls" } })
check("comma in password still drops the node", pwd:find("3.3.3.3", 1, true) == nil)

-- ---------- Surge 家族不受影响：名字在 `=` 左侧，逗号不影响该行解析 ----------
-- 本条只针对 QX。Surge 的 [Proxy] 行是 `NAME = type, host, port, …`，
-- 名字里含逗号的节点仍应写出定义行，只是不进 [Proxy Group] 成员列表。
local surge = output.generate({ trojan("Bad,Name", "4.4.4.4") }, "surge")
check("surge still emits comma-named node", surge:find("Bad,Name = trojan", 1, true) ~= nil)
local group = surge:match("PROXY = select[^\n]*") or ""
check("surge group excludes comma name", group:find("Bad,Name", 1, true) == nil)

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
