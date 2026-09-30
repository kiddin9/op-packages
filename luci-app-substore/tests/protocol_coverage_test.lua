-- protocol_coverage_test.lua — 协议覆盖一致性回归测试（2.6.0）
-- 覆盖本轮修复：
--   1. hysteria(v1) / socks 的 URI 文本导入（此前只出不进，导出→导入回环丢节点）
--   2. 简易 YAML 兜底解析不再把未知协议兜底成 vmess（静默数据损坏）
--   3. socks5 -> socks 规范化，使节点页筛选 / 规则 proto_filter 能命中
--   4. clashmeta hysteria(v1) 用 sni 而非 servername；不写 v1 非法的 obfs-password
--   5. clashmeta socks5 不再重复输出 password；http 补 username
--   6. singbox hysteria(v1) 用 auth_str（不是 password）、obfs 为字符串
--   7. singbox / surge 的 socks、http 凭据不再丢
--   8. core.merge_form_node 能清空 username
-- 用法：lua5.1 tests/protocol_coverage_test.lua

package.path = "./root/usr/share/?.lua;" .. package.path

local parser = require("substore.parser")
local output = require("substore.output")
local output_uri = require("substore.output_uri")
local node = require("substore.node")
local core = require("substore.core")
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

-- ============================================================
-- 1. URI 文本导入：hysteria(v1)
-- ============================================================
local hy = parser.parse_uri("hysteria://pw@1.2.3.4:443/?sni=a.com&insecure=1&obfs=xxx#HY")
check("hysteria URI 可解析", hy ~= nil)
check("hysteria proto", hy and hy.proto == "hysteria")
check("hysteria server", hy and hy.server == "1.2.3.4")
check("hysteria port", hy and tonumber(hy.port) == 443)
check("hysteria password", hy and hy.password == "pw")
check("hysteria sni", hy and hy.sni == "a.com")
check("hysteria obfs", hy and hy.obfs == "xxx")
-- hysteria 系列在 mihomo / sing-box 里都是 TLS-only
check("hysteria security=tls", hy and hy.security == "tls")
-- obfs-password 是 hysteria2(salamander) 专属，v1 不应有
check("hysteria 无 obfs-password", hy and hy["obfs-password"] == nil)
check("hysteria insecure 透传", hy and hy.insecure == "1")

-- 不带查询参数的极简链接也要能解析
local hy_min = parser.parse_uri("hysteria://secret@9.9.9.9:8443#MIN")
check("hysteria 无参数可解析", hy_min ~= nil and hy_min.password == "secret")

-- 无法识别的查询参数忽略而不是报错（第三方链接常带 upmbps/downmbps 等）
local hy_extra = parser.parse_uri("hysteria://pw@1.2.3.4:443/?upmbps=100&downmbps=200&peer=x#E")
check("hysteria 未知参数忽略", hy_extra ~= nil and hy_extra.server == "1.2.3.4")

-- ============================================================
-- 2. URI 文本导入：socks / socks5
-- ============================================================
local sk = parser.parse_uri("socks5://user:pass@5.6.7.8:1080#SK")
check("socks5 URI 可解析", sk ~= nil)
-- socks5 与 socks 是同一协议，统一归一为规范名 socks
check("socks5 归一为 socks", sk and sk.proto == "socks")
check("socks server", sk and sk.server == "5.6.7.8")
check("socks port", sk and tonumber(sk.port) == 1080)
check("socks username", sk and sk.username == "user")
check("socks password", sk and sk.password == "pass")

local sk2 = parser.parse_uri("socks://5.6.7.8:1080#SK2")
check("socks:// 同义可解析", sk2 ~= nil and sk2.proto == "socks")
check("无认证 socks 无 username", sk2 and sk2.username == nil)
check("无认证 socks 无 password", sk2 and sk2.password == nil)

-- 密码含未编码的 @：必须取最后一个 @ 作分界（按第一个切会静默解析出错误密码）
local sk3 = parser.parse_uri("socks5://u:p@ss@5.6.7.8:1080#S3")
check("socks 密码含 @ 正确切分", sk3 ~= nil and sk3.username == "u"
	and sk3.password == "p@ss" and sk3.server == "5.6.7.8")

-- 第三方链接可能带 ? 尾巴，不能污染 host:port
local sk4 = parser.parse_uri("socks5://5.6.7.8:1080/?foo=bar#S4")
check("socks 忽略查询尾巴", sk4 ~= nil and sk4.server == "5.6.7.8" and tonumber(sk4.port) == 1080)

