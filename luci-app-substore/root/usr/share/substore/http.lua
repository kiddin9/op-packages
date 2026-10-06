-- http.lua — 订阅下载（SSRF 防护、超时、大小限制）（纯 Lua）
-- luci-app-substore

local util = require("substore.util")
local msg = require("substore.msg")

local M = {}

M.DEFAULT_MAX_SIZE = 10 * 1024 * 1024 -- 10MB
M.DEFAULT_TIMEOUT = 20
M.MAX_REDIRECTS = 4

-- ---------- 私网 / 保留地址判断 ----------

-- 单段数值：十进制 / 八进制（前导 0）/ 十六进制（0x 前缀）
-- 返回数值；不是数值写法返回 nil
local function numeral(seg)
	if seg:match("^0[xX]%x+$") then return tonumber(seg:sub(3), 16) end
	if seg:match("^0%d+$") then return tonumber(seg:sub(2), 8) end
	if seg:match("^%d+$") then return tonumber(seg, 10) end
	return nil
end

-- 把 inet_aton 接受的各种数值型 IPv4 写法归一为点分十进制。
-- curl / wget 都按 inet_aton 语义解析主机名，因此 SSRF 检查必须用同一套语义，
-- 否则 "0177.0.0.1"（八进制 127.0.0.1）、"2130706433"（十进制）、"0x7f000001"（十六进制）、
-- "127.1"（短写）会被 is_private_ipv4 当成公网地址而放行，实测这几种写法都能连到 127.0.0.1。
-- 段数与点号数必须一致（拒绝 "1..2" 这类畸形写法）。
-- 返回 "a.b.c.d"；不是数值型 IPv4 时返回 nil。
local function normalize_ipv4(host)
	local dots = select(2, host:gsub("%.", ""))
	local parts = {}
	for seg in host:gmatch("[^%.]+") do parts[#parts + 1] = seg end
	if #parts ~= dots + 1 or #parts > 4 then return nil end

	local vals = {}
	for i, seg in ipairs(parts) do
		local v = numeral(seg)
		if not v then return nil end
		vals[i] = v
	end

	-- inet_aton：前 k-1 段各 8 位，最后一段吃掉剩余位宽
	local k = #vals
	for i = 1, k - 1 do
		if vals[i] > 255 then return nil end
	end
	if vals[k] >= 2 ^ (32 - 8 * (k - 1)) then return nil end

	local n = 0
	for i, v in ipairs(vals) do
		local shift = (i < k) and (32 - 8 * i) or 0
		n = n + v * 2 ^ shift
	end

	local o1 = math.floor(n / 2 ^ 24) % 256
	local o2 = math.floor(n / 2 ^ 16) % 256
	local o3 = math.floor(n / 2 ^ 8) % 256
	local o4 = n % 256
	return string.format("%d.%d.%d.%d", o1, o2, o3, o4)
end

local function is_private_ipv4(ip)
	local a, b, c, d = ip:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
	if not a then return false end
	a, b, c, d = tonumber(a), tonumber(b), tonumber(c), tonumber(d)
	if not (a and b and c and d) then return true end
	if a == 0 then return true end
	if a == 10 then return true end
	if a == 127 then return true end
	if a == 100 and b >= 64 and b <= 127 then return true end -- 100.64/10 CGNAT
	if a == 169 and b == 254 then return true end            -- link-local
	if a == 172 and b >= 16 and b <= 31 then return true end  -- 172.16/12
	if a == 192 and b == 168 then return true end             -- 192.168/16
	if a >= 224 then return true end                          -- multicast + reserved
	return false
end

local function is_private_ipv6(ip)
	if ip == "::" or ip == "::1" then return true end
	local l = ip:lower()
	if l:match("^0*:") and not l:match("^0*::?0*$") and l ~= "0" then return true end
	if l:sub(1, 2) == "fc" or l:sub(1, 2) == "fd" then return true end -- ULA fc00/7
	local ll = l:sub(1, 4)
	if ll == "fe80" or ll == "fe81" or ll == "fe82" or ll == "fe83"
		or ll == "fe84" or ll == "fe85" or ll == "fe86" or ll == "fe87"
		or ll == "fe88" or ll == "fe89" or ll == "fe8a" or ll == "fe8b"
		or ll == "fe8c" or ll == "fe8d" or ll == "fe8e" or ll == "fe8f"
		or ll == "fe90" or ll == "fe91" or ll == "fe92" or ll == "fe93"
		or ll == "fe94" or ll == "fe95" or ll == "fe96" or ll == "fe97"
		or ll == "fe98" or ll == "fe99" or ll == "fe9a" or ll == "fe9b"
		or ll == "fe9c" or ll == "fe9d" or ll == "fe9e" or ll == "fe9f"
		or ll == "fea0" or ll == "fea1" or ll == "fea2" or ll == "fea3"
		or ll == "fea4" or ll == "fea5" or ll == "fea6" or ll == "fea7"
		or ll == "fea8" or ll == "fea9" or ll == "feaa" or ll == "feab"
		or ll == "feac" or ll == "fead" or ll == "feae" or ll == "feaf"
		or ll == "feb0" or ll == "feb1" or ll == "feb2" or ll == "feb3"
		or ll == "feb4" or ll == "feb5" or ll == "feb6" or ll == "feb7"
		or ll == "feb8" or ll == "feb9" or ll == "feba" or ll == "febb"
		or ll == "febc" or ll == "febd" or ll == "febe" or ll == "febf" then
		return true -- link-local fe80::/10
	end
	if l:sub(1, 2) == "ff" then return true end -- multicast
	return false
end

local function is_private(ip)
	ip = ip or ""
	if ip:find(":", 1, true) then return is_private_ipv6(ip) end
	return is_private_ipv4(ip)
end

-- 粗校验：像不像一个 IPv6 字面量。
-- 带 ":" 的主机并不都是 IPv6 —— parse_url 对 "127.0.0.1:" 这类「有冒号但端口为空」
-- 的写法取不到端口，会把整个 "127.0.0.1:" 当主机名返回；它既不是合法域名，
-- is_private_ipv6 也识别不出，于是被当成公网放行。实测 curl 会把它连到 127.0.0.1:80。
-- 因此：含 ":" 但不像 IPv6 的一律拒绝（fail-closed）。
local function looks_like_ipv6(h)
	if not h:match("^[%x:%.]+$") then return false end
	if select(2, h:gsub(":", "")) < 2 then return false end
	if h:find("::.*::") then return false end -- "::" 最多出现一次
	return true
end

-- ---------- URL 解析 ----------
function M.parse_url(url)
	url = util.trim(url or "")
	local scheme, rest = url:match("^([%w%+%-%.]+)://(.*)$")
	if not scheme then return nil, "Invalid URL" end
	scheme = scheme:lower()
	if scheme ~= "http" and scheme ~= "https" then return nil, "Only http/https is supported" end
	-- 主机部分到第一个 / ? # 为止（RFC 3986）。只剥 "/" 是不够的：
	-- "http://127.0.0.1?a=1" 会剩下 "127.0.0.1?a=1"，它既不是合法主机名也不是
	-- 数值型 IPv4，DNS 必然解析不出来，能不能拦住就全看本机有没有解析能力
	-- （见 check_public 的 fail-open 分支）—— 不能指望；curl 实际连的是
	-- 127.0.0.1（路由器上的 LuCI 就是 :80）。
	local hostport = rest:match("^[^/%?#]*") or ""
	-- 剥掉 userinfo（user:pass@）：RFC 3986 里 userinfo 到**最后一个** @ 为止，
	-- @ 之后才是主机。不剥的话 "http://evil@127.0.0.1/" 会把 "evil@127.0.0.1"
	-- 当成主机名交给 check_public：它不是合法域名，本机有解析能力时会被
	-- 判为「无法解析」而拒绝，但本机没有解析能力时是放行的 —— 不能指望
	-- 那一层兜住。而 curl 实际连的是 127.0.0.1 —— 实测可复现。
	local at = hostport:find("@", 1, true)
	while at do
		hostport = hostport:sub(at + 1)
		at = hostport:find("@", 1, true)
	end
	local host, port
	if hostport:sub(1, 1) == "[" then
		local close = hostport:find("]", 1, true)
		if not close then return nil, "Invalid hostname" end
		host = hostport:sub(2, close - 1)
		port = hostport:sub(close + 1):match("^:(%d+)$") or (scheme == "https" and "443" or "80")
	else
		local h, p = hostport:match("^([^:]+):(%d+)$")
		if h then
			host, port = h, p
		else
			host, port = hostport, (scheme == "https" and "443" or "80")
		end
	end
	if not host or host == "" then return nil, "Invalid hostname" end
	-- 端口范围校验：`(%d+)` 只保证是数字，`http://host:99999/` 与 `:0` 都能通过，
	-- 而这两个端口连不出去 —— 下载必然失败，却会先经过一轮 DNS/SSRF 检查，
	-- 报出来的是「连接失败」这种指错方向的原因。parse_proxy 早已做了同样的校验，
	-- 这里对齐。
	local pn = tonumber(port)
	if not pn or pn < 1 or pn > 65535 then return nil, "Invalid port" end
	return { scheme = scheme, host = host, port = tostring(pn) }
end

-- 校验并规范化代理地址：支持 http/https/socks4/socks5/socks5h，可含 user:pass@
-- 空串 → ""（未使用）；合法 → 规范化地址；非法 → nil, err
-- 部分机场按 User-Agent 区分客户端：同一个订单链接，只有用「该订单绑定的客户端」
-- 的 UA 去请求才返回真实节点，其余 UA 得到一段占位内容（见 README「订阅客户端类型」）。
-- 这里只做「能不能安全地放进命令行」的校验，不判断 UA 是否符合某家客户端。
--
-- 拒绝控制字符：UA 最终会以 `-A <ua>` 的形式进入 shell 命令，util.shq 的单引号
-- 能挡住注入，但挡不住 UA 里的换行 —— curl 会把它当成**响应头之外的**新请求头
-- 拼进去（header injection），且日志里也会被换行截断、伪造出额外行。
-- 长度上限 256：真实 UA 都在 100 字符内，超长的只可能是构造出来的。
function M.validate_user_agent(ua)
	if ua == nil then return "" end
	local s = util.trim(tostring(ua))
	if s == "" then return "" end
	if #s > 256 then return nil, "User-Agent is too long (at most 256 characters)" end
	if s:find("%c") then return nil, "User-Agent must not contain control characters" end
	return s
end

function M.parse_proxy(p)
	local s = util.trim(p or "")
	if s == "" then return "" end
	local scheme, rest = s:match("^(%a[%w]*)://(.*)$")
	if not scheme then return nil, "Invalid proxy format" end
	scheme = scheme:lower()
	if scheme ~= "http" and scheme ~= "https" and scheme ~= "socks4"
		and scheme ~= "socks5" and scheme ~= "socks5h" then
		return nil, msg.join("Unsupported proxy protocol: ", scheme)
	end
	local userinfo, hostport = "", rest:gsub("/.*$", "")
	local at = hostport:find("@", 1, true)
	if at then
		userinfo = hostport:sub(1, at - 1)
		hostport = hostport:sub(at + 1)
	end
	if userinfo ~= "" and not userinfo:match("^[%w%.%-_:]+$") then
		return nil, "Proxy username/password contains invalid characters"
	end
	local host, port
	local bracketed = hostport:sub(1, 1) == "["
	if bracketed then
		host = hostport:match("^%[([%w%.%-%:]+)%]")
		port = hostport:match("^%[.*%]%:(%d+)$")
	else
		local h, prt = hostport:match("^([^:]+):(%d+)$")
		if h then host, port = h, prt else host = hostport end
	end
	if not host or host == "" or not host:match("^[%w%.%-%:]+$") then
		return nil, "Invalid proxy host"
	end
	-- 未加方括号的 IPv6 字面量：RFC 3986 要求 IPv6 主机必须写成 [addr]。
	-- 没有方括号时 `::1:1080` 既可能是「地址 ::1 + 端口 1080」，也可能就是
	-- 地址 `::1:1080` —— 无法判定。与其猜一个再拼出一条 curl -x 解析不了的
	-- 代理串（静默失效），不如明确报错让用户补上方括号。
	if not bracketed and select(2, host:gsub(":", "")) > 1 then
		return nil, "An IPv6 proxy address must be bracketed, e.g. http://[::1]:1080"
	end
	if port then
		port = tonumber(port)
		if not port or port < 1 or port > 65535 then return nil, "Invalid proxy port" end
	end
	-- IPv6 字面量必须把方括号拼回去：上面为做主机校验把 [::1] 拆成了 ::1，
	-- 直接拼会得到 `http://::1:1080` —— 冒号歧义，curl -x 与 http_proxy= 都
	-- 解析不了（curl 会把 `::1:1080` 整个当成主机名），代理静默失效。
	-- 单个冒号才是 host:port 的分隔符。
	if host:find(":", 1, true) then host = "[" .. host .. "]" end
	local r = scheme .. "://"
	if userinfo ~= "" then r = r .. userinfo .. "@" end
	r = r .. host
	if port then r = r .. ":" .. port end
	return r
end

-- ---------- 主机名解析 ----------
-- 解析手段按代价逐级回退：nixio（进程内，不 fork）→ busybox nslookup（fork 一次）。
local function have(cmd)
	return os.execute("command -v " .. cmd .. " >/dev/null 2>&1") == 0
end

-- busybox nslookup 的输出形如：
--   Server:		192.168.1.1
--   Address:	192.168.1.1:53
--
--   Name:	example.com
--   Address: 93.184.216.34
--   Address: 2606:2800:220:1:248:1893:25c8:1946
-- 只取 "Name:" 之后的 "Address:" 行：前面那两行是 **DNS 服务器自己**的地址
-- （路由器上通常就是 192.168.x.x），当成解析结果会让每个域名都被判成内网而全部误拒。
-- 解析失败（NXDOMAIN / 超时）时 busybox 只往 stderr 写错误，stdout 里没有 Name: 段，
-- ips 为空 → 返回 nil，与「解析失败」语义一致。
local function resolve_via_nslookup(host)
	local p = io.popen("nslookup " .. util.shq(host) .. " 2>/dev/null")
	if not p then return nil end
	local out = p:read("*a") or ""
	p:close()
	local ips, in_answer = {}, false
	for line in out:gmatch("[^\r\n]+") do
		if line:match("^%s*Name%s*:") then
			in_answer = true
		elseif in_answer then
			local a = line:match("^%s*Address%s*:%s*(%S+)")
			if a then
				a = a:match("^([^%%]+)") or a -- 去掉 IPv6 的 %zone 后缀
				if a ~= "" then ips[#ips + 1] = a end
			end
		end
	end
	if #ips == 0 then return nil end
	return ips
end

-- 解析主机 → IP 列表。返回 ips, have_resolver
--   ips           解析结果；解析不出来为 nil
--   have_resolver 本机是否存在**可用**的解析手段
-- 第二个返回值必须与第一个分开：「解析失败」和「本机根本没有解析能力」是两回事，
-- 处置方式完全相反（见 check_public），合并成一个 nil 会得出错误结论。
local function resolve(host)
	local have_resolver = false
	local nixio = util.try_require("nixio")
	if nixio then
		have_resolver = true
		local ok, addrs = pcall(function() return nixio.getaddrinfo(host) end)
		if ok and type(addrs) == "table" then
			local ips = {}
			for _, a in ipairs(addrs) do
				if a and a.addr then ips[#ips + 1] = a.addr end
			end
			if #ips > 0 then return ips, true end
		end
	end
	if have("nslookup") then
		have_resolver = true
		local ips = resolve_via_nslookup(host)
		if ips then return ips, true end
	end
	return nil, have_resolver
end

-- 回环别名（/etc/hosts 常见写法），比较前会先去掉尾部点
local LOOPBACK_NAMES = {
	["localhost"] = true,
	["localhost.localdomain"] = true,
	["localhost4"] = true,
	["localhost4.localdomain4"] = true,
	["localhost6"] = true,
	["localhost6.localdomain6"] = true,
	["ip6-localhost"] = true,
	["ip6-loopback"] = true,
	["ip6-localnet"] = true,
}

-- SSRF 预检：拒绝 localhost / 私网 / 保留地址。返回 ok, reason, unverified
--   unverified 为 true 表示「本机没有任何 DNS 解析手段，这次放行没有经过解析校验」。
--   调用方（下载层）据此在连接建立后强制复核对端地址，见 verify_peer_ip。
function M.check_public(host)
	host = util.trim(host or ""):lower()
	if host == "" then return false, "Empty hostname" end
	-- userinfo 应已被 parse_url 剥掉；这里再挡一次。
	-- "evil@127.0.0.1" 不是合法主机名，DNS 解析必然失败，而解析失败是放行的
	-- （fail-open），于是会绕过检查 —— 实测该写法确实能连到 127.0.0.1。
	if host:find("@", 1, true) then return false, "Hostname contains the invalid character @" end
	-- 空白 / 百分号编码：主机名里都不合法（"127.0.0.1%00.example.com" 这类
	-- 截断写法当前版本的 curl 会直接判 URL 非法，但不同版本行为不一，直接拒绝更稳）
	if host:find("[%s%%]") then return false, "Hostname contains invalid characters" end
	-- 去掉尾部点："localhost." 与 "localhost" 指向同一台机器，
	-- 不归一会被当成普通域名交给 DNS，解析失败时即放行。
	host = host:gsub("%.$", "")
	if host == "" then return false, "Empty hostname" end

	if host:find(":", 1, true) then
		if not looks_like_ipv6(host) then return false, "Invalid hostname" end
		if is_private_ipv6(host) then return false, "Target is a private/reserved address" end
		return true
	end

	-- 数值型 IPv4（十进制 / 八进制 / 十六进制 / 短写）按 inet_aton 语义归一后再判私网
	local norm = normalize_ipv4(host)
	if norm then
		if is_private_ipv4(norm) then return false, "Target is a private/reserved address" end
		return true
	end

	if LOOPBACK_NAMES[host] then return false, "Target is localhost" end

	local ips, have_resolver = resolve(host)
	if not ips then
		if have_resolver then
			-- 本机有解析手段却解析不出来 → 域名确实不存在（NXDOMAIN）。
			-- 拒绝（fail-closed）。
			--
			-- 不能在这里放行：`127.0.0.1.nip.io` 这类**公网可解析到内网**的域名，
			-- 只要本机这一刻解析不出来（解析器临时故障、超时），就绕过了上面
			-- 全部检查被放行，而 curl 自己仍会把它解析到 127.0.0.1 并连上去。
			-- 检查的强度不能低于被检查者。
			return false, "Cannot resolve the target hostname"
		end
		-- 本机连一个解析手段都没有（nixio 不可用，且没有 nslookup）。
		--
		-- 这种情形**不能**按「解析失败」处理：[2.6.8-r1] 把两者合并成了同一个
		-- nil，于是这种设备上**所有**域名订阅都被拒，报「无法解析目标主机名」——
		-- 而 curl/wget 自带 libc 解析器，照样能解析并下载，2.6.7-r1 实测正常。
		-- 「本机没装 luci-lib-nixio」不等于「这个域名解析不出来」，两者被混为一谈
		-- 就是那次回归的根因。
		--
		-- 放行，改由下载层在**连接建立之后**用 curl 回报的 %{remote_ip} 复核
		-- 实际对端地址（见 verify_peer_ip）。那才是真正连上去的那个 IP，
		-- 比预检更贴近事实，顺带免疫「预检时解析到公网、连接时解析到内网」的
		-- DNS rebinding。
		return true, "No local DNS resolution; the peer address will be verified at connect time", true
	end
	for _, ip in ipairs(ips) do
		if not is_private(ip) then return true end
	end
	return false, "Target resolves only to private/reserved addresses"
end

-- ---------- 下载 ----------
local function detect_tool()
	if have("curl") then return "curl" end
	if have("wget") then return "wget" end
	return nil
end

local function location_from_headers(path)
	local raw = util.read_file(path)
	if not raw then return nil end
	for line in raw:gmatch("[^\r\n]+") do
		local v = line:match("^%s*[Ll]ocation:%s*(.+)$")
		if v then return util.trim(v) end
	end
	return nil
end

-- 读取响应头（curl -D 输出），返回小写键 → 值的表；重复键取最后一个
local function read_headers(path)
	local h = {}
	local raw = util.read_file(path)
	if not raw then return h end
	for line in raw:gmatch("[^\r\n]+") do
		local k, v = line:match("^%s*([^:]+):%s*(.*)$")
		if k then h[k:lower()] = v end
	end
	return h
end

local function resolve_url(base, loc)
	if loc:find("://", 1, true) then return loc end
	local scheme, host = base:match("^([%w]+)://([^/]+)")
	if not scheme then return loc end
	-- 协议相对地址（//host/path）：沿用 scheme，但主机取自 Location 本身，
	-- 否则会被误当成同主机的路径而漏掉跨主机跳转
	if loc:sub(1, 2) == "//" then return scheme .. ":" .. loc end
	if loc:sub(1, 1) == "/" then return scheme .. "://" .. host .. loc end
	local base_path = base:match("^[%w]+://[^/]+(.*)$") or "/"
	local dir = base_path:match("^(.*)/[^/]*$") or ""
	return scheme .. "://" .. host .. dir .. "/" .. loc
end

-- 从 wget -S 日志中按出现顺序提取重定向目标（Location）
local function locations_from_log(raw)
	local locs = {}
	for line in (raw or ""):gmatch("[^\r\n]+") do
		local v = line:match("^%s*[Ll]ocation:%s*(.+)$")
		if v then locs[#locs + 1] = util.trim(v) end
	end
	return locs
end

-- 复检重定向链：每一跳都必须通过 check_public。
-- busybox wget 没有 --max-redirect，无法在发出请求前拦住重定向，只能在 -S 日志里
-- 逐跳校验；任一跳不安全即整体失败并丢弃响应体（§14/§16）。
-- 纯函数，不触网，便于离线测试。返回 ok, err
function M.validate_redirect_chain(base_url, log)
	for _, loc in ipairs(locations_from_log(log)) do
		local next_url = resolve_url(base_url, loc)
		local np = M.parse_url(next_url)
		if not np then return false, msg.join("Invalid redirect target: ", loc) end
		local ok, re = M.check_public(np.host)
		if not ok then return false, msg.join("Unsafe redirect target: ", re or "") end
	end
	return true
end

-- 代理地址去凭据，用于日志（§39：不记录代理密码）
function M.redact_proxy(p)
	local scheme, rest = tostring(p or ""):match("^(%a[%w]*)://(.*)$")
	if not scheme then return "***" end
	return scheme .. "://" .. (rest:gsub("^[^@]*@", ""))
end

-- 抹掉文本中的 URL 凭据（//user:pass@），用于日志与错误信息（§39）
function M.scrub_credentials(text)
	return (tostring(text or ""):gsub("//([^%s/@:]*)%:([^%s/@]*)@", "//***@"))
end

-- 连接建立后复核**实际**对端地址，返回 ok, err。
--
-- check_public 是预检，它解析的是「此刻」的 DNS；curl 稍后会自己再解析一次，
-- 两次结果未必相同（DNS rebinding、TTL 过期、多 A 记录轮询、本机无解析手段时的
-- 直接放行）。curl 的 %{remote_ip} 回报的是真正建立连接的那个 IP ——
-- 用它复核，SSRF 防护才不依赖「预检那一刻的 DNS 恰好和连接时一致」。
--
-- 走代理时 %{remote_ip} 是代理的地址（多半就在内网），必须跳过：代理是用户
-- 自己配置的，不属于 SSRF 防护要拦的目标。
local function verify_peer_ip(ip, proxy, unverified)
	if proxy and proxy ~= "" then return true end
	if not ip or ip == "" then
		-- curl 没回报对端地址（连接没建立，或 curl < 7.29 不支持该变量）。
		if unverified then
			-- 预检时本机就没有解析能力（check_public 放行了），现在连对端地址
			-- 也拿不到 —— 这个请求从头到尾没有任何一处校验过目标，
			-- 必须拒绝，否则「无法校验」就等于「放行」。
			return false, "Cannot verify the target address (no local DNS resolution and no peer IP obtained)"
		end
		-- 有解析能力时预检已经查过一轮，这里无从复核不额外拒绝。
		return true
	end
	if is_private(ip) then
		return false, msg.compose("Target actually connects to a private/reserved address (", ip, ")")
	end
	return true
end

local function fetch_curl(url, parsed, opts)
	local max, t = opts.max_size, opts.timeout
	local proxy_arg = ""
	if opts.proxy and opts.proxy ~= "" then
		proxy_arg = " -x " .. util.shq(opts.proxy)
	end
	-- 订阅客户端类型（User-Agent）。空 = 不传，curl 用自带的 curl/x.y.z。
	-- 必须在**每一跳**都带上：重定向后的目标同样按 UA 决定返回什么内容。
	local ua_arg = ""
	if opts.user_agent and opts.user_agent ~= "" then
		ua_arg = " -A " .. util.shq(opts.user_agent)
	end
	-- 临时文件名带随机标记：固定路径会让两个并发下载（如两个订阅的 cron 同时触发，
	-- 或手动更新撞上 cron）互相覆盖，A 订阅存下 B 的内容且都不报错。
	local tag = util.rnd_hex(8)
	local cur = url
	for redirect = 0, M.MAX_REDIRECTS do
		local tmp = "/tmp/substore_dl_" .. tag .. "_" .. redirect .. ".tmp"
		local hdr = tmp .. ".hdr"
		local errf = tmp .. ".err"
		-- 清理必须在**每一条**退出路径上执行。
		-- 此前只在「本轮开始」和「2xx 成功」两处 os.remove：失败路径（curl 报错、
		-- 超限、重定向无 Location / 目标不安全、HTTP 4xx-5xx、重定向次数过多）
		-- 都把文件留在 /tmp。而 OpenWrt 的 /tmp 是 tmpfs —— 占的是内存；
		-- 订阅更新失败（cron 定时重试）会一轮轮往内存里堆 .tmp/.hdr/.err，
		-- 其中 .tmp 可能是部分下载的响应体，最大到 max_size。
		local function cleanup()
			os.remove(tmp); os.remove(hdr); os.remove(errf)
		end
		cleanup()
		-- -w 同时取 http_code 与 remote_ip：后者是真正建立连接的对端地址，
		-- 用来在拿到响应体之前复核目标（见 verify_peer_ip）。
		local cmd = string.format(
			"curl -sS -o %s --max-time %d --connect-timeout %d --max-redirs 0 --max-filesize %d -D %s -w \"%%{http_code} %%{remote_ip}\"%s%s %s 2>%s",
			util.shq(tmp), t, math.min(t, 10), max, util.shq(hdr), proxy_arg, ua_arg, util.shq(cur), util.shq(errf))
		local p = io.popen(cmd)
		local raw = util.trim(p and p:read("*a") or "")
		if p then p:close() end
		-- 正常是 "200 93.184.216.34"；连接没建立时 curl 只回 "000"（没有 IP）。
		local code, peer = raw:match("^(%d+)%s*(%S*)$")
		if not code then code = raw end
		if code == "" or code == "000" then
			local errtext = util.trim(util.read_file(errf) or "Download failed")
			cleanup()
			return nil, errtext
		end
		-- 只把 2xx 当成功。写成 [23] 会把 3xx 也当成功，于是重定向响应体（通常是空的
		-- 或一段 HTML）被当成订阅内容存下去：已存的节点被清空、node_count 归 0，
		-- 而 error 仍是空字符串，列表页看不出任何异常。下面的重定向分支也因此永远不会执行。
		if code:match("^2%d%d$") then
			local pok, perr = verify_peer_ip(peer, opts.proxy, opts.unverified)
			if not pok then
				cleanup()
				return nil, perr
			end
			local size = util.file_size(tmp)
			if size > max then
				cleanup()
				return nil, msg.compose("Response exceeds the size limit (", max, " bytes)")
			end
			local content = util.read_file(tmp)
			local headers = read_headers(hdr)
			cleanup()
			if not content then return nil, "Failed to read the response" end
			return content, headers
		end
		if code:match("^3%d%d$") then
			-- 重定向的**发起方**也要复核：否则一个公网域名可以先 302 到
			-- 127.0.0.1 并在第一跳就连上内网服务（Location 检查只能拦住
			-- 第二跳的目标，拦不住第一跳本身）。
			local pok, perr = verify_peer_ip(peer, opts.proxy, opts.unverified)
			if not pok then
				cleanup()
				return nil, perr
			end
			local loc = location_from_headers(hdr)
			if not loc then
				cleanup()
				return nil, "Redirect without a Location header"
			end
			local next_url = resolve_url(cur, loc)
			local np = M.parse_url(next_url)
			if not np then
				cleanup()
				return nil, "Invalid redirect target"
			end
			local ok, re = M.check_public(np.host)
			if not ok then
				cleanup()
				return nil, msg.join("Unsafe redirect target: ", re or "")
			end
			cleanup()
			cur = next_url
		else
			cleanup()
			return nil, msg.join("HTTP error ", code)
		end
	end
	return nil, "Too many redirects"
end

-- wget 后端的代理环境变量。busybox wget 只能通过 http_proxy/https_proxy 环境变量
-- 使用 http(s) 代理；遇到它不支持的协议（socks*）必须明确报错，
-- 不能丢掉代理静默直连（§12）。返回 env 或 nil, err
function M.wget_proxy_env(proxy)
	if proxy == nil or proxy == "" then return "" end
	local scheme = tostring(proxy):match("^(%a[%w]*)://")
	scheme = scheme and scheme:lower() or ""
	if scheme ~= "http" and scheme ~= "https" then
		return nil, msg.compose("The current download backend (wget) does not support ", string.upper(scheme),
			" proxies; install curl or use an http proxy")
	end
	return "http_proxy=" .. util.shq(proxy) .. " https_proxy=" .. util.shq(proxy) .. " "
end

local function fetch_wget(url, parsed, opts)
	-- 本机没有 DNS 解析能力时，check_public 只能 fail-open 放行，把校验推迟到
	-- 「连接建立后复核对端地址」。curl 后端有 %{remote_ip} 可用（见 verify_peer_ip），
	-- wget 后端**没有任何等价物**：拿不到对端地址，busybox wget 也没有可用的
	-- 重定向拦截（重定向链只能事后从 -S 日志里看，拦不住已经发出去的请求）。
	-- 于是在这条路径上，「预检放行」之后不存在任何一处校验 —— 等于没有 SSRF 防护。
	-- 与 verify_peer_ip 的处置保持一致：校验不了就拒绝，而不是放行。
	if opts.unverified then
		return nil, "No local DNS resolution: the wget backend cannot verify the target address and refused the download (install curl and retry)"
	end
	local max, t = opts.max_size, opts.timeout
	local proxy_env, perr = M.wget_proxy_env(opts.proxy)
	if not proxy_env then return nil, perr end
	-- busybox wget 用 -U 设置 User-Agent（已核对 busybox 1.37 的 --help）。
	local ua_arg = ""
	if opts.user_agent and opts.user_agent ~= "" then
		ua_arg = " -U " .. util.shq(opts.user_agent)
	end
	local tag = util.rnd_hex(8)
	local tmp = "/tmp/substore_dl_wget_" .. tag .. ".tmp"
	local log = tmp .. ".log"
	os.remove(tmp); os.remove(log)
	-- -S 打印响应头（含整条重定向链），据此复检 SSRF；
	-- 日志与响应体分流：体写 tmp，链写 log
	local cmd = proxy_env .. string.format("wget -S -q -T %d%s -O %s %s >%s 2>&1",
		t, ua_arg, util.shq(tmp), util.shq(url), util.shq(log))
	local rc = os.execute(cmd)
	-- 退出码必须看：wget 失败时可能已经写下半截响应体，只判断 size == 0
	-- 会把残缺内容当成下载成功。
	-- Lua 5.1 的 os.execute 返回数字退出码，5.2+ 返回 true/nil, "exit", code，两者都兼容。
	local exit_ok = (rc == true) or (type(rc) == "number" and rc == 0)
	local logtext = util.read_file(log) or ""
	os.remove(log)
	local safe, reason = M.validate_redirect_chain(url, logtext)
	if not safe then
		os.remove(tmp)
		return nil, reason
	end
	local size = util.file_size(tmp)
	if size > max then os.remove(tmp); return nil, msg.compose("Response exceeds the size limit (", max, " bytes)") end
	if not exit_ok then
		os.remove(tmp)
		return nil, "Download failed (wget exit code is non-zero)"
	end
	if size == 0 then os.remove(tmp); return nil, "Download failed or the content is empty" end
	local content = util.read_file(tmp)
	os.remove(tmp)
	if not content then return nil, "Failed to read the response" end
	return content, {} -- wget 不捕获响应头（无 subscription-userinfo）
end

local function fetch(tool, url, parsed, opts)
	if tool == "curl" then return fetch_curl(url, parsed, opts) end
	return fetch_wget(url, parsed, opts)
end

-- 下载订阅内容。成功返回 body, headers, nil；失败返回 nil, nil, err
-- opts.proxy 为可选代理地址（scheme://host:port），应由调用方用 parse_proxy 校验
-- opts.user_agent 为可选的订阅客户端 User-Agent，应由调用方用 validate_user_agent 校验
function M.download(url, opts)
	opts = opts or {}
	local max_size = opts.max_size or M.DEFAULT_MAX_SIZE
	local timeout = opts.timeout or M.DEFAULT_TIMEOUT
	local parsed = M.parse_url(url)
	if not parsed then return nil, nil, "Invalid URL" end
	local ua, uaerr = M.validate_user_agent(opts.user_agent)
	if not ua then return nil, nil, uaerr end
	local ok, reason, unverified = M.check_public(parsed.host)
	if not ok then return nil, nil, reason end
	local tool = detect_tool()
	if not tool then return nil, nil, "No download tool available (curl/wget)" end
	local body, headers = fetch(tool, url, parsed, { max_size = max_size, timeout = timeout, proxy = opts.proxy,
		user_agent = ua, unverified = unverified })
	if not body then return nil, nil, headers end
	return body, headers or {}, nil
end

return M