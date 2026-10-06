-- output_egern_test.lua — Egern 配置输出（output_egern.lua）的回归测试
-- 用法：lua5.1 tests/output_egern_test.lua
--
-- Egern 的配置是 YAML，不是 Surge 的逗号行（LEGACY_ISSUES 的 7.2）。它与本仓库
-- 其它输出端有几处**结构性**差异，每一处写错客户端都不报错、只是节点不可用，
-- 所以逐条锁住：
--
--   1. proxies 是顶层列表，每项是**单键映射**，键名即小写协议名
--      （`- shadowsocks:`），字段名一律 snake_case（user_id / peer_public_key /
--      skip_tls_verify）—— 既不是 Clash 的 network:+ws-opts，也不是 Surge 的
--      逗号行，两边的字段名都不能照抄；
--   2. vmess / vless 的传输层是 transport 子映射，键名是传输类型本身
--      （tls / ws / wss / grpc / http2）。**TLS 也是其中一种**，没有顶层 tls
--      开关 —— 「明文 tcp」就是完全不写 transport；
--   3. Reality 的嵌套位置按协议分叉：vmess / vless 在 transport.<类型>.reality
--      里，trojan / anytls 是节点顶层的 reality 对象。键名是 public_key /
--      short_id（不是统一模型的 public-key / short-id，也不是 reality-opts）；
--   4. 协议清单与 Surge 家族不同：有 VLESS 与 WireGuard，**没有** SSR 与
--      Hysteria v1 —— 后两者整条丢弃（EGERN_KEY）；
--   5. 节点名必须全局唯一（官方文档原文），与 mihomo 同一约束，复用
--      util.unique_tags。
--
-- 逐字段依据：egernapp.com/docs/configuration/example/ 与
-- .../configuration/proxies/（官方示例与协议字段表）。

package.path = "./root/usr/share/?.lua;" .. package.path

local node = require("substore.node")
local output = require("substore.output")

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

-- 输出是 table.concat(…, "\n")，**最后一行没有尾随换行**。断言行首/行尾时统一
-- 给正文补一个 "\n"，这样「某行以 X 结尾」的断言对末行同样成立。
local function has(s, sub)
	return type(s) == "string" and (s .. "\n"):find(sub, 1, true) ~= nil
end

local function N(t) return node.normalize(t) end

local function gen(nodes, opts)
	return output.generate(nodes, "egern", opts or { name = "PROXY" })
end

-- ============ 1. 顶层结构 ============

local ss = N{ proto = "shadowsocks", name = "SS", server = "1.2.3.4", port = 8388,
	method = "aes-256-gcm", password = "pw" }
local out = gen({ ss })

check("proxies is a top-level key", has(out, "proxies:"))
check("protocol is the mapping key (not a type field)",
	has(out, "  - shadowsocks:") and not has(out, "type: shadowsocks"))
check("fields are indented under the protocol key", has(out, "\n      name: SS\n"))
check("policy_groups is emitted", has(out, "policy_groups:") and has(out, "  - select:"))
check("group name and membership", has(out, "      name: PROXY\n")
	and has(out, "      policies:\n        - SS\n"))
check("snake_case field names", has(out, "password: pw") and not has(out, "Password"))
-- 统一模型的 name/server/port 三个字段在所有协议上共用
check("common fields server/port", has(out, "server: 1.2.3.4") and has(out, "port: 8388"))

-- 空节点表：proxies 必须是空**列表**（只写 `proxies:` 在 YAML 里是 null），
-- 且策略组要有合法成员
local empty = gen({})
check("empty proxies is an empty list", has(empty, "proxies: []"))
check("empty policies falls back to DIRECT", has(empty, "        - DIRECT"))

-- ============ 2. 逐协议的字段名 ============

-- shadowsocks：method + password；udp_relay 只在支持它的协议上出现
check("ss method/password", has(gen({ ss }), "method: aes-256-gcm") and has(gen({ ss }), "password: pw"))
check("ss udp_relay emitted when set",
	has(gen({ N{ proto = "shadowsocks", name = "S", server = "s", port = 1,
		method = "aes-256-gcm", password = "p", udp = true } }), "udp_relay: true"))

-- SIP003 混淆 → obfs 三件套
local ss_obfs = N{ proto = "shadowsocks", name = "SSO", server = "1.2.3.4", port = 8388,
	method = "aes-256-gcm", password = "pw", plugin = "obfs-local;obfs=http;obfs-host=bing.com" }
