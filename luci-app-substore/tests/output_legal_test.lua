-- output_legal_test.lua — 输出层「生成的配置必须能被目标客户端加载」回归测试
-- 用法：lua5.1 tests/output_legal_test.lua
--
-- 覆盖 P2 批次三：
--   M19  QX [policy] 引用未定义的服务器（悬空引用）
--   M23  wireguard 的 allowed-ips / reserved / dns 以字符串形态原样透传
--   M24  hysteria2/hysteria 分享链接只读 insecure，丢掉 skip-cert-verify
--   M25  trojan/tuic 分享链接 alpn 为数组时输出 "table: 0x..."
--   M27  未加引号的 YAML 标量里反斜杠被翻倍
--   L21  成员列表里含逗号的名字被当成两个成员
--   L22  非数字 port 原样输出

package.path = "./root/usr/share/?.lua;" .. package.path

local node = require("substore.node")
local clash_meta = require("substore.output_clash_meta")
local singbox = require("substore.output_singbox")
local uri = require("substore.output_uri")
local formats = require("substore.output_formats")

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

-- 取出第一行匹配 pattern 的整行
local function line_with(text, pattern)
	for l in text:gmatch("[^\n]+") do
		if l:find(pattern) then return l end
	end
	return nil
end

-- ---------- M27：未加引号的标量里反斜杠不得翻倍 ----------
-- need_quote 的触发集里没有反斜杠，所以 `pa\ss` 会走「不加引号」这条路；
-- 转义若在判定之前无条件执行，输出就是 `pa\\ss`，YAML 回读得到两个反斜杠。
local bs = node.normalize({ proto = "trojan", server = "1.2.3.4", port = 443,
	password = "pa\\ss", name = "BS" })
local bs_line = line_with(clash_meta.generate({ bs }), "password")
check("M27 plain scalar keeps single backslash",
	bs_line == "    password: pa\\ss")
check("M27 plain scalar not doubled", not bs_line:find("pa\\\\ss", 1, true))

-- 含 `:` 时必须加引号，加引号时反斜杠才需要转义
local bq = node.normalize({ proto = "trojan", server = "1.2.3.4", port = 443,
	password = "pa\\ss: x", name = "BQ" })
local bq_line = line_with(clash_meta.generate({ bq }), "password")
check("M27 quoted scalar escapes backslash",
	bq_line == '    password: "pa\\\\ss: x"')

-- ---------- M23：wireguard 数组字段在字符串形态下也要输出成列表 ----------
-- mihomo 的 allowed-ips / dns 是 []string、reserved 是 []uint8，只接受列表；
-- 写成标量会让它拒绝加载整份配置。字符串来源：表单导入、URI 导入、.conf 导入。
local wg_str = node.normalize({
	proto = "wireguard", server = "1.2.3.4", port = 51820, name = "WS",
	["private-key"] = "k", ["public-key"] = "p",
	["allowed-ips"] = "0.0.0.0/0, ::/0", reserved = "1,2,3", dns = "1.1.1.1, 8.8.8.8",
})
local cm_str = clash_meta.generate({ wg_str })
check("M23 clash allowed-ips is a list",
	cm_str:find("\n      %- 0%.0%.0%.0/0\n") ~= nil
	and cm_str:find("\n      %- \"::/0\"\n") ~= nil)
check("M23 clash reserved is a list",
	cm_str:find("\n      %- 1\n") ~= nil and cm_str:find("\n      %- 3\n") ~= nil)
check("M23 clash dns is a list",
	cm_str:find("\n      %- 1%.1%.1%.1\n") ~= nil
	and cm_str:find("\n      %- 8%.8%.8%.8\n") ~= nil)
check("M23 clash no scalar allowed-ips",
	line_with(cm_str, "allowed%-ips:") == "    allowed-ips:")
check("M23 clash no scalar reserved",
	line_with(cm_str, "reserved:") == "    reserved:")

-- 数组形态（Clash YAML 嵌套列表导入）不能被破坏
local wg_tbl = node.normalize({
	proto = "wireguard", server = "1.2.3.4", port = 51820, name = "WT",
	["private-key"] = "k", ["public-key"] = "p",
	["allowed-ips"] = { "0.0.0.0/0", "::/0" }, reserved = { 1, 2, 3 }, dns = { "1.1.1.1" },
})
local cm_tbl = clash_meta.generate({ wg_tbl })
check("M23 clash table form still a list",
	cm_tbl:find("\n      %- 0%.0%.0%.0/0\n") ~= nil
	and cm_tbl:find("\n      %- 1%.1%.1%.1\n") ~= nil)

