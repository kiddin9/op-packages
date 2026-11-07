-- luci-app-easymesh — Quick Setup tab
-- Copyright (C) 2026 Arafat Rahman Zami Mondol <zamimondol@gmail.com>

local m, o
local helpers = require "luci.model.cbi.easymesh.helpers"

m = Map("easymesh", translate("EasyMesh — Quick Setup"),
        translate("Pick a preset for your router's role. Current config is " ..
                  "backed up automatically before applying."))

helpers.attach_common_hooks(m, Map)

-- ─── Wired backhaul port (convenience selector) ───────────
local wp = m:section(TypedSection, "easymesh", translate("Wired backhaul port"),
    translate("Presets with wired backhaul will remove this port from the LAN " ..
              "bridge. Pick a port NOT used by your uplink or modem. " ..
              "Leave empty to disable wired backhaul entirely."))
wp.anonymous = true

o = wp:option(ListValue, "preferred_wired_port", translate("Preferred wired port"))
o:value("", translate("(none — wired presets will skip)"))
for _, p in ipairs(helpers.list_eth_ports()) do
    o:value(p, helpers.port_label(p))
end
o.default = ""
o.rmempty = false

-- ─── Preset definitions ───────────────────────────────────
local presets = {
    { id = "srv_5g", group = "srv", values = { enabled="1", role="server", band_mode="single_5g", encryption="0", kvr="1", ap_mode="0", ap_enabled_2g="1", ap_enabled_5g="1", ap_network="lan", wired_if="" }, label = translate("1. Server — 5 GHz wireless only"), desc = translate("[SERVER] Gateway. Extenders join via 5 GHz mesh only.") },
    { id = "srv_2g", group = "srv", values = { enabled="1", role="server", band_mode="single_2g", encryption="0", kvr="1", ap_mode="0", ap_enabled_2g="1", ap_enabled_5g="1", ap_network="lan", wired_if="" }, label = translate("2. Server — 2.4 GHz wireless only"), desc = translate("[SERVER] Extenders join via 2.4 GHz (longer range).") },
    { id = "srv_dual", group = "srv", values = { enabled="1", role="server", band_mode="dual", encryption="0", kvr="1", ap_mode="0", ap_enabled_2g="1", ap_enabled_5g="1", ap_network="lan", wired_if="" }, label = translate("3. Server — Dual-band wireless only"), desc = translate("[SERVER] Both radios carry backhaul.") },
    { id = "srv_wired", group = "srv", values = { enabled="1", role="server", band_mode="none", encryption="0", kvr="1", ap_mode="0", ap_enabled_2g="1", ap_enabled_5g="1", ap_network="lan", wired_if="AUTO_DETECT" }, label = translate("4. Server — Wired backhaul only"), desc = translate("[SERVER] No wireless mesh — extenders connect by cable.") },
    { id = "srv_5g_wired", group = "srv", values = { enabled="1", role="server", band_mode="single_5g_wired", encryption="0", kvr="1", ap_mode="0", ap_enabled_2g="1", ap_enabled_5g="1", ap_network="lan", wired_if="AUTO_DETECT" }, label = translate("5. Server — 5 GHz + Wired"), desc = translate("[SERVER] 5 GHz mesh primary, Ethernet parallel.") },
    { id = "srv_2g_wired", group = "srv", values = { enabled="1", role="server", band_mode="single_2g_wired", encryption="0", kvr="1", ap_mode="0", ap_enabled_2g="1", ap_enabled_5g="1", ap_network="lan", wired_if="AUTO_DETECT" }, label = translate("6. Server — 2.4 GHz + Wired"), desc = translate("[SERVER] 2.4 GHz mesh plus Ethernet.") },
    { id = "srv_dual_wired", group = "srv", values = { enabled="1", role="server", band_mode="dual_wired", encryption="0", kvr="1", ap_mode="0", ap_enabled_2g="1", ap_enabled_5g="1", ap_network="lan", wired_if="AUTO_DETECT" }, label = translate("7. Server — Dual-band + Wired"), desc = translate("[SERVER] Maximum redundancy. Both radios + Ethernet.") },

    { id = "cli_5g", group = "cli", values = { enabled="1", role="client", band_mode="single_5g", encryption="0", kvr="1", ap_mode="1", ip_mode="dhcp", ap_enabled_2g="1", ap_enabled_5g="1", ap_network="lan", wired_if="" }, label = translate("8. Client — 5 GHz wireless only"), desc = translate("[CLIENT] Extender via 5 GHz. No cable.") },
    { id = "cli_2g", group = "cli", values = { enabled="1", role="client", band_mode="single_2g", encryption="0", kvr="1", ap_mode="1", ip_mode="dhcp", ap_enabled_2g="1", ap_enabled_5g="1", ap_network="lan", wired_if="" }, label = translate("9. Client — 2.4 GHz wireless only"), desc = translate("[CLIENT] Extender via 2.4 GHz.") },
    { id = "cli_dual", group = "cli", values = { enabled="1", role="client", band_mode="dual", encryption="0", kvr="1", ap_mode="1", ip_mode="dhcp", ap_enabled_2g="1", ap_enabled_5g="1", ap_network="lan", wired_if="" }, label = translate("10. Client — Dual-band wireless only"), desc = translate("[CLIENT] Extender via both radios.") },
    { id = "cli_wired", group = "cli", values = { enabled="1", role="client", band_mode="none", encryption="0", kvr="1", ap_mode="1", ip_mode="dhcp", ap_enabled_2g="1", ap_enabled_5g="1", ap_network="lan", wired_if="AUTO_DETECT" }, label = translate("11. Client — Wired backhaul only"), desc = translate("[CLIENT] Cable only, no wireless mesh.") },
    { id = "cli_5g_wired", group = "cli", values = { enabled="1", role="client", band_mode="single_5g_wired", encryption="0", kvr="1", ap_mode="1", ip_mode="dhcp", ap_enabled_2g="1", ap_enabled_5g="1", ap_network="lan", wired_if="AUTO_DETECT" }, label = translate("12. Client — 5 GHz + Wired fallback"), desc = translate("[CLIENT] 5 GHz primary, Ethernet fallback.") },
    { id = "cli_2g_wired", group = "cli", values = { enabled="1", role="client", band_mode="single_2g_wired", encryption="0", kvr="1", ap_mode="1", ip_mode="dhcp", ap_enabled_2g="1", ap_enabled_5g="1", ap_network="lan", wired_if="AUTO_DETECT" }, label = translate("13. Client — 2.4 GHz + Wired fallback"), desc = translate("[CLIENT] 2.4 GHz primary, Ethernet fallback.") },
    { id = "cli_dual_wired", group = "cli", values = { enabled="1", role="client", band_mode="dual_wired", encryption="0", kvr="1", ap_mode="1", ip_mode="dhcp", ap_enabled_2g="1", ap_enabled_5g="1", ap_network="lan", wired_if="AUTO_DETECT" }, label = translate("14. Client — Dual-band + Wired fallback"), desc = translate("[CLIENT] Both radios + Ethernet. Maximum redundancy.") },

    { id = "node_5g", group = "node", values = { enabled="1", role="node", band_mode="single_5g", encryption="0", kvr="1", ap_mode="0", ap_enabled_2g="0", ap_enabled_5g="0", wired_if="" }, label = translate("15. Node — 5 GHz relay"), desc = translate("[NODE] Relay only, 5 GHz. No client SSID.") },
    { id = "node_dual", group = "node", values = { enabled="1", role="node", band_mode="dual", encryption="0", kvr="1", ap_mode="0", ap_enabled_2g="0", ap_enabled_5g="0", wired_if="" }, label = translate("16. Node — Dual-band relay"), desc = translate("[NODE] Relay only, both radios.") },
    { id = "node_wired", group = "node", values = { enabled="1", role="node", band_mode="none", encryption="0", kvr="1", ap_mode="0", ap_enabled_2g="0", ap_enabled_5g="0", wired_if="AUTO_DETECT" }, label = translate("17. Node — Wired relay only"), desc = translate("[NODE] Relay via cable only. No wireless.") },

    { id = "revert_wired", group = "recover", values = {}, custom = "detach_wired", label = translate("18. Detach wired backhaul"), desc = translate("Removes Ethernet backhaul, restores port to bridge.") },
    { id = "disable", group = "disable", values = { enabled="0" }, label = translate("19. Disable mesh"), desc = translate("Turns off mesh. Radios stay enabled.") },
}

