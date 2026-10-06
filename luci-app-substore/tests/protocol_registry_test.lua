-- protocol_registry_test.lua — 协议 × 目标格式的注册表一致性（防漂移）
-- 用法：lua5.1 tests/protocol_registry_test.lua
--
-- 这个仓库最反复出现的失效模式是「协议清单散落多处，漏改一处 → 节点被静默丢弃」：
-- 新增一个协议要同时改模型、解析器、若干输出模块和模板，而漏掉任何一处都**不报错**，
-- 只是导出的订阅里少了那个节点（用户看到的仍是「导出成功」）。
--
-- 所以这里不逐个断言注册表常量（它们多是各模块内的 local，取值域也各不相同），
-- 而是走**行为**：把每个协议的最小可用节点喂给每一种目标格式，断言「节点是否出现
-- 在输出里」与下方 DROPPED 表完全一致。DROPPED 是唯一的显式声明，每条都注明
-- 由哪个模块决定，便于审查它是「协议确实不支持」还是「漏接了」。
--
-- 两个方向都会红：
--   * 新协议漏接某个输出 → 该格式下节点消失，但 DROPPED 里没写 → FAIL；
--   * 某格式补上了对某协议的支持（或退化了）→ 与 DROPPED 不符 → FAIL；
--   * 新增目标格式 → 格式清单直接取自 output.FORMAT_OPTIONS，新格式会被遍历到，
--     若它对某协议有过滤而表里没写 → FAIL。

package.path = "./root/usr/share/?.lua;" .. package.path

local util = require("substore.util")
local node = require("substore.node")
local output = require("substore.output")

local passed, failed = 0, 0

local function check(name, cond)
	if cond then
		passed = passed + 1
		print("PASS " .. name)
	else
		failed = failed + 1
		print("FAIL " .. name)
	end
end

-- 每个协议的最小可用节点：只给身份字段，其余交给 node.normalize 补默认值。
-- 样本缺身份字段时输出模块可能因校验而跳过该节点，那会把「协议不支持」与
-- 「样本不全」混为一谈，测试就失去意义了。
local SAMPLES = {
	vmess       = { uuid = "u" },
	vless       = { uuid = "u" },
	trojan      = { password = "p" },
	shadowsocks = { method = "aes-256-gcm", password = "p" },
	ssr         = { password = "p", method = "aes-128-cfb", protocol = "origin", obfs = "plain" },
	hysteria2   = { password = "p" },
	hysteria    = { password = "p" },
	tuic        = { uuid = "u", password = "p" },
	wireguard   = { ["private-key"] = "k", ["public-key"] = "k2", ip = "10.0.0.2/32" },
	socks       = { username = "u", password = "p" },
	anytls      = { password = "p" },
}

-- 分享链接的 scheme。URI 类格式（shadowrocket / v2rayuri）会把节点名编码进
-- base64（vmess 甚至是「base64 里套 base64」），按名字查找必然漏判 ——
-- 只能按 scheme 判断节点有没有被输出。
local SCHEME = {
	vmess = "vmess://", vless = "vless://", trojan = "trojan://",
	shadowsocks = "ss://", ssr = "ssr://", hysteria2 = "hysteria2://",
	hysteria = "hysteria://", tuic = "tuic://", wireguard = "wireguard://",
	socks = "socks5://",
	anytls = "anytls://",
}
local URI_FORMATS = { shadowrocket = true, v2rayuri = true }

