-- converter_test.lua — 转换引擎单元测试
-- 用法：lua5.1 tests/converter_test.lua

package.path = "./root/usr/share/?.lua;" .. package.path

local converter = require("substore.converter")

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

-- ---------- 基础功能测试 ----------
check("module exists", converter ~= nil)
check("validate_nodes method exists", type(converter.validate_nodes) == "function")
check("convert method exists", type(converter.convert) == "function")
check("process_pipeline method exists", type(converter.process_pipeline) == "function")
check("apply_template method exists", type(converter.apply_template) == "function")

-- ---------- validate_nodes 测试 ----------
local valid_nodes = {
	{ proto = "vmess", server = "1.1.1.1", port = 443, name = "Node1" },
	{ proto = "vless", server = "2.2.2.2", port = 8443, name = "Node2" },
}
local ok, errs = converter.validate_nodes(valid_nodes)
check("validate_nodes valid", ok == true and (errs == nil or #errs == 0))

local invalid_nodes = {
	{ proto = "vmess", server = "1.1.1.1", port = nil },
	{ proto = nil, server = "2.2.2.2", port = 443 },
}
local ok2, errs2 = converter.validate_nodes(invalid_nodes)
check("validate_nodes invalid", ok2 == false and errs2 ~= nil and #errs2 > 0)

-- ---------- convert 测试 ----------
local nodes_for_output = {
	{ proto = "vmess", name = "TestVMess", server = "1.1.1.1", port = 443, uuid = "uuid-1" },
	{ proto = "trojan", name = "TestTrojan", server = "2.2.2.2", port = 443, password = "pass" },
}
local yaml_out = converter.convert(nodes_for_output, "clash", {})
check("convert clash returns string", type(yaml_out) == "string" and yaml_out:find("proxies:") ~= nil)
check("convert clash contains node name", yaml_out and yaml_out:find("TestVMess") ~= nil)

local json_out = converter.convert(nodes_for_output, "json", {})
check("convert json returns string", type(json_out) == "string" and json_out:find("TestVMess") ~= nil)

local b64_out = converter.convert(nodes_for_output, "base64", {})
check("convert base64 returns string", type(b64_out) == "string" and #b64_out > 0)

-- ---------- process_pipeline 测试 ----------
local pipeline_nodes = {
	{ proto = "vmess", name = "HK VMESS", server = "1.1.1.1", port = 443 },
	{ proto = "trojan", name = "US TROJAN", server = "2.2.2.2", port = 443 },
	{ proto = "vmess", name = "JP VMESS", server = "3.3.3.3", port = 443 },
}
local pipeline = {
	{ type = "filter", opts = { proto = "vmess" } },
}
local filtered = converter.process_pipeline(pipeline_nodes, pipeline)
check("process_pipeline filter count", filtered ~= nil and #filtered == 2)
check("process_pipeline filter proto", filtered and filtered[1].proto == "vmess" and filtered[2].proto == "vmess")

-- ---------- apply_template 测试 ----------
local template_nodes = {
	{ proto = "vmess", name = "NodeA", server = "1.1.1.1", port = 443 },
}
local template = "{{name}}-{{proto}}"
local templated = converter.apply_template(template_nodes, template)
check("apply_template returns table", type(templated) == "table")
check("apply_template preserves count", templated ~= nil and #templated == 1)

-- ---------- 结果 ----------
print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
