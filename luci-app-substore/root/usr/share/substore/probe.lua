-- probe.lua — 节点网络探测（Ping / TCPing / URL 测试）（纯 Lua，无 luci.* 依赖）
-- luci-app-substore
-- 依赖 busybox 内置工具：ping、nc、wget、cut（OpenWrt / ImmortalWrt 均内置）

local util = require("substore.util")

local M = {}

M.TIMEOUT = 2 -- 每个目标的超时（秒）

-- shell 引号（%q 双引号转义），配合 safe_host 校验，双重防命令注入
local function q(s) return string.format("%q", s) end

-- 校验目标主机名/IP：仅允许 [A-Za-z0-9._-] 与冒号（IPv6），杜绝命令注入
local function safe_host(host)
	return type(host) == "string" and host ~= "" and host:match("^[%w%.%-%:]+$") ~= nil
end

local function safe_port(port)
	port = tonumber(port)
	if port and port >= 1 and port <= 65535 then return port end
	return nil
end

-- 解析 ping 输出的 time=xx.x ms
function M.parse_ping(out)
	out = out or ""
	local t = out:match("time=([%d%.]+)")
	return t and tonumber(t) or nil
end

-- 解析 shell 包装输出的 "起始uptime 结束uptime"（单位秒），返回毫秒延迟
function M.parse_delta(out)
	out = util.trim(out or "")
	local a, b = out:match("^(%d+%.?%d*)%s+(%d+%.?%d*)$")
	if a and b then
		local d = (tonumber(b) - tonumber(a)) * 1000
		if d >= 0 then return d end
	end
	return nil
end

-- URL 测试命令与解析（优先 curl 输出 time_total，回退 wget + uptime 差值）
local url_tool
local function detect_url_tool()
	if url_tool == nil then
		local f = io.popen("command -v curl >/dev/null 2>&1 && echo curl || echo wget")
		url_tool = util.trim(f and f:read("*a") or "wget")
		if f then f:close() end
	end
	return url_tool
end

local function build_url_job(url)
	if detect_url_tool() == "curl" then
		local cmd = "curl -s -o /dev/null --connect-timeout " .. M.TIMEOUT .. " --max-time " .. M.TIMEOUT
			.. " -w '%{http_code} %{time_total}' " .. q(url) .. " 2>/dev/null"
		return cmd, function(out)
			-- http_code=000 表示连接失败（拒绝/超时），其余状态码均说明对端可用 HTTP 通信
			local code, t = util.trim(out or ""):match("^(%d+)%s+([%d%.]+)$")
			t = tonumber(t)
			if code and code ~= "000" and t and t > 0 then return t * 1000 end
			return nil
		end
	end
	local cmd = "a=$(cut -d' ' -f1 /proc/uptime); if wget -q -T " .. M.TIMEOUT .. " -O /dev/null " .. q(url)
		.. " 2>/dev/null; then b=$(cut -d' ' -f1 /proc/uptime); echo \"$a $b\"; fi"
	return cmd, M.parse_delta
end

-- 单节点探测（串行，便于单测）。返回延迟 ms（number）或 nil（失败/超时）
function M.ping(server)
	server = util.trim(server or "")
	if not safe_host(server) then return nil end
	local f = io.popen("ping -c 1 -W " .. M.TIMEOUT .. " " .. q(server) .. " 2>/dev/null")
	local out = f and f:read("*a") or ""
	if f then f:close() end
	return M.parse_ping(out)
end

function M.tcping(server, port)
	server = util.trim(server or "")
	port = safe_port(port)
	if not safe_host(server) or not port then return nil end
	local cmd = "a=$(cut -d' ' -f1 /proc/uptime); if nc -z -w " .. M.TIMEOUT .. " " .. q(server) .. " " .. port
		.. " >/dev/null 2>&1; then b=$(cut -d' ' -f1 /proc/uptime); echo \"$a $b\"; fi"
	local f = io.popen(cmd)
	local out = f and f:read("*a") or ""
	if f then f:close() end
	return M.parse_delta(out)
end

function M.url_test(server, port)
	server = util.trim(server or "")
	port = safe_port(port)
	if not safe_host(server) or not port then return nil end
	local url = "http://" .. server .. ":" .. port .. "/"
	local cmd, parse = build_url_job(url)
	local f = io.popen(cmd)
	local out = f and f:read("*a") or ""
	if f then f:close() end
	return parse(out)
end

-- 为单个节点构造探测任务：返回 cmd, parse 或 nil
local function build_job(mode, server, port)
	server = util.trim(server or "")
	if not safe_host(server) then return nil end
	if mode == "ping" then
		return "ping -c 1 -W " .. M.TIMEOUT .. " " .. q(server) .. " 2>/dev/null", M.parse_ping
	elseif mode == "tcping" then
		port = safe_port(port)
		if not port then return nil end
		local cmd = "a=$(cut -d' ' -f1 /proc/uptime); if nc -z -w " .. M.TIMEOUT .. " " .. q(server) .. " " .. port
			.. " >/dev/null 2>&1; then b=$(cut -d' ' -f1 /proc/uptime); echo \"$a $b\"; fi"
		return cmd, M.parse_delta
	elseif mode == "url" then
		port = safe_port(port)
		if not port then return nil end
		return build_url_job("http://" .. server .. ":" .. port .. "/")
	end
	return nil
end

-- 批量探测：mode = "ping" | "tcping" | "url"
-- 并行启动所有子进程再统一读取，总耗时≈单节点超时，而非节点数×超时。
-- 返回结果数组 { name=, server=, port=, latency=number|nil }
function M.probe(nodes, mode)
	local jobs = {}
	for _, n in ipairs(nodes or {}) do
		local cmd, parse = build_job(mode, n.server, n.port)
		local f = cmd and io.popen(cmd) or nil
		jobs[#jobs + 1] = {
			f = f, parse = parse,
			name = n.name or "", server = n.server or "", port = n.port or "",
		}
	end
	local out = {}
	for _, j in ipairs(jobs) do
		local latency
		if j.f then
			local raw = j.f:read("*a") or ""
			j.f:close()
			latency = j.parse and j.parse(raw) or nil
		end
		out[#out + 1] = {
			name = j.name, server = j.server, port = j.port, latency = latency,
		}
	end
	return out
end

return M
