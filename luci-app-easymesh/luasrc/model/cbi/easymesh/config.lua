-- luci-app-easymesh — Settings tab
-- Copyright (C) 2026 Arafat Rahman Zami Mondol <zamimondol@gmail.com>

local m, s, o
local helpers = require "luci.model.cbi.easymesh.helpers"
local uci     = require "luci.model.uci".cursor()

m = Map("easymesh", translate("EasyMesh — Settings"),
        translate("Mesh role, backhaul interface, link priorities and recovery."))

helpers.attach_common_hooks(m, Map)

-- Safety notice (compact)
local safety = m:section(SimpleSection)
safety.template = "easymesh/safety_notice"

-- ─── Mesh settings ────────────────────────────────────────
s = m:section(TypedSection, "easymesh", translate("Mesh settings"))
s.anonymous = true

o = s:option(Flag, "enabled", translate("Enable EasyMesh"))
o.default = "0"; o.rmempty = false

o = s:option(ListValue, "role", translate("Mesh role"))
o:value("off",    translate("Off"))
o:value("server", translate("Server (gateway - has internet)"))
o:value("client", translate("Client (uses mesh internet)"))
o:value("node",   translate("Node (relay only)"))
o.default = "off"; o.rmempty = false

o = s:option(ListValue, "band_mode", translate("Mesh mode"),
        translate("Combined wireless band + wired backhaul."))
o:value("single_5g",       translate("5 GHz wireless only"))
o:value("single_2g",       translate("2.4 GHz wireless only"))
o:value("dual",            translate("Dual-band wireless only"))
o:value("single_5g_wired", translate("5 GHz wireless + Wired backhaul"))
o:value("single_2g_wired", translate("2.4 GHz wireless + Wired backhaul"))
o:value("dual_wired",      translate("Dual-band wireless + Wired backhaul"))
o:value("none",            translate("Wired only (no wireless mesh)"))
o:value("custom",          translate("Custom radio"))
o.default = "single_5g"
o:depends("enabled", "1")

local apRadio = s:option(ListValue, "custom_radio", translate("Custom mesh radio"))
uci:foreach("wireless", "wifi-device", function(sect)
    local name = sect['.name']
    local band = sect.band or "?"
    local label = name .. " ("
    if band == "2g" then label = label .. "2.4 GHz"
    elseif band == "5g" then label = label .. "5 GHz"
    elseif band == "6g" then label = label .. "6 GHz"
    else label = label .. band end
    apRadio:value(name, label .. ")")
end)
apRadio:depends("band_mode", "custom")

o = s:option(Value, "mesh_id", translate("Mesh ID"),
        translate("Must match on all nodes. Ignored in wired-only mode."))
o.default = "EasyMesh_Dualband"; o.datatype = "maxlength(32)"
o:depends("enabled", "1")

o = s:option(Flag, "encryption", translate("Require password (WPA3-SAE)"))
o.default = "0"; o.rmempty = false; o:depends("enabled", "1")

o = s:option(Value, "key", translate("Mesh password"),
        translate("Must match on all nodes."))
o.default = "changeme123"; o.password = true; o.rmempty = false
o:depends("encryption", "1")

o = s:option(Flag, "kvr", translate("Enable 802.11k/v/r fast roaming"))
o.default = "1"; o.rmempty = false; o:depends("enabled", "1")

o = s:option(Value, "mobility_domain", translate("Mobility domain"))
o.default = "4f57"; o.datatype = "and(hexstring,rangelength(4,4))"
o:depends("kvr", "1")

-- ─── Wired backhaul (source of truth) ─────────────────────
local w = m:section(TypedSection, "easymesh", translate("Wired backhaul interface"),
    translate("Adds a physical Ethernet port as a batman hardif. Required on " ..
              "BOTH sides for a wired link. The port is auto-removed from the " ..
              "LAN bridge on apply."))
w.anonymous = true

o = w:option(ListValue, "wired_if", translate("Wired backhaul interface"))
o:value("", translate("Disabled"))
for _, p in ipairs(helpers.list_eth_ports()) do
    o:value(p, helpers.port_label(p))
end

-- ─── Link priority weights ────────────────────────────────
local lp = m:section(TypedSection, "easymesh", translate("Link priority weights"),
    translate("Batman-adv throughput_override values in Kbit/s. Higher = " ..
              "preferred. Set to 0 to let batman auto-decide per link. " ..
              "Defaults: wired=1000000, 6G=900000, 5G=600000, 2.4G=30000."))
lp.anonymous = true

o = lp:option(Value, "priority_wired", translate("Wired (Kbit/s)"))
o.default = "1000000"; o.datatype = "uinteger"; o.rmempty = false

o = lp:option(Value, "priority_6g", translate("6 GHz wireless (Kbit/s)"))
o.default = "900000"; o.datatype = "uinteger"; o.rmempty = false

o = lp:option(Value, "priority_5g", translate("5 GHz wireless (Kbit/s)"))
o.default = "600000"; o.datatype = "uinteger"; o.rmempty = false

o = lp:option(Value, "priority_24g", translate("2.4 GHz wireless (Kbit/s)"))
o.default = "30000"; o.datatype = "uinteger"; o.rmempty = false

-- ─── Boot-time reliability ────────────────────────────────
local cf = m:section(TypedSection, "easymesh", translate("Boot-time reliability"),
    translate("The init script applies link priorities at boot and 90s later. " ..
              "Enable cron fallback to reapply every minute on hardware where " ..
              "mesh interfaces appear late. Safe (idempotent)."))
cf.anonymous = true

o = cf:option(Flag, "cron_fallback", translate("Enable cron fallback"))
o.default = "0"; o.rmempty = false

-- ─── Safe Apply & Recovery Actions ────────────────────────────────
local a = m:section(TypedSection, "easymesh", translate("Safe Apply & Recovery Actions"),
    translate("Enable rollback before risky changes. Reapply or restore from " ..
              "the last automatic backup if something breaks."))
a.anonymous = true

o = a:option(Flag, "safe_apply", translate("Safe apply (60-second rollback)"))
o.default = "0"; o.rmempty = false

local reapply = a:option(Button, "_reapply", translate("Reapply EasyMesh Settings"))
reapply.inputtitle = translate("Reapply EasyMesh Settings")
reapply.inputstyle = "apply"
function reapply.write(self, section)
    luci.sys.call("/etc/init.d/easymesh restart >/tmp/easymesh-reapply.log 2>&1")
    luci.http.redirect(luci.dispatcher.build_url("admin", "network", "easymesh", "config"))
end

local restore = a:option(Button, "_restore", translate("Restore from last backup"))
restore.inputtitle = translate("Restore from last backup")
restore.inputstyle = "reset"
function restore.write(self, section)
    luci.sys.call("/etc/init.d/easymesh restore >/tmp/easymesh-restore.log 2>&1")
    luci.http.redirect(luci.dispatcher.build_url("admin", "network", "easymesh", "config"))
end

local pairbtn = a:option(Button, "_pair", translate("Pair with another router"))
pairbtn.inputtitle = translate("Enter pairing mode (2 minutes)")
pairbtn.inputstyle = "apply"
pairbtn.description = translate("WPS-style pairing. Press the WPS button on both " ..
                                "routers within 2 minutes. Auto-reverts on timeout.")
function pairbtn.write(self, section)
    luci.sys.call("/etc/init.d/easymesh pair >/tmp/easymesh-pair.log 2>&1 &")
    luci.http.redirect(luci.dispatcher.build_url("admin", "network", "easymesh", "config"))
end

return m
