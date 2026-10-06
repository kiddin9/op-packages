-- Copyright (C) 2021 dz <dingzhong110@gmail.com>
-- Copyright (C) 2026 Arafat Rahman Zami Mondol <zamimondol@gmail.com>
-- v2.8 — wired+wireless priority display, editable priority weights, mesh VLANs

local m, s, o
local sys = require "luci.sys"
local uci = require "luci.model.uci".cursor()

m = Map("easymesh", translate("EasyMesh"),
        translate("Configure a Batman-adv mesh network."))

function m.parse(self, ...)
    Map.parse(self, ...)
    local role = self:get("config", "role")
    local ap_mode = self:get("config", "ap_mode")
    if role == "server" and ap_mode == "1" then
        self:set("config", "ap_mode", "0")
    end
    local wired_if = self:get("config", "wired_if")
    local preferred = self:get("config", "preferred_wired_port")
    if (not wired_if or wired_if == "") and preferred and preferred ~= "" then
        self:set("config", "wired_if", preferred)
    elseif wired_if and wired_if ~= "" and (not preferred or preferred == "") then
        self:set("config", "preferred_wired_port", wired_if)
    end
end

function m.on_after_commit(self)
    luci.sys.call("/etc/init.d/easymesh restart >/tmp/easymesh-apply.log 2>&1 &")
end

-- =========================================================
-- Helpers
-- =========================================================
local function get_preferred_wired_port()
    local wired_if = uci:get("easymesh", "config", "wired_if")
    local preferred = uci:get("easymesh", "config", "preferred_wired_port")
    local pick = ""
    if wired_if and wired_if ~= "" then pick = wired_if
    elseif preferred and preferred ~= "" then pick = preferred end
    if pick ~= "" then
        local f = io.open("/sys/class/net/" .. pick, "r")
        if f then f:close(); return pick end
    end
    return ""
end

local function list_eth_ports()
    local ports, seen = {}, {}
    local fp = io.popen("ls /sys/class/net 2>/dev/null")
    if fp then
        for d in fp:lines() do
            if (d:match("^eth%d+$") or d:match("^lan%d+$")) and not seen[d] then
                seen[d] = true; table.insert(ports, d)
            end
        end
        fp:close()
    end
    uci:foreach("network", "device", function(sect)
        local n = sect['.name']
        if n and (n:match("^eth%d+$") or n:match("^lan%d+$")) and not seen[n] then
            seen[n] = true; table.insert(ports, n)
        end
    end)
    table.sort(ports)
    return ports
end

local function port_label(p)
    local f = io.open("/sys/class/net/" .. p .. "/brport/bridge", "r")
    if f then f:close(); return p .. "  (in bridge — will be removed on apply)" end
    return p .. "  (free)"
end

local function read_bytes(iface)
    local rx, tx = 0, 0
    local f = io.open("/sys/class/net/" .. iface .. "/statistics/rx_bytes", "r")
    if f then rx = tonumber(f:read("*l")) or 0; f:close() end
    f = io.open("/sys/class/net/" .. iface .. "/statistics/tx_bytes", "r")
    if f then tx = tonumber(f:read("*l")) or 0; f:close() end
    return rx, tx
end

local function human_rate(bps)
    if bps < 0 then bps = 0 end
    if bps < 1024 then return string.format("%d B/s", bps)
    elseif bps < 1048576 then return string.format("%.1f KB/s", bps / 1024)
    elseif bps < 1073741824 then return string.format("%.1f MB/s", bps / 1048576)
    else return string.format("%.2f GB/s", bps / 1073741824) end
end

local function read_override(iface)
    -- Try multiple batctl syntaxes — first one that returns a digit wins
    local cmds = {
        "batctl hardif " .. iface .. " throughput_override",
        "batctl hardif " .. iface .. " to",
        "batctl meshif bat0 hardif " .. iface .. " throughput_override",
    }
    for _, cmd in ipairs(cmds) do
        local fp = io.popen(cmd .. " 2>/dev/null")
        if fp then
            local val = fp:read("*l")
            fp:close()
            if val and val ~= "" and val:match("%d") then
                return val
            end
        end
    end
    return "?"
