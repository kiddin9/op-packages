-- p1_fixes_test.lua — P1 批次缺陷修复的回归测试
-- 用法：lua5.1 tests/p1_fixes_test.lua
--
-- 覆盖本轮修复（每项都先在修改前用探针复现过，再断言修复后的行为）：
--   M1  trojan 密码未做 url_decode
--   M2  vmess classic JSON 忽略 host / path
--   M3  SSR 密码 base64 回退不可达
--   M4  vless/trojan/vmess/hysteria2/tuic/ss 缺 host/port 校验
--   M5  sing-box YAML 嵌套 tls: map 被跳过（含嵌套序列 alpn / utls.fingerprint）
--   M7  通用 JSON 节点路径忽略 type 字段、无协议白名单
--   M8  Surge 段名大小写敏感（[PROXY] 不识别）
--   M10 userinfo 按首个 @ 切分（密码含 @ 时错位）
--   M12 core.load 遇到非 table 条目直接崩溃
--   M15 改名替换串里的 % 未转义（吞字符 / 注入 NUL 字节）
--   M20 output_v2ray.supported() 只排除 ssr
--   M21 clashmeta 从不写 flow
--   M22 clashmeta 丢弃 grpc / h2 传输参数
--   另：Surge/QX 未知协议白名单（H6 的 Surge 侧）、简易 YAML 嵌套序列

package.path = "./root/usr/share/?.lua;" .. package.path

local util = require("substore.util")
local parser = require("substore.parser")
local surge = require("substore.parser_surge")
local node = require("substore.node")
local core = require("substore.core")
local output = require("substore.output")
local output_clash_meta = require("substore.output_clash_meta")

local passed, failed = 0, 0
local function check(name, cond)
	if cond then passed = passed + 1; print("PASS " .. name)
	else failed = failed + 1; print("FAIL " .. name) end
end

-- 解析单条 URI，返回节点（或 nil）
local function one(uri)
	local r = parser.parse(uri)
	return r and r.nodes and r.nodes[1] or nil
end

-- ---------- M1：trojan 密码必须 url_decode ----------
-- 未解码时密码会是字面量 "p%40ss%3Aword"，认证必然失败。
local t1 = one("trojan://p%40ss%3Aword@1.2.3.4:443?sni=a.com#T")
check("M1 trojan parsed", t1 ~= nil and t1.proto == "trojan")
check("M1 trojan password url_decoded", t1 and t1.password == "p@ss:word")
check("M1 trojan server/port", t1 and t1.server == "1.2.3.4" and t1.port == 443)

-- ---------- M2：vmess classic JSON 的 host / path ----------
-- 未修复时 ws 的 Host 头与 path 全丢，服务端按默认路径匹配失败。
local vm_json = util.json_encode({
	v = "2", ps = "V", add = "1.2.3.4", port = "443", id = "u", aid = "0",
	net = "ws", type = "none", host = "ws.example.com", path = "/vmpath",
	tls = "tls", sni = "a.com",
})
local t2 = one("vmess://" .. util.base64_encode(vm_json))
check("M2 vmess classic parsed", t2 ~= nil and t2.proto == "vmess")
check("M2 vmess keeps host", t2 and t2.host == "ws.example.com")
check("M2 vmess keeps path", t2 and t2.path == "/vmpath")
check("M2 vmess keeps net", t2 and t2.net == "ws")

-- 未提供 host/path 时不应凭空造出字段
local t2b = one("vmess://" .. util.base64_encode(util.json_encode({
	v = "2", ps = "V2", add = "1.2.3.4", port = "443", id = "u", aid = "0", net = "tcp",
})))
check("M2 absent host stays nil", t2b and t2b.host == nil)
check("M2 absent path stays nil", t2b and t2b.path == nil)

-- ---------- M3：SSR 密码 base64 回退 ----------
-- 密码为纯 base64（非 base64url）时也必须解出明文，而不是乱码。
local ssr_main = "1.2.3.4:8080:origin:aes-128-cfb:plain:"
	.. util.base64_url_encode("plainpass")
	.. "/?remarks=" .. util.base64_url_encode("SSR")
