-- singbox_transport_test.lua — sing-box 出站 transport 读取回归测试
-- 用法：lua5.1 tests/singbox_transport_test.lua
--
-- 缺陷（docs/LEGACY_ISSUES.md 1.3）：两个读取侧都不认 sing-box 的 transport 对象 ——
-- parser_json_config 读的是 outbound.network（sing-box 出站里根本没有这个字段），
-- 简易 YAML 解析器只展开 tls: 子块。于是 ws / grpc / h2 节点全部按 tcp 导入，
-- 客户端拿明文 tcp 去连只开了 ws 的端口，握手必然失败且**不报错**。
-- 简易 YAML 侧更彻底：path / host 连带都没带进 node_data。
--
-- 字段名取自上游 sing-box.sagernet.org/configuration/shared/v2ray-transport/：
--   ws           path、headers.Host
--   grpc         service_name
--   http         path、host（数组）
--   httpupgrade  path、host（单个字符串）

package.path = "./root/usr/share/?.lua;" .. package.path

local parser = require("substore.parser")

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

local function first(content)
	local r = parser.parse(content)
	return r and r.nodes and r.nodes[1] or nil
end

-- ---------- JSON 侧 ----------
local JSON_WS = [[{"outbounds":[{"type":"vmess","tag":"n","server":"1.2.3.4",
"server_port":443,"uuid":"11111111-2222-3333-4444-555555555555",
"transport":{"type":"ws","path":"/ws","headers":{"Host":"a.com"}},
"tls":{"enabled":true,"server_name":"a.com","utls":{"enabled":true,"fingerprint":"chrome"}}}]}]]

local jw = first(JSON_WS)
check("json ws node parsed", jw ~= nil)
check("json ws net", jw and jw.net == "ws")
check("json ws path", jw and jw.path == "/ws")
check("json ws host from headers.Host", jw and jw.host == "a.com")
check("json tls utls fingerprint", jw and jw.fp == "chrome")
check("json tls server_name", jw and jw.sni == "a.com")

local jg = first([[{"outbounds":[{"type":"vless","tag":"n","server":"1.2.3.4",
"server_port":443,"uuid":"u","transport":{"type":"grpc","service_name":"svc"}}]}]])
check("json grpc net", jg and jg.net == "grpc")
check("json grpc service_name -> path", jg and jg.path == "svc")

local jh = first([[{"outbounds":[{"type":"vless","tag":"n","server":"1.2.3.4",
"server_port":443,"uuid":"u","transport":{"type":"http","host":["h1.com","h2.com"],"path":"/p"}}]}]])
check("json http net", jh and jh.net == "http")
check("json http path", jh and jh.path == "/p")
-- http 的 host 是数组，取首个
check("json http host takes first of array", jh and jh.host == "h1.com")

local ju = first([[{"outbounds":[{"type":"vless","tag":"n","server":"1.2.3.4",
"server_port":443,"uuid":"u","transport":{"type":"httpupgrade","host":"hu.com","path":"/hu"}}]}]])
check("json httpupgrade net", ju and ju.net == "http")
check("json httpupgrade path", ju and ju.path == "/hu")
-- httpupgrade 的 host 是单个字符串（与 http 的数组不同）
check("json httpupgrade host", ju and ju.host == "hu.com")

-- quic 在本项目模型里没有对应传输方式，不得凭空映射成别的
local jq = first([[{"outbounds":[{"type":"vless","tag":"n","server":"1.2.3.4",
"server_port":443,"uuid":"u","transport":{"type":"quic"}}]}]])
check("json quic not mapped to a wrong transport",
	jq and jq.net ~= "ws" and jq.net ~= "grpc" and jq.net ~= "http")

-- 无 transport 的普通节点不得被改动
local jplain = first([[{"outbounds":[{"type":"trojan","tag":"n","server":"1.2.3.4",
"server_port":443,"password":"p"}]}]])
check("json node without transport still parses", jplain and jplain.proto == "trojan")
check("json node without transport has no path", jplain and jplain.path == nil)

-- ---------- 简易 YAML 侧 ----------
-- 用一条 Clash YAML 解析器认不出的 sing-box 风格 YAML，强制走回退解析器
local YAML_WS = [[outbounds:
  - type: vmess
    tag: n
    server: 1.2.3.4
    server_port: 443
    uuid: 11111111-2222-3333-4444-555555555555
    transport:
      type: ws
      path: /ws
      headers:
        Host: a.com
    tls:
      enabled: true
      server_name: a.com
      utls:
        enabled: true
        fingerprint: chrome
]]
local yw = first(YAML_WS)
check("yaml ws node parsed", yw ~= nil)
check("yaml ws net", yw and yw.net == "ws")
check("yaml ws path", yw and yw.path == "/ws")
check("yaml ws host", yw and yw.host == "a.com")
check("yaml tls utls fingerprint", yw and yw.fp == "chrome")

local YAML_GRPC = [[outbounds:
  - type: vless
    tag: n
    server: 1.2.3.4
    server_port: 443
    uuid: u
    transport:
      type: grpc
      service_name: svc
]]
local yg = first(YAML_GRPC)
check("yaml grpc net", yg and yg.net == "grpc")
check("yaml grpc service_name -> path", yg and yg.path == "svc")

-- 两条导入路径必须给出一致的节点（同一条订阅走 JSON 与 YAML 不该有差别）
check("json and yaml agree on net", jw and yw and jw.net == yw.net)
check("json and yaml agree on path", jw and yw and jw.path == yw.path)
check("json and yaml agree on host", jw and yw and jw.host == yw.host)
check("json and yaml agree on fp", jw and yw and jw.fp == yw.fp)

-- ---------- 结果 ----------
print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
