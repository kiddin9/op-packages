a = Map("miaplus")
a.apply_on_parse = true
function a.on_apply(self)
	luci.sys.call("/etc/init.d/miaplus restart >/dev/null 2>&1 &")
end

local section = arg[1]

t = a:section(TypedSection, section, translate("Rules"))
t.template = "cbi/tblsection"
t.anonymous = true
t.addremove = true
t.sortable  = true

e = t:option(Flag, "enable", translate("Enabled"))
e.rmempty = false
e.default = "1"

-- HH:MM / H:MM -> 分钟；非法或空返回 nil
local function time_to_min(s)
	local h, m = s:match("^(%d?%d):(%d%d)$")
	if not h then return nil end
	h, m = tonumber(h), tonumber(m)
	if h > 23 or m > 59 then return nil end
	return h * 60 + m
end

e = t:option(Value, "timeon", translate("Start time"))
e.optional = false
e.default = "00:00"
function e.validate(self, value, section)
	local mins = time_to_min(value)
	if not mins then
		return nil, translate("Invalid time, expected HH:MM")
	end
	return string.format("%02d:%02d", math.floor(mins / 60), mins % 60)
end

e = t:option(Value, "timeoff", translate("End time"))
e.optional=false
e.default = "23:59"
function e.validate(self, value, section)
	local mins = time_to_min(value)
	if not mins then
		return nil, translate("Invalid time, expected HH:MM")
	end
	-- 跨字段：起止时间不能相同（起止相同即无管控，易误配）
	local on = self.map:formvalue("cbid.miaplus." .. section .. ".timeon")
	local on_min = on and time_to_min(on)
	if on_min ~= nil and on_min == mins then
		return nil, translate("Start and end time must differ")
	end
	return string.format("%02d:%02d", math.floor(mins / 60), mins % 60)
end

e = t:option(Flag, "z1", translate("Mon"))
e.rmempty = true
e.default = 1

e = t:option(Flag, "z2", translate("Tue"))
e.rmempty = true
e.default=1

e = t:option(Flag, "z3", translate("Wed"))
e.rmempty = true
e.default = 1

e = t:option(Flag, "z4", translate("Thu"))
e.rmempty = true
e.default = 1

e = t:option(Flag, "z5", translate("Fri"))
e.rmempty = true
e.default = 1

e = t:option(Flag, "z6", translate("Sat"))
e.rmempty = true
e.default = 1

e = t:option(Flag, "z7", translate("Sun"))
e.rmempty = true
e.default = 1

return a
