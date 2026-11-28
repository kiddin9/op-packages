// parser_clash_yaml.uc — Clash YAML 解析 → 统一节点模型（ucode）
// luci-app-substore
// 内置极简缩进式 YAML 解析器，处理 Clash proxies / proxy-groups 结构
//
// 从 parser_clash_yaml.lua 移植。对外 API 不变：
//   M.TYPE_MAP   Clash type → 统一 proto 的权威映射表（对象）
//   M.parse(s)   解析 Clash YAML，返回统一节点模型**数组**
// Lua 版的多返回值在 ucode 里改为数组：util.json_decode 返回 [value, err]，
// 这里只取 value。Lua 表里「nil 值 = 键不存在」，ucode 对象允许存 null，
// 因此节点在返回前会把 null 值的顶层键删掉，保持与 Lua 版相同的节点形状。

import { isnan } from 'math';

const util = require('substore.util');
const node = require('substore.node');

const M = {};

// Clash type → 统一 proto。
// 这是**权威映射表**：parser_json_config 与 parser.lua 的简易 YAML 兜底解析都复用同一份，
// 避免各自维护一份而漂移（曾出现兜底那份缺 hysteria2/hysteria/tuic/wireguard，
// 且把 socks5 原样留下，导致这些节点被误当成 vmess 或被筛选器静默丢弃）。
const TYPE_MAP = {
	vmess: 'vmess',
	vless: 'vless',
	trojan: 'trojan',
	ss: 'shadowsocks',
	shadowsocks: 'shadowsocks',
	socks5: 'socks',
	socks: 'socks',
	hysteria2: 'hysteria2',
	hysteria: 'hysteria',
	tuic: 'tuic',
	wireguard: 'wireguard',
	ssr: 'ssr',
	http: 'http',
	anytls: 'anytls'
};

// 导出供 parser.lua 的简易 YAML 兜底解析复用（单一事实来源）
M.TYPE_MAP = TYPE_MAP;

// Lua 的 %s 字符集合（isspace）。ucode 的 POSIX ERE 里不用 \s（不可移植）。
const WS = ' \t\r\n\v\f';

function is_ws(c) {
	return c != null && c != '' && index(WS, c) >= 0;
}

// Lua 的 `str:gsub("%s*$", "")`（只去尾部空白，不动头部）
function trim_right(s) {
	let i = length(s);
	while (i > 0 && is_ws(substr(s, i - 1, 1)))
		i--;
	return substr(s, 0, i);
}

// Lua 的 `a or b`：只有 nil / false 才回退。ucode 的 ?? 只回退 null，
// || 又会把 0 / "" 当成假，两者都不等价。
function lua_or(a, b) {
	return (a == null || a === false) ? b : a;
}

// Lua 的 `not x`（nil / false 为假；0 与 "" 在 Lua 里是真）
function lua_falsy(v) {
	return v == null || v === false;
}

// Lua 的 tonumber()：只接受数字与字符串；空串 / 纯空白 / 无法解析返回 nil。
// 不能用裸 `+v`：ucode 里 +"" == 0、+"abc" == NaN、+"0b101" == 5（Lua 得 nil）、
// +".5" == NaN（Lua 得 0.5）。因此先按 Lua 5.1 认可的写法过一遍正则再转换。
function lua_tonumber(v) {
	let t = type(v);

	if (t == 'int' || t == 'double')
		return v;

	if (t != 'string')
		return null;

	let s = trim(v);
	if (s == '')
		return null;

	// 十六进制整数（Lua 5.1 的 tonumber 对 0x/0X 走 strtoul base16）
	if (match(s, /^[+-]?0[xX][0-9A-Fa-f]+$/))
		return +s;

	// 十进制：strtod 接受的完整写法（允许 `.5` / `5.` / `1e2`）
	if (!match(s, /^[+-]?([0-9]+(\.[0-9]*)?|\.[0-9]+)([eE][+-]?[0-9]+)?$/))
		return null;

	// ucode 的 + 不认前导小数点：+.5 == NaN，补一个 0
	if (match(s, /^[+-]?\.[0-9]/)) {
		let sign = match(s, /^[+-]/) ? substr(s, 0, 1) : '';
		s = sign + '0' + substr(s, length(sign));
	}

	let n = +s;
	if (isnan(n))
		return null;

	return n;
}

