-- output_clash_meta_test.lua — Clash.Meta / Mihomo 输出单元测试
-- 用法：lua5.1 tests/output_clash_meta_test.lua

package.path = "./root/usr/share/?.lua;" .. package.path

local output_clash_meta = require("substore.output_clash_meta")

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
check("module exists", output_clash_meta ~= nil)
check("generate method exists", type(output_clash_meta.generate) == "function")

-- ---------- 测试节点 ----------
local test_nodes = {
	{
		proto = "vmess",
		name = "TestVMess",
		server = "1.1.1.1",
		port = 443,
		uuid = "abc-123",
		net = "ws",
		security = "tls",
		sni = "example.com",
		path = "/ws",
		host = "example.com",
	},
	{
		proto = "vless",
		name = "TestVLESS",
		server = "2.2.2.2",
		port = 443,
		uuid = "vless-uuid-123",
		net = "tcp",
		security = "tls",
		sni = "example.org",
		alpn = "h2,http/1.1",
		fp = "chrome",
	},
	{
		proto = "trojan",
		name = "TestTrojan",
		server = "3.3.3.3",
		port = 443,
		password = "trojan-pass",
		sni = "example.com",
		["skip-cert-verify"] = true,
		udp = true,
	},
	{
		proto = "shadowsocks",
		name = "TestSS",
		server = "4.4.4.4",
		port = 8388,
		method = "aes-256-gcm",
		password = "ss-pass",
	},
	{
		proto = "hysteria2",
		name = "TestHysteria2",
		server = "5.5.5.5",
		port = 443,
		password = "hy2-pass",
		sni = "hy2.example.com",
		alpn = "h3",
	},
	{
		proto = "tuic",
		name = "TestTUIC",
		server = "6.6.6.6",
		port = 443,
		uuid = "tuic-uuid",
		password = "tuic-pass",
		["udp-relay-mode"] = "native",
	},
	{
		proto = "wireguard",
		name = "TestWireGuard",
		server = "7.7.7.7",
		port = 51820,
		["private-key"] = "wg-private",
		["peer-public-key"] = "wg-peer",
		["preshared-key"] = "wg-psk",
	},
	{
		proto = "socks",
		name = "TestSocks",
		server = "8.8.8.8",
		port = 1080,
		username = "user",
		password = "pass",
	},
}

-- ---------- 生成测试 ----------
local options = {
	name = "TestGroup",
	latency_test = true,
	health_check = true,
}

local yaml_output = output_clash_meta.generate(test_nodes, options)

check("generate returns string", type(yaml_output) == "string")
check("output contains proxies", yaml_output and yaml_output:find("proxies:") ~= nil)
check("output contains proxy-groups", yaml_output and yaml_output:find("proxy%-groups:") ~= nil)
check("output contains vmess node", yaml_output and yaml_output:find("TestVMess") ~= nil)
check("output contains vless node", yaml_output and yaml_output:find("TestVLESS") ~= nil)
check("output contains trojan node", yaml_output and yaml_output:find("TestTrojan") ~= nil)
check("output contains shadowsocks node", yaml_output and yaml_output:find("TestSS") ~= nil)
check("output contains hysteria2 node", yaml_output and yaml_output:find("TestHysteria2") ~= nil)
check("output contains tuic node", yaml_output and yaml_output:find("TestTUIC") ~= nil)
check("output contains wireguard node", yaml_output and yaml_output:find("TestWireGuard") ~= nil)
check("output contains socks node", yaml_output and yaml_output:find("TestSocks") ~= nil)

-- 检查协议类型映射
check("vmess type present", yaml_output and yaml_output:find("type: vmess") ~= nil)
check("vless type present", yaml_output and yaml_output:find("type: vless") ~= nil)
check("trojan type present", yaml_output and yaml_output:find("type: trojan") ~= nil)
check("ss type present", yaml_output and yaml_output:find("type: ss") ~= nil)

-- 检查特殊字段
check("skip-cert-verify present", yaml_output and yaml_output:find("skip%-cert%-verify") ~= nil)
check("udp present", yaml_output and yaml_output:find("udp:") ~= nil)
check("alpn present", yaml_output and yaml_output:find("alpn:") ~= nil)
-- H14：uTLS 指纹的键名是 client-fingerprint，**不是** fp。
-- mihomo 全仓库没有任何结构体声明 `proxy:"fp,..."`，而它的 proxy 解码器对未知键
-- 是静默忽略的 —— 写 `fp:` 既不报错也不生效，配置看起来有指纹、实际用默认指纹。
-- 这条断言此前锁的正是那个 bug（find("fp:")）。
check("client-fingerprint present",
	yaml_output and yaml_output:find("client%-fingerprint: chrome") ~= nil)