local o_obfs = gen({ ss_obfs })
check("ss obfs trio", has(o_obfs, "obfs: http") and has(o_obfs, "obfs_host: bing.com"))
-- v2ray-plugin 在 Egern 里没有对应字段：丢插件、保留节点（不是整条丢弃）
local ss_v2 = N{ proto = "shadowsocks", name = "SSV", server = "1.2.3.4", port = 8388,
	method = "aes-256-gcm", password = "pw", plugin = "v2ray-plugin;mode=websocket;host=h.com" }
local o_v2 = gen({ ss_v2 })
check("ss v2ray-plugin dropped, node kept",
	has(o_v2, "SSV") and not has(o_v2, "obfs") and not has(o_v2, "plugin"))

-- vmess：user_id + security（取值域与 node.VMESS_CIPHERS 一致，缺省回退 auto）
local vm = N{ proto = "vmess", name = "VM", server = "1.2.3.4", port = 443, uuid = "u-1" }
check("vmess user_id (not uuid)", has(gen({ vm }), "user_id: u-1") and not has(gen({ vm }), "uuid:"))
check("vmess security defaults to auto", has(gen({ vm }), "security: auto"))
check("vmess security keeps a whitelisted cipher",
	has(gen({ N{ proto = "vmess", name = "V", server = "s", port = 1, uuid = "u",
		cipher = "chacha20-poly1305" } }), "security: chacha20-poly1305"))

-- vless：user_id + flow
local vl = N{ proto = "vless", name = "VL", server = "1.2.3.4", port = 443, uuid = "u-1",
	flow = "xtls-rprx-vision" }
check("vless user_id/flow", has(gen({ vl }), "user_id: u-1") and has(gen({ vl }), "flow: xtls-rprx-vision"))

-- trojan：password + sni + skip_tls_verify
local tr = N{ proto = "trojan", name = "TR", server = "1.2.3.4", port = 443, password = "p",
	sni = "s.example.com", ["skip-cert-verify"] = true }
check("trojan password/sni/skip_tls_verify",
	has(gen({ tr }), "password: p") and has(gen({ tr }), "sni: s.example.com")
	and has(gen({ tr }), "skip_tls_verify: true"))

-- anytls：password（不是 auth）
local at = N{ proto = "anytls", name = "AT", server = "1.2.3.4", port = 443, password = "p" }
check("anytls password (not auth)", has(gen({ at }), "password: p") and not has(gen({ at }), "auth:"))

-- hysteria2：密码字段叫 auth，混淆叫 obfs_password
local hy = N{ proto = "hysteria2", name = "HY", server = "1.2.3.4", port = 443, password = "p",
	obfs = "salamander", ["obfs-password"] = "op" }
local o_hy = gen({ hy })
-- 注意不能用 `not has(o_hy, "password:")`：混淆字段 obfs_password 里就含这个子串
check("hysteria2 password is auth", has(o_hy, "auth: p") and not has(o_hy, "\n      password:"))
check("hysteria2 obfs/obfs_password", has(o_hy, "obfs: salamander") and has(o_hy, "obfs_password: op"))
-- obfs=plain 是「无混淆」，不能写出 `obfs: plain`
check("hysteria2 obfs=plain is omitted",
	not has(gen({ N{ proto = "hysteria2", name = "H", server = "s", port = 1, password = "p",
		obfs = "plain" } }), "obfs:"))

-- tuic：uuid + password + udp_relay_mode + alpn 列表
local tu = N{ proto = "tuic", name = "TU", server = "1.2.3.4", port = 443, uuid = "u-1",
	password = "p", ["udp-relay-mode"] = "native", alpn = "h3,h2" }
local o_tu = gen({ tu })
check("tuic uuid/password", has(o_tu, "uuid: u-1") and has(o_tu, "password: p"))
check("tuic udp_relay_mode (snake_case, not udp_relay)",
	has(o_tu, "udp_relay_mode: native") and not has(o_tu, "udp_relay: "))
check("tuic alpn is a block list", has(o_tu, "alpn:\n        - h3\n        - h2"))

-- socks5：协议键是 socks5（统一模型里叫 socks）
local so = N{ proto = "socks", name = "SO", server = "1.2.3.4", port = 1080,
	username = "usr", password = "pw" }
local o_so = gen({ so })
check("socks maps to the socks5 key", has(o_so, "  - socks5:"))
check("socks5 username/password", has(o_so, "username: usr") and has(o_so, "password: pw"))

-- wireguard：private_key + peer_public_key + local_ipv4/6（Egern 的必填组合）
local wg = N{ proto = "wireguard", name = "WG", server = "1.2.3.4", port = 51820,
	["private-key"] = "priv", ["public-key"] = "pub", ["pre-shared-key"] = "psk",
	ip = "10.0.0.2/32", reserved = "1,2,3", dns = "1.1.1.1", mtu = 1420,
	["persistent-keepalive"] = 25 }
