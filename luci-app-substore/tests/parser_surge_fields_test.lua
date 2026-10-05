-- parser_surge_fields_test.lua — Surge 系 / Loon / QX 行解析的两个字段级缺陷
-- 用法：lua5.1 tests/parser_surge_fields_test.lua
--
-- 锁住两件事（对应 docs/LEGACY_ISSUES.md 第七节的 7.5 与 7.6）：
--   7.5 行拆分必须**引号感知**：Loon 把凭据写成双引号包裹的位置参数
--       （nsloon.app/docs/Node/），密码里含逗号时旧实现（`rest:gmatch("[^,]+")`）
--       会把它切成两段 —— 密码静默变成 `"pa`，用户拿到的不是他填的凭据。
--   7.6 Loon 的 `transport=<tcp|ws|http>` + `path=` + `host=` 必须映射到统一模型。
--       只认 Surge 旧写法（ws=true / ws-path / ws-headers=Host:）时，别人给的
--       Loon 配置导入后 net 保持默认 tcp、path / host 全丢，导出到任何格式都按
--       tcp 去连一个只开了 ws 的端口 —— 握手失败且不报错。
--
-- 反向验证：本文件在修复前应当失败（见每条注释里的「修复前」）。

package.path = "./root/usr/share/?.lua;" .. package.path

local surge = require("substore.parser_surge")

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

-- 带值输出的断言：反向验证时能直接从输出看出「改前是什么」
local function eq(name, got, want)
	check(name .. " (got " .. string.format("%q", tostring(got))
		.. ", want " .. string.format("%q", tostring(want)) .. ")", got == want)
end

-- 解析一份 [Proxy] 配置，返回按名字索引的节点表
local function parse_proxy(lines)
	local r = surge.parse("[Proxy]\n" .. table.concat(lines, "\n") .. "\n")
	local by = {}
	for _, n in ipairs(r) do by[n.name] = n end
	return by, r
end

-- ============================================================
-- 7.5 引号感知切分
-- ============================================================

-- Loon / Surge 位置参数：`"pa,ss"` 是一个字段，不是两个。
-- 修复前：密码被切成 `"pa`（多一个引号、少掉后半段），sni 之后仍能解析。
local p1 = parse_proxy({
	'T = Trojan,t.example.com,443,"pa,ss",sni=t.example.com',
})
eq("7.5 surge positional quoted comma password", p1["T"] and p1["T"].password, "pa,ss")
eq("7.5 surge positional quoted comma keeps following fields", p1["T"] and p1["T"].sni, "t.example.com")

-- Loon 的 AnyTLS 同样是引号位置参数
local p2 = parse_proxy({
	'A = AnyTLS,a.example.com,443,"p,w",sni=a.example.com',
})
eq("7.5 loon anytls quoted comma password", p2["A"] and p2["A"].password, "p,w")

-- VMess 的位置参数是「加密方式, UUID」两个字段；UUID 含逗号时不能被切开
local p3 = parse_proxy({
	'V = VMess,v.example.com,443,aes-128-gcm,"uu,id"',
})
eq("7.5 loon vmess cipher still positional[1]", p3["V"] and p3["V"].cipher, "aes-128-gcm")
eq("7.5 loon vmess quoted comma uuid", p3["V"] and p3["V"].uuid, "uu,id")

-- QX：值里的逗号同理。注意 QX 的 kv 值**不做 unquote**（unquote 的注释写明只用于
-- Loon 的位置参数，QX 的 sample.conf 也没有引号写法），所以引号原样保留 ——
-- 这里要锁的是「值没有被逗号截断」：修复前拿到的是 `"pa`（逗号之后的半段丢失），
-- 修复后 `pa,ss` 完整保留。
local q1 = surge.parse("[server_local]\n"
	.. 'trojan=h.example.com:443, password="pa,ss", over-tls=true, tag=T\n')
check("7.5 qx comma in value is not truncated (got "
	.. string.format("%q", tostring(q1[1] and q1[1].password)) .. ")",
	q1[1] ~= nil and q1[1].password ~= nil
		and q1[1].password:find("pa,ss", 1, true) ~= nil)
eq("7.5 qx quoted comma keeps following fields", q1[1] and q1[1].security, "tls")

-- 回归：无引号的输入必须与旧实现逐字符等价
local p4 = parse_proxy({
	'S = ss,h.example.com,8388,encrypt-method=aes-256-gcm,password=plainpwd',
	'T2 = Trojan,h.example.com,443,plainpwd,sni=s.example.com',
})
eq("regression unquoted ss method", p4["S"] and p4["S"].method, "aes-256-gcm")
eq("regression unquoted ss password", p4["S"] and p4["S"].password, "plainpwd")
eq("regression unquoted trojan positional password", p4["T2"] and p4["T2"].password, "plainpwd")

-- 回归：引号包裹但**不含逗号**的值仍被剥掉引号（既有行为）
local p5 = parse_proxy({
	'T3 = Trojan,h.example.com,443,"pwd"',
})
eq("regression quoted password unquoted", p5["T3"] and p5["T3"].password, "pwd")