-- sing-box：allowed_ips / dns 是 []string，reserved 是 []uint8（必须是数字）
local sb_str = singbox.generate({ wg_str })
check("M23 singbox allowed_ips array",
	sb_str:find('"allowed_ips":%["0%.0%.0%.0/0","::/0"%]') ~= nil)
check("M23 singbox allowed_ips not string",
	sb_str:find('"allowed_ips":"', 1, true) == nil)
check("M23 singbox reserved numeric array",
	sb_str:find('"reserved":%[1,2,3%]') ~= nil)
check("M23 singbox reserved not string",
	sb_str:find('"reserved":"', 1, true) == nil)
check("M23 singbox dns array",
	sb_str:find('"dns":%["1%.1%.1%.1","8%.8%.8%.8"%]') ~= nil)

-- 空值不得产出空列表（`allowed-ips: []` 同样是非法值）
local wg_empty = node.normalize({
	proto = "wireguard", server = "1.2.3.4", port = 51820, name = "WE",
	["private-key"] = "k", ["public-key"] = "p", ["allowed-ips"] = "",
})
check("M23 empty allowed-ips omitted (clash)",
	line_with(clash_meta.generate({ wg_empty }), "allowed%-ips") == nil)
check("M23 empty allowed-ips omitted (singbox)",
	singbox.generate({ wg_empty }):find("allowed_ips", 1, true) == nil)

-- ---------- L22：非数字 port ----------
-- sing-box / v2ray 一直用 tonumber() or 0 兜底，clash 输出此前原样透传
local badport = { proto = "trojan", server = "1.2.3.4", port = "abc",
	password = "p", name = "BP" }
check("L22 non-numeric port falls back to 0",
	line_with(clash_meta.generate({ badport }), "port:") == "    port: 0")
local okport = { proto = "trojan", server = "1.2.3.4", port = "8443",
	password = "p", name = "OP" }
check("L22 numeric string port preserved",
	line_with(clash_meta.generate({ okport }), "port:") == "    port: 8443")

-- ---------- M24：hysteria2/hysteria 的 insecure 以 skip-cert-verify 为准 ----------
-- parser.lua 的注释写明了：insecure 是 URI 参数名，模型里的权威字段是
-- skip-cert-verify；而只有 URI 解析器会写 insecure，Clash / sing-box JSON /
-- 表单导入的节点只有 skip-cert-verify。
local function hy2(extra)
	local t = { proto = "hysteria2", server = "1.2.3.4", port = 443,
		password = "p", name = "H" }
	for k, v in pairs(extra or {}) do t[k] = v end
	return node.normalize(t)
end
local u_true = uri.to_share_uri(hy2({ ["skip-cert-verify"] = true }))
check("M24 skip-cert-verify=true emits insecure=1",
	u_true:find("insecure=1", 1, true) ~= nil)
local u_false = uri.to_share_uri(hy2({ ["skip-cert-verify"] = false }))
check("M24 skip-cert-verify=false emits insecure=0",
	u_false:find("insecure=0", 1, true) ~= nil)
local u_str = uri.to_share_uri(hy2({ skip_cert_verify = "false" }))
check("M24 skip_cert_verify alias honoured",
	u_str:find("insecure=0", 1, true) ~= nil)
local u_none = uri.to_share_uri(hy2(nil))
check("M24 absent emits nothing",
	u_none:find("insecure", 1, true) == nil)
local u_legacy = uri.to_share_uri(hy2({ insecure = "true" }))
check("M24 legacy insecure field still honoured",
	u_legacy:find("insecure=1", 1, true) ~= nil)
-- hysteria v1 走同一分支
local u_h1 = uri.to_share_uri(node.normalize({ proto = "hysteria", server = "1.2.3.4",
	port = 443, password = "p", name = "H1", ["skip-cert-verify"] = true }))
check("M24 hysteria v1 also emits insecure=1",
	u_h1:find("insecure=1", 1, true) ~= nil)

