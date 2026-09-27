-- parser_json_config_test.lua — JSON 配置解析单元测试
-- 用法：lua5.1 tests/parser_json_config_test.lua

package.path = "./root/usr/share/?.lua;" .. package.path

local json_parser = require("substore.parser_json_config")

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

-- ---------- Sing-box JSON 解析 ----------
local singbox_json = [[
{
  "outbounds": [
    {
      "tag": "vmess-out",
      "type": "vmess",
      "server": "1.1.1.1",
      "server_port": 443,
      "uuid": "abc-123-def",
      "security": "tls",
      "alter_id": 0,
      "tls": {
        "server_name": "example.com"
      }
    },
    {
      "tag": "vless-out",
      "type": "vless",
      "server": "2.2.2.2",
      "server_port": 443,
      "uuid": "vless-uuid-123",
      "flow": "xtls-rprx-vision",
      "tls": {
        "server_name": "example.org"
      }
    },
    {
      "tag": "trojan-out",
      "type": "trojan",
      "server": "3.3.3.3",
      "server_port": 443,
      "password": "trojan-pass",
      "tls": {
        "server_name": "trojan.example.com"
      }
    },
    {
      "tag": "ss-out",
      "type": "shadowsocks",
      "server": "4.4.4.4",
      "server_port": 8388,
      "method": "aes-256-gcm",
      "password": "ss-pass"
    }
  ]
}
]]

local singbox_nodes = json_parser.parse_singbox_json(singbox_json)
check("singbox parse result exists", singbox_nodes ~= nil)
check("singbox node count", singbox_nodes and #singbox_nodes == 4)

if singbox_nodes and #singbox_nodes >= 1 then
	local n1 = singbox_nodes[1]
	check("singbox vmess name", n1.name == "vmess-out")
	check("singbox vmess proto", n1.proto == "vmess")
	check("singbox vmess server", n1.server == "1.1.1.1")
	check("singbox vmess port", n1.port == 443)
	check("singbox vmess uuid", n1.uuid == "abc-123-def")
	check("singbox vmess security", n1.security == "tls")
	check("singbox vmess sni", n1.sni == "example.com")
end

if singbox_nodes and #singbox_nodes >= 2 then
	local n2 = singbox_nodes[2]
	check("singbox vless name", n2.name == "vless-out")
	check("singbox vless proto", n2.proto == "vless")
	check("singbox vless server", n2.server == "2.2.2.2")
	check("singbox vless port", n2.port == 443)
	check("singbox vless uuid", n2.uuid == "vless-uuid-123")
end

if singbox_nodes and #singbox_nodes >= 3 then
	local n3 = singbox_nodes[3]
	check("singbox trojan name", n3.name == "trojan-out")
	check("singbox trojan proto", n3.proto == "trojan")
	check("singbox trojan server", n3.server == "3.3.3.3")
	check("singbox trojan port", n3.port == 443)
	check("singbox trojan password", n3.password == "trojan-pass")
end

if singbox_nodes and #singbox_nodes >= 4 then
	local n4 = singbox_nodes[4]
	check("singbox ss name", n4.name == "ss-out")
	check("singbox ss proto", n4.proto == "shadowsocks")
	check("singbox ss server", n4.server == "4.4.4.4")
	check("singbox ss port", n4.port == 8388)
	check("singbox ss method", n4.method == "aes-256-gcm")
	check("singbox ss password", n4.password == "ss-pass")
end

-- ---------- V2Ray JSON 解析 ----------
local v2ray_json = [[
{
  "outbounds": [
    {
      "tag": "vmess-out",
      "protocol": "vmess",
      "settings": {
        "vnext": [
          {
            "address": "5.5.5.5",
            "port": 443,
            "users": [
              {
                "id": "v2ray-vmess-uuid",
                "alterId": 0,
                "security": "auto"
              }
            ]
          }
        ]
      },
      "streamSettings": {
        "network": "ws",
        "security": "tls",
        "tlsSettings": {
          "serverName": "v2ray.example.com"
        }
      }
    },
    {
      "tag": "vless-out",
      "protocol": "vless",
      "settings": {
        "vnext": [
          {
            "address": "6.6.6.6",
            "port": 443,
            "users": [
              {
                "id": "v2ray-vless-uuid",
                "flow": "xtls-rprx-vision"
              }
            ]
          }
        ]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "serverName": "reality.example.com"
        }
      }
    }
  ]
}
]]

