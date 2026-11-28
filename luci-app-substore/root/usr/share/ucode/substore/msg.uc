// msg.uc — 组合型用户可见消息的拼接与还原（纯 ucode，不依赖 luci.i18n）
//
// 与 Lua 版语义完全一致：后端模块不能 require("luci.i18n")（cron 在独立
// 进程里跑 core.sync，没有 LuCI 环境），所以一律返回语言中立的英文 msgid，
// 翻译只发生在显示边界。
//
// 「msgid 前缀 + 动态值」这类消息用 "\1"（SOH）分隔各段：显示边界按分隔符
// 拆开、逐段查表，于是前缀也能翻译，动态值原样输出。SOH 不会出现在任何
// 合法取值里，且 json 编码会把它转义成 \u0001，存进 meta.error 再读回仍完好。
//
// ucode 没有多返回值，compose 用变参数组接收各段。

const M = {};

M.SEP = '\1';

M.compose = function(...parts) {
	return join(M.SEP, parts);
};

// compose 的两段简写，读起来更接近 `前缀 .. 值`
M.join = function(prefix, value) {
	return M.compose(prefix, value);
};

// 把一串 msgid 用 sep 连成组合消息。sep 自己也是一段（也参与查表），
// 因为中文里的连接符未必与英文相同。
M.compose_list = function(parts, sep) {
	let out = [];
	let first = true;

	for (let p in (parts ?? [])) {
		if (!first)
			push(out, M.SEP + `${sep}` + M.SEP);
		push(out, `${p}`);
		first = false;
	}

	return join('', out);
};

// 翻译一条（可能是组合消息的）用户可见文案。translate 由调用方传入 ——
// 本模块不 require luci.i18n。对已经翻译过的串是幂等的：它不含分隔符，
// 整串查表落空即原样返回。
M.translate = function(s, translate) {
	if (s == null)
		return null;

	s = `${s}`;
	let i = index(s, M.SEP);

	if (i < 0)
		return translate(s);

	return translate(substr(s, 0, i)) + M.translate(substr(s, i + 1), translate);
};

return M;
