-- luci-app-easymesh — shared helper functions
-- Copyright (C) 2026 Arafat Rahman Zami Mondol <zamimondol@gmail.com>
--
-- Extracted from the original monolithic easymesh.lua. These functions are
-- used by the tabbed CBI views (config, quick_setup, vlans, topology, profiles).
-- None of them write config — they only read state or run batctl/io commands.

local M = {}

local uci = require "luci.model.uci".cursor()

-- ─────────────────────────────────────────────────────────
-- Wired port helpers
-- ─────────────────────────────────────────────────────────

function M.get_preferred_wired_port()
    local wired_if  = uci:get("easymesh", "config", "wired_if")
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

function M.list_eth_ports()
    local ports, seen = {}, {}
    local fp = io.popen("ls /sys/class/net 2>/dev/null")
    if fp then
        for d in fp:lines() do
            if (d:match("^eth%d+$") or d:match("^lan%d+$")) and not seen[d] then
                seen[d] = true
                table.insert(ports, d)
            end
        end
        fp:close()
    end
    uci:foreach("network", "device", function(sect)
        local n = sect['.name']
        if n and (n:match("^eth%d+$") or n:match("^lan%d+$")) and not seen[n] then
            seen[n] = true
            table.insert(ports, n)
        end
    end)
    table.sort(ports)
    return ports
end

function M.port_label(p)
    local f = io.open("/sys/class/net/" .. p .. "/brport/bridge", "r")
    if f then f:close(); return p .. "  (in bridge — will be removed on apply)" end
    return p .. "  (free)"
end

-- ─────────────────────────────────────────────────────────
-- Byte / rate helpers
-- ─────────────────────────────────────────────────────────

function M.read_bytes(iface)
    local rx, tx = 0, 0
    local f = io.open("/sys/class/net/" .. iface .. "/statistics/rx_bytes", "r")
    if f then rx = tonumber(f:read("*l")) or 0; f:close() end
    f = io.open("/sys/class/net/" .. iface .. "/statistics/tx_bytes", "r")
    if f then tx = tonumber(f:read("*l")) or 0; f:close() end
    return rx, tx
end

function M.human_rate(bps)
    if bps < 0 then bps = 0 end
    if bps < 1024 then return string.format("%d B/s", bps)
    elseif bps < 1048576 then return string.format("%.1f KB/s", bps / 1024)
    elseif bps < 1073741824 then return string.format("%.1f MB/s", bps / 1048576)
    else return string.format("%.2f GB/s", bps / 1073741824) end
end

-- ─────────────────────────────────────────────────────────
-- batctl helpers
-- ─────────────────────────────────────────────────────────

function M.read_override(iface)
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

function M.batman_ping(mac)
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

-- ─────────────────────────────────────────────────────────
-- Active hardifs + bandwidth sampling
-- ─────────────────────────────────────────────────────────

function M.active_ifaces()
    local ifaces = {}
    local fp = io.popen("batctl if 2>/dev/null")
    if fp then
        for line in fp:lines() do
            local iface = line:match("^([^:]+):%s*active")
            if iface then table.insert(ifaces, iface) end
        end
        fp:close()
    end
    return ifaces
end

function M.sample_rates(active_ifaces)
    local s1, s2 = {}, {}
    for _, iface in ipairs(active_ifaces) do
        local rx, tx = M.read_bytes(iface); s1[iface] = { rx = rx, tx = tx }
    end
    if #active_ifaces > 0 then
        os.execute("sleep 1")
        for _, iface in ipairs(active_ifaces) do
            local rx, tx = M.read_bytes(iface); s2[iface] = { rx = rx, tx = tx }
        end
    end
    local rates = {}
    for _, iface in ipairs(active_ifaces) do
        rates[iface] = {
            rx = M.human_rate(s2[iface].rx - s1[iface].rx),
            tx = M.human_rate(s2[iface].tx - s1[iface].tx),
        }
    end
    return rates
end

-- ─────────────────────────────────────────────────────────
-- Originators (for wired neighbor / last-seen)
-- ─────────────────────────────────────────────────────────

function M.parse_originators()
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

-- ─────────────────────────────────────────────────────────
-- Wireless peer detection
-- ─────────────────────────────────────────────────────────

function M.detect_nodes()
    local data = {}
    local fp = io.popen("batctl n 2>/dev/null | tail -n +2")
    if not fp then return data end
    for line in fp:lines() do
        local iface, neighbor, lastseen = line:match("^%s*(%S+)%s+(%S+)%s+(%S+)")
        if iface and neighbor and neighbor:match("^[0-9a-fA-F:]+$") then
            if iface:match("^phy") or iface:match("^mesh") then
                table.insert(data, { IF = iface, Neighbor = neighbor, lastseen = lastseen })
            end
        end
    end
    fp:close()
    return data
end


-- ─────────────────────────────────────────────────────────
-- Common CBI hooks — call from every tab that saves config
-- ─────────────────────────────────────────────────────────

function M.attach_common_hooks(m, MapClass)
    local sys = require "luci.sys"

    function m.parse(self, ...)
        MapClass.parse(self, ...)
        local role     = self:get("config", "role")
        local ap_mode  = self:get("config", "ap_mode")
        if role == "server" and ap_mode == "1" then
            self:set("config", "ap_mode", "0")
        end
        local wired_if  = self:get("config", "wired_if")
        local preferred = self:get("config", "preferred_wired_port")
        if (not wired_if or wired_if == "") and preferred and preferred ~= "" then
            self:set("config", "wired_if", preferred)
        elseif wired_if and wired_if ~= "" and (not preferred or preferred == "") then
            self:set("config", "preferred_wired_port", wired_if)
        end
    end

    function m.on_after_commit(self)
        sys.call("/etc/init.d/easymesh restart >/tmp/easymesh-apply.log 2>&1 &")
    end
end

return M