local v2ray_nodes = json_parser.parse_v2ray_json(v2ray_json)
check("v2ray parse result exists", v2ray_nodes ~= nil)
check("v2ray node count", v2ray_nodes and #v2ray_nodes == 2)

if v2ray_nodes and #v2ray_nodes >= 1 then
	local n1 = v2ray_nodes[1]
	check("v2ray vmess name", n1.name == "vmess-out")
	check("v2ray vmess proto", n1.proto == "vmess")
	check("v2ray vmess server", n1.server == "5.5.5.5")
	check("v2ray vmess port", n1.port == 443)
	check("v2ray vmess uuid", n1.uuid == "v2ray-vmess-uuid")
	check("v2ray vmess net", n1.net == "ws")
end

if v2ray_nodes and #v2ray_nodes >= 2 then
	local n2 = v2ray_nodes[2]
	check("v2ray vless name", n2.name == "vless-out")
	check("v2ray vless proto", n2.proto == "vless")
	check("v2ray vless server", n2.server == "6.6.6.6")
	check("v2ray vless port", n2.port == 443)
	check("v2ray vless uuid", n2.uuid == "v2ray-vless-uuid")
end

-- ---------- Clash JSON 解析 ----------
local clash_json = [[
{
  "proxies": [
    {
      "name": "ClashVMess",
      "type": "vmess",
      "server": "7.7.7.7",
      "port": 443,
      "uuid": "clash-vmess-uuid",
      "alterId": 0,
      "cipher": "auto",
      "network": "ws",
      "ws-opts": {
        "path": "/ws"
      }
    },
    {
      "name": "ClashVLESS",
      "type": "vless",
      "server": "8.8.8.8",
      "port": 443,
      "uuid": "clash-vless-uuid",
      "network": "tcp"
    },
    {
      "name": "ClashTrojan",
      "type": "trojan",
      "server": "9.9.9.9",
      "port": 443,
      "password": "clash-trojan-pass",
      "sni": "clash.example.com"
    }
  ]
}
]]

local clash_nodes = json_parser.parse_clash_json(clash_json)
check("clash parse result exists", clash_nodes ~= nil)
check("clash node count", clash_nodes and #clash_nodes == 3)

if clash_nodes and #clash_nodes >= 1 then
	local n1 = clash_nodes[1]
	check("clash vmess name", n1.name == "ClashVMess")
	check("clash vmess proto", n1.proto == "vmess")
	check("clash vmess server", n1.server == "7.7.7.7")
	check("clash vmess port", n1.port == 443)
	check("clash vmess uuid", n1.uuid == "clash-vmess-uuid")
	check("clash vmess net", n1.net == "ws")
end

if clash_nodes and #clash_nodes >= 2 then
	local n2 = clash_nodes[2]
	check("clash vless name", n2.name == "ClashVLESS")
	check("clash vless proto", n2.proto == "vless")
	check("clash vless server", n2.server == "8.8.8.8")
	check("clash vless port", n2.port == 443)
	check("clash vless uuid", n2.uuid == "clash-vless-uuid")
end

if clash_nodes and #clash_nodes >= 3 then
	local n3 = clash_nodes[3]
	check("clash trojan name", n3.name == "ClashTrojan")
	check("clash trojan proto", n3.proto == "trojan")
	check("clash trojan server", n3.server == "9.9.9.9")
	check("clash trojan port", n3.port == 443)
	check("clash trojan password", n3.password == "clash-trojan-pass")
	check("clash trojan sni", n3.sni == "clash.example.com")
end

-- ---------- 结果 ----------
print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