-- ---------- M25：alpn 数组归一 ----------
-- Clash YAML 的 alpn 列表与 sing-box JSON 的 tls.alpn 导入后就是 table，
-- 直接 url_encode 会 tostring 成 "table: 0x..."
local function alpn_node(proto, extra)
	local t = { proto = proto, server = "1.2.3.4", port = 443, name = "A",
		alpn = { "h3", "h2" } }
	for k, v in pairs(extra or {}) do t[k] = v end
	return node.normalize(t)
end
local u_trojan = uri.to_share_uri(alpn_node("trojan", { password = "p" }))
check("M25 trojan alpn table joined",
	u_trojan:find("alpn=h3%2Ch2", 1, true) ~= nil)
check("M25 trojan no table address",
	u_trojan:find("table", 1, true) == nil)
local u_tuic = uri.to_share_uri(alpn_node("tuic", { uuid = "u", password = "p" }))
check("M25 tuic alpn table joined",
	u_tuic:find("alpn=h3%2Ch2", 1, true) ~= nil)
check("M25 tuic no table address", u_tuic:find("table", 1, true) == nil)
local u_vless = uri.to_share_uri(alpn_node("vless", { uuid = "u" }))
check("M25 vless alpn table joined",
	u_vless:find("alpn=h3%2Ch2", 1, true) ~= nil)
-- 字符串形态不受影响
local u_alpn_str = uri.to_share_uri(node.normalize({ proto = "trojan",
	server = "1.2.3.4", port = 443, password = "p", name = "AS", alpn = "h3,h2" }))
check("M25 alpn string unchanged",
	u_alpn_str:find("alpn=h3%2Ch2", 1, true) ~= nil)

-- ---------- L21：含逗号的名字不得进入成员列表 ----------
-- Surge 家族 / QX 的成员列表是 `NAME = select, X, Y, DIRECT`，没有引号或转义
-- 机制；名字里的逗号会被当成成员分隔符，产出两个都不存在的成员。
local n_comma = node.normalize({ proto = "trojan", server = "1.2.3.4", port = 443,
	password = "p", name = "A,B" })
local n_good = node.normalize({ proto = "trojan", server = "5.6.7.8", port = 443,
	password = "p", name = "Good" })

local surge = formats.to_surge({ n_comma, n_good })
local surge_sel = line_with(surge, "= select")
check("L21 surge select keeps good node",
	surge_sel == "PROXY = select, Good, DIRECT")
-- 节点定义本身仍保留在 [Proxy] 里（只是不可通过策略组选中）
check("L21 surge proxy line kept", surge:find("A,B = trojan", 1, true) ~= nil)

local qx = formats.to_qx({ n_good, n_comma })
local qx_pol = line_with(qx, "static=")
check("L21 qx policy keeps good node",
	qx_pol == "static=PROXY, DIRECT, Good")

-- 含换行的名字：定义行经 util.one_line 变成空格，成员列表必须与之一致，
-- 否则同样是悬空引用
local n_nl = node.normalize({ proto = "trojan", server = "7.7.7.7", port = 443,
	password = "p", name = "X\nY" })
local surge_nl = formats.to_surge({ n_nl })
check("L21 newline name normalised in def",
	surge_nl:find("X Y = trojan", 1, true) ~= nil)
check("L21 newline name matches in select",
	line_with(surge_nl, "= select") == "PROXY = select, X Y, DIRECT")

-- ---------- M19：QX [policy] 不得引用未定义的服务器 ----------
-- QX 的 [server_local] 只输出 shadowsocks / vmess / vless / trojan 四类；
-- 其余节点（hysteria2 / tuic / socks / wireguard …）没有定义行，
-- 列进 [policy] 就是悬空引用。
local hy = node.normalize({ proto = "hysteria2", server = "9.9.9.9", port = 443,
	password = "p", name = "HY" })
local qx2 = formats.to_qx({ n_good, hy })
check("M19 qx policy drops undefined node",
	line_with(qx2, "static=") == "static=PROXY, DIRECT, Good")
check("M19 qx server_local has no hysteria2",
	qx2:find("hysteria2", 1, true) == nil)
check("M19 qx server_local keeps trojan",
	qx2:find("trojan=5.6.7.8:443", 1, true) ~= nil)

-- 全部节点都不受支持时，策略组只剩组名与 DIRECT，仍然是合法行
local qx3 = formats.to_qx({ hy })
check("M19 qx empty policy still valid",
	line_with(qx3, "static=") == "static=PROXY, DIRECT")

-- ---------- 结果 ----------
print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
