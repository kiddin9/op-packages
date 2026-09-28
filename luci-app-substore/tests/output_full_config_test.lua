-- output_full_config_test.lua — sing-box / V2Ray(Xray) 完整配置输出
-- 用法：lua5.1 tests/output_full_config_test.lua
--
-- 覆盖 2.4.0 起的行为：target=singbox / target=v2ray 由「仅 outbounds 片段」
-- 改为「outbounds + 分流」的完整配置。

package.path = "./root/usr/share/?.lua;" .. package.path

local util = require("substore.util")
local output = require("substore.output")
local singbox = require("substore.output_singbox")
local v2ray = require("substore.output_v2ray")

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
	{ proto = "vmess", name = "HK 01", server = "1.1.1.1", port = 443, uuid = "u1", net = "tcp" },
	{ proto = "vless", name = "HK 01", server = "2.2.2.2", port = 443, uuid = "u2" },
	{ proto = "trojan", name = "JP", server = "3.3.3.3", port = 443, password = "p" },
	{ proto = "ssr", name = "SSR", server = "4.4.4.4", port = 8388, method = "aes-128-cfb", password = "p" },
}

-- ---------- util.JSON_EMPTY_OBJECT：空表必须能表达成对象 ----------
-- Lua 空表无法区分 {} 与 []，is_array({}) 为 true，默认会编码成 []，
-- 而 sing-box 的 tls、Xray 的 settings 都必须是对象
check("empty table encodes as array (baseline)", util.json_encode({}) == "[]")
check("JSON_EMPTY_OBJECT encodes as object", util.json_encode(util.JSON_EMPTY_OBJECT) == "{}")
check("JSON_EMPTY_OBJECT nested", util.json_encode({ settings = util.JSON_EMPTY_OBJECT }) == '{"settings":{}}')

-- ---------- util.unique_tags ----------
local ut = util.unique_tags(
	{ { name = "A" }, { name = "A" }, { name = "B" }, { name = "direct" } },
	{ direct = true }
)
check("unique_tags dedupes", ut[1] == "A" and ut[2] == "A #2" and ut[3] == "B")
check("unique_tags avoids reserved", ut[4] == "direct #2")
check("unique_tags falls back to server:port", util.unique_tags({ { server = "h", port = 1 } })[1] == "h:1")

-- ============================================================
-- sing-box 完整配置
-- ============================================================
local sb_raw = singbox.generate(nodes)
local sb = util.json_decode(sb_raw)

check("sb is valid json", sb ~= nil)
check("sb has outbounds", type(sb.outbounds) == "table")
check("sb has route", type(sb.route) == "table")

-- 不含 inbounds / dns（会绑定本地端口、覆盖用户 DNS）
check("sb has no inbounds", sb.inbounds == nil)
check("sb has no dns", sb.dns == nil)

