-- output.lua — 订阅输出统一分发（所有 13 种目标格式）
-- luci-app-substore

local util = require("substore.util")
local node = require("substore.node")
local clash_meta = require("substore.output_clash_meta")
local output_uri = require("substore.output_uri")
local output_singbox = require("substore.output_singbox")
local output_v2ray = require("substore.output_v2ray")
local output_formats = require("substore.output_formats")

local M = {}

local function esc_yaml(s)
	s = tostring(s or "")
	s = s:gsub("\\", "\\\\"):gsub("\"", "\\\""):gsub("\n", "\\n")
	if s:find("[ :#{}[\],&*?|>'\"%@`]", 1, true) or s:match("^[-?]*:") then
		return '"' .. s .. '"'
	end
	return s
end

function M.to_clash_yaml(nodes)
	local out = {}
	out[#out + 1] = "proxies:"
	for _, n in ipairs(nodes) do
		local proto = n.proto or "vmess"
		local name = esc_yaml(n.name or "")
		out[#out + 1] = "- name: " .. name
		out[#out + 1] = "  type: " .. proto
		out[#out + 1] = "  server: " .. esc_yaml(n.server or "")
		out[#out + 1] = "  port: " .. tostring(n.port or 0)
		if n.uuid then out[#out + 1] = "  uuid: " .. esc_yaml(n.uuid) end
		if n.password then out[#out + 1] = "  password: " .. esc_yaml(n.password) end
		if n.method then out[#out + 1] = "  cipher: " .. esc_yaml(n.method) end
		if n.net then out[#out + 1] = "  network: " .. esc_yaml(n.net) end
		if n.security then out[#out + 1] = "  tls: " .. tostring(n.security ~= "none") end
		if n.sni then out[#out + 1] = "  sni: " .. esc_yaml(n.sni) end
	end
	out[#out + 1] = ""
	out[#out + 1] = "proxy-groups:"
	out[#out + 1] = "- name: ALL"
	out[#out + 1] = "  type: select"
	out[#out + 1] = "  proxies: [REJECT]"
	return table.concat(out, "\n")
end

function M.to_json(nodes)
	return util.json_encode(nodes)
end

function M.to_base64(nodes)
	local yaml = M.to_clash_yaml(nodes)
	return util.base64_encode(yaml)
end

-- 目标格式别名映射（兼容 ?target=X 的各类写法）
M.FORMAT_ALIASES = {
	clash       = "clashmeta",
	yaml        = "clashmeta",
	clashmeta   = "clashmeta",
	mihomo      = "clashmeta",
	stash       = "stash",
	surge       = "surge",
	surfboard   = "surfboard",
	surgemac    = "surgemac",
	loon        = "loon",
	egern       = "egern",
	shadowrocket = "shadowrocket",
	rocket      = "shadowrocket",
	qx          = "qx",
	quantumult  = "qx",
	singbox     = "singbox",
	sing_box    = "singbox",
	["sing-box"] = "singbox",
	v2ray       = "v2ray",
	v2rayuri    = "v2rayuri",
	v2ray_uri   = "v2rayuri",
	uri         = "v2rayuri",
	plain       = "plain",
	plainjson   = "plain",
	json        = "plain",
	base64      = "shadowrocket",
}

-- 目标格式的 HTTP Content-Type
local CONTENT_TYPES = {
	clashmeta = "text/plain; charset=utf-8",
	stash = "text/plain; charset=utf-8",
	surge = "text/plain; charset=utf-8",
	surfboard = "text/plain; charset=utf-8",
	surgemac = "text/plain; charset=utf-8",
	loon = "text/plain; charset=utf-8",
	egern = "text/plain; charset=utf-8",
	qx = "text/plain; charset=utf-8",
	shadowrocket = "text/plain; charset=utf-8",
	singbox = "application/json; charset=utf-8",
	v2ray = "application/json; charset=utf-8",
	v2rayuri = "text/plain; charset=utf-8",
	plain = "application/json; charset=utf-8",
}

function M.content_type_for(format)
	format = (format or "clash") or "clash"
	if type(format) ~= "string" then format = "clash" end
	local norm = M.FORMAT_ALIASES[format:lower():gsub("[-_%s]", "")]
	if not norm then norm = M.FORMAT_ALIASES[format:lower()] end
	return CONTENT_TYPES[norm]
end

-- 目标格式的下载文件名后缀
local FILENAME_EXT = {
	clashmeta = "yaml",
	stash = "yaml",
	surge = "conf",
	surfboard = "conf",
	surgemac = "conf",
	loon = "conf",
	egern = "conf",
	qx = "conf",
	shadowrocket = "txt",
	singbox = "json",
	v2ray = "json",
	v2rayuri = "txt",
	plain = "json",
}

function M.extension_for(format)
	format = (format or "clash") or "clash"
	if type(format) ~= "string" then format = "clash" end
	local norm = M.FORMAT_ALIASES[format:lower():gsub("[-_%s]", "")]
	if not norm then norm = M.FORMAT_ALIASES[format:lower()] end
	return FILENAME_EXT[norm] or "txt"
end

-- 统一分发：nodes → 目标格式字符串
function M.generate(nodes, format, options)
	format = (format or "clash") or "clash"
	if type(format) ~= "string" then format = "clash" end
	local norm = M.FORMAT_ALIASES[format:lower():gsub("[-_%s]", "")]
	if not norm then norm = M.FORMAT_ALIASES[format:lower()] end
	if not norm then return nil, "unsupported format: " .. tostring(format) end

	if norm == "clashmeta" then return clash_meta.generate(nodes, options) end
	if norm == "stash" then return output_formats.to_stash(nodes, options) end
	if norm == "surge" then return output_formats.to_surge(nodes, options) end
	if norm == "surfboard" then return output_formats.to_surfboard(nodes, options) end
	if norm == "surgemac" then return output_formats.to_surgemac(nodes, options) end
	if norm == "loon" then return output_formats.to_loon(nodes, options) end
	if norm == "egern" then return output_formats.to_egern(nodes, options) end
	if norm == "shadowrocket" then return output_uri.to_shadowrocket(nodes) end
	if norm == "qx" then return output_formats.to_qx(nodes, options) end
	if norm == "singbox" then return output_singbox.generate(nodes) end
	if norm == "v2ray" then return output_v2ray.generate(nodes) end
	if norm == "v2rayuri" then return output_uri.to_v2ray_uri(nodes) end
	if norm == "plain" then return output_formats.to_plain(nodes) end

	return nil, "unsupported format: " .. tostring(format)
end

return M