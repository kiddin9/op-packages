-- parse_local 表单模式测试：全字段透传 + 类型/别名修正
package.path = "root/usr/share/?.lua;root/usr/share/?/init.lua;" .. package.path

local parser = require("substore.parser")
local util = require("substore.util")

local passed, failed = 0, 0
local function check(name, cond)
	if cond then passed = passed + 1; print("PASS " .. name)
	else failed = failed + 1; print("FAIL " .. name) end
end

-- 用户实际场景：Clash 风格 vmess ws 节点（经表单录入为 JSON）
local form_json = util.json_encode({
	{
		type = "vmess",
		name = "test-vmess",
		server = "attwa10005.cdn.node.a.unicenter7.net",
		port = "30849",
		uuid = "b109403f-1b9c-3a10-9034-a5b1c2cacbc2",
		cipher = "auto",
		alterId = "0",
		net = "ws",
		path = "/009c250b-54f5-43a8-8b18-dccbb5d8c66a.y.live01.m3u8",
		["skip-cert-verify"] = "false",
		udp = "true",
	},
})

local res, err = parser.parse_local(form_json, "form")
check("form parse ok", res ~= nil)
check("form format", res and res.format == "local-form")
check("form node count", res and #res.nodes == 1)
local n = res and res.nodes[1] or {}
check("proto vmess", n.proto == "vmess")
check("name", n.name == "test-vmess")
check("server", n.server == "attwa10005.cdn.node.a.unicenter7.net")
check("port coerced to number", n.port == 30849)
check("uuid", n.uuid == "b109403f-1b9c-3a10-9034-a5b1c2cacbc2")
check("cipher kept", n.cipher == "auto")
check("method alias from cipher", n.method == "auto")
check("alterId coerced", n.alterId == 0)
check("net ws", n.net == "ws")
check("path kept", n.path == "/009c250b-54f5-43a8-8b18-dccbb5d8c66a.y.live01.m3u8")
check("skip-cert-verify bool false", n["skip-cert-verify"] == false)
check("skip_cert_verify alias", n.skip_cert_verify == false)
check("udp bool true", n.udp == true)

-- network 别名 → net
local res2 = parser.parse_local(util.json_encode({
	{ type = "vless", server = "a.com", port = "443", uuid = "u", network = "ws", path = "/p" },
}), "form")
local n2 = res2 and res2.nodes[1] or {}
check("network alias to net", n2.net == "ws")
check("network key removed", n2.network == nil)
check("path kept vless", n2.path == "/p")

-- ssr 参数别名
local res3 = parser.parse_local(util.json_encode({
	{ type = "ssr", server = "b.com", port = "8388", password = "p", cipher = "aes-256-cfb",
	  protocol = "auth_aes128_md5", obfs = "tls1.2_ticket_auth",
	  ["obfs-param"] = "op", ["protocol-param"] = "pp" },
}), "form")
local n3 = res3 and res3.nodes[1] or {}
check("ssr obfs_param alias", n3.obfs_param == "op")
check("ssr protocol_param alias", n3.protocol_param == "pp")

-- wireguard kebab-case 字段透传
local res4 = parser.parse_local(util.json_encode({
	{ type = "wireguard", server = "c.com", port = "51820",
	  ["private-key"] = "pk", ["peer-public-key"] = "ppk" },
}), "form")
local n4 = res4 and res4.nodes[1] or {}
check("wireguard private-key kept", n4["private-key"] == "pk")
check("wireguard peer-public-key kept", n4["peer-public-key"] == "ppk")

-- 无名节点自动命名
local res5 = parser.parse_local(util.json_encode({
	{ type = "trojan", server = "d.com", port = "443", password = "x" },
}), "form")
local n5 = res5 and res5.nodes[1] or {}
check("auto name server:port", n5.name == "d.com:443")

-- 非 JSON 返回错误
local res6, err6 = parser.parse_local("not json", "form")
check("invalid json error", res6 == nil and err6 ~= nil)

-- hy2 混淆：表单透传 → URI 输出 → URI 解析回环
local res7 = parser.parse_local(util.json_encode({
	{ type = "hysteria2", server = "hy2.com", port = "443", password = "pw",
	  sni = "hy2.com", obfs = "salamander", ["obfs-password"] = "secret" },
}), "form")
local n7 = res7 and res7.nodes[1] or {}
check("hy2 obfs passthrough", n7.obfs == "salamander")
check("hy2 obfs-password passthrough", n7["obfs-password"] == "secret")

local output_uri = require("substore.output_uri")
local hy2_link = output_uri.to_share_uri and output_uri.to_share_uri(n7) or nil
check("hy2 uri generated", type(hy2_link) == "string" and hy2_link:match("^hysteria2://") ~= nil)
check("hy2 uri has obfs", hy2_link and hy2_link:find("obfs=salamander", 1, true) ~= nil)
check("hy2 uri has obfs-password", hy2_link and hy2_link:find("obfs%-password=secret") ~= nil)

-- URI 回读
local res8 = hy2_link and parser.parse(hy2_link) or nil
local n8 = res8 and res8.nodes and res8.nodes[1] or {}
check("hy2 uri roundtrip obfs", n8.obfs == "salamander")
check("hy2 uri roundtrip obfs-password", n8["obfs-password"] == "secret")

-- clash_meta / sing-box 输出含混淆
local output_clash = require("substore.output_clash_meta")
local output_singbox = require("substore.output_singbox")
local cm = output_clash.generate and output_clash.generate({ n7 }) or nil
check("clash_meta hy2 obfs", type(cm) == "string" and cm:find("obfs: salamander", 1, true) ~= nil)
check("clash_meta hy2 obfs-password", type(cm) == "string" and cm:find("obfs%-password: secret") ~= nil)
local sb = output_singbox.to_outbound and output_singbox.to_outbound(n7) or nil
check("singbox hy2 obfs type", type(sb) == "table" and sb.obfs and sb.obfs.type == "salamander")
check("singbox hy2 obfs password", type(sb) == "table" and sb.obfs and sb.obfs.password == "secret")

-- vmess headerType / tls 透传
local res9 = parser.parse_local(util.json_encode({
	{ type = "vmess", server = "v.com", port = "80", uuid = "u", net = "tcp",
	  headerType = "http", host = "a.com", tls = "tls" },
}), "form")
local n9 = res9 and res9.nodes[1] or {}
check("vmess headerType passthrough", n9.headerType == "http")
check("vmess tls passthrough", n9.tls == "tls")
check("vmess type key removed", n9.type == nil)

print(string.format("%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
