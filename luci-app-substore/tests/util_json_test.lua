-- util_json_test.lua — JSON 编解码保真与错误上报单元测试
-- 用法：lua5.1 tests/util_json_test.lua
--
-- 覆盖审计表 M13（null / 空对象往返被改写）与 M14（json_decode 永不返回错误串）。

package.path = "./root/usr/share/?.lua;" .. package.path

local util = require("substore.util")

local passed, failed = 0, 0
local function check(name, cond)
	if cond then
		passed = passed + 1
	else
		failed = failed + 1
		print("FAIL: " .. name)
	end
end

local function rt(s) -- 解码再编码，返回编码结果与错误
	local v, err = util.json_decode(s)
	if err then return nil, err end
	return util.json_encode(v)
end

-- ---------- M14：错误必须上报 ----------
do
	local _, err = util.json_decode("{")
	check("M14 unterminated object reports error", type(err) == "string")

	local _, err2 = util.json_decode("[1,2")
	check("M14 unterminated array reports error", type(err2) == "string")

	local _, err3 = util.json_decode('{"a":}')
	check("M14 missing value reports error", type(err3) == "string")

	local _, err4 = util.json_decode("[1,]")
	check("M14 trailing comma in array rejected", type(err4) == "string")

	local _, err5 = util.json_decode('{"a":1,}')
	check("M14 trailing comma in object rejected", type(err5) == "string")

	-- 合法输入不得被误判
	local v, e = util.json_decode('{"a":1}')
	check("M14 valid object still parses", type(v) == "table" and v.a == 1 and e == nil)

	local arr, e2 = util.json_decode("[1,2,3]")
	check("M14 valid array still parses", type(arr) == "table" and #arr == 3 and e2 == nil)

	-- 顶层 null 是合法 JSON，必须与「解析失败」区分开
	local n, e3 = util.json_decode("null")
	check("M14 top-level null is valid, not an error", n == nil and e3 == nil)
end

-- ---------- M14：尾部脏数据必须拒绝 ----------
do
	local _, err = util.json_decode("1 2")
	check("M14 trailing content after number rejected", type(err) == "string")

	local _, err2 = util.json_decode("[1] junk")
	check("M14 trailing content after array rejected", type(err2) == "string")

	local _, err3 = util.json_decode('{"a":1}{"b":2}')
	check("M14 two concatenated objects rejected", type(err3) == "string")

	local _, err4 = util.json_decode("1.2.3")
	check("M14 malformed number rejected", type(err4) == "string")

	-- 尾随空白是合法的
	local v, e = util.json_decode("[1]  \n\t ")
	check("M14 trailing whitespace allowed", type(v) == "table" and v[1] == 1 and e == nil)
end

-- ---------- M13：数组中的 null 往返保持 null ----------
do
	local out = rt("[null,1]")
	check("M13 null in array round-trips to null", out == "[null,1]")

	local out2 = rt("[null,null]")
	check("M13 multiple nulls round-trip", out2 == "[null,null]")

	local out3 = rt('{"a":[1,null,2]}')
	check("M13 nested null in object array round-trips", out3 == '{"a":[1,null,2]}')

	-- 编码侧直接喂 null 占位符
	local decoded = util.json_decode("[null]")
	check("M13 decoded null slot is a table placeholder", type(decoded) == "table" and type(decoded[1]) == "table")
end

-- ---------- M13：空对象往返保持对象 ----------
do
	local out = rt('{"tls":{}}')
	check("M13 empty object round-trips as object", out == '{"tls":{}}')

	local out2 = rt('{"settings":{},"x":1}')
	check("M13 empty object among other keys round-trips", out2 == '{"settings":{},"x":1}')

	-- 空数组仍须保持数组
	local out3 = rt("[]")
	check("M13 empty array still round-trips as array", out3 == "[]")

	local out4 = rt('{"a":[]}')
	check("M13 empty array value round-trips", out4 == '{"a":[]}')

	-- 显式常量仍然有效
	check("M13 JSON_EMPTY_OBJECT still encodes to {}", util.json_encode(util.JSON_EMPTY_OBJECT) == "{}")
end

-- ---------- 回归：既有行为不得被破坏 ----------
do
	local out = rt('{"a":1,"b":"x","c":true,"d":false}')
	check("regression object scalars", out ~= nil and out:find('"a":1', 1, true) ~= nil
		and out:find('"b":"x"', 1, true) ~= nil and out:find('"c":true', 1, true) ~= nil)

	local out2 = rt('[1,2,3]')
	check("regression plain array", out2 == "[1,2,3]")

	local out3 = rt('"hello"')
	check("regression plain string", out3 == '"hello"')

	local out4 = rt("42")
	check("regression plain number", out4 == "42")

	-- 转义序列
	local s = util.json_decode('"a\\nb\\tc\\"d"')
	check("regression escape sequences", s == 'a\nb\tc"d')

	-- unicode 转义
	local u = util.json_decode('"\\u4e2d"')
	check("regression unicode escape", u == "中")

	-- 空对象解码后仍是 table 且可被 pairs 遍历（调用方普遍这么用）
	local o = util.json_decode("{}")
	local cnt = 0
	for _ in pairs(o) do cnt = cnt + 1 end
	check("regression decoded empty object iterable", type(o) == "table" and cnt == 0)
end

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
