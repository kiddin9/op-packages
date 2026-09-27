local net = require "luci.model.network"
local sys = require "luci.sys"
local http = require "luci.http"

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
        "Normal reads live counters from /proc/net/dev. " ..
        "vnStat reads the vnStat database which updates on its own schedule."
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
        "WAN interface to track. Leave blank for auto-detection.<br>" ..
        "<strong>Tip:</strong> If your WAN uses a dynamic name (e.g. wwan0_1) " ..
        "it will be detected automatically when left blank."
    )
    iface:value("", translate("Auto detect"))

    local netm = net.init()
    for _, dev in ipairs(netm:get_interfaces()) do
        local name = dev:shortname()
        if name and not name:match("^lo$") and not name:match("^br%-") then
            iface:value(name)
        end
    end

    -- Data retention info
    local info = s:option(DummyValue, "_info", translate("vnStat Database"))
    info.rawhtml  = true
    info.cfgvalue = function()
        -- Show current database size if available
        local size_out = sys.exec("du -sh /etc/vnstat/ 2>/dev/null | cut -f1") or ""
        size_out = size_out:match("^%s*(.-)%s*$") or ""
        local db_size = size_out ~= "" and (" — " .. size_out) or ""
        return string.format(
            '<span style="font-size:12px;color:#6b7280;">%s%s</span>',
            translate("Location: /etc/vnstat/"),
            db_size
        )
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
        sys.call("/etc/init.d/vnstat stop 2>/dev/null")
        sys.call("rm -f /etc/vnstat/* 2>/dev/null")

        -- Re-initialise only interfaces that currently exist
        local netm2 = net.init()
        for _, dev in ipairs(netm2:get_interfaces()) do
            local name = dev:shortname()
            if name and not name:match("^lo$") and not name:match("^br%-") then
                sys.call("vnstat -u -i " .. name .. " >/dev/null 2>&1")
            end
        end

        sys.call("/etc/init.d/vnstat start 2>/dev/null")
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
