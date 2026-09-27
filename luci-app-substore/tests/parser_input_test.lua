-- parser_input_test.lua — 多客户端配置导入（sing-box / V2Ray / Clash JSON / Surge / QX）单元测试
-- 用法：lua5.1 tests/parser_input_test.lua

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

check("module exists", parser ~= nil)
check("parse exists", type(parser.parse) == "function")

-- ---------- sing-box JSON ----------
local singbox = [[
{
  "outbounds": [
    { "type": "vmess", "tag": "sb-vmess", "server": "1.1.1.1", "server_port": 443, "uuid": "u1",
      "tls": { "enabled": true, "server_name": "sni.example.com" } },
    { "type": "trojan", "tag": "sb-trojan", "server": "2.2.2.2", "server_port": 443, "password": "p1" },
    { "type": "shadowsocks", "tag": "sb-ss", "server": "3.3.3.3", "server_port": 8388, "method": "aes-256-gcm", "password": "p2" }
  ]
}
]]

check("detect singbox = json", parser.detect(singbox) == "json")
local r1 = parser.parse(singbox)
check("singbox parses", r1 and r1.nodes ~= nil)
check("singbox 3 nodes", r1 and #r1.nodes == 3)
check("singbox vmess uuid", r1 and r1.nodes[1] and r1.nodes[1].uuid == "u1")
check("singbox vmess sni", r1 and r1.nodes[1] and r1.nodes[1].sni == "sni.example.com")
check("singbox trojan pass", r1 and r1.nodes[2] and r1.nodes[2].password == "p1")

-- ---------- V2Ray JSON ----------
local v2ray = [[
{
  "outbounds": [
    { "protocol": "vmess", "tag": "v-vmess",
      "settings": { "vnext": [ { "address": "5.5.5.5", "port": 443, "users": [ { "id": "vid-1" } ] } ] },
      "streamSettings": { "network": "ws", "security": "tls", "tlsSettings": { "serverName": "ws.example.com" } } }
  ]
}
]]

check("detect v2ray = json", parser.detect(v2ray) == "json")
local r2 = parser.parse(v2ray)
check("v2ray parses", r2 and r2.nodes ~= nil)
check("v2ray 1 node", r2 and #r2.nodes == 1)
check("v2ray uuid", r2 and r2.nodes[1] and r2.nodes[1].uuid == "vid-1")
check("v2ray net ws", r2 and r2.nodes[1] and r2.nodes[1].net == "ws")
check("v2ray sni", r2 and r2.nodes[1] and r2.nodes[1].sni == "ws.example.com")

-- ---------- Clash JSON ----------
local clashjson = [[
{ "proxies": [ { "name": "c-vmess", "type": "vmess", "server": "6.6.6.6", "port": 443, "uuid": "cu1" } ] }
]]
local r3 = parser.parse(clashjson)
check("clash json parses", r3 and r3.nodes ~= nil and #r3.nodes == 1)
check("clash json uuid", r3 and r3.nodes[1] and r3.nodes[1].uuid == "cu1")

-- ---------- Surge 配置 ----------
local surge = [[
[General]
loglevel = notify

[Proxy]
香港 = ss, 8.8.8.8, 8388, encrypt-method=aes-256-gcm, password=sspwd
美西 = vmess, 9.9.9.9, 443, username=vm-uuid, tls=true, sni=vm.example.com, ws=true, ws-path=/wsp

[Proxy Group]
PROXY = select, 香港, 美西
]]
check("detect surge = surge", parser.detect(surge) == "surge")
local r4 = parser.parse(surge)
check("surge parses", r4 and r4.nodes ~= nil)
check("surge 2 nodes", r4 and #r4.nodes == 2)
check("surge ss method", r4 and r4.nodes[1] and r4.nodes[1].method == "aes-256-gcm")
check("surge ss pass", r4 and r4.nodes[1] and r4.nodes[1].password == "sspwd")
check("surge vmess uuid", r4 and r4.nodes[2] and r4.nodes[2].uuid == "vm-uuid")
check("surge vmess net ws", r4 and r4.nodes[2] and r4.nodes[2].net == "ws")

-- ---------- QX 配置 ----------
local qx = [[
[server_local]
shadowsocks=10.0.0.1:8388, method=chacha20-ietf-poly1305, password=qxpwd, tag=QXSS
vmess=10.0.0.2:443, method=none, password=qx-uuid, obfs=ws, obfs-host=qx.example.com, obfs-uri=/qx, tls-verification=true, tag=QXVMess

[policy]
static=节点选择, QXSS, QXVMess, direct
]]
check("detect qx = surge", parser.detect(qx) == "surge")
local r5 = parser.parse(qx)
check("qx parses", r5 and r5.nodes ~= nil)
check("qx 2 nodes", r5 and #r5.nodes == 2)
check("qx ss pass", r5 and r5.nodes[1] and r5.nodes[1].password == "qxpwd")
check("qx vmess uuid", r5 and r5.nodes[2] and r5.nodes[2].uuid == "qx-uuid")
check("qx vmess net ws", r5 and r5.nodes[2] and r5.nodes[2].net == "ws")

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)