end

local function batman_ping(mac)
    if not mac or mac == "" or mac == "—" then return "—" end

    -- 30-second cache — page reloads within that window are instant
    local cachepath = "/tmp/easymesh-ping-" .. mac:gsub(":", "")
    local f = io.open(cachepath, "r")
    if f then
        local ts  = tonumber(f:read("*l") or "0")
        local val = f:read("*l") or "—"
        f:close()
        if ts and (os.time() - ts) < 30 then
            return val
        end
    end

    local fp = io.popen("batctl ping -c 2 -i 0.2 -t 1 " .. mac .. " 2>/dev/null")
    if not fp then return "—" end
    local min_ms = nil
    for line in fp:lines() do
        local t = line:match("time=([%d%.]+)")
        if t then
            local ms = tonumber(t)
            if ms and (not min_ms or ms < min_ms) then min_ms = ms end
        end
    end
    fp:close()
    local result = min_ms and string.format("%.1f ms", min_ms) or "—"

    local w = io.open(cachepath, "w")
    if w then w:write(os.time(), "\n", result, "\n"); w:close() end

    return result
end

-- =========================================================
-- Active hardifs + live bandwidth sampling (1s window)
-- =========================================================
local active_ifaces = {}
local afl = io.popen("batctl if 2>/dev/null")
if afl then
    for line in afl:lines() do
        local iface = line:match("^([^:]+):%s*active")
        if iface then table.insert(active_ifaces, iface) end
    end
    afl:close()
end

local s1, s2 = {}, {}
for _, iface in ipairs(active_ifaces) do
    local rx, tx = read_bytes(iface); s1[iface] = { rx = rx, tx = tx }
end
if #active_ifaces > 0 then
    os.execute("sleep 1")
    for _, iface in ipairs(active_ifaces) do
        local rx, tx = read_bytes(iface); s2[iface] = { rx = rx, tx = tx }
    end
end

local rates = {}
for _, iface in ipairs(active_ifaces) do
    rates[iface] = {
        rx = human_rate(s2[iface].rx - s1[iface].rx),
        tx = human_rate(s2[iface].tx - s1[iface].tx),
    }
end

-- =========================================================
-- Originators (for wired neighbor / last-seen)
-- =========================================================
local function parse_originators()
    local by_iface = {}
    local fp = io.popen("batctl o 2>/dev/null | tail -n +2")
    if not fp then return by_iface end
    for line in fp:lines() do
        local starred = line:match("^%s*%*") ~= nil
        local mac, seen = line:match("([0-9a-fA-F:]+)%s+(%d+%.%d+s)")
        local iface = line:match("%[%s*([%w%-_]+)%s*%]")
        if mac and iface then
            if not by_iface[iface] then by_iface[iface] = {} end
            table.insert(by_iface[iface], { mac = mac, seen = seen, starred = starred })
        end
    end
    fp:close()
    return by_iface
end

local originators = parse_originators()

-- =========================================================
-- Wireless peers table (with Priority column)
-- =========================================================
local function detect_nodes()
    local data = {}
    local fp = io.popen("batctl n 2>/dev/null | tail -n +2")
    if not fp then return data end
    for line in fp:lines() do
        local iface, neighbor, lastseen = line:match("^%s*(%S+)%s+(%S+)%s+(%S+)")
        if iface and neighbor and neighbor:match("^[0-9a-fA-F:]+$") then
            if iface:match("^phy") or iface:match("mesh") then
                table.insert(data, { IF = iface, Neighbor = neighbor, lastseen = lastseen })
            end
        end
    end
    fp:close()
    return data
end

local wireless_count = 0
local wired_count = 0
for _, iface in ipairs(active_ifaces) do
    if iface:match("^phy") or iface:match("mesh") then
        wireless_count = wireless_count + 1
    elseif iface:match("^eth") or iface:match("^lan") then
        wired_count = wired_count + 1
    end
