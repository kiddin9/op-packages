-- ss_plugin_test.lua — shadowsocks SIP003 插件全链路回归测试
-- 用法：lua5.1 tests/ss_plugin_test.lua
--
-- 缺陷：`plugin` 能被解析、能通过 node.normalize 存活，但三个输出模块全都
-- 静默丢掉它 —— 带 obfs / v2ray-plugin 的 ss 节点导出后，客户端以明文 SS
-- 去连只接受带插件握手的服务端，必然失败且不报错。表单侧同样致命：
-- plugin 不在 node.PROTO_FIELDS.shadowsocks 里，用户在界面上编辑一次
-- 该节点，core.merge_form_node 就会把插件配置清空。
--
-- 上游依据（均已核对，非推测）：
--   * SIP002  SS-URI = "ss://" userinfo "@" host ":" port [ "/" ] [ "?" plugin ] [ "#" tag ]
--             plugin 的取值整体做百分号编码
--   * sing-box shadowsocks 出站：plugin（字符串，仅支持 obfs-local / v2ray-plugin）
--             与 plugin_opts（SIP003 原始参数串，原样透传）
--   * mihomo  shadowsocks 出站：plugin（obfs / v2ray-plugin / …）、
--             plugin-opts 是**映射**；obfs 的 mode 必须 ∈ {tls,http}，
--             v2ray-plugin 的 mode 必须是 websocket，否则整个 outbound 构造失败，
--             mihomo 拒绝加载整份配置

package.path = "./root/usr/share/?.lua;" .. package.path

local util = require("substore.util")
local node = require("substore.node")
local core = require("substore.core")
local parser = require("substore.parser")
local clash_meta = require("substore.output_clash_meta")
local singbox = require("substore.output_singbox")
local uri_mod = require("substore.output_uri")

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

local function line_with(text, pattern)
	for l in text:gmatch("[^\n]+") do
		if l:find(pattern) then return l end
	end
	return nil
end

-- SIP002 规范里的示例 URI
local SPEC_URI = "ss://YWVzLTI1Ni1nY206cGFzcw==@192.168.100.1:8888/"
	.. "?plugin=obfs-local%3Bobfs%3Dhttp%3Bobfs-host%3Dwww.baidu.com#Example2"
local SPEC_PLUGIN = "obfs-local;obfs=http;obfs-host=www.baidu.com"

-- ---------- util.parse_sip003_plugin ----------
-- 取一个本地引用：修复前 util 里没有这个函数，直接调用会让整个文件在第 55 行
-- 崩掉，后面的断言一条都跑不到，反向验证就失去了意义。
local parse_plugin = util.parse_sip003_plugin or function() return nil end
local name, opts_str, opts_map = parse_plugin(SPEC_PLUGIN)
opts_map = opts_map or {}
check("parse plugin name", name == "obfs-local")
check("parse plugin opts string", opts_str == "obfs=http;obfs-host=www.baidu.com")
check("parse plugin opts map obfs", opts_map.obfs == "http")
check("parse plugin opts map obfs-host", opts_map["obfs-host"] == "www.baidu.com")
check("parse empty plugin returns nil", parse_plugin("") == nil)
check("parse nil plugin returns nil", parse_plugin(nil) == nil)
-- SIP003 规定分号、等号、反斜杠可用反斜杠转义
local esc_name, _, esc_map = parse_plugin("obfs-local;obfs=http\\;x")
esc_map = esc_map or {}
check("parse escaped semicolon name", esc_name == "obfs-local")
check("parse escaped semicolon kept", esc_map and esc_map.obfs == "http\\;x")

