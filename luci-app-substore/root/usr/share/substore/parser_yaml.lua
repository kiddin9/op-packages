-- parser_yaml.lua — YAML 解析器：Clash/Sing-box → 统一节点模型（纯 Lua）
-- luci-app-substore

local util = require("substore.util")
local node = require("substore.node")

local M = {}

local proto_map = {
    vmess = "vmess",
    vless = "vless",
    trojan = "trojan",
    ss = "shadowsocks",
    shadowsocks = "shadowsocks",
    ssr = "ssr",
    http = "http",
    socks5 = "socks5",
}

local function split_lines(content)
    local out = {}
    for line in content:gmatch("[^\r\n]+") do
        out[#out + 1] = line
    end
    return out
end

local function trim_quotes(v)
    return v:gsub('^["\'](.*)["\']$', '%1')
end

local function parse_yaml_section(content, section_key)
    local lines = split_lines(content)
    local nodes = {}
    local current = nil
    local in_section = false
    local section_indent = 0
    local list_indent = nil

    for _, line in ipairs(lines) do
        local trimmed = util.trim(line)
        if trimmed == "" or trimmed:sub(1, 1) == "#" then
            -- skip empty and comments
        else
            local indent = line:match("^%s*") and #line:match("^%s*") or 0
            -- section start
            if trimmed:match("^" .. section_key .. ":%s*$") then
                in_section = true
                section_indent = indent
                current = nil
                list_indent = nil
            elseif in_section then
                if indent <= section_indent then
                    in_section = false
                    if current then
                        nodes[#nodes + 1] = current
                        current = nil
                    end
                else
                    local list_match = line:match("^%s*%-%s*(.*)$")
                    if list_match then
                        if current then
                            nodes[#nodes + 1] = current
                        end
                        current = {}
                        -- inline key:value on same line as -
                        local k, v = list_match:match("^([^:]+):%s*(.+)$")
                        if k then
                            current[util.trim(k)] = trim_quotes(util.trim(v))
                        end
                        list_indent = indent
                    elseif current and indent > (list_indent or section_indent) then
                        local k, v = trimmed:match("^([^:]+):%s*(.+)$")
                        if k then
                            k = util.trim(k)
                            v = util.trim(v)
                            v = trim_quotes(v)
                            -- ignore nested structures with empty value
                            if v ~= "" then
                                current[k] = v
                            end
                        end
                    end
                end
            end
        end
    end

    if current then
        nodes[#nodes + 1] = current
    end

    return nodes
end

local function normalize_clash_node(raw)
    if not raw.server or not raw.port then
        return nil
    end
    local proto = proto_map[raw.type or raw.proto] or "vmess"
    local node_data = {
        proto = proto,
        name = raw.name or raw.Name or (raw.server .. ":" .. tostring(raw.port or "")),
        server = raw.server,
        port = tonumber(raw.port),
        uuid = raw.uuid or raw.id,
        password = raw.password,
        method = raw.cipher or raw.method,
        net = raw.network or raw.net,
        security = raw.tls or raw.security,
        sni = raw.sni or raw.servername,
        alterId = tonumber(raw.alterId),
    }
    return node.normalize(node_data)
end

function M.parse_clash_yaml(content)
    local raw_nodes = parse_yaml_section(content, "proxies")
    -- also try outbounds for compatibility
    if #raw_nodes == 0 then
        raw_nodes = parse_yaml_section(content, "outbounds")
    end
    local result = {}
    for _, raw in ipairs(raw_nodes) do
        local n = normalize_clash_node(raw)
        if n then
            result[#result + 1] = n
        end
    end
    return result
end

local function normalize_singbox_node(raw)
    if not raw.server or not raw.server_port then
        return nil
    end
    local proto = raw.type
    -- map proto names
    if proto == "shadowsocks" then proto = "shadowsocks" end
    if proto == "ss" then proto = "shadowsocks" end
    local node_data = {
        proto = proto,
        name = raw.tag or (raw.server .. ":" .. tostring(raw.server_port or "")),
        server = raw.server,
        port = tonumber(raw.server_port),
        uuid = raw.uuid,
        password = raw.password,
        method = raw.method,
        security = raw.security,
        sni = raw.servername,
        net = raw.network,
    }
    return node.normalize(node_data)
end

function M.parse_singbox_yaml(content)
    local raw_nodes = parse_yaml_section(content, "outbounds")
    local result = {}
    for _, raw in ipairs(raw_nodes) do
        local n = normalize_singbox_node(raw)
        if n then
            result[#result + 1] = n
        end
    end
    return result
end

-- 通用解析：根据 section 自动选择
function M.parse(content)
    if not content or content == "" then
        return {}
    end
    if content:find("proxies:", 1, true) then
        return M.parse_clash_yaml(content)
    elseif content:find("outbounds:", 1, true) then
        -- 尝试 sing-box 格式
        local nodes = M.parse_singbox_yaml(content)
        if #nodes > 0 then
            return nodes
        end
        -- fallback to clash parser
        return M.parse_clash_yaml(content)
    end
    return {}
end

return M
