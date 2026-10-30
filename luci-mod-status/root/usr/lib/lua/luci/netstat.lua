-- Shared helpers for luci-app-netstat.
--
-- Everything here relies only on what every OpenWrt router has: the vnStat 2
-- CLI, procfs/sysfs and netifd over ubus. There are no board-specific
-- interface names or device paths; the uplink is found from the routing
-- table and history comes from whatever vnStat has in its database.

local nixio = require "nixio"
local fs    = require "nixio.fs"
local util  = require "luci.util"
local jsonc = require "luci.jsonc"
local uci   = require "luci.model.uci"

local M = {}

M.VNSTAT = "/usr/bin/vnstat"

-- Netdev and logical interface names are used in shell commands, so only
-- allow the characters Linux and netifd actually use.
function M.safe_name(name)
    return type(name) == "string" and name ~= "" and name:match("^[%w%-%._]+$") ~= nil
end

function M.netdev_exists(name)
    return M.safe_name(name) and fs.access("/sys/class/net/" .. name) and true or false
end

function M.vnstat_installed()
    return fs.access(M.VNSTAT, "x") and true or false
end

-- Interfaces present in the vnStat database, one per line from
-- "vnstat --dbiflist 1". Returns a sorted list and a lookup set.
function M.db_interfaces()
    local list, set = {}, {}
    if not M.vnstat_installed() then return list, set end
    local out = util.exec(M.VNSTAT .. " --dbiflist 1 2>/dev/null") or ""
    for name in out:gmatch("[^\n]+") do
        name = name:match("^%s*(.-)%s*$")
        if M.safe_name(name) and not set[name] then
            set[name] = true
            list[#list + 1] = name
        end
    end
    table.sort(list)
    return list, set
end

-- Run "vnstat --json <mode> <limit> [-i iface]" and return the raw text if it
-- looks like JSON, or nil (vnStat missing, interface not in the database, ...).
function M.vnstat_json_raw(mode, limit, iface)
    if not M.vnstat_installed() then return nil end
    local cmd = M.VNSTAT .. " --json " .. mode .. " " .. tostring(tonumber(limit) or 0)
    if iface then
        if not M.safe_name(iface) then return nil end
        cmd = cmd .. " -i " .. iface
    end
    local out = util.exec(cmd .. " 2>/dev/null") or ""
    if not out:match("^%s*{") then return nil end
    return out
end

-- Devices that carry a default route, lowest metric first (IPv4, then IPv6).
-- Read straight from the kernel so it works whatever the uplink is called
-- (pppoe-wan, wwan0, eth1, wg0, ...).
function M.default_route_devices()
    local found, seen = {}, {}
    local function add(dev, metric)
        if dev and dev ~= "lo" and not seen[dev] then
            seen[dev] = true
            found[#found + 1] = { dev = dev, metric = metric or 0 }
        end
    end

    local f = io.open("/proc/net/route", "r")
    if f then
        local v4 = {}
        for line in f:lines() do
            local fld = {}
            for w in line:gmatch("%S+") do fld[#fld + 1] = w end
            -- Iface Destination Gateway Flags RefCnt Use Metric Mask ...
            if fld[2] == "00000000" and fld[8] == "00000000" then
                v4[#v4 + 1] = { dev = fld[1], metric = tonumber(fld[7]) or 0 }
            end
        end
        f:close()
        table.sort(v4, function(a, b) return a.metric < b.metric end)
        for _, r in ipairs(v4) do add(r.dev, r.metric) end
    end

    f = io.open("/proc/net/ipv6_route", "r")
    if f then
        local v6 = {}
        for line in f:lines() do
            local fld = {}
            for w in line:gmatch("%S+") do fld[#fld + 1] = w end
            -- dest prefixlen src srcprefixlen nexthop metric refcnt use flags dev
            if fld[1] == "00000000000000000000000000000000" and fld[2] == "00" and fld[10] then
                v6[#v6 + 1] = { dev = fld[10], metric = tonumber(fld[6], 16) or 0 }
            end
        end
        f:close()
        table.sort(v6, function(a, b) return a.metric < b.metric end)
        for _, r in ipairs(v6) do add(r.dev, r.metric) end
    end

    local devs = {}
    for _, r in ipairs(found) do devs[#devs + 1] = r.dev end
    return devs
end

-- With a "known" set, a device is only accepted if it is in that set (e.g.
-- the vnStat database); otherwise it has to exist in /sys/class/net.
local function accept(dev, known)
    if not M.safe_name(dev) then return nil end
    if known then return known[dev] and dev or nil end
    return M.netdev_exists(dev) and dev or nil
end

-- Accepts a logical netifd interface name ("wan", "modem") or a netdev name
-- ("eth1", "wwan0") and returns the matching netdev, or nil. Logical names
-- win: on DSA routers the WAN port netdev is often also called "wan", but
-- the logical interface's L3 device (e.g. pppoe-wan) is the real uplink.
function M.resolve_device(name, known)
    if not M.safe_name(name) then return nil end
    local st = util.ubus("network.interface." .. name, "status", {})
    if type(st) == "table" then
        local dev = accept(st.l3_device, known) or accept(st.device, known)
        if dev then return dev end
    end
    return accept(name, known)
end

function M.preferred_name()
    local c = uci.cursor()
    return c:get_first("netstats", "config", "prefer") or ""
end

-- The device to show: the "Preferred Interface" setting if it resolves,
-- otherwise the default-route device.
function M.wan_device(known)
    local dev = M.resolve_device(M.preferred_name(), known)
    if dev then return dev end
    for _, d in ipairs(M.default_route_devices()) do
        dev = accept(d, known)
        if dev then return dev end
    end
    return nil
end

local function first_addr(list)
    if type(list) == "table" and type(list[1]) == "table" then
        return list[1].address
    end
    return nil
end

-- Local address of a device: netifd's view first, then the kernel's.
function M.device_ipaddr(dev)
    if not M.safe_name(dev) then return nil end

    local dump = util.ubus("network.interface", "dump", {})
    if type(dump) == "table" and type(dump.interface) == "table" then
        for _, key in ipairs({ "ipv4-address", "ipv6-address" }) do
            for _, ifc in ipairs(dump.interface) do
                if ifc.up and ifc.l3_device == dev then
                    local a = first_addr(ifc[key])
                    if a then return a end
                end
            end
        end
    end

    local addrs = nixio.getifaddrs() or {}
    for _, fam in ipairs({ "inet", "inet6" }) do
        for _, a in ipairs(addrs) do
            if a.name == dev and a.family == fam and a.addr
               and not a.addr:match("^[Ff][Ee]80:") then
                return a.addr
            end
        end
    end
    return nil
end

-- This month's rx/tx bytes for a device from the vnStat database, cached in
-- /tmp for a minute because the status widget polls every two seconds and
-- vnStat only writes to its database every few minutes anyway.
local CACHE = "/tmp/luci-netstat-vnstat-month"

function M.vnstat_month_total(dev)
    if not M.safe_name(dev) then return nil end

    local now = os.time()
    local mtime = fs.stat(CACHE, "mtime")
    if mtime and now - mtime < 60 and now >= mtime then
        local c = fs.readfile(CACHE) or ""
        local cdev, rx, tx = c:match("^(%S+) (%d+) (%d+)")
        if cdev == dev then
            return { rx = tonumber(rx), tx = tonumber(tx) }
        end
    end

    local raw = M.vnstat_json_raw("m", 1, dev)
    local data = raw and jsonc.parse(raw)
    if type(data) ~= "table" or type(data.interfaces) ~= "table" then return nil end
    local ifc = data.interfaces[1]
    if type(ifc) ~= "table" or type(ifc.traffic) ~= "table" then return nil end

    -- jsonversion 1 (vnStat 1.x) used plural keys and KiB units.
    local legacy = tostring(data.jsonversion) == "1"
    local months = ifc.traffic[legacy and "months" or "month"]
    local scale  = legacy and 1024 or 1

    local rx, tx = 0, 0
    local last = type(months) == "table" and months[#months]
    if type(last) == "table" and type(last.date) == "table" then
        local t = os.date("*t", now)
        if tonumber(last.date.year) == t.year and tonumber(last.date.month) == t.month then
            rx = (tonumber(last.rx) or 0) * scale
            tx = (tonumber(last.tx) or 0) * scale
        end
    end

    fs.writefile(CACHE, string.format("%s %.0f %.0f\n", dev, rx, tx))
    return { rx = rx, tx = tx }
end

-- DatabaseDir from /etc/vnstat.conf, or vnStat's built-in default.
function M.vnstat_dbdir()
    local conf = fs.readfile("/etc/vnstat.conf") or ""
    for line in conf:gmatch("[^\n]+") do
        local dir = line:match("^%s*DatabaseDir%s+\"([^\"]+)\"")
        if dir then return dir end
    end
    return "/var/lib/vnstat"
end

return M
