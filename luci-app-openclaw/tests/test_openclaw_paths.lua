package.path = "./luasrc/?.lua;./luasrc/?/?.lua;" .. package.path

local paths = require "openclaw.paths"

local function eq(actual, expected, label)
	if actual ~= expected then
		error(string.format("%s: expected %q, got %q", label, tostring(expected), tostring(actual)), 2)
	end
end

local function check(input, expected_base, expected_root)
	local derived = paths.derive_paths(input)
	eq(derived.install_path, expected_base, "install_path")
	eq(derived.oc_root, expected_root, "oc_root")
	eq(derived.node_base, expected_root .. "/node", "node_base")
	eq(derived.oc_global, expected_root .. "/global", "oc_global")
	eq(derived.oc_data, expected_root .. "/data", "oc_data")
end

check(nil, "/opt", "/opt/openclaw")
check("", "/opt", "/opt/openclaw")
check("/mnt/data", "/mnt/data", "/mnt/data/openclaw")
check("/mnt/data/openclaw", "/mnt/data", "/mnt/data/openclaw")
check("/mnt/data/", "/mnt/data", "/mnt/data/openclaw")

eq(paths.normalize_install_path("relative/path"), nil, "relative path rejected")
eq(paths.normalize_install_path("/mnt/data bad"), nil, "space rejected")
eq(paths.normalize_install_path("/"), nil, "root rejected")
eq(paths.is_safe_openclaw_root("/mnt/data/openclaw"), true, "safe root")
eq(paths.is_safe_openclaw_root("/mnt/data"), false, "unsafe root")

print("ok")
