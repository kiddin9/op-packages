-- node_rename_test.lua — 节点重命名规则引擎单元测试
-- 用法：lua5.1 tests/node_rename_test.lua

package.path = "./root/usr/share/?.lua;" .. package.path

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

-- 辅助：创建节点
local function mk(proto, server, port, name)
	return { proto = proto, server = server, port = port, name = name or (server .. ":" .. port) }
end

-- ---------- parse_rename_rules ----------
check("parse empty rules", #node.parse_rename_rules("") == 0)

local rules1 = node.parse_rename_rules("^(.*):(\\d+)$ -> $1")
check("parse regex rule count", #rules1 == 1)
check("parse regex rule type", rules1[1] and rules1[1].type == "regex")
check("parse regex pattern", rules1[1] and rules1[1].pattern == "^(.*):(\\d+)$")
check("parse regex replacement", rules1[1] and rules1[1].replacement == "$1")

local rules2 = node.parse_rename_rules("vmess -> VMESS")
check("parse simple replace", #rules2 == 1 and rules2[1].type == "regex")
check("parse simple pattern", rules2[1].pattern == "vmess")
check("parse simple replacement", rules2[1].replacement == "VMESS")

local rules3 = node.parse_rename_rules("{server}_{port}_{proto}")
check("parse template rule count", #rules3 == 1)
check("parse template rule type", rules3[1] and rules3[1].type == "template")
check("parse template content", rules3[1] and rules3[1].template == "{server}_{port}_{proto}")

local rules4 = node.parse_rename_rules([[
^(.*):(\d+)$ -> $1
vmess -> VMESS
{server}_{port}_{proto}
]])
check("parse multiple rules", #rules4 == 3)

-- 精确匹配：旧名称=新名称
local rules5 = node.parse_rename_rules("香港=HK")
check("parse exact rule count", #rules5 == 1)
check("parse exact rule type", rules5[1] and rules5[1].type == "exact")
check("parse exact old", rules5[1] and rules5[1].old == "香港")
check("parse exact new", rules5[1] and rules5[1].new == "HK")

local rules6 = node.parse_rename_rules(" 香港 = HK ")
check("parse exact trim", rules6[1] and rules6[1].old == "香港" and rules6[1].new == "HK")

-- 注释行应被忽略
local rules7 = node.parse_rename_rules("# 注释\n香港=HK")
check("parse exact skips comment", #rules7 == 1 and rules7[1].type == "exact")

-- ---------- rename_with_rules ----------
-- 测试正则替换
local nodes1 = { mk("vmess", "1.2.3.4", 443, "1.2.3.4:443") }
node.rename_with_rules(nodes1, node.parse_rename_rules("^(.*):(\\d+)$ -> $1"))
check("regex rename strip port", nodes1[1].name == "1.2.3.4")

-- 测试简单替换
local nodes2 = { mk("vmess", "1.2.3.4", 443, "vmess node") }
node.rename_with_rules(nodes2, node.parse_rename_rules("vmess -> VMESS"))
check("simple replace vmess", nodes2[1].name == "VMESS node")

-- 测试模板变量
local nodes3 = { mk("vmess", "1.2.3.4", 443, "old") }
node.rename_with_rules(nodes3, node.parse_rename_rules("{server}_{port}_{proto}"))
check("template rename", nodes3[1].name == "1.2.3.4_443_vmess")

-- 测试链式规则
local nodes4 = { mk("vmess", "1.2.3.4", 443, "1.2.3.4:443") }
node.rename_with_rules(nodes4, node.parse_rename_rules([[
^(.*):(\d+)$ -> $1
vmess -> VMESS
]]))
-- 第一步去掉端口 -> 1.2.3.4, 第二步 vmess->VMESS 不匹配
check("chain rule 1", nodes4[1].name == "1.2.3.4")

-- 测试模板后接替换
local nodes5 = { mk("vmess", "1.2.3.4", 443, "old") }
node.rename_with_rules(nodes5, node.parse_rename_rules([[
{server}_{port}_{proto}
vmess -> VMESS
]]))
check("template then replace", nodes5[1].name == "1.2.3.4_443_VMESS")

-- 测试精确匹配重命名
local nodes6 = { mk("vmess", "1.2.3.4", 443, "香港") }
node.rename_with_rules(nodes6, node.parse_rename_rules("香港=HK"))
check("exact rename match", nodes6[1].name == "HK")

-- 精确匹配不命中时不改动
local nodes7 = { mk("vmess", "1.2.3.4", 443, "东京") }
node.rename_with_rules(nodes7, node.parse_rename_rules("香港=HK"))
check("exact rename no match", nodes7[1].name == "东京")

-- 精确匹配 + 模板链式
local nodes8 = { mk("vmess", "1.2.3.4", 443, "香港") }
node.rename_with_rules(nodes8, node.parse_rename_rules([[
香港=HK
{name}_{port}
]]))
check("exact then template", nodes8[1].name == "HK_443")

-- 保持向后兼容：M.rename
local n = mk("vmess", "1.1.1.1", 443, "old")
node.rename(n, "new")
check("backward compat rename", n.name == "new")

-- ---------- 结果 ----------
print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