end

local total_links = wireless_count + wired_count
local status_line
if wired_count > 0 then
    status_line = translate("Active mesh links") .. ": " .. total_links ..
                  " (" .. wireless_count .. " wireless + " .. wired_count .. " wired)"
else
    status_line = translate("Active mesh links") .. ": " .. wireless_count .. " (all wireless)"
end

local peers = detect_nodes()
for _, p in ipairs(peers) do
    -- Skip ping if lastseen > 30s → no timeout cost for stale entries
    local ls = tonumber((p.lastseen or ""):match("([%d%.]+)") or "9999")
    if ls and ls < 30 then
        p.Latency = batman_ping(p.Neighbor)
    else
        p.Latency = translate("stale")
    end
    p.Priority = read_override(p.IF)
    local r = rates[p.IF]
    if r then p.BW_RX = r.rx; p.BW_TX = r.tx
    else p.BW_RX = "—"; p.BW_TX = "—" end
end

local v = m:section(Table, peers, "", "<b>" .. status_line .. "</b>")
v:option(DummyValue, "IF",       translate("Interface"))
v:option(DummyValue, "Neighbor", translate("Neighbor MAC"))
v:option(DummyValue, "lastseen", translate("Last seen"))
v:option(DummyValue, "Latency",  translate("Latency"))
v:option(DummyValue, "BW_RX",    translate("RX rate"))
v:option(DummyValue, "BW_TX",    translate("TX rate"))
v:option(DummyValue, "Priority", translate("Priority weight"))

-- =========================================================
-- Wired backhaul details
-- =========================================================
local function detect_wired_details()
    local rows = {}
    local fp = io.popen("batctl if 2>/dev/null")
    if not fp then return rows end
    for line in fp:lines() do
        local iface, state = line:match("^([^:]+):%s*(%S+)")
        if iface and state == "active" and
           (iface:match("^eth%d+$") or iface:match("^lan%d+$")) then

            local carrier = "?"
            local cf = io.open("/sys/class/net/" .. iface .. "/carrier", "r")
            if cf then local val = cf:read("*l"); cf:close()
                carrier = (val == "1") and "yes" or "no" end

            local speed = "?"
            local sf = io.open("/sys/class/net/" .. iface .. "/speed", "r")
            if sf then local val = sf:read("*l"); sf:close()
                if val and val ~= "" and val ~= "-1" then speed = val .. " Mbps" end end

            local override = read_override(iface)

            local bridged = "no"
            local bf = io.open("/sys/class/net/" .. iface .. "/brport/bridge", "r")
            if bf then bf:close(); bridged = "yes" end

            local entries = originators[iface] or {}
            local best = nil
            for _, e in ipairs(entries) do
                if e.starred then best = e; break end
            end
            best = best or entries[1]
            local neighbor = best and best.mac or "—"
            local lastseen = best and best.seen or "—"

            local latency = batman_ping(neighbor)

            local r = rates[iface]
            table.insert(rows, {
                IF = iface, State = state, Cable = carrier, Speed = speed,
                Neighbor = neighbor, Lastseen = lastseen, Latency = latency,
                BW_RX = r and r.rx or "—", BW_TX = r and r.tx or "—",
                Override = override, Bridged = bridged,
            })
        end
    end
    fp:close()
    return rows
end

local wired_rows = detect_wired_details()
if #wired_rows > 0 then
    local wv = m:section(Table, wired_rows,
        "<b>" .. translate("Wired backhaul details") .. "</b>")
    wv:option(DummyValue, "IF",       translate("Interface"))
    wv:option(DummyValue, "State",    translate("State"))
    wv:option(DummyValue, "Cable",    translate("Cable"))
    wv:option(DummyValue, "Speed",    translate("Link speed"))
    wv:option(DummyValue, "Neighbor", translate("Neighbor MAC"))
    wv:option(DummyValue, "Lastseen", translate("Last seen"))
    wv:option(DummyValue, "Latency",  translate("Latency"))
    wv:option(DummyValue, "BW_RX",    translate("RX rate"))
    wv:option(DummyValue, "BW_TX",    translate("TX rate"))
    wv:option(DummyValue, "Override", translate("Priority weight"))
    wv:option(DummyValue, "Bridged",  translate("In LAN bridge"))