local o_wg = gen({ wg })
check("wireguard private_key/peer_public_key",
	has(o_wg, "private_key: priv") and has(o_wg, "peer_public_key: pub"))
check("wireguard preshared_key", has(o_wg, "preshared_key: psk"))
check("wireguard local_ipv4 from ip", has(o_wg, "local_ipv4: 10.0.0.2/32"))
check("wireguard reserved/dns_servers are block lists",
	has(o_wg, "reserved:\n        - 1\n        - 2\n        - 3")
	and has(o_wg, "dns_servers:\n        - 1.1.1.1"))
check("wireguard mtu/keepalive", has(o_wg, "mtu: 1420") and has(o_wg, "keepalive: 25"))
-- wireguard 的 public-key 是**对端公钥**，绝不能被当成 Reality
check("wireguard has no reality block", not has(o_wg, "reality:"))

-- ============ 3. transport 嵌套（vmess / vless） ============

-- 明文 tcp：完全不写 transport（Egern 没有顶层 tls 开关）
check("plain tcp has no transport", not has(gen({ vm }), "transport:"))

-- ws 无 TLS → ws；ws + TLS → wss（官方把两者列为两个传输类型）
local vm_ws = N{ proto = "vmess", name = "VMW", server = "1.2.3.4", port = 443, uuid = "u-1",
	net = "ws", path = "/ws", host = "h.com" }
local o_ws = gen({ vm_ws })
check("ws transport", has(o_ws, "      transport:\n        ws:\n          path: /ws"))
check("ws headers Host", has(o_ws, "          headers:\n            Host: h.com"))

local vm_wss = N{ proto = "vmess", name = "VMWS", server = "1.2.3.4", port = 443, uuid = "u-1",
	net = "ws", security = "tls", path = "/ws", sni = "s.example.com", ["skip-cert-verify"] = true }
local o_wss = gen({ vm_wss })
check("ws + tls becomes wss", has(o_wss, "        wss:") and not has(o_wss, "        ws:\n"))
check("wss carries sni/skip_tls_verify",
	has(o_wss, "sni: s.example.com") and has(o_wss, "skip_tls_verify: true"))

-- grpc：服务名在 Egern 里叫 service_name（Clash 叫 grpc-service-name）
local vm_grpc = N{ proto = "vmess", name = "VMG", server = "1.2.3.4", port = 443, uuid = "u-1",
	net = "grpc", path = "gsvc", sni = "s.example.com" }
local o_grpc = gen({ vm_grpc })
check("grpc uses service_name", has(o_grpc, "        grpc:\n          service_name: gsvc"))
check("grpc has no grpc-service-name", not has(o_grpc, "grpc-service-name"))

-- http2
local vl_h2 = N{ proto = "vless", name = "VLH", server = "1.2.3.4", port = 443, uuid = "u-1",
	net = "h2", path = "/h2", host = "h.com", security = "tls" }
local o_h2 = gen({ vl_h2 })
check("h2 maps to the http2 transport", has(o_h2, "        http2:\n          path: /h2"))

-- ============ 4. Reality 的嵌套位置 ============

-- vmess / vless：在 transport.<类型>.reality 里（tcp+tls 时就是 transport.tls.reality）
local vmr = N{ proto = "vmess", name = "VMR", server = "1.2.3.4", port = 443, uuid = "u-1",
	["public-key"] = "PBK", ["short-id"] = "SID", sni = "s.example.com" }
local o_vmr = gen({ vmr })
check("vmess reality nested under transport", has(o_vmr, "      transport:\n        tls:\n")
	and has(o_vmr, "          reality:\n            public_key: PBK\n            short_id: SID"))
check("vmess reality uses snake_case keys, not reality-opts",
	not has(o_vmr, "reality-opts") and not has(o_vmr, "public-key:"))

-- vmess + ws + reality：reality 挂在 wss 子映射里
local vmwr = N{ proto = "vmess", name = "VMWR", server = "1.2.3.4", port = 443, uuid = "u-1",
	net = "ws", path = "/w", ["public-key"] = "PBK", ["short-id"] = "SID" }
check("vmess ws+reality nests reality under wss",
	has(gen({ vmwr }), "        wss:\n          path: /w\n          reality:\n            public_key: PBK"))

-- trojan / anytls：节点**顶层**的 reality 对象（不在 transport 里）
local trr = N{ proto = "trojan", name = "TRR", server = "1.2.3.4", port = 443, password = "p",
	["public-key"] = "PBK", ["short-id"] = "SID" }
check("trojan reality is top-level",
	has(gen({ trr }), "\n      reality:\n        public_key: PBK\n        short_id: SID"))
