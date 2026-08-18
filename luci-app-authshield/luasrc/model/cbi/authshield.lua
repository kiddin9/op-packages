-- LuCI CBI model for AuthShield
local sys   = require "luci.sys"
local jsonc = require "luci.jsonc"

local m, s, o

m = Map("authshield", translate("AuthShield"),
    translate("Lightweight intrusion prevention that delays or blocks repeated failed login attempts for both LuCI and Dropbear SSH."))

-- IMPORTANT: the UCI section type is 'settings' (not 'main')
s = m:section(TypedSection, "settings", translate("General Settings"))
s.anonymous = true
s.addremove = false


s:tab("main", translate("General"))
s:tab("advanced", translate("Advanced / Global"))
s:tab("circuit", translate("Circuit Breaker"))

-- small helpers
local function uint_range_validator(minv, maxv, label, def)
    return function(self, value)
        if not value or value == "" then
            return tostring(def)   -- auto-fill with default if empty
        end
        local n = tonumber(value)
        if not n or n < minv or n > maxv then
            return nil, translatef("%s must be %d–%d.", label, minv, maxv)
        end
        return tostring(math.floor(n))
    end
end

-- Enable / Disable
o = s:taboption("main", Flag, "enabled", translate("Enable AuthShield"))
o.default = 1
o.rmempty = false

-- Failure threshold
o = s:taboption("main", Value, "threshold", translate("Failure Threshold"),
    translate("Number of failed attempts within the time window before an IP is banned.") ..
    " " .. translate("Allowed range:") .. " " .. translate("1–30"))
o.placeholder = "5"
o.default = 5
o.rmempty = true
o.validate = uint_range_validator(1, 30, translate("Failure Threshold"), 5)
function o.write(self, section, value)
    if not value or value == "" then value = "5" end
    Value.write(self, section, value)
end

-- Time window (seconds)
o = s:taboption("main", Value, "window", translate("Time Window (s)"),
    translate("Period in seconds during which failed attempts are counted.") ..
    " " .. translate("Allowed range:") .. " " .. translate("10–60"))
o.placeholder = "10"
o.default = 10
o.rmempty = true
o.validate = uint_range_validator(10, 60, translate("Time Window (s)"), 10)
function o.write(self, section, value)
    if not value or value == "" then value = "10" end
    Value.write(self, section, value)
end

-- Penalty duration (seconds)
o = s:taboption("main", Value, "penalty", translate("Ban Duration (s)"),
    translate("How long (in seconds) a client is banned after exceeding the threshold.") ..
    " " .. translate("Allowed range:") .. " " .. translate("60–600"))
o.placeholder = "60"
o.default = 60
o.rmempty = true
o.validate = uint_range_validator(60, 600, translate("Ban Duration (s)"), 60)
function o.write(self, section, value)
    if not value or value == "" then value = "60" end
    Value.write(self, section, value)
end

