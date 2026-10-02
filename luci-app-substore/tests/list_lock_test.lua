-- list_lock_test.lua — 订阅列表互斥锁回归测试
-- 用法：lua5.1 tests/list_lock_test.lua
--
-- 缺陷（docs/LEGACY_ISSUES.md 1.1）：`load()` 读出整表、`save()` 整表写回，
-- 中间无锁。LuCI 页面保存订阅、cron 定时更新、组合订阅自动重算三者可能同时
-- 发生，后写者整表覆盖先写者 —— 订阅静默丢失，没有任何报错。
--
-- 本机没有 nixio（用不了 flock），Lua 5.1 的 io.open 也没有 O_EXCL，
-- 因此用 `mkdir` 做锁（成功者唯一），并用锁目录自身的 mtime 判定陈旧锁 ——
-- mtime 由 mkdir 原子设好，不存在「目录已建、时间戳还没写」的窗口。
--
-- 反向对照：改动前 util 里没有任何锁原语，core 也不认 .lock 目录，
-- 下面「第二个 acquire 返回 false」「锁被占用时 add 拒绝写入」等会失败。

package.path = "./root/usr/share/?.lua;" .. package.path

local util = require("substore.util")
local core = require("substore.core")

local passed, failed = 0, 0
local function check(name, cond)
	if cond then passed = passed + 1; print("PASS " .. name)
	else failed = failed + 1; print("FAIL " .. name) end
end

-- 改动前这些符号不存在。用 nil 兜底而不是直接调用：否则脚本会在第一次
-- nil 调用处中断，后面的断言全看不到，反向验证就只剩半份报告。
local lock_acquire = util.lock_acquire or function() return nil end
local lock_release = util.lock_release or function() end

local tmp = "/tmp/substore_lock_test"
local q = string.format("%q", tmp)
os.execute("rm -rf " .. q)
os.execute("mkdir -p " .. q .. "/nodes")

core.DATA_DIR = tmp
core.LIST_FILE = tmp .. "/subscriptions.json"
core.NODES_DIR = tmp .. "/nodes"
local LOCK_DIR = tmp .. "/.lock"

local function exists(p)
	local f = io.open(p, "rb")
	if f then f:close() return true end
	return false
end

-- ---------- 第一部分：util 的锁原语 ----------
check("lock_acquire exists", type(util.lock_acquire) == "function")
check("lock_release exists", type(util.lock_release) == "function")
check("LOCK_STALE is a positive number",
	type(util.LOCK_STALE) == "number" and util.LOCK_STALE > 0)

os.execute("rm -rf " .. string.format("%q", tmp .. "/p1"))
local p1 = tmp .. "/p1"

check("first acquire succeeds", lock_acquire(p1) == true)
check("lock dir created", exists(p1))
-- 持有者信息是排障用的（谁、什么时候拿的）
local owner = util.read_file(p1 .. "/owner")
check("owner file written", type(owner) == "string")
check("owner file has a timestamp",
	type(owner) == "string" and tonumber(owner:match("(%d+)%s*$")) ~= nil)

-- 第二个持有者必须被挡住（这是锁的全部意义）
check("second acquire refused", lock_acquire(p1) == false)
check("second acquire did not clobber owner",
	util.read_file(p1 .. "/owner") == owner)

lock_release(p1)
check("release removes the lock dir", not exists(p1))
check("acquire after release succeeds", lock_acquire(p1) == true)
lock_release(p1)

-- 陈旧锁回收：持有者被 kill 时目录会留下，不回收就永久死锁
-- （比丢数据更糟：订阅从此再也改不了）。把 mtime 拨回 2001 年模拟。
lock_acquire(p1)
os.execute("touch -d '@1000000000' " .. string.format("%q", p1))
check("stale lock reclaimed", lock_acquire(p1) == true)
lock_release(p1)
check("stale reclaim left no extra dir", not exists(p1))

-- 未陈旧的锁不得被回收
lock_acquire(p1)
check("fresh lock not reclaimed", lock_acquire(p1) == false)
lock_release(p1)

