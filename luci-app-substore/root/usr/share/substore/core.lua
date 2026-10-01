-- core.lua — 订阅源元数据、节点数据与状态管理（纯 Lua，无 luci.* 依赖）
-- luci-app-substore

local util = require("substore.util")
local http = require("substore.http")
local parser = require("substore.parser")

local M = {}

M.version = "2.6.9"
M.DATA_DIR = "/etc/substore"
M.LIST_FILE = M.DATA_DIR .. "/subscriptions.json"
M.NODES_DIR = M.DATA_DIR .. "/nodes"
M.CRON_FILE = "/etc/cron.d/substore"

M.MAX_SIZE = 10 * 1024 * 1024 -- 10MB
M.TIMEOUT = 20

-- 「协议筛选」的可选协议，用的是节点模型里的**规范**协议名（node.normalize 的产物）。
-- 控制器（read_rules_fields）与三个表单模板共用这一份：两边各写一份的话，
-- 一旦漂移，勾选框就会生成一个永远匹配不到任何节点的 proto_filter，
-- 而症状是「勾了没用」—— 不会报错，最难查。
-- 不含 socks5：解析阶段已把它归一成 socks（见 parser.lua 的说明）。
M.RULE_PROTOS = { "vmess", "vless", "trojan", "shadowsocks", "ssr",
	"hysteria2", "tuic", "hysteria", "wireguard", "socks" }

local function id_is_valid(id)
	return type(id) == "string" and id ~= "" and id:match("^[A-Za-z0-9_%-]+$") ~= nil
end

-- 目录权限只收紧一次（每进程）。load() 每次读列表都会调用 ensure_dirs()，
-- 无条件 chmod 会让每次读取都多 fork 两个子进程。
local dirs_secured = false
function M.ensure_dirs()
	util.ensure_dir(M.DATA_DIR, "700")
	util.ensure_dir(M.NODES_DIR, "700")
	if not dirs_secured then
		dirs_secured = true
		-- mkdir -m 只对**本次新建**的目录生效；从旧版本升级上来的机器上目录已存在，
		-- 权限仍是当初按 umask 建的（通常 0755），所以这里显式再 chmod 一次。
		-- 目录里是订阅 URL、公开下载 token 与节点凭据，0700 只留 root。
		util.chmod(M.DATA_DIR, "700")
		util.chmod(M.NODES_DIR, "700")
	end
end

-- 读取订阅列表，返回 seq, items, err。
--
-- 必须区分「文件不存在 / 为空」（合法的空列表）与「文件存在但解析失败」
-- （内容损坏、被截断、磁盘错误）。后者若按空列表处理，后果是灾难性的：
-- M.add / M.add_local / M.add_combo 会在这个空表上追加一条然后整表写回，
-- 把用户已有的全部订阅抹掉，并且 _seq 归零后重新发出 s00000001 这种
-- 已经用过的 ID。因此损坏时必须显式报错，由调用方拒绝写入。
local function load()
	M.ensure_dirs()
	local raw = util.read_file(M.LIST_FILE)
	if not raw or raw == "" then return 0, {} end
	local data = util.json_decode(raw)
	if type(data) ~= "table" then
		return 0, {}, "订阅列表文件已损坏，无法解析：" .. M.LIST_FILE
	end
	local seq = tonumber(data._seq) or 0
	local items = type(data.items) == "table" and data.items or {}
	-- items 的每个值都必须是订阅元数据表。出现别的类型说明文件不是本程序写的
	-- （被手工编辑过 / 被截断后又被补全 / 磁盘错误）。此时不能原样返回：
	--   * M.list / M.get 里的 pairs(meta) 会抛
	--     "bad argument #1 to 'pairs' (table expected, got string)" ——
	--     订阅列表页直接 500；cron 路径更糟，core.list() 抛异常会让整轮同步
	--     在打印 "N ok, M failed" 之前中断，substore-cron.sh 据此判为成功。
	--   * 静默丢弃坏条目再返回也不行：调用方会以为列表完好，下一次 save 就把
	--     它们永久抹掉（与 H8 的整体损坏同一个陷阱）。
	-- 因此：返回能用的条目，同时带上损坏错误，让写路径（add / save_meta /
	-- write_nodes …）拒绝落盘，与上面的整体损坏走同一条路。
	local bad = false
	local clean = {}
	for id, meta in pairs(items) do
		if type(meta) == "table" then clean[id] = meta else bad = true end
	end
	if bad then
		return seq, clean, "订阅列表文件已损坏，存在非法条目：" .. M.LIST_FILE
	end
	return seq, items