check("trojan reality is not inside a transport", not has(gen({ trr }), "transport:"))

local atr = N{ proto = "anytls", name = "ATR", server = "1.2.3.4", port = 443, password = "p",
	["public-key"] = "PBK", ["short-id"] = "SID" }
check("anytls reality is top-level",
	has(gen({ atr }), "\n      reality:\n        public_key: PBK\n        short_id: SID"))

-- 没有 short-id 时只写 public_key（short_id 是可选的）
local vmr2 = N{ proto = "vmess", name = "VMR2", server = "1.2.3.4", port = 443, uuid = "u-1",
	["public-key"] = "PBK" }
check("reality without short_id omits the key",
	has(gen({ vmr2 }), "public_key: PBK") and not has(gen({ vmr2 }), "short_id:"))

-- ============ 5. 协议清单：SSR 与 Hysteria v1 整条丢弃 ============

local ssr = N{ proto = "ssr", name = "SSR", server = "1.2.3.4", port = 8388,
	method = "aes-128-cfb", password = "p", protocol = "origin", obfs = "plain" }
local o_ssr = gen({ ssr })
check("ssr node is dropped entirely", not has(o_ssr, "SSR") and not has(o_ssr, "ssr:"))
check("dropping ssr leaves an empty proxies list", has(o_ssr, "proxies: []"))

-- hysteria v1 的字段结构与 v2 不同（v1 的 obfs 是普通字符串、没有 obfs_password），
-- 拿 hysteria2 的键去顶会让客户端按错误的协议去连
local hy1 = N{ proto = "hysteria", name = "HY1", server = "1.2.3.4", port = 443, password = "p" }
local o_hy1 = gen({ hy1 })
check("hysteria v1 node is dropped entirely",
	not has(o_hy1, "HY1") and not has(o_hy1, "hysteria:"))

-- 混合：可表达的节点保留，不可表达的丢弃，策略组只列保留的
local mixed = gen({ ss, ssr, hy1 })
check("mixed input keeps only expressible nodes",
	has(mixed, "SS") and not has(mixed, "SSR") and not has(mixed, "HY1"))
check("policy group lists only kept nodes", has(mixed, "        - SS\n")
	and not has(mixed, "        - SSR"))

-- ============ 6. 名字唯一性 ============

-- 官方要求节点名全局唯一；重名追加 " #2"，组名与内置策略一并占位
local dup = gen({
	N{ proto = "vmess", name = "D", server = "1.1.1.1", port = 1, uuid = "a" },
	N{ proto = "vmess", name = "D", server = "1.1.1.2", port = 2, uuid = "b" },
	N{ proto = "vmess", name = "PROXY", server = "1.1.1.3", port = 3, uuid = "c" },
})
check("duplicate names get a #N suffix",
	has(dup, '      name: D\n') and has(dup, '      name: "D #2"\n'))
check("a node named like the group is renamed",
	has(dup, '      name: "PROXY #2"\n'))
check("policies reference the renamed tags",
	has(dup, "        - D\n        - \"D #2\"\n        - \"PROXY #2\"\n"))

-- ============ 7. YAML 转义与端口 ============

-- 含 YAML c-indicator 的值必须加引号（未加引号的 `name: a: b` 会让客户端
-- 拒绝整份配置）—— 转义实现与 Clash.Meta 输出共用一份
local weird = gen({ N{ proto = "vmess", name = "a: b", server = "1.2.3.4", port = 443, uuid = "u" } })
check("names needing quotes are quoted", has(weird, '      name: "a: b"\n'))
check("quoted names are quoted in policies too", has(weird, '        - "a: b"\n'))

local pct = gen({ N{ proto = "shadowsocks", name = "P", server = "s", port = 1,
	method = "aes-256-gcm", password = "%secret" } })
check("passwords starting with % are quoted", has(pct, 'password: "%secret"'))

-- port 必须是整数：非数字值会被客户端拒绝，与 clash_meta 的兜底一致
local bad_port = gen({ N{ proto = "vmess", name = "BP", server = "s", port = "abc", uuid = "u" } })
check("non-numeric port falls back to 0", has(bad_port, "port: 0"))

-- ============ 8. 格式注册 ============

-- Egern 的内容是 YAML，后缀必须与内容一致（.conf 会被下游当成 Surge 的逗号行）
check("egern extension is yaml", output.extension_for("egern") == "yaml")
check("egern content-type is set", output.content_type_for("egern") ~= nil)
check("egern dispatches to the YAML generator", type(output.generate({ ss }, "egern", {})) == "string")

-- ---------- 结果 ----------
print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