end

-- =========================================================
-- TOP: Preferred wired port
-- =========================================================
local wp = m:section(TypedSection, "easymesh", translate("Wired backhaul port"),
    translate("Convenience selector. Mirrors 'Wired backhaul interface' below. " ..
              "Presets that use wired backhaul will remove this port from the LAN bridge. " ..
              "Pick a port NOT used by your uplink or modem. " ..
              "Leave empty to disable wired backhaul entirely."))
wp.anonymous = true

o = wp:option(ListValue, "preferred_wired_port", translate("Preferred wired port"))
o:value("", translate("(none — wired presets will skip)"))
for _, p in ipairs(list_eth_ports()) do o:value(p, port_label(p)) end
o.default = ""
o.rmempty = false

-- =========================================================
-- Boot-time reliability (cron toggle)
-- =========================================================
local cf = m:section(TypedSection, "easymesh",
    translate("Boot-time reliability"),
    translate("The init script applies link priorities at boot and 90s later. " ..
              "On some hardware, mesh interfaces appear even later, leaving " ..
              "priority weight at 0. Enable cron fallback to reapply priority " ..
              "every minute. Safe (idempotent) but runs in the background. " ..
              "When disabled, the cron line is commented out in /etc/crontabs/root."))
cf.anonymous = true

o = cf:option(Flag, "cron_fallback", translate("Enable cron fallback"))
o.default = "0"
o.rmempty = false

-- =========================================================
-- Link priority weights (editable)
-- =========================================================
local lp = m:section(TypedSection, "easymesh",
    translate("Link priority weights"),
    translate("Batman-adv throughput_override values in Kbit/s. " ..
              "Higher = preferred. Set to 0 to let batman auto-decide per link. " ..
              "Defaults: wired=1000000, 6G=900000, 5G=600000, 2.4G=30000. " ..
              "Changes apply on next Save & Apply (or 'Reapply EasyMesh Settings')."))
lp.anonymous = true

o = lp:option(Value, "priority_wired", translate("Wired (Kbit/s)"))
o.default = "1000000"
o.datatype = "uinteger"
o.rmempty = false

o = lp:option(Value, "priority_6g", translate("6 GHz wireless (Kbit/s)"))
o.default = "900000"
o.datatype = "uinteger"
o.rmempty = false

o = lp:option(Value, "priority_5g", translate("5 GHz wireless (Kbit/s)"))
o.default = "600000"
o.datatype = "uinteger"
o.rmempty = false

o = lp:option(Value, "priority_24g", translate("2.4 GHz wireless (Kbit/s)"))
o.default = "30000"
o.datatype = "uinteger"
o.rmempty = false

-- =========================================================
-- Mesh VLANs (extend guest/IoT/hotspot over mesh)
-- =========================================================
local mv = m:section(TypedSection, "easymesh",
    translate("Mesh VLANs"),
    translate("Extend guest / IoT / hotspot networks across the mesh. " ..
              "Enter a comma-separated list of VLAN IDs (e.g. 10,20,30). " ..
              "The init script creates bat0.<vid> as an 8021q device for each ID. " ..
              "If a bridge named br-<vid>, br-lan<vid>, br-vlan<vid>, br-guest<vid>, " ..
              "or br-iot<vid> already exists, it is auto-added to that bridge. " ..
              "Otherwise, add the bat0.<vid> device manually in " ..
              "Network → Interfaces → Devices. " ..
              "Requires 802.1Q-capable switches on the physical wired backhaul."))
mv.anonymous = true

o = mv:option(Value, "mesh_vlans",
    translate("VLAN IDs (comma-separated)"),
    translate("Example: 10,20,30 — Leave empty to disable"))
