module("luci.controller.netstat", package.seeall)
local nixio = require("nixio")
local nfs   = require("nixio.fs")
local uci   = require("luci.model.uci").cursor()
local nsu   = require("luci.netstat")

function index()
    entry({"admin", "tools"}, firstchild(), _("Tools"), 50).dependent = false
    entry({"admin", "tools", "netstat"}, cbi("netstat/config"), _("Netstat"), 20).leaf = true
    entry({"admin", "tools", "netstat_config"}, alias("admin", "tools", "netstat")).dependent = true
    entry({"admin", "tools", "get_netdev_stats"}, call("getNetdevStats"), nil).sysauth = false
end

-- Reads /proc/net/dev and returns per-interface rx/tx byte counters.
function getNetdevStats()
    local f = io.open("/proc/net/dev", "r")
    if not f then
        luci.http.prepare_content("application/json")
        luci.http.write('{"stats":{},"ip":"N/A","status":"Disconnected"}')
        return
    end
    local content = f:read("*a")
    f:close()

    local stats = {}
    for line in content:gmatch("[^\n]+") do
        local iface, values = line:match("^%s*([^:]+):%s+(.*)$")
        if iface and values then
            local nums = {}
            for num in values:gmatch("%d+") do
                table.insert(nums, tonumber(num))
            end
            if #nums >= 9 then
                stats[iface] = { rx = nums[1], tx = nums[9] }
            end
        end
    end

    local status = #nsu.default_route_devices() > 0 and "Connected" or "Disconnected"

    local function read_cmd(cmd)
        local p = io.popen(cmd)
        if not p then return nil end
        local line = p:read("*l")
        p:close()
        if not line then return nil end
        line = line:gsub("^%s+",""):gsub("%s+$","")
        return line ~= "" and line or nil
    end

    -- ── Tracked device ──────────────────────────────────────────────────────
    -- The "Preferred Interface" setting (netdev or logical name such as
    -- "wan"), otherwise the default-route device. Both are resolved
    -- generically; no interface names are assumed.
    local prefer_iface = nsu.wan_device(stats) or ""

    local function is_valid_ip(v)
        if not v then return false end
        local a,b,c,d = v:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
        if a and b and c and d then
            a,b,c,d = tonumber(a),tonumber(b),tonumber(c),tonumber(d)
            if a<=255 and b<=255 and c<=255 and d<=255 then return true end
        end
        if v:find(":",1,true) and v:match("^[%x:]+$") then return true end
        return false
    end

    local ip = "N/A"
    local ip_source = "none"

    -- Determine whether the caller wants a public IP (slow, requires network)
    -- or just the fast local WAN address.  The JS frontend sends ?fast=1 for
    -- poll ticks and omits it only when explicitly requesting a public IP refresh.
    local want_public = luci.http.formvalue("fast") ~= "1"

    -- 1. Try public-IP APIs (only when not in fast mode)
    if want_public then
        local public_cmds = {
            "curl -fsS --max-time 2 'https://api.ipify.org' 2>/dev/null",
            "curl -fsS --max-time 2 'http://api.ipify.org' 2>/dev/null",
            "uclient-fetch -qO- --timeout=2 'https://api.ipify.org' 2>/dev/null",
        }
        for _, cmd in ipairs(public_cmds) do
            local v = read_cmd(cmd)
            if is_valid_ip(v) then ip = v; ip_source = "public"; break end
        end
    end

    -- 2. Fall back to the local address of the tracked device
    if ip == "N/A" and prefer_iface ~= "" then
        local v = nsu.device_ipaddr(prefer_iface)
        if is_valid_ip(v) then ip = v; ip_source = "local" end
    end

    -- ── vnStat totals (only with the vnStat backend) ────────────────────────
    -- Live rates always come from /proc/net/dev; the vnStat backend swaps the
    -- "downloaded/uploaded" boxes to this month's totals from its database.
    local vnstat_total = nil
    if prefer_iface ~= "" and
       (uci:get_first("netstats", "config", "backend") or "normal") == "vnstat" then
        vnstat_total = nsu.vnstat_month_total(prefer_iface)
    end

    -- ── System uptime ─────────────────────────────────────────────────────────
    local uptime_sec = 0
    local uf = io.open("/proc/uptime", "r")
    if uf then
        local line = uf:read("*l")
        uf:close()
        if line then
            uptime_sec = math.floor(tonumber(line:match("^([%d%.]+)")) or 0)
        end
    end

    -- ── CPU usage (two reads 200 ms apart for accurate delta) ────────────────
    local cpu_pct = 0
    local function read_cpu_stat()
        local f = io.open("/proc/stat", "r")
        if not f then return nil end
        local line = f:read("*l"); f:close()
        local vals = {}
        for n in line:gmatch("%d+") do vals[#vals+1] = tonumber(n) end
        if #vals < 4 then return nil end
        local idle, total = vals[4], 0
        for _, v in ipairs(vals) do total = total + v end
        return { idle = idle, total = total }
    end
    local s1 = read_cpu_stat()
    if s1 then
        nixio.nanosleep(0, 200000000)
        local s2 = read_cpu_stat()
        if s2 then
            local d_total = s2.total - s1.total
            local d_idle  = s2.idle  - s1.idle
            if d_total > 0 then
                cpu_pct = math.floor((d_total - d_idle) / d_total * 100 + 0.5)
            end
        end
    end

    -- ── Memory usage ──────────────────────────────────────────────────────────
    local mem_total, mem_available, mem_free = 0, 0, 0
    local mf = io.open("/proc/meminfo", "r")
    if mf then
        for line in mf:lines() do
            local k, v = line:match("^(%S+):%s+(%d+)")
            if k == "MemTotal"     then mem_total     = tonumber(v) or 0 end
            if k == "MemAvailable" then mem_available = tonumber(v) or 0 end
            if k == "MemFree"      then mem_free      = tonumber(v) or 0 end
        end
        mf:close()
    end
    -- MemAvailable is present on Linux 3.14+; fall back to MemFree on older kernels
    if mem_available == 0 and mem_free > 0 then mem_available = mem_free end
    local mem_pct = 0
    if mem_total > 0 then
        mem_pct = math.floor((mem_total - mem_available) / mem_total * 100 + 0.5)
    end
    -- used MB and total MB for display
    local mem_used_mb  = math.floor((mem_total - mem_available) / 1024 + 0.5)
    local mem_total_mb = math.floor(mem_total / 1024 + 0.5)

    -- ── Disk space (root filesystem) ──────────────────────────────────────────
    local disk_pct, disk_used_mb, disk_total_mb = 0, 0, 0
    local df = read_cmd("df -k / 2>/dev/null | awk 'NR==2{print $2,$3}'")
    if df then
        local dtotal, dused = df:match("^(%d+)%s+(%d+)$")
        dtotal = tonumber(dtotal) or 0
        dused  = tonumber(dused)  or 0
        if dtotal > 0 then
            disk_pct      = math.floor(dused / dtotal * 100 + 0.5)
            disk_used_mb  = math.floor(dused  / 1024 + 0.5)
            disk_total_mb = math.floor(dtotal / 1024 + 0.5)
        end
    end

    -- ── CPU temperature ───────────────────────────────────────────────────────
    local cpu_temp = nil
    -- Scan all available thermal zones and pick the highest valid reading
    -- (avoids hardcoded zone numbers which vary per device)
    for path in (nfs.glob("/sys/class/thermal/thermal_zone*/temp") or function() end) do
        local tf = io.open(path, "r")
        if tf then
            local val = tf:read("*l")
            tf:close()
            local t = tonumber(val)
            if t and t > 0 then
                -- values > 1000 are in millidegrees
                if t > 1000 then t = t / 1000 end
                t = math.floor(t + 0.5)
                -- Keep the highest temperature reading across all zones
                if cpu_temp == nil or t > cpu_temp then
                    cpu_temp = t
                end
            end
        end
    end

    luci.http.prepare_content("application/json")
    luci.http.write_json({ stats = stats, ip = ip, ip_source = ip_source,
                           status = status,
                           prefer_iface = prefer_iface,
                           vnstat_total = vnstat_total,
                           uptime      = uptime_sec,
                           cpu_pct     = cpu_pct,
                           cpu_temp    = cpu_temp,
                           mem_pct     = mem_pct,
                           mem_used    = mem_used_mb,
                           mem_total   = mem_total_mb,
                           disk_pct    = disk_pct,
                           disk_used   = disk_used_mb,
                           disk_total  = disk_total_mb })
end
