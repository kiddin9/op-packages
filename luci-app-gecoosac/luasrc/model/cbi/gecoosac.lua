local fs = require "nixio.fs"

local DEFAULT_UPLOAD_DIR = "/tmp/gecoosac/upload/"
local DEFAULT_DB_DIR = "/etc/gecoosac/"
local DEFAULT_CRT_FILE = "/etc/gecoosac/tls/gecoosac.crt"
local DEFAULT_KEY_FILE = "/etc/gecoosac/tls/gecoosac.key"
local DEFAULT_PID_DIR = "/var/run/"

local function trim(value)
	return (value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function is_abs_path(value)
	return type(value) == "string" and value:match("^/") and not value:find("[%z\r\n]")
end

local function validate_abs_path(self, value)
	value = trim(value)
	if is_abs_path(value) then
		return value
	end

	return nil, translate("Expecting an absolute path")
end

local function is_upload_path(path)
	path = trim(path):gsub("/+$", "")
	return path == "/tmp/gecoosac/upload" or path:match("/gecoosac/upload$") ~= nil
end

local function remove_tree(path)
	local stat = fs.lstat and fs.lstat(path) or fs.stat(path)
	if not stat then
		return
	end

	if stat.type == "dir" then
		local iter = fs.dir(path)
		if iter then
			for entry in iter do
				if entry ~= "." and entry ~= ".." then
					remove_tree(path .. "/" .. entry)
				end
			end
		end
		fs.rmdir(path)
	else
		fs.unlink(path)
	end
end

local function clear_upload_dir(path)
	path = trim(path)
	if path == "" then
		path = DEFAULT_UPLOAD_DIR
	end

	path = path:gsub("/+$", "")
	if not is_abs_path(path) then
		return nil, translate("Expecting an absolute path")
	end

	local real = fs.realpath(path) or path
	real = real:gsub("/+$", "")
	if not is_upload_path(real) then
		return nil, translate("Only Gecoos upload directories can be cleared")
	end

	if fs.stat(real, "type") ~= "dir" then
		return true
	end

	local iter = fs.dir(real)
	if iter then
		for entry in iter do
			if entry ~= "." and entry ~= ".." then
				remove_tree(real .. "/" .. entry)
			end
		end
	end

	return true
end

if fs.access("/usr/bin/gecoosac") then
	m = Map("gecoosac", translate("Gecoos AC"), translate("Batch management Gecoos AP, Default password: admin") .. "<br>" .. translatef("The current AC version %s, only supports AP 7.6 and above.","2.2"))
else
	m = Map("gecoosac", translate("Gecoos AC"), translate("Batch management Gecoos AP, Default password: admin") .. "<br>" .. translate("The AC program does not exist, please check."))
end

m:section(SimpleSection).template  = "gecoosac/gecoosac_status"

s = m:section(TypedSection, "gecoosac", translate("Global Settings"))
s.addremove = false
s.anonymous = true

enable = s:option(Flag, "enabled", translate("Enabled AC"))
enable.rmempty = false

o = s:option(Value, "port", translate("Set interface port"))
o.placeholder = 60650
o.default     = 60650
o.datatype    = "port"
o.rmempty     = false

o = s:option(Flag, "isonlyoneprot", translate("Single Port Mode"), translate("Do not enable the independent management port, only use one port for management."))
o.default = 0
o.rmempty = false

o = s:option(Value, "m_port", translate("Set management port"))
o.placeholder = 8080
o.default     = 8080
o.datatype    = "port"
o:depends("isonlyoneprot", "0")

o = s:option(Flag, "https", translate("Enable HTTPS service"), translate("A certificate file must be specified, otherwise it will fail to start."))
o.default = 0
o:depends("isonlyoneprot", "0")

o = s:option(Value, "crt_file", translate("Specify crt certificate file"))
o.placeholder = DEFAULT_CRT_FILE
o.default     = DEFAULT_CRT_FILE
o.validate    = validate_abs_path
o:depends({isonlyoneprot = "0", https = "1"})

o = s:option(Value, "key_file", translate("Specify key certificate file"))
o.placeholder = DEFAULT_KEY_FILE
o.default     = DEFAULT_KEY_FILE
o.validate    = validate_abs_path
o:depends({isonlyoneprot = "0", https = "1"})

upload_dir = s:option(Value, "upload_dir", translate("Upload dir path"), translate("The path to upload AP upgrade firmware"))
upload_dir.placeholder = DEFAULT_UPLOAD_DIR
upload_dir.default     = DEFAULT_UPLOAD_DIR
upload_dir.rmempty     = false
upload_dir.validate    = validate_abs_path

db_dir = s:option(Value, "db_dir", translate("Database dir path"), translate("The path to store the config database"))
db_dir.placeholder = DEFAULT_DB_DIR
db_dir.default     = DEFAULT_DB_DIR
db_dir.rmempty     = false
db_dir.validate    = validate_abs_path

o = s:option(Value, "piddir", translate("PID dir path"), translate("The path to store the AC program pid file"))
o.placeholder = DEFAULT_PID_DIR
o.default     = DEFAULT_PID_DIR
o.rmempty     = false
o.validate    = validate_abs_path

o = s:option(ListValue, "lang", translate("Language"))
o:value("zh", translate("Chinese"))
o:value("en", translate("English"))
o.default = "zh"
o.rmempty = false

debug = s:option(Flag, "debug", translate("Debug Mode"))
debug.default = 0
debug.rmempty = false

showtip = s:option(Flag, "showtip", translate("Show IP Tip"), translate("Show the IP 6.7.8.9 setup tip when it is not configured."))
showtip.default = 1
showtip.rmempty = false

log = s:option(Flag, "log", translate("Enable Log"))
log.default = 0
log.rmempty = false

clear_upload = s:option(Button, "clear_upload", translate("Clear Upload Directory"))
clear_upload.inputstyle = "remove"
clear_upload.write = function(self, section)
	local path = upload_dir:formvalue(section) or upload_dir:cfgvalue(section) or DEFAULT_UPLOAD_DIR
	local ok, err = clear_upload_dir(path)
	if not ok then
		self.map.message = err or translate("Upload directory was not cleared")
	end
end

return m
