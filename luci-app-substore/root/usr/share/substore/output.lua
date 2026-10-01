-- output.lua — 订阅输出统一分发（所有目标格式的唯一注册点）
-- luci-app-substore

local clash_meta = require("substore.output_clash_meta")
local output_uri = require("substore.output_uri")
local output_singbox = require("substore.output_singbox")
local output_v2ray = require("substore.output_v2ray")
local output_formats = require("substore.output_formats")
local output_wgconf = require("substore.output_wireguard_conf")

local M = {}


-- 目标格式别名映射（兼容 ?target=X 的各类写法）
M.FORMAT_ALIASES = {
	-- Clash 原版：vless/hysteria2/tuic/wireguard 等原版不支持的协议会被过滤
	clash       = "clash",
	clashclassic = "clash",
	clashpremium = "clash",
	-- Clash.Meta / Mihomo
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
	-- wg-quick / AmneziaWG .conf
	wgconf      = "wgconf",
	wg          = "wgconf",
	wireguard   = "wgconf",
	amneziawg   = "wgconf",
	amnezia     = "wgconf",
	conf        = "wgconf",
	plain       = "plain",
	plainjson   = "plain",
	json        = "plain",
	base64      = "shadowrocket",
}

-- 目标格式的 HTTP Content-Type
local CONTENT_TYPES = {
	clash = "text/plain; charset=utf-8",
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
	wgconf = "text/plain; charset=utf-8",
	plain = "application/json; charset=utf-8",
}

-- 未指定 target 时的默认格式（保持历史行为：Clash.Meta）
local DEFAULT_FORMAT = "clashmeta"

function M.content_type_for(format)
	format = (format or DEFAULT_FORMAT) or DEFAULT_FORMAT
	if type(format) ~= "string" then format = DEFAULT_FORMAT end
	local norm = M.FORMAT_ALIASES[format:lower():gsub("[-_%s]", "")]
	if not norm then norm = M.FORMAT_ALIASES[format:lower()] end
	return CONTENT_TYPES[norm]
end

-- 目标格式的下载文件名后缀
local FILENAME_EXT = {
	clash = "yaml",
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
	wgconf = "conf",
	plain = "json",
}

function M.extension_for(format)
	format = (format or DEFAULT_FORMAT) or DEFAULT_FORMAT
	if type(format) ~= "string" then format = DEFAULT_FORMAT end
	local norm = M.FORMAT_ALIASES[format:lower():gsub("[-_%s]", "")]
	if not norm then norm = M.FORMAT_ALIASES[format:lower()] end
	return FILENAME_EXT[norm] or "txt"
end

-- UI 下拉使用的有序格式列表（单一数据源；模板由此渲染，避免多处硬编码不同步）
M.FORMAT_OPTIONS = {
	{ "clashmeta", "Clash.Meta / Mihomo" },
	{ "clash", "Clash" },
	{ "stash", "Stash" },
	{ "surge", "Surge" },
	{ "surfboard", "Surfboard" },
	{ "surgemac", "SurgeMac" },
	{ "loon", "Loon" },
	{ "egern", "Egern" },
	{ "qx", "Quantumult X" },
	{ "shadowrocket", "Shadowrocket" },
	{ "singbox", "sing-box" },
	{ "v2ray", "V2Ray" },
	{ "v2rayuri", "V2Ray URI" },
	{ "wgconf", "WireGuard / AmneziaWG .conf" },
	{ "plain", "Plain JSON" },
}

-- 统一分发：nodes → 目标格式字符串
function M.generate(nodes, format, options)
	-- 空串 / 纯空白等同于「未指定」。
	-- `?target=` 会传进来 ""，而 "" 在 Lua 里是**真值**，所以 `format or DEFAULT_FORMAT`
	-- 兜不住它，会一路落到 "unsupported format: "（冒号后面什么都没有）——
	-- 用户拿到的是一个说不出原因的错误页。控制器只在 nil 时兜底，覆盖不到空串。
	if type(format) ~= "string" then format = "" end
	format = format:match("^%s*(.-)%s*$") or ""
	if format == "" then format = DEFAULT_FORMAT end
	local norm = M.FORMAT_ALIASES[format:lower():gsub("[-_%s]", "")]
	if not norm then norm = M.FORMAT_ALIASES[format:lower()] end
	if not norm then return nil, "unsupported format: " .. tostring(format) end

	if norm == "clashmeta" then return clash_meta.generate(nodes, options) end
	if norm == "clash" then return output_formats.to_clash(nodes, options) end
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
	if norm == "wgconf" then return output_wgconf.generate(nodes, options) end
	if norm == "plain" then return output_formats.to_plain(nodes) end

	return nil, "unsupported format: " .. tostring(format)
end

return M