-- 节点出站按序在前；SSR 被丢弃
check("sb node1 is vmess", sb.outbounds[1].type == "vmess" and sb.outbounds[1].tag == "HK 01")
check("sb node2 tag deduped", sb.outbounds[2].type == "vless" and sb.outbounds[2].tag == "HK 01 #2")
check("sb node3 is trojan", sb.outbounds[3].type == "trojan" and sb.outbounds[3].tag == "JP")
check("sb drops ssr", sb_raw:find('"ssr"') == nil)
check("sb outbound count", #sb.outbounds == 3 + 4) -- 节点 + selector + urltest + direct + block

-- selector
local sel, urltest, direct, block
for _, o in ipairs(sb.outbounds) do
	if o.type == "selector" then sel = o
	elseif o.type == "urltest" then urltest = o
	elseif o.type == "direct" then direct = o
	elseif o.type == "block" then block = o end
end
check("sb has selector", sel ~= nil and sel.tag == "select")
check("sb selector default auto", sel and sel.default == "auto")
check("sb selector lists auto+direct first", sel and sel.outbounds[1] == "auto" and sel.outbounds[2] == "direct")
check("sb selector lists all proxies", sel and #sel.outbounds == 2 + 3)

check("sb has urltest", urltest ~= nil and urltest.tag == "auto")
check("sb urltest lists all proxies", urltest and #urltest.outbounds == 3)
check("sb urltest outbound1", urltest and urltest.outbounds[1] == "HK 01")
check("sb urltest outbound2", urltest and urltest.outbounds[2] == "HK 01 #2")

check("sb has direct", direct ~= nil and direct.tag == "direct")
check("sb has block", block ~= nil and block.tag == "block")

-- route
check("sb route.final is select", sb.route.final == "select")
check("sb route auto_detect_interface", sb.route.auto_detect_interface == true)
check("sb route rule count", #sb.route.rules == 1)
check("sb route private -> direct", sb.route.rules[1].ip_is_private == true and sb.route.rules[1].outbound == "direct")
-- action 自 1.11.0 起才存在且默认即 "route"；省略它才能同时兼容 1.10 与 1.11+
check("sb route rule omits action (version compat)", sb.route.rules[1].action == nil)

-- tls 必须是对象：security=tls 但无 sni 时曾产出非法的 "tls":[]
local tls_node = { { proto = "vmess", name = "T", server = "1.1.1.1", port = 443, uuid = "u", security = "tls" } }
local tls_raw = singbox.generate(tls_node)
check("sb tls is object not array", tls_raw:find('"tls":{}') ~= nil and tls_raw:find('"tls":%[%]') == nil)
check("sb tls with sni keeps server_name",
	singbox.generate({ { proto = "vmess", name = "T", server = "1.1.1.1", port = 443, uuid = "u",
		security = "tls", sni = "example.com" } }):find('"server_name":"example.com"') ~= nil)

-- 节点名与保留 tag 重名时不得冲突
local clash_name = singbox.generate({ { proto = "vmess", name = "direct", server = "1.1.1.1", port = 443, uuid = "u" } })
local cn = util.json_decode(clash_name)
local cn_tags = {}
for _, o in ipairs(cn.outbounds) do cn_tags[o.tag] = (cn_tags[o.tag] or 0) + 1 end
local all_unique = true
for _, c in pairs(cn_tags) do if c > 1 then all_unique = false end end
check("sb tags unique despite reserved name", all_unique)
check("sb renamed reserved node", cn.outbounds[1].tag == "direct #2")

-- 无可用节点：不生成 selector / urltest（outbounds 不允许为空），final 退回 direct
local sb_empty = util.json_decode(singbox.generate({}))
check("sb empty has 2 outbounds", #sb_empty.outbounds == 2)
check("sb empty final direct", sb_empty.route.final == "direct")
local sb_empty_types = {}
for _, o in ipairs(sb_empty.outbounds) do sb_empty_types[o.type] = true end
check("sb empty no selector/urltest", not sb_empty_types.selector and not sb_empty_types.urltest)
check("sb empty keeps direct/block", sb_empty_types.direct and sb_empty_types.block)

-- 确定性：同样输入两次结果一致
check("sb deterministic", singbox.generate(nodes) == singbox.generate(nodes))

-- ============================================================
-- V2Ray / Xray 完整配置
-- ============================================================
local v2_raw = v2ray.generate(nodes)
local v2 = util.json_decode(v2_raw)

check("v2 is valid json", v2 ~= nil)
check("v2 has outbounds", type(v2.outbounds) == "table")
check("v2 has routing", type(v2.routing) == "table")
check("v2 has log", type(v2.log) == "table" and v2.log.loglevel == "warning")

-- 不含 inbounds / dns
check("v2 has no inbounds", v2.inbounds == nil)
check("v2 has no dns", v2.dns == nil)

-- 节点出站按序在前
check("v2 node1 is vmess", v2.outbounds[1].protocol == "vmess" and v2.outbounds[1].tag == "HK 01")
check("v2 node2 tag deduped", v2.outbounds[2].protocol == "vless" and v2.outbounds[2].tag == "HK 01 #2")
check("v2 node3 is trojan", v2.outbounds[3].protocol == "trojan" and v2.outbounds[3].tag == "JP")
check("v2 drops ssr", v2_raw:find('"ssr"') == nil)
check("v2 outbound count", #v2.outbounds == 3 + 2) -- 节点 + freedom + blackhole

-- freedom / blackhole：settings 必须是对象，不能是 []
local freedom, blackhole
for _, o in ipairs(v2.outbounds) do
	if o.protocol == "freedom" then freedom = o
	elseif o.protocol == "blackhole" then blackhole = o end
end
check("v2 has freedom direct", freedom ~= nil and freedom.tag == "direct")
check("v2 has blackhole block", blackhole ~= nil and blackhole.tag == "block")
check("v2 settings is object not array", v2_raw:find('"settings":%[%]') == nil)
check("v2 blackhole response", blackhole and blackhole.settings.response.type == "none")

-- observatory：leastPing 必须依赖它才生效
check("v2 has observatory", type(v2.observatory) == "table")
check("v2 observatory subjectSelector", v2.observatory and #v2.observatory.subjectSelector == 3)
check("v2 observatory probeUrl", v2.observatory and v2.observatory.probeUrl ~= nil)
check("v2 observatory probeInterval", v2.observatory and v2.observatory.probeInterval == "10s")

-- routing
check("v2 domainStrategy", v2.routing.domainStrategy == "IPIfNonMatch")
check("v2 has balancer", type(v2.routing.balancers) == "table" and #v2.routing.balancers == 1)
local bal = v2.routing.balancers[1]
check("v2 balancer tag auto", bal.tag == "auto")
check("v2 balancer strategy leastPing", bal.strategy.type == "leastPing")
check("v2 balancer selector lists proxies", #bal.selector == 3)
check("v2 rule count", #v2.routing.rules == 2)
check("v2 rule1 private -> direct",
	v2.routing.rules[1].type == "field" and v2.routing.rules[1].ip[1] == "geoip:private"
	and v2.routing.rules[1].outboundTag == "direct")
check("v2 rule2 catchall -> balancer",
	v2.routing.rules[2].network == "tcp,udp" and v2.routing.rules[2].balancerTag == "auto")

-- 前缀匹配防护：Xray 的 selector 按前缀匹配，节点名 "d" 是 "direct" 的前缀，
-- 若不消解会把 direct 出站也纳入负载均衡
local pfx = util.json_decode(v2ray.generate({ { proto = "vmess", name = "d", server = "1.1.1.1", port = 443, uuid = "u" } }))
check("v2 renames prefix-of-reserved node", pfx.outbounds[1].tag == "d #2")
check("v2 balancer selector excludes direct", pfx.routing.balancers[1].selector[1] == "d #2")

-- 无可用节点：没有 balancer 可引用，兜底规则改指 direct
local v2_empty = util.json_decode(v2ray.generate({}))
check("v2 empty has 2 outbounds", #v2_empty.outbounds == 2)
check("v2 empty no balancer", v2_empty.routing.balancers == nil)
check("v2 empty no observatory", v2_empty.observatory == nil)
check("v2 empty rule count", #v2_empty.routing.rules == 2)
check("v2 empty catchall -> direct", v2_empty.routing.rules[2].outboundTag == "direct")

check("v2 deterministic", v2ray.generate(nodes) == v2ray.generate(nodes))

-- ---------- 往返：完整配置重新导入必须只取真实节点 ----------
-- 完整配置里多了 selector / urltest / direct / block（sing-box）与
-- freedom / blackhole（Xray），解析器必须跳过它们而非当成节点
local parser = require("substore.parser")
for _, fmt in ipairs({ "singbox", "v2ray" }) do
	local txt = (fmt == "singbox") and sb_raw or v2_raw
	local res = parser.parse(txt)
	check("roundtrip " .. fmt .. " parses", res ~= nil and #res.nodes == 3)
	local protos = {}
	for _, n in ipairs(res and res.nodes or {}) do protos[n.proto] = true end
	check("roundtrip " .. fmt .. " only real proxies",
		protos.vmess and protos.vless and protos.trojan
		and not protos.direct and not protos.selector and not protos.urltest and not protos.freedom)
end

-- ---------- 经 output.generate 分发后行为一致 ----------
check("dispatch singbox full", output.generate(nodes, "singbox") == sb_raw)
check("dispatch v2ray full", output.generate(nodes, "v2ray") == v2_raw)
check("dispatch singbox alias", output.generate(nodes, "sing-box") == sb_raw)

-- ---------- 结果 ----------
print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
