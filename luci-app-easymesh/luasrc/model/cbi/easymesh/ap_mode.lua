-- luci-app-easymesh — AP Mode tab
-- Copyright (C) 2026 Arafat Rahman Zami Mondol <zamimondol@gmail.com>

local m, u, o
local uci = require "luci.model.uci".cursor()
local helpers = require "luci.model.cbi.easymesh.helpers"

m = Map("easymesh", translate("EasyMesh — AP Mode (Dumb AP)"),
        translate("A Dumb AP broadcasts the client WiFi network without running " ..
                  "its own DHCP or firewall. Use this on satellite nodes so " ..
                  "clients on any node get an IP from the master server."))

helpers.attach_common_hooks(m, Map)

-- ─── Gate by role (read from UCI, since role lives on the Settings tab) ───
local role = uci:get("easymesh", "config", "role") or "off"

if role ~= "client" and role ~= "node" then
    local notice = m:section(SimpleSection)
    notice.template = "easymesh/ap_mode_gate"
    notice.data = {
        role = role,
    }
    return m
end

-- ─── AP Mode configuration (client + node only) ───────────
u = m:section(TypedSection, "easymesh", translate("AP Mode"))
u.anonymous = true

o = u:option(Flag, "ap_mode", translate("Enable AP Mode (Dumb AP)"))
o.default = "0"; o.rmempty = false

o = u:option(ListValue, "ip_mode", translate("IP mode"))
o:value("dhcp",   translate("DHCP (from Server)"))
o:value("static", translate("Static IP"))
o.default = "static"; o:depends("ap_mode", "1")

o = u:option(Value, "ipaddr", translate("IP address"))
o.default = "192.168.10.10"; o.datatype = "ip4addr"
o:depends("ip_mode", "static")

o = u:option(Value, "netmask", translate("Netmask"))
o.default = "255.255.255.0"; o.datatype = "ip4addr"
o:depends("ip_mode", "static")

o = u:option(Value, "gateway", translate("Gateway"))
o.default = "192.168.10.1"; o.datatype = "ip4addr"
o:depends("ip_mode", "static")

o = u:option(Value, "dns", translate("DNS server"))
o.default = "192.168.10.1"; o.datatype = "ip4addr"
o:depends("ip_mode", "static")

return m
