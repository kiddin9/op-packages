local sys = require "luci.sys"
local m, s, o

-- Create the main map object
m = Map("timewol", translate("Timed Wake on LAN"),
	translate("Wake up your local area network devices on schedule"))
m.template = "timewol/index"

-- Running Status Section
s = m:section(TypedSection, "basic", translate("Running Status"))
s.anonymous = true

o = s:option(DummyValue, "timewol_status", translate("Current Status"))
o.template = "timewol/timewol"
o.value = translate("Collecting data...")

-- Basic Settings Section
s = m:section(TypedSection, "basic", translate("Basic Settings"))
s.anonymous = true

o = s:option(Flag, "enable", translate("Enable"))
o.rmempty = false

-- Client Settings Section
s = m:section(TypedSection, "macclient", translate("Client Settings"))
s.template = "cbi/tblsection"
s.anonymous = true
s.addremove = true

o = s:option(Flag, "enable", translate("Enable"))
o.default = 1
o.rmempty = false

-- Client MAC Address
o = s:option(Value, "macaddr", translate("Client MAC"))
o.rmempty = false
sys.net.mac_hints(function(mac, hint)
	o:value(mac, string.format("%s (%s)", mac, hint))
end)

-- Network Interface
o = s:option(Value, "maceth", translate("Network Interface"))
o.rmempty = false
o.default = "br-lan"
for _, device in ipairs(sys.net.devices()) do
	if device ~= "lo" then
		o:value(device)
	end
end

-- Function to validate cron field values
local function validate_cron_field(option_name, value, min, max, default)
	if value == "" then
		return default
	elseif value == "*" then
		return value
	end
	local num = tonumber(value)
	if num and num >= min and num <= max then
		return value
	else
		return nil, translatef("Invalid value for %s: %s. Must be between %d and %d or '*'", option_name, value, min, max)
	end
end

-- Scheduling Options with Default Values and Range Checks
local schedule_options = {
	{ "minute", translate("Minute"), 0, 59, "0" },
	{ "hour", translate("Hour"), 0, 23, "0" },
	{ "day", translate("Day"), 1, 31, "*" },
	{ "month", translate("Month"), 1, 12, "*" },
	{ "weeks", translate("Week"), 0, 6, "*" }  -- 0 for Sunday, 6 for Saturday
}

for _, opt in ipairs(schedule_options) do
	o = s:option(Value, opt[1], opt[2])
	o.default = opt[5] or opt[4] -- Use default value if present, otherwise use maximum value
	o.optional = false
	o.validate = function(self, value)
		return validate_cron_field(opt[2], value, opt[3], opt[4], o.default)
	end
end

-- Apply the configuration changes
m.apply_on_parse = true
function m.on_apply(self)
	sys.exec("/etc/init.d/timewol restart")
end

return m
