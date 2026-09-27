-- controller/admin/substore.lua — LuCI 路由注册（Lua 兼容模式）

module("luci.controller.admin.substore", package.seeall)

local function back_to_list()
	local http = require("luci.http")
	http.redirect(luci.dispatcher.build_url("admin", "services", "substore", "list"))
end

function index()
	entry({"admin", "services", "substore"}, alias("admin", "services", "substore", "list"), nil)
	entry({"admin", "services", "substore", "list"}, template("substore/subscriptions"), _("Subscriptions"), 10)
	entry({"admin", "services", "substore", "form"}, template("substore/form"), nil)
	entry({"admin", "services", "substore", "localform"}, template("substore/local_form"), nil)
	entry({"admin", "services", "substore", "nodes"}, template("substore/nodes"), nil)
	entry({"admin", "services", "substore", "output"}, template("substore/output"), nil)
	entry({"admin", "services", "substore", "combo"}, template("substore/combo"), nil)
	entry({"admin", "services", "substore", "create"}, call("action_create"), nil)
	entry({"admin", "services", "substore", "save"}, call("action_save"), nil)
	entry({"admin", "services", "substore", "local_create"}, call("action_local_create"), nil)
	entry({"admin", "services", "substore", "local_save"}, call("action_local_save"), nil)
	entry({"admin", "services", "substore", "combo_save"}, call("action_combo_save"), nil)
	entry({"admin", "services", "substore", "node_edit"}, template("substore/node_edit"), nil)
	entry({"admin", "services", "substore", "node_save"}, call("action_node_save"), nil)
	entry({"admin", "services", "substore", "node_delete"}, call("action_node_delete"), nil)
	entry({"admin", "services", "substore", "node_set_group"}, call("action_node_set_group"), nil)
	entry({"admin", "services", "substore", "delete"}, call("action_delete"), nil)
	entry({"admin", "services", "substore", "update"}, call("action_update"), nil)
	entry({"admin", "services", "substore", "probe"}, call("action_probe"), nil)
	-- public download endpoint token based, no login, for Passwall OpenClash
	entry({"substore", "download"}, call("action_download"), nil)
end

local function post_ok()
	-- 拒绝缺失 CSRF token 的 POST
	local http = require("luci.http")
	return http.formvalue("token") ~= nil
end

-- read cron fields from form, validate cron expression, return cron_enable cron_time
local function read_cron_fields()
	local http = require("luci.http")
	local core = require("substore.core")
	local cron_enable = http.formvalue("cron_enable") or "0"
	local m = http.formvalue("cron_min") or "0"
	local h = http.formvalue("cron_hour") or "3"
	local dom = http.formvalue("cron_dom") or "*"
	local mon = http.formvalue("cron_mon") or "*"
	local dow = http.formvalue("cron_dow") or "*"
	local cron_time = table.concat({m,h,dom,mon,dow}, " ")
	if not core.cron_time_valid(cron_time) then
		cron_enable = "0"
		cron_time = ""
	end
	if cron_enable ~= "1" then cron_enable = "0" end
	return cron_enable, cron_time
end

