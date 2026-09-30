-- output_formats_test.lua — 13 种目标格式统一分发单元测试
-- 用法：lua5.1 tests/output_formats_test.lua

package.path = "./root/usr/share/?.lua;" .. package.path

local output = require("substore.output")
local fmts = require("substore.output_formats")
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

-- 各目标格式均返回字符串
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

-- sing-box / v2ray 自 2.4.0 起输出完整配置：outbounds 除节点外还含
-- selector / urltest（sing-box）与 direct / block，故此处不再断言节点数量，
-- 改为断言节点出站按序在前、且结构与分流齐全（详见 output_full_config_test.lua）
local singbox = output.generate(nodes, "singbox")
check("singbox is json", singbox:find("{") == 1)
local sb = util.json_decode(singbox)
check("singbox has outbounds", sb and sb.outbounds ~= nil and #sb.outbounds == 4 + 4)
check("singbox type vmess", sb and sb.outbounds[1] and sb.outbounds[1].type == "vmess")

local v2ray = output.generate(nodes, "v2ray")
local vr = util.json_decode(v2ray)
check("v2ray has outbounds", vr and vr.outbounds ~= nil and #vr.outbounds == 4 + 2)
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
-- 注意：clash 自 2.3.0-r2 起指"Clash 原版"（会过滤 vless/hysteria2/tuic/wireguard），
-- 不再是 clashmeta 的别名；clashmeta 的别名是 yaml / mihomo
check("alias yaml -> clashmeta", output.generate(nodes, "clashmeta") == output.generate(nodes, "yaml"))
check("alias mihomo -> clashmeta", output.generate(nodes, "clashmeta") == output.generate(nodes, "mihomo"))
check("alias sing_box", output.generate(nodes, "sing_box") == output.generate(nodes, "singbox"))

-- 未知格式报错
local bad, err = output.generate(nodes, "nonsense")
check("unknown format returns nil", bad == nil)
check("unknown format has err", err ~= nil)

-- 空节点
check("empty nodes ok", type(output.generate({}, "surge")) == "string")

-- H14：tuic 的 alpn 可能是数组（sing-box JSON / Clash YAML 的 alpn 列表导入后即为
-- table），直接 "alpn=" .. n.alpn 会 attempt to concatenate a table value，
-- 让整次导出直接报错。
local ok_alpn, line_alpn = pcall(fmts.surge_line, { proto = "tuic", name = "T", server = "1.2.3.4",
	port = 443, uuid = "u", password = "p", security = "tls", sni = "s.example.com",
	alpn = { "h3", "h2" } })
check("tuic alpn array does not raise", ok_alpn)
check("tuic alpn array joined", ok_alpn and line_alpn:find("alpn=h3,h2", 1, true) ~= nil)
check("tuic alpn string still works",
	fmts.surge_line({ proto = "tuic", name = "T", server = "1.2.3.4", port = 443, uuid = "u",
		alpn = "h3" }):find("alpn=h3", 1, true) ~= nil)

-- H7：节点名 / 参数值来自订阅内容（不可信输入），含换行会截断当前行并伪造出
-- 一条新的代理行。
local nl_line = fmts.surge_line({ proto = "trojan", name = "A\nB = trojan, 6.6.6.6, 443, password=x",
	server = "1.1.1.1", port = 443, password = "p", security = "tls" })
check("surge line has no newline", nl_line:find("\n") == nil)
check("surge line has no CR", nl_line:find("\r") == nil)
check("surge line keeps name prefix", nl_line:sub(1, 1) == "A")

local function count_lines(s)
	local c = 0
	for _ in s:gmatch("\n") do c = c + 1 end
	return c
end

-- 代理组行同样不能被节点名注入：压平后的名字不得让输出多出一行，
-- 也不得产生一条以注入内容开头的新行
local grp = fmts.to_surge({ { proto = "trojan", name = "G\nINJECT = trojan, 9.9.9.9, 443, password=q",
	server = "1.1.1.1", port = 443, password = "p", security = "tls" } })
local grp_ok = fmts.to_surge({ { proto = "trojan", name = "GINJECT = trojan, 9.9.9.9, 443, password=q",
	server = "1.1.1.1", port = 443, password = "p", security = "tls" } })
check("surge group newline name adds no line", count_lines(grp) == count_lines(grp_ok))
local starts_inject = false
for l in grp:gmatch("[^\n]+") do
	if l:sub(1, 6) == "INJECT" then starts_inject = true end
end
check("surge group line not injected", starts_inject == false)

-- Quantumult X：节点名含换行不得让输出多出一行
local qx_nl = fmts.to_qx({ { proto = "trojan", name = "X\nY", server = "1.1.1.1", port = 443,
	password = "p" } })
local qx_ok = fmts.to_qx({ { proto = "trojan", name = "XY", server = "1.1.1.1", port = 443,
	password = "p" } })
check("qx newline name does not add lines", count_lines(qx_nl) == count_lines(qx_ok))
check("qx newline name flattened", qx_nl:find("X Y", 1, true) ~= nil)

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)