-- util.lua — 通用工具（纯 Lua 5.1，无外部依赖）
-- luci-app-substore

local msg = require("substore.msg")

local M = {}

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

function M.trim(s)
	return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- 安全 require：模块不存在时返回 nil 而不报错
function M.try_require(name)
	local ok, mod = pcall(require, name)
	if ok and mod then return mod end
	return nil
end

-- ---------- Base64 ----------
function M.base64_encode(s)
	if type(s) ~= "string" then return "" end
	local out = {}
	for i = 1, #s, 3 do
		local b1 = s:byte(i)
		local b2 = s:byte(i + 1)
		local b3 = s:byte(i + 2)
		local n = b1 * 65536 + (b2 or 0) * 256 + (b3 or 0)
		out[#out + 1] = B64:sub(math.floor(n / 262144) % 64 + 1, math.floor(n / 262144) % 64 + 1)
		out[#out + 1] = B64:sub(math.floor(n / 4096) % 64 + 1, math.floor(n / 4096) % 64 + 1)
		out[#out + 1] = b2 and B64:sub(math.floor(n / 64) % 64 + 1, math.floor(n / 64) % 64 + 1) or "="
		out[#out + 1] = b3 and B64:sub(n % 64 + 1, n % 64 + 1) or "="
	end
	return table.concat(out)
end

function M.base64_decode(s)
	if type(s) ~= "string" then return "" end
	s = s:gsub("[^%w%+/=]", "")
	local out = {}
	local n, bits = 0, 0
	for i = 1, #s do
		local c = s:sub(i, i)
		if c == "=" then break end
		local v = B64:find(c, 1, true)
		if v then
			n = n * 64 + (v - 1)
			bits = bits + 6
			while bits >= 8 do
				bits = bits - 8
				n = math.floor(n)
				local byte = math.floor(n / (2 ^ bits)) % 256
				out[#out + 1] = string.char(byte)
				n = n % (2 ^ bits)
			end
		end
	end
	return table.concat(out)
end

-- URL-safe Base64（RFC 4648 base64url）：- _ 代替 + /，无 padding
function M.base64_url_encode(s)
	s = s or ""
	return (M.base64_encode(s):gsub("+", "-"):gsub("/", "_"):gsub("=+$", ""))
end

function M.base64_url_decode(s)
	if type(s) ~= "string" then return "" end
	s = s:gsub("-", "+"):gsub("_", "/")
	return M.base64_decode(s)
end

-- shell 单引号转义。拼进 shell 命令行的**一切外部数据**都必须走这里。
-- 不能用 string.format("%q")：它生成的是双引号字符串，而 /bin/sh 在双引号内
-- 仍然会做 $() 和 `` 命令替换，所以 format("%q", "$(rm -rf /)") 会被真的执行。
-- 单引号内除 ' 之外所有字符都是字面量，' 本身写作 '\'' 即可闭合再转义。
function M.shq(s)
	return "'" .. tostring(s or ""):gsub("'", "'\\''") .. "'"
end

-- 把值压成单行。Surge / Loon / Quantumult X / wg-quick .conf 都是行式格式：
-- 值里一旦含换行，就会截断当前行并伪造出额外的一行（节点名、sni、path 等
-- 全部来自订阅内容，属于不可信输入）。换行/回车压成空格，其余控制字符丢弃。
function M.one_line(s)
	if s == nil then return nil end
	return (tostring(s):gsub("[\r\n]+", " "):gsub("%c", ""))
end

-- 生成随机十六进制 token（用于下载链接访问控制）
--
-- 不能直接用 math.random 产出：Lua 5.1 的 math.random 是 31 位 LCG，而原实现
-- 每次调用都重新 randomseed，同一时钟刻度内的多次调用会给出完全相同的序列
-- （实测 20 万次调用只有约 18 万个不同值，约 9.7% 的 token 重复）。订阅下载
-- token 是访问控制的唯一凭据，重复即可被猜测。优先直接读内核熵源，
-- 只有在 /dev/urandom 不可用时才退回 PRNG（且只播种一次）。
local prng_seeded = false
local function seed_prng()
	if prng_seeded then return end
	prng_seeded = true
	math.randomseed(os.time() + math.floor((os.clock() * 1000000) % 1000000))
end

function M.rnd_hex(len)
	len = len or 16
	local f = io.open("/dev/urandom", "rb")
	if f then
		local need = math.ceil(len / 2)
		local bytes = f:read(need)
		f:close()
		if bytes and #bytes == need then
			local out = {}
			for i = 1, #bytes do
				out[#out + 1] = string.format("%02x", bytes:byte(i))
			end
			return (table.concat(out):sub(1, len))
		end
	end
	seed_prng()
	local hex = "0123456789abcdef"
	local out = {}
	for _ = 1, len do
		local idx = math.random(1, 16)
		out[#out + 1] = hex:sub(idx, idx)
	end
	return table.concat(out)
end

-- RFC 4122 version 4 UUID（8-4-4-4-12 十六进制）。
--
-- 客户端的 uuid 字段要的是**合法 UUID**，不是「一串随机字符」：
-- vmess/vless 的 uuid 会被解析成 16 字节，格式不对时多数客户端直接拒绝该节点。
-- 所以这里按规范置版本位（第 13 位十六进制 = 4）与变体位（第 17 位 ∈ 8/9/a/b），
-- 而不是随便取 36 个字符。随机源复用 rnd_hex（优先 /dev/urandom）。
-- 32 个十六进制字符按 8-4-4-4-12 切分；第 13 位固定 '4'（版本），
-- 第 17 位取 8/9/a/b（变体，即高两位为二进制的 10）。
function M.uuid()
	local h = M.rnd_hex(32)
	if #h < 32 then return nil end
	local variant = tonumber(h:sub(17, 17), 16) % 4 + 8 -- 8..11 → 8/9/a/b
	return string.format("%s-%s-4%s-%x%s-%s",
		h:sub(1, 8), h:sub(9, 12), h:sub(14, 16),
		variant, h:sub(18, 20),
		h:sub(21, 32))
end

-- 把任意字符串转成 string.gsub 的**字面**替换串。
--
-- gsub 的替换串有自己的语义：`%` 后接数字是捕获引用，`%%` 才是字面百分号，
-- 而 `%` 后接其它字符会被吞掉、结尾的 `%` 会注入 NUL 字节。
-- 用户提供的替换值（节点名、模板变量）必须原样落地，所以先转义。
function M.gsub_literal(s)
	return (tostring(s or ""):gsub("%%", "%%%%"))
end

-- ---------- URL ----------
function M.url_decode(s)
	if type(s) ~= "string" then return "" end
	return s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)
end

-- 从 query string 提取字段（接受 URL 片段，如 "…?a=1&b=2#frag"）
function M.url_extract(s, field)
	if type(s) ~= "string" then return nil end
	local q = s:match("[^#?]*%?([^#]*)")
	if not q then return nil end
	for k, v in q:gmatch("([^&=]+)=([^&]*)") do
		if k == field then return M.url_decode(v) end
	end
	return nil
end

-- 拆分 host:port，支持 [ipv6]:port
function M.split_hostport(s)
	if type(s) ~= "string" then return nil, nil end
	s = M.trim(s)
	-- 去掉可能尾随的路径（如 "host:port/path"）
	s = s:match("^([^/]*)") or s
	if s == "" then return nil, nil end
	if s:sub(1, 1) == "[" then
		local close = s:find("]", 1, true)
		if not close then return nil, nil end
		local host = s:sub(2, close - 1)
		local port = s:sub(close + 1):match("^:(%d+)$")
		return host, port
	else
		local host, port = s:match("^([^:]+):(%d+)$")
		if host then return host, port end
		-- 没有可识别的端口，整串就是主机名 —— 但必须先剥掉**尾随**冒号：
		-- `"example.com:"` 此前原样返回 host="example.com:"，调用方拿这个带
		-- 冒号的串当主机名，DNS 解析必然失败，而失败点离这里很远、很难定位。
		-- 只剥结尾的冒号，`"::1"` 这类不带方括号的裸 IPv6 不受影响。
		s = s:gsub(":$", "")
		if s == "" then return nil, nil end
		return s, nil
	end
end

-- 解析 SIP003 插件串（shadowsocks 的 `plugin` 字段）。
--
-- 格式出自 SIP002 §"For plugin argument"，与 SIP003 的 SS_PLUGIN_OPTIONS 同构：
--     <name>[;<key>=<value>]...        例：obfs-local;obfs=http;obfs-host=www.baidu.com
-- 值里的 `;`、`=`、`\` 按规范用反斜杠转义，因此切分必须跳过转义序列 ——
-- 否则 `path=/a\;b` 会被切成两段，得到一个并不存在的选项，而 `\;` 是 v2ray-plugin
-- 的 path 里完全可能出现的写法。
--
-- 返回 name, opts_string, opts_map：
--   * opts_string 是 `;` 之后的原样串（含转义），用于 sing-box 的 plugin_opts ——
--     该字段就是交给插件进程的 SS_PLUGIN_OPTIONS，原样透传才不失真；
--   * opts_map 是拆好的键值对，用于需要逐键映射的目标（mihomo 的 plugin-opts）。
--     不带 `=` 的裸标志（v2ray-plugin 的 `tls`）取值为 true。
-- 空串或没有插件名时返回 nil。
function M.parse_sip003_plugin(raw)
	if type(raw) ~= "string" or raw == "" then return nil end
	local fields, buf = {}, {}
	local i, n = 1, #raw
	-- 必须是 while：下面遇到转义序列要一次吃掉两个字符，Lua 的数值 for 会在每轮
	-- 重新赋值控制变量，循环体内改 i 不生效。
	while i <= n do
		local c = raw:sub(i, i)
		if c == "\\" and i < n then
			buf[#buf + 1] = c .. raw:sub(i + 1, i + 1)
			i = i + 2
		elseif c == ";" then
			fields[#fields + 1] = table.concat(buf)
			buf = {}
			i = i + 1
		else
			buf[#buf + 1] = c
			i = i + 1
		end
	end
	fields[#fields + 1] = table.concat(buf)

	local name = M.trim(fields[1] or "")
	if name == "" then return nil end

	local opts_list = {}
	for idx = 2, #fields do
		local f = M.trim(fields[idx])
		if f ~= "" then opts_list[#opts_list + 1] = f end
	end

	local map = {}
	for _, f in ipairs(opts_list) do
		local k, v = f:match("^([^=]+)=(.*)$")
		if k then
			map[M.trim(k)] = v
		else
			map[f] = true
		end
	end

	return name, table.concat(opts_list, ";"), map
end

-- ---------- JSON ----------
local function utf8_char(cp)
	if cp < 0x80 then
		return string.char(cp)
	elseif cp < 0x800 then
		return string.char(0xC0 + math.floor(cp / 0x40), 0x80 + cp % 0x40)
	elseif cp < 0x10000 then
		return string.char(0xE0 + math.floor(cp / 0x1000),
			0x80 + math.floor(cp / 0x40) % 0x40, 0x80 + cp % 0x40)
	else
		return string.char(0xF0 + math.floor(cp / 0x40000),
			0x80 + math.floor(cp / 0x1000) % 0x40,
			0x80 + math.floor(cp / 0x40) % 0x40, 0x80 + cp % 0x40)
	end
end

local function is_array(t)
	local i = 0
	for k in pairs(t) do
		i = i + 1
		if t[i] == nil then return false end
	end
	return i == #t
end

-- JSON null 占位符：仅在数组中用于保留位置（对象中的 null 仍解码为 nil）
local JSON_NULL = {}

-- JSON 空对象占位符。Lua 的空表无法区分 {} 与 []（is_array 判定空表为数组），
-- 而 sing-box / Xray 的部分字段必须是对象（"tls": {}、"settings": {}），
-- 编码成 [] 会被客户端拒绝。需要空对象时显式使用本常量。
--
-- 标记用的是**元表**而不是表本身的同一性：解码器每遇到一个 `{}` 必须返回一张
-- 新表，不能返回这张共享的常量表。core.load 拿到 items 后会直接往里塞订阅
-- （`items[id] = {...}`），共享表会让这次写入落到全局哨兵上，随后 json_encode
-- 又把哨兵短路成 `{}` —— 结果是「接口返回新增成功、进程内 list 也看得到，
-- 但文件里什么都没写，重启即消失」。
local JSON_OBJ_MT = { __tostring = function() return "{}" end }
M.JSON_EMPTY_OBJECT = setmetatable({}, JSON_OBJ_MT)

function M.json_encode(v)
	local function enc(v)
		local t = type(v)
		if v == nil then
			return "null"
		elseif t == "string" then
			return '"' .. v:gsub('[%z\1-\31\\"]', function(c)
				if c == '"' then return '\\"'
				elseif c == "\\" then return "\\\\"
				elseif c == "\n" then return "\\n"
				elseif c == "\r" then return "\\r"
				elseif c == "\t" then return "\\t"
				elseif c == "\b" then return "\\b"
				elseif c == "\f" then return "\\f"
				else return string.format("\\u%04x", c:byte()) end
			end) .. '"'
		elseif t == "number" then
			-- 非有限数必须编成 null：`%.14g` 对 inf / -inf 产出的是字面量
			-- `inf` / `-inf`，那不是合法 JSON —— 整份文件会因此解析不了。
			-- 触发路径是真实存在的：订阅响应头 `subscription-userinfo` 里的
			-- `total=1e999` 经 tonumber 就是 inf，写进 subscriptions.json 后
			-- 下一次 load() 直接判「列表文件已损坏」，全部订阅从界面上消失；
			-- 节点侧的 port 同理，一个 inf 会毁掉该订阅的整个节点文件。
			if v ~= v or v == math.huge or v == -math.huge then return "null" end
			return string.format("%.14g", v)
		elseif t == "boolean" then
			return v and "true" or "false"
		elseif t == "table" then
			-- 带空对象标记、且**确实还是空的**才编成 {}：标记只是「这里曾经是
			-- 空对象」的线索，调用方完全可能拿到解码结果后往里加键
			-- （core.load 就是这么用 items 的）。少了 next(v) == nil 这一半，
			-- 加过键的表会被编回 {}，内容静默丢失。
			if getmetatable(v) == JSON_OBJ_MT and next(v) == nil then
				return "{}"
			elseif v == JSON_NULL then
				-- 数组里的 null 解码时被换成 JSON_NULL 占位（见 json_decode），
				-- 编码时必须还原成 null。此前没有这个分支，占位符落进下面的
				-- is_array 判定（空表判为数组）被编成 []，于是 `[null,1]` 往返
				-- 变成 `[[],1]` —— 结构被悄悄改写。
				return "null"
			elseif is_array(v) then
				local a = {}
				for i = 1, #v do a[#a + 1] = enc(v[i]) end
				return "[" .. table.concat(a, ",") .. "]"
			else
				local a = {}
				for k, val in pairs(v) do
					a[#a + 1] = enc(tostring(k)) .. ":" .. enc(val)
				end
				return "{" .. table.concat(a, ",") .. "}"
			end
		end
		return "null"
	end
	return enc(v)
end

function M.json_decode(s)
	if type(s) ~= "string" then return nil, "not a string" end
	local i = 1
	local len = #s

	local function skip_ws()
		while true do
			local c = s:sub(i, i)
			if c == " " or c == "\t" or c == "\n" or c == "\r" then i = i + 1 else break end
		end
	end

	-- 嵌套深度上限。parse 是递归下降，每进一层容器就多一层 Lua 调用栈；
	-- 几千层时 Lua 5.1 会**抛出** "stack overflow" 而不是返回错误，而本函数的
	-- 契约是 `nil, err`。抛出的异常会一路冒到调用方：core.add_local 里的
	-- `M.sync(id)` 没有 pcall，控制器也没兜住，于是本地订阅导入在订阅行已经
	-- 写盘之后变成 HTTP 500，且 sync 内的 save_meta(error=...) 全被跳过，
	-- 留下一条「看起来还在更新中」的空记录。
	-- 64 层远超任何真实配置（订阅节点是扁平的，sing-box 配置最深也不过十几层）。
	local MAX_DEPTH = 64

	local function parse(depth)
		skip_ws()
		if i > len then return nil, "unexpected end" end
		local c = s:sub(i, i)

		if (c == "{" or c == "[") and depth >= MAX_DEPTH then
			return nil, "nesting too deep"
		end

		if c == "{" then
			i = i + 1
			local obj = {}
			skip_ws()
			-- 空对象必须返回 JSON_EMPTY_OBJECT 而不是裸 {}：Lua 的空表无法区分
			-- {} 与 []，裸 {} 会被 is_array 判成数组、编码回 []，于是
			-- `{"tls":{}}` 往返变成 `{"tls":[]}` —— sing-box / Xray 里
			-- 要求是对象的字段（tls / settings）会因此被客户端拒绝。
			-- 每次返回**新表**（带同一标记元表），不能返回共享常量：
			-- 见 JSON_OBJ_MT 处的说明。
			if s:sub(i, i) == "}" then i = i + 1 return setmetatable({}, JSON_OBJ_MT) end
			while true do
				skip_ws()
				local k, ke = parse(depth + 1)
				if ke then return nil, ke end
				if not k or type(k) ~= "string" then return nil, "expected string key" end
				skip_ws()
				if s:sub(i, i) ~= ":" then return nil, "expected ':'" end
				i = i + 1
				local val, verr = parse(depth + 1)
				if verr then return nil, verr end
				obj[k] = val
				skip_ws()
				local cc = s:sub(i, i)
				if cc == "," then
					i = i + 1
				elseif cc == "}" then
					i = i + 1
					return obj
				else
					return nil, "expected ',' or '}'"
				end
			end

		elseif c == "[" then
			i = i + 1
			local arr = {}
			skip_ws()
			if s:sub(i, i) == "]" then i = i + 1 return arr end
			while true do
				local val, verr = parse(depth + 1)
				-- 必须把内层错误透出去：此前无条件把 nil 当成 null 占位，
				-- 于是 `[1,]` 这种畸形输入被静默接受（parse 报错后 i 未前进，
				-- 下一轮读到 `]` 就当成数组结束），解出 `{1, JSON_NULL}`。
				if verr then return nil, verr end
				if val == nil then val = JSON_NULL end
				arr[#arr + 1] = val
				skip_ws()
				local cc = s:sub(i, i)
				if cc == "," then
					i = i + 1
				elseif cc == "]" then
					i = i + 1
					return arr
				else
					return nil, "expected ',' or ']'"
				end
			end

		elseif c == '"' then
			i = i + 1
			local out = {}
			while true do
				local ch = s:sub(i, i)
				if ch == "" then return nil, "unterminated string" end
				if ch == '"' then i = i + 1 return table.concat(out) end
				if ch == "\\" then
					i = i + 1
					local e = s:sub(i, i)
					i = i + 1
					local map = { ['"'] = '"', ["\\"] = "\\", ["/"] = "/",
						b = "\b", f = "\f", n = "\n", r = "\r", t = "\t" }
					if e == "u" then
						local hex = s:sub(i, i + 3)
						i = i + 4
						local cp = tonumber(hex, 16)
						if not cp then return nil, "bad unicode" end
						if cp >= 0xD800 and cp <= 0xDBFF then
							if s:sub(i, i) == "\\" and s:sub(i + 1, i + 1) == "u" then
								local hex2 = s:sub(i + 2, i + 5)
								local cp2 = tonumber(hex2, 16)
								if cp2 and cp2 >= 0xDC00 and cp2 <= 0xDFFF then
									i = i + 6
									cp = 0x10000 + (cp - 0xD800) * 0x400 + (cp2 - 0xDC00)
								end
							end
						end
						out[#out + 1] = utf8_char(cp)
					else
						out[#out + 1] = map[e] or e
					end
				else
					out[#out + 1] = ch
					i = i + 1
				end
			end

		elseif c == "t" and s:sub(i, i + 3) == "true" then
			i = i + 4
			return true
		elseif c == "f" and s:sub(i, i + 4) == "false" then
			i = i + 5
			return false
		elseif c == "n" and s:sub(i, i + 3) == "null" then
			i = i + 4
			return nil
		elseif c:match("[%-%d]") then
			local num = s:match("^-?%d+%.?%d*[eE]?[%+%-]?%d*", i)
			if not num or num == "" then return nil, "bad number" end
			i = i + #num
			local n = tonumber(num)
			if not n then return nil, "bad number value" end
			return n
		else
			return nil, "unexpected char " .. c
		end
	end

	local v, perr = parse(0)
	-- 此前写成 `local v = parse(); return v` —— parse 的第二返回值（错误串）
	-- 被直接丢弃，于是 json_decode **永远不返回错误**：所有调用方的
	-- `local data, err = util.json_decode(...)` 里 err 判断都是死代码，
	-- 畸形输入一律表现为「解出来是 nil」，与「内容就是 null」无法区分。
	if perr then return nil, perr end
	-- 解析出一个值还不够，必须确认**没有剩余内容**：parse 只消费一个值，
	-- 于是 "1 2" / "[1] junk" / "1.2.3"（数字模式只吃 1.2）这类输入会被
	-- 当成合法值静默接受，尾部的脏数据凭空消失。
	skip_ws()
	if i <= len then return nil, "trailing content at position " .. i end
	return v
end

-- ---------- 文件 ----------
function M.read_file(path)
	local f, e = io.open(path, "rb")
	if not f then return nil, e end
	local data = f:read("*a")
	f:close()
	return data
end

function M.file_size(path)
	local f = io.open(path, "rb")
	if not f then return 0 end
	local data = f:read("*a")
	f:close()
	return #data
end

-- 修改文件权限。Lua 5.1 标准库**没有** os.chmod（那是 nixio/posix 才有的），
-- 所以走 busybox 的 chmod，路径经 shq 引用。mode 传八进制字符串（如 "600"）。
function M.chmod(path, mode)
	return os.execute("chmod " .. mode .. " " .. M.shq(path) .. " >/dev/null 2>&1") == 0
end

-- 原子写：先写临时文件再重命名，避免写一半损坏。
--
-- 两处必须做对，否则「原子」只是名义上的：
--   1) 临时文件名不能固定成 "<path>.tmp"：两个进程同时写同一路径时会交错写进
--      同一个临时文件，rename 上去的是两者内容的混合体，各自的原子性都失效。
--   2) write / close 的返回值必须检查：磁盘写满或写入被截断时 f:write 会失败，
--      但 os.rename 依然成功 —— 于是原子地换上一个残缺文件，调用方却以为成功，
--      下一次读取才发现数据没了。
--
-- mode 可选：写盘后把文件权限收紧到该值。数据文件里是订阅 URL、公开下载 token、
-- 节点凭据；io.open 按 umask 创建，默认通常是 0644 —— 同机任何用户都能读到。
function M.atomic_write(path, content, mode)
	local tmp = string.format("%s.tmp.%s", path, M.rnd_hex(8))
	local f, e = io.open(tmp, "wb")
	if not f then return false, e end
	local wok, werr = f:write(content)
	if not wok then
		f:close()
		os.remove(tmp)
		return false, werr
	end
	local cok, cerr = f:close()
	if not cok then
		os.remove(tmp)
		return false, cerr
	end
	local rok, rerr = os.rename(tmp, path)
	if not rok then
		os.remove(tmp)
		return false, rerr
	end
	-- rename 保留临时文件自身的权限，所以收紧必须在 rename **之后**做：
	-- 先 chmod 再 rename 的话，临时文件名是公开可猜的，中间窗口里别人仍能读到。
	if mode then M.chmod(path, mode) end
	return true
end

-- 建目录。mode 可选，仅在目录**由本次调用创建**时生效 ——
-- 对已存在的目录 busybox mkdir 不会改权限（要改得显式 chmod），
-- 调用方若需要「无论新建与否都收紧」，用 M.chmod 单独补一次。
function M.ensure_dir(path, mode)
	if mode then
		os.execute("mkdir -p -m " .. mode .. " " .. M.shq(path) .. " >/dev/null 2>&1")
	else
		os.execute("mkdir -p " .. M.shq(path))
	end
end

-- ---------- 互斥锁（mkdir 锁 + 陈旧锁回收） ----------
--
-- 用途：把「读整表 → 改 → 写整表」这段临界区串行化。LuCI 页面保存订阅、
-- cron 定时更新、组合订阅自动重算三者可能同时发生，后写者整表覆盖先写者，
-- 结果是订阅静默丢失。本机没有 nixio，用不了 flock；Lua 5.1 的 io.open 也没有
-- O_EXCL —— 但 `mkdir` 本身是原子的，成功者只有一个，拿它当锁。
--
-- 崩溃残留：持有者被杀掉时目录会留在原地，后来者必须能回收，否则永久死锁
-- （比丢数据更糟：整台设备的订阅从此无法再修改）。判据是**锁目录自身的
-- mtime**，不是目录里的文件 —— mtime 由 mkdir 原子地设好，不存在「目录已建、
-- 时间戳还没写」的窗口；写在目录里的持有者文件只作排障用，不参与判定。
M.LOCK_STALE = 60 -- 秒。超过这个时长仍未释放即视为持有者已死。

-- 锁目录是否已陈旧。用一条 shell 判断完成，不解析 stat 输出（少一处格式依赖）。
-- stat 失败时回退成 0，于是「距今」必然大于阈值 —— 判定为陈旧，可以回收。
-- 这是有意的失败方向：无法确认的锁宁可回收，也不要永久卡死。
local function lock_is_stale(path, stale)
	local cmd = string.format(
		"[ $(( $(date +%%s) - $(stat -c %%Y %s 2>/dev/null || echo 0) )) -gt %d ]",
		M.shq(path), stale)
	return os.execute(cmd) == 0
end

-- 取锁。成功返回 true，调用方**必须**在临界区结束时调 lock_release。
-- 失败返回 false（别人正持有，且未判定为陈旧）。
-- opts.stale 覆盖超时阈值；opts.pid 写入持有者文件（默认 os.getpid 不可用，留 0）。
function M.lock_acquire(path, opts)
	opts = opts or {}
	local stale = tonumber(opts.stale) or M.LOCK_STALE
	-- 最多两轮：第一轮抢不到就查一次陈旧性，回收后第二轮重抢。
	for _ = 1, 2 do
		if os.execute("mkdir " .. M.shq(path) .. " >/dev/null 2>&1") == 0 then
			-- 持有者信息纯属排障用（`cat` 一眼看出是谁、什么时候拿的）。
			-- 写失败不影响正确性，因此不检查返回值。
			local f = io.open(path .. "/owner", "wb")
			if f then
				f:write(string.format("%d %d\n", tonumber(opts.pid) or 0, os.time()))
				f:close()
			end
			return true
		end
		if lock_is_stale(path, stale) then
			os.execute("rm -rf " .. M.shq(path) .. " >/dev/null 2>&1")
		else
			return false
		end
	end
	return false
end

-- 释放锁。持有者之外的人不应调用；这里不做持有者校验 —— 校验需要额外的
-- 竞态窗口，而收益只是把「用错 API」变成一条错误信息。
function M.lock_release(path)
	os.execute("rm -rf " .. M.shq(path) .. " >/dev/null 2>&1")
end

-- ---------- 人性化格式 ----------
-- 字节数 → 可读字符串（B/K/M/G/T），如 20G、512M
function M.human_bytes(n)
	n = tonumber(n) or 0
	n = math.floor(n + 0.5)
	if n <= 0 then return "0B" end
	local units = { "B", "K", "M", "G", "T" }
	local i, v = 1, n
	while v >= 1024 and i < #units do
		v = v / 1024
		i = i + 1
	end
	local s = string.format("%.1f", v):gsub("%.0$", "")
	return s .. units[i]
end

-- 秒数 → 可读时长（天/小时/分钟）。
--
-- 返回的是**语言中立的组合消息**（数字 + 单位 msgid），由显示边界逐段翻译
-- （见 msg.lua）。本模块不能 require("luci.i18n")：substore-cron.sh 会在没有
-- LuCI 环境的独立 lua 进程里跑 core.sync。
-- 单位 msgid 带前导空格：英文得到 "3 days"，中文 msgstr 去掉那个空格即 "3天"，
-- 两边都不必为对方将就。
function M.human_duration(secs)
	secs = tonumber(secs) or 0
	if secs <= 0 then return "Expired" end
	local d = secs / 86400
	if d >= 1 then return msg.compose(math.floor(d), " days") end
	local h = secs / 3600
	if h >= 1 then return msg.compose(math.floor(h), " hours") end
	local m = secs / 60
	if m >= 1 then return msg.compose(math.floor(m), " minutes") end
	return "Less than a minute"
end

-- 为一组节点生成唯一 tag（供 sing-box / Xray 完整配置使用）。
-- 节点名可能重复，也可能与保留 tag（direct / block / select / auto …）同名；
-- sing-box 与 Xray 都要求 outbound tag 唯一，重名时追加 " #2"、" #3"。
-- 返回与 nodes 等长的 tag 数组。
function M.unique_tags(nodes, reserved)
	local used = {}
	for k in pairs(reserved or {}) do used[k] = true end
	local tags = {}
	for i, n in ipairs(nodes or {}) do
		local base = n.name
		if base == nil or base == "" then
			base = (n.server or "") .. ":" .. tostring(n.port or "")
		end
		local tag, k = base, 2
		while used[tag] do
			tag = base .. " #" .. k
			k = k + 1
		end
		used[tag] = true
		tags[i] = tag
	end
	return tags
end

return M