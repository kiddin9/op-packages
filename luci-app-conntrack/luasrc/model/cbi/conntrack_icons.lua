local i18n = require("luci.i18n")
local nixio = require("nixio")

local m = Map("conntrack", i18n.translate("Conntrack Custom App Icons"), i18n.translate("Manage your custom application regex mappings and SVG icons here. Note that the regex and icon mappings only apply to tracked TCP connections that successfully return a domain name for matching, and will not affect existing hardcoded rules (such as YouTube detection). Custom regex expressions and icon mappings will be matched with the highest priority based on their ranking order."))

local old_map_render = m.render
function m.render(self, ...)
	luci.http.write([[
<script src="https://code.iconify.design/3/3.1.0/iconify.min.js"></script>
<script type="text/javascript" src="]] .. luci.dispatcher.build_url('admin/network/conntrack/conntrack_custom_js') .. [["></script>
<h2>
<ul class="cbi-tabmenu" style="border-bottom:0 !important;">
	<li class="cbi-tab-disabled"><a href="]] .. luci.dispatcher.build_url('admin/network/conntrack') .. [[">]] .. i18n.translate("ConnTrack") .. [[</a></li>
	<li class="cbi-tab"><a href="]] .. luci.dispatcher.build_url('admin/network/conntrack/conntrack_icons_config') .. [["><strong>]] .. i18n.translate("Custom App Icons Config") .. [[</strong></a></li>
</ul>
</h2>
]])
	return old_map_render(self, ...)
end

local s1 = m:section(TypedSection, "regex_icon", i18n.translate("Regex Expression & Icon Mappings"))
s1.description = i18n.translate('You can use an <a href="https://icon-sets.iconify.design/" target="_blank">existing Iconify ID</a> (e.g., logos:youtube) or a custom ID defined in the Custom SVG Icons Repository below.')
s1.anonymous = true
s1.addremove = true
s1.sortable = true
s1.template = "cbi/tblsection"

local p1 = s1:option(Value, "pattern", i18n.translate("Regex Pattern"))
p1.rmempty = false
p1.placeholder = "/\\.google\\./i"

local i1_hint = i18n.translate("You can use an existing Iconify ID (e.g., logos:youtube) or a custom ID defined in the Custom SVG Icons Repository below.")
local i1 = s1:option(Value, "icon", string.format('%s <span title="%s" data-tooltip="%s" style="cursor:help; border-bottom:1px dashed #666;">(?)</span>', i18n.translate("Iconify ID"), i1_hint, i1_hint))
i1.rmempty = false
i1.placeholder = "conntrack:google"

local s2 = m:section(TypedSection, "my_custom_icons", i18n.translate("Custom SVG Icons Repository"))
s2.anonymous = true
s2.addremove = true
s2.template = "cbi/tblsection"

local v2 = s2:option(DummyValue, "_preview", i18n.translate("Icon Preview"))
function v2.cfgvalue(self, section)
	local name = self.map:get(section, "name") or "mdi:server-network"
	return string.format('<span class="iconify-live-preview" data-icon="%s" style="font-size:24px;vertical-align:middle;"></span>', name)
end
v2.rawhtml = true

local n2_hint = i18n.translate("The Iconify ID must start with 'conntrack:' prefix to avoid overriding existing Iconify datasets.")
local n2 = s2:option(Value, "name", string.format('%s <span title="%s" data-tooltip="%s" style="cursor:help; color: #e00; border-bottom:1px dashed #e00;">(?)</span>', i18n.translate("Iconify ID"), i18n.translate(n2_hint), i18n.translate(n2_hint)))
n2.rmempty = false
n2.placeholder = "conntrack:google"
function n2.validate(self, value)
	if value and value ~= "" then
		if not value:match("^conntrack:") then
			return nil, i18n.translate("Validation Error: The Iconify ID must begin with 'conntrack:' prefix (e.g., conntrack:custom_name).")
		end
	end
	return value
end

local w2 = s2:option(Value, "width", i18n.translate("Icon Width"))
w2.rmempty = false
w2.datatype = "uinteger"
w2.placeholder = "24"
w2.default = "24"

local h2 = s2:option(Value, "height", i18n.translate("Icon Height"))
h2.rmempty = false
h2.datatype = "uinteger"
h2.placeholder = "24"
h2.default = "24"

local b2 = s2:option(TextValue, "svg_body", i18n.translate("SVG Body (Raw XML)"))
b2.rmempty = false
b2.rows = 3

local function base64_encode(data)
	local b = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
	return ((data:gsub('.', function(x)
		local r, b_val = '', x:byte()
		for i = 8, 1, -1 do r = r .. (b_val % 2^i - b_val % 2^(i-1) >= 2^(i-1) and '1' or '0') end
		return r
	end) .. '0000'):gsub('%d%d%d%d%d%d', function(x)
		if (#x < 6) then return '' end
		local c = 0
		for i = 1, 6 do c = c + (x:sub(i, i) == '1' and 2^(6-i) or 0) end
		return b:sub(c + 1, c + 1)
	end) .. ({ '', '==', '=' })[#data % 3 + 1])
end

local function base64_decode(data)
	local b = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
	data = string.gsub(data, '[^'..b..'=]', '')
	return (data:gsub('.', function(x)
		if (x == '=') then return '' end
		local r, f = '', (b:find(x) - 1)
		for i = 6, 1, -1 do r = r .. (f % 2^i - f % 2^(i-1) >= 2^(i-1) and '1' or '0') end
		return r;
	end):gsub('%d%d%d%d%d%d%d%d', function(x)
		local c = 0
		for i = 1, 8 do c = c + (x:sub(i, i) == '1' and 2^(8-i) or 0) end
		return string.char(c)
	end))
end

function b2.cfgvalue(self, section)
	local value = Value.cfgvalue(self, section)
	if value and value ~= "" then
		local pcall_ok, decoded = pcall(nixio.bin.b64decode, value)
		if pcall_ok then
			return decoded
		end
	end
	return value
end

function b2.validate(self, value)
	if value and value ~= "" then
		if not value:match("^%s*<svg") then
			return nil, i18n.translate("Invalid SVG content. Must start with <svg> tag.")
		end
		return nixio.bin.b64encode(value)
	end
	return value
end

return m

