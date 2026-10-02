-- controller/admin/substore.lua — LuCI 路由注册（Lua 兼容模式）

module("luci.controller.admin.substore", package.seeall)

-- 返回列表页。err 非空时把错误带到列表页显示（§18：失败必须让用户看见，
-- 不能「失败了却看起来像成功」）。沿用 LuCI 既有的 query + 模板渲染，不引入新 framework。
local function back_to_list(err)
	local http = require("luci.http")
	local url = luci.dispatcher.build_url("admin", "services", "substore", "list")
	if err ~= nil and tostring(err) ~= "" then
		url = url .. "?err=" .. luci.util.urlencode(tostring(err))
	end
	http.redirect(url)
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

-- 表单字段统一取字符串。
--
-- LuCI 的 formvalue **不保证返回字符串**：同名字段提交多次时返回的是 table。
-- 依据上游 luci/http.lua 的 urldecode_message_body：
--     elseif what == parser.VALUE and name then
--         local val = msg.params[name]
--         if type(val) == "table" then val[#val+1] = ...
--         elseif val ~= nil then msg.params[name] = { val, ... }   -- ← 第二次出现变成 table
-- 而 formvalue 原样返回 msg.params[name]；上游 luadoc 也写着
-- "@return HTTP input value or table of all input value"。
--
-- 本项目多处直接对返回值 :gsub / util.trim / urlencode，遇到 table 会抛
-- "attempt to index a table value" → HTTP 500。攻击面不限于已登录用户：
-- /substore/download 是**无需登录**的入口（供 Passwall / OpenClash 拉取），
-- 对它 POST 一个重复的 token 字段即可触发。统一收敛后这类输入不再崩溃。
--
-- 取值语义：table 取最后一个（与「同名参数后者覆盖前者」的直觉一致），
-- nil 保持 nil（post_ok 依赖这一点区分「无 token」与「空 token」）。
--
-- 注意：必须定义在 post_ok **之前** —— Lua 的 local function 只捕获定义时
-- 已可见的局部变量，写在后面会让 post_ok 里的 fv 落到全局（nil）。
local function fv(http, key)
	local v = http.formvalue(key)
	if type(v) == "table" then v = v[#v] end
	if v == nil then return nil end
	return tostring(v)
end

-- post_ok 失败的原因，供调用方回显（§18：失败必须让用户看见）。
-- 每个请求是一个独立的 Lua 进程，不存在跨请求残留；同一进程内多次调用时
-- post_ok 成功会把它清空，因此不会把上一次的失败带进这一次。
local post_fail_msg = nil

-- POST 请求的 token 校验。
--
-- 上游 LuCI 渲染表单时，模板变量 `token` 就是 luci.dispatcher.context.authtoken
-- （modules/luci-lua-runtime/luasrc/template.lua 的 viewns 元表：
--    elseif key == "token" then return disp.context.authtoken），
-- 所以「提交的 token == authtoken」正是框架自己那套判定，
-- 不可能误拒合法表单 —— 合法表单提交的就是 authtoken。
--
-- 此前的判定是 `token ~= nil`：`token=`（空串）也能通过，等于没有校验。
-- 取不到 authtoken 时（老版本 LuCI / 非标准上下文）退回原判定，
-- 不能因为拿不到框架内部字段就把所有表单都拒掉。
local function post_ok()
	local http = require("luci.http")
	local tok = fv(http, "token")
	if tok == nil then
		post_fail_msg = "请求校验失败（缺少 token），请刷新页面后重试"
		return false
	end
	local ok, authtoken = pcall(function()
		return require("luci.dispatcher").context.authtoken
	end)
	if ok and type(authtoken) == "string" and authtoken ~= "" and tok ~= authtoken then
		post_fail_msg = "请求校验失败（token 不匹配），请刷新页面后重试"
		return false
	end
	post_fail_msg = nil
	return true
end

-- read cron fields from form, validate cron expression, return cron_enable cron_time
local function read_cron_fields()
	local http = require("luci.http")
	local core = require("substore.core")
	local cron_enable = fv(http, "cron_enable") or "0"
	local m = fv(http, "cron_min") or "0"
	local h = fv(http, "cron_hour") or "3"
	local dom = fv(http, "cron_dom") or "*"
	local mon = fv(http, "cron_mon") or "*"
	local dow = fv(http, "cron_dow") or "*"
	local cron_time = table.concat({m,h,dom,mon,dow}, " ")
	if not core.cron_time_valid(cron_time) then
		cron_enable = "0"
		cron_time = ""
	end
	if cron_enable ~= "1" then cron_enable = "0" end
	return cron_enable, cron_time
end

-- read subscription client type (User-Agent) from form, return ua string, err
--
-- 部分机场按 User-Agent 决定返回真实节点还是占位内容。表单提交的是
-- 「预设 key（ua_preset）+ 自定义文本（ua_custom）」，这里解析成最终要存的 UA。
-- 非法值必须回显（与规则校验同理）：静默存空会让用户以为设置生效了，
-- 实际更新出来的仍是占位节点。
local function read_ua_fields()
	local http = require("luci.http")
	local core = require("substore.core")
	local ua, err = core.resolve_user_agent(fv(http, "ua_preset"), fv(http, "ua_custom"))
	if not ua then return nil, err end
	return ua
end

-- read subscription level rules from form, return rules table, err
--
-- 第二个返回值是**用户可见**的校验错误。目前只有重命名规则的正则需要校验：
-- 非法 pattern 会被 node.rename_with_rules 里的 pcall 静默吞掉，用户看到的是
-- 「规则写了但没生效」。在这里拦下来，调用方用 back_to_list(err) 回显。
local function read_rules_fields()
	local http = require("luci.http")
	local core = require("substore.core")
	local node = require("substore.node")
	local proto_list = {}
	-- 协议清单来自 core.RULE_PROTOS，与表单模板共用一份（见该常量的说明）
	for _, p in ipairs(core.RULE_PROTOS) do
		if fv(http, "proto_filter_"..p) then proto_list[#proto_list+1]=p end
	end
	local rules_enable = fv(http, "rules_enable") or "0"
	if rules_enable ~= "1" then rules_enable = "0" end
	local rename_map = fv(http, "rename_map") or ""
	local vok, verr = node.validate_rename_map(rename_map)
	if not vok then return nil, verr end
	return {
		rules_enable = rules_enable,
		proto_filter = table.concat(proto_list, ","),
		keyword_include = fv(http, "keyword_include") or "",
		keyword_exclude = fv(http, "keyword_exclude") or "",
		dedup = fv(http, "dedup") or "0",
		rename_map = rename_map,
	}
end

function action_create()
	local http = require("luci.http")
	local core = require("substore.core")
	if post_ok() then
		local name = (fv(http, "name") or ""):gsub("^%s+", ""):gsub("%s+$", "")
		local url = (fv(http, "url") or ""):gsub("^%s+", ""):gsub("%s+$", "")
		local proxy_enable = fv(http, "proxy_enable") or "0"
		if proxy_enable ~= "1" then proxy_enable = "0" end
		local proxy = (fv(http, "proxy") or ""):gsub("^%s+", ""):gsub("%s+$", "")
		if name == "" or url == "" then
			return back_to_list("名称和 URL 不能为空")
		end
		local cron_enable, cron_time = read_cron_fields()
		-- 规则校验失败（如非法正则）必须回显，否则用户看到的是「规则没生效」
		local rules, rules_err = read_rules_fields()
		if not rules then return back_to_list(rules_err or "规则无效") end
		local user_agent, ua_err = read_ua_fields()
		if user_agent == nil then return back_to_list(ua_err or "订阅客户端类型无效") end
		local id, err = core.add(name, url, {
			proxy_enable = proxy_enable, proxy = proxy, user_agent = user_agent,
			cron_enable = cron_enable, cron_time = cron_time,
			rules_enable = rules.rules_enable, proto_filter = rules.proto_filter,
			keyword_include = rules.keyword_include, keyword_exclude = rules.keyword_exclude,
			dedup = rules.dedup, rename_map = rules.rename_map,
		})
		if not id then return back_to_list(err or "创建订阅失败") end
		core.write_cron()
	end
	back_to_list(post_fail_msg)
end

function action_save()
	local http = require("luci.http")
	local core = require("substore.core")
	if post_ok() then
		local id = fv(http, "id") or ""
		local name = (fv(http, "name") or ""):gsub("^%s+", ""):gsub("%s+$", "")
		local url = (fv(http, "url") or ""):gsub("^%s+", ""):gsub("%s+$", "")
		local proxy_enable = fv(http, "proxy_enable") or "0"
		if proxy_enable ~= "1" then proxy_enable = "0" end
		local proxy = (fv(http, "proxy") or ""):gsub("^%s+", ""):gsub("%s+$", "")
		if id == "" then return back_to_list("缺少订阅 ID") end
		if name == "" or url == "" then
			return back_to_list("名称和 URL 不能为空")
		end
		local cron_enable, cron_time = read_cron_fields()
		-- 规则校验失败（如非法正则）必须回显，否则用户看到的是「规则没生效」
		local rules, rules_err = read_rules_fields()
		if not rules then return back_to_list(rules_err or "规则无效") end
		local user_agent, ua_err = read_ua_fields()
		if user_agent == nil then return back_to_list(ua_err or "订阅客户端类型无效") end
		local ok, err = core.save_meta(id, {
			name = name, url = url, proxy_enable = proxy_enable, proxy = proxy,
			user_agent = user_agent,
			cron_enable = cron_enable, cron_time = cron_time,
			rules_enable = rules.rules_enable, proto_filter = rules.proto_filter,
			keyword_include = rules.keyword_include, keyword_exclude = rules.keyword_exclude,
			dedup = rules.dedup, rename_map = rules.rename_map,
		})
		if not ok then return back_to_list(err or "保存失败") end
		core.write_cron()
	end
	back_to_list(post_fail_msg)
end

function action_local_create()
	local http = require("luci.http")
	local core = require("substore.core")
	if post_ok() then
		local name = (fv(http, "name") or ""):gsub("^%s+", ""):gsub("%s+$", "")
		local content = fv(http, "content") or ""
		local local_mode = fv(http, "local_mode") or "text"
		-- 规则校验失败（如非法正则）必须回显，否则用户看到的是「规则没生效」
		local rules, rules_err = read_rules_fields()
		if not rules then return back_to_list(rules_err or "规则无效") end
		-- §19：空名称 / 空内容必须明确报错，不能无声创建无效订阅
		if name == "" then return back_to_list("名称不能为空") end
		if content == "" then return back_to_list("订阅内容不能为空") end
		local id, err = core.add_local(name, content, local_mode, {
			rules_enable = rules.rules_enable,
			proto_filter = rules.proto_filter,
			keyword_include = rules.keyword_include,
			keyword_exclude = rules.keyword_exclude,
			dedup = rules.dedup,
		})
		if not id then return back_to_list(err or "创建本地订阅失败") end
	end
	back_to_list(post_fail_msg)
end

function action_local_save()
	local http = require("luci.http")
	local core = require("substore.core")
	if post_ok() then
		local id = fv(http, "id") or ""
		local name = (fv(http, "name") or ""):gsub("^%s+", ""):gsub("%s+$", "")
		local content = fv(http, "content") or ""
		local local_mode = fv(http, "local_mode") or "text"
		-- 规则校验失败（如非法正则）必须回显，否则用户看到的是「规则没生效」
		local rules, rules_err = read_rules_fields()
		if not rules then return back_to_list(rules_err or "规则无效") end
		if id == "" then return back_to_list("缺少订阅 ID") end
		if name == "" then return back_to_list("名称不能为空") end
		if content == "" then return back_to_list("订阅内容不能为空") end
		local ok, err = core.save_meta(id, {
			name = name,
			raw_content = content,
			local_mode = local_mode,
			rules_enable = rules.rules_enable,
			proto_filter = rules.proto_filter,
			keyword_include = rules.keyword_include,
			keyword_exclude = rules.keyword_exclude,
			dedup = rules.dedup,
		})
		if not ok then return back_to_list(err or "保存失败") end
		-- 解析失败会写进 meta.error（列表页 Status 列可见），此处再明确提示一次
		local sok, serr = core.sync(id)
		if not sok then return back_to_list(serr or "解析订阅内容失败") end
	end
	back_to_list(post_fail_msg)
end

function action_delete()
	local http = require("luci.http")
	local core = require("substore.core")
	if post_ok() then
		-- §18：删除失败必须让用户看见。core.remove 对「非法 ID / 订阅不存在」
		-- 返回 false（或 false, err），此前返回值被整个丢弃 —— 用户点了删除，
		-- 页面正常跳回，订阅却还在，看起来像「删了但没生效」。
		--
		-- id 支持单个（行内删除按钮）或逗号分隔多个（勾选批量删除），
		-- 与节点页 action_node_delete 的 idx 同一套约定。订阅 id 是 "s%08x"，
		-- 不含逗号，切分不会切坏。
		local ids = {}
		for s in tostring(fv(http, "id") or ""):gmatch("[^,%s]+") do
			ids[#ids + 1] = s
		end
		if #ids == 0 then return back_to_list("未指定要删除的订阅") end
		local removed, first_err = 0, nil
		for _, id in ipairs(ids) do
			local ok, err = core.remove(id)
			if ok then
				removed = removed + 1
			elseif not first_err then
				first_err = err
			end
		end
		-- 部分失败也必须说：勾了 5 个只删掉 3 个却显示「成功」，
		-- 用户不会再回头管剩下那 2 个。
		--
		-- 只要**有订阅真的被删掉**就要重写 cron —— 部分失败的分支也不例外：
		-- 被删掉的订阅的 cron 行若留着，substore-cron.sh 会拿着已不存在的 id
		-- 反复执行，每次都以非 0 退出（见脚本末尾的 FAILED 判断），
		-- 在日志里刷失败、并让监控误报。
		if removed > 0 then core.write_cron() end
		if removed < #ids then
			if removed == 0 then
				return back_to_list(first_err or "删除失败：订阅不存在")
			end
			return back_to_list(string.format("已删除 %d 个，另有 %d 个删除失败",
				removed, #ids - removed))
		end
	end
	back_to_list(post_fail_msg)
end

-- 节点页返回链接：保留当前筛选参数
-- 返回节点页。err 非空时把失败原因带到页面显示（§18：失败必须让用户看见，
-- 不能「失败了却看起来像成功」）。与 back_to_list 同一套约定。
local function back_to_nodes(http, err)
	local id = fv(http, "id") or ""
	local qs = "?id=" .. luci.util.urlencode(id)
	for _, k in ipairs({ "proto", "keyword", "group", "sort", "desc" }) do
		local v = fv(http, k)
		if v and v ~= "" then qs = qs .. "&" .. k .. "=" .. luci.util.urlencode(v) end
	end
	if err ~= nil and tostring(err) ~= "" then
		qs = qs .. "&err=" .. luci.util.urlencode(tostring(err))
	end
	http.redirect(luci.dispatcher.build_url("admin", "services", "substore", "nodes") .. qs)
end

-- 单节点保存：表单 JSON 解析后经 merge_form_node 合并到原节点（保留 raw/tags 等非表单字段）
function action_node_save()
	local http = require("luci.http")
	local core = require("substore.core")
	local parser = require("substore.parser")
	if post_ok() then
		local id = fv(http, "id") or ""
		local idx = tonumber(fv(http, "idx") or "")
		local content = fv(http, "content") or ""
		local nodes = core.read_nodes(id)
		-- §18：任何一条失败路径都必须把原因带回页面。
		-- 原来只在成功分支里做事，其余情况一律静默重定向，
		-- 用户提交了坏数据却看到「已保存」的样子。
		if not idx or not nodes[idx] then
			back_to_nodes(http, "节点不存在或下标无效")
			return
		end
		if content == "" then
			back_to_nodes(http, "提交内容为空")
			return
		end
		local res, perr = parser.parse_local(content, "form")
		local newn = res and res.nodes and res.nodes[1]
		if not newn then
			back_to_nodes(http, perr or "表单数据解析失败")
			return
		end
		nodes[idx] = core.merge_form_node(nodes[idx], newn)
		if not core.write_nodes(id, nodes) then
			back_to_nodes(http, "写入节点数据失败")
			return
		end
		core.refresh_combos(id)
	end
	back_to_nodes(http, post_fail_msg)
end

-- 节点删除：idx 支持单个（行内删除按钮）或逗号分隔多个（勾选批量删除）
function action_node_delete()
	local http = require("luci.http")
	local core = require("substore.core")
	if post_ok() then
		local id = fv(http, "id") or ""
		local idx_param = fv(http, "idx") or ""
		local nodes = core.read_nodes(id)
		local idxs = {}
		for s in tostring(idx_param):gmatch("%d+") do
			idxs[#idxs + 1] = tonumber(s)
		end
		-- §18：什么都没删掉时必须说清楚，不能静默跳回列表。
		if #idxs == 0 then
			back_to_nodes(http, "未指定要删除的节点")
			return
		end
		-- 倒序删除，避免 table.remove 后下标偏移
		table.sort(idxs, function(a, b) return a > b end)
		local removed = false
		for _, i in ipairs(idxs) do
			if nodes[i] then
				table.remove(nodes, i)
				removed = true
			end
		end
		if not removed then
			back_to_nodes(http, "节点不存在或已被删除")
			return
		end
		if not core.write_nodes(id, nodes) then
			back_to_nodes(http, "写入节点数据失败")
			return
		end
		core.save_meta(id, { node_count = #nodes })
		core.refresh_combos(id)
	end
	back_to_nodes(http, post_fail_msg)
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
	local id = fv(http, "id") or ""
	local idx = tonumber(fv(http, "idx") or "")
	local group = util.trim(fv(http, "group") or "")
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
	-- 与 node_save / node_delete 一致：group 是组合订阅筛选与重命名规则的输入，
	-- 改了不同步组合的话，组合的下载链接会一直吐旧分组的数据。
	core.refresh_combos(id)
	http.write(util.json_encode({ ok = true }))
end

-- combo save: id empty create else edit, sources from src_id checkboxes and reuse rules
function action_combo_save()
	local http = require("luci.http")
	local core = require("substore.core")
	local util = require("substore.util")
	if post_ok() then
		local id = util.trim(fv(http, "id") or "")
		local name = (fv(http, "name") or ""):gsub("^%s+", ""):gsub("%s+$", "")
		local sources = {}
		for _, it in ipairs(core.list()) do
			if not it.combo and fv(http, "src_" .. it.id) then
				sources[#sources + 1] = it.id
			end
		end
		-- §18：此前名称留空、或一个来源都没勾选时，这里整段跳过、直接跳回列表 ——
		-- 用户填了表单却什么都没发生，页面上也没有任何提示。
		if name == "" then return back_to_list("名称不能为空") end
		-- 规则校验失败（如非法正则）必须回显，否则用户看到的是「规则没生效」
		local rules, rules_err = read_rules_fields()
		if not rules then return back_to_list(rules_err or "规则无效") end
		local o = {
			rules_enable = rules.rules_enable, proto_filter = rules.proto_filter,
			keyword_include = rules.keyword_include, keyword_exclude = rules.keyword_exclude,
			dedup = rules.dedup,
		}
		-- 返回值此前被整个丢弃：add_combo / save_combo 的失败（非法 ID、
		-- 未选来源、写入失败）一律静默。
		local nid, err
		if id == "" then
			nid, err = core.add_combo(name, sources, o)
		else
			nid, err = core.save_combo(id, name, sources, o)
		end
		if not nid then return back_to_list(err or "保存组合订阅失败") end
	end
	back_to_list(post_fail_msg)
end

function action_update()
	local http = require("luci.http")
	local core = require("substore.core")
	if post_ok() then
		local id = fv(http, "id") or ""
		local meta = core.get(id)
		if meta and meta["local"] then
			-- local subscription does not support auto update
			return
		end
		-- §18：订阅不存在（ID 拼错 / 已被删除）时此前静默跳回列表，
		-- 用户点了「更新」却看不到任何反馈。
		if not meta then return back_to_list("订阅不存在") end
		-- pcall 只保证「不抛异常」；core.sync 的失败是「返回 nil, err」而非抛错，
		-- 因此必须同时检查两层结果，否则失败永远不会写回列表状态。
		local ok, res, err = pcall(core.sync, id)
		if not ok then
			-- 抛异常：第二个返回值是错误信息
			core.save_meta(id, { error = tostring(res), last_update = os.time() })
		elseif not res then
			-- 正常返回但失败：第三个返回值是错误信息
			core.save_meta(id, { error = tostring(err or "更新失败"), last_update = os.time() })
		end
	end
	back_to_list(post_fail_msg)
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
	local id = util.trim(fv(http, "id") or "")
	local mode = util.trim(fv(http, "mode") or "")
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
	local proto = util.trim(fv(http, "proto") or "")
	local keyword = util.trim(fv(http, "keyword") or "")
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
	local token = util.trim(fv(http, "token") or "")
	local target = util.trim(fv(http, "target") or "ClashMeta")

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