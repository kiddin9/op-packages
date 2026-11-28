// node.uc — 统一节点模型
// luci-app-substore

import { isnan } from 'math';

const util = require('substore.util');
const msg = require('substore.msg');

const M = {};

M.PROTOS = [
	'vmess', 'vless', 'trojan', 'shadowsocks', 'ssr', 'hysteria2', 'tuic', 'hysteria', 'wireguard', 'socks',
	'anytls'
];

// 每种协议在「表单导入 / 节点编辑」界面里渲染的字段集合，数组顺序即界面顺序。
// 这是**唯一**的字段清单：LuCI 页面渲染成 window.SUBSTORE_PROTO_FIELDS，
// core.merge_form_node 用它决定「哪些字段可以被表单覆盖（含清空）」。
M.PROTO_FIELDS = {
	ssr: ['server', 'port', 'password', 'cipher', 'protocol', 'obfs', 'obfs-param', 'protocol-param', 'udp'],
	vmess: ['server', 'port', 'uuid', 'alterId', 'cipher', 'net', 'headerType', 'path', 'host', 'sni', 'security', 'udp', 'skip-cert-verify'],
	vless: ['server', 'port', 'uuid', 'security', 'flow', 'net', 'headerType', 'path', 'host', 'sni', 'udp', 'skip-cert-verify',
		'public-key', 'short-id', 'spider-x', 'fp'],
	trojan: ['server', 'port', 'password', 'sni', 'net', 'headerType', 'path', 'host', 'udp', 'skip-cert-verify'],
	shadowsocks: ['server', 'port', 'password', 'method', 'headerType', 'udp', 'plugin'],
	hysteria2: ['server', 'port', 'password', 'sni', 'obfs', 'obfs-password', 'skip-cert-verify'],
	hysteria: ['server', 'port', 'password', 'sni', 'obfs', 'skip-cert-verify'],
	tuic: ['server', 'port', 'uuid', 'password', 'sni', 'udp', 'skip-cert-verify'],
	anytls: ['server', 'port', 'password', 'sni', 'alpn', 'skip-cert-verify', 'public-key', 'short-id'],
	wireguard: ['server', 'port', 'private-key', 'public-key', 'pre-shared-key', 'ip', 'ipv6', 'allowed-ips', 'reserved', 'persistent-keepalive', 'listen-port', 'mtu', 'amnezia-wg-option'],
	socks: ['server', 'port', 'username', 'password', 'udp']
};

M.FORM_ALWAYS_FIELDS = ['name', 'group'];

// TLS-only 协议：协议本身要求 TLS 层，缺了客户端直接起不来
M.TLS_ONLY = {
	trojan: true,
	hysteria2: true,
	hysteria: true,
	tuic: true,
	anytls: true
};

// 支持 Reality 的协议。判据必须是「协议 + 有没有 public-key」两者，
// 只看 public-key 会误伤 wireguard（它的 public-key 与 Reality 无关）。
M.REALITY_PROTOS = {
	vless: true,
	vmess: true,
	trojan: true,
	anytls: true
};

// 支持 uTLS 客户端指纹的协议
M.CLIENT_FP_PROTOS = {
	vmess: true,
	vless: true,
	trojan: true,
	shadowsocks: true,
	anytls: true
};

M.supports_client_fp = function(proto) {
	if (proto == 'ss')
		proto = 'shadowsocks';
	return M.CLIENT_FP_PROTOS[proto] == true;
};

// 协议默认值，用于补全缺省字段
const DEFAULTS = {
	vmess: { net: 'tcp', security: 'none' },
	vless: { net: 'tcp', security: 'none' }
};
for (let proto in M.TLS_ONLY)
	DEFAULTS[proto] = { security: 'tls' };

M.VMESS_CIPHERS = {
	auto: true, none: true, zero: true,
	'aes-128-gcm': true, 'chacha20-poly1305': true
};

function str(v) {
	return v == null ? '' : `${v}`;
}

// 判断节点是否拥有某标签；兼容 tags 为数组（{"fast"}）或 set（{fast:true}）
function has_tag(node, tag) {
	let t = node ? node.tags : null;
	if (type(t) != 'object' && type(t) != 'array')
		return false;

	if (type(t) == 'object' && t[tag] === true)
		return true;

	if (type(t) == 'array') {
		for (let v in t) {
			if (v == tag)
				return true;
		}
	}

	return false;
}

