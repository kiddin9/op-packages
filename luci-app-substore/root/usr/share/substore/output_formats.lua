-- output_formats.lua — Surge 系 / Loon / QX / Stash / Plain JSON 输出（纯 Lua）
-- （Egern 不在这里：它的配置是 YAML，见 output_egern.lua）
-- luci-app-substore

local util = require("substore.util")
local clash_meta = require("substore.output_clash_meta")
local msg = require("substore.msg")

local M = {}

-- 规范化协议名
local function props(n)
	local proto = (n.proto or ""):lower()
	if proto == "ss" then proto = "shadowsocks" end
	return proto
end

-- Loon 的 VMess「加密方式」（位置参数的第 1 个）取值，取自
-- nsloon.app/docs/Node/ 的 VMess 一行：none / auto / aes-128-cfb /
-- aes-128-gcm / chacha20-ietf-poly1305。
--
-- 与统一模型的 VMESS_CIPHERS（node.lua：auto / none / zero / aes-128-gcm /
-- chacha20-poly1305）有两处对不上，直接照抄会让节点在 Loon 上加载失败：
--   * 同一个算法两种拼写：模型写 chacha20-poly1305，Loon 写 chacha20-ietf-poly1305；
--   * 模型的 zero 是 Xray 专用的取值，Loon 的清单里没有。
-- 所以做一次显式映射，未列出的取值退回 auto（Loon 与各家都认的默认值）。
-- 只用于 Loon；Surge / Surfboard / SurgeMac 的 vmess 走具名 username=，
-- 加密方式是另一个参数（encrypt-method），见 LEGACY_ISSUES 的 7.9。
local LOON_VMESS_CIPHER = {
	auto = "auto", none = "none",
	["aes-128-gcm"] = "aes-128-gcm", ["aes-128-cfb"] = "aes-128-cfb",
	["chacha20-poly1305"] = "chacha20-ietf-poly1305",
	["chacha20-ietf-poly1305"] = "chacha20-ietf-poly1305",
}

-- Surge 家族的 VMess「加密方式」是**具名**参数 encrypt-method，与 Loon 把它放在
-- 位置参数上不同（manual.nssurge.com/policies/vmess.html 原文：
--   `Name = vmess, <host>, <port>, username=<UUID>[, parameter=value, ...]`
--   encrypt-method 取值只有 aes-128-gcm / chacha20-ietf-poly1305，默认 aes-128-gcm；
-- Surfboard 的 vmess 页同此）。
--
-- 只有模型的 chacha20-poly1305 需要写出来：它的拼写与客户端不同
-- （chacha20-ietf-poly1305），不写这个参数 Surge 会按默认的 aes-128-gcm 去连，
-- chacha20 的节点**静默用错算法**——握手失败或更糟。aes-128-gcm 是客户端默认值，
-- 写与不写等价，这里仍写出来是为了让导出结果自解释。
-- 其余取值（none / zero / auto / aes-128-cfb）不在客户端的清单里，映射不到就不写
-- 该参数、由客户端取默认值；写一个客户端不认的取值是「写了读不懂的东西」，
-- 与本文件丢弃 wireguard / ssr 同一约定。
local SURGE_VMESS_CIPHER = {
	["aes-128-gcm"] = "aes-128-gcm",
	["chacha20-poly1305"] = "chacha20-ietf-poly1305",
	["chacha20-ietf-poly1305"] = "chacha20-ietf-poly1305",
}

-- 支持 Reality 的目标格式。Reality 只在 Loon 的节点行里有官方文档：
-- nsloon.app/docs/Node/ 给出 VLESS / VMess / Trojan / AnyTLS 的 Reality 示例，
-- 统一用 public-key / short-id 两个具名参数。
--
-- Surge 家族没有 Reality：Surge 手册的协议清单里没有 VLESS，共享 TLS 参数页
-- （manual.nssurge.com/policies/tls.html）也只列 skip-cert-verify / sni / alpn /
-- server-cert-verify-name / server-cert-fingerprint-sha256 / client-cert，
-- 没有任何公钥参数；Surfboard 的 AnyTLS 文档同样只有 password / skip-cert-verify /
-- sni / server-cert-fingerprint-sha256 / reuse。给它们写 public-key 是「写了客户端
-- 不认识的参数」，节点必然连不上，那个参数对客户端也只是噪声。
-- 注意：Surge 对「不认识的代理行 / 参数」的处置**没有官方依据** —— 官方只说明过
-- 无法识别的 *section* 会原样保留且不报错，代理行的情况未提及（本仓库早期的注释
-- 与 LEGACY_ISSUES 里写的「会拒绝加载整份配置」未经证实，已按此更正）。
-- 所以这里的判据是「不写客户端读不懂的东西」，与本文件丢弃 wireguard / ssr 同一约定，
-- 不依赖任何未经证实的「整份配置会被拒绝」前提。
-- Egern 确实有 Reality，但它的写法是 YAML 里的 reality 对象，与本文件输出的逗号行
-- 对不上 —— 那部分由 output_egern.lua 实现（7.2 已实施）。
local REALITY_FLAVORS = { loon = true }

