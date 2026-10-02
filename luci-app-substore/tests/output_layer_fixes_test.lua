-- output_layer_fixes_test.lua — 输出层代码级审计发现的 10 项缺陷回归测试
-- 用法：lua5.1 tests/output_layer_fixes_test.lua
--
-- 每一项都对应一个「生成的配置在目标客户端上会被拒绝 / 静默跑错」的缺陷：
--   F1  clashmeta  ws 节点同时有 path 与 host 时输出两个并列的 ws-opts 键
--   F2  v2ray     ws/grpc/http 传输层无参数时输出 []（Xray 解进结构体指针报错）
--   F3  clashmeta 节点名与组名 / 保留名冲突时产生重复 name，mihomo 拒绝加载
--   F4  clashmeta esc_yaml 未引用的标量以 % / ! / - 开头时是非法 YAML
--   F5  QX         vless 节点丢掉 obfs / tls 参数
--   F6  surge      vless + ws 节点丢掉整个传输层
--   F7  surge/QX   参数值里的逗号把凭据静默截断
--   F8  uri        IPv6 字面量地址未加方括号
--   F9  clashmeta  amnezia-wg-option 子键未转义
--   F10 output     content_type_for / extension_for 对空 target 落空
--
-- 每一项都先用 git stash 之外的 HEAD 版本反向验证过：断言在修复前必须失败。

package.path = "./root/usr/share/?.lua;" .. package.path

local node = require("substore.node")
local util = require("substore.util")
local clash_meta = require("substore.output_clash_meta")
local v2ray = require("substore.output_v2ray")
local formats = require("substore.output_formats")
local uri = require("substore.output_uri")
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

-- 取出第一行匹配 pattern 的整行
local function line_with(text, pattern)
	for l in text:gmatch("[^\n]+") do
		if l:find(pattern) then return l end
	end
	return nil
end

-- ---------- F1：ws-opts 只能出现一次 ----------
-- mihomo 的 ws-opts 是单个映射；同一层级出现两个同名键时 YAML 解析器
-- 报 duplicate key（或后者覆盖前者），path 与 headers 必定丢一个。
local ws_node = node.normalize({ proto = "vmess", name = "WS", server = "1.2.3.4",
	port = 443, uuid = "11111111-2222-3333-4444-555555555555", net = "ws",
	path = "/ray", host = "ws.example.com" })