-- 目标格式清单取自唯一注册点 output.FORMAT_OPTIONS（不在这里另抄一份）
local FORMATS = {}
for _, opt in ipairs(output.FORMAT_OPTIONS) do FORMATS[#FORMATS + 1] = opt[1] end

-- 每个协议在哪些格式下**会被丢弃**，以及原因（决定它的模块）。
-- 未列出的 (协议, 格式) 一律断言「节点必须出现在输出里」。
local DROPPED = {
	-- output_wireguard_conf 只输出 wireguard 节点，其余一律过滤
	vmess       = { wgconf = "wgconf 只收 wireguard" },
	-- vless：Surge / Surfboard / SurgeMac 的官方协议清单里都没有 VLESS
	-- （manual.nssurge.com 的 Proxy Protocols、getsurfboard.com 的 external-proxy），
	-- Loon 与 Egern 支持（nsloon.app/docs/Node/ 有独立 VLESS 一节、
	-- egernapp.com/docs/configuration/proxies/ 的协议清单含 Vless）；
	-- 原版 Clash 无 VLESS；wgconf 只收 wireguard。过滤点在 surge_config
	-- （查 FAMILY_CAPS），FAMILY_CAPS 是唯一声明。
	vless       = {
		clash = "原版 Clash 无 VLESS", wgconf = "wgconf 只收 wireguard",
		surge = "Surge 无 VLESS", surfboard = "Surfboard 无 VLESS", surgemac = "SurgeMac 无 VLESS",
	},
	trojan      = { wgconf = "wgconf 只收 wireguard" },
	shadowsocks = { wgconf = "wgconf 只收 wireguard" },
	-- ssr：Surge/Surfboard/SurgeMac 不支持（FAMILY_CAPS 的 ssr=false），Egern 也不支持
	-- （output_egern.lua 的 EGERN_KEY 里没有 ssr —— 它的官方协议清单里只有 Shadowsocks，
	--   没有 SSR）；只有 Loon 支持（nsloon.app/docs/Node/ 有独立 ShadowsocksR 一节）；
	-- to_qx 只认 ss/vmess/vless/trojan；singbox 的 supported() 明确排除 ssr；
	-- v2ray 的 V2RAY_PROTOS 里没有 ssr。
	ssr         = {
		surge = "Surge 无 SSR", surfboard = "Surfboard 无 SSR", surgemac = "SurgeMac 无 SSR",
		egern = "Egern 无 SSR（协议清单只有 Shadowsocks，没有 SSR）",
		qx = "to_qx 只认 ss/vmess/vless/trojan", singbox = "singbox 不支持 ssr",
		v2ray = "V2RAY_PROTOS 无 ssr", wgconf = "wgconf 只收 wireguard",
	},
	-- hysteria2 / tuic / hysteria：原版 Clash、qx、v2ray 都不支持
	-- （hysteria v1 另有一处：Egern 的协议清单里只有 Hysteria2。v1 与 v2 的字段结构
	--   不同 —— v1 的 obfs 是普通字符串、没有 obfs_password —— 拿 Hysteria2 的键去顶
	--   会让客户端按错误的协议去连，所以 output_egern.lua 整条丢弃。）
	hysteria2   = { clash = "原版 Clash 无 hysteria2", qx = "to_qx 无 hysteria2",
		v2ray = "V2RAY_PROTOS 无 hysteria2", wgconf = "wgconf 只收 wireguard" },
	tuic        = { clash = "原版 Clash 无 tuic", qx = "to_qx 无 tuic",
		v2ray = "V2RAY_PROTOS 无 tuic", wgconf = "wgconf 只收 wireguard" },
	hysteria    = { clash = "原版 Clash 无 hysteria", qx = "to_qx 无 hysteria",
		v2ray = "V2RAY_PROTOS 无 hysteria", wgconf = "wgconf 只收 wireguard",
		egern = "Egern 只有 Hysteria2，没有 Hysteria v1" },
	-- wireguard：Surge 家族需要专用的多段 [WireGuard] 配置，单行 [Proxy] 表达不了，
	-- surge_config 统一丢弃；原版 Clash / qx / v2ray 同样不支持。
	-- Egern **不在**此列：它的配置是 YAML，WireGuard 有独立的协议块
	-- （private_key / peer_public_key / local_ipv4…），output_egern.lua 能完整表达 ——
	-- 这是 7.2 实施后新获得的能力（此前走 surge_config 的逗号行，只能丢弃）。
	-- （shadowrocket / v2rayuri 会输出本项目自定义的 wireguard:// 链接 —— 这是既有
	--   行为，此处如实记录，并不代表已验证该 scheme 被客户端接受。）
	wireguard   = { clash = "原版 Clash 无 wireguard", surge = "Surge 单行表达不了",
		surfboard = "同 Surge", surgemac = "同 Surge", loon = "同 Surge",
		qx = "to_qx 无 wireguard", v2ray = "V2RAY_PROTOS 无 wireguard" },
	socks       = { qx = "to_qx 无 socks", wgconf = "wgconf 只收 wireguard" },
	-- anytls：mihomo / Stash / sing-box 1.12+ / Shadowrocket / Surge 家族
	-- （Surge iOS 5.17.0+ 与 Mac 6.4.3+、Surfboard、Loon、Egern）以及
	-- QX 1.6.0+ 都支持；原版 Clash（Dreamacro）与 Xray/V2Ray 都不认识该协议
	-- （Xray issue #4428 以 not planned 关闭），wgconf 只收 wireguard。
	anytls      = {
		clash = "原版 Clash 无 anytls", v2ray = "V2RAY_PROTOS 无 anytls",
		wgconf = "wgconf 只收 wireguard",
	},
}

-- ---------- 表本身的自洽性（防止错别字 / 过期条目把测试变成空转） ----------
local proto_set, fmt_set = {}, {}
for _, p in ipairs(node.PROTOS) do proto_set[p] = true end
for _, f in ipairs(FORMATS) do fmt_set[f] = true end

local unknown_proto = {}
for p in pairs(DROPPED) do if not proto_set[p] then unknown_proto[#unknown_proto + 1] = p end end
table.sort(unknown_proto)
check("DROPPED keys are all in node.PROTOS"
	.. (#unknown_proto > 0 and (" (" .. table.concat(unknown_proto, ",") .. ")") or ""),
	#unknown_proto == 0)

local unknown_fmt = {}
for _, p in pairs(DROPPED) do
	for f in pairs(p) do if not fmt_set[f] then unknown_fmt[f] = true end end
end
local uf = {}
for f in pairs(unknown_fmt) do uf[#uf + 1] = f end
table.sort(uf)
check("DROPPED formats are all in FORMAT_OPTIONS"
	.. (#uf > 0 and (" (" .. table.concat(uf, ",") .. ")") or ""),
	#uf == 0)

-- 每个协议都要有样本与 scheme，否则下面的循环会静默跳过它（测试看着全绿其实漏测）
local missing_sample, missing_scheme = {}, {}
for _, p in ipairs(node.PROTOS) do
	if not SAMPLES[p] then missing_sample[#missing_sample + 1] = p end
	if not SCHEME[p] then missing_scheme[#missing_scheme + 1] = p end
end
check("every proto has a sample"
	.. (#missing_sample > 0 and (" (" .. table.concat(missing_sample, ",") .. ")") or ""),
	#missing_sample == 0)
check("every proto has a scheme"
	.. (#missing_scheme > 0 and (" (" .. table.concat(missing_scheme, ",") .. ")") or ""),
	#missing_scheme == 0)
check("FORMATS is non-empty", #FORMATS > 0)

-- ---------- 行为：逐个 (协议, 格式) 验证 ----------
-- 名字带首尾标记，避免 MKhysteria 成为 MKhysteria2 的子串（子串匹配会误判）
local function sample(proto)
	local n = { proto = proto, name = "MK" .. proto .. "X", server = "10.9.0.1", port = 443 }
	for k, v in pairs(SAMPLES[proto] or {}) do n[k] = v end
	return node.normalize(n)
end

local function emitted(out, proto, fmt)
	if type(out) ~= "string" then return false end
	if URI_FORMATS[fmt] then
		local s = out
		if fmt == "shadowrocket" then
			local ok, dec = pcall(util.base64_decode, out)
			if not ok or type(dec) ~= "string" then return false end
			s = dec
		end
		return s:find(SCHEME[proto], 1, true) ~= nil
	end
	return out:find("MK" .. proto .. "X", 1, true) ~= nil
end

local total_pairs = 0
for _, proto in ipairs(node.PROTOS) do
	local drops = DROPPED[proto] or {}
	local bad = {}
	for _, fmt in ipairs(FORMATS) do
		total_pairs = total_pairs + 1
		local ok, out = pcall(output.generate, { sample(proto) }, fmt, {})
		local got, want
		if not ok then
			got, want = "error: " .. tostring(out), "kept"
		else
			got, want = emitted(out, proto, fmt), not drops[fmt]
		end
		if got ~= want then
			bad[#bad + 1] = fmt .. " want " .. (want and "kept" or "dropped")
				.. " got " .. tostring(got)
		end
	end
	check(proto .. " matches the format registry"
		.. (#bad > 0 and (" (" .. table.concat(bad, "; ") .. ")") or ""),
		#bad == 0)
end
check("registry covers every proto x format pair",
	total_pairs == #node.PROTOS * #FORMATS)

-- plain 是「无损导出」：它不做任何协议过滤，任何协议都必须出现在 Plain JSON 里。
-- 单独命名这条不变量，是因为一旦有人给 to_plain 加上过滤，症状会非常隐蔽
-- （备份/迁移用的导出静默少了节点）。
local plain_lossy = {}
for _, proto in ipairs(node.PROTOS) do
	local ok, out = pcall(output.generate, { sample(proto) }, "plain", {})
	if not ok or not emitted(out, proto, "plain") then plain_lossy[#plain_lossy + 1] = proto end
end
check("plain JSON is lossless for every proto"
	.. (#plain_lossy > 0 and (" (missing: " .. table.concat(plain_lossy, ",") .. ")") or ""),
	#plain_lossy == 0)

-- ---------- 结果 ----------
print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