o.default = ""
o.datatype = "maxlength(200)"
o.rmempty = false

-- =========================================================
-- QUICK SETUP — 19 presets
-- =========================================================
local q = m:section(TypedSection, "easymesh", translate("Quick Setup"),
    translate("Click a preset. A confirmation dialog will appear. " ..
              "Current config is backed up automatically before applying. " ..
              "Grouped by role: SERVER (has internet) → CLIENT (uses mesh) → NODE (relay only)."))
q.anonymous = true

local presets = {
    { id = "srv_5g", values = { enabled="1", role="server", band_mode="single_5g", encryption="0", kvr="1", ap_mode="0", ap_enabled_2g="1", ap_enabled_5g="1", ap_network="lan", wired_if="" }, label = translate("1. Server — 5 GHz wireless only"), desc = translate("[SERVER] Gateway. Extenders join via 5 GHz mesh only.") },
    { id = "srv_2g", values = { enabled="1", role="server", band_mode="single_2g", encryption="0", kvr="1", ap_mode="0", ap_enabled_2g="1", ap_enabled_5g="1", ap_network="lan", wired_if="" }, label = translate("2. Server — 2.4 GHz wireless only"), desc = translate("[SERVER] Extenders join via 2.4 GHz (longer range).") },
    { id = "srv_dual", values = { enabled="1", role="server", band_mode="dual", encryption="0", kvr="1", ap_mode="0", ap_enabled_2g="1", ap_enabled_5g="1", ap_network="lan", wired_if="" }, label = translate("3. Server — Dual-band wireless only"), desc = translate("[SERVER] Both radios carry backhaul.") },
    { id = "srv_wired", values = { enabled="1", role="server", band_mode="none", encryption="0", kvr="1", ap_mode="0", ap_enabled_2g="1", ap_enabled_5g="1", ap_network="lan", wired_if="AUTO_DETECT" }, label = translate("4. Server — Wired backhaul only"), desc = translate("[SERVER] No wireless mesh — extenders connect by cable.") },
    { id = "srv_5g_wired", values = { enabled="1", role="server", band_mode="single_5g_wired", encryption="0", kvr="1", ap_mode="0", ap_enabled_2g="1", ap_enabled_5g="1", ap_network="lan", wired_if="AUTO_DETECT" }, label = translate("5. Server — 5 GHz + Wired"), desc = translate("[SERVER] 5 GHz mesh primary, Ethernet parallel.") },
    { id = "srv_2g_wired", values = { enabled="1", role="server", band_mode="single_2g_wired", encryption="0", kvr="1", ap_mode="0", ap_enabled_2g="1", ap_enabled_5g="1", ap_network="lan", wired_if="AUTO_DETECT" }, label = translate("6. Server — 2.4 GHz + Wired"), desc = translate("[SERVER] 2.4 GHz mesh plus Ethernet.") },
    { id = "srv_dual_wired", values = { enabled="1", role="server", band_mode="dual_wired", encryption="0", kvr="1", ap_mode="0", ap_enabled_2g="1", ap_enabled_5g="1", ap_network="lan", wired_if="AUTO_DETECT" }, label = translate("7. Server — Dual-band + Wired"), desc = translate("[SERVER] Maximum redundancy. Both radios + Ethernet.") },

    { id = "cli_5g", values = { enabled="1", role="client", band_mode="single_5g", encryption="0", kvr="1", ap_mode="1", ip_mode="dhcp", ap_enabled_2g="1", ap_enabled_5g="1", ap_network="lan", wired_if="" }, label = translate("8. Client — 5 GHz wireless only"), desc = translate("[CLIENT] Extender via 5 GHz. No cable.") },
    { id = "cli_2g", values = { enabled="1", role="client", band_mode="single_2g", encryption="0", kvr="1", ap_mode="1", ip_mode="dhcp", ap_enabled_2g="1", ap_enabled_5g="1", ap_network="lan", wired_if="" }, label = translate("9. Client — 2.4 GHz wireless only"), desc = translate("[CLIENT] Extender via 2.4 GHz.") },
    { id = "cli_dual", values = { enabled="1", role="client", band_mode="dual", encryption="0", kvr="1", ap_mode="1", ip_mode="dhcp", ap_enabled_2g="1", ap_enabled_5g="1", ap_network="lan", wired_if="" }, label = translate("10. Client — Dual-band wireless only"), desc = translate("[CLIENT] Extender via both radios.") },
    { id = "cli_wired", values = { enabled="1", role="client", band_mode="none", encryption="0", kvr="1", ap_mode="1", ip_mode="dhcp", ap_enabled_2g="1", ap_enabled_5g="1", ap_network="lan", wired_if="AUTO_DETECT" }, label = translate("11. Client — Wired backhaul only"), desc = translate("[CLIENT] Cable only, no wireless mesh.") },
    { id = "cli_5g_wired", values = { enabled="1", role="client", band_mode="single_5g_wired", encryption="0", kvr="1", ap_mode="1", ip_mode="dhcp", ap_enabled_2g="1", ap_enabled_5g="1", ap_network="lan", wired_if="AUTO_DETECT" }, label = translate("12. Client — 5 GHz + Wired fallback"), desc = translate("[CLIENT] 5 GHz primary, Ethernet fallback.") },
    { id = "cli_2g_wired", values = { enabled="1", role="client", band_mode="single_2g_wired", encryption="0", kvr="1", ap_mode="1", ip_mode="dhcp", ap_enabled_2g="1", ap_enabled_5g="1", ap_network="lan", wired_if="AUTO_DETECT" }, label = translate("13. Client — 2.4 GHz + Wired fallback"), desc = translate("[CLIENT] 2.4 GHz primary, Ethernet fallback.") },
    { id = "cli_dual_wired", values = { enabled="1", role="client", band_mode="dual_wired", encryption="0", kvr="1", ap_mode="1", ip_mode="dhcp", ap_enabled_2g="1", ap_enabled_5g="1", ap_network="lan", wired_if="AUTO_DETECT" }, label = translate("14. Client — Dual-band + Wired fallback"), desc = translate("[CLIENT] Both radios + Ethernet. Maximum redundancy.") },

    { id = "node_5g", values = { enabled="1", role="node", band_mode="single_5g", encryption="0", kvr="1", ap_mode="0", ap_enabled_2g="0", ap_enabled_5g="0", wired_if="" }, label = translate("15. Node — 5 GHz relay"), desc = translate("[NODE] Relay only, 5 GHz. No client SSID.") },
    { id = "node_dual", values = { enabled="1", role="node", band_mode="dual", encryption="0", kvr="1", ap_mode="0", ap_enabled_2g="0", ap_enabled_5g="0", wired_if="" }, label = translate("16. Node — Dual-band relay"), desc = translate("[NODE] Relay only, both radios.") },
    { id = "node_wired", values = { enabled="1", role="node", band_mode="none", encryption="0", kvr="1", ap_mode="0", ap_enabled_2g="0", ap_enabled_5g="0", wired_if="AUTO_DETECT" }, label = translate("17. Node — Wired relay only"), desc = translate("[NODE] Relay via cable only. No wireless.") },

    { id = "revert_wired", values = {}, custom = "detach_wired", label = translate("18. Detach wired backhaul"), desc = translate("Removes Ethernet backhaul, restores port to bridge.") },
    { id = "disable", values = { enabled="0" }, label = translate("19. Disable mesh"), desc = translate("Turns off mesh. Radios stay enabled.") },
}