-- Ports protected
o = s:taboption("main", Value, "ports", translate("Protected Ports"))
o.placeholder = "80 443"
o.description = translate("Space-separated ports (max 10). Each must be numeric, 1–65535.")
function o.validate(self, value, section)
    if not value or value == "" then
        return value
    end
    local seen, out = {}, {}
    for p in value:gmatch("[%d]+") do
        local n = tonumber(p)
        if not n or n < 1 or n > 65535 then
            return nil, translatef("Invalid port number: %s (must be between 1 and 65535)", p)
        end
        if not seen[n] then
            seen[n] = true
            out[#out + 1] = tostring(n)
        end
        if #out > 10 then
            return nil, translate("You can specify at most 10 ports.")
        end
    end
    return table.concat(out, " ")
end

-- Monitor Dropbear SSH
o = s:taboption("main", Flag, "watch_dropbear", translate("Monitor Dropbear SSH"),
    translate("Also monitor bad password attempts on Dropbear SSH service."))
o.default = 0

-- Ignore private/local IPs
o = s:taboption("main", Flag, "ignore_private_ip", translate("Ignore Private IPs"),
    translate("Skip banning LAN, loopback, and link-local addresses."))
o.default = 1

-- ---- Current bans (from nft sets; shows IP and remaining time with live countdown) ----
do
    local function fetch_set(setname)
        local out = sys.exec("nft -j list set inet fw4 " .. setname .. " 2>/dev/null")
        local list = {}
        if not out or #out == 0 then return list end

        local ok, obj = pcall(jsonc.parse, out)
        if not ok or type(obj) ~= "table" or type(obj.nftables) ~= "table" then
            return list
        end

        for _, item in ipairs(obj.nftables) do
            local set = item and item.set
            local elems = set and set.elem
            if type(elems) == "table" then
                for _, e in ipairs(elems) do
                    if type(e) == "table" then
                        local ip = (type(e.elem) == "table" and (e.elem.val or e.elem[1])) or e.elem or e.val or e[1]
                        local rem = e.expires or e.timeout or (type(e.elem) == "table" and e.elem.expires)
                        if ip then table.insert(list, { ip = tostring(ip), rem = tonumber(rem) or 0 }) end
                    elseif type(e) == "string" then
                        table.insert(list, { ip = e, rem = 0 })
                    end
                end
            end
        end
        return list
    end

    local function render_rows(list)
        table.sort(list, function(a,b) return (a.ip or "") < (b.ip or "") end)
        if #list == 0 then
            return "<em>" .. translate("None") .. "</em>"
        end

        local html = {}
        html[#html+1] = '<table class="table"><thead><tr><th>'
        html[#html+1] = translate("IP")
        html[#html+1] = '</th><th>'
        html[#html+1] = translate("Expires")
        html[#html+1] = '</th></tr></thead><tbody>'

        for _, r in ipairs(list) do
            local sec = r.rem and math.floor(r.rem) or 0
            local init = (sec > 0) and (tostring(sec) .. "s") or "-"
            html[#html+1] = '<tr' .. (sec <= 0 and ' class="opacity-50"' or '') .. '>'
            html[#html+1] = '<td>' .. r.ip .. '</td>'
            html[#html+1] = '<td class="as-ttl" data-seconds="' .. tostring(sec) .. '">' .. init .. '</td>'
            html[#html+1] = '</tr>'
        end
        html[#html+1] = '</tbody></table>'

        -- Live countdown (client-side)
        html[#html+1] = [[
<script>
(function(){
  function fmt(sec){
    sec = Math.max(0, Math.floor(sec));
    var d = Math.floor(sec/86400); sec %= 86400;
    var h = Math.floor(sec/3600); sec %= 3600;
    var m = Math.floor(sec/60); var s = sec % 60;
    if (d>0) return d + "d " + String(h).padStart(2,"0") + "h" + String(m).padStart(2,"0") + "m";
    if (h>0) return h + "h " + String(m).padStart(2,"0") + "m " + String(s).padStart(2,"0") + "s";
    if (m>0) return m + "m " + String(s).padStart(2,"0") + "s";
    return s + "s";
  }
  var cells = document.querySelectorAll(".as-ttl");
  if (!cells.length) return;
  setInterval(function(){
    cells.forEach(function(td){
      var sec = parseInt(td.dataset.seconds || "0", 10);
      if (isNaN(sec)) sec = 0;
      if (sec <= 0){
        td.textContent = "-";
        var tr = td.closest("tr");
        if (tr) tr.classList.add("opacity-50");
        return;
      }
      sec -= 1;
      td.dataset.seconds = String(sec);
      td.textContent = fmt(sec);
    });
  }, 1000);
})();
</script>]]
        return table.concat(html)
    end

    local v4 = fetch_set("authshield_penalty_v4")
    local v6 = fetch_set("authshield_penalty_v6")
    for _, x in ipairs(v6) do table.insert(v4, x) end  -- merge

    local dv = s:taboption("main", DummyValue, "_current_bans", translate("Currently Banned IPs"))
    dv.rawhtml = true
    function dv.cfgvalue()
        return render_rows(v4)
    end
end


-- Escalate frequent offenders
o = s:taboption("advanced", Flag, "escalate_enable", translate("Escalate frequent offenders"),
    translate("When enabled, if an IP receives more than the threshold number of bans within the window, the next ban lasts the escalation penalty (24h by default). Counts bans (not failures). Private/loopback/ULA are still skipped when 'Ignore private IPs' is on."))
o.default = 1

-- Escalation tuning (frequent offenders → 24h)
o = s:taboption("advanced", Value, "escalate_threshold", translate("Escalate Threshold"),
    translate("Number of bans within the window that triggers escalation (the current ban is included in the check)."))
o.placeholder = "5"; o.default = 5
o.datatype = "range(2,10)"

o = s:taboption("advanced", Value, "escalate_window", translate("Escalate Window (seconds)"),
    translate("Rolling time window for counting bans (e.g. 3600 for 1 hour)."))
o.placeholder = "3600"; o.default = 3600
o.datatype = "range(1800,21600)"

o = s:taboption("advanced", Value, "escalate_penalty", translate("Escalate Penalty (seconds)"),
    translate("Ban duration applied upon escalation (e.g. 86400 for 24 hours)."))
o.placeholder = "86400"; o.default = 86400
o.datatype = "range(3600,604800)"

-- Advanced / Global controls
o = s:taboption("advanced", Flag, "global_enable", translate("Enable Global Rule"),
    translate("If enabled, an IP with more than the global threshold of failed logins within the global window is banned for the global penalty (24h by default). Private/loopback/ULA are still skipped when 'Ignore private IPs' is on."))
o.default = o.default or 1
o.rmempty = false

o = s:taboption("advanced", Value, "global_threshold", translate("Global Threshold"),
    translate("Failed logins within the global window that trigger the 24h ban (strictly greater-than this number). Example: set 60 for 'more than 60'."))
o.placeholder = "60"; o.default = 60
o.datatype = "range(30,300)"

o = s:taboption("advanced", Value, "global_window", translate("Global Window (seconds)"),
    translate("Rolling time window to count failed logins (e.g. 43200 for 12 hours)."))
o.placeholder = "43200"; o.default = 43200
o.datatype = "range(3600,172800)"

o = s:taboption("advanced", Value, "global_penalty", translate("Global Penalty (seconds)"),
    translate("Ban duration when the global threshold is exceeded (e.g. 86400 for 24 hours)."))
o.placeholder = "86400"; o.default = 86400
o.datatype = "range(3600,604800)"

-- ========== Circuit Breaker Tab ==========

o = s:taboption("circuit", Flag, "circuit_enable", translate("Enable Circuit Breaker"),
    translate("When total failed logins across all IPs exceed the threshold within the window, block management ports on WAN interface for the specified duration. Private/loopback/ULA are still skipped when 'Ignore private IPs' is on."))
o.default = 1
o.rmempty = false

o = s:taboption("circuit", Value, "circuit_threshold", translate("Circuit Threshold"),
    translate("Total failed login attempts (from all IPs combined) that trigger the circuit breaker. Example: 120 total failures."))
o.placeholder = "120"
o.default = 120
o.datatype = "range(50,500)"

o = s:taboption("circuit", Value, "circuit_window", translate("Circuit Window (seconds)"),
    translate("Rolling time window to count total failed logins (e.g. 43200 for 12 hours)."))
o.placeholder = "43200"
o.default = 43200
o.datatype = "range(3600,172800)"

o = s:taboption("circuit", Value, "circuit_penalty", translate("Circuit Block Duration (seconds)"),
    translate("How long to block WAN access to management ports when circuit breaker triggers. WAN access automatically restores after this duration via nftables timeout. Note: The failure counter has a 12-hour memory by default, so repeated login attempts after unlock may cause immediate re-locking until the memory window expires."))
o.placeholder = "3600"
o.default = 3600
o.datatype = "range(600,14400)"

-- Circuit breaker status display
do
    local function get_circuit_status()
        local status_file = "/var/run/authshield.circuit"
        local f = io.open(status_file, "r")
        if not f then
            return "<em>" .. translate("Circuit breaker not active") .. "</em>"
        end
        
        local content = f:read("*all")
        f:close()
        
        local locked, expires, count = content:match("^(%d+) (%d+) (%d+)")
        if not locked then
            return "<em>" .. translate("Invalid status") .. "</em>"
        end
        
        locked = tonumber(locked)
        expires = tonumber(expires)
        count = tonumber(count)
        local now = os.time()
        
        if locked == 1 and expires > now then
            local remaining = expires - now
            return string.format('<span style="color:red;font-weight:bold">🔒 %s</span> - %s %ds (%s: %d)', 
                translate("LOCKED"),
                translate("WAN ports blocked for"),
                remaining,
                translate("Total failures"),
                count)
        elseif locked == 0 then
            return string.format('<span style="color:green">✓ %s</span> - %s: %d', 
                translate("UNLOCKED"),
                translate("Total failures in window"),
                count)
        else
            return "<em>" .. translate("Monitoring...") .. "</em>"
        end
    end
    
    local dv = s:taboption("circuit", DummyValue, "_circuit_status", translate("Circuit Breaker Status"))
    dv.rawhtml = true
    function dv.cfgvalue()
        return get_circuit_status()
    end
end

return m