// 标量值转换：布尔 / 数字 / 去引号 / 保留字符串
function scalar(raw) {
	raw = raw ?? '';
	raw = trim_right(raw);
	if (raw == 'true' || raw == 'True' || raw == 'TRUE')
		return true;
	if (raw == 'false' || raw == 'False' || raw == 'FALSE')
		return false;
	if (raw == 'null' || raw == '~' || raw == '')
		return null;
	let q = match(raw, /^"(.*)"$/);
	if (q)
		raw = q[1];
	q = match(raw, /^'(.*)'$/);
	if (q)
		raw = q[1];
	// 内联数组 [1,2,3] / ['a','b']
	if (substr(raw, 0, 1) == '[' && substr(raw, length(raw) - 1, 1) == ']') {
		let arr = [];
		// Lua 的 gmatch("[^,%s]+")：按逗号/空白切出非空片段
		for (let mm in (match(substr(raw, 1, length(raw) - 2), /[^, \t\r\n\v\f]+/g) ?? [])) {
			let item = mm[0];
			let iq = match(item, /^"(.*)"$/);
			if (iq)
				item = iq[1];
			iq = match(item, /^'(.*)'$/);
			if (iq)
				item = iq[1];
			let n = lua_tonumber(item);
			if (n != null)
				push(arr, n);
			else
				push(arr, item);
		}
		return arr;
	}
	let n = lua_tonumber(raw);
	if (n != null)
		return n;
	return raw;
}

// 去掉行尾注释。YAML 规定内联注释的 # 前必须有空白，引号内的 # 不算注释。
// 不处理的话 `proxies: # 说明` 会把注释文本当成值，proxies 变成字符串，
// 整份配置被判定为「没有 proxies」→ 0 个节点且不报错。
function strip_comment(v) {
	let in_s = false, in_d = false;
	for (let i = 0; i < length(v); i++) {
		let c = substr(v, i, 1);
		if (in_s) {
			if (c == "'")
				in_s = false;
		}
		else if (in_d) {
			if (c == '"')
				in_d = false;
		}
		else if (c == "'")
			in_s = true;
		else if (c == '"')
			in_d = true;
		else if (c == '#' && (i == 0 || is_ws(substr(v, i - 1, 1))))
			return trim_right(substr(v, 0, i));
	}
	return v;
}

// 按顶层分隔符切分，忽略引号内以及 {} / [] 内部的同级分隔符
function split_top(s, sep) {
	let parts = [], buf = [];
	let depth = 0, in_s = false, in_d = false;
	for (let i = 0; i < length(s); i++) {
		let c = substr(s, i, 1);
		if (in_s) {
			if (c == "'")
				in_s = false;
			push(buf, c);
		}
		else if (in_d) {
			if (c == '"')
				in_d = false;
			push(buf, c);
		}
		else if (c == "'") {
			in_s = true;
			push(buf, c);
		}
		else if (c == '"') {
			in_d = true;
			push(buf, c);
		}
		else if (c == '{' || c == '[') {
			depth++;
			push(buf, c);
		}
		else if (c == '}' || c == ']') {
			depth--;
			push(buf, c);
		}
		else if (c == sep && depth == 0) {
			push(parts, join('', buf));
			buf = [];
		}
		else
			push(buf, c);
	}
	push(parts, join('', buf));
	return parts;
}

// 解析 YAML 流式映射 {...}。Clash 机场配置常用
// `- {name: A, type: vmess, server: 1.1.1.1, port: 443}` 这种写法：它是合法 YAML，
// 但不是合法 JSON（键没有加引号），util.json_decode 必然失败，节点被整条静默
// 丢弃（0 个节点且无报错）。
function parse_flow_map(s) {
	// Lua: s:match("^%s*{(.*)}%s*$") —— 贪婪的 (.*) 取到最后一个 }
	let body = match(s, /^[ \t\r\n\v\f]*\{(.*)\}[ \t\r\n\v\f]*$/);
	if (!body)
		return null;
	let map = {};
	for (let part in split_top(body[1], ',')) {
		// Lua: part:match("^%s*([^:]+):%s*(.*)$")
		let kv = match(part, /^[ \t\r\n\v\f]*([^:]+):[ \t\r\n\v\f]*(.*)$/);
		if (kv) {
			let k = trim_right(kv[1]);
			// Lua: map[k] = scalar(...) —— 赋 nil 等于删键，这里直接跳过 null
			let v = scalar(strip_comment(kv[2]));
			if (v != null)
				map[k] = v;
		}
	}
	if (length(keys(map)) == 0)
		return null;
	return map;
}

