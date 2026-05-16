local M = {}

local function trim(value)
	return (value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

function M.normalize_install_path(value)
	local raw = trim(value)
	if raw == "" then raw = "/opt" end
	raw = raw:gsub("/+$", "")
	if raw == "" then raw = "/" end

	if raw:sub(1, 1) ~= "/" then return nil end
	if raw:match("[%s'\"`$;&|<>()]") then return nil end
	if raw == "/" or raw == "/proc" or raw:match("^/proc/") or
		raw == "/sys" or raw:match("^/sys/") or
		raw == "/dev" or raw:match("^/dev/") or
		raw == "/tmp" or raw:match("^/tmp/") or
		raw == "/var" or raw:match("^/var/") or
		raw == "/etc" or raw:match("^/etc/") or
		raw == "/usr" or raw:match("^/usr/") or
		raw == "/bin" or raw:match("^/bin/") or
		raw == "/sbin" or raw:match("^/sbin/") or
		raw == "/lib" or raw:match("^/lib/") or
		raw == "/rom" or raw:match("^/rom/") or
		raw == "/overlay" or raw:match("^/overlay/") then
		return nil
	end

	if raw:match("/openclaw$") then
		raw = raw:gsub("/openclaw$", "")
		if raw == "" then raw = "/" end
	end

	return raw
end

function M.derive_paths(value)
	local base = M.normalize_install_path(value) or "/opt"
	local root = (base == "/") and "/openclaw" or (base .. "/openclaw")
	return {
		install_path = base,
		oc_root = root,
		node_base = root .. "/node",
		oc_global = root .. "/global",
		oc_data = root .. "/data",
		config_file = root .. "/data/.openclaw/openclaw.json"
	}
end

function M.shellquote(value)
	return "'" .. tostring(value or ""):gsub("'", "'\\''") .. "'"
end

function M.is_safe_openclaw_root(value)
	if type(value) ~= "string" or not value:match("/openclaw$") then return false end
	if value == "/openclaw" or value == "/opt/openclaw" then return true end
	if value:match("^/mnt/[^/]+/openclaw$") or value:match("^/media/[^/]+/openclaw$") then return true end
	if value:match("^/srv/[^/]+/openclaw$") then return true end
	if value == "/overlay/upper/opt/openclaw" then return true end
	return false
end

return M
