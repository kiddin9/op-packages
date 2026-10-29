local net = require "luci.model.network"
local sys = require "luci.sys"
local http = require "luci.http"
local nsu = require "luci.netstat"

local m = Map("netstats", translate("Netstat"),
    translate("Configure traffic monitoring and view usage history from a single page.")
)

local active_tab = http.formvalue("tab") or "usage"

local tabs = m:section(SimpleSection)
tabs.template = "netstat/tabs"

if active_tab == "settings" then
    local s = m:section(TypedSection, "config", translate("Monitoring Settings"))
    s.anonymous = true
    s.addremove = false

    -- Traffic backend
    local backend = s:option(ListValue, "backend", translate("Traffic Backend"))
    backend.default = "normal"
    backend:value("normal", translate("Normal (Real-time)"))
    backend:value("vnstat", translate("vnStat (Historical, Delayed)"))
    backend.description = translate(
        "Live download/upload rates always come from /proc/net/dev. " ..
        "With Normal the downloaded/uploaded totals count since boot; " ..
        "with vnStat they show this month's totals from the vnStat database, " ..
        "which vnStat updates every few minutes."
    )

    -- View mode
    local mode = s:option(ListValue, "mode", translate("View Mode"))
    mode.default = "daily"
    mode:value("daily",   translate("Daily Usage"))
    mode:value("monthly", translate("Monthly Usage"))
    mode.description = translate("Default view shown on the Network Usage tab.")

    -- Interface preference
    local iface = s:option(ListValue, "prefer", translate("Preferred Interface"))
    iface.description = translate(
        "Interface to track. Leave on auto-detection to follow the device " ..
        "that holds the default route, whatever it is called on this router.<br>" ..
        "Logical interfaces (e.g. wan) are resolved to their current device."
    )
    iface:value("", translate("Auto detect"))

    -- Logical netifd interfaces, live netdevs and anything vnStat already
    -- has history for. Nothing is hard-coded.
    local seen = { [""] = true, lo = true, loopback = true }
    local function add_choice(name, label)
        if name and not seen[name] and nsu.safe_name(name) then
            seen[name] = true
            iface:value(name, label or name)
        end
    end

    local netm = net.init()
    for _, n in ipairs(netm:get_networks()) do
        add_choice(n:name(), n:name() .. " (" .. translate("logical interface") .. ")")
    end
    for _, dev in ipairs(netm:get_interfaces()) do
        add_choice(dev:shortname())
    end
    for _, name in ipairs((nsu.db_interfaces())) do
        add_choice(name, name .. " (" .. translate("vnStat history") .. ")")
    end

    -- Data retention info
    local info = s:option(DummyValue, "_info", translate("vnStat Database"))
    info.rawhtml  = true
    info.cfgvalue = function()
        if not nsu.vnstat_installed() then
            return '<span style="font-size:12px;color:#b91c1c;">' ..
                translate("vnStat is not installed. Install the vnstat2 package.") ..
                '</span>'
        end

        local dir = nsu.vnstat_dbdir()
        local size_out = sys.exec("du -sh '" .. dir:gsub("'", "") .. "' 2>/dev/null | cut -f1") or ""
        size_out = size_out:match("^%s*(.-)%s*$") or ""
        local db_size = size_out ~= "" and (" — " .. size_out) or ""

        local tracked = table.concat((nsu.db_interfaces()), ", ")
        if tracked == "" then tracked = translate("none yet") end

        local html = string.format(
            '<span style="font-size:12px;opacity:0.75;">%s %s%s<br>%s %s</span>',
            translate("Location:"), dir, db_size,
            translate("Tracked interfaces:"), tracked
        )

        -- /var is a tmpfs on OpenWrt, so the default location loses history
        -- on every reboot.
        if dir:match("^/var/") or dir:match("^/tmp/") or dir == "/var" or dir == "/tmp" then
            html = html .. '<br><span style="font-size:12px;color:#b45309;">' ..
                translate("This directory is in RAM, so history is lost on reboot. " ..
                    "Set DatabaseDir in /etc/vnstat.conf to persistent storage to keep it.") ..
                '</span>'
        end
        return html
    end

    -- Reset button with inline JS confirmation
    local reset = s:option(Button, "_reset", translate("Reset Historical Data"))
    reset.inputtitle = translate("Reset Database")
    reset.inputstyle = "reset"
    reset.description = translate(
        "<strong style='color:#b91c1c;'>Warning:</strong> " ..
        "This permanently deletes all stored traffic history for every interface."
    )

    -- Inject confirmation dialog via rawhtml trick
    local confirm_js = s:option(DummyValue, "_confirm_js", "")
    confirm_js.rawhtml = true
    confirm_js.cfgvalue = function()
        return [[
<script>
(function () {
    var btn = document.querySelector('input[value="]] .. translate("Reset Database") .. [["]');
    if (!btn) return;
    btn.addEventListener('click', function (e) {
        if (!confirm(']] .. translate("Are you sure? All traffic history will be permanently deleted.") .. [[')) {
            e.preventDefault();
        }
    });
})();
</script>]]
    end

    function reset.write(self, section)
        -- vnStat 2 keeps everything in one SQLite database, so drop and
        -- re-create each interface's entry instead of deleting files.
        local ifaces = nsu.db_interfaces()
        sys.call("/etc/init.d/vnstat stop >/dev/null 2>&1")
        for _, name in ipairs(ifaces) do
            sys.call(nsu.VNSTAT .. " --remove --force -i " .. name .. " >/dev/null 2>&1")
            sys.call(nsu.VNSTAT .. " --add --force -i " .. name .. " >/dev/null 2>&1")
        end
        sys.call("rm -f /tmp/luci-netstat-vnstat-month")
        sys.call("/etc/init.d/vnstat start >/dev/null 2>&1")
        m.message = translate("vnStat database has been reset successfully for all interfaces.")
    end

elseif active_tab == "about" then
    local about = m:section(SimpleSection, translate("About"))
    about.template = "netstat/about"

else -- usage tab (default)
    local usage = m:section(SimpleSection, translate("Network Usage"))
    usage.template = "netstat/usage"
end

return m