local group_headers = {
    srv     = translate("SERVER presets — has internet (1–7)"),
    cli     = translate("CLIENT presets — uses mesh internet (8–14)"),
    node    = translate("NODE presets — relay only (15–17)"),
    recover = translate("Recovery — detach wired backhaul (18)"),
    disable = translate("Disable — turn off mesh (19)"),
}

-- ─── Render grouped preset buttons ────────────────────────
local group_order = { "srv", "cli", "node", "recover", "disable" }
for _, grp in ipairs(group_order) do
    local gh = m:section(SimpleSection)
    gh.template = "easymesh/group_header"
    gh.data = group_headers[grp]

    for _, p in ipairs(presets) do
        if p.group == grp then
            local q = m:section(TypedSection, "easymesh")
            q.anonymous = true
            local btn = q:option(Button, "_preset_" .. p.id, p.label)
            btn.inputstyle = "apply"
            btn.description = p.desc

            function btn.write(self, section)
                luci.sys.call("/etc/init.d/easymesh backup >/tmp/easymesh-preset.log 2>&1")

                if p.custom == "detach_wired" then
                    luci.sys.call("/etc/init.d/easymesh detach_wired >>/tmp/easymesh-preset.log 2>&1")
                else
                    local cur = luci.model.uci.cursor()
                    local needs_wired = false
                    for _, val in pairs(p.values) do
                        if val == "AUTO_DETECT" then needs_wired = true; break end
                    end
                    local wired_port = ""
                    if needs_wired then
                        wired_port = helpers.get_preferred_wired_port()
                        if wired_port == "" then
                            luci.sys.call("logger -t easymesh 'Preset needs wired but no port chosen — wired disabled'")
                        end
                    end
                    for k, val in pairs(p.values) do
                        if val ~= "AUTO_DETECT" then
                            cur:set("easymesh", "config", k, val)
                        end
                    end
                    cur:set("easymesh", "config", "wired_if", wired_port)
                    cur:set("easymesh", "config", "preferred_wired_port", wired_port)
                    if needs_wired and wired_port == "" then
                        local bm = p.values.band_mode or "single_5g"
                        bm = tostring(bm):gsub("_wired$", "")
                        cur:set("easymesh", "config", "band_mode", bm)
                    end
                    cur:commit("easymesh")
                    luci.sys.call("/etc/init.d/easymesh restart >>/tmp/easymesh-preset.log 2>&1")
                end
                luci.http.redirect(luci.dispatcher.build_url("admin", "network", "easymesh", "quick"))
            end
        end
    end
end

-- Confirmation-dialog template
local confirm_section = m:section(SimpleSection)
confirm_section.template = "easymesh/preset_confirm"

return m