for _, p in ipairs(presets) do
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
                wired_port = get_preferred_wired_port()
                if wired_port == "" then
                    luci.sys.call("logger -t easymesh 'Preset needs wired but no port chosen — wired disabled'")
                end
            end
            for k, val in pairs(p.values) do
                if val ~= "AUTO_DETECT" then cur:set("easymesh", "config", k, val) end
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
        luci.http.redirect(luci.dispatcher.build_url("admin", "network", "easymesh"))
    end
end

-- =========================================================
-- MESH SETTINGS
-- =========================================================
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
        translate("Combined wireless band + wired backhaul. Wired variants use the port selected above."))
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
o.default = "EasyMesh_Dualband"; o.datatype = "maxlength(32)"; o:depends("enabled", "1")

o = s:option(Flag, "encryption", translate("Require password (WPA3-SAE)"))
o.default = "0"; o.rmempty = false; o:depends("enabled", "1")

o = s:option(Value, "key", translate("Mesh password"),
        translate("Must match on all nodes. Only used when 'Require password' is enabled."))
o.default = "changeme123"; o.password = true; o.rmempty = false; o:depends("encryption", "1")

o = s:option(Flag, "kvr", translate("Enable 802.11k/v/r fast roaming"))
o.default = "1"; o.rmempty = false; o:depends("enabled", "1")