-- 边界：空字段照旧丢弃（与 gmatch("[^,]+") 一致，位置参数不会多出空项）
local p6 = parse_proxy({
	'T4 = Trojan,h.example.com,443,,sni=s.example.com',
})
eq("boundary empty field dropped", p6["T4"] and p6["T4"].password, nil)
eq("boundary empty field keeps later kv", p6["T4"] and p6["T4"].sni, "s.example.com")

-- 边界：引号个数为奇数（订阅内容不可信）时**不做**引号感知，退回按逗号切分。
-- 否则那个落单的引号会一直「开着」，把后面的 sni= 一起吞进同一个字段。
local p7 = parse_proxy({
	'T5 = Trojan,h.example.com,443,pa"ss,sni=s.example.com',
})
eq("boundary odd quote falls back to comma split (password)", p7["T5"] and p7["T5"].password, 'pa"ss')
eq("boundary odd quote does not swallow later kv", p7["T5"] and p7["T5"].sni, "s.example.com")

-- ============================================================
-- 7.6 Loon transport= / path= / host=
-- ============================================================

-- Loon 文档的 VLESS-over-WS 行（nsloon.app/docs/Node/）
-- 修复前：net 保持 vless 的默认 "tcp"，path / host 为 nil
local t1 = parse_proxy({
	'VLESS = VLESS,v.example.com,443,"uu-id",transport=ws,path=/websocket,'
		.. 'host=cdn.example.com,over-tls=true,sni=s.example.com',
})
local n1 = t1["VLESS"]
eq("7.6 loon transport=ws -> net", n1 and n1.net, "ws")
eq("7.6 loon path=", n1 and n1.path, "/websocket")
eq("7.6 loon host=", n1 and n1.host, "cdn.example.com")
eq("7.6 loon over-tls still tls", n1 and n1.security, "tls")
eq("7.6 loon sni kept", n1 and n1.sni, "s.example.com")
eq("7.6 loon positional uuid kept", n1 and n1.uuid, "uu-id")

-- Loon 文档：兼容配置里的 transport=http 按 WebSocket 处理
local t2 = parse_proxy({
	'VLESS2 = VLESS,v.example.com,443,"uu-id",transport=http,path=/h,host=h.example.com',
})
eq("7.6 loon transport=http -> ws (per Loon docs)", t2["VLESS2"] and t2["VLESS2"].net, "ws")

-- transport=tcp 显式写出来时保持 tcp（不引入新取值）
local t3 = parse_proxy({
	'TRO = Trojan,t.example.com,443,"pwd",transport=tcp,sni=t.example.com',
})
eq("7.6 loon transport=tcp stays tcp", t3["TRO"] and t3["TRO"].net, "tcp")

-- 回归：Surge 旧写法（ws=true / ws-path / ws-headers=Host:）仍然生效
local t4 = parse_proxy({
	'M = vmess,v.example.com,443,username=uu,tls=true,sni=s.example.com,'
		.. 'ws=true,ws-path=/oldpath,ws-headers=Host:old.example.com',
})
local n4 = t4["M"]
eq("regression legacy ws=true -> net", n4 and n4.net, "ws")
eq("regression legacy ws-path", n4 and n4.path, "/oldpath")
eq("regression legacy ws-headers Host", n4 and n4.host, "old.example.com")

-- 新写法优先：同一行两种都出现时以 Loon 的 transport= / path= / host= 为准
local t5 = parse_proxy({
	'M2 = vmess,v.example.com,443,username=uu,ws=true,ws-path=/old,'
		.. 'ws-headers=Host:old.example.com,transport=ws,path=/new,host=new.example.com',
})
local n5 = t5["M2"]
eq("new form wins: path", n5 and n5.path, "/new")
eq("new form wins: host", n5 and n5.host, "new.example.com")

-- Loon 的 VMess-over-WS 行：位置参数（加密方式, UUID）与传输参数并存
local t6 = parse_proxy({
	'VM = VMess,v.example.com,443,aes-128-gcm,"uu-id",transport=ws,path=/websocket,'
		.. 'host=cdn.example.com,over-tls=true,sni=s.example.com',
})
local n6 = t6["VM"]
eq("7.6 loon vmess cipher", n6 and n6.cipher, "aes-128-gcm")
eq("7.6 loon vmess uuid", n6 and n6.uuid, "uu-id")
eq("7.6 loon vmess net", n6 and n6.net, "ws")
eq("7.6 loon vmess path/host", n6 and (n6.path .. "|" .. tostring(n6.host)), "/websocket|cdn.example.com")

-- 回归：Reality（7.4 相关）不受 7.6 改动影响
local t7 = parse_proxy({
	'R = VLESS,v.example.com,443,"uu-id",transport=tcp,public-key="PBK",short-id=sid123,over-tls=true',
})
local n7 = t7["R"]
eq("regression reality public-key", n7 and n7["public-key"], "PBK")
eq("regression reality short-id", n7 and n7["short-id"], "sid123")
eq("regression reality security", n7 and n7.security, "reality")
eq("regression reality transport=tcp", n7 and n7.net, "tcp")

-- ---------- 结果 ----------
print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
