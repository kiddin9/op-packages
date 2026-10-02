-- parser_mixed_format_test.lua — 混合格式文本导入的显式报错（M11 / A3）
-- 用法：lua5.1 tests/parser_mixed_format_test.lua
--
-- 背景：detect() 只返回优先级最高的**一种**格式，其余部分被静默丢弃，
-- 而 parse 返回的是合法表 —— 同步报成功，用户以为整份都导进来了。
-- 实测（2.6.15-r1）：
--   「URI + WG conf」→ detect=wireguard-conf，只得到 WG 节点，err=nil
--   「URI + JSON」   → detect=uri，只得到 URI 节点，err=nil
--
-- 修复：新增 detect_all()（整份文档级标记 + 行首锚定），
-- parse_local 文本模式在命中 >1 种格式时**明确报错**。
--
-- 本文件覆盖三类：
--   A 单格式内容一律不得被误判（误判会把正常配置挡在门外，比漏报更糟）
--   B 混合内容必须报错，且错误信息点名命中的格式
--   C 作用域：只影响本地文本导入，远程订阅（M.parse）行为不变

package.path = "./root/usr/share/?.lua;" .. package.path

local parser = require("substore.parser")
local util = require("substore.util")

local passed, failed = 0, 0
local function check(name, cond)
	if cond then passed = passed + 1; print("PASS " .. name)
	else failed = failed + 1; print("FAIL " .. name) end
end

local function vmess_uri(name)
	return "vmess://" .. util.base64_encode(util.json_encode({
		v = "2", ps = name, add = "1.2.3.4", port = "443",
		id = "11111111-2222-3333-4444-555555555555",
		aid = "0", net = "ws", type = "none", host = "", path = "/", tls = "",
	}))
end

local URI = vmess_uri("U-01")
local VLESS = "vless://11111111-2222-3333-4444-555555555555@1.2.3.4:443?encryption=none&type=ws#V-01"

local WG_CONF = [[
[Interface]
PrivateKey = aGVsbG93b3JsZHByaXZhdGVrZXkwMDAwMDAwMDAwMDA=
Address = 10.7.0.2/32
DNS = 1.1.1.1

[Peer]
PublicKey = cGVlcnB1YmxpY2tleTAwMDAwMDAwMDAwMDAwMDAwMDAwMDA=
AllowedIPs = 0.0.0.0/0
Endpoint = wg.example.com:51820
]]

local JSON_OBJ = util.json_encode({
	outbounds = { { type = "vmess", server = "1.2.3.4", server_port = 443,
		uuid = "11111111-2222-3333-4444-555555555555" } },
})

local JSON_ARRAY = util.json_encode({
	{ type = "vmess", server = "1.2.3.4", port = 443,
		uuid = "11111111-2222-3333-4444-555555555555" },
})

local CLASH_YAML = [[
proxies:
  - name: n1
    type: vmess
    server: 1.2.3.4
    port: 443
    uuid: 11111111-2222-3333-4444-555555555555
    alterId: 0
    cipher: auto
]]

local SURGE = [[
[Proxy]
n1 = vmess, 1.2.3.4, 443, username=11111111-2222-3333-4444-555555555555

[Proxy Group]
auto = select, n1

[Rule]
FINAL,auto
]]

