-- anytls_reality_test.lua — AnyTLS 协议与 Reality（VLESS/VMess/Trojan/AnyTLS）的回归测试
-- 用法：lua5.1 tests/anytls_reality_test.lua
--
-- 这个文件锁住三件容易「改一处漏一处」的事：
--   1. 各解析器读进来的 Reality 参数（分享链接的 pbk/sid/spx、Loon 的
--      public-key/short-id、QX 的 reality-base64-pubkey/reality-hex-shortid）
--      必须落到统一模型的同一组键上；
--   2. node.normalize 据 public-key 推导 security=reality，且**不能**误伤
--      wireguard（它的 public-key 是对端公钥，与 Reality 无关）；
--   3. 每个输出格式按各自客户端的文档写出 Reality 参数 —— 支持的要写全，
--      不支持的（Surge 家族、Xray、原版 Clash）一个都不能写：这些客户端的
--      协议清单里根本没有对应参数，写过去只会是客户端读不懂的噪声。
--      （早期注释写的「Surge 会拒绝加载整份配置」**未经官方证实** ——
--       官方只说明过无法识别的 *section* 会原样保留且不报错；判据是
--       「不写客户端读不懂的东西」，见 output_formats.lua 的 REALITY_FLAVORS。）
--
-- 逐条依据见各处注释引用的官方文档 / 客户端源码。

package.path = "./root/usr/share/?.lua;" .. package.path

local node = require("substore.node")
local parser = require("substore.parser")
local output = require("substore.output")
local fmts = require("substore.output_formats")

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

local function has(s, sub)
	return type(s) == "string" and s:find(sub, 1, true) ~= nil
end

-- ============ 1. 分享链接解析 ============

local r1 = parser.parse("anytls://pwd123@a.example.com:8443?sni=s.example.com&insecure=1#MyAny")
local a1 = r1.nodes[1]
check("anytls URI parsed", a1 and a1.proto == "anytls")
check("anytls URI password from userinfo", a1.password == "pwd123")
check("anytls URI server/port", a1.server == "a.example.com" and a1.port == 8443)
check("anytls URI sni", a1.sni == "s.example.com")
check("anytls URI insecure -> skip-cert-verify", a1["skip-cert-verify"] == true)
-- anytls 建立在 TLS 之上，没有明文模式
check("anytls URI security is tls", a1.security == "tls")

local r2 = parser.parse("vless://uuid-1@b.example.com:443?security=reality&pbk=PUBKEY&sid=abc123"
	.. "&spx=%2F&fp=chrome&sni=www.example.com&flow=xtls-rprx-vision#MyReality")
local v2 = r2.nodes[1]
check("vless reality URI parsed", v2 and v2.proto == "vless")
check("vless reality URI pbk -> public-key", v2["public-key"] == "PUBKEY")
check("vless reality URI sid -> short-id", v2["short-id"] == "abc123")
check("vless reality URI spx -> spider-x (url-decoded)", v2["spider-x"] == "/")
check("vless reality URI fp", v2.fp == "chrome")
check("vless reality URI flow", v2.flow == "xtls-rprx-vision")
check("vless reality URI sni", v2.sni == "www.example.com")
check("vless reality URI security", v2.security == "reality")

-- ============ 2. 行式配置解析（Loon 位置参数 / QX / Surge 具名参数） ============