o = s:option(Value, "mobility_domain", translate("Mobility domain"))
o.default = "4f57"; o.datatype = "and(hexstring,rangelength(4,4))"; o:depends("kvr", "1")

-- =========================================================
-- CLIENT WIFI — 2.4 GHz
-- =========================================================
local t24 = m:section(TypedSection, "easymesh", translate("Client WiFi — 2.4 GHz"),
    translate("Longer range, lower speed. Use a different SSID from 5 GHz."))
t24.anonymous = true

o = t24:option(Flag, "ap_enabled_2g", translate("Broadcast 2.4 GHz"))
o.default = "1"; o.rmempty = false; o:depends("enabled", "1")

o = t24:option(Value, "ap_ssid_2g", translate("2.4 GHz SSID"))
o.default = "EasyMesh_WiFi"; o.datatype = "maxlength(32)"; o:depends("ap_enabled_2g", "1")

o = t24:option(ListValue, "ap_encryption_2g", translate("2.4 GHz security"))
o:value("none", translate("None (open)"))
o:value("psk2+ccmp", translate("WPA2-PSK"))
o:value("sae", translate("WPA3-SAE"))
o:value("sae-mixed", translate("WPA2/WPA3 transition"))
o.default = "sae-mixed"; o:depends("ap_enabled_2g", "1")

o = t24:option(Value, "ap_key_2g", translate("2.4 GHz password"))
o.default = "changeme123"; o.password = true
o:depends("ap_encryption_2g", "psk2+ccmp")
o:depends("ap_encryption_2g", "sae")
o:depends("ap_encryption_2g", "sae-mixed")

-- =========================================================
-- CLIENT WIFI — 5 GHz
-- =========================================================
local t5 = m:section(TypedSection, "easymesh", translate("Client WiFi — 5 GHz"),
    translate("Shorter range, much faster. Use a different SSID from 2.4 GHz."))
t5.anonymous = true

o = t5:option(Flag, "ap_enabled_5g", translate("Broadcast 5 GHz"))
o.default = "1"; o.rmempty = false; o:depends("enabled", "1")

o = t5:option(Value, "ap_ssid_5g", translate("5 GHz SSID"))
o.default = "EasyMesh_WiFi_5G"; o.datatype = "maxlength(32)"; o:depends("ap_enabled_5g", "1")

o = t5:option(ListValue, "ap_encryption_5g", translate("5 GHz security"))
o:value("none", translate("None (open)"))
o:value("psk2+ccmp", translate("WPA2-PSK"))
o:value("sae", translate("WPA3-SAE"))
o:value("sae-mixed", translate("WPA2/WPA3 transition"))
o.default = "sae-mixed"; o:depends("ap_enabled_5g", "1")

o = t5:option(Value, "ap_key_5g", translate("5 GHz password"))
o.default = "changeme123"; o.password = true
o:depends("ap_encryption_5g", "psk2+ccmp")
o:depends("ap_encryption_5g", "sae")
o:depends("ap_encryption_5g", "sae-mixed")