-- read subscription level rules from form, return rules table
local function read_rules_fields()
	local http = require("luci.http")
	local proto_list = {}
	for _, p in ipairs({"vmess","vless","trojan","shadowsocks","ssr","hysteria2","tuic","hysteria","wireguard","socks"}) do
		if http.formvalue("proto_filter_"..p) then proto_list[#proto_list+1]=p end
	end
	local rules_enable = http.formvalue("rules_enable") or "0"
	if rules_enable ~= "1" then rules_enable = "0" end
	return {
		rules_enable = rules_enable,
		proto_filter = table.concat(proto_list, ","),
		keyword_include = http.formvalue("keyword_include") or "",
		keyword_exclude = http.formvalue("keyword_exclude") or "",
		dedup = http.formvalue("dedup") or "0",
		rename_map = http.formvalue("rename_map") or "",
	}
end

function action_create()
	local http = require("luci.http")
	local core = require("substore.core")
	if post_ok() then
		local name = (http.formvalue("name") or ""):gsub("^%s+", ""):gsub("%s+$", "")
		local url = (http.formvalue("url") or ""):gsub("^%s+", ""):gsub("%s+$", "")
		local proxy_enable = http.formvalue("proxy_enable") or "0"
		if proxy_enable ~= "1" then proxy_enable = "0" end
		local proxy = (http.formvalue("proxy") or ""):gsub("^%s+", ""):gsub("%s+$", "")
		if name ~= "" and url ~= "" then
			local cron_enable, cron_time = read_cron_fields()
			local rules = read_rules_fields()
			core.add(name, url, {
				proxy_enable = proxy_enable, proxy = proxy,
				cron_enable = cron_enable, cron_time = cron_time,
				rules_enable = rules.rules_enable, proto_filter = rules.proto_filter,
				keyword_include = rules.keyword_include, keyword_exclude = rules.keyword_exclude,
				dedup = rules.dedup, rename_map = rules.rename_map,
			})
			core.write_cron()
		end
	end
	back_to_list()
end

function action_save()
	local http = require("luci.http")
	local core = require("substore.core")
	if post_ok() then
		local id = http.formvalue("id") or ""
		local name = (http.formvalue("name") or ""):gsub("^%s+", ""):gsub("%s+$", "")
		local url = (http.formvalue("url") or ""):gsub("^%s+", ""):gsub("%s+$", "")
		local proxy_enable = http.formvalue("proxy_enable") or "0"
		if proxy_enable ~= "1" then proxy_enable = "0" end
		local proxy = (http.formvalue("proxy") or ""):gsub("^%s+", ""):gsub("%s+$", "")
		if name ~= "" and url ~= "" then
			local cron_enable, cron_time = read_cron_fields()
			local rules = read_rules_fields()
			core.save_meta(id, {
				name = name, url = url, proxy_enable = proxy_enable, proxy = proxy,
				cron_enable = cron_enable, cron_time = cron_time,
				rules_enable = rules.rules_enable, proto_filter = rules.proto_filter,
				keyword_include = rules.keyword_include, keyword_exclude = rules.keyword_exclude,
				dedup = rules.dedup, rename_map = rules.rename_map,
			})
			core.write_cron()
		end
	end
	back_to_list()
end

function action_local_create()
	local http = require("luci.http")
	local core = require("substore.core")
	if post_ok() then
		local name = (http.formvalue("name") or ""):gsub("^%s+", ""):gsub("%s+$", "")
		local content = http.formvalue("content") or ""
		local local_mode = http.formvalue("local_mode") or "text"
		local rules = read_rules_fields()
		if name ~= "" and content ~= "" then
			core.add_local(name, content, local_mode, {
				rules_enable = rules.rules_enable,
				proto_filter = rules.proto_filter,
				keyword_include = rules.keyword_include,
				keyword_exclude = rules.keyword_exclude,
				dedup = rules.dedup,
			})
		end
	end
	back_to_list()
end

function action_local_save()
	local http = require("luci.http")
	local core = require("substore.core")
	if post_ok() then
		local id = http.formvalue("id") or ""
		local name = (http.formvalue("name") or ""):gsub("^%s+", ""):gsub("%s+$", "")
		local content = http.formvalue("content") or ""
		local local_mode = http.formvalue("local_mode") or "text"
		local rules = read_rules_fields()
		if id ~= "" and name ~= "" and content ~= "" then
			core.save_meta(id, {
				name = name,
				raw_content = content,
				local_mode = local_mode,
				rules_enable = rules.rules_enable,
				proto_filter = rules.proto_filter,
				keyword_include = rules.keyword_include,
				keyword_exclude = rules.keyword_exclude,
				dedup = rules.dedup,
			})
			core.sync(id)
		end
	end
	back_to_list()
end

function action_delete()
	local http = require("luci.http")
	local core = require("substore.core")
	if post_ok() then
		core.remove(http.formvalue("id") or "")
		core.write_cron()
	end
	back_to_list()
end

-- 节点页返回链接：保留当前筛选参数
local function back_to_nodes(http)
	local id = http.formvalue("id") or ""
	local qs = "?id=" .. luci.util.urlencode(id)
	for _, k in ipairs({ "proto", "keyword", "group", "sort", "desc" }) do
		local v = http.formvalue(k)
		if v and v ~= "" then qs = qs .. "&" .. k .. "=" .. luci.util.urlencode(v) end
	end
	http.redirect(luci.dispatcher.build_url("admin", "services", "substore", "nodes") .. qs)
end

-- 单节点保存：表单 JSON 解析后经 merge_form_node 合并到原节点（保留 raw/tags 等非表单字段）
function action_node_save()
	local http = require("luci.http")
	local core = require("substore.core")
	local parser = require("substore.parser")
	if post_ok() then
		local id = http.formvalue("id") or ""
		local idx = tonumber(http.formvalue("idx") or "")
		local content = http.formvalue("content") or ""
		local nodes = core.read_nodes(id)
		if idx and nodes[idx] and content ~= "" then
			local res = parser.parse_local(content, "form")
			local newn = res and res.nodes and res.nodes[1]
			if newn then
				nodes[idx] = core.merge_form_node(nodes[idx], newn)
				if core.write_nodes(id, nodes) then
					core.refresh_combos(id)
				end
			end
		end
	end
	back_to_nodes(http)
end

-- 单节点删除
function action_node_delete()
	local http = require("luci.http")
	local core = require("substore.core")
	if post_ok() then
		local id = http.formvalue("id") or ""
		local idx = tonumber(http.formvalue("idx") or "")
		local nodes = core.read_nodes(id)
		if idx and nodes[idx] then
			table.remove(nodes, idx)
			if core.write_nodes(id, nodes) then
				core.save_meta(id, { node_count = #nodes })
				core.refresh_combos(id)
			end
		end
	end
	back_to_nodes(http)
end

-- 单节点分组快速设置（XHR，JSON 响应）
function action_node_set_group()
	local http = require("luci.http")
	local core = require("substore.core")
	local util = require("substore.util")
	http.prepare_content("application/json")
	if not post_ok() then
		http.write(util.json_encode({ ok = false, err = "forbidden" }))
		return
	end
	local id = http.formvalue("id") or ""
	local idx = tonumber(http.formvalue("idx") or "")
	local group = util.trim(http.formvalue("group") or "")
	local nodes = core.read_nodes(id)
	if not idx or not nodes[idx] then
		http.write(util.json_encode({ ok = false, err = "node not found" }))
		return
	end
	nodes[idx].group = group ~= "" and group or nil
	if not core.write_nodes(id, nodes) then
		http.write(util.json_encode({ ok = false, err = "write failed" }))
		return
	end
	http.write(util.json_encode({ ok = true }))
end

-- combo save: id empty create else edit, sources from src_id checkboxes and reuse rules
function action_combo_save()
	local http = require("luci.http")
	local core = require("substore.core")
	local util = require("substore.util")
	if post_ok() then
		local id = util.trim(http.formvalue("id") or "")
		local name = (http.formvalue("name") or ""):gsub("^%s+", ""):gsub("%s+$", "")
		local sources = {}
		for _, it in ipairs(core.list()) do
			if not it.combo and http.formvalue("src_" .. it.id) then
				sources[#sources + 1] = it.id
			end
		end
		if name ~= "" then
			local rules = read_rules_fields()
			local o = {
				rules_enable = rules.rules_enable, proto_filter = rules.proto_filter,
				keyword_include = rules.keyword_include, keyword_exclude = rules.keyword_exclude,
				dedup = rules.dedup,
			}
			if id == "" then
				core.add_combo(name, sources, o)
			else
				core.save_combo(id, name, sources, o)
			end
		end
	end
	back_to_list()
end

function action_update()
	local http = require("luci.http")
	local core = require("substore.core")
	if post_ok() then
		local id = http.formvalue("id") or ""
		local meta = core.get(id)
		if meta and meta["local"] then
			-- local subscription does not support auto update
			return
		end
		-- pcall fallback: parse or write error will not 500 the page, error saved to list status
		local ok, err = pcall(function()
			return core.sync(id)
		end)
		if not ok then
			core.save_meta(id, { error = tostring(err), last_update = os.time() })
		end
	end
	back_to_list()
end

-- node probe endpoint: POST id + mode ping tcping url + proto + keyword, return JSON
function action_probe()
	local http = require("luci.http")
	local core = require("substore.core")
	local node = require("substore.node")
	local util = require("substore.util")
	local probe = require("substore.probe")
	if not post_ok() then
		http.status(403, "Forbidden")
		http.prepare_content("text/plain; charset=utf-8")
		http.write("invalid token")
		return
	end
	local id = util.trim(http.formvalue("id") or "")
	local mode = util.trim(http.formvalue("mode") or "")
	if mode ~= "ping" and mode ~= "tcping" and mode ~= "url" then
		http.status(400, "Bad Request")
		http.prepare_content("text/plain; charset=utf-8")
		http.write("bad mode")
		return
	end
	local meta = core.get(id)
	if not meta then
		http.status(404, "Not Found")
		http.prepare_content("text/plain; charset=utf-8")
		http.write("not found")
		return
	end
	-- 与 nodes 页一致的过滤：按当前 proto / keyword 过滤后逐个探测
	local nodes = core.read_nodes(id)
	local proto = util.trim(http.formvalue("proto") or "")
	local keyword = util.trim(http.formvalue("keyword") or "")
	if proto ~= "" then nodes = node.filter(nodes, { proto = proto }) end
	if keyword ~= "" then nodes = node.filter(nodes, { keyword = keyword }) end
	nodes = node.sort(nodes, "name", false)

	local results = probe.probe(nodes, mode)
	local ok_count, sum = 0, 0
	for _, r in ipairs(results) do
		if r.latency then
			ok_count = ok_count + 1
			sum = sum + r.latency
		end
	end
	local avg = ok_count > 0 and math.floor(sum / ok_count + 0.5) or nil
	http.prepare_content("application/json; charset=utf-8")
	http.write(util.json_encode({
		ok = true, mode = mode, total = #results,
		ok_count = ok_count, avg = avg, results = results,
	}))
end

-- 公开下载端点：GET /substore/download?token=<token>&target=<format>
function action_download()
	local http = require("luci.http")
	local core = require("substore.core")
	local util = require("substore.util")
	local token = util.trim(http.formvalue("token") or "")
	local target = util.trim(http.formvalue("target") or "ClashMeta")

	local content, ct, filename, err = core.generate_link(token, target)
	if not content then
		http.status(404, "Not Found")
		http.prepare_content("text/plain; charset=utf-8")
		http.write(err or "not found")
		return
	end

	http.prepare_content(ct)
	-- 文件名白名单：剥离引号/换行/控制字符，防 HTTP 头注入
	local safe_name = (filename or "subscription.txt"):gsub("[^%w%-%._]", "_")
	http.header("Content-Disposition",
		"attachment; filename=\"" .. safe_name .. "\"")
	http.write(content)
end