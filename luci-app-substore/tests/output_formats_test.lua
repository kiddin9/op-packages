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
-- 多值 alpn 在 Surge 家族的行语法里表达不了（逗号分隔的 key=value，无转义），
-- 拼成 `alpn=h3,h2` 会被读成 `alpn=h3` 加一个悬空字段。该参数被省略、
-- 节点本身保留 —— alpn 只是协商提示，缺省时客户端用服务端给出的列表。
check("tuic alpn array omitted, node kept",
	ok_alpn and line_alpn ~= nil and line_alpn:find("alpn=", 1, true) == nil
	and line_alpn:find("tuic, 1.2.3.4, 443", 1, true) ~= nil)
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

-- ---------- 7.9：Loon 与 Surge 家族的参数名 / 写法分叉 ----------
-- 依据：nsloon.app/docs/Node/（Loon 节点行）与 manual.nssurge.com/policies/*.html
-- （Surge 家族）。两家语法在四处不同：TLS 开关名、UDP 开关名、VMess 加密方式的
-- 落点、以及凭据是否写成端口之后的位置参数。写错任何一处都不会报错，只是节点
-- 连不上 —— 所以每处分叉都钉一条断言。

-- (a) TLS 开关名：Surge 家族 tls=true，Loon over-tls=true
local vm_tls = { proto = "vmess", name = "V", server = "1.1.1.1", port = 443,
	uuid = "u", security = "tls" }
check("surge vmess tls=true", fmts.surge_line(vm_tls, "surge"):find("tls=true", 1, true) ~= nil)
check("loon vmess over-tls=true", fmts.surge_line(vm_tls, "loon"):find("over-tls=true", 1, true) ~= nil)
-- 具名参数之间是 ", " 分隔，所以独立的 tls 参数会以 ", tls=true" 出现；
-- 直接找 "tls=true" 会命中 "over-tls=true" 的子串，必须带上前导分隔符。
check("loon vmess no bare tls=true",
	fmts.surge_line(vm_tls, "loon"):find(", tls=true", 1, true) == nil)

local vl_tls = { proto = "vless", name = "L", server = "1.1.1.1", port = 443,
	uuid = "u", security = "tls" }
check("surge vless tls=true", fmts.surge_line(vl_tls, "surge"):find("tls=true", 1, true) ~= nil)
check("loon vless over-tls=true", fmts.surge_line(vl_tls, "loon"):find("over-tls=true", 1, true) ~= nil)

-- Trojan 是例外：Loon 文档的 Trojan 示例（明文与 Reality 两条）里根本没有 TLS 键
-- —— Trojan 本身就建立在 TLS 之上，Loon 不再要这个开关。Surge 家族的 tls=true
-- 则是文档要求的，不能跟着一起删。
local tj_node = { proto = "trojan", name = "T", server = "1.1.1.1", port = 443, password = "p" }
check("surge trojan tls=true", fmts.surge_line(tj_node, "surge"):find("tls=true", 1, true) ~= nil)
local loon_tj = fmts.surge_line(tj_node, "loon")
check("loon trojan has no tls key", loon_tj:find("tls", 1, true) == nil)
check("loon trojan positional password", loon_tj:find('trojan, 1.1.1.1, 443, "p"', 1, true) ~= nil)

-- (b) UDP 开关名：Surge 家族 udp-relay=true，Loon udp=true
local udp_node = { proto = "trojan", name = "U", server = "1.1.1.1", port = 443,
	password = "p", udp = true }
check("surge udp-relay=true", fmts.surge_line(udp_node, "surge"):find("udp-relay=true", 1, true) ~= nil)
local loon_udp = fmts.surge_line(udp_node, "loon")
check("loon udp=true", loon_udp:find("udp=true", 1, true) ~= nil)
check("loon has no udp-relay", loon_udp:find("udp-relay", 1, true) == nil)

-- (c) Surge 家族的 VMess 加密方式写在具名参数 encrypt-method 上，取值只有
-- aes-128-gcm / chacha20-ietf-poly1305（默认前者）。模型的 chacha20-poly1305
-- 与客户端拼写不同，不写出来 Surge 会按默认的 aes-128-gcm 去连 —— 静默用错算法。
local vm_chacha = { proto = "vmess", name = "C", server = "1.1.1.1", port = 443,
	uuid = "u", cipher = "chacha20-poly1305" }
check("surge vmess chacha mapped",
	fmts.surge_line(vm_chacha, "surge"):find("encrypt-method=chacha20-ietf-poly1305", 1, true) ~= nil)
local vm_gcm = { proto = "vmess", name = "C", server = "1.1.1.1", port = 443,
	uuid = "u", cipher = "aes-128-gcm" }
check("surge vmess aes-128-gcm",
	fmts.surge_line(vm_gcm, "surge"):find("encrypt-method=aes-128-gcm", 1, true) ~= nil)
-- 不在客户端清单里的取值（zero / none / auto / aes-128-cfb）不写该参数、节点保留：
-- 写一个客户端读不懂的取值比不写更糟
local vm_zero = { proto = "vmess", name = "C", server = "1.1.1.1", port = 443,
	uuid = "u", cipher = "zero" }
local zero_line = fmts.surge_line(vm_zero, "surge")
check("surge vmess unmapped cipher omitted",
	zero_line ~= nil and zero_line:find("encrypt-method", 1, true) == nil)
-- Loon 把加密方式放在位置参数上，不该出现具名的 encrypt-method
check("loon vmess no named encrypt-method",
	fmts.surge_line(vm_chacha, "loon"):find("encrypt-method", 1, true) == nil)

-- (d) Loon 的 shadowsocks / hysteria2 凭据同样是位置参数（密码带双引号）
local ss_node = { proto = "shadowsocks", name = "S", server = "1.1.1.1", port = 8388,
	method = "aes-256-gcm", password = "pw" }
check("surge ss named", fmts.surge_line(ss_node, "surge"):find("encrypt-method=aes-256-gcm", 1, true) ~= nil)
check("loon ss positional",
	fmts.surge_line(ss_node, "loon"):find('shadowsocks, 1.1.1.1, 8388, aes-256-gcm, "pw"', 1, true) ~= nil)

local hy_node = { proto = "hysteria2", name = "H", server = "1.1.1.1", port = 443, password = "pw" }
check("surge hysteria2 named", fmts.surge_line(hy_node, "surge"):find("password=pw", 1, true) ~= nil)
check("loon hysteria2 positional",
	fmts.surge_line(hy_node, "loon"):find('hysteria2, 1.1.1.1, 443, "pw"', 1, true) ~= nil)

-- (e) 值里含英文逗号：Loon 的引号按文档确实能保住逗号，本实现仍按「整条丢弃」
-- 处理（具名参数不带引号，同一行混用两种约定会让「哪个值被包裹」变成依赖客户端
-- 实现的行为）。这里钉住这个保守选择，避免日后被无意改成半截输出。
local ss_comma = { proto = "shadowsocks", name = "S", server = "1.1.1.1", port = 8388,
	method = "aes-256-gcm", password = "pa,ss" }
check("loon comma password drops node", fmts.surge_line(ss_comma, "loon") == nil)

-- ---------- Loon 输出 → 导入回环 ----------
-- 生成端与解析端必须成对改动：只改生成端的话，导出的 Loon 配置再导入回来会静默
-- 丢掉凭据（parser_surge 此前对 ssr 根本没有取字段的分支，对 shadowsocks /
-- hysteria2 也不认位置参数）。
local psurge = require("substore.parser_surge")
local function loon_roundtrip(node)
	return psurge.parse(fmts.to_loon({ node }, { name = "P" }))[1]
end

local rt_ss = loon_roundtrip(ss_node)
check("loon rt ss method", rt_ss and rt_ss.method == "aes-256-gcm")
check("loon rt ss password", rt_ss and rt_ss.password == "pw")

local rt_hy = loon_roundtrip(hy_node)
check("loon rt hysteria2 password", rt_hy and rt_hy.password == "pw")
check("loon rt hysteria2 security", rt_hy and rt_hy.security == "tls")

local rt_vm = loon_roundtrip(vm_tls)
check("loon rt vmess uuid", rt_vm and rt_vm.uuid == "u")
check("loon rt vmess security", rt_vm and rt_vm.security == "tls")

local rt_vl = loon_roundtrip(vl_tls)
check("loon rt vless uuid", rt_vl and rt_vl.uuid == "u")
check("loon rt vless security", rt_vl and rt_vl.security == "tls")

-- Trojan：Loon 行里不再有 TLS 开关，security 由 node.normalize 的 TLS_ONLY 补回
local rt_tj = loon_roundtrip(tj_node)
check("loon rt trojan password", rt_tj and rt_tj.password == "p")
check("loon rt trojan security", rt_tj and rt_tj.security == "tls")

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)