-- ---------- 第二部分：core 的写入口被锁串行化 ----------
-- 手工造一个「别人正持有」的锁
os.execute("rm -rf " .. string.format("%q", LOCK_DIR))
os.execute("mkdir -p " .. string.format("%q", LOCK_DIR))

local blocked_id, blocked_err = core.add("A", "https://example.com/a")
check("add refused while lock held", blocked_id == nil)
check("refusal names the conflict",
	type(blocked_err) == "string" and blocked_err:find("另一个进程", 1, true) ~= nil)
-- 关键：被挡住时**不得**落盘。改动前这里会写成功。
check("refused add did not write the list", not exists(core.LIST_FILE))
check("refused add left no subscription", #core.list() == 0)
-- 别人的锁也不能被顺手删掉
check("refused add left the foreign lock alone", exists(LOCK_DIR))

os.execute("rm -rf " .. string.format("%q", LOCK_DIR))

-- 锁释放后一切照常
local id, err = core.add("A", "https://example.com/a")
check("add succeeds once unlocked", type(id) == "string" and err == nil)
check("subscription persisted", #core.list() == 1)
check("lock released after add", not exists(LOCK_DIR))

-- ---------- 释放必须覆盖每一条返回路径 ----------
-- 包一层的好处就在这里：函数中途 return 也不会漏掉释放。
-- 漏释放的症状是「过一会儿自己好了」（陈旧回收），最难查。

-- (a) 参数校验失败提前 return
local _, e1 = core.add("", "https://example.com/x")
check("empty name rejected", type(e1) == "string")
check("lock released after validation failure", not exists(LOCK_DIR))

-- (b) 列表文件损坏时提前 return
util.atomic_write(core.LIST_FILE, "{ this is not json")
local _, e2 = core.add("B", "https://example.com/b")
check("corrupt list rejected", type(e2) == "string" and e2:find("损坏", 1, true) ~= nil)
check("lock released after corruption error", not exists(LOCK_DIR))
-- 损坏的文件不得被覆盖
check("corrupt list left untouched",
	(util.read_file(core.LIST_FILE) or ""):find("not json", 1, true) ~= nil)

-- 恢复一份干净的列表
util.atomic_write(core.LIST_FILE, util.json_encode({ _seq = 1, items = {
	[id] = { name = "A", url = "https://example.com/a", enabled = true },
} }))

-- (c) 正常路径
local ok3 = core.save_meta(id, { name = "A2" })
check("save_meta succeeds", ok3 == true)
check("lock released after save_meta", not exists(LOCK_DIR))
check("save_meta actually applied", core.get(id).name == "A2")

-- (d) remove
check("remove succeeds", core.remove(id) == true)
check("lock released after remove", not exists(LOCK_DIR))
check("list empty after remove", #core.list() == 0)

-- ---------- 可重入：save_combo 内部会调 save_meta ----------
-- 不可重入的话第二次取锁会把自己挡在门外，组合订阅永远保存不了。
-- 这里直接验证嵌套调用链能跑通，且过程中不会留下锁。
local a1 = core.add("src1", "https://example.com/1")
local a2 = core.add("src2", "https://example.com/2")
check("two sources added", type(a1) == "string" and type(a2) == "string")
local cid, cerr = core.add_combo("combo", { a1, a2 })
check("add_combo succeeds (nested save_meta)", type(cid) == "string" and cerr == nil)
check("lock released after add_combo", not exists(LOCK_DIR))
local cok, cerr2 = core.save_combo(cid, "combo2", { a1 })
check("save_combo succeeds (nested save_meta)", cok ~= nil and cerr2 == nil)
check("lock released after save_combo", not exists(LOCK_DIR))

-- 嵌套期间外层不得被内层提前释放：内层返回后外层仍持有，
-- 所以此时从「另一个进程」的视角看锁应当还在。
-- 用一个能观察到中间状态的钩子来验证。
local saw_lock_inside = false
local real_save_meta = core.save_meta
core.save_meta = function(...)
	if exists(LOCK_DIR) then saw_lock_inside = true end
	return real_save_meta(...)
end
core.save_combo(cid, "combo3", { a1 })
core.save_meta = real_save_meta
check("outer lock still held while inner runs", saw_lock_inside)

os.execute("rm -rf " .. q)

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
