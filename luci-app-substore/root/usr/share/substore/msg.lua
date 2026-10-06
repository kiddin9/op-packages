-- msg.lua — 组合型用户可见消息的拼接与还原（纯 Lua，不 require luci.i18n）
--
-- 为什么需要它：
--   后端模块**不能** require("luci.i18n") —— substore-cron.sh 在独立的 lua 进程里
--   跑 core.sync，那里没有 LuCI 环境。所以后端一律返回语言中立的英文 msgid，
--   翻译只发生在显示边界（控制器 / 视图）。
--
--   但有一类消息是「msgid 前缀 + 动态值」拼出来的，例如：
--       "Invalid proxy config: " .. reason
--   整体查翻译表必然落空 —— 值每次都不同 —— 前缀那半句就永远翻译不了。
--   这里用分隔符把各段拼起来，显示边界按分隔符拆开、**逐段**查表，
--   于是前缀也能翻译，动态值原样输出。
--
-- 分隔符取 "\1"（SOH）：它不会出现在任何合法取值里（URL / 主机名 / User-Agent /
-- 端口 / 协议名在 http.lua 里都校验过），而且 util.json_encode 会把控制字符
-- 转义成 \u0001，所以组合消息存进 meta.error 再读回来仍然完好。
--
-- 拆分只按**第一个**分隔符切，剩下的递归处理，所以嵌套（值本身又是组合消息）
-- 天然成立。全程精确，没有任何启发式匹配。
local M = {}

M.SEP = "\1"

-- 把若干段依次拼成一条组合消息。段可以是 msgid（会被翻译），
-- 也可以是要原样显示的动态值（查表落空即原样输出）。
function M.compose(...)
	local out = {}
	for i = 1, select("#", ...) do
		if i > 1 then out[#out + 1] = M.SEP end
		out[#out + 1] = tostring((select(i, ...)))
	end
	return table.concat(out)
end

-- compose 的两段简写，读起来更贴近原来的 `前缀 .. 值`。
function M.join(prefix, value)
	return M.compose(prefix, value)
end

-- 把一串 msgid 用 sep 连成组合消息。sep 自己也是一段（也参与查表），
-- 因为中文里的连接符未必与英文相同。
function M.compose_list(parts, sep)
	local out = {}
	for i, p in ipairs(parts) do
		if i > 1 then out[#out + 1] = M.SEP .. tostring(sep) .. M.SEP end
		out[#out + 1] = tostring(p)
	end
	return table.concat(out)
end

-- 翻译一条（可能是组合消息的）用户可见文案。translate 由调用方传入 ——
-- 本模块不 require luci.i18n（见文件头）。
-- 对**已经翻译过**的串是幂等的：它不含分隔符，整串查表落空即原样返回。
function M.translate(s, translate)
	if s == nil then return nil end
	s = tostring(s)
	local i = s:find(M.SEP, 1, true)
	if not i then return translate(s) end
	return translate(s:sub(1, i - 1)) .. M.translate(s:sub(i + 1), translate)
end

return M