end

local function save(seq, items)
	M.ensure_dirs()
	-- 0600：列表里有订阅 URL 与公开下载 token
	return util.atomic_write(M.LIST_FILE, util.json_encode({ _seq = seq, items = items }), "600")
end

-- 返回 arr, err。err 非空表示列表文件已损坏。
-- 整体无法解析时 arr 为空；只有部分条目非法时 arr 仍包含能用的条目
-- （坏条目已被 load 过滤掉，否则下面的 pairs(meta) 会抛异常）。
-- 追加第二个返回值是向后兼容的：调用方普遍写成 ipairs(core.list()) 或
-- local items = core.list()，都只取第一个值。
function M.list()
	local _, items, lerr = load()
	local arr = {}
	for id, meta in pairs(items) do
		local m = {}
		for k, v in pairs(meta) do m[k] = v end
		m.id = id
		arr[#arr + 1] = m
	end
	table.sort(arr, function(a, b) return (a.name or "") < (b.name or "") end)
	return arr, lerr
end

function M.get(id)
	if not id_is_valid(id) then return nil end
	local _, items = load()
	local meta = items[id]
	if not meta then return nil end
	local m = {}
	for k, v in pairs(meta) do m[k] = v end
	m.id = id
	return m
end

function M.add(name, url, opts)
	name = util.trim(name or "")
	url = util.trim(url or "")
	opts = opts or {}
	if name == "" or url == "" then return nil, "名称/URL 不能为空" end
	local seq, items, lerr = load()
	if lerr then return nil, lerr end
	seq = seq + 1
	local id = string.format("s%08x", seq)
	local cron_time = util.trim(opts.cron_time or "")
	if not M.cron_time_valid(cron_time) then cron_time = "" end
	items[id] = {
		name = name, url = url, enabled = true,
		node_count = 0, last_update = nil, error = "", format = "",
		token = util.rnd_hex(16),
		proxy_enable = (opts.proxy_enable == true or opts.proxy_enable == "1") and "1" or "0",
		proxy = util.trim(opts.proxy or ""),
		cron_enable = (opts.cron_enable == true or opts.cron_enable == "1") and cron_time ~= "",
		cron_time = cron_time,
		rules_enable = (opts.rules_enable == true or opts.rules_enable == "1") and true or false,
		proto_filter = util.trim(opts.proto_filter or ""),
		keyword_include = util.trim(opts.keyword_include or ""),
		keyword_exclude = util.trim(opts.keyword_exclude or ""),
		dedup = (opts.dedup == true or opts.dedup == "1") and "1" or "0",
		rename_map = opts.rename_map or "",
		["local"] = false,
		raw_content = "",
		local_mode = "text",
	}
	if not save(seq, items) then return nil, "写入失败" end
	return id
end

function M.add_local(name, raw_content, local_mode, opts)
	name = util.trim(name or "")
	raw_content = util.trim(raw_content or "")
	local_mode = local_mode or "text"
	opts = opts or {}
	if name == "" or raw_content == "" then return nil, "名称/内容 不能为空" end
	local seq, items, lerr = load()
	if lerr then return nil, lerr end
	seq = seq + 1
	local id = string.format("s%08x", seq)
	items[id] = {
		name = name, url = "", enabled = true,
		node_count = 0, last_update = nil, error = "", format = "",
		token = util.rnd_hex(16),
		proxy_enable = "0", proxy = "",
		cron_enable = false, cron_time = "",
		rules_enable = (opts.rules_enable == true or opts.rules_enable == "1") and true or false,
		proto_filter = util.trim(opts.proto_filter or ""),
		keyword_include = util.trim(opts.keyword_include or ""),
		keyword_exclude = util.trim(opts.keyword_exclude or ""),
		dedup = (opts.dedup == true or opts.dedup == "1") and "1" or "0",
		rename_map = opts.rename_map or "",
		["local"] = true,
		raw_content = raw_content,
		local_mode = local_mode,
	}
	if not save(seq, items) then return nil, "写入失败" end
	-- 立即解析一次
	M.sync(id)
	return id
end

-- 获取订阅的下载 token；若不存在则生成并持久化
function M.ensure_token(id)
	if not id_is_valid(id) then return nil end
	local seq, items, lerr = load()
	if lerr then return nil end
	local meta = items[id]
	if not meta then return nil end
	if not meta.token or meta.token == "" then
		meta.token = util.rnd_hex(16)
		save(seq, items)
	end
	return meta.token
end

-- 依据 token 查找订阅 ID
local function id_by_token(token)
	if type(token) ~= "string" or token == "" then return nil end
	local _, items = load()
	for id, meta in pairs(items) do
		if meta.token == token then return id end
	end
	return nil
end

-- 生成订阅下载内容：按 target 格式转换节点。返回 content, content_type, filename, err
function M.generate_link(token, target, opts)
	opts = opts or {}
	local id = id_by_token(token)
	if not id then return nil, nil, nil, "无效的订阅 token" end
	local meta = M.get(id)
	local nodes = M.read_nodes(id)
	if #nodes == 0 then return nil, nil, nil, "暂无可用的节点（请先更新订阅）" end

	local output = require("substore.output")
	local content, err = output.generate(nodes, target, opts)
	if not content then return nil, nil, nil, err or "无法生成目标格式" end

	local ct = opts.content_type or output.content_type_for(target) or "text/plain; charset=utf-8"
	local ext = output.extension_for(target) or "txt"
	local base = (meta and meta.name and meta.name ~= "") and meta.name or id
	local filename = base .. "." .. ext
	return content, ct, filename, nil
end

-- save_meta 补丁里的「清除」哨兵值。
-- Lua 的 pairs 永远不会产出值为 nil 的键，所以补丁表里写 `k = nil` 等于什么都没写，
-- 调用方无法表达「把这个字段删掉」。需要清除时传 M.CLEAR，save_meta 会还原成 nil。
M.CLEAR = setmetatable({}, { __tostring = function() return "substore.CLEAR" end })

function M.save_meta(id, patch)
	if not id_is_valid(id) then return false, "非法 ID" end
	local seq, items, lerr = load()
	if lerr then return false, lerr end
	local meta = items[id]
	if not meta then return false, "订阅不存在" end
	for k, v in pairs(patch or {}) do
		if v == nil or v == M.CLEAR then meta[k] = nil else meta[k] = v end
	end
	return save(seq, items)
end

function M.remove(id)
	if not id_is_valid(id) then return false end
	local seq, items, lerr = load()
	if lerr then return false, lerr end
	if not items[id] then return false end
	items[id] = nil
	save(seq, items)
	os.remove(M.nodes_file(id))
	return true
end

function M.nodes_file(id)
	return M.NODES_DIR .. "/" .. id .. ".json"
end

function M.write_nodes(id, nodes)
	M.ensure_dirs()
	-- 0600：节点文件里有 uuid / 密码 / 私钥等全部凭据
	return util.atomic_write(M.nodes_file(id), util.json_encode(nodes), "600")
end

function M.read_nodes(id)
	if not id_is_valid(id) then return {} end
	local raw = util.read_file(M.nodes_file(id))
	if not raw or raw == "" then return {} end
	local nodes = util.json_decode(raw)
	if type(nodes) ~= "table" then return {} end
	return nodes
end

-- 解析 subscription-userinfo 响应头（upload/download/total/expire），返回数字表或 nil
function M.parse_userinfo(s)
	if type(s) ~= "string" or s == "" then return nil end
	local u = {}
	for k, v in s:gmatch("([%w_%-]+)%s*=%s*([^;]+)") do
		local key = k:lower()
		if key == "upload" or key == "download" or key == "total" or key == "expire" then
			local num = tonumber(util.trim(v))
			if num then u[key] = num end
		end
	end
	if next(u) == nil then return nil end
	return u
end

-- 下载并解析订阅，写入节点文件并更新状态。成功返回 node_count，失败返回 nil, err
function M.sync(id)
	local log = function(msg) os.execute("logger -t luci-app-substore " .. util.shq(msg)) end
	log("Sync start id="..tostring(id))
	local meta = M.get(id)
	if not meta then log("Sync fail: subscription not found"); return nil, "订阅不存在" end
	-- 组合订阅：无下载源，直接重算合并节点
	if M.is_combo(meta) then
		log("Sync combo refresh")
		local cnt, cerr = M.combo_refresh(id)
		if not cnt then log("Combo refresh fail: " .. tostring(cerr)) end
		return cnt, cerr
	end
	-- 本地订阅：直接解析 raw_content
	if meta["local"] then
		log("Sync local subscription")
		local content = meta.raw_content or ""
		if content == "" then
			-- 失败路径一律不改 node_count：磁盘上的旧节点仍在，订阅链接仍在下发（§35）
			M.save_meta(id, { error = "本地订阅内容为空", last_update = os.time() })
			return nil, "本地订阅内容为空"
		end
		local res, perr = parser.parse_local(content, meta.local_mode or "text")
		if not res or not res.nodes then
			log("Parse local fail: " .. tostring(perr))
			M.save_meta(id, { error = perr or "本地解析失败", last_update = os.time() })
			return nil, perr or "本地解析失败"
		end
		log("Parse local ok nodes="..#res.nodes)
		local nodes = M.apply_rules(res.nodes, meta)
		if not M.write_nodes(id, nodes) then
			M.save_meta(id, { error = "写入节点数据失败", last_update = os.time() })
			return nil, "写入节点数据失败"
		end
		local ok = M.save_meta(id, {
			node_count = #nodes, format = res.format or "local", error = "", last_update = os.time(),
		})
		if not ok then return nil, "更新状态失败" end
		M.refresh_combos(id)
		return #nodes
	end
	if not meta.url or meta.url == "" then log("Sync fail: no URL"); return nil, "无订阅 URL" end

	-- 订阅代理：开启时代理地址必须有效。无效就明确失败——
	-- 静默直连会让用户以为流量走了代理，属于必须避免的 silent fallback（§12）。
	local proxy = ""
	if meta.proxy_enable == true or meta.proxy_enable == "1" then
		local p, perr = http.parse_proxy(meta.proxy or "")
		if not p or p == "" then
			local msg = perr or "代理地址为空"
			log("Proxy invalid: " .. tostring(msg))
			M.save_meta(id, { error = "代理配置无效: " .. tostring(msg), last_update = os.time() })
			return nil, "代理配置无效: " .. tostring(msg)
		end
		proxy = p
	end
	-- 日志不记录代理凭据（§39）
	if proxy ~= "" then log("Using proxy " .. http.redact_proxy(proxy)) end

	local content, headers, err = http.download(meta.url, { max_size = M.MAX_SIZE, timeout = M.TIMEOUT, proxy = proxy })
	if not content then
		-- 下载工具的报错可能回显含凭据的 URL，写日志与入库前先抹掉（§39）
		local safe_err = http.scrub_credentials(err or "下载失败")
		log("Download fail: " .. safe_err)
		M.save_meta(id, { error = safe_err, last_update = os.time() })
		return nil, safe_err
	end
	log("Download ok size="..#content)

	local ui = M.parse_userinfo(headers and headers["subscription-userinfo"])
	if ui then log("Userinfo total="..tostring(ui.total).." expire="..tostring(ui.expire)) end

	local res, perr = parser.parse(content)
	if not res or not res.nodes then
		log("Parse fail: " .. tostring(perr))
		M.save_meta(id, { error = perr or "解析失败", last_update = os.time() })
		return nil, perr or "解析失败"
	end
	log("Parse ok nodes="..#res.nodes)

	local nodes = M.apply_rules(res.nodes, meta)
	if not M.write_nodes(id, nodes) then
		M.save_meta(id, { error = "写入节点数据失败", last_update = os.time() })
		return nil, "写入节点数据失败"
	end

	local ok = M.save_meta(id, {
		node_count = #nodes, format = res.format, error = "", last_update = os.time(),
		-- 机场不再下发 subscription-userinfo 时必须把旧数值清掉，
		-- 否则列表页会一直显示早已过期的流量/到期时间。用 M.CLEAR 表达「清除」。
		upload = (ui and ui.upload) or M.CLEAR,
		download = (ui and ui.download) or M.CLEAR,
		total = (ui and ui.total) or M.CLEAR,
		expire = (ui and ui.expire) or M.CLEAR,
	})
	if not ok then return nil, "更新状态失败" end
	-- 源订阅更新后，刷新引用它的组合订阅
	M.refresh_combos(id)
	return #nodes
end

-- 对节点应用订阅级规则（rules_enable 为真时生效）；纯函数，便于测试
function M.apply_rules(nodes, meta)
	meta = meta or {}
	if not (meta.rules_enable == true or meta.rules_enable == "1") then return nodes end
	local node_mod = require("substore.node")
	local rules = {
		proto_filter = meta.proto_filter or "",
		keyword_include = meta.keyword_include or "",
		keyword_exclude = meta.keyword_exclude or "",
		dedup = meta.dedup or "0",
		rename_map = meta.rename_map or "",
	}
	return node_mod.apply_rules(nodes, rules)
end

-- ---------- 单节点编辑 ----------

-- 表单管理的字段集合：合并时先从原节点清除，再用表单值覆盖，未出现在表单中的字段（raw/tags 等）保留
local FORM_KEYS = {
	name = true, group = true, server = true, port = true, password = true,
	cipher = true, method = true, protocol = true, obfs = true,
	["obfs-param"] = true, obfs_param = true, ["protocol-param"] = true, protocol_param = true,
	udp = true, uuid = true, alterId = true, net = true, network = true,
	headerType = true, path = true, host = true, sni = true, tls = true,
	["skip-cert-verify"] = true, skip_cert_verify = true, security = true, flow = true,
	["obfs-password"] = true, obfs_password = true,
	["private-key"] = true, private_key = true, ["peer-public-key"] = true, peer_public_key = true,
	["public-key"] = true, public_key = true, ["pre-shared-key"] = true, preshared_key = true, 
	ip = true, ipv6 = true, ["allowed-ips"] = true, allowed_ips = true,
	reserved = true, ["persistent-keepalive"] = true, persistent_keepalive = true,
	["listen-port"] = true, listen_port = true,
	mtu = true, dns = true, ["amnezia-wg-option"] = true,
	-- socks / http 的用户名。必须在表里：下面的 merge_form_node 先按 FORM_KEYS
	-- 清空原节点再套用提交值，不在表里的字段会保留旧值——用户在表单里清空用户名
	-- 也删不掉（collectNodes 会略过空值），等于改不动。
	username = true,
}

-- FORM_KEYS 里同一个语义的多种写法。表单只渲染其中的规范写法，别名必须跟随规范
-- 写法一起清空：解析器产出的就是别名（parser_clash_yaml 写 skip_cert_verify、
-- parser_json_config 与 parser.lua 写 obfs_param / protocol_param），残留的别名
-- 仍会被输出模块读到，表现为「关不掉」——例如 build_tls 在 security 为 "none"
-- 时还会退回 n.tls，output_formats.surge_line 同理，于是用户把 vmess 的 TLS
-- 关掉之后 Surge 输出里依然是 tls=true。
local FORM_ALIASES = {
	["obfs_param"] = "obfs-param",
	["protocol_param"] = "protocol-param",
	["skip_cert_verify"] = "skip-cert-verify",
	["obfs_password"] = "obfs-password",
	["private_key"] = "private-key",
	["public_key"] = "public-key",
	["peer-public-key"] = "public-key",
	["peer_public_key"] = "public-key",
	["preshared_key"] = "pre-shared-key",
	["allowed_ips"] = "allowed-ips",
	["persistent_keepalive"] = "persistent-keepalive",
	["listen_port"] = "listen-port",
	["network"] = "net",
	-- normalize 把 tls 归一到 security，两者是同一语义的两种写法
	["tls"] = "security",
	-- shadowsocks 用 method、vmess/ssr 用 cipher，parse_local 双向互为别名
	["method"] = "cipher",
	["cipher"] = "method",
}

-- 合并表单节点到原节点。
--
-- 只有「该协议的表单确实渲染过」的字段才允许被覆盖（含被清空）：表单按
-- node.PROTO_FIELDS[proto] 渲染，未渲染的字段根本提交不上来，把它们一并清空
-- 就等于用空值覆盖原值 —— vmess 的 security、hysteria2/tuic 的 security、
-- WireGuard 的 dns 都是这样被静默抹掉的（详见 node.PROTO_FIELDS 的注释）。
-- 别名（FORM_ALIASES）跟随其规范写法一起清空，避免残留值「关不掉」。
--
-- 协议未知（不在 PROTO_FIELDS 里）时退回「清空全部表单字段」的旧行为：
-- 那时无从判断表单渲染了什么，清空虽然可能丢字段，但至少不会留下用户改不动的旧值。
function M.merge_form_node(orig, formnode)
	local node_mod = require("substore.node")
	local out = {}
	for k, v in pairs(orig or {}) do out[k] = v end
	local fields = type(formnode) == "table" and node_mod.PROTO_FIELDS[formnode.proto] or nil
	local old_fields = type(orig) == "table" and node_mod.PROTO_FIELDS[orig.proto] or nil
	-- 原协议未知（或原节点没有 proto）时不做「只清渲染字段」的裁剪：那种情况下
	-- 无从判断原节点里哪些字段是本协议的，退回到清空全部表单字段的旧行为。
	if fields and (orig == nil or orig.proto == nil or old_fields) then
		local rendered = {}
		for _, k in ipairs(fields) do rendered[k] = true end
		-- 协议被改过时，旧协议的字段也要清掉（vmess 改成 trojan 不该留着 uuid）。
		-- 协议没变时 old_fields == fields，是同一个集合，无副作用。
		for _, k in ipairs(old_fields or {}) do rendered[k] = true end
		for _, k in ipairs(node_mod.FORM_ALWAYS_FIELDS) do rendered[k] = true end
		for k in pairs(FORM_KEYS) do
			-- 先看字段本身是否被渲染；只有「别名」才回退到它的规范写法。
			-- 顺序不能反：method 与 cipher 互为别名，若一律先查别名表，
			-- shadowsocks 渲染的 method 会被判成「cipher 没渲染」而不清空。
			local canon = rendered[k] and k or (FORM_ALIASES[k] or k)
			if rendered[canon] then out[k] = nil end
		end
	else
		for k in pairs(FORM_KEYS) do out[k] = nil end
	end
	for k, v in pairs(formnode or {}) do
		if k ~= "type" then out[k] = v end
	end
	return out
end

-- ---------- 组合订阅（combo） ----------

-- 判断是否为组合订阅
function M.is_combo(meta)
	return meta ~= nil and (meta.combo == true or type(meta.sources) == "table")
end

-- 物化组合节点：按 sources 顺序合并各源节点，再应用组合自身的规则（复用 per-sub 规则字段）
function M.combo_nodes(meta)
	if type(meta) ~= "table" then return {} end
	local srcs = type(meta.sources) == "table" and meta.sources or {}
	local merged = {}
	for _, sid in ipairs(srcs) do
		local ns = M.read_nodes(sid)
		for _, n in ipairs(ns) do merged[#merged + 1] = n end
	end
	return M.apply_rules(merged, meta)
end

-- 重新计算组合节点并落盘，更新状态。成功返回 node_count，失败返回 nil, err
function M.combo_refresh(id)
	if not id_is_valid(id) then return nil, "非法 ID" end
	local meta = M.get(id)
	if not meta then return nil, "订阅不存在" end
	local srcs = type(meta.sources) == "table" and meta.sources or {}
	if #srcs == 0 then
		M.save_meta(id, { error = "请选择至少一个订阅", node_count = 0, last_update = os.time() })
		return nil, "请选择至少一个订阅"
	end
	local nodes = M.combo_nodes(meta)
	if not M.write_nodes(id, nodes) then
		M.save_meta(id, { error = "写入节点数据失败", last_update = os.time() })
		return nil, "写入节点数据失败"
	end
	M.save_meta(id, { node_count = #nodes, error = "", last_update = os.time() })
	return #nodes
end

-- 源订阅更新后刷新所有引用它的组合，避免组合停留旧数据
function M.refresh_combos(src_id)
	if not src_id then return end
	for _, it in ipairs(M.list()) do
		local srcs = type(it.sources) == "table" and it.sources or {}
		for _, sid in ipairs(srcs) do
			if sid == src_id then
				M.combo_refresh(it.id)
				break
			end
		end
	end
end

-- 创建组合订阅（无 URL，cron/代理禁用）；成功后物化节点。返回 id 或 nil, err
function M.add_combo(name, sources, opts)
	name = util.trim(name or "")
	opts = opts or {}
	if name == "" then return nil, "名称不能为空" end
	local srcs = {}
	if type(sources) == "table" then
		for _, s in ipairs(sources) do
			s = util.trim(tostring(s or ""))
			if s ~= "" and id_is_valid(s) then srcs[#srcs + 1] = s end
		end
	end
	if #srcs == 0 then return nil, "请选择至少一个订阅" end
	local seq, items, lerr = load()
	if lerr then return nil, lerr end
	seq = seq + 1
	local id = string.format("s%08x", seq)
	items[id] = {
		name = name, url = "", enabled = true, combo = true, sources = srcs,
		node_count = 0, last_update = nil, error = "", format = "",
		token = util.rnd_hex(16),
		proxy_enable = "0", proxy = "",
		cron_enable = false, cron_time = "",
		rules_enable = (opts.rules_enable == true or opts.rules_enable == "1") and true or false,
		proto_filter = util.trim(opts.proto_filter or ""),
		keyword_include = util.trim(opts.keyword_include or ""),
		keyword_exclude = util.trim(opts.keyword_exclude or ""),
		dedup = (opts.dedup == true or opts.dedup == "1") and "1" or "0",
		rename_map = opts.rename_map or "",
	}
	if not save(seq, items) then return nil, "写入失败" end
	M.combo_refresh(id)
	return id
end

-- 编辑组合订阅：更新名称/来源/规则后重算物化节点。成功返回 node_count，失败返回 nil, err
function M.save_combo(id, name, sources, opts)
	if not id_is_valid(id) then return nil, "非法 ID" end
	name = util.trim(name or "")
	if name == "" then return nil, "名称不能为空" end
	local srcs = {}
	if type(sources) == "table" then
		for _, s in ipairs(sources) do
			s = util.trim(tostring(s or ""))
			if s ~= "" and id_is_valid(s) and s ~= id then srcs[#srcs + 1] = s end
		end
	end
	if #srcs == 0 then return nil, "请选择至少一个订阅" end
	opts = opts or {}
	M.save_meta(id, {
		name = name, sources = srcs,
		rules_enable = (opts.rules_enable == true or opts.rules_enable == "1") and true or false,
		proto_filter = util.trim(opts.proto_filter or ""),
		keyword_include = util.trim(opts.keyword_include or ""),
		keyword_exclude = util.trim(opts.keyword_exclude or ""),
		dedup = (opts.dedup == true or opts.dedup == "1") and "1" or "0",
		rename_map = opts.rename_map or "",
	})
	return M.combo_refresh(id)
end

-- 合并多个订阅的节点
function M.merge(ids, opts)
	opts = opts or {}
	local all = {}
	local node_mod = require("substore.node")
	for _, id in ipairs(ids) do
		local nodes = M.read_nodes(id)
		for _, n in ipairs(nodes) do
			all[#all + 1] = n
		end
	end
	-- 规则已在各订阅 sync 时按订阅级配置应用；此处仅应用 opts 过滤
	if opts.proto then
		all = node_mod.filter(all, { proto = opts.proto })
	end
	if opts.keyword and opts.keyword ~= "" then
		all = node_mod.filter(all, { keyword = opts.keyword })
	end
	if opts.dedup then
		all = node_mod.dedup(all)
	end
	if opts.sort then
		all = node_mod.sort(all, opts.sort, opts.desc)
	end
	return all
end

-- 校验 cron 表达式：5 个字段，每个为数字或 *，防 cron 文件命令注入
function M.cron_time_valid(ct)
	if type(ct) ~= "string" then return false end
	local fields = {}
	for f in ct:gmatch("%S+") do fields[#fields + 1] = f end
	if #fields ~= 5 then return false end
	for _, f in ipairs(fields) do
		if f ~= "*" and not f:match("^%d+$") then return false end
	end
	return true
end

-- 依据各订阅的 cron 设置生成 /etc/cron.d/substore；无启用项则移除该文件
function M.write_cron()
	local lines = { "# luci-app-substore cron (per-subscription)" }
	for _, it in ipairs(M.list()) do
		local en = (it.cron_enable == true or it.cron_enable == "1")
		local ct = util.trim(it.cron_time or "")
		if en and M.cron_time_valid(ct) then
			lines[#lines + 1] = ct .. " root /usr/bin/substore-cron.sh " .. it.id .. " >/tmp/substore-cron.log 2>&1"
		end
	end
	if #lines == 1 then
		os.remove(M.CRON_FILE)
		return true
	end
	return util.atomic_write(M.CRON_FILE, table.concat(lines, "\n") .. "\n")
end

return M