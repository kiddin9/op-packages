-- output_formats_test.lua — 13 种目标格式统一分发单元测试
-- 用法：lua5.1 tests/output_formats_test.lua

package.path = "./root/usr/share/?.lua;" .. package.path

local output = require("substore.output")
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

local nodes = {
	{ proto = "vmess", name = "VMess Node", server = "1.1.1.1", port = 443,
	  uuid = "abc-123", net = "ws", security = "tls", sni = "example.com",
	  path = "/ws", host = "example.com" },
	{ proto = "vless", name = "VLESS Node", server = "2.2.2.2", port = 443,
	  uuid = "vless-uuid", security = "tls", sni = "example.org" },
	{ proto = "trojan", name = "Trojan Node", server = "3.3.3.3", port = 443,
	  password = "trojan-pass", sni = "example.com" },
	{ proto = "shadowsocks", name = "SS Node", server = "4.4.4.4", port = 8388,
	  method = "aes-256-gcm", password = "ss-pass" },
}

check("module exists", output ~= nil)
check("generate exists", type(output.generate) == "function")

-- 13 种目标格式均返回字符串
local formats = {
	"clash", "clashmeta", "mihomo", "stash",
	"surge", "surfboard", "surgemac", "loon", "egern",
	"qx", "singbox", "v2ray", "v2rayuri", "shadowrocket", "plain",
}

for _, f in ipairs(formats) do
	local s, err = output.generate(nodes, f)
	check("generate " .. f .. " returns string", type(s) == "string" and (not err))
	print("       ", err or "")
end

-- 格式头检查
local surge = output.generate(nodes, "surge")
check("surge has [Proxy]", surge:find("%[Proxy%]") ~= nil)
check("surge has vmess line", surge:find("VMess Node = vmess") ~= nil)
check("surge has ss line", surge:find("SS Node = shadowsocks") ~= nil)

local qx = output.generate(nodes, "qx")
check("qx has [server_local]", qx:find("%[server_local%]") ~= nil)
check("qx has vmess line", qx:find("vmess=1.1.1.1:443") ~= nil)
check("qx has policy", qx:find("%[policy%]") ~= nil)

local singbox = output.generate(nodes, "singbox")
check("singbox is json", singbox:find("{") == 1)
local sb = util.json_decode(singbox)
check("singbox has outbounds", sb and sb.outbounds ~= nil and #sb.outbounds == 4)
check("singbox type vmess", sb and sb.outbounds[1] and sb.outbounds[1].type == "vmess")

local v2ray = output.generate(nodes, "v2ray")
local vr = util.json_decode(v2ray)
check("v2ray has outbounds", vr and vr.outbounds ~= nil and #vr.outbounds == 4)
check("v2ray protocol vmess", vr and vr.outbounds[1] and vr.outbounds[1].protocol == "vmess")

local uri = output.generate(nodes, "v2rayuri")
check("uri list has vmess", uri:find("vmess://") ~= nil)
check("uri list has vless", uri:find("vless://") ~= nil)
check("uri list has trojan", uri:find("trojan://") ~= nil)
check("uri list has ss", uri:find("ss://") ~= nil)

local rocket = output.generate(nodes, "shadowrocket")
local dec = util.base64_decode(rocket)
check("shadowrocket is base64 of uri", dec:find("vmess://") ~= nil)

local plain = output.generate(nodes, "plain")
local pj = util.json_decode(plain)
check("plain is json array", type(pj) == "table" and pj[1] ~= nil and pj[1].proto == "vmess")

-- 别名映射
check("alias clashmeta", output.generate(nodes, "clashmeta") == output.generate(nodes, "clash"))
check("alias sing_box", output.generate(nodes, "sing_box") == output.generate(nodes, "singbox"))

-- 未知格式报错
local bad, err = output.generate(nodes, "nonsense")
check("unknown format returns nil", bad == nil)
check("unknown format has err", err ~= nil)

-- 空节点
check("empty nodes ok", type(output.generate({}, "surge")) == "string")

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)