-- data_integrity_test.lua — 数据完整性与 token 熵回归测试
-- 用法：lua5.1 tests/data_integrity_test.lua
--
-- 覆盖：
--   H8  订阅列表文件损坏时必须报错并拒绝写入，而不是按空列表处理
--       （否则下一次 add 会把用户所有订阅覆盖掉）
--   H9  atomic_write 必须检查 write / close 的返回值
--   H10 临时文件名必须唯一，并发写同一路径不得互相踩踏、不得残留
--   H11 下载 token 必须来自内核熵源，不得出现可预测的重复

package.path = "./root/usr/share/?.lua;" .. package.path

local core = require("substore.core")
local util = require("substore.util")

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

-- 重定向数据目录到临时目录，避免污染系统
local tmp = os.tmpname() .. "_substore"
os.execute("mkdir -p " .. string.format("%q", tmp .. "/nodes"))
core.DATA_DIR = tmp
core.LIST_FILE = tmp .. "/subscriptions.json"
core.NODES_DIR = tmp .. "/nodes"

-- ---------- H8：损坏的列表文件 ----------

local id1 = core.add("订阅一", "http://example.com/a")
check("add first subscription", id1 ~= nil)
check("list count after add", #core.list() == 1)

local good = util.read_file(core.LIST_FILE)
check("list file written", good ~= nil and good ~= "")

-- 把文件写成无法解析的内容，模拟截断 / 磁盘损坏
util.atomic_write(core.LIST_FILE, "{ 这不是合法 JSON")

local arr, lerr = core.list()
check("list reports corruption", lerr ~= nil and type(lerr) == "string")
check("list returns empty array on corruption", type(arr) == "table" and #arr == 0)

-- 关键：写入路径必须拒绝，而不是在空表上追加后整表写回
local id2, aerr = core.add("订阅二", "http://example.com/b")
check("add refuses on corruption", id2 == nil)
check("add returns corruption error",
	aerr ~= nil and aerr:find("corrupted", 1, true) ~= nil)

local id3, lerr2 = core.add_local("本地订阅", "vmess://x")
check("add_local refuses on corruption", id3 == nil and lerr2 ~= nil)

local id4, cerr = core.add_combo("组合", { id1 })
check("add_combo refuses on corruption", id4 == nil and cerr ~= nil)

check("corrupt file not overwritten", util.read_file(core.LIST_FILE) == "{ 这不是合法 JSON")
check("save_meta refuses on corruption", (core.save_meta(id1, { name = "x" })) == false)

-- 恢复后必须能继续正常写入，且 _seq 不得回退（否则会重复发放已用过的 ID）
util.atomic_write(core.LIST_FILE, good)
check("list recovers", #core.list() == 1)
local id5 = core.add("订阅三", "http://example.com/c")
check("add works after recovery", id5 ~= nil)
check("id not reused after recovery", id5 ~= nil and id5 ~= id1)

-- ---------- H9：atomic_write 的返回值 ----------

local ok_bad, err_bad = util.atomic_write("/proc/substore-nonexistent/x.json", "data")
check("atomic_write fails on bad path", ok_bad == false)
check("atomic_write returns error", err_bad ~= nil)

local target = tmp .. "/atomic.txt"
check("atomic_write succeeds", util.atomic_write(target, "hello") == true)
check("atomic_write content", util.read_file(target) == "hello")
check("atomic_write overwrites", util.atomic_write(target, "world") == true
	and util.read_file(target) == "world")

-- ---------- H10：临时文件名唯一、无残留 ----------

local base = tmp .. "/concurrent.txt"
local names = {}
for _ = 1, 20 do
	local n = string.format("%s.tmp.%s", base, util.rnd_hex(8))
	names[n] = true
end
local distinct = 0
for _ in pairs(names) do distinct = distinct + 1 end
check("tmp names are unique", distinct == 20)

-- 写完后不得在目标目录留下 .tmp 文件
os.execute("rm -f " .. string.format("%q", tmp) .. "/*.tmp.*")
util.atomic_write(base, "x")
local listing = tmp .. "/ls.txt"
os.execute("ls -a " .. string.format("%q", tmp) .. " > " .. string.format("%q", listing))
local ls = util.read_file(listing) or ""
local leftover = 0
for name in ls:gmatch("[^\n]+") do
	if name:find("%.tmp%.") then leftover = leftover + 1 end
end
check("no leftover tmp files", leftover == 0)

-- ---------- H11：token 熵 ----------

local seen, dups, N = {}, 0, 20000
for _ = 1, N do
	local t = util.rnd_hex(16)
	if seen[t] then dups = dups + 1 else seen[t] = true end
end
check("no duplicate tokens in " .. N .. " draws", dups == 0)

local tok = util.rnd_hex(16)
check("token length 16", #tok == 16)
check("token is lowercase hex", tok:match("^[0-9a-f]+$") ~= nil)
check("token length honoured for odd len", #util.rnd_hex(7) == 7)
check("token length honoured for 32", #util.rnd_hex(32) == 32)

-- 订阅 token 走同一条路径
local t1 = core.ensure_token(id1)
check("subscription token length", type(t1) == "string" and #t1 == 16)
check("subscription token stable", core.ensure_token(id1) == t1)

-- ---------- 写盘失败时不得交出不存在的状态（M.remove / M.ensure_token） ----------
-- 两处此前都丢弃了 save() 的返回值：
--   M.remove       → 返回 true，且**已经删掉节点文件**：订阅在列表里还在，
--                    点进去却是空的，用户以为删成功了
--   M.ensure_token → 返回一个只存在于内存里的 token，而 id_by_token 从磁盘读，
--                    用户拿到的是必然报「无效的订阅 token」的链接
-- 用替身让 atomic_write 失败（比 chmod 更可移植：测试可能以 root 运行，
-- 权限位对 root 不起作用）。
local real_atomic_write = util.atomic_write

-- 先正常建一条带节点的订阅（此时 atomic_write 还是真的）
local fail_id = core.add("写盘失败用例", "http://example.com/fail")
check("setup: add works before failure injection", fail_id ~= nil)
local fail_nodes = core.write_nodes(fail_id, { { proto = "vmess", name = "n", server = "1.2.3.4", port = 443 } })
check("setup: nodes written", fail_nodes == true)

-- ensure_token：token 写不进去时返回 nil，而不是一个用不了的 token。
-- add() 建订阅时就已经带了 token，先清掉才能走到「生成并持久化」那条路
-- （M.CLEAR 是 save_meta 的清除哨兵，见 core.lua 的说明）。
-- 这一步必须用**真实**的 atomic_write：失败替身只用于下面两条断言。
check("setup: clear token", core.save_meta(id5, { token = core.CLEAR }) == true)

util.atomic_write = function() return false, "No space left on device" end
local rok, rerr = core.remove(fail_id)
check("remove reports write failure", rok == false)
check("remove surfaces the write error", type(rerr) == "string" and rerr ~= "")
check("remove keeps nodes file on write failure",
	#core.read_nodes(fail_id) == 1)

local tok_fail, tok_err = core.ensure_token(id5)
check("ensure_token reports write failure", tok_fail == nil)
check("ensure_token surfaces the write error", type(tok_err) == "string" and tok_err ~= "")

util.atomic_write = real_atomic_write
-- 恢复后仍能正常发 token（替身没有把模块状态弄坏）
local tok_ok = core.ensure_token(id5)
check("ensure_token works after recovery", type(tok_ok) == "string" and #tok_ok == 16)
check("ensure_token stable after recovery", core.ensure_token(id5) == tok_ok)

os.execute("rm -rf " .. string.format("%q", tmp))

-- ---------- 结果 ----------
print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