-- ---------- 解析：ss:// URI 的 plugin 必须落到模型 ----------
local parsed = parser.parse(SPEC_URI)
check("uri parsed", parsed ~= nil and #parsed.nodes == 1)
local n = parsed.nodes[1]
check("plugin parsed from uri", n.plugin == SPEC_PLUGIN)
check("plugin survives normalize", node.normalize(n).plugin == SPEC_PLUGIN)

-- ---------- mihomo（clashmeta） ----------
local d = node.normalize(n)
local yaml = clash_meta.generate({ d })
check("clashmeta emits plugin: obfs", yaml:find("    plugin: obfs\n", 1, true) ~= nil)
check("clashmeta emits plugin-opts", yaml:find("    plugin-opts:\n", 1, true) ~= nil)
check("clashmeta obfs mode", yaml:find("      mode: http\n", 1, true) ~= nil)
check("clashmeta obfs host", yaml:find("      host: www.baidu.com\n", 1, true) ~= nil)
-- plugin-opts 的子键必须缩进在它之下
local po = line_with(yaml, "plugin%-opts:")
local mode_line = line_with(yaml, "mode: http")
check("clashmeta plugin-opts children nested",
	po ~= nil and mode_line ~= nil
	and #mode_line:match("^(%s*)") > #po:match("^(%s*)"))

local function ss(plugin)
	return node.normalize({ proto = "shadowsocks", name = "S", server = "1.2.3.4",
		port = 8388, method = "aes-256-gcm", password = "p", plugin = plugin })
end

-- simple-obfs 是 obfs-local 的历史别名，mihomo 只认 obfs
local simple = clash_meta.generate({ ss("simple-obfs;obfs=tls;obfs-host=h.com") })
check("clashmeta simple-obfs mapped to obfs",
	simple:find("    plugin: obfs\n", 1, true) ~= nil)
check("clashmeta simple-obfs mode tls", simple:find("      mode: tls\n", 1, true) ~= nil)

-- v2ray-plugin：mode 必须是 websocket
local v2 = clash_meta.generate({ ss("v2ray-plugin;mode=websocket;host=h.com;path=/ws;tls") })
check("clashmeta v2ray-plugin name",
	v2:find("    plugin: v2ray-plugin\n", 1, true) ~= nil)
check("clashmeta v2ray-plugin mode",
	v2:find("      mode: websocket\n", 1, true) ~= nil)
check("clashmeta v2ray-plugin host", v2:find("      host: h.com\n", 1, true) ~= nil)
check("clashmeta v2ray-plugin path", v2:find("      path: /ws\n", 1, true) ~= nil)
check("clashmeta v2ray-plugin tls", v2:find("      tls: true\n", 1, true) ~= nil)

-- 参数非法时必须**整个不输出**插件：mihomo 对这两类插件是强校验的，
-- 输出一个必然被拒绝的组合会让整份配置加载失败，一个坏节点废掉整个订阅。
local bad_obfs = clash_meta.generate({ ss("obfs-local") })
check("clashmeta obfs without mode omitted",
	bad_obfs:find("plugin:", 1, true) == nil)
local bad_obfs2 = clash_meta.generate({ ss("obfs-local;obfs=bogus") })
check("clashmeta obfs invalid mode omitted",
	bad_obfs2:find("plugin:", 1, true) == nil)
local bad_v2 = clash_meta.generate({ ss("v2ray-plugin;mode=quic") })
check("clashmeta v2ray-plugin invalid mode omitted",
	bad_v2:find("plugin:", 1, true) == nil)
-- 未知插件名：mihomo 的 plugin 分支没有收尾 else，未知名字本来就静默跳过
local unknown = clash_meta.generate({ ss("kcptun;key=abc") })
check("clashmeta unknown plugin omitted",
	unknown:find("plugin:", 1, true) == nil)
-- 无插件的普通 ss 节点不得凭空多出 plugin 字段
local plain = clash_meta.generate({ ss(nil) })
check("clashmeta plain ss has no plugin", plain:find("plugin", 1, true) == nil)

-- ---------- sing-box ----------
local sbox = singbox.generate({ d })
check("singbox emits plugin", sbox:find('"plugin":"obfs-local"', 1, true) ~= nil)
check("singbox plugin_opts is raw SIP003 string",
	sbox:find('"plugin_opts":"obfs=http;obfs-host=www.baidu.com"', 1, true) ~= nil)
-- sing-box 只支持这两个插件名，其余会拒绝加载整份配置
check("singbox unknown plugin omitted",
	singbox.generate({ ss("kcptun;key=abc") }):find('"plugin"', 1, true) == nil)
check("singbox v2ray-plugin kept",
	singbox.generate({ ss("v2ray-plugin;mode=websocket") }):find('"plugin":"v2ray-plugin"', 1, true) ~= nil)
check("singbox plain ss has no plugin",
	singbox.generate({ ss(nil) }):find('"plugin"', 1, true) == nil)

-- ---------- 分享链接回写（SIP002） ----------
local out_uri = uri_mod.to_share_uri(d)
check("uri keeps plugin query",
	out_uri:find("/?plugin=", 1, true) ~= nil)
check("uri percent-encodes plugin",
	out_uri:find("plugin=obfs-local%3Bobfs%3Dhttp%3Bobfs-host%3Dwww.baidu.com", 1, true) ~= nil)
-- 往返：导出 → 再解析，插件配置必须一字不差
local back = parser.parse(out_uri)
check("uri round-trip re-parses", back ~= nil and #back.nodes == 1)
check("uri round-trip plugin preserved",
	back.nodes[1].plugin == SPEC_PLUGIN)
-- 无插件时不得多出 `/?plugin=`
check("uri plain ss has no plugin query",
	uri_mod.to_share_uri(ss(nil)):find("plugin", 1, true) == nil)

-- ---------- 表单：字段清单与合并 ----------
local ss_fields = node.PROTO_FIELDS.shadowsocks
local has_plugin = false
for _, k in ipairs(ss_fields) do if k == "plugin" then has_plugin = true end end
check("PROTO_FIELDS.shadowsocks has plugin", has_plugin)
-- 表单渲染 plugin 后，清空输入框必须能真的删掉它
local cleared = core.merge_form_node(d, { proto = "shadowsocks", name = "S",
	server = "1.2.3.4", port = 8388, method = "aes-256-gcm", password = "p", plugin = "" })
check("merge_form_node clears plugin", cleared.plugin == "" or cleared.plugin == nil)
-- 表单提交了新值时必须生效
local updated = core.merge_form_node(d, { proto = "shadowsocks", name = "S",
	server = "1.2.3.4", port = 8388, method = "aes-256-gcm", password = "p",
	plugin = "v2ray-plugin;mode=websocket" })
check("merge_form_node applies plugin", updated.plugin == "v2ray-plugin;mode=websocket")

-- ---------- 结果 ----------
print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
