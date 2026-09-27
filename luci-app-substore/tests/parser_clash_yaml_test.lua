-- parser_clash_yaml_test.lua — Clash YAML 解析单元测试
-- 用法：lua5.1 tests/parser_clash_yaml_test.lua

package.path = "./root/usr/share/?.lua;" .. package.path

local parser = require("substore.parser_clash_yaml")

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

-- ---------- 基本 Clash YAML ----------
local clash_yaml_basic = [[
proxies:
  - name: TestVMess
    type: vmess
    server: 1.1.1.1
    port: 443
    uuid: abc-123
    alterId: 0
    cipher: auto
    network: ws
    ws-opts:
      path: /ws
      headers:
        Host: example.com
    tls: true
    servername: example.com
  - name: TestVLESS
    type: vless
    server: 2.2.2.2
    port: 443
    uuid: vless-uuid-123
    network: tcp
    tls: true
    sni: example.org
    alpn:
      - h2
      - http/1.1
    fp: chrome
  - name: TestTrojan
    type: trojan
    server: 3.3.3.3
    port: 443
    password: trojan-pass
    sni: example.com
    skip-cert-verify: true
    udp: true
  - name: TestSS
    type: ss
    server: 4.4.4.4
    port: 8388
    cipher: aes-256-gcm
    password: ss-pass
  - name: TestHysteria2
    type: hysteria2
    server: 5.5.5.5
    port: 443
    password: hy2-pass
    sni: hy2.example.com
    alpn:
      - h3
  - name: TestTUIC
    type: tuic
    server: 6.6.6.6
    port: 443
    uuid: tuic-uuid
    password: tuic-pass
    udp-relay-mode: native
  - name: TestWireGuard
    type: wireguard
    server: 7.7.7.7
    port: 51820
    uuid: wg-uuid
    private-key: wg-private
    peer-public-key: wg-peer
    preshared-key: wg-psk
  - name: TestSocks
    type: socks5
    server: 8.8.8.8
    port: 1080
    username: user
    password: pass
]]

local nodes = parser.parse(clash_yaml_basic)
check("parse returns table", type(nodes) == "table")
check("node count", nodes and #nodes == 8)

if nodes and #nodes >= 1 then
	local n1 = nodes[1]
	check("vmess name", n1.name == "TestVMess")
	check("vmess proto", n1.proto == "vmess")
	check("vmess server", n1.server == "1.1.1.1")
	check("vmess port", n1.port == 443)
	check("vmess uuid", n1.uuid == "abc-123")
	check("vmess net", n1.net == "ws")
	check("vmess sni", n1.sni == "example.com")
end

if nodes and #nodes >= 2 then
	local n2 = nodes[2]
	check("vless name", n2.name == "TestVLESS")
	check("vless proto", n2.proto == "vless")
	check("vless server", n2.server == "2.2.2.2")
	check("vless port", n2.port == 443)
	check("vless uuid", n2.uuid == "vless-uuid-123")
	check("vless sni", n2.sni == "example.org")
	check("vless alpn", n2.alpn ~= nil)
	check("vless fp", n2.fp == "chrome")
end

if nodes and #nodes >= 3 then
	local n3 = nodes[3]
	check("trojan name", n3.name == "TestTrojan")
	check("trojan proto", n3.proto == "trojan")
	check("trojan server", n3.server == "3.3.3.3")
	check("trojan port", n3.port == 443)
	check("trojan password", n3.password == "trojan-pass")
	check("trojan sni", n3.sni == "example.com")
	check("trojan skip-cert-verify", n3["skip-cert-verify"] == true or n3.skip_cert_verify == true)
	check("trojan udp", n3.udp == true)
end

if nodes and #nodes >= 4 then
	local n4 = nodes[4]
	check("ss name", n4.name == "TestSS")
	check("ss proto", n4.proto == "shadowsocks")
	check("ss server", n4.server == "4.4.4.4")
	check("ss port", n4.port == 8388)
	check("ss method", n4.method == "aes-256-gcm")
	check("ss password", n4.password == "ss-pass")
end

if nodes and #nodes >= 5 then
	local n5 = nodes[5]
	check("hysteria2 name", n5.name == "TestHysteria2")
	check("hysteria2 proto", n5.proto == "hysteria2")
	check("hysteria2 server", n5.server == "5.5.5.5")
	check("hysteria2 port", n5.port == 443)
	check("hysteria2 password", n5.password == "hy2-pass")
end

if nodes and #nodes >= 6 then
	local n6 = nodes[6]
	check("tuic name", n6.name == "TestTUIC")
	check("tuic proto", n6.proto == "tuic")
	check("tuic server", n6.server == "6.6.6.6")
end

if nodes and #nodes >= 7 then
	local n7 = nodes[7]
	check("wireguard name", n7.name == "TestWireGuard")
	check("wireguard proto", n7.proto == "wireguard")
	check("wireguard server", n7.server == "7.7.7.7")
end

if nodes and #nodes >= 8 then
	local n8 = nodes[8]
	check("socks name", n8.name == "TestSocks")
	check("socks proto", n8.proto == "socks")
	check("socks server", n8.server == "8.8.8.8")
end

-- ---------- proxy-groups ----------
local clash_yaml_groups = [[
proxies:
  - name: Node1
    type: vmess
    server: 1.1.1.1
    port: 443
    uuid: u1
proxy-groups:
  - name: Group1
    type: select
    proxies:
      - Node1
      - REJECT
]]

local nodes2 = parser.parse(clash_yaml_groups)
check("groups parse nodes", nodes2 and #nodes2 == 1)
check("groups parse name", nodes2 and nodes2[1].name == "Node1")

-- ---------- 流式 JSON 节点（机场 clash 配置常见写法）----------
local clash_yaml_flow = [[
proxies:
  - {"name":"V1-FlowVMess","type":"vmess","server":"a.cdn.node.example.com","port":30849,"uuid":"u-1","alterId":0,"cipher":"auto","udp":true,"tags":"hk","network":"ws","ws-opts":{"path":"/009c.x.m3u8","headers":{"Host":"edge.example.com"}},"skip-cert-verify":false}
  - {"name":"V1-FlowSSR","type":"ssr","server":"b.cdn.node.example.com","port":30800,"cipher":"chacha20-ietf","password":"pwd","protocol":"auth_aes128_sha1","protocol-param":"174188:MUQuUs","obfs":"tls1.2_ticket_auth","obfs-param":"cdn.com","udp":true,"tags":"jp"}
]]

local fnodes = parser.parse(clash_yaml_flow)
check("flow node count", fnodes and #fnodes == 2)

if fnodes and #fnodes >= 1 then
	local f1 = fnodes[1]
	check("flow vmess proto", f1.proto == "vmess")
	check("flow vmess name", f1.name == "V1-FlowVMess")
	check("flow vmess server", f1.server == "a.cdn.node.example.com")
	check("flow vmess port", f1.port == 30849)
	check("flow vmess uuid", f1.uuid == "u-1")
	check("flow vmess net", f1.net == "ws")
	check("flow vmess path", f1.path == "/009c.x.m3u8")
	check("flow vmess host", f1.host == "edge.example.com")
end

if fnodes and #fnodes >= 2 then
	local f2 = fnodes[2]
	check("flow ssr proto", f2.proto == "ssr")
	check("flow ssr server", f2.server == "b.cdn.node.example.com")
	check("flow ssr cipher", f2.method == "chacha20-ietf")
	check("flow ssr protocol", f2.protocol == "auth_aes128_sha1")
	check("flow ssr obfs", f2.obfs == "tls1.2_ticket_auth")
end

-- ---------- 结果 ----------
print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