-- ============================================================
-- 3. 导出 → 导入回环（修复前 hysteria / socks 只出不进）
-- ============================================================
local rt_cases = {
	{ "hysteria",  "hysteria://pw@1.2.3.4:443/?sni=a.com&insecure=1&obfs=xxx#HY" },
	{ "hysteria2", "hysteria2://pw@1.2.3.4:443/?sni=a.com&obfs=salamander&obfs-password=op#H2" },
	{ "socks5",    "socks5://user:pass@5.6.7.8:1080#SK" },
	{ "socks",     "socks://5.6.7.8:1080#SK2" },
	{ "tuic",      "tuic://uuid-x:pw@1.2.3.4:443?sni=a.com#T" },
	{ "vmess",     "vmess://" .. util.base64_encode(util.json_encode({
		v = "2", ps = "V", add = "1.2.3.4", port = "443", id = "u-1", aid = "0", net = "tcp", tls = "tls",
	})) },
}
for _, c in ipairs(rt_cases) do
	local n = parser.parse_uri(c[2])
	check("回环 " .. c[1] .. " 首次解析", n ~= nil)
	if n then
		local back = output_uri.to_share_uri(n)
		check("回环 " .. c[1] .. " 可再导出", back ~= nil)
		local n2 = back and parser.parse_uri(back)
		check("回环 " .. c[1] .. " 再导入成功", n2 ~= nil)
		check("回环 " .. c[1] .. " proto 不变", n2 and n2.proto == n.proto)
		check("回环 " .. c[1] .. " server 不变", n2 and n2.server == n.server)
		check("回环 " .. c[1] .. " port 不变", n2 and tonumber(n2.port) == tonumber(n.port))
	end
end

