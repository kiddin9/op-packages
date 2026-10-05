-- view_injection_test.lua — 视图层的注入与字段清单一致性检查
-- 用法：lua5.1 tests/view_injection_test.lua
--
-- 这些是静态源码检查（.htm 需要 LuCI 运行时才能渲染，lua5.1 跑不了模板），
-- 但检查的正是那类「只在浏览器里才暴露」的缺陷：
--   H2  注入到 <script> 里的值必须转义 "</"：json_encode 不转义 "<"，
--       而 "</script" 会在 HTML 词法阶段就闭合脚本元素（与 JS 字符串上下文无关），
--       查询串里的 id 可以直接构造出 "</script><script>alert(1)</script>"。
--   字段清单必须由服务端注入：core.merge_form_node 用 node.PROTO_FIELDS 决定
--       哪些字段可以被表单覆盖，前端若另抄一份就会漂移（vmess 的 TLS 字段
--       丢失正是这么来的）。

package.path = "./root/usr/share/?.lua;" .. package.path

local util = require("substore.util")
local node = require("substore.node")

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

local VIEWS = {
	"root/usr/lib/lua/luci/view/substore/nodes.htm",
	"root/usr/lib/lua/luci/view/substore/node_edit.htm",
	"root/usr/lib/lua/luci/view/substore/local_form.htm",
	"root/usr/lib/lua/luci/view/substore/subscriptions.htm",
	"root/usr/lib/lua/luci/view/substore/form.htm",
	"root/usr/lib/lua/luci/view/substore/combo.htm",
	"root/usr/lib/lua/luci/view/substore/output.htm",
}