-- Loon 的凭据一律是端口之后的**位置参数**且带双引号：
--   AnyTLS = AnyTLS,host,443,"password",sni=...        (nsloon.app/docs/Node/)
--   VMess  = VMess,host,443,aes-128-gcm,"uuid",...
-- 只认具名参数的话，Loon 配置导入后 uuid / password 全丢，节点被下游静默丢弃。
local loon = "[Proxy]\n"
	.. 'AnyTLS = AnyTLS,anytls.example.com,443,"password",sni=anytls.example.com,'
	.. 'public-key="LgJ9bNTyUqBLFkDA12-QgEL7c1yQ1ztk-V1Q-3OLXSk",short-id=164168844958a16d,over-tls=true\n'
	.. 'VLESS-R = VLESS,vless.example.com,443,"ae521383-9375-2e0d-c347-48cf3d98eb6e",'
	.. 'transport=tcp,flow=xtls-rprx-vision,public-key="LgJ9bNTyUqBLFkDA12-QgEL7c1yQ1ztk-V1Q-3OLXSk",'
	.. 'short-id=164168844958a16d,over-tls=true,sni=www.example.com\n'
	.. 'VMess-R = VMess,vmess.example.com,443,aes-128-gcm,"52396e06-3a1a-4e3a-9b3f-000000000001",'
	.. 'public-key="LgJ9bNTyUqBLFkDA12-QgEL7c1yQ1ztk-V1Q-3OLXSk",short-id=164168844958a16d,'
	.. 'over-tls=true,sni=www.example.com\n'
	.. 'Trojan-R = Trojan,trojan.example.com,443,"pwd",public-key="LgJ9bNTyUqBLFkDA12-QgEL7c1yQ1ztk-V1Q-3OLXSk",'
	.. 'short-id=164168844958a16d,over-tls=true,sni=t.example.com\n'

