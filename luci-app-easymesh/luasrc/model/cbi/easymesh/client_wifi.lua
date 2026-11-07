-- luci-app-easymesh — Client WiFi tab
-- Copyright (C) 2026 Arafat Rahman Zami Mondol <zamimondol@gmail.com>

local m, o, t24, t5, tn
local uci = require "luci.model.uci".cursor()
local helpers = require "luci.model.cbi.easymesh.helpers"

m = Map("easymesh", translate("EasyMesh — Client WiFi"),
        translate("SSIDs broadcast by client nodes so end devices can join " ..
                  "the mesh. Use different SSIDs for 2.4 GHz and 5 GHz to " ..
                  "prevent sticky-client behaviour."))

helpers.attach_common_hooks(m, Map)

-- ─── Gate by enabled (read from UCI, since enabled lives on Settings) ───
local enabled = uci:get("easymesh", "config", "enabled") or "0"

if enabled ~= "1" then
    local notice = m:section(SimpleSection)
    notice.template = "easymesh/client_wifi_gate"
    return m
end

-- ─── 2.4 GHz ──────────────────────────────────────────────
t24 = m:section(TypedSection, "easymesh", translate("2.4 GHz"),
    translate("Longer range, lower speed."))
t24.anonymous = true

o = t24:option(Flag, "ap_enabled_2g", translate("Broadcast 2.4 GHz"))
o.default = "1"; o.rmempty = false

o = t24:option(Value, "ap_ssid_2g", translate("2.4 GHz SSID"))
o.default = "EasyMesh_WiFi"; o.datatype = "maxlength(32)"
o:depends("ap_enabled_2g", "1")

o = t24:option(ListValue, "ap_encryption_2g", translate("2.4 GHz security"))
o:value("none",      translate("None (open)"))
o:value("psk2+ccmp", translate("WPA2-PSK"))
o:value("sae",       translate("WPA3-SAE"))
o:value("sae-mixed", translate("WPA2/WPA3 transition"))
o.default = "sae-mixed"; o:depends("ap_enabled_2g", "1")

o = t24:option(Value, "ap_key_2g", translate("2.4 GHz password"))
o.default = "changeme123"; o.password = true
o:depends("ap_encryption_2g", "psk2+ccmp")
o:depends("ap_encryption_2g", "sae")
o:depends("ap_encryption_2g", "sae-mixed")

-- ─── 5 GHz ────────────────────────────────────────────────
t5 = m:section(TypedSection, "easymesh", translate("5 GHz"),
    translate("Shorter range, much faster."))
t5.anonymous = true

o = t5:option(Flag, "ap_enabled_5g", translate("Broadcast 5 GHz"))
o.default = "1"; o.rmempty = false

o = t5:option(Value, "ap_ssid_5g", translate("5 GHz SSID"))
o.default = "EasyMesh_WiFi_5G"; o.datatype = "maxlength(32)"
o:depends("ap_enabled_5g", "1")

o = t5:option(ListValue, "ap_encryption_5g", translate("5 GHz security"))
o:value("none",      translate("None (open)"))
o:value("psk2+ccmp", translate("WPA2-PSK"))
o:value("sae",       translate("WPA3-SAE"))
o:value("sae-mixed", translate("WPA2/WPA3 transition"))
o.default = "sae-mixed"; o:depends("ap_enabled_5g", "1")

o = t5:option(Value, "ap_key_5g", translate("5 GHz password"))
o.default = "changeme123"; o.password = true
o:depends("ap_encryption_5g", "psk2+ccmp")
o:depends("ap_encryption_5g", "sae")
o:depends("ap_encryption_5g", "sae-mixed")

-- ─── Shared ───────────────────────────────────────────────
tn = m:section(TypedSection, "easymesh", translate("Shared"))
tn.anonymous = true

o = tn:option(ListValue, "ap_network", translate("Attach client WiFi to network"))
o.default = "lan"
uci:foreach("network", "interface", function(sect)
    local name = sect['.name']
    if name then o:value(name, name) end
end)

return m