-- 各 Surge 系客户端对「非通用协议」的支持情况。
--
-- 通用协议（shadowsocks / vmess / trojan / socks5 / http / hysteria2 / tuic /
-- anytls）各家都认；各家**不一致**的是 VLESS、SSR 与 Hysteria（v1）三个，
-- 所以只记这三个。注意 Hysteria **2** 是通用的，各家都支持；不一致的是它的
-- 上一代 Hysteria v1。
-- 用一张表而不是给每个调用点传布尔参数：此前是 `supports_ssr` 一个布尔量，
-- 加一个维度就要再加一个参数，调用点一多必然漏传（漏传的默认值还是「支持」，
-- 于是导出里多出客户端读不懂的行，且不报错）。
--
-- 依据（均为各客户端官方文档的协议清单）：
--   * Surge / SurgeMac：manual.nssurge.com 的 Proxy Protocols 一节只列
--     HTTP and HTTP/2、SOCKS5、Shadowsocks、Snell、VMess、Trojan、TUIC、
--     Hysteria 2、MASQUE、AnyTLS、Trust Tunnel、SSH、WireGuard、Tailscale
--     —— 没有 VLESS、没有 ShadowsocksR，也没有 Hysteria（v1）。
--     Hysteria v1 的证据：清单里写的是 "Hysteria 2"，且同目录下
--     manual.nssurge.com/policies/hysteria2.html 存在而 hysteria.html 是 404。
--   * Surfboard：getsurfboard.com 的 external-proxy 清单同样没有 VLESS / SSR。
--     （Surfboard 是否有 Hysteria v1 未获证据：该站文档的
--     profile-format/proxy/external-proxy 一节及其无斜杠形式都返回 404。
--     既然无法证实「读不懂」，就不替它丢弃 —— 见 LEGACY_ISSUES 的 (j)，
--     该条已实施：Surge / SurgeMac 丢弃 Hysteria v1，Surfboard 按此保留。）
--   * Loon：nsloon.app/docs/Node/ 有独立的 VLESS 与 ShadowsocksR 两节，都支持；
--     但节点类型清单里**只有 Hysteria2**，没有 Hysteria（v1）—— 与 Surge 家族
--     相反的两处之一（另一处是 VLESS / SSR）。
--
-- Egern **不在**这张表里：它的配置是 YAML，已由 output_egern.lua 单独实现
-- （7.2 已实施）。它的协议清单与 Surge 家族本就不同（有 VLESS 与 WireGuard，
-- 没有 SSR 与 Hysteria v1），能力判定一并搬到了那个模块里。
--
-- 注意 hysteria 指的是**上一代 v1**：Hysteria 2 是各家通用的，被丢的只有 v1
-- （两者在 surge_line 里共用同一个输出分支，靠 proto 区分）。
local FAMILY_CAPS = {
	surge     = { vless = false, ssr = false, hysteria = false },
	surfboard = { vless = false, ssr = false },
	surgemac  = { vless = false, ssr = false, hysteria = false },
	-- Loon 支持 VLESS 与 SSR（与 Surge 家族相反），但没有 Hysteria v1
	-- （节点类型清单里只有 Hysteria2）。标 false 即整条丢弃，与丢弃 wireguard
	-- 同一约定：不输出客户端读不懂的东西。
	loon      = { vless = true,  ssr = true, hysteria = false },
}

