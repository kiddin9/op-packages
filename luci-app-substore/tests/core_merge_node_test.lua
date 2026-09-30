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

-- ---------- 表单没渲染的字段不得被清空 ----------
--
-- 表单按 node.PROTO_FIELDS[proto] 渲染，没渲染的字段提交不上来。原先
-- merge_form_node 一律清空全部表单字段，等于用空值覆盖原值：vmess 与
-- hysteria2/tuic 的 TLS 层字段（security）就是这样被静默抹掉的 —— 前者
-- 变成明文，后者让 sing-box 因 C.ErrTLSRequired 拒绝启动。
local parser = require("substore.parser")
local util = require("substore.util")
local node = require("substore.node")

-- 模拟一次真实的表单提交：只提交本协议渲染出来的字段，再过 parse_local
local function submit(proto, vals)
	local t = {}
	for _, k in ipairs(node.PROTO_FIELDS[proto] or {}) do
		if vals[k] ~= nil and vals[k] ~= "" then t[k] = tostring(vals[k]) end
	end
	t.type = proto
	return parser.parse_local(util.json_encode({ t }), "form").nodes[1]
end

local vless_node = { proto = "vmess", name = "n", server = "1.1.1.1", port = 443, uuid = "u", security = "tls" }
local kept = core.merge_form_node(vless_node, submit("vmess", { name = "n", server = "1.1.1.1", port = 443, uuid = "u", security = "tls" }))
check("vmess security kept through form", kept.security == "tls")

-- 关掉 TLS 时，别名 tls 必须一起清掉，否则 build_tls / surge_line 会退回旧值
local off = core.merge_form_node(
	{ proto = "vmess", name = "n", server = "1.1.1.1", port = 443, uuid = "u", security = "tls", tls = true },
	submit("vmess", { name = "n", server = "1.1.1.1", port = 443, uuid = "u", security = "none" }))
check("vmess security off honoured", off.security == "none")
check("vmess tls alias cleared", off.tls == nil)

-- hysteria2 / tuic / hysteria 是 TLS-only，表单不渲染 security，不得被清掉
for _, p in ipairs({ "hysteria2", "hysteria", "tuic" }) do
	local o = { proto = p, name = "n", server = "1.1.1.1", port = 443, password = "pw", security = "tls" }
	local r = core.merge_form_node(o, submit(p, { name = "n", server = "1.1.1.1", port = 443, password = "pw" }))
	check(p .. " security kept through form", r.security == "tls")
end

-- 未渲染的普通字段同样保留（WireGuard 的 dns、vmess 的 flow）
local wg = { proto = "wireguard", name = "w", server = "1.1.1.1", port = 51820, ["private-key"] = "pk", dns = "1.1.1.1" }
local wg2 = core.merge_form_node(wg, submit("wireguard", { name = "w", server = "1.1.1.1", port = 51820, ["private-key"] = "pk" }))
check("wireguard dns preserved", wg2.dns == "1.1.1.1")
local vm = { proto = "vmess", name = "n", server = "1.1.1.1", port = 443, uuid = "u", flow = "xtls-rprx-vision" }
local vm2 = core.merge_form_node(vm, submit("vmess", { name = "n", server = "1.1.1.1", port = 443, uuid = "u" }))
check("vmess flow preserved", vm2.flow == "xtls-rprx-vision")

-- 别名跟随规范名一起清空（解析器产出的是下划线写法）
local alias = core.merge_form_node(
	{ proto = "vmess", name = "n", server = "1.1.1.1", port = 443, uuid = "u", ["skip-cert-verify"] = true, skip_cert_verify = true },
	submit("vmess", { name = "n", server = "1.1.1.1", port = 443, uuid = "u" }))
check("skip-cert-verify cleared", alias["skip-cert-verify"] == nil)
check("skip_cert_verify alias cleared", alias.skip_cert_verify == nil)

-- 协议未知时退回旧行为（清空全部表单字段）
local unk = core.merge_form_node({ proto = "snell", name = "s", server = "1.1.1.1", port = 443, password = "p" },
	{ proto = "snell", name = "s", server = "1.1.1.1", port = 443 })
check("unknown proto falls back to full wipe", unk.password == nil)

print(string.format("%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