local t3 = one("ssr://" .. util.base64_url_encode(ssr_main))
check("M3 ssr parsed", t3 ~= nil and t3.proto == "ssr")
check("M3 ssr password decoded", t3 and t3.password == "plainpass")
check("M3 ssr remarks decoded", t3 and t3.name == "SSR")
check("M3 ssr method/protocol/obfs", t3 and t3.method == "aes-128-cfb"
	and t3.protocol == "origin" and t3.obfs == "plain")

-- 非 ASCII 备注必须原样还原（base64url → UTF-8），不能被解成乱码
local ssr_plain = "1.2.3.4:8080:origin:aes-128-cfb:plain:"
	.. util.base64_url_encode("p") .. "/?remarks=" .. util.base64_url_encode("香港节点")
local t3b = one("ssr://" .. util.base64_url_encode(ssr_plain))
check("M3 ssr utf8 remarks preserved", t3b and t3b.name == "香港节点")

-- 外层用 base64url 字母表（含 - / _）的 ssr:// 链接同样必须正确解析。
-- 标准 base64 解码会把 -/_ 当非法字符**剔除**（util.lua 的 `[^%w%+/=]`），
-- 整串少掉若干字符、解成乱码，且不报错——用户只看到一个连不上的节点。
-- 这里的 server 取 1.2.3.100 是因为该 body 的标准 base64 恰好含 "/"，
-- base64url 编码后变成 "_"（已实测确认）。
local ssr_b64u = "1.2.3.100:8080:origin:aes-128-cfb:plain:"
	.. util.base64_url_encode("pw") .. "/?remarks=" .. util.base64_url_encode("U")
local outer = util.base64_url_encode(ssr_b64u)
check("M3 outer really uses base64url alphabet",
	outer:find("-", 1, true) ~= nil or outer:find("_", 1, true) ~= nil)
-- 前提校验：用标准 base64 解码这份 base64url 串确实会出错（复现原缺陷）
local t3c_std = one("ssr://" .. outer)
check("M3 base64url outer decodes", t3c_std ~= nil and t3c_std.proto == "ssr")
check("M3 base64url outer server", t3c_std and t3c_std.server == "1.2.3.100")
check("M3 base64url outer password", t3c_std and t3c_std.password == "pw")
check("M3 base64url outer name", t3c_std and t3c_std.name == "U")
-- 标准 base64 外层仍然照旧
local outer_std = util.base64_encode(ssr_b64u)
local t3d = one("ssr://" .. outer_std)
check("M3 standard outer still works", t3d ~= nil and t3d.proto == "ssr"
	and t3d.server == "1.2.3.100" and t3d.password == "pw")

