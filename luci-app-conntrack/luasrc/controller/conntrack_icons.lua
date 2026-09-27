module("luci.controller.conntrack_icons", package.seeall)

function index()
	entry({"admin", "network", "conntrack", "conntrack_icons_config"}, cbi("conntrack_icons"), nil, nil).dependent = true
	entry({"admin", "network", "conntrack", "conntrack_custom_js"}, call("action_generate_js"), nil, nil)
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

function action_generate_js()
	local uci = require("luci.model.uci").cursor()
	luci.http.prepare_content("application/javascript")

	local rules = {}
	local bundles = {}

	uci:foreach("conntrack", "regex_icon", function(s)
		if s.pattern and s.icon then
			local raw_pattern, modifier = s.pattern:match("^/(.-)/(%a*)$")
			if raw_pattern then
				table.insert(rules, string.format("\t\t{ reg: new RegExp(%q, \"%s\"), icon: %q }", raw_pattern, modifier or "", s.icon))
			else
				table.insert(rules, string.format("\t\t{ reg: new RegExp(%q, \"i\"), icon: %q }", s.pattern, s.icon))
			end
		end
	end)

	uci:foreach("conntrack", "my_custom_icons", function(s)
		if s.name and s.svg_body then
			-- local safe_svg = nixio.bin.b64decode(s.svg_body):gsub("[\r\n\t]", " ")
			table.insert(bundles, string.format("\t\t%q: { body: %q, width: %d, height: %d }", 
				s.name, s.svg_body, tonumber(s.width) or 24, tonumber(s.height) or 24))
		end
	end)

	luci.http.write("window._customIconRules = [\n" .. table.concat(rules, ",\n") .. "\n];\n\n")
	luci.http.write("window._customIconBundles = {\n" .. table.concat(bundles, ",\n") .. "\n};\n\n")
	
	luci.http.write([[
(function() {
	if (window.Iconify && window._customIconBundles) {
		for (var name in window._customIconBundles) {
			if (window._customIconBundles.hasOwnProperty(name)) {
				var b = window._customIconBundles[name];
				var parts = name.split(':');
				if (parts.length === 2) {
					var prefix = parts[0];
					var localName = parts[1];
					var iconData = { icons: {} };
					iconData.icons[localName] = { body: atob(b.body), width: b.width, height: b.height };
					iconData.prefix = prefix;
					Iconify.addIcon(name, iconData.icons[localName]);
				}
			}
		}
	}
	
	document.addEventListener("DOMContentLoaded", function() {
	var previews = document.querySelectorAll(".iconify-live-preview");
	previews.forEach(function(span) {
		var iconName = span.getAttribute("data-icon");
		if (iconName && window.Iconify && typeof window.Iconify.getIcon === "function") {
			var iconObj = window.Iconify.getIcon(iconName);
			if (iconObj && iconObj.body) {
				var iw = 48, ih = 48;
				if (iconObj.width/iconObj.height > 2 ||
					iconObj.height/iconObj.width > 2) {
					iw = ""; ih = "";
				}
				span.innerHTML = '<svg xmlns="http://w3.org" viewBox="0 0 ' + (iconObj.width || 24) + ' ' + (iconObj.height || 24) + '" width="' + iw + '" height="' + ih + '" style="vertical-align:middle;">' + iconObj.body + '</svg>';
			}
		}
	});
	});

})();
]])
end