-- ============================================================
-- 4. 订阅文本中混有 hysteria / socks 行不再整行丢弃
-- ============================================================
local mixed = table.concat({
	"hysteria://pw@1.1.1.1:443#A",
	"socks5://u:p@2.2.2.2:1080#B",
	"vmess://" .. util.base64_encode(util.json_encode({
		v = "2", ps = "C", add = "3.3.3.3", port = "443", id = "u-2",
	})),
}, "\n")
local mixed_res = parser.parse(mixed)
check("混合 URI 文本解析出 3 个节点", mixed_res and mixed_res.nodes and #mixed_res.nodes == 3)
if mixed_res and mixed_res.nodes then
	local protos = {}
	for _, n in ipairs(mixed_res.nodes) do protos[n.proto] = true end
	check("混合文本含 hysteria", protos.hysteria == true)
	check("混合文本含 socks", protos.socks == true)
	check("混合文本含 vmess", protos.vmess == true)
end

-- ============================================================
-- 5. 简易 YAML 兜底解析：未知协议不得兜底成 vmess
-- ============================================================
local fb = parser.parse_yaml_content and parser.parse_yaml_content or nil
-- 走公开入口，确保兜底路径可达
local yaml_outbounds = [[
outbounds:
  - type: hysteria2
    server: 1.1.1.1
    server_port: 443
    password: p1
  - type: hysteria
    server: 1.1.1.2
    server_port: 443
    auth_str: p2
  - type: tuic
    server: 1.1.1.3
    server_port: 443
    uuid: u3
  - type: wireguard
    server: 1.1.1.4
    server_port: 51820
  - type: socks
    server: 1.1.1.5
    server_port: 1080
]]
local yres = parser.parse_yaml(yaml_outbounds)
if yres and #yres >0 then
	local protos = {}
	for _, n in ipairs(yres) do protos[n.proto] = (protos[n.proto] or 0) + 1 end
	check("兜底解析 hysteria2 不被兜底成 vmess", protos.hysteria2 == 1)
	check("兜底解析 hysteria 不被兜底成 vmess", protos.hysteria == 1)
	check("兜底解析 tuic 不被兜底成 vmess", protos.tuic == 1)
	check("兜底解析 wireguard 不被兜底成 vmess", protos.wireguard == 1)
	check("兜底解析 socks 规范化", protos.socks == 1)
	check("兜底解析无 vmess 假节点", protos.vmess == nil)
else
	check("兜底解析 outbounds YAML", false)
end

-- ============================================================
-- 5b. sing-box YAML outbounds 的字段名别名（server_port / tag / auth_str / server_name / insecure）
--     修复前：段名 `outbounds:` 被识别，但只读 Clash 的 port / name，
--     所有 sing-box YAML 出站都卡在 `not port` 上被静默丢弃（解析出 0 个节点）。
-- ============================================================
local sb_yaml = [[
outbounds:
  - type: hysteria2
    tag: HY2
    server: 1.1.1.1
    server_port: 443
    password: p1
    tls:
      server_name: sni.example.com
      insecure: true
  - type: hysteria
    tag: HY1
    server: 1.1.1.2
    server_port: 8443
    auth_str: p2
  - type: vmess
    tag: VM
    server: 1.1.1.3
    server_port: 443
    uuid: u-3
    security: aes-128-gcm
]]
local sb_res = parser.parse_yaml(sb_yaml)
check("sing-box YAML 出站不再被丢弃", sb_res and #sb_res == 3)
if sb_res and #sb_res == 3 then
	check("sing-box YAML server_port 生效", tonumber(sb_res[1].port) == 443)
	check("sing-box YAML tag 作为 name", sb_res[1].name == "HY2")
	check("sing-box YAML tls.server_name -> sni", sb_res[1].sni == "sni.example.com")
	check("sing-box YAML tls.insecure -> skip-cert-verify", sb_res[1]["skip-cert-verify"] == true)
	check("sing-box YAML auth_str -> password", sb_res[2].password == "p2")
	check("sing-box YAML hysteria 端口", tonumber(sb_res[2].port) == 8443)
	-- sing-box 的 vmess.security 是加密方式，不是 TLS 层
	check("sing-box YAML vmess.security -> cipher", sb_res[3].cipher == "aes-128-gcm")
	check("sing-box YAML vmess security 不当作 TLS 层", sb_res[3].security ~= "aes-128-gcm")
end

-- insecure: false 不能被当成真值（"false" 在 Lua 里是真值）
local sb_false = parser.parse_yaml([[
outbounds:
  - type: hysteria2
    server: 1.1.1.9
    server_port: 443
    password: p
    tls:
      insecure: false
]])
check("sing-box YAML insecure:false 不置 skip-cert-verify",
	sb_false and sb_false[1] and sb_false[1]["skip-cert-verify"] ~= true)

-- ============================================================
-- 6. socks5 -> socks 规范化后，筛选 / 规则过滤能命中
-- ============================================================
local clash_socks = [[
proxies:
  - name: SK
    type: socks5
    server: 1.1.1.1
    port: 1080
    username: u
    password: p
]]
local cns = parser.parse_yaml(clash_socks)
check("clash socks5 导入成功", cns and #cns == 1)
check("clash socks5 归一为 socks", cns and cns[1] and cns[1].proto == "socks")
check("node.filter proto=socks 命中", #node.filter(cns, { proto = "socks" }) == 1)
check("apply_rules proto_filter=socks 命中", #node.apply_rules(cns, { proto_filter = "socks" }) == 1)

-- 直接对未归一节点调用 normalize 也应归一（所有真实节点都会经过 normalize）
local raw_norm = node.normalize({ proto = "socks5", server = "1.1.1.1", port = 1080 })
check("node.normalize 归一 socks5", raw_norm.proto == "socks")

-- ============================================================
-- 7. clashmeta 输出：hysteria(v1) 用 sni，不写 servername / obfs-password
-- ============================================================
local hy_node = { proto = "hysteria", name = "HY", server = "1.1.1.1", port = 443,
	password = "pw", obfs = "obs", sni = "s.com" }
local cm_hy = output.generate({ hy_node }, "clashmeta")
check("clashmeta hysteria 有 sni", cm_hy and cm_hy:find("    sni: s.com", 1, true) ~= nil)
check("clashmeta hysteria 无 servername", cm_hy and cm_hy:find("servername", 1, true) == nil)
check("clashmeta hysteria 无 obfs-password", cm_hy and cm_hy:find("obfs-password", 1, true) == nil)
check("clashmeta hysteria 有 obfs", cm_hy and cm_hy:find("    obfs: obs", 1, true) ~= nil)

-- hysteria2 仍然用 sni + obfs-password
local h2_node = { proto = "hysteria2", name = "H2", server = "1.1.1.2", port = 443,
	password = "p", obfs = "salamander", ["obfs-password"] = "op", sni = "s2.com" }
local cm_h2 = output.generate({ h2_node }, "clashmeta")
check("clashmeta hysteria2 有 sni", cm_h2 and cm_h2:find("    sni: s2.com", 1, true) ~= nil)
check("clashmeta hysteria2 有 obfs-password", cm_h2 and cm_h2:find("    obfs-password: op", 1, true) ~= nil)

-- vmess 仍然用 servername（不能被 hysteria 的改动误伤）
local vm_node = { proto = "vmess", name = "V", server = "1.1.1.3", port = 443,
	uuid = "u", sni = "s3.com", security = "tls" }
local cm_vm = output.generate({ vm_node }, "clashmeta")
check("clashmeta vmess 仍用 servername", cm_vm and cm_vm:find("    servername: s3.com", 1, true) ~= nil)

-- ============================================================
-- 8. clashmeta 输出：socks password 不重复；http 补 username
-- ============================================================
local sk_node = { proto = "socks", name = "SK", server = "1.1.1.4", port = 1080,
	username = "u", password = "p" }
local cm_sk = output.generate({ sk_node }, "clashmeta")
local _, pw_cnt = cm_sk:gsub("    password:", "")
check("clashmeta socks password 只出现一次", pw_cnt == 1)
check("clashmeta socks username 输出", cm_sk:find("    username: u", 1, true) ~= nil)

local http_node = { proto = "http", name = "HT", server = "1.1.1.5", port = 8080,
	username = "hu", password = "hp" }
local cm_ht = output.generate({ http_node }, "clashmeta")
check("clashmeta http username 输出", cm_ht and cm_ht:find("    username: hu", 1, true) ~= nil)
local _, htpw = cm_ht:gsub("    password:", "")
check("clashmeta http password 只出现一次", htpw == 1)

-- ============================================================
-- 9. singbox 输出：hysteria(v1) 用 auth_str、obfs 为字符串
-- ============================================================
local sb_hy = util.json_decode(output.generate({ hy_node }, "singbox"))
check("singbox hysteria auth_str", sb_hy and sb_hy.outbounds[1] and sb_hy.outbounds[1].auth_str == "pw")
check("singbox hysteria 无 password 键", sb_hy and sb_hy.outbounds[1] and sb_hy.outbounds[1].password == nil)
check("singbox hysteria obfs 为字符串", sb_hy and sb_hy.outbounds[1] and sb_hy.outbounds[1].obfs == "obs")

local sb_h2 = util.json_decode(output.generate({ h2_node }, "singbox"))
check("singbox hysteria2 仍用 password", sb_h2 and sb_h2.outbounds[1] and sb_h2.outbounds[1].password == "p")
check("singbox hysteria2 obfs 为对象", sb_h2 and sb_h2.outbounds[1] and type(sb_h2.outbounds[1].obfs) == "table"
	and sb_h2.outbounds[1].obfs.password == "op")

-- singbox socks / http 凭据
local sb_sk = util.json_decode(output.generate({ sk_node }, "singbox"))
check("singbox socks username", sb_sk and sb_sk.outbounds[1] and sb_sk.outbounds[1].username == "u")
check("singbox socks password", sb_sk and sb_sk.outbounds[1] and sb_sk.outbounds[1].password == "p")
local sb_ht = util.json_decode(output.generate({ http_node }, "singbox"))
check("singbox http username", sb_ht and sb_ht.outbounds[1] and sb_ht.outbounds[1].username == "hu")
check("singbox http password", sb_ht and sb_ht.outbounds[1] and sb_ht.outbounds[1].password == "hp")

-- ============================================================
-- 10. Surge 家族：socks / http 凭据
-- ============================================================
local sg_sk = output.generate({ sk_node }, "surge")
check("surge socks username", sg_sk and sg_sk:find("username=u", 1, true) ~= nil)
check("surge socks password", sg_sk and sg_sk:find("password=p", 1, true) ~= nil)
local sg_ht = output.generate({ http_node }, "surge")
check("surge http username", sg_ht and sg_ht:find("username=hu", 1, true) ~= nil)
check("surge http password", sg_ht and sg_ht:find("password=hp", 1, true) ~= nil)

-- ============================================================
-- 11. core.merge_form_node 能清空 username（FORM_KEYS 必须含 username）
-- ============================================================
local old_node = { proto = "socks", name = "N", server = "1.1.1.1", port = 1080,
	username = "olduser", password = "oldpass" }
local merged = core.merge_form_node(old_node, { proto = "socks", name = "N", server = "1.1.1.1", port = 1080,
	password = "newpass" })
check("merge_form_node 清空 username", merged and merged.username == nil)
check("merge_form_node 更新 password", merged and merged.password == "newpass")

-- ---------- 结果 ----------
print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