local tn = m:section(TypedSection, "easymesh", translate("Client WiFi — shared"))
tn.anonymous = true
o = tn:option(ListValue, "ap_network", translate("Attach client WiFi to network"))
o.default = "lan"
uci:foreach("network", "interface", function(sect)
    local name = sect['.name']
    if name then o:value(name, name) end
end)
o:depends("enabled", "1")

-- =========================================================
-- AP MODE
-- =========================================================
local u = m:section(TypedSection, "easymesh", translate("AP Mode (Dumb AP)"))
u.anonymous = true

o = u:option(Flag, "ap_mode", translate("Enable AP Mode (Dumb AP)"))
o.default = "0"; o.rmempty = false
o:depends("role", "client"); o:depends("role", "node")

o = u:option(ListValue, "ip_mode", translate("IP mode"))
o:value("dhcp",   translate("DHCP (from Server)"))
o:value("static", translate("Static IP"))
o.default = "static"; o:depends("ap_mode", "1")

o = u:option(Value, "ipaddr", translate("IP address"))
o.default = "192.168.10.10"; o.datatype = "ip4addr"; o:depends("ip_mode", "static")
o = u:option(Value, "netmask", translate("Netmask"))
o.default = "255.255.255.0"; o.datatype = "ip4addr"; o:depends("ip_mode", "static")
o = u:option(Value, "gateway", translate("Gateway"))
o.default = "192.168.10.1"; o.datatype = "ip4addr"; o:depends("ip_mode", "static")
o = u:option(Value, "dns", translate("DNS server"))
o.default = "192.168.10.1"; o.datatype = "ip4addr"; o:depends("ip_mode", "static")

-- =========================================================
-- BOTTOM: Wired backhaul (source of truth)
-- =========================================================
local w = m:section(TypedSection, "easymesh", translate("Wired backhaul"),
    translate("Optional. Adds a physical Ethernet port as a batman hardif. " ..
              "Required on BOTH sides for a wired link. " ..
              "The port is auto-removed from the LAN bridge on apply."))
w.anonymous = true

o = w:option(ListValue, "wired_if", translate("Wired backhaul interface"))
o:value("", translate("Disabled"))
for _, p in ipairs(list_eth_ports()) do o:value(p, port_label(p)) end

-- =========================================================
-- Safety and actions
-- =========================================================
local a = m:section(TypedSection, "easymesh", translate("Safety and actions"))
a.anonymous = true

o = a:option(Flag, "safe_apply", translate("Safe apply (60-second rollback)"))
o.default = "0"; o.rmempty = false

local reapply = a:option(Button, "_reapply", translate("Reapply EasyMesh Settings"))
reapply.inputtitle = translate("Reapply EasyMesh Settings")
reapply.inputstyle = "apply"
function reapply.write(self, section)
    luci.sys.call("/etc/init.d/easymesh restart >/tmp/easymesh-reapply.log 2>&1")
    luci.http.redirect(luci.dispatcher.build_url("admin", "network", "easymesh"))
end

local restore = a:option(Button, "_restore", translate("Restore from last backup"))
restore.inputtitle = translate("Restore from last backup")
restore.inputstyle = "reset"
function restore.write(self, section)
    luci.sys.call("/etc/init.d/easymesh restore >/tmp/easymesh-restore.log 2>&1")
    luci.http.redirect(luci.dispatcher.build_url("admin", "network", "easymesh"))
end

local pairbtn = a:option(Button, "_pair", translate("Pair with another router"))
pairbtn.inputtitle = translate("Enter pairing mode (2 minutes)")
pairbtn.inputstyle = "apply"
pairbtn.description = translate("WPS-style pairing. Press the WPS button on both routers within 2 minutes. Auto-reverts on timeout.")
function pairbtn.write(self, section)
    luci.sys.call("/etc/init.d/easymesh pair >/tmp/easymesh-pair.log 2>&1 &")
    luci.http.redirect(luci.dispatcher.build_url("admin", "network", "easymesh"))
end

local confirm_section = m:section(SimpleSection)
confirm_section.template = "easymesh/preset_confirm"

return m