check("no bogus fp key", yaml_output and yaml_output:find("    fp:") == nil)

-- 检查 proxy-groups
check("SELECT group present", yaml_output and yaml_output:find("type: select") ~= nil)
check("URL-TEST group present", yaml_output and yaml_output:find("type: url%-test") ~= nil)
check("LOAD-BALANCE group present", yaml_output and yaml_output:find("type: load%-balance") ~= nil)

-- 检查选项
check("name option used", yaml_output and yaml_output:find("TestGroup") ~= nil)

-- ---------- 空节点测试 ----------
local empty_output = output_clash_meta.generate({}, {})
check("empty nodes handled", type(empty_output) == "string")

-- ---------- 结果 ----------
-- H12：sni 与 servername 是同一字段的两种写法，同时存在时只能输出一个 servername
-- 键。Clash YAML 导入会同时填上两者，各写一行会让 YAML 出现重复键。
local dup_out = output_clash_meta.generate({ { proto = "vmess", name = "D", server = "1.1.1.1",
	port = 443, uuid = "u", sni = "s.example.com", servername = "s.example.com" } })
local dup_count = 0
for _ in dup_out:gmatch("servername:") do dup_count = dup_count + 1 end
check("no duplicate servername key", dup_count == 1)
check("servername value kept", dup_out:find("servername: s%.example%.com") ~= nil)
check("servername only still emitted",
	output_clash_meta.generate({ { proto = "vmess", name = "S", server = "1.1.1.1", port = 443,
		uuid = "u", servername = "only.example.com" } }):find("servername: only%.example%.com") ~= nil)

-- H13：含控制字符的值必须转义并加双引号。未加引号的换行/回车会破坏文档结构，
-- 而转义后的 "\t" 落在 plain scalar 里会被 YAML 当成两个普通字符。
local esc_out = output_clash_meta.generate({ { proto = "vmess", name = "tab\there", server = "1.1.1.1",
	port = 443, uuid = "u", password = "p\rw" } })
check("tab escaped and quoted", esc_out:find('"tab\\there"') ~= nil)
check("CR escaped and quoted", esc_out:find('"p\\rw"') ~= nil)
check("no raw CR in output", esc_out:find("\r") == nil)
local nl_out = output_clash_meta.generate({ { proto = "vmess", name = "a\nb", server = "1.1.1.1",
	port = 443, uuid = "u" } })
check("newline name quoted and escaped", nl_out:find('name: "a\\nb"') ~= nil)
check("newline name does not add a line", nl_out:find('name: a\nb') == nil)

-- H14b：client-fingerprint 只对真正支持 uTLS 的协议输出。
-- hysteria / hysteria2 / tuic 在 mihomo 里的同名字段叫 fingerprint，但那是
-- 证书固定（SHA256 pin），与 uTLS 不是一回事；把模型的 fp 顶上去是语义错误，
-- 而 mihomo 又会静默忽略未知键 —— 用户以为指纹生效了，其实没有。
local hy2_fp = output_clash_meta.generate({ { proto = "hysteria2", name = "H2", server = "1.1.1.1",
	port = 443, password = "p", fp = "chrome" } })
check("hysteria2 drops fp (cert-pin semantics differ)", hy2_fp:find("fingerprint") == nil)
local tuic_fp = output_clash_meta.generate({ { proto = "tuic", name = "T", server = "1.1.1.1",
	port = 443, uuid = "u", password = "p", fp = "chrome" } })
check("tuic drops fp", tuic_fp:find("fingerprint") == nil)
-- ss 别名写法（未归一化的节点直接进输出模块）同样要认出来
local ss_fp = output_clash_meta.generate({ { proto = "ss", name = "S", server = "1.1.1.1",
	port = 8388, method = "aes-256-gcm", password = "p", fp = "chrome" } })
check("ss alias emits client-fingerprint", ss_fp:find("client%-fingerprint: chrome") ~= nil)

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