-- ---------- M4：host / port 校验 ----------
-- 残缺节点会被写成 `server: ` / `port: 0`，mihomo 与 sing-box 会拒绝加载
-- 整份配置——一个节点废掉整个订阅。
local bad_uris = {
	["vless port 0"] = "vless://uuid@1.2.3.4:0#A",
	["vless port missing"] = "vless://uuid@1.2.3.4#B",
	["vless port > 65535"] = "vless://uuid@1.2.3.4:99999#C",
	["trojan port 0"] = "trojan://p@1.2.3.4:0#D",
	["ss port 0"] = "ss://YWVzLTI1Ni1nY206cA==@1.2.3.4:0#E",
	["hysteria2 port missing"] = "hysteria2://p@1.2.3.4#F",
	["tuic port 0"] = "tuic://u:p@1.2.3.4:0#G",
}
for label, uri in pairs(bad_uris) do
	local r = parser.parse(uri)
	check("M4 dropped: " .. label, r ~= nil and #r.nodes == 0)
end

-- 合法边界值必须保留
local ok_port = one("vless://uuid@1.2.3.4:65535#OK")
check("M4 keeps port 65535", ok_port ~= nil and ok_port.port == 65535)
local ok_port1 = one("vless://uuid@1.2.3.4:1#OK1")
check("M4 keeps port 1", ok_port1 ~= nil and ok_port1.port == 1)

-- ---------- M5：sing-box YAML 嵌套 tls: map ----------
-- tls 是嵌套 map，且内部还含嵌套序列（alpn）与嵌套 map（utls）。
-- 未修复时整层 TLS 丢失：trojan/vmess/vless 静默退化成明文，
-- hysteria2/tuic 让客户端以 C.ErrTLSRequired 拒绝启动。
local sb_yaml = [[
outbounds:
  - type: vless
    tag: sb
    server: 1.2.3.4
    server_port: 443
    uuid: u-1
    flow: xtls-rprx-vision
    tls:
      enabled: true
      server_name: sni.example.com
      insecure: true
      alpn:
        - h2
        - http/1.1
      utls:
        enabled: true
        fingerprint: chrome
]]
local t5 = one(sb_yaml)
check("M5 sing-box yaml parsed", t5 ~= nil and t5.proto == "vless")
check("M5 tls enabled -> security", t5 and t5.security == "tls")
check("M5 server_name -> sni", t5 and t5.sni == "sni.example.com")
check("M5 insecure -> skip-cert-verify", t5 and t5["skip-cert-verify"] == true)
check("M5 flow preserved", t5 and t5.flow == "xtls-rprx-vision")
check("M5 alpn nested sequence", t5 and type(t5.alpn) == "table"
	and t5.alpn[1] == "h2" and t5.alpn[2] == "http/1.1")
-- utls 排在 alpn 之后：若嵌套序列不被支持，read_map 会在 alpn 处截断，
-- 这个键会连带消失（这正是 read_seq 要解决的问题）
check("M5 utls fingerprint -> fp", t5 and t5.fp == "chrome")
-- 嵌套 map 不得以 table 形式漏到 tls 字段（table 恒为真值，
-- 会被下游的 `if n.tls then` 当成「已启用 TLS」）
check("M5 tls table not leaked", t5 and type(t5.tls) ~= "table")

-- tls.enabled 为假时不得开启 TLS。
-- 用 vless 而非 trojan：trojan 是 TLS-only，node.DEFAULTS 会强制补 security="tls"，
-- 用它测不出「tls 块存在但未启用」这条分支（vless 的默认值是 "none"）。
local sb_off = [[
outbounds:
  - type: vless
    tag: off
    server: 1.2.3.4
    server_port: 443
    uuid: u-off
    tls:
      enabled: false
      server_name: s.example.com
]]
local t5b = one(sb_off)
check("M5 tls disabled stays off", t5b and (t5b.security == nil or t5b.security == "none"))

-- ---------- M7：通用 JSON 节点用 type 映射协议 + 白名单 ----------
local t7 = one(util.json_encode({
	{ type = "trojan", server = "1.2.3.4", port = 443, password = "p", name = "J" },
}))
check("M7 json type -> proto", t7 ~= nil and t7.proto == "trojan")
check("M7 json password kept", t7 and t7.password == "p")
-- type 已被消费为协议，不能原样留在节点上（vmess 的 type 是 header 类型，语义不同）
check("M7 type consumed", t7 and t7.type == nil)

-- 未知类型必须丢弃，而不是兜底成 vmess 造出字段全错的假节点
local t7b = parser.parse(util.json_encode({
	{ type = "snell", server = "1.2.3.4", port = 443, password = "p" },
}))
check("M7 unknown type dropped", t7b ~= nil and #t7b.nodes == 0)

-- 无 server/port 的条目丢弃
local t7c = parser.parse(util.json_encode({
	{ type = "vmess", server = "", port = 443, uuid = "u" },
}))
check("M7 empty server dropped", t7c ~= nil and #t7c.nodes == 0)

-- ---------- M8：Surge 段名大小写不敏感 ----------
check("M8 is_config [Proxy]", surge.is_config("[Proxy]\nA = vmess, 1.2.3.4, 443\n"))
check("M8 is_config [PROXY]", surge.is_config("[PROXY]\nA = vmess, 1.2.3.4, 443\n"))
check("M8 is_config [server_local]", surge.is_config("[server_local]\nvmess=1.2.3.4:443\n"))
check("M8 is_config negative", not surge.is_config("proxies:\n  - name: x\n"))
-- 全大写段名必须能整份解析（未修复时被判成 JSON 数组 → 整份报错）
local t8 = parser.parse("[PROXY]\nA = vmess, 1.2.3.4, 443, username=u\n")
check("M8 uppercase section parses", t8 ~= nil and #t8.nodes == 1)
check("M8 uppercase node proto", t8 and t8.nodes[1] and t8.nodes[1].proto == "vmess")

-- Surge / QX 未知协议白名单（H6 的 Surge 侧）
check("M8/H6 surge unknown proto dropped",
	#surge.parse("[Proxy]\nA = snell, 1.2.3.4, 443, psk=x\n") == 0)
check("M8/H6 qx unknown proto dropped",
	#surge.parse("[server_local]\nssh=1.2.3.4:22, password=p\n") == 0)
-- 已知协议仍正常
check("M8/H6 surge known proto kept",
	#surge.parse("[Proxy]\nA = trojan, 1.2.3.4, 443, password=p\n") == 1)

-- ---------- M10：userinfo 按最后一个 @ 切分 ----------
-- 密码里含未转义的 @ 时，按首个 @ 切分会把密码截断、host 变成 "ss@1.2.3.4"。
local t10 = one("hysteria2://p@ss@1.2.3.4:443?sni=a.com#H")
check("M10 hysteria2 parsed", t10 ~= nil and t10.proto == "hysteria2")
check("M10 password keeps @", t10 and t10.password == "p@ss")
check("M10 server correct", t10 and t10.server == "1.2.3.4")
check("M10 port correct", t10 and t10.port == 443)

-- 多个 @ 也按最后一个切
local t10b = one("trojan://a@b@c@1.2.3.4:443#T")
check("M10 multiple @ in password", t10b and t10b.password == "a@b@c"
	and t10b.server == "1.2.3.4")

-- ---------- M12：core.load 遇坏条目不崩溃 ----------
local tmp = os.tmpname() .. "_p1fix"
os.remove(tmp)
core.DATA_DIR = tmp
core.LIST_FILE = tmp .. "/subscriptions.json"
core.NODES_DIR = tmp .. "/nodes"
core.ensure_dirs()
os.execute("mkdir -p " .. util.shq(tmp))
local fh = io.open(core.LIST_FILE, "w")
fh:write('{"seq":3,"items":{"good":{"name":"G","url":"http://e.com/s"},"bad":"not-a-table"}}')
fh:close()

-- 未修复时 M.list 里的 pairs(meta) 会抛
-- "bad argument #1 to 'pairs' (table expected, got string)"，订阅列表页直接 500。
-- 注意 core.load 是模块内局部函数，对外只能通过 core.list() 观察。
local arr, lerr = core.list()
check("M12 list does not crash", type(arr) == "table")
check("M12 good entry kept", #arr == 1 and arr[1].id == "good" and arr[1].name == "G")
check("M12 corruption reported", type(lerr) == "string" and lerr:find("corrupted") ~= nil)

-- 坏条目不能因为「静默过滤」而被当成正常列表：写路径必须拒绝落盘，
-- 否则下一次 save 会把坏条目永久抹掉
local wrote = core.save_meta("good", { upload = 1 })
check("M12 write refused on corruption", wrote == nil or wrote == false)

-- 全部条目合法时不报错
local fh2 = io.open(core.LIST_FILE, "w")
fh2:write('{"_seq":4,"items":{"a":{"name":"A"}}}')
fh2:close()
local arr2, lerr2 = core.list()
check("M12 clean file no error", lerr2 == nil and #arr2 == 1 and arr2[1].id == "a")
os.execute("rm -rf " .. util.shq(tmp))

-- ---------- M15：改名替换串的 % 与 $ ----------
local function rename_one(name, rules)
	local ns = node.rename_with_rules(
		{ { name = name, proto = "vmess", server = "1.2.3.4", port = 443 } }, rules)
	return ns[1].name
end

-- 结尾的 % 未转义会注入 NUL 字节（"100%" → "100\0"），
-- 节点名会写进节点文件并下发给所有客户端
local m15a = rename_one("x", { { type = "regex", pattern = "x", replacement = "100%" } })
check("M15 trailing percent preserved", m15a == "100%")
check("M15 no NUL injected", m15a:find("%z") == nil)
check("M15 percent length exact", #m15a == 4)

-- % 后接非数字字符未转义会被静默吞掉（"50%off" → "50off"）
local m15b = rename_one("x", { { type = "regex", pattern = "x", replacement = "50%off" } })
check("M15 percent before letter preserved", m15b == "50%off")
check("M15 percent before letter length", #m15b == 6)

-- 捕获引用仍可用
local m15c = rename_one("ab", { { type = "regex", pattern = "(a)(b)", replacement = "$2$1" } })
check("M15 backreference still works", m15c == "ba")

-- %% 按字面 % 处理（用户写了两个就得到两个）
local m15d = rename_one("x", { { type = "regex", pattern = "x", replacement = "a%%b" } })
check("M15 double percent literal", m15d == "a%%b")

-- ---------- M20：output_v2ray 协议白名单 ----------
-- Xray 只认 vmess/vless/trojan/shadowsocks/socks/http；其余协议没有对应
-- outbound 类型，写成 `"protocol": "hysteria2"` 会让 Xray 拒绝整份配置。
local m20_nodes = {
	{ proto = "vmess", name = "V", server = "1.1.1.1", port = 443, uuid = "u" },
	{ proto = "vless", name = "L", server = "2.2.2.2", port = 443, uuid = "u2" },
	{ proto = "trojan", name = "T", server = "3.3.3.3", port = 443, password = "p" },
	{ proto = "ss", name = "S", server = "4.4.4.4", port = 8388, method = "aes-256-gcm", password = "p" },
	{ proto = "socks", name = "SK", server = "5.5.5.5", port = 1080, username = "u", password = "p" },
	{ proto = "hysteria2", name = "H2", server = "6.6.6.6", port = 443, password = "p" },
	{ proto = "hysteria", name = "H1", server = "7.7.7.7", port = 443, password = "p" },
	{ proto = "tuic", name = "TU", server = "8.8.8.8", port = 443, uuid = "u3", password = "p" },
	{ proto = "wireguard", name = "WG", server = "9.9.9.9", port = 51820, ["private-key"] = "k" },
	{ proto = "ssr", name = "SSR", server = "10.10.10.10", port = 8080, password = "p" },
}
local m20_out = output.generate(m20_nodes, "v2ray")
local m20_cfg = util.json_decode(m20_out)
local m20_protos = {}
for _, o in ipairs(m20_cfg and m20_cfg.outbounds or {}) do
	m20_protos[o.protocol] = true
end
for _, bad in ipairs({ "hysteria2", "hysteria", "tuic", "wireguard", "ssr" }) do
	check("M20 v2ray drops " .. bad, not m20_protos[bad])
end
check("M20 v2ray keeps vmess", m20_protos.vmess)
check("M20 v2ray keeps vless", m20_protos.vless)
check("M20 v2ray keeps trojan", m20_protos.trojan)
check("M20 v2ray maps ss ->shadowsocks", m20_protos.shadowsocks)
check("M20 v2ray keeps socks", m20_protos.socks)
check("M20 v2ray keeps freedom/blackhole", m20_protos.freedom and m20_protos.blackhole)
-- 被放行的 socks 凭据必须真的写进 users（否则等于放行了个空壳）
local m20_socks
for _, o in ipairs(m20_cfg.outbounds) do
	if o.protocol == "socks" then m20_socks = o end
end
check("M20 socks credentials kept", m20_socks ~= nil
	and m20_socks.settings.servers[1].users[1].user == "u")
local m20_ss
for _, o in ipairs(m20_cfg.outbounds) do
	if o.protocol == "shadowsocks" then m20_ss = o end
end
check("M20 ss method kept", m20_ss ~= nil
	and m20_ss.settings.servers[1].method == "aes-256-gcm")
-- 被丢弃的节点不能残留出站（tag 会进 balancer selector）
check("M20 dropped nodes produce no outbound",
	#m20_cfg.outbounds == 7) -- vmess/vless/trojan/ss/socks + freedom/blackhole

-- ---------- M21：clashmeta 写 flow ----------
-- flow 是 XTLS Vision（xtls-rprx-vision）的必需参数；不写的话 mihomo 按普通
-- vless 处理，服务端要求 vision 时握手失败。surge / v2ray / URI 三个输出都写
-- flow，只有 clashmeta 漏了。
local m21 = output_clash_meta.generate({
	{ proto = "vless", name = "L", server = "1.1.1.1", port = 443,
		uuid = "u", flow = "xtls-rprx-vision", security = "tls", sni = "e.com" },
})
check("M21 vless flow written", m21:find("flow: xtls%-rprx%-vision") ~= nil)
-- vmess 没有 flow 概念，不得凭空写出该键
local m21b = output_clash_meta.generate({
	{ proto = "vmess", name = "V", server = "1.1.1.1", port = 443, uuid = "u" },
})
check("M21 vmess has no flow", m21b:find("flow:", 1, true) == nil)
-- 无 flow 的 vless 也不写空键
local m21c = output_clash_meta.generate({
	{ proto = "vless", name = "L2", server = "1.1.1.1", port = 443, uuid = "u" },
})
check("M21 vless without flow omits key", m21c:find("flow:", 1, true) == nil)

-- ---------- M22：clashmeta 的 grpc / h2 传输参数 ----------
-- 只写 network: grpc 时客户端用默认服务名去连，握手失败——与 ws 丢 path 同类。
-- 键名对照上游 transport 文档：grpc-service-name（带 grpc- 前缀）；
-- 服务名存在 node.path（与 output_v2ray 的 serviceName、sing-box 的 service_name 同源）。
local m22g = output_clash_meta.generate({
	{ proto = "vless", name = "G", server = "1.1.1.1", port = 443,
		uuid = "u", net = "grpc", path = "my-grpc-svc", security = "tls" },
})
check("M22 grpc network written", m22g:find("network: grpc") ~= nil)
check("M22 grpc-opts block", m22g:find("grpc%-opts:") ~= nil)
check("M22 grpc-service-name", m22g:find("grpc%-service%-name: my%-grpc%-svc") ~= nil)

-- h2-opts.host 是**列表**，h2-opts.path 是标量（上游 transport 文档）
local m22h = output_clash_meta.generate({
	{ proto = "trojan", name = "H", server = "2.2.2.2", port = 443, password = "p",
		net = "h2", path = "/h2path", host = "h2.example.com" },
})
check("M22 h2 network written", m22h:find("network: h2") ~= nil)
check("M22 h2-opts block", m22h:find("h2%-opts:") ~= nil)
check("M22 h2 host is a list", m22h:find("host:\n        %- h2%.example%.com") ~= nil)
check("M22 h2 path scalar", m22h:find("path: /h2path") ~= nil)

-- 无 path 的 grpc 节点不写出空 grpc-opts 块
local m22e = output_clash_meta.generate({
	{ proto = "vless", name = "E", server = "4.4.4.4", port = 443, uuid = "u", net = "grpc" },
})
check("M22 grpc without path omits opts", m22e:find("grpc%-opts:", 1, true) == nil)

-- grpc 节点不得写出 h2-opts，反之亦然
check("M22 grpc has no h2-opts", m22g:find("h2%-opts:", 1, true) == nil)
check("M22 h2 has no grpc-opts", m22h:find("grpc%-opts:", 1, true) == nil)

-- ws 行为不变（回归保护）
local m22w = output_clash_meta.generate({
	{ proto = "vmess", name = "W", server = "3.3.3.3", port = 443, uuid = "u",
		net = "ws", path = "/ws", host = "ws.example.com" },
})
check("M22 ws-opts unchanged", m22w:find("ws%-opts:") ~= nil
	and m22w:find("path: /ws") ~= nil
	and m22w:find("Host: ws%.example%.com") ~= nil)

-- ---------- 结果 ----------
print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