local lr = parser.parse(loon)
check("loon config parsed as surge", lr.format == "surge" and #lr.nodes == 4)
local byname = {}
for _, n in ipairs(lr.nodes) do byname[n.name] = n end

local la = byname["AnyTLS"]
check("loon anytls parsed", la and la.proto == "anytls")
check("loon anytls positional password unquoted", la.password == "password")
check("loon anytls sni", la.sni == "anytls.example.com")
check("loon anytls public-key unquoted", la["public-key"] == "LgJ9bNTyUqBLFkDA12-QgEL7c1yQ1ztk-V1Q-3OLXSk")
check("loon anytls short-id", la["short-id"] == "164168844958a16d")
check("loon anytls over-tls -> security reality", la.security == "reality")

local lv = byname["VLESS-R"]
check("loon vless positional uuid unquoted", lv.uuid == "ae521383-9375-2e0d-c347-48cf3d98eb6e")
check("loon vless flow", lv.flow == "xtls-rprx-vision")
check("loon vless reality", lv.security == "reality" and lv["public-key"] ~= nil)

local lm = byname["VMess-R"]
check("loon vmess positional cipher", lm.cipher == "aes-128-gcm")
check("loon vmess positional uuid", lm.uuid == "52396e06-3a1a-4e3a-9b3f-000000000001")
check("loon vmess reality", lm.security == "reality")

local lt = byname["Trojan-R"]
check("loon trojan positional password", lt.password == "pwd")
check("loon trojan reality", lt.security == "reality")

-- QX：Reality 的键名与别家都不同（reality-base64-pubkey / reality-hex-shortid），
-- vless 的 flow 写 vless-flow。语法取自官方 sample.conf。
local qx = "[server_local]\n"
	.. "anytls=example.com:443, password=pwd, over-tls=true, tls-host=apple.com, "
	.. "reality-base64-pubkey=k4Uxez0sjl8bKaZH2Vgi8-WDFshML51QkxKFLWFIONk, "
	.. "reality-hex-shortid=0123456789abcdef, tag=anytls-reality\n"
	.. "vless=192.168.1.1:443, method=none, password=23ad6b10-8d1a-40f7-8ad0-e3e35cd32291, "
	.. "obfs=over-tls, obfs-host=apple.com, "
	.. "reality-base64-pubkey=k4Uxez0sjl8bKaZH2Vgi8-WDFshML51QkxKFLWFIONk, "
	.. "reality-hex-shortid=0123456789abcdef, vless-flow=xtls-rprx-vision, tag=vless-reality\n"

local qr = parser.parse(qx)
check("qx config parsed", qr.format == "surge" and #qr.nodes == 2)
local qby = {}
for _, n in ipairs(qr.nodes) do qby[n.name] = n end

local qa = qby["anytls-reality"]
check("qx anytls parsed", qa and qa.proto == "anytls")
check("qx anytls password", qa.password == "pwd")
check("qx anytls tls-host -> sni", qa.sni == "apple.com")
check("qx anytls reality-base64-pubkey -> public-key",
	qa["public-key"] == "k4Uxez0sjl8bKaZH2Vgi8-WDFshML51QkxKFLWFIONk")
check("qx anytls reality-hex-shortid -> short-id", qa["short-id"] == "0123456789abcdef")
check("qx anytls security reality", qa.security == "reality")

local qv = qby["vless-reality"]
check("qx vless password -> uuid", qv.uuid == "23ad6b10-8d1a-40f7-8ad0-e3e35cd32291")
check("qx vless obfs=over-tls -> security tls", qv.security == "reality")
check("qx vless obfs-host -> sni", qv.sni == "apple.com")
check("qx vless vless-flow -> flow", qv.flow == "xtls-rprx-vision")
check("qx vless public-key", qv["public-key"] == "k4Uxez0sjl8bKaZH2Vgi8-WDFshML51QkxKFLWFIONk")
check("qx vless short-id", qv["short-id"] == "0123456789abcdef")

-- Surge 具名参数（Surge iOS 5.17.0+ / Mac 6.4.3+ 起支持 anytls）
local sr = parser.parse("[Proxy]\nSAny = anytls, 1.2.3.4, 443, password=pwd, sni=s.example.com, skip-cert-verify=1\n")
local sa = sr.nodes[1]
check("surge anytls named password", sa.password == "pwd")
check("surge anytls security tls (no reality)", sa.security == "tls")
check("surge anytls skip-cert-verify", sa["skip-cert-verify"] == true)

-- ============ 3. node.normalize 的 Reality 推导 ============

local function sec(t)
	return node.normalize(t).security
end

-- Loon 的 Reality 行写的是 over-tls=true + public-key（security 只是 tls），
-- 分享链接写 security=reality —— 两种来源都要归到同一个 security。
check("normalize anytls + public-key -> reality",
	sec({ proto = "anytls", server = "s", port = 1, password = "p", ["public-key"] = "PBK" }) == "reality")
check("normalize vless + public-key (security=tls) -> reality",
	sec({ proto = "vless", server = "s", port = 1, uuid = "u", security = "tls", ["public-key"] = "PBK" }) == "reality")
check("normalize vmess + public-key -> reality",
	sec({ proto = "vmess", server = "s", port = 1, uuid = "u", ["public-key"] = "PBK" }) == "reality")
check("normalize trojan + public-key -> reality",
	sec({ proto = "trojan", server = "s", port = 1, password = "p", ["public-key"] = "PBK" }) == "reality")

-- wireguard 的 public-key 是**对端公钥**，与 Reality 毫无关系。一旦被当成 Reality，
-- security 会变成 reality，output_singbox 就会去读 tls.reality，wireguard 节点的
-- TLS 无关字段整批丢失。
local wg = node.normalize({ proto = "wireguard", server = "s", port = 51820,
	["private-key"] = "k", ["public-key"] = "k2", ip = "10.0.0.2/32" })
check("normalize wireguard public-key does NOT mean reality", wg.security ~= "reality")

-- 不在 REALITY_PROTOS 里的协议即使带了 public-key 也不推导
check("normalize socks + public-key stays non-reality",
	sec({ proto = "socks", server = "s", port = 1, username = "u", password = "p", ["public-key"] = "PBK" }) ~= "reality")
check("normalize shadowsocks + public-key stays non-reality",
	sec({ proto = "shadowsocks", server = "s", port = 1, method = "aes-256-gcm", password = "p",
		["public-key"] = "PBK" }) ~= "reality")

-- ============ 4. 各输出格式的 Reality 参数 ============

local ANY = node.normalize({ proto = "anytls", name = "AnyX", server = "1.2.3.4", port = 443,
	password = "p", sni = "s.example.com", ["skip-cert-verify"] = true,
	["public-key"] = "PBK", ["short-id"] = "SID" })
local VLESS = node.normalize({ proto = "vless", name = "VlX", server = "1.2.3.4", port = 443,
	uuid = "u", ["public-key"] = "PBK", ["short-id"] = "SID", ["spider-x"] = "/sp",
	fp = "chrome", sni = "www.example.com", flow = "xtls-rprx-vision" })
local VMESS = node.normalize({ proto = "vmess", name = "VmX", server = "1.2.3.4", port = 443,
	uuid = "u", ["public-key"] = "PBK", ["short-id"] = "SID", fp = "chrome", sni = "www.example.com" })
local TROJAN = node.normalize({ proto = "trojan", name = "TrX", server = "1.2.3.4", port = 443,
	password = "p", ["public-key"] = "PBK", ["short-id"] = "SID", fp = "chrome", sni = "www.example.com" })

local function gen(n, f)
	return output.generate({ n }, f, { name = "PROXY" })
end

-- --- clashmeta：mihomo 的 reality-opts 只在 vless / vmess / trojan 的出站结构体里
-- （adapter/outbound/{vless,vmess,trojan}.go 的 RealityOpts），anytls.go 的
-- AnyTLSOption 里**没有**任何 reality 字段 —— 写过去会被静默忽略。
local cm_any = gen(ANY, "clashmeta")
check("clashmeta anytls type", has(cm_any, "type: anytls"))
check("clashmeta anytls password", has(cm_any, "password: p"))
check("clashmeta anytls tls true", has(cm_any, "tls: true"))
check("clashmeta anytls sni (not servername)", has(cm_any, "sni: s.example.com")
	and not has(cm_any, "servername:"))
check("clashmeta anytls has NO reality-opts", not has(cm_any, "reality-opts"))

local cm_v = gen(VLESS, "clashmeta")
check("clashmeta vless reality-opts", has(cm_v, "reality-opts:"))
check("clashmeta vless reality public-key", has(cm_v, "public-key: PBK"))
check("clashmeta vless reality short-id", has(cm_v, "short-id: SID"))
-- uTLS 指纹是代理**顶层**的 client-fingerprint，不是 reality-opts 的子键
check("clashmeta vless client-fingerprint (not fp)", has(cm_v, "client-fingerprint: chrome")
	and not has(cm_v, "\n    fp:"))

local cm_m = gen(VMESS, "clashmeta")
check("clashmeta vmess reality-opts", has(cm_m, "reality-opts:") and has(cm_m, "public-key: PBK"))
local cm_t = gen(TROJAN, "clashmeta")
check("clashmeta trojan reality-opts", has(cm_t, "reality-opts:") and has(cm_t, "public-key: PBK"))
-- wireguard 的顶层 public-key 不能被当成 reality-opts
local WG = node.normalize({ proto = "wireguard", name = "WG", server = "1.2.3.4", port = 51820,
	["private-key"] = "k", ["public-key"] = "k2", ip = "10.0.0.2/32" })
check("clashmeta wireguard has NO reality-opts", not has(gen(WG, "clashmeta"), "reality-opts"))

-- --- sing-box：tls.reality（snake_case），且 Reality 下 uTLS 是强制的
local sb_any = gen(ANY, "singbox")
check("singbox anytls type", has(sb_any, '"type":"anytls"'))
check("singbox anytls password", has(sb_any, '"password":"p"'))
check("singbox anytls reality enabled", has(sb_any, '"reality":{"enabled":true'))
check("singbox anytls reality public_key/short_id", has(sb_any, '"public_key":"PBK"')
	and has(sb_any, '"short_id":"SID"'))
local sb_v = gen(VLESS, "singbox")
check("singbox vless reality + utls", has(sb_v, '"reality":{"enabled":true')
	and has(sb_v, '"utls":{"enabled":true,"fingerprint":"chrome"}'))
check("singbox vless flow", has(sb_v, '"flow":"xtls-rprx-vision"'))

-- --- Xray / V2Ray：realitySettings（camelCase），字段名取自 REALITYConfig
local v2_v = gen(VLESS, "v2ray")
check("v2ray vless security reality", has(v2_v, '"security":"reality"'))
check("v2ray vless realitySettings publicKey", has(v2_v, '"publicKey":"PBK"'))
check("v2ray vless realitySettings shortId", has(v2_v, '"shortId":"SID"'))
check("v2ray vless realitySettings spiderX", has(v2_v, '"spiderX":"/sp"'))
check("v2ray vless realitySettings serverName/fingerprint",
	has(v2_v, '"serverName":"www.example.com"') and has(v2_v, '"fingerprint":"chrome"'))
-- Xray 不认识 anytls：节点整体丢弃，而不是生成一个非法 outbound
check("v2ray drops anytls", not has(gen(ANY, "v2ray"), "anytls"))

-- security 声称 reality 却没有 public-key：REALITYConfig.Build() 会因公钥为空报错
-- （客户端分支报 `empty "password"`），而 security == "reality" 又必须配
-- realitySettings —— 原样输出会让 Xray 拒绝加载整份配置。降级成普通 TLS。
local NOPBK = node.normalize({ proto = "vless", name = "NoPbk", server = "1.2.3.4", port = 443,
	uuid = "u", security = "reality", sni = "x.example.com" })
local v2_nopbk = gen(NOPBK, "v2ray")
check("v2ray reality without public-key -> no realitySettings",
	not has(v2_nopbk, "realitySettings"))
check("v2ray reality without public-key -> downgraded to tls",
	has(v2_nopbk, '"security":"tls"') and has(v2_nopbk, '"tlsSettings"'))

-- --- 分享链接：vless 用 pbk/sid/spx（Xray 分享链接规范）
local uri_v = gen(VLESS, "v2rayuri")
check("vless uri scheme", has(uri_v, "vless://u@1.2.3.4:443"))
check("vless uri pbk/sid/spx", has(uri_v, "pbk=PBK") and has(uri_v, "sid=SID") and has(uri_v, "spx=%2Fsp"))
check("vless uri security + flow", has(uri_v, "security=reality") and has(uri_v, "flow=xtls-rprx-vision"))
-- anytls:// 链接规范只定义了 sni / insecure，Reality 参数写进去是非法参数
local uri_a = gen(ANY, "v2rayuri")
check("anytls uri scheme", has(uri_a, "anytls://p@1.2.3.4:443"))
check("anytls uri has NO reality params", not has(uri_a, "pbk=") and not has(uri_a, "sid="))

-- --- QX：reality-base64-pubkey / reality-hex-shortid
local qx_any = gen(ANY, "qx")
check("qx anytls line", has(qx_any, "anytls=1.2.3.4:443"))
check("qx anytls password + over-tls", has(qx_any, "password=p") and has(qx_any, "over-tls=true"))
check("qx anytls tls-host", has(qx_any, "tls-host=s.example.com"))
check("qx anytls reality keys", has(qx_any, "reality-base64-pubkey=PBK")
	and has(qx_any, "reality-hex-shortid=SID"))
local qx_v = gen(VLESS, "qx")
check("qx vless flow + reality keys", has(qx_v, "vless-flow=xtls-rprx-vision")
	and has(qx_v, "reality-base64-pubkey=PBK") and has(qx_v, "reality-hex-shortid=SID"))
-- sample.conf 的 Reality 条目不止 vless / anytls：vmess 与 trojan 各有一条
-- （`;vmess=…, obfs=over-tls, …, reality-base64-pubkey=…` /
--   `;trojan=…, over-tls=true, tls-host=…, reality-base64-pubkey=…`）。
local qx_m = gen(VMESS, "qx")
check("qx vmess reality keys", has(qx_m, "reality-base64-pubkey=PBK")
	and has(qx_m, "reality-hex-shortid=SID"))
local qx_t = gen(TROJAN, "qx")
check("qx trojan over-tls + reality keys", has(qx_t, "over-tls=true")
	and has(qx_t, "reality-base64-pubkey=PBK") and has(qx_t, "reality-hex-shortid=SID"))

-- --- Surge 家族：只有 Loon 的节点行文档化了 Reality（public-key / short-id）。
-- Surge / SurgeMac / Surfboard / Egern 写 public-key 是「客户端不认识的参数」，
-- Surge 遇到无法解析的代理行会拒绝加载整份配置。
check("surge anytls named password, no reality",
	has(gen(ANY, "surge"), "anytls, 1.2.3.4, 443, password=p") and not has(gen(ANY, "surge"), "public-key"))
check("surgemac anytls named password, no reality",
	has(gen(ANY, "surgemac"), "password=p") and not has(gen(ANY, "surgemac"), "public-key"))
-- Surfboard 的 anytls 密码是端口之后的位置参数，裸值不带引号
check("surfboard anytls bare positional password",
	has(gen(ANY, "surfboard"), "anytls, 1.2.3.4, 443, p,"))
check("surfboard anytls no reality", not has(gen(ANY, "surfboard"), "public-key"))
-- Loon 的 anytls 密码是带引号的位置参数，且 Reality 参数写全
local lo_any = gen(ANY, "loon")
check("loon anytls quoted positional password", has(lo_any, 'anytls, 1.2.3.4, 443, "p",'))
check("loon anytls reality params", has(lo_any, "public-key=PBK") and has(lo_any, "short-id=SID"))
local lo_v = gen(VLESS, "loon")
check("loon vless reality params", has(lo_v, "public-key=PBK") and has(lo_v, "short-id=SID"))
-- Loon 文档的 Reality 示例覆盖 VLESS / VMess / Trojan / AnyTLS 四种节点
-- （nsloon.app/docs/Node/，原文：「public-key 和 short-id 用于 Reality」）。
local lo_m = gen(VMESS, "loon")
check("loon vmess reality params", has(lo_m, "public-key=PBK") and has(lo_m, "short-id=SID"))
local lo_t = gen(TROJAN, "loon")
check("loon trojan reality params", has(lo_t, "public-key=PBK") and has(lo_t, "short-id=SID"))
check("surge vless reality params dropped",
	not has(gen(VLESS, "surge"), "public-key") and not has(gen(VLESS, "surge"), "short-id"))
check("surge vmess reality params dropped",
	not has(gen(VMESS, "surge"), "public-key") and not has(gen(VMESS, "surge"), "short-id"))
check("surfboard trojan reality params dropped",
	not has(gen(TROJAN, "surfboard"), "public-key"))
check("egern anytls named password, no reality",
	has(gen(ANY, "egern"), "password=p") and not has(gen(ANY, "egern"), "public-key"))

-- ============ 5. 表单字段清单 ============
-- core.merge_form_node 会把「在 PROTO_FIELDS 里但表单没提交」的字段当作清空处理。
-- anytls 的 Reality 凭据不列入清单的话，用户在界面上编辑一次就把它们抹掉 ——
-- 而表单渲染的字段正是同一份清单（window.SUBSTORE_PROTO_FIELDS），
-- 所以列入即会被渲染出来，两边不会脱节。
local core = require("substore.core")
local af = node.PROTO_FIELDS.anytls
local af_set = {}
for _, k in ipairs(af) do af_set[k] = true end
check("anytls PROTO_FIELDS carries public-key", af_set["public-key"] == true)
check("anytls PROTO_FIELDS carries short-id", af_set["short-id"] == true)

local kept = core.merge_form_node(
	{ proto = "anytls", name = "A", server = "s", port = 443, password = "p",
		["public-key"] = "PBK", ["short-id"] = "SID" },
	{ proto = "anytls", name = "A2", server = "s", port = 443, password = "p",
		["public-key"] = "PBK", ["short-id"] = "SID" })
check("anytls form merge keeps reality creds",
	kept["public-key"] == "PBK" and kept["short-id"] == "SID")

-- ============ 6. surge_line 的边界 ============

-- 未知协议以前会一路掉到末尾，生成 `Name = snell, host, port` 这样的残行 ——
-- 客户端解析到不认识的类型会拒绝加载整份配置，必须整条剔除（返回 nil）。
check("surge_line unknown proto -> nil",
	fmts.surge_line({ proto = "snell", name = "S", server = "1.2.3.4", port = 443 }) == nil)

-- 参数值里的逗号没有引号 / 转义机制，会把凭据静默截断；位置参数同理
-- （Loon 的那对引号只是标记，值里的逗号照样是分隔符）。
local bad_pw = node.normalize({ proto = "anytls", name = "Bad", server = "1.2.3.4", port = 443, password = "a,b" })
check("surge_line comma in named password -> nil", fmts.surge_line(bad_pw, "surge") == nil)
check("surge_line comma in quoted positional password -> nil", fmts.surge_line(bad_pw, "loon") == nil)
check("surge_line comma in bare positional password -> nil", fmts.surge_line(bad_pw, "surfboard") == nil)

-- ============ 结果 ============
print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