local ws_yaml = clash_meta.generate({ ws_node })
local ws_opts_count = 0
for _ in ws_yaml:gmatch("ws%-opts:") do ws_opts_count = ws_opts_count + 1 end
check("F1 ws-opts emitted exactly once", ws_opts_count == 1)
check("F1 ws path present", ws_yaml:find("path: /ray", 1, true) ~= nil)
check("F1 ws host present", ws_yaml:find("Host: ws.example.com", 1, true) ~= nil)
-- headers 必须嵌在 ws-opts 之下（缩进比 ws-opts 深）
local ws_opts_line = line_with(ws_yaml, "ws%-opts:")
local headers_line = line_with(ws_yaml, "headers:")
check("F1 headers nested under ws-opts",
	ws_opts_line ~= nil and headers_line ~= nil
	and #headers_line:match("^(%s*)") > #ws_opts_line:match("^(%s*)"))

-- 只有 host、没有 path 的 ws 节点：ws-opts 是 path 与 headers 的共同父键，
-- 原来 `ws-opts:` 那一行写在 `if node.path` 里面，于是这种节点输出一个
-- 悬空的 `headers:` —— 既不在任何 ws-opts 之下，也不是合法的 vmess 键，
-- mihomo 要么报未知字段要么直接忽略 Host，ws 握手被服务端拒绝。
local ws_host_only = node.normalize({ proto = "vmess", name = "WSH", server = "1.2.3.4",
	port = 443, uuid = "11111111-2222-3333-4444-555555555555", net = "ws",
	host = "ws.example.com" })
local wsh_yaml = clash_meta.generate({ ws_host_only })
check("F1 host-only ws emits ws-opts",
	line_with(wsh_yaml, "ws%-opts:") ~= nil)
local wsh_opts = line_with(wsh_yaml, "ws%-opts:")
local wsh_headers = line_with(wsh_yaml, "headers:")
check("F1 host-only headers nested under ws-opts",
	wsh_opts ~= nil and wsh_headers ~= nil
	and #wsh_headers:match("^(%s*)") > #wsh_opts:match("^(%s*)"))
check("F1 host-only Host preserved",
	wsh_yaml:find("Host: ws.example.com", 1, true) ~= nil)

-- ---------- F2：空传输层必须是 {} 而不是 [] ----------
-- Xray 用标准库 json.Unmarshal 解析配置，wsSettings 等是结构体指针，
-- 把 JSON 数组解进结构体会直接 UnmarshalTypeError，Xray 拒绝启动。
local grpc_node = node.normalize({ proto = "vless", name = "G", server = "5.6.7.8",
	port = 443, uuid = "u", net = "grpc" })
local gcfg = v2ray.generate({ grpc_node })
check("F2 grpc empty settings is object", gcfg:find('"grpcSettings":{}', 1, true) ~= nil)
check("F2 grpc empty settings is not array", gcfg:find('"grpcSettings":[]', 1, true) == nil)

local ws_empty = node.normalize({ proto = "vless", name = "W", server = "5.6.7.9",
	port = 443, uuid = "u", net = "ws" })
check("F2 ws empty settings is object",
	v2ray.generate({ ws_empty }):find('"wsSettings":{}', 1, true) ~= nil)

local http_empty = node.normalize({ proto = "vless", name = "H", server = "5.6.7.10",
	port = 443, uuid = "u", net = "http" })
check("F2 http empty settings is object",
	v2ray.generate({ http_empty }):find('"httpSettings":{}', 1, true) ~= nil)

-- 解码出的空对象一旦被写入键，必须照常编码出这些键（不能因为是
-- JSON_EMPTY_OBJECT 的同款元表就一律输出 {}）
local decoded = util.json_decode('{"a":{}}')
decoded.a.b = 1
check("F2 decoded empty object still encodable",
	util.json_encode(decoded):find('"a":{"b":1}', 1, true) ~= nil)

-- ---------- F3：节点名冲突必须消解 ----------
-- mihomo 的 proxies 里 name 是主键，重名直接拒绝加载整份配置。
local d1 = node.normalize({ proto = "trojan", name = "HK01", server = "1.1.1.1",
	port = 443, password = "a" })
local d2 = node.normalize({ proto = "trojan", name = "HK01", server = "2.2.2.2",
	port = 443, password = "b" })
local dup = {}
for l in clash_meta.generate({ d1, d2 }):gmatch("  %- name: ([^\n]+)") do
	dup[#dup + 1] = l
end
check("F3 duplicate node names uniquified", dup[1] ~= dup[2])
check("F3 first name preserved", dup[1] == "HK01")

-- 节点名撞上生成的策略组名：组名是 proxies 之外的顶层键，同名同样冲突
local p = node.normalize({ proto = "trojan", name = "Proxy", server = "3.3.3.3",
	port = 443, password = "c" })
local collide = clash_meta.generate({ p })
-- 节点被改名（`#` 使 YAML 需要引号），策略组本身仍叫 Proxy
check("F3 node named like group renamed",
	collide:find('  - name: "Proxy #2"', 1, true) ~= nil)
-- 只看 proxies 段：策略组本身仍叫 Proxy，不能被这条断言误伤
local proxies_section = collide:match("^proxies:\n(.-)\nproxy%-groups:") or ""
check("F3 no proxy left named Proxy",
	proxies_section:find("  - name: Proxy\n", 1, true) == nil)
check("F3 group keeps its name",
	collide:find("proxy-groups:\n  - name: Proxy\n", 1, true) ~= nil)

-- ---------- F4：未加引号的 YAML 标量必须合法 ----------
-- `%` 在 YAML 里是指令前缀，`!` 是标签前缀，行首 `-` 是块序列项，
-- 这三种开头的裸标量都是非法 YAML，mihomo 解析直接失败。
check("F4 percent-leading value quoted",
	clash_meta.generate({ node.normalize({ proto = "trojan", name = "P",
		server = "1.1.1.1", port = 443, password = "%40abc" }) })
		:find('password: "%40abc"', 1, true) ~= nil)
check("F4 bang-leading value quoted",
	clash_meta.generate({ node.normalize({ proto = "trojan", name = "B",
		server = "1.1.1.1", port = 443, password = "!secret" }) })
		:find('password: "!secret"', 1, true) ~= nil)
check("F4 dash-leading value quoted",
	clash_meta.generate({ node.normalize({ proto = "trojan", name = "D",
		server = "1.1.1.1", port = 443, password = "-abc" }) })
		:find('password: "-abc"', 1, true) ~= nil)
-- 普通值不应被无谓地加引号（否则所有既有输出都变样）
check("F4 plain value not quoted",
	clash_meta.generate({ node.normalize({ proto = "trojan", name = "N",
		server = "1.1.1.1", port = 443, password = "plainpass" }) })
		:find("password: plainpass", 1, true) ~= nil)

-- ---------- F5 / F6：vless 的 ws 传输层 ----------
-- QX 与 Surge 家族的 vless 与 vmess 共用同一套传输参数名。此前只有 vmess
-- 分支写了，vless + ws 导出成明文 tcp 条目，客户端按 tcp 去连只开了 ws 的
-- 端口，必然失败且不报错。
local vless_ws = node.normalize({ proto = "vless", name = "VLWS", server = "1.2.3.4",
	port = 443, uuid = "u", net = "ws", path = "/p", host = "h.com", security = "tls" })

local qx = formats.to_qx({ vless_ws })
local qx_vless = line_with(qx, "vless=")
check("F5 qx vless has obfs=ws", qx_vless ~= nil and qx_vless:find("obfs=ws", 1, true) ~= nil)
check("F5 qx vless has obfs-uri", qx_vless ~= nil and qx_vless:find("obfs-uri=/p", 1, true) ~= nil)
check("F5 qx vless has obfs-host", qx_vless ~= nil and qx_vless:find("obfs-host=h.com", 1, true) ~= nil)
check("F5 qx vless has tls-verification",
	qx_vless ~= nil and qx_vless:find("tls-verification=true", 1, true) ~= nil)

local surge = formats.to_surge({ vless_ws })
local surge_vless = line_with(surge, "VLWS = vless")
check("F6 surge vless has ws=true",
	surge_vless ~= nil and surge_vless:find("ws=true", 1, true) ~= nil)
check("F6 surge vless has ws-path",
	surge_vless ~= nil and surge_vless:find("ws-path=/p", 1, true) ~= nil)
check("F6 surge vless has ws-headers",
	surge_vless ~= nil and surge_vless:find("ws-headers=Host:h.com", 1, true) ~= nil)

-- ---------- F7：值里的逗号不能静默截断 ----------
-- `password=pa,ss` 在逗号分隔语法里会被读成 `password=pa` 加一个悬空字段。
local comma_pw = node.normalize({ proto = "trojan", name = "CP", server = "1.2.3.4",
	port = 443, password = "pa,ss" })
local cp_line = formats.surge_line(comma_pw)
check("F7 surge drops comma-valued node", cp_line == nil)
-- 节点被丢弃后，成员列表也不得再引用它（否则是悬空引用）
local cp_cfg = formats.to_surge({ comma_pw })
check("F7 surge select excludes dropped node",
	line_with(cp_cfg, "= select") == "PROXY = select, DIRECT")

local qx_cp = formats.to_qx({ comma_pw })
check("F7 qx drops comma-valued node", qx_cp:find("trojan=", 1, true) == nil)
check("F7 qx policy excludes dropped node",
	line_with(qx_cp, "static=") == "static=PROXY, DIRECT")

-- 合法的多字段行不得被误判（逗号是结构分隔符，不是值的一部分）
local ok_node = node.normalize({ proto = "trojan", name = "OK", server = "5.6.7.8",
	port = 443, password = "plain", sni = "s.example.com" })
local ok_line = formats.surge_line(ok_node)
check("F7 legal multi-field line kept", ok_line ~= nil)
check("F7 legal line has all fields",
	ok_line:find("password=plain", 1, true) ~= nil
	and ok_line:find("sni=s.example.com", 1, true) ~= nil)
local ok_qx = formats.to_qx({ ok_node })
check("F7 legal qx line kept", ok_qx:find("trojan=5.6.7.8:443", 1, true) ~= nil)
check("F7 legal qx keeps sni",
	line_with(ok_qx, "trojan="):find("tls-host=s.example.com", 1, true) ~= nil)

-- ---------- F8：IPv6 字面量地址 ----------
-- RFC 3986 的 authority 里 IPv6 必须写成 [addr]，否则 `::` 与端口分隔符
-- 无法区分，客户端把地址解析成垃圾。
local v6 = node.normalize({ proto = "trojan", name = "v6", server = "fd00::1",
	port = 443, password = "p", security = "tls" })
check("F8 ipv6 bracketed in uri",
	uri.to_share_uri(v6):find("@[fd00::1]:443", 1, true) ~= nil)
-- 已经是方括号形态的不得重复加括号
local v6b = node.normalize({ proto = "trojan", name = "v6b", server = "[fd00::1]",
	port = 443, password = "p", security = "tls" })
check("F8 bracketed ipv6 not double-wrapped",
	uri.to_share_uri(v6b):find("@[fd00::1]:443", 1, true) ~= nil
	and uri.to_share_uri(v6b):find("[[", 1, true) == nil)
-- IPv4 / 域名不受影响
check("F8 ipv4 unchanged",
	uri.to_share_uri(node.normalize({ proto = "trojan", name = "v4", server = "1.2.3.4",
		port = 443, password = "p", security = "tls" })):find("@1.2.3.4:443", 1, true) ~= nil)

-- ---------- F9：amnezia-wg-option 子键转义 ----------
-- 子键来自导入的 YAML/JSON（不可信），键名里的引号 / 换行会截断映射。
local awg = node.normalize({ proto = "wireguard", name = "AWG", server = "1.2.3.4",
	port = 51820, ["private-key"] = "k", ["public-key"] = "pk",
	["amnezia-wg-option"] = { jc = 4, ["x: 1"] = 2 } })
local awg_yaml = clash_meta.generate({ awg })
check("F9 awg numeric subkey plain", awg_yaml:find("jc: 4", 1, true) ~= nil)
check("F9 awg subkey quoted",
	awg_yaml:find('"x: 1": 2', 1, true) ~= nil)

-- ---------- F10：空 target 的 Content-Type 与后缀 ----------
-- `?target=` 传进来的是 ""，而 "" 在 Lua 里是真值，`format or DEFAULT_FORMAT`
-- 兜不住它 —— 正文按默认格式生成，响应头与文件名却是另一回事。
check("F10 empty target content type",
	output.content_type_for("") == output.content_type_for("clashmeta"))
check("F10 empty target extension",
	output.extension_for("") == output.extension_for("clashmeta"))
check("F10 whitespace target treated as empty",
	output.content_type_for("   ") == output.content_type_for("clashmeta"))
check("F10 nil target content type",
	output.content_type_for(nil) == output.content_type_for("clashmeta"))
check("F10 empty target extension is yaml", output.extension_for("") == "yaml")
check("F10 unknown target falls back to txt", output.extension_for("nonsense") == "txt")

-- ---------- 结果 ----------
print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
