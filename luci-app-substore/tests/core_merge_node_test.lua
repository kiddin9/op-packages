-- core.merge_form_node 测试：表单字段整体替换、非表单字段保留
package.path = "root/usr/share/?.lua;root/usr/share/?/init.lua;" .. package.path

-- core.lua 的 merge_form_node 不依赖 io/网络，可直接测试
local core = require("substore.core")

local passed, failed = 0, 0
local function check(name, cond)
	if cond then passed = passed + 1; print("PASS " .. name)
	else failed = failed + 1; print("FAIL " .. name) end
end

local orig = {
	proto = "vmess", name = "old", group = "g1",
	server = "a.com", port = 443, uuid = "u1", sni = "a.com",
	raw = "vmess://xxx", tags = { "fast" }, remark_src = "机场A",
}

-- 表单提交的新值：改名、换分组、清空 sni、改端口
local formnode = {
	proto = "vmess", name = "new", group = "g2",
	server = "a.com", port = 8443, uuid = "u1",
}

local m = core.merge_form_node(orig, formnode)
check("name replaced", m.name == "new")
check("group replaced", m.group == "g2")
check("port replaced", m.port == 8443)
check("server kept", m.server == "a.com")
check("sni cleared (form-managed, absent in form)", m.sni == nil)
check("raw preserved", m.raw == "vmess://xxx")
check("tags preserved", m.tags and m.tags[1] == "fast")
check("custom field preserved", m.remark_src == "机场A")
check("proto kept", m.proto == "vmess")
check("no type key", m.type == nil)

-- 分组清空：formnode 无 group 键 → 清除
local m2 = core.merge_form_node(orig, { proto = "vmess", name = "n", server = "a.com", port = 1 })
check("group cleared when absent", m2.group == nil)

-- 协议切换：旧协议字段被清除
local m3 = core.merge_form_node(orig, {
	proto = "trojan", name = "t", server = "a.com", port = 443, password = "pw",
})
check("proto switched", m3.proto == "trojan")
check("uuid cleared after proto switch", m3.uuid == nil)
check("password set", m3.password == "pw")

-- 空表/空原节点容错
local m4 = core.merge_form_node(nil, { name = "x" })
check("nil orig ok", m4.name == "x")
local m5 = core.merge_form_node(orig, nil)
check("nil form keeps non-form fields", m5.raw == "vmess://xxx")
check("nil form clears form fields", m5.name == nil)

print(string.format("%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
