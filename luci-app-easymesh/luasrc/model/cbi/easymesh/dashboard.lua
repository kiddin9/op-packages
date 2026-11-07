-- luci-app-easymesh — Dashboard tab
-- Copyright (C) 2026 Arafat Rahman Zami Mondol <zamimondol@gmail.com>

local m, v, wv
local helpers = require "luci.model.cbi.easymesh.helpers"

m = Map("easymesh", translate("EasyMesh — Dashboard"),
        translate("Live mesh status. Refreshes on every page load. " ..
                  "Bandwidth is sampled over 1 second; latency is cached for 30 seconds."))

-- ─── Wireless peers ───────────────────────────────────────
local active = helpers.active_ifaces()
local rates  = helpers.sample_rates(active)

local wireless_count, wired_count = 0, 0
for _, iface in ipairs(active) do
    if iface:match("^phy") or iface:match("^mesh") then
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

local peers = helpers.detect_nodes()
for _, p in ipairs(peers) do
    local ls = tonumber((p.lastseen or ""):match("([%d%.]+)") or "9999")
    if ls and ls < 30 then
        p.Latency = helpers.batman_ping(p.Neighbor)
    else
        p.Latency = translate("stale")
    end
    p.Priority = helpers.read_override(p.IF)
    local r = rates[p.IF]
    if r then p.BW_RX = r.rx; p.BW_TX = r.tx
    else p.BW_RX = "—"; p.BW_TX = "—" end
end

v = m:section(Table, peers, "<b>" .. status_line .. "</b>")
v:option(DummyValue, "IF",       translate("Interface"))
v:option(DummyValue, "Neighbor", translate("Neighbor MAC"))
v:option(DummyValue, "lastseen", translate("Last seen"))
v:option(DummyValue, "Latency",  translate("Latency"))
v:option(DummyValue, "BW_RX",    translate("RX rate"))
v:option(DummyValue, "BW_TX",    translate("TX rate"))
v:option(DummyValue, "Priority", translate("Priority weight"))

-- ─── Wired backhaul details ───────────────────────────────
local originators = helpers.parse_originators()

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

            local override = helpers.read_override(iface)

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
            local latency  = helpers.batman_ping(neighbor)
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
    wv = m:section(Table, wired_rows,
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

return m