-- 生成 Surge 风格代理行（Surge / Surfboard / SurgeMac / Loon 通用）。
-- flavor 取目标格式名，只用于「各客户端写法确实不同」的参数 —— 目前是 AnyTLS
-- 密码的位置与 Reality 是否支持；其余参数各家共用同一套 Surge 语法。
function M.surge_line(n, flavor)
	flavor = flavor or "surge"
	local proto = props(n)
	local head_parts = { proto, n.server or "", tostring(n.port or 0) }
	-- 位置参数：紧跟端口之后的字段（Surfboard / Loon 的 AnyTLS 密码写在这里）。
	-- 与 e（具名 key=value 列表）分开攒，最后按「端口, 位置参数…, 具名参数…」拼接。
	local positional = {}
	local e = {}
	local tls = (n.security and n.security ~= "none") or (n.tls and n.tls ~= false and n.tls ~= "none")

	-- TLS 开关的**参数名**各家不同：
	--   Surge / Surfboard / SurgeMac：`tls=true`
	--     （manual.nssurge.com/policies/vmess.html 与 .../vless.html 的 tls 参数）
	--   Loon：`over-tls=true`
	--     （nsloon.app/docs/Node/ 通篇用 over-tls；文档只为 ws 传输列过别名
	--      「ws=true ↔ transport=ws」，从没把 tls 列为 over-tls 的别名）
	-- 只换名字，不换语义：两边都是「本连接走 TLS」这一个布尔量。
	local is_loon = (flavor == "loon")
	local tls_flag = is_loon and "over-tls=true" or "tls=true"

	-- Loon 的凭据写法：端口之后的**位置参数**且用双引号包起来
	--   Trojan = Trojan,h,p,"密码"
	--   VLESS  = VLESS,h,p,"UUID"
	--   VMess  = VMess,h,p,加密方式,"UUID"
	-- （nsloon.app/docs/Node/）。Surge / Surfboard / SurgeMac 沿用同一套语法的
	-- 具名写法（password= / username=），所以只在 flavor == "loon" 时分叉。
	--
	-- 返回 nil 表示这个值用带引号的位置参数表达不了：值里本身含双引号时，
	-- 包裹后的 `"pa"ss"` 该怎么切由客户端自行决定，没有文档依据 —— 调用方
	-- 据此整条丢弃该节点（与「值里含逗号」同一约定，见函数末尾的检查）。
	local function loon_positional(v)
		v = v or ""
		if v:find('"', 1, true) then return nil end
		return '"' .. v .. '"'
	end

	-- ws 传输参数。vmess 与 vless 都要输出：这两个协议在 Surge 家族里共用同一套
	-- 参数名，此前只有 vmess 分支写了，vless + ws 的节点导出后丢掉整个传输层，
	-- 客户端按 tcp 去连一个只开了 ws 的端口，握手必然失败且不报错。
	local function add_ws()
		if n.net == "ws" then
			e[#e + 1] = "ws=true"
			if n.path then e[#e + 1] = "ws-path=" .. n.path end
			if n.host then e[#e + 1] = "ws-headers=Host:" .. n.host end
		end
	end

	-- Reality 参数。Loon 的 VLESS / VMess / Trojan / AnyTLS Reality 示例共用
	-- public-key（Base64 公钥）与 short-id（十六进制）这两个参数名
	-- （nsloon.app/docs/Node/ 原文：「public-key 和 short-id 用于 Reality」）。
	--
	-- 判据取「有没有 public-key」而不是 security == "reality"：public-key 就是
	-- Reality 的凭据，缺了它客户端根本连不上；而 security 在两种来源里含义不同 ——
	-- 分享链接写 security=reality，Loon 的行则写 over-tls=true + public-key
	-- （security 只是 tls）。只看 security 会漏掉后者，导出后 Reality 参数全丢。
	local function add_reality()
		-- 只有 Loon 的节点行文档化了 Reality 参数（见 REALITY_FLAVORS 的说明）
		if not REALITY_FLAVORS[flavor] then return end
		if not n["public-key"] then return end
		-- Loon 文档把公钥画成带双引号的值，short-id 不带：
		--   `public-key="LgJ9bNTyUqBLFkDA12-QgEL7c1yQ1ztk-V1Q-3OLXSk",short-id=164168844958a16d`
		-- （nsloon.app/docs/Node/ 的 VLESS / VMess / Trojan / AnyTLS Reality 示例）。
		-- Base64 字母表（A-Za-z0-9+/=）里没有双引号，加引号只是写法对齐，
		-- 不会引入歧义，也不会与下面的逗号检查冲突。
		e[#e + 1] = 'public-key="' .. n["public-key"] .. '"'
		if n["short-id"] then e[#e + 1] = "short-id=" .. n["short-id"] end
	end

	if proto == "shadowsocks" then
		local cipher = n.method or n.cipher or "aes-256-gcm"
		if is_loon then
			-- Loon 的 Shadowsocks 把加密方式与密码都画在位置参数上，密码带双引号：
			--   `Shadowsocks,服务器,端口,加密方式,"密码"`（nsloon.app/docs/Node/）
			-- 加密方式是裸值，与 VMess 行的加密方式同形。
			-- 此前写成具名的 encrypt-method= / password=，落在 Loon 的语法里就是
			-- 第 4、5 个位置参数各拿到一串 `key=value` 文本 —— 加密方式解析不出来，
			-- 密码也不再是密码，节点必然连不上。
			local pw = loon_positional(n.password)
			if not pw then return nil end
			positional[#positional + 1] = cipher
			positional[#positional + 1] = pw
		else
			e[#e + 1] = "encrypt-method=" .. cipher
			e[#e + 1] = "password=" .. (n.password or "")
		end
	elseif proto == "vmess" then
		if flavor == "loon" then
			-- Loon 的 VMess 把加密方式与 UUID 都放在位置参数上（见 loon_positional）
			local id = loon_positional(n.uuid)
			if not id then return nil end
			-- 加密方式取值按 Loon 的拼写映射（见 LOON_VMESS_CIPHER）
			positional[#positional + 1] = LOON_VMESS_CIPHER[n.cipher] or "auto"
			positional[#positional + 1] = id
		else
			e[#e + 1] = "username=" .. (n.uuid or "")
			-- Surge 家族把加密方式写在具名参数 encrypt-method 上（见 SURGE_VMESS_CIPHER）
			local sc = SURGE_VMESS_CIPHER[n.cipher]
			if sc then e[#e + 1] = "encrypt-method=" .. sc end
		end
		if tls then e[#e + 1] = tls_flag end
		if n.sni then e[#e + 1] = "sni=" .. n.sni end
		-- VMess 的 Reality 与 VLESS 同形。Loon 文档的 VMess-Reality 示例：
		-- `VMess = VMess,host,443,aes-128-gcm,"uuid",transport=tcp,alterId=0,`
		-- `public-key="…",short-id=…,over-tls=true`（nsloon.app/docs/Node/）。
		-- 此前只在 vless / trojan / anytls 三个分支调了 add_reality()，vmess 的
		-- Reality 节点导出到 Loon 后 public-key / short-id 全丢 —— 客户端按普通
		-- TLS 去连，REALITY 握手建立不起来，而 Loon 不会因此报错。
		add_reality()
		add_ws()
	elseif proto == "vless" then
		if flavor == "loon" then
			-- Loon 的 VLESS 只有一个位置参数：UUID（见 loon_positional）
			local id = loon_positional(n.uuid)
			if not id then return nil end
			positional[#positional + 1] = id
		else
			e[#e + 1] = "username=" .. (n.uuid or "")
		end
		if tls then e[#e + 1] = tls_flag end
		if n.sni then e[#e + 1] = "sni=" .. n.sni end
		if n.flow then e[#e + 1] = "flow=" .. n.flow end
		add_reality()
		add_ws()
	elseif proto == "trojan" then
		if flavor == "loon" then
			-- Loon 的 Trojan 只有一个位置参数：密码（见 loon_positional）
			local pw = loon_positional(n.password)
			if not pw then return nil end
			positional[#positional + 1] = pw
		else
			e[#e + 1] = "password=" .. (n.password or "")
		end
		-- Loon 的 Trojan 行**没有** TLS 开关：nsloon.app/docs/Node/ 的明文与 Reality
		-- 两条示例都只写 `Trojan,服务器,端口,"密码",sni=…[,public-key=…,short-id=…]`，
		-- 既没有 over-tls 也没有 tls。Trojan 本身就建立在 TLS 之上，Loon 不再要这个
		-- 开关；写上去是客户端读不懂的参数。Surge 家族的 tls=true 相反是文档要求的。
		if not is_loon then e[#e + 1] = "tls=true" end
		if n.sni then e[#e + 1] = "sni=" .. n.sni end
		add_reality()
	elseif proto == "anytls" then
		-- AnyTLS 建立在 TLS 之上，协议本身没有明文模式，行里也就没有 tls 开关
		-- （Surge 手册：TLS 总是启用，共用 TLS 参数；sing-box 把 tls 标为 Required）。
		--
		-- 密码的写法各家不同，且三家都有官方文档，只能按 flavor 分别输出：
		--   Surge（iOS 5.17.0+ / Mac 6.4.3+）与 SurgeMac：具名参数
		--     `Name = anytls, host, port, password=pwd`
		--     （manual.nssurge.com/policies/anytls.html）
		--   Surfboard：端口之后的位置参数，裸值不带引号
		--     `Name = anytls, host, port, password, skip-cert-verify=true, ...`
		--     （getsurfboard.com/docs/profile-format/proxy/external-proxy/anytls/）
		--   Loon：端口之后的位置参数，值用双引号包起来
		--     `Name = AnyTLS,host,port,"password",sni=...`（nsloon.app/docs/Node/）
		-- 其余 flavor（surge / surgemac）走上面的具名写法。
		-- （Egern 已不在本文件里 —— 它的配置是 YAML，见 output_egern.lua。）
		--
		-- 按 flavor 分叉的协议不止 anytls：Loon 的 vmess / vless / trojan /
		-- shadowsocks / ssr / hysteria2 同样把凭据画在位置参数上，TLS 开关与 UDP
		-- 参数的名字也和 Surge 家族不同 —— 那些分叉在各分支里就地处理（见
		-- is_loon / tls_flag 与 loon_positional 上方的说明）。anytls 的特别之处
		-- 只在于它的密码写法在**三家之间**都不同（Surge 具名 / Surfboard 裸位置
		-- 参数 / Loon 带引号位置参数），所以只有它在这里写成了三分支。
		if flavor == "surfboard" then
			positional[#positional + 1] = n.password or ""
		elseif flavor == "loon" then
			local pw = loon_positional(n.password)
			if not pw then return nil end
			positional[#positional + 1] = pw
		else
			e[#e + 1] = "password=" .. (n.password or "")
		end
		if n.sni then e[#e + 1] = "sni=" .. n.sni end
		add_reality()
	elseif proto == "ssr" then
		local cipher = n.method or n.cipher or "aes-128-cfb"
		if is_loon then
			-- Loon 的 ShadowsocksR 同样把加密方式与密码放在位置参数上（密码带引号），
			-- 其余仍是具名参数：
			--   `ShadowsocksR,服务器,端口,加密方式,"密码",protocol=…,obfs=…`
			-- （nsloon.app/docs/Node/）。具名的 encrypt-method= / password= 在这里
			-- 会各自占掉一个位置参数，加密方式与密码都解析不出来。
			local pw = loon_positional(n.password)
			if not pw then return nil end
			positional[#positional + 1] = cipher
			positional[#positional + 1] = pw
		else
			e[#e + 1] = "encrypt-method=" .. cipher
			e[#e + 1] = "password=" .. (n.password or "")
		end
		e[#e + 1] = "protocol=" .. (n.protocol or "origin")
		e[#e + 1] = "obfs=" .. (n.obfs or "plain")
		local op = n.obfs_param or n["obfs-param"]
		local pp = n.protocol_param or n["protocol-param"]
		if op and op ~= "" then e[#e + 1] = "obfs-param=" .. op end
		if pp and pp ~= "" then e[#e + 1] = "protocol-param=" .. pp end
	elseif proto == "hysteria2" or proto == "hysteria" then
		if is_loon then
			-- Loon 的 Hysteria2 把密码放在位置参数上，带双引号：
			--   `Hysteria2,服务器,端口,"密码",sni=…`（nsloon.app/docs/Node/）
			local pw = loon_positional(n.password)
			if not pw then return nil end
			positional[#positional + 1] = pw
		else
			e[#e + 1] = "password=" .. (n.password or "")
		end
		if n.sni then e[#e + 1] = "sni=" .. n.sni end
	elseif proto == "tuic" then
		e[#e + 1] = "username=" .. (n.uuid or "")
		if n.password then e[#e + 1] = "password=" .. n.password end
		if n.sni then e[#e + 1] = "sni=" .. n.sni end
		if n.alpn then
			-- alpn 可能是数组：sing-box JSON 与 Clash YAML 的 alpn 列表导入后就是 table，
			-- 直接拼接会 "attempt to concatenate a table value" 让整次导出失败
			local alpn = n.alpn
			if type(alpn) == "table" then alpn = table.concat(alpn, ",") end
			-- 多值 alpn 在这里表达不了：Surge 家族的行是逗号分隔的 key=value，
			-- 没有引号 / 转义，`alpn=h3,h2` 会被读成 `alpn=h3` 加一个悬空字段。
			-- 但 alpn 只是协商提示，缺省时客户端会用服务端给出的列表，
			-- 不像密码那样一旦被截断就静默发错凭据 —— 所以这里丢掉该参数、
			-- 保留节点，而不是像下面的通用逗号检查那样整条丢弃。
			if alpn ~= "" and not alpn:find(",", 1, true) then
				e[#e + 1] = "alpn=" .. alpn
			end
		end
	elseif proto == "socks5" or proto == "socks" or proto == "http" then
		-- socks5 / http 在 Surge 家族里都用 username= / password= 具名参数
		-- （Surge 手册：Name = http, <host>, <port>[, <username>, <password>]
		--   "may be given positionally after the port, or as named parameters"）
		if n.username then
			e[#e + 1] = "username=" .. n.username
			if n.password then e[#e + 1] = "password=" .. n.password end
		end
	else
		-- 未知协议：以前会一路掉到这里，生成 `Name = snell, host, port` 这样的残行。
		-- 客户端遇到不认识的类型，这一个节点必然不可用（是跳过该节点还是拒绝加载
		-- 整份配置，各家均未获官方证实），没有理由把它输出出去。
		-- 返回 nil 由调用方整条剔除，与下面「值里含逗号」同一约定。
		return nil
	end

	-- 取值写 true/false，不写 1：Loon 文档的示例就是 `skip-cert-verify=false`
	-- （nsloon.app/docs/Node/ 的 Hysteria2 一行），直接证明 false 是合法字面量、
	-- true 同理；而 Surge 手册的 TLS 页只写「Optional, boolean, default: false」，
	-- 两家的文档里都找不到 `1` 这个取值。解析端两种都认
	-- （parser_surge 把非 "0" / 非 "false" 都当 true），所以回环不受影响。
	if n["skip-cert-verify"] then e[#e + 1] = "skip-cert-verify=true" end
	-- UDP 转发的参数名同样各家不同：Surge 家族是 udp-relay=true，Loon 是 udp=true
	-- （nsloon.app/docs/Node/ 的每个示例都写 udp=true，udp-relay 一次都没出现；
	-- 相关的另外两个开关叫 udp-over-tcp / udp-port）。
	if n.udp then e[#e + 1] = is_loon and "udp=true" or "udp-relay=true" end

	-- 参数值里的逗号无法用这些格式表达，整条丢弃（返回 nil，由调用方剔除）。
	-- [Proxy] 行与 QX 的 [server_local] 行都是逗号分隔的 `key=value` 序列，
	-- 语法里没有引号 / 转义机制：`password=pa,ss` 会被读成 `password=pa` 加上
	-- 一个悬空的 `ss` 字段 —— 凭据被静默截断，用户不会收到任何提示。
	-- 节点名里的逗号已由 names_of 单独处理（不进成员列表），但名字在 `=` 左侧，
	-- 不影响本行解析；值在右侧，必须在这里挡掉。
	for _, kv in ipairs(e) do
		local v = kv:match("^[^=]*=(.*)$")
		if v and v:find(",", 1, true) then return nil end
	end
	-- 位置参数（Loon 的凭据写法）按官方文档是带双引号包裹的，而 Loon 文档明说
	-- 「参数值中含有英文逗号时，请使用双引号包裹」（nsloon.app/docs/Node/）——
	-- 也就是说那对引号**确实**能保住逗号。这里仍然按「值里含逗号就整条丢弃」
	-- 处理，是刻意的保守选择：本行的具名参数（sni= / ws-path= / ws-headers=Host:）
	-- 一律不带引号，同一行里两种约定混用会让「哪个值被包裹」变成依赖客户端实现
	-- 的行为；统一丢弃最容易验证，代价只是极少见的「密码里带逗号」的节点。
	-- （值里本身带双引号的情况已由 loon_positional 在构造时挡掉。）
	for _, v in ipairs(positional) do
		if v:find(",", 1, true) then return nil end
	end

	for _, v in ipairs(positional) do head_parts[#head_parts + 1] = v end
	local line = (n.name or "") .. " = " .. table.concat(head_parts, ", ")
	if #e > 0 then line = line .. ", " .. table.concat(e, ", ") end
	-- 节点名与各参数值都来自订阅（不可信）：含换行会截断本行并伪造出一条新的代理行
	return util.one_line(line)
end

-- 收集可用于「逗号分隔成员列表」的节点名（Surge 家族 [Proxy Group] / QX [policy]）。
--
-- 两类名字必须排除，否则生成的配置整体非法：
--   * 含逗号：这些格式的成员列表就是 `NAME = select, X, Y, DIRECT`，语法里没有
--     引号 / 转义机制，名字里的逗号会被当成成员分隔符 —— `A,B` 被读成两个成员
--     `A` 与 `B`，两个都不存在（客户端的处置未获官方证实，但引用不存在的代理
--     无论如何都不是用户想要的结果）。节点定义本身仍留在 [Proxy] /
--     [server_local] 中，只是不进成员列表。
--   * 换行：定义行经过 util.one_line（换行→空格），成员列表若用原始名就对不上
--     定义行，同样成为悬空引用。这里统一先 one_line 再比对，保证两边一致。
local function names_of(nodes)
	local out = {}
	for _, n in ipairs(nodes or {}) do
		local nm = util.one_line(n.name)
		if nm and nm ~= "" and not nm:find(",", 1, true) then
			out[#out + 1] = nm
		end
	end
	return out
end

-- Surge 家族配置（Surge / Surfboard / SurgeMac / Loon 通用）
-- flavor：目标格式名。既决定 surge_line 里按客户端分叉的少数参数，也用来查
-- FAMILY_CAPS —— 每个调用点不再各自传「支持什么」的布尔量（见 FAMILY_CAPS 的说明）。
local function surge_config(nodes, group_name, flavor)
	local caps = FAMILY_CAPS[flavor] or {}
	local list = nodes or {}
	-- 过滤 Surge 家族无法用单行 [Proxy] 表达的协议：
	--   vless / ssr：按 FAMILY_CAPS 分客户端（Surge/Surfboard/SurgeMac 两个都不认）
	--   hysteria：同样按 FAMILY_CAPS（Surge/SurgeMac 只有 Hysteria 2，没有 v1；
	--     Surfboard 未获证据，本表没对它表态，故保留）
	--   wireguard：Surge 需专用多段 [WireGuard] 配置，单行无法表达，统一丢弃（不输出损坏行）
	local kept = {}
	for _, n in ipairs(list) do
		local p = (n.proto or ""):lower()
		if p == "wireguard" then
			-- drop
		elseif caps[p] == false then
			-- drop：能力表显式标了 false 的协议。写成数据驱动而不是逐个协议写
			-- `elseif p == "ssr" and not caps.ssr`：每加一个维度就要再加一条分支，
			-- 漏掉的那条默认是「保留」，于是导出里多出客户端读不懂的行且不报错。
			-- （caps[p] 为 nil 表示「这张表没对它表态」，一律保留。）
		else
			kept[#kept + 1] = n
		end
	end
	list = kept
	local out = {}
	out[#out + 1] = "[Proxy]"
	-- surge_line 对「值里含逗号」这类无法表达的节点返回 nil，这些节点必须
	-- 同时从成员列表里剔除 —— 否则 [Proxy Group] 会引用一个不存在的代理。
	local rendered = {}
	for _, n in ipairs(list) do
		local line = M.surge_line(n, flavor)
		if line then
			out[#out + 1] = line
			rendered[#rendered + 1] = n
		end
	end
	out[#out + 1] = ""
	out[#out + 1] = "[Proxy Group]"
	local names = names_of(rendered)
	local select = group_name .. " = select"
	for _, nm in ipairs(names) do select = select .. ", " .. nm end
	select = select .. ", DIRECT"
	out[#out + 1] = util.one_line(select)
	return table.concat(out, "\n")
end

function M.to_surge(nodes, options)
	options = options or {}
	return surge_config(nodes, options.name or "PROXY", "surge")
end

function M.to_surfboard(nodes, options)
	options = options or {}
	return surge_config(nodes, options.name or "PROXY", "surfboard")
end

function M.to_surgemac(nodes, options)
	options = options or {}
	return surge_config(nodes, options.name or "PROXY", "surgemac")
end

-- Loon：Surge 兼容语法（支持 VLESS 与 SSR）
function M.to_loon(nodes, options)
	options = options or {}
	return surge_config(nodes, options.name or "PROXY", "loon")
end

-- Egern 不在本文件里：它的配置是 YAML，而不是这里的逗号行，所以由
-- output_egern.lua 单独实现（LEGACY_ISSUES 的 7.2 已实施）。
-- 此前这里是 `surge_config(nodes, name, "egern")` —— 导出的是 Surge 的逗号行，
-- Egern 根本读不了。

-- Stash：Clash 兼容 YAML
function M.to_stash(nodes, options)
	return clash_meta.generate(nodes, options)
end

-- Clash 原版（Dreamacro Clash / ClashX / Clash for Windows）不支持的协议类型。
-- 只排除"确定不支持"的，不做白名单，避免误丢原版其实支持的类型。
local CLASH_LEGACY_UNSUPPORTED = {
	vless = true, hysteria2 = true, hysteria = true, tuic = true, wireguard = true,
	-- anytls 同样是原版 Clash 之后才出现的类型（Dreamacro/clash 的配置参考里
	-- 只有 ss / ssr / vmess / snell / trojan / http / socks5）。不排除的话
	-- to_clash 会把它交给 clash_meta 生成 `type: anytls`，原版 Clash 解析到
	-- 未知类型会拒绝加载整份配置。
	anytls = true,
}

-- Clash 原版：过滤掉原版不认识的协议后，复用 Clash.Meta 的 YAML 生成
function M.to_clash(nodes, options)
	local kept = {}
	for _, n in ipairs(nodes or {}) do
		local p = props(n)
		if not CLASH_LEGACY_UNSUPPORTED[p] then kept[#kept + 1] = n end
	end
	return clash_meta.generate(kept, options)
end

-- QX 的 ws / tls 具名参数。vmess 与 vless 在 QX 里共用同一套参数名，
-- 两个分支必须写出完全一致的集合 —— 此前 vless 一个都没写，vless + ws + tls
-- 的节点导出成明文 tcp 条目，客户端按 tcp 去连只开了 ws 的端口，必然失败且不报错。
local function qx_transport(n, f)
	if n.net == "ws" then
		f[#f + 1] = "obfs=ws"
		if n.path then f[#f + 1] = "obfs-uri=" .. n.path end
		if n.host then f[#f + 1] = "obfs-host=" .. n.host end
	end
end

-- 注意：带 Reality 公钥的 vmess / vless 不走这里，改走 qx_obfs_reality
-- （QX 只认 obfs= 形式的 TLS 标志，见该函数的说明）。
local function qx_tls(n, f)
	if n.sni then f[#f + 1] = "tls-host=" .. n.sni end
	if n.security and n.security ~= "none" then f[#f + 1] = "tls-verification=true" end
end

-- QX 的 vmess / vless **带 Reality 公钥**时的传输 / TLS 标志。
--
-- 官方 sample.conf（crossutility/Quantumult-X 仓库）的 [server_local] 前写明：
--
--   …if the corresponding line (socks5: over-tls=true, http: over-tls=true,
--   trojan: over-tls=true or obfs=wss, anytls: over-tls=true, … vmess:
--   obfs=over-tls or obfs=wss, vless: obfs=over-tls or obfs=wss) contains the
--   reality-base64-pubkey param, then the standard TLS will be replaced with
--   the Reality.
--
-- 即 vmess / vless 的「TLS 标志」在 QX 里是 obfs= 形式，而 qx_tls() 对所有协议
-- 统一输出 tls-host= + tls-verification=。两者写法不一致时 QX 会忽略公钥，
-- 节点静默退回普通 TLS（握手必失败）。所以带公钥的 vmess / vless 改走这里，
-- 不带公钥的一律不动 —— qx_tls() 是既有实现，全量改写会让所有 QX vmess / vless
-- TLS 节点的输出形态变化（`tls-host` / `tls-verification` 对 vmess / vless 是否
-- 同样有效没有官方依据：sample.conf 里只用 obfs= 形式，但「未出现」≠「无效」）。
--
-- obfs 取值与 qx_transport 对齐：ws + TLS 写 wss，纯 TLS 写 over-tls。
-- wss 下 obfs-host 同时充当 TLS 握手名与 Host 头（sample.conf 的注释），
-- 所以 host 优先、退回 sni；over-tls 下 obfs-host 只是 SNI。
local function qx_obfs_reality(n, f)
	if n.net == "ws" then
		f[#f + 1] = "obfs=wss"
		if n.path then f[#f + 1] = "obfs-uri=" .. n.path end
		local h = n.host or n.sni
		if h then f[#f + 1] = "obfs-host=" .. h end
	else
		f[#f + 1] = "obfs=over-tls"
		if n.sni then f[#f + 1] = "obfs-host=" .. n.sni end
	end
end

-- QX 的 Reality 参数。官方 sample.conf 的 [server_local] 里，vmess / vless /
-- trojan / anytls 四类条目都用这两个键：Base64 公钥 reality-base64-pubkey 与
-- 十六进制 reality-hex-shortid。sample.conf 的注释写明「只要该行设置了
-- reality-base64-pubkey，标准 TLS 就会被换成 Reality TLS」。判据取「有没有
-- public-key」，与 surge_line 的 add_reality 一致。
--
-- TLS 标志由调用方负责：vmess / vless 走 qx_obfs_reality（obfs=over-tls / wss），
-- trojan / anytls 走 over-tls=true + tls-host=。
local function qx_reality(n, f)
	if not n["public-key"] then return end
	f[#f + 1] = "reality-base64-pubkey=" .. n["public-key"]
	if n["short-id"] then f[#f + 1] = "reality-hex-shortid=" .. n["short-id"] end
end

-- 单条 [server_local] 定义行。返回 nil 表示该节点无法用 QX 的行语法表达，
-- 由调用方整条剔除（定义行与 [policy] 成员一并去掉）。
--
-- 具名字段先攒成列表再拼接，而不是边拼字符串边追加：值里含逗号的条目在逗号
-- 分隔语法里表达不了（`password=pa,ss` 会被读成 `password=pa` 加一个悬空字段，
-- 凭据被静默截断），必须能逐字段判定后整条丢弃。若先拼成整行再回头用模式去切，
-- 行内本来就有的 `, ` 结构分隔符与值里的逗号无法区分 —— 会把每条合法行都误判成非法。
local function qx_server_line(n, tag)
	local proto = props(n)
	local host = (n.server or "") .. ":" .. tostring(n.port or 0)
	local f = {}
	if proto == "shadowsocks" then
		f[#f + 1] = "method=" .. (n.method or n.cipher or "aes-256-gcm")
		f[#f + 1] = "password=" .. (n.password or "")
	elseif proto == "vmess" then
		f[#f + 1] = "method=none"
		f[#f + 1] = "password=" .. (n.uuid or "")
		-- 带 Reality 公钥的 vmess 必须用 obfs= 形式的 TLS 标志，否则 QX 忽略公钥
		-- （见 qx_obfs_reality 的说明）。不带公钥的维持既有写法。
		if n["public-key"] then qx_obfs_reality(n, f) else qx_transport(n, f); qx_tls(n, f) end
		-- sample.conf 有 vmess 的 Reality 条目（obfs=over-tls + reality-base64-pubkey
		-- + reality-hex-shortid），此前只给 vless / anytls 输出了公钥。
		qx_reality(n, f)
	elseif proto == "vless" then
		f[#f + 1] = "method=none"
		f[#f + 1] = "password=" .. (n.uuid or "")
		if n["public-key"] then qx_obfs_reality(n, f) else qx_transport(n, f); qx_tls(n, f) end
		-- sample.conf 的 vless Reality 条目在公钥之外还带 vless-flow=xtls-rprx-vision
		if n["public-key"] and n.flow then f[#f + 1] = "vless-flow=" .. n.flow end
		qx_reality(n, f)
	elseif proto == "trojan" then
		f[#f + 1] = "password=" .. (n.password or "")
		f[#f + 1] = "over-tls=true"
		if n.sni then f[#f + 1] = "tls-host=" .. n.sni end
		-- sample.conf 的 trojan Reality 条目就是这一形：
		-- `trojan=host:443, password=pwd, over-tls=true, tls-host=apple.com,`
		-- `reality-base64-pubkey=…, reality-hex-shortid=…, tag=…`
		qx_reality(n, f)
	elseif proto == "anytls" then
		-- QX 1.6.0 起支持 anytls（版本号只有第三方转述，语法本身取自官方
		-- sample.conf）。写法与上面的 trojan 同形：
		-- `anytls=host:port, password=pwd, over-tls=true, tls-host=<sni>, ...`
		f[#f + 1] = "password=" .. (n.password or "")
		f[#f + 1] = "over-tls=true"
		if n.sni then f[#f + 1] = "tls-host=" .. n.sni end
		qx_reality(n, f)
	end
	if #f == 0 then return nil end
	for _, kv in ipairs(f) do
		local v = kv:match("^[^=]*=(.*)$")
		if v and v:find(",", 1, true) then return nil end
	end
	-- 节点名 / sni / path / host 全部来自订阅（不可信），含换行会截断本行并
	-- 伪造出一条新的 server_local 行。tag 排在最后。
	return util.one_line(
		proto .. "=" .. host .. ", " .. table.concat(f, ", ") .. ", tag=" .. tag)
end

-- Quantumult X
function M.to_qx(nodes, options)
	options = options or {}
	local out = {}
	-- 真正写出了 [server_local] 行的节点。QX 只支持下面这 5 类协议
	-- （shadowsocks / vmess / vless / trojan / anytls），其余节点
	-- （hysteria2 / hysteria / tuic / socks / wireguard / ssr …）没有定义行；
	-- [policy] 若把它们也列进去，就成了引用不存在服务器的悬空条目。
	local emitted = {}
	out[#out + 1] = "[server_local]"
	for _, n in ipairs(nodes or {}) do
		local tag = util.one_line(n.name or ((n.server or "") .. ":" .. tostring(n.port or 0)))
		-- 名字里的逗号落在 `tag=` 的值上，而本行是逗号分隔的 `key=value` 序列，
		-- 语法里没有引号 / 转义：`tag=A,B` 会被读成 `tag=A` 加一个悬空字段。
		-- QX 对这种行的实际处置未经核实（本机没有 QX 可实测），但无论它是报错
		-- 还是静默忽略，用户拿到的都不是他填的那个名字 —— 所以整条丢弃，与
		-- Surge 家族丢 wireguard / ssr、Clash 原版丢不支持协议同一约定，也与
		-- 下面 [policy] 成员列表的排除条件（names_of）保持一致。
		-- 注意判定用 one_line 之后的名字：names_of 也是先 one_line 再比对，
		-- 两边必须用同一个字符串，否则定义行与成员列表会对不上。
		if not tag:find(",", 1, true) then
			local line = qx_server_line(n, tag)
			if line then
				out[#out + 1] = line
				emitted[#emitted + 1] = n
			end
		end
	end
	out[#out + 1] = ""
	out[#out + 1] = "[policy]"
	local names = names_of(emitted)
	local policy = "static=" .. (options.name or "PROXY") .. ", DIRECT"
	for _, nm in ipairs(names) do policy = policy .. ", " .. nm end
	out[#out + 1] = util.one_line(policy)
	out[#out + 1] = ""
	out[#out + 1] = "[server_remote]"
	return table.concat(out, "\n")
end

-- Plain JSON：节点统一模型 JSON 数组
function M.to_plain(nodes)
	return util.json_encode(nodes or {})
end

-- 统一分发
function M.generate(nodes, format, options)
	format = (format or ""):lower()
	if format == "surge" then return M.to_surge(nodes, options) end
	if format == "surfboard" then return M.to_surfboard(nodes, options) end
	if format == "surgemac" then return M.to_surgemac(nodes, options) end
	if format == "loon" then return M.to_loon(nodes, options) end
	-- egern 不在这里：见文件头的说明，它由 output_egern.lua 实现
	if format == "qx" then return M.to_qx(nodes, options) end
	if format == "stash" then return M.to_stash(nodes, options) end
	if format == "clash" then return M.to_clash(nodes, options) end
	if format == "plain" then return M.to_plain(nodes) end
	return nil, msg.join("Unsupported output format: ", tostring(format))
end

return M