M.normalize = function(node) {
	if (type(node) != 'object')
		return node;

	if (node.proto == 'ss')
		node.proto = 'shadowsocks';
	if (node.proto == 'socks5')
		node.proto = 'socks';

	let d = DEFAULTS[node.proto] ?? {};
	for (let k, v in d) {
		if (node[k] == null)
			node[k] = v;
	}

	// tls 的空串 / "none" / "false" 统一归一为 null
	if (node.tls === '' || node.tls === 'none' || node.tls === 'false')
		delete node.tls;
	else if (node.tls === 'true')
		node.tls = true;

	// tls 与 security 是同一语义，统一落到 security
	if (node.security == null || node.security === 'none') {
		if (node.tls === true)
			node.security = 'tls';
		else if (node.tls === 'tls' || node.tls === 'reality')
			node.security = node.tls;
	}

	// 带 public-key 就是 Reality，与 security 怎么写无关
	if (node['public-key'] && M.REALITY_PROTOS[node.proto])
		node.security = 'reality';

	// vmess 的加密方式存于 cipher，非白名单取值直接丢弃（删键，与 Lua 的 nil 一致；
	// 留 null 键会让 JSON 序列化多出一个字段）
	if (node.proto == 'vmess' && node.cipher != null && !M.VMESS_CIPHERS[node.cipher])
		delete node.cipher;

	if (node.name == null || node.name === '')
		node.name = str(node.server) + ':' + str(node.port);

	// tags 字符串自动拆分为数组（逗号分隔）
	if (type(node.tags) == 'string') {
		let t = [];
		for (let tag in split(node.tags, ',')) {
			tag = trim(tag);
			if (tag != '')
				push(t, tag);
		}
		node.tags = t;
	}

	return node;
};

// 过滤：支持 proto、keyword（name/server）、server、port、group、tags
M.filter = function(nodes, opts) {
	opts = opts ?? {};
	let out = [];

	for (let n in (nodes ?? [])) {
		if (opts.proto && n.proto != opts.proto)
			continue;

		let ok = true;

		if (opts.keyword && opts.keyword != '') {
			let kw = lc(opts.keyword);
			if (index(lc(str(n.name)), kw) < 0 && index(lc(str(n.server)), kw) < 0)
				ok = false;
		}

		if (ok && opts.server && n.server != opts.server)
			ok = false;

		if (ok && opts.port && +n.port != +opts.port)
			ok = false;

		if (ok && opts.group && n.group != opts.group)
			ok = false;

		if (ok && opts.tags) {
			let wanted = opts.tags;
			if (type(wanted) == 'string')
				wanted = trim(wanted);
			if (!has_tag(n, wanted))
				ok = false;
		}

		if (ok)
			push(out, n);
	}

	return out;
};

// WireGuard peer 公钥。字段名以 parser 产出的 "public-key" 为准
function wg_public_key(n) {
	return n['public-key'] ?? n.public_key ?? n['peer-public-key'] ?? n.peer_public_key;
}

// 去重键的「身份」部分：同一 server:port 上的不同账号是不同节点
function identity_key(n) {
	let proto = lc(str(n.proto));

	if (proto == 'ss') proto = 'shadowsocks';
	if (proto == 'wg') proto = 'wireguard';
	if (proto == 'socks5') proto = 'socks';

	if (proto == 'wireguard')
		return str(wg_public_key(n));

	if (proto == 'shadowsocks')
		return str(n.method ?? n.cipher) + '\1' + str(n.password);

	if (proto == 'ssr')
		return str(n.method ?? n.cipher) + '\1' + str(n.password)
			+ '\1' + str(n.protocol) + '\1' + str(n.obfs);

	if (proto == 'vmess' || proto == 'vless')
		return str(n.uuid);

	if (proto == 'tuic')
		return str(n.uuid) + '\1' + str(n.password);

	if (proto == 'socks' || proto == 'http')
		return str(n.username) + '\1' + str(n.password);

	if (proto == 'trojan' || proto == 'hysteria' || proto == 'hysteria2')
		return str(n.password);

	return '';
}

M.dedup = function(nodes) {
	let seen = {};
	let out = [];

	for (let n in (nodes ?? [])) {
		let proto = lc(str(n.proto));
		if (proto == 'wg')
			proto = 'wireguard';

		let key = proto + '|' + str(n.server) + '|' + str(n.port) + '|' + identity_key(n);

		if (seen[key] !== true) {
			seen[key] = true;
			push(out, n);
		}
	}

	return out;
};

// 排序：by = "name"|"server"|"proto"|"port"
M.sort = function(nodes, by, desc) {
	by = by ?? 'name';
	desc = (desc === true);

	sort(nodes, function(a, b) {
		let av, bv;

		if (by == 'port') {
			av = +a[by];
			bv = +b[by];
			if (isnan(av)) av = 0;
			if (isnan(bv)) bv = 0;
		}
		else {
			// 字段值可能是数字，统一转成字符串再比
			av = str(a[by]);
			bv = str(b[by]);
		}

		if (av == bv)
			return 0;
		if (desc)
			return av > bv ? -1 : 1;
		return av < bv ? -1 : 1;
	});

	return nodes;
};

M.rename = function(node, new_name) {
	if (type(node) == 'object' && new_name != null)
		node.name = new_name;
	return node;
};

// 逗号分隔列表 → 数组，逐项去空白（group / template 名大小写敏感）
function split_list(s) {
	let out = [];

	for (let item in split(s ?? '', ',')) {
		item = trim(item);
		if (item != '')
			push(out, item);
	}

	return out;
}

// 关键词串拆分为数组（英文逗号/中文逗号/空白分隔），忽略空项，统一小写
function split_keywords(s) {
	let out = [];

	for (let kw in split(replace(s ?? '', /[ \t\r\n\v\f,，]+/g, ' '), ' ')) {
		kw = lc(kw);
		if (kw != '')
			push(out, kw);
	}

	return out;
}

function match_keywords(n, kws) {
	let name = lc(str(n.name));
	let server = lc(str(n.server));

	for (let kw in (kws ?? [])) {
		if (index(name, kw) >= 0 || index(server, kw) >= 0)
			return true;
	}

	return false;
}

// 把模板里的 {var} 占位符按**字面**替换（回调返回值不参与 $ 引用语义）
function expand_placeholders(template, n) {
	return replace(template, /\{(server|port|proto|name|uuid|password|group)\}/g, (m, key) => {
		return str(n[key]);
	});
}

// 应用规则集到节点列表
M.apply_rules = function(nodes, rules) {
	rules = rules ?? {};

	// 协议过滤
	if (rules.proto_filter && rules.proto_filter != '') {
		let set = {};
		for (let p in split_list(rules.proto_filter))
			set[p] = true;

		let out = [];
		for (let n in nodes) {
			if (set[n.proto] === true)
				push(out, n);
		}
		nodes = out;
	}

	// 分组过滤
	if (rules.group_filter && rules.group_filter != '') {
		let set = {};
		for (let g in split_list(rules.group_filter))
			set[g] = true;

		let out = [];
		for (let n in nodes) {
			if (set[n.group] === true)
				push(out, n);
		}
		nodes = out;
	}

	// 标签包含
	if (rules.tags_include && rules.tags_include != '') {
		let set = {};
		for (let t in split_list(rules.tags_include))
			set[t] = true;

		let out = [];
		for (let n in nodes) {
			let matched = false;
			for (let tag in keys(set)) {
				if (has_tag(n, tag)) {
					matched = true;
					break;
				}
			}
			if (matched)
				push(out, n);
		}
		nodes = out;
	}

	// 模板过滤
	if (rules.template_filter && rules.template_filter != '') {
		let set = {};
		for (let tmpl in split_list(rules.template_filter))
			set[tmpl] = true;

		let out = [];
		for (let n in nodes) {
			if (set[n.template] === true)
				push(out, n);
		}
		nodes = out;
	}

	// 关键词包含
	if (rules.keyword_include && rules.keyword_include != '') {
		let kws = split_keywords(rules.keyword_include);
		let out = [];
		for (let n in nodes) {
			if (match_keywords(n, kws))
				push(out, n);
		}
		nodes = out;
	}

	// 关键词排除
	if (rules.keyword_exclude && rules.keyword_exclude != '') {
		let kws = split_keywords(rules.keyword_exclude);
		let out = [];
		for (let n in nodes) {
			if (!match_keywords(n, kws))
				push(out, n);
		}
		nodes = out;
	}

	// 去重
	if (rules.dedup === '1' || rules.dedup === true)
		nodes = M.dedup(nodes);

	// 重命名规则
	if (rules.rename_map && rules.rename_map != '')
		nodes = M.rename_with_rules(nodes, M.parse_rename_rules(rules.rename_map));

	// 模板应用：若节点有 template，则生成 url
	if (rules.template_apply === true || rules.template_apply === '1') {
		for (let n in nodes) {
			if (n.template && n.template != '' && !n.url) {
				n.url = replace(n.template, /\{(server|port|uuid|name)\}/g, (m, key) => {
					return key == 'uuid' ? str(n.uuid ?? n.password) : str(n[key]);
				});
			}
		}
	}

	return nodes;
};

// ---------- 分组 ----------

// 按字段分组：返回 { [字段值]: [节点...] }
M.group_by = function(nodes, field) {
	let groups = {};

	for (let n in (nodes ?? [])) {
		let key = str(n[field]);
		if (!groups[key])
			groups[key] = [];
		push(groups[key], n);
	}

	return groups;
};

M.group_nodes = function(nodes) {
	return M.group_by(nodes, 'group');
};

// 按规则为节点设置 group：rules = [ {field:..., prefix:...}, ... ]
M.add_group = function(nodes, rules) {
	rules = rules ?? [];

	for (let n in (nodes ?? [])) {
		for (let r in rules) {
			if (type(r) == 'object' && r.field)
				n.group = str(r.prefix) + str(n[r.field]);
		}
	}

	return nodes;
};

M.filter_by_group = function(nodes, group_name) {
	let out = [];
	for (let n in (nodes ?? [])) {
		if (n.group == group_name)
			push(out, n);
	}
	return out;
};

// ---------- 标签 ----------

// 为节点打标签。两种模式：
//   数组模式：add_tags(nodes, ["vip"]) 追加字符串标签
//   规则模式：add_tags(nodes, [{type:"keyword", value:"HK", tag:"hongkong"}])
M.add_tags = function(nodes, tags) {
	tags = tags ?? [];
	if (type(tags) == 'string')
		tags = [tags];
	if (type(tags) != 'array')
		return nodes;

	// 规则模式：元素为 {type, value, tag}
	if (length(tags) && type(tags[0]) == 'object') {
		for (let n in (nodes ?? [])) {
			if (!n.tags || (type(n.tags) != 'object' && type(n.tags) != 'array'))
				n.tags = {};

			for (let rule in tags) {
				let matched = false;

				if (rule.type == 'keyword') {
					let kw = rule.value ?? '';
					if (kw != '' && (index(str(n.name), kw) >= 0 || index(str(n.server), kw) >= 0))
						matched = true;
				}

				if (matched && rule.tag)
					n.tags[rule.tag] = true;
			}
		}

		return nodes;
	}

	// 数组模式：追加字符串标签（去重）
	for (let n in (nodes ?? [])) {
		if (!n.tags || type(n.tags) != 'array')
			n.tags = [];

		let has = {};
		for (let t in n.tags)
			has[t] = true;

		for (let t in tags) {
			if (has[t] !== true) {
				push(n.tags, t);
				has[t] = true;
			}
		}
	}

	return nodes;
};

// 按标签集合过滤：要求节点拥有 tags 中的所有标签
M.filter_by_tags = function(nodes, tags) {
	let out = [];

	for (let n in (nodes ?? [])) {
		let matched = true;

		if (type(tags) == 'string')
			tags = [tags];

		for (let t in (tags ?? [])) {
			if (!has_tag(n, t)) {
				matched = false;
				break;
			}
		}

		if (matched)
			push(out, n);
	}

	return out;
};

// ---------- 重命名规则引擎 ----------

// 解析重命名规则字符串为规则表列表
//   "旧名称=新名称"（精确匹配）
//   "pattern -> replacement"（正则替换）
//   "{server}_{port}_{proto}"（含 {var} 占位符）
M.parse_rename_rules = function(rule_str) {
	rule_str = rule_str ?? '';
	let rules = [];
	let no = 0;

	for (let line in split(rule_str, /[\r\n]+/)) {
		if (line == '')
			continue;

		no++;
		line = trim(line);
		if (line == '' || substr(line, 0, 1) == '#')
			continue;

		let arrow = index(line, '->');
		if (arrow >= 0) {
			let pat = trim(substr(line, 0, arrow));
			let repl = trim(substr(line, arrow + 2));
			if (repl != '')
				push(rules, { type: 'regex', pattern: pat, replacement: repl, line_no: no });
			continue;
		}

		if (index(line, '{') >= 0) {
			push(rules, { type: 'template', template: line, line_no: no });
			continue;
		}

		let eq = index(line, '=');
		if (eq > 0) {
			push(rules, {
				type: 'exact',
				old: trim(substr(line, 0, eq)),
				new: trim(substr(line, eq + 1)),
				line_no: no
			});
		}
	}

	return rules;
};

// 用户写的是正则风格；ucode 用 POSIX ERE，这里把 Perl 风格简写翻译过去。
//   \d \D \w \W \s \S → 对应字符类（字符类内部只展开内容）
//   \b \B → 空（ERE 无词边界，与原实现一致按无操作处理）
// 其余 \x 原样保留。`|` 是 ERE 原生语法，不需要拆候选。
function translate_regex(pat) {
	let out = [];
	let in_class = false;
	let i = 0, n = length(pat);

	while (i < n) {
		let c = substr(pat, i, 1);

		if (c == '\\' && i + 1 < n) {
			let nx = substr(pat, i + 1, 1);

			if (in_class) {
				switch (nx) {
				case 'd': push(out, '0-9'); break;
				case 'w': push(out, 'A-Za-z0-9_'); break;
				case 's': push(out, ' \\t\\r\\n\\v\\f'); break;
				case 'b': case 'B': break;
				default: push(out, '\\' + nx);
				}
			}
			else {
				switch (nx) {
				case 'd': push(out, '[0-9]'); break;
				case 'D': push(out, '[^0-9]'); break;
				case 'w': push(out, '[A-Za-z0-9_]'); break;
				case 'W': push(out, '[^A-Za-z0-9_]'); break;
				case 's': push(out, '[ \\t\\r\\n\\v\\f]'); break;
				case 'S': push(out, '[^ \\t\\r\\n\\v\\f]'); break;
				case 'b': case 'B': break;
				default: push(out, '\\' + nx);
				}
			}

			i += 2;
			continue;
		}

		if (c == '[')
			in_class = true;
		else if (c == ']')
			in_class = false;

		push(out, c);
		i++;
	}

	return join('', out);
}

// 把用户写的 $1..$9 保留为 ucode replace 的捕获引用，其余 $ 按字面转义
// （不转义的话 "50$" 里的 $ 会参与引用语义）。
function build_replacement(rep) {
	rep = rep ?? '';
	let out = [];
	let i = 0, n = length(rep);

	while (i < n) {
		let c = substr(rep, i, 1);
		let nx = substr(rep, i + 1, 1);

		if (c == '$' && nx != '' && match(nx, /[0-9]/)) {
			push(out, '$' + nx);
			i += 2;
		}
		else if (c == '$') {
			push(out, '$$');
			i++;
		}
		else {
			push(out, c);
			i++;
		}
	}

	return join('', out);
}

// 校验重命名规则串里的正则是否可用。返回 [ok, err]
M.validate_rename_map = function(rule_str) {
	for (let r in M.parse_rename_rules(rule_str)) {
		if (r.type == 'regex') {
			try {
				let re = regexp(translate_regex(r.pattern ?? ''));
				replace('', re, build_replacement(r.replacement));
			}
			catch (e) {
				return [false, msg.compose('Rename rule line ', r.line_no ?? 0,
					': invalid regular expression (', r.pattern ?? '', ')')];
			}
		}
	}

	return [true, null];
};

M.rename_with_rules = function(nodes, rules) {
	for (let n in (nodes ?? [])) {
		for (let r in (rules ?? [])) {
			if (r.type == 'exact') {
				if (n.name == r.old)
					n.name = r.new;
			}
			else if (r.type == 'template' && r.template) {
				n.name = expand_placeholders(r.template, n);
			}
			else if (r.type == 'regex') {
				try {
					// 'g' 必须显式传给 regexp()：ucode 的 replace() 对无 g 的
					// 正则只替换第一处，而重命名规则沿用 Lua 版 gsub 的全局语义。
					let re = regexp(translate_regex(r.pattern ?? ''), 'g');
					n.name = replace(str(n.name), re, build_replacement(r.replacement));
				}
				catch (e) {
					// 非法正则：保持原名（与原实现的 pcall 兜底一致）
				}
			}
		}
	}

	return nodes;
};

return M;