// 预处理内容为 (indent, rest) 列表，跳过空行、注释、文档分隔符
function preprocess(content) {
	let items = [];
	// Lua: (content:gsub("\r\n", "\n")):gmatch("[^\n]+") —— 按 \n 切分、跳过空行
	for (let l in split(replace(content, /\r\n/g, '\n'), '\n')) {
		if (l == '')
			continue;
		let s = l;
		let ind = 0;
		while (substr(s, 0, 1) == ' ') {
			ind++;
			s = substr(s, 1);
		}
		let t = trim_right(s);
		if (t != '' && !match(t, /^#/) && t != '---' && t != '...')
			push(items, { ind: ind, rest: t });
	}
	return items;
}

function parse_yaml(content) {
	let items = preprocess(content);
	let pos = 0;
	const n_items = length(items);

	let read_list = null;

	function read_map(min_indent) {
		let map = {};
		while (pos < n_items) {
			let it = items[pos];
			if (it.ind < min_indent)
				break;
			if (it.rest == '-' || match(it.rest, /^-[ \t\r\n\v\f]/))
				break;
			let kv = match(it.rest, /^([^:]+):[ \t\r\n\v\f]*(.*)$/);
			if (!kv) {
				pos++;
			}
			else {
				let k = trim_right(kv[1]);
				// 行尾注释必须先去掉，否则 `proxies: # 说明` 会把注释文本当成值，
				// proxies 变成字符串，整份配置被判定为「没有 proxies」
				let v = strip_comment(kv[2]);
				pos++;
				if (v == '' || v == '|' || v == '>') {
					if (pos < n_items && items[pos].ind > it.ind) {
						let nxt = items[pos];
						if (nxt.rest == '-' || match(nxt.rest, /^-[ \t\r\n\v\f]/))
							map[k] = read_list(nxt.ind);
						else
							map[k] = read_map(nxt.ind);
					}
					else
						map[k] = {};
				}
				else {
					// Lua: map[k] = scalar(v) —— nil 等于删键
					let sv = scalar(v);
					if (sv != null)
						map[k] = sv;
				}
			}
		}
		return map;
	}

	read_list = function(min_indent) {
		let list = [];
		while (pos < n_items) {
			let it = items[pos];
			if (it.ind < min_indent)
				break;
			let dash;
			if (it.rest == '-')
				dash = '';
			else {
				let m = match(it.rest, /^-[ \t\r\n\v\f]*(.*)$/);
				dash = m ? m[1] : null;
			}
			if (dash == null)
				break;
			pos++;
			// 列表项也要去掉行尾注释：`- {a: 1} # 说明`、`- "::/0" # 说明`
			// 都会让注释文本混进值里（流式映射那条甚至会整项解析失败）
			dash = strip_comment(dash);

			let m = null;
			// 流式 JSON 对象：- {"name":"...","type":"vmess",...}（机场 clash 配置常见写法）
			if (substr(dash, 0, 1) == '{') {
				// 先按 JSON 解（键带引号的流式写法），失败再按 YAML 流式映射解
				let [obj, _err] = util.json_decode(dash);
				if (type(obj) == 'object' || type(obj) == 'array')
					m = obj;
				if (!m)
					m = parse_flow_map(dash);
			}
			else {
				let kv = match(dash, /^([^:]+):[ \t\r\n\v\f]*(.*)$/);
				// 引号开头的列表项是标量而非映射：避免把 "- \"::/0\"" 里的冒号
				// 当成 key:value 分隔符，从而把整个标量解析成 table
				if (kv && kv[2] != '' && !match(dash, /^["']/)) {
					m = {};
					let mk = trim_right(kv[1]);
					let mv = scalar(kv[2]);
					// Lua 里 `{[k] = nil}` 是一张空表（仍为真值），这里跳过 null 赋值
					if (mv != null)
						m[mk] = mv;
				}
			}

			if (pos < n_items && items[pos].ind > it.ind) {
				let nxt = items[pos];
				if (nxt.rest == '-' || match(nxt.rest, /^-[ \t\r\n\v\f]/)) {
					// Lua: list[#list+1] = m or (dash ~= "" and scalar(dash) or nil)
					// 其中 `(true and false) or nil` 是 nil —— false 结果不追加
					let val = m;
					if (!val) {
						val = null;
						if (dash != '') {
							let sv = scalar(dash);
							if (sv !== false)
								val = sv;
						}
					}
					if (val != null)
						push(list, val);
				}
				else {
					let sub = read_map(nxt.ind);
					if (m) {
						for (let sk, sv in sub)
							m[sk] = sv;
						push(list, m);
					}
					else
						push(list, sub);
				}
			}
			else if (m || dash != '') {
				// Lua: list[#list+1] = m or scalar(dash)；赋值 nil 不追加，false 会追加
				if (m)
					push(list, m);
				else {
					let sv = scalar(dash);
					if (sv != null)
						push(list, sv);
				}
			}
		}
		return list;
	};

	let doc = read_map(0);
	return doc;
}

// 将单个 Clash proxy 表映射为统一节点模型
function map_clash_node(p) {
	if (type(p) != 'object')
		return null;
	if (lua_falsy(p.name) || lua_falsy(p.server) || lua_falsy(p.port))
		return null;

	// 未知协议必须丢弃，不能原样透传、也不能兜底成 vmess：
	//   * 原样透传：统一模型承载不了 snell / shadowtls / mieru / ssh 等类型（认证
	//     方式与字段都不同），透传出去会在输出端变成 sing-box 的 type: "snell"、
	//     Xray 的 protocol: "snell" 这类非法取值，客户端会拒绝加载整份配置。
	//   * 兜底成 vmess：那是凭空造出一个字段全错的节点，比丢弃更糟（用户看到
	//     "导入成功"，实际拿到一批不可用的假节点）。
	// parser.lua 的简易 YAML 兜底解析（复用同一张 TYPE_MAP）早已按此处理，此处对齐。
	let proto = TYPE_MAP[p.type];
	if (proto == null)
		return null;
	let n = {
		proto: proto,
		name: p.name,
		server: p.server,
		port: lua_tonumber(p.port),
		uuid: lua_or(p.uuid, p.id),
		password: p.password,
		method: lua_or(p.cipher, p.method),
		net: lua_or(p.network, p.net),
		sni: lua_or(p.sni, p.servername),
		tls: p.tls,
		// uTLS 指纹：mihomo 的键是 client-fingerprint（全仓库没有任何结构体声明
		// `proxy:"fp,..."`，详见 node.CLIENT_FP_PROTOS 的说明）。只读 p.fp 的话，
		// 一份真正的 mihomo 配置导入后指纹全部丢失 —— 与输出端写 `fp:` 是同一个
		// 错误的另一半。仍然读 p.fp 是为了兼容本项目旧版本自己导出的配置。
		// 注意不要读 `fingerprint`：hysteria/hysteria2/tuic 上那是证书固定
		// （SHA256 pin），与 uTLS 语义不同，映射过来是错的。
		fp: lua_or(p['client-fingerprint'], p.fp)
	};
	if (!lua_falsy(p.alpn))
		n.alpn = p.alpn;
	if (p.udp != null)
		n.udp = p.udp;
	if (p['skip-cert-verify'] != null) {
		let sk = p['skip-cert-verify'];
		n['skip-cert-verify'] = sk;
		n.skip_cert_verify = sk;
	}
	if (!lua_falsy(p.alterId)) {
		let av = lua_tonumber(p.alterId);
		if (av != null)
			n.alterId = av;
	}
	if (!lua_falsy(p.security))
		n.security = p.security;
	if (!lua_falsy(p.flow))
		n.flow = p.flow;
	// ws-opts（Clash 的 ws 传输参数）映射到统一模型的 path / host
	if (type(p['ws-opts']) == 'object' || type(p['ws-opts']) == 'array') {
		if (!lua_falsy(p['ws-opts'].path))
			n.path = p['ws-opts'].path;
		let wh = p['ws-opts'].headers;
		if ((type(wh) == 'object' || type(wh) == 'array') && !lua_falsy(wh.Host))
			n.host = wh.Host;
	}

	// 保留其余字段（wireguard 的 private-key、peer-public-key 等）
	// 但 type 要排除：Clash 的 type 是协议判别字段（vmess/ss/trojan），
	// 已经在上面映射成 proto；原样拷进来会让节点多出一个 type，
	// 而 output_uri 把它当成 vmess 的 header type 写出（"type":"vmess"），
	// 生成客户端无法识别的 vmess:// 链接。
	for (let k, v in p) {
		if (k != 'type' && n[k] == null)
			n[k] = v;
	}

	// Lua 表里值为 nil 的键等于不存在；ucode 对象会保留 null 键。
	// 统一删掉 null 值的顶层键，保持与 Lua 版节点形状一致（下游看到的都是「缺键」）。
	for (let k in keys(n)) {
		if (n[k] == null)
			delete n[k];
	}

	return node.normalize(n);
}

// 解析 Clash YAML，返回统一节点模型列表（数组）
M.parse = function(content) {
	if (content == null || content == '')
		return [];
	let doc = parse_yaml(content);
	let proxies = doc ? doc.proxies : null;
	if (type(proxies) != 'array')
		return [];

	let nodes = [];
	for (let p in proxies) {
		let n = map_clash_node(p);
		if (n)
			push(nodes, n);
	}
	return nodes;
};

return M;