-- ---------- A：单格式内容不得被误判 ----------
-- 每条都断言「能解析出节点」且「没有 err」：只断言 err 的话，
-- 一份本来就解析不出节点的内容（比如 base64 那段）会让断言失去意义。
local function ok_single(name, content, want_format, want_nodes)
	local res, err = parser.parse_local(content, "text")
	check("A " .. name .. " imports without error", err == nil)
	check("A " .. name .. " parses nodes",
		res ~= nil and #res.nodes >= want_nodes)
	if want_format then
		check("A " .. name .. " format is " .. want_format,
			res ~= nil and res.format == want_format)
	end
end

ok_single("uri list", URI .. "\n" .. VLESS .. "\n", "uri", 2)
ok_single("uri with comment line", "# 我的订阅 https://example.com/sub\n" .. URI .. "\n", "uri", 1)
ok_single("wireguard conf", WG_CONF, "wireguard-conf", 1)
ok_single("json config", JSON_OBJ, "json", 1)
ok_single("json array", JSON_ARRAY, "json", 1)
ok_single("clash yaml", CLASH_YAML, "yaml", 1)
ok_single("surge", SURGE, "surge", 1)
-- base64：整份内容是一个 base64 blob（解出来是 URI 列表）
ok_single("base64 of uri list",
	util.base64_encode(URI .. "\n" .. VLESS .. "\n"), "base64", 2)

-- 最容易误判的一类：**正常配置里带订阅地址**。
-- Clash YAML 的 `url: https://…`、sing-box JSON 的 `"url": "https://…"` 都含 "://"，
-- 若用 detect() 里那条宽松的 content:find("://") 当 URI 判据，这些配置会被判成
-- 「YAML + URI 混合」而拒绝导入。
ok_single("clash yaml with proxy-provider url", CLASH_YAML ..
	"proxy-providers:\n  p:\n    url: https://example.com/sub\n    path: ./p.yaml\n",
	"yaml", 1)
ok_single("singbox json with url in route rule", util.json_encode({
	outbounds = { { type = "vmess", server = "1.2.3.4", server_port = 443,
		uuid = "11111111-2222-3333-4444-555555555555" } },
	route = { rules = { { url = "https://example.com/x" } } },
}), "json", 1)
-- YAML 流式映射 `{path: /x}` 不是 JSON 对象（键没有引号）
ok_single("clash yaml with flow mapping", CLASH_YAML ..
	"    ws-opts:\n      {path: /ws, headers: {Host: a.example.com}}\n",
	"yaml", 1)
-- WG conf 的 [Interface] 也是 "[" 开头，不得被判成 JSON 数组
ok_single("wireguard conf not read as json array", WG_CONF, "wireguard-conf", 1)
-- Surge 的 [Proxy] 段头同样以 "[" 开头
ok_single("surge not read as json array", SURGE, "surge", 1)
-- 注释里的链接不是节点行
ok_single("wireguard conf with commented url", WG_CONF .. "\n# https://example.com/sub\n",
	"wireguard-conf", 1)

-- detect_all 单格式只命中一种
check("A detect_all uri", #parser.detect_all(URI .. "\n" .. VLESS) == 1)
check("A detect_all wireguard-conf", #parser.detect_all(WG_CONF) == 1)
check("A detect_all surge", #parser.detect_all(SURGE) == 1)
check("A detect_all empty", #parser.detect_all("") == 0)
check("A detect_all plain text", #parser.detect_all("hello world") == 0)

-- ---------- B：混合内容必须明确报错 ----------
local function mixed(name, content, want_a, want_b)
	local res, err = parser.parse_local(content, "text")
	check("B " .. name .. " rejected", res == nil)
	check("B " .. name .. " error is explicit",
		type(err) == "string" and err:find("混用了多种格式", 1, true) ~= nil)
	-- 错误信息必须点名两种格式，否则用户不知道要拆成哪两份
	check("B " .. name .. " names both formats",
		type(err) == "string" and err:find(want_a, 1, true) ~= nil
			and err:find(want_b, 1, true) ~= nil)
end

mixed("uri + wireguard conf", URI .. "\n" .. WG_CONF, "URI 链接", "WireGuard .conf")
mixed("wireguard conf + uri", WG_CONF .. "\n" .. URI, "URI 链接", "WireGuard .conf")
mixed("uri + json object", URI .. "\n" .. JSON_OBJ, "URI 链接", "JSON")
mixed("json object + uri", JSON_OBJ .. "\n" .. URI, "URI 链接", "JSON")
mixed("uri + json array", URI .. "\n" .. JSON_ARRAY, "URI 链接", "JSON")
mixed("uri + clash yaml", URI .. "\n" .. CLASH_YAML, "URI 链接", "Clash YAML")
mixed("uri + surge", URI .. "\n" .. SURGE, "URI 链接", "Surge/Loon 配置")

-- 报错不能是「静默丢弃」的另一种说法：绝不能返回部分节点
local resB = parser.parse_local(URI .. "\n" .. WG_CONF, "text")
check("B mixed import returns no partial nodes", resB == nil)

-- ---------- C：作用域 ----------
-- 远程订阅走 M.parse，不经 detect_all —— 混合格式的远程订阅行为不变。
-- 这是刻意的：本地导入是人工粘贴（能提示用户拆开），远程订阅的响应内容
-- 不受用户控制，直接拒收会让「订阅源多吐了一行」变成整条订阅不可用。
local resC = parser.parse(URI .. "\n" .. WG_CONF)
check("C remote parse still returns nodes", resC ~= nil and #resC.nodes >= 1)

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
