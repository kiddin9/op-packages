-- acl_menu_test.lua — 菜单 ACL 接线（M29）
-- 用法：lua5.1 tests/acl_menu_test.lua
--
-- 背景：本应用此前**没有任何 ACL** —— 没有 acl.d 文件，菜单也没有 depends.acl，
-- 于是任何能登录 LuCI 的用户都能看到并使用它（含订阅 URL 与下载 token）。
--
-- 修复：新增 ACL 组 luci-app-substore（rpcd/acl.d）+ 菜单 depends.acl 引用它。
--
-- 这条链路上任何一环写错都**不会报错**，只会静默失效（ACL 形同虚设），
-- 因此必须把跨文件的接线关系固化下来：
--   A  acl.d 文件存在、是合法 JSON、定义了组 luci-app-substore
--   B  menu.d 两个条目的 depends.acl 引用的正是这个组名（拼错 = 组不存在）
--   C  Makefile 必须真的安装 acl.d 文件（本包用逐文件 install 规则，
--      漏一条规则 = 文件不随包发布 = ACL 不存在，而构建不会报错）

package.path = "./root/usr/share/?.lua;" .. package.path

local util = require("substore.util")

local passed, failed = 0, 0
local function check(name, cond)
	if cond then passed = passed + 1; print("PASS " .. name)
	else failed = failed + 1; print("FAIL " .. name) end
end

local ACL_PATH = "root/usr/share/rpcd/acl.d/luci-app-substore.json"
local MENU_PATH = "root/usr/share/luci/menu.d/luci-app-substore.json"

-- ---------- A：ACL 组定义 ----------
local raw = util.read_file(ACL_PATH)
check("acl.d file exists", raw ~= nil and raw ~= "")

local acl = raw and util.json_decode(raw) or nil
check("acl.d is valid json", type(acl) == "table")
check("acl.d defines the app group", type(acl) == "table" and type(acl["luci-app-substore"]) == "table")
check("acl group has a description",
	type(acl) == "table" and acl["luci-app-substore"]
	and type(acl["luci-app-substore"].description) == "string"
	and acl["luci-app-substore"].description ~= "")
check("acl group declares read perms",
	acl and acl["luci-app-substore"] and type(acl["luci-app-substore"].read) == "table")
check("acl group declares write perms",
	acl and acl["luci-app-substore"] and type(acl["luci-app-substore"].write) == "table")

-- ---------- B：菜单引用同一个组名 ----------
local mraw = util.read_file(MENU_PATH)
check("menu.d file exists", mraw ~= nil and mraw ~= "")
local menu = mraw and util.json_decode(mraw) or nil
check("menu.d is valid json", type(menu) == "table")

local entries = { "admin/services/substore", "admin/services/substore/list" }
for _, path in ipairs(entries) do
	local e = type(menu) == "table" and menu[path] or nil
	check("menu has " .. path, type(e) == "table")
	local aclref = e and e.depends and e.depends.acl
	check(path .. " declares depends.acl", type(aclref) == "table" and #aclref > 0)
	-- 引用的组名必须与 acl.d 里定义的**完全一致**：拼错不会报错，
	-- 只会让这个菜单项对任何非 root 用户都不可见（或让 ACL 形同虚设）
	check(path .. " references the defined group",
		type(aclref) == "table" and aclref[1] == "luci-app-substore"
		and type(acl) == "table" and acl[aclref[1]] ~= nil)
end

-- 菜单 action 指向的 view 必须在控制器里注册过（组名对了但路径写错同样静默失效）
local ctl_raw = util.read_file("root/usr/lib/lua/luci/controller/admin/substore.lua") or ""
check("menu view path is registered in controller",
	ctl_raw:find('"admin", "services", "substore", "list"', 1, true) ~= nil
	or ctl_raw:find("'admin', 'services', 'substore', 'list'", 1, true) ~= nil)

-- ---------- C：Makefile 安装规则 ----------
local mk = util.read_file("Makefile") or ""
check("Makefile installs the acl.d file",
	mk:find("root/usr/share/rpcd/acl.d/luci-app-substore.json", 1, true) ~= nil)
check("Makefile creates the acl.d directory",
	mk:find("/usr/share/rpcd/acl.d", 1, true) ~= nil)
check("Makefile installs the menu.d file",
	mk:find("root/usr/share/luci/menu.d/luci-app-substore.json", 1, true) ~= nil)

-- 两个文件都在 root/ 下（否则打包时不会被带上）
check("acl.d lives under root/", util.read_file("root/usr/share/rpcd/acl.d/luci-app-substore.json") ~= nil)

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