-- ---------- H2：JSON 编码注入到 JS 的位置必须转义**全部** "<" ----------
--
-- 只转 "</" 是不够的：HTML 词法阶段一旦看到 "<!--"，就进入 script data escaped
-- 状态，其后的 "</script>" 不再结束脚本块 —— 页面剩余部分全被当成脚本文本吞掉。
-- 转义全部 "<" 为 \u003c 后，HTML 词法阶段看不到任何 "<"，两个坑一并堵上；
-- 而 \u003c 在 JSON 与 JS 字符串字面量里都还原成 "<"，取值不受影响。
--
-- 逐个 json_encode 调用点检查：要么同一行/下一行出现 gsub("<", …)，
-- 要么该值是白名单归一化后的固定取值（注释里标注了「白名单」）。
for _, path in ipairs(VIEWS) do
	local src = util.read_file(path)
	if src then
		local lines = {}
		for l in (src .. "\n"):gmatch("([^\n]*)\n") do lines[#lines + 1] = l end
		for i, l in ipairs(lines) do
			-- 只关心真正注入到模板里的调用，跳过注释
			if l:find("json_encode") and not l:match("^%s*%-%-") and not l:match("^%s*//") then
				-- 转义可能写在下一行，白名单说明通常写在紧邻的注释里（上一两行）
				local window = (lines[i - 2] or "") .. (lines[i - 1] or "") .. l .. (lines[i + 1] or "")
				local escaped = window:find('gsub("<"', 1, true) ~= nil
					and window:find("\\u003c", 1, true) ~= nil
				-- 白名单归一化的取值（"text"/"form"）不含 "<"，无需转义
				local whitelisted = window:find("白名单", 1, true) ~= nil
				check(path:match("[^/]+$") .. ":" .. i .. ' json_encode escapes <',
					escaped or whitelisted)
			end
		end
	end
end

-- 反向验证：不转义时确实能闭合 script（说明上面的检查不是空转）
local payload = "</script><script>alert(1)</script>"
check("json_encode does not escape <", util.json_encode(payload):find("</script", 1, true) ~= nil)
check("gsub(</) removes the closing tag",
	(util.json_encode(payload):gsub("</", "<\\/")):find("</script", 1, true) == nil)

-- 反向验证之二：只转 "</" 挡不住 "<!--" —— 这正是本轮把转义范围放宽到全部 "<" 的原因。
-- 该断言在旧实现（gsub("</") ）上必须成立，否则说明这条理由不成立。
local comment_payload = "<!--x"
check("gsub(</) alone still leaves <!-- (page-breaking)",
	(util.json_encode(comment_payload):gsub("</", "<\\/")):find("<!--", 1, true) ~= nil)
check("gsub(<) escapes <!-- too",
	(util.json_encode(comment_payload):gsub("<", "\\u003c")):find("<!--", 1, true) == nil)
check("gsub(<) still removes the closing tag",
	(util.json_encode(payload):gsub("<", "\\u003c")):find("</script", 1, true) == nil)

-- ---------- 字段清单：唯一来源在 Lua，页面负责注入 ----------
local js = util.read_file("root/www/luci-static/resources/substore/nodeform.js")
check("nodeform.js readable", js ~= nil)
-- 注释里会举例说明注入方式（"var PROTO_FIELDS = { proto: [...] }"），先剥掉注释再查
local js_code = js:gsub("/%*.-%*/", ""):gsub("//[^\n]*", "")
check("nodeform.js does not hardcode PROTO_FIELDS", js_code:find("PROTO_FIELDS = {") == nil)
check("nodeform.js does not hardcode SUBSTORE_PROTOS",
	js_code:find('SUBSTORE_PROTOS = %[') == nil)
check("nodeform.js reads injected PROTO_FIELDS", js:find("window.SUBSTORE_PROTO_FIELDS") ~= nil)
check("nodeform.js reads injected SUBSTORE_PROTOS", js:find("window.SUBSTORE_PROTOS") ~= nil)

for _, path in ipairs({ "root/usr/lib/lua/luci/view/substore/node_edit.htm",
	"root/usr/lib/lua/luci/view/substore/local_form.htm" }) do
	local src = util.read_file(path) or ""
	local name = path:match("[^/]+$")
	check(name .. " injects SUBSTORE_PROTOS", src:find("var SUBSTORE_PROTOS = <%=js_protos%>", 1, true) ~= nil)
	check(name .. " injects SUBSTORE_PROTO_FIELDS", src:find("var SUBSTORE_PROTO_FIELDS = <%=js_proto_fields%>", 1, true) ~= nil)
	check(name .. " loads nodeform.js", src:find("nodeform.js", 1, true) ~= nil)
end

-- 每个协议都要有字段清单，否则表单渲染不出任何输入框
for _, p in ipairs(node.PROTOS) do
	local f = node.PROTO_FIELDS[p]
	check("PROTO_FIELDS has " .. p, type(f) == "table" and #f > 0)
end

-- 每个渲染出来的字段都要有标签，否则界面上直接显示英文键名。
--
-- 两份模板各有一份 FIELD_LABELS（node_edit.htm 编辑单个节点，local_form.htm
-- 本地订阅的表单导入），此前只检查了 node_edit.htm —— 于是 local_form.htm
-- 可以静默缺标签，症状是那个表单里直接显示英文键名。两份都要查。
--
-- 这里刻意**不做**「两份键集完全相等」的断言：标签是用 '"([%w%-]+)"%s*:' 从
-- 模板文本里抠出来的，会连带抠到无关的 JS 字符串键（实测 local_form.htm 会多出
-- `? "block" : "none"` 里的 "block"），做相等断言必然误报。真正要保证的不变量
-- 是「每份模板都覆盖了全部字段」，逐个字段查即可。
local LABEL_TEMPLATES = {
	"root/usr/lib/lua/luci/view/substore/node_edit.htm",
	"root/usr/lib/lua/luci/view/substore/local_form.htm",
}
local REQUIRED_FIELDS = {}
for _, fields in pairs(node.PROTO_FIELDS) do
	for _, k in ipairs(fields) do REQUIRED_FIELDS[k] = true end
end
for _, k in ipairs(node.FORM_ALWAYS_FIELDS) do REQUIRED_FIELDS[k] = true end

for _, path in ipairs(LABEL_TEMPLATES) do
	local name = path:match("[^/]+$")
	local src = util.read_file(path) or ""
	local labels = {}
	for k in src:gmatch('"([%w%-]+)"%s*:') do labels[k] = true end
	local missing = {}
	for k in pairs(REQUIRED_FIELDS) do
		if not labels[k] then missing[#missing + 1] = k end
	end
	table.sort(missing)
	check(name .. " labels every form field" .. (#missing > 0 and (" (missing: " .. table.concat(missing, ",") .. ")") or ""),
		#missing == 0)
end

-- TLS 层字段必须出现在表单里，否则编辑一次就丢 TLS（vmess 的历史缺陷）
for _, p in ipairs({ "vmess", "vless" }) do
	local has = false
	for _, k in ipairs(node.PROTO_FIELDS[p]) do if k == "security" then has = true end end
	check(p .. " form renders security", has)
end

-- TLS-only 协议必须由 normalize 保证 security，而不是靠 URI 解析器各自补。
-- 清单直接读 node.TLS_ONLY（唯一来源）：在这里另写一份字面量的话，新增一个
-- TLS-only 协议时本用例不会覆盖它，测试看着全绿其实漏测。
for p in pairs(node.TLS_ONLY) do
	check(p .. " normalize forces security=tls",
		node.normalize({ proto = p, server = "h", port = 1 }).security == "tls")
end
-- TLS_ONLY 必须非空，否则上面的循环一条都不跑，静默通过
check("TLS_ONLY non-empty", next(node.TLS_ONLY) ~= nil)

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
