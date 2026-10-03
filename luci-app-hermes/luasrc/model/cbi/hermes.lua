-- luci-app-hermes — CBI Model (18.06 compat)
local sys = require "luci.sys"

m = Map("hermes", "Hermes Agent",

	translate("Python-based AI Agent Gateway for OpenWrt routers."))

-- Status panel
m:section(SimpleSection).template = "hermes/status"

-- Basic settings
s = m:section(NamedSection, "main", "hermes", translate("Basic Settings"))
s.addremove = false
s.anonymous = true

o = s:option(Flag, "enabled", translate("Enable Service"))
o.rmempty = false

o = s:option(Value, "port", translate("Gateway Port"))
o.datatype = "port"
o.default = "3000"
o.rmempty = false

o = s:option(ListValue, "bind", translate("Listen Interface"))
o:value("lan", "LAN")
o:value("loopback", "Loopback")
o:value("all", translate("All Interfaces"))
o.default = "lan"

o = s:option(Value, "pty_port", translate("PTY Port"))
o.datatype = "port"
o.default = "3001"
o.rmempty = false

-- API settings
s2 = m:section(NamedSection, "main", "hermes", translate("API Settings"))
s2.addremove = false
s2.anonymous = true

o = s2:option(Value, "api_endpoint", translate("API Endpoint"))
o.default = "https://api.boos.lat/v1"
o.rmempty = false

o = s2:option(Value, "api_key", translate("API Key"))
o.password = true
o.rmempty = true

o = s2:option(Value, "model", translate("Model"))
o.default = "opus4.6"
o.rmempty = false

return m
