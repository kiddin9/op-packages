// core.lua — 订阅源元数据、节点数据与状态管理（纯 Lua，无 luci.* 依赖）
// ucode 移植版：本文件 core.uc，与 Lua 版逐条对应。
// luci-app-substore
//
// 多返回值约定：Lua 版的 `v, err` 改为数组 `[v, err]`（见 util.uc 头部说明）；
// 下文注释里的「返回 a, b」沿用 Lua 的记法，ucode 实现实际返回 `[a, b]`。
// 其余语义逐条对照 Lua 版移植，注释记录了实测过的边界，不要删。

import { unlink } from 'fs';
import { isnan } from 'math';

const util = require('substore.util');
const http = require('substore.http');
const parser = require('substore.parser');
const msg = require('substore.msg');
const node = require('substore.node');

const M = {};

M.version = '2.9.0';
M.DATA_DIR = '/etc/substore';
M.LIST_FILE = M.DATA_DIR + '/subscriptions.json';
M.NODES_DIR = M.DATA_DIR + '/nodes';
M.CRON_FILE = '/etc/cron.d/substore';
// 列表文件的互斥锁超时（秒）。锁目录固定为 DATA_DIR 下的 .lock，
// 由 with_list_lock 现算 —— 不做成常量：那样任何改了 DATA_DIR 的调用方
// （测试、或将来支持自定义数据目录）都必须记得同步改它，忘了就会去锁真实
// 的 /etc/substore，症状是写入全部报「正被另一个进程修改」。
M.LOCK_STALE = util.LOCK_STALE;

M.MAX_SIZE = 10 * 1024 * 1024; // 10MB
M.TIMEOUT = 20;

// 「协议筛选」的可选协议，用的是节点模型里的**规范**协议名（node.normalize 的产物）。
// 控制器（read_rules_fields）与三个表单模板共用这一份：两边各写一份的话，
// 一旦漂移，勾选框就会生成一个永远匹配不到任何节点的 proto_filter，
// 而症状是「勾了没用」—— 不会报错，最难查。
// 不含 socks5：解析阶段已把它归一成 socks（见 parser.lua 的说明）。
// （ucode 侧对应 parser.uc。）
// 直接引用 node.PROTOS，而不是再写一份字面量：两份逐字相同的清单必然会漂移，
// 而漂移的症状是「勾了没用」且不报错（最难查的一类）。node.uc 只 require
// substore.util，不反向依赖 core，因此这里引用它不会形成循环依赖。
M.RULE_PROTOS = node.PROTOS;

// 「订阅客户端类型」预设。部分机场（如 Allblue 加速器）按 User-Agent 区分客户端：
// 同一个订单链接，只有用**该订单绑定的客户端**的 UA 去请求才返回真实节点，
// 其它 UA 拿到的是「与您使用客户端不兼容」的占位内容 —— 表现为订阅能解析成功，
// 但只有 7 个指向 127.0.0.1:1080 的假节点。
//
// 各 UA 字符串取自客户端源码，非猜测：
//   clash-verge  clash-verge-rev  src-tauri/src/utils/network.rs  `clash-verge/v{版本}`
//   v2rayn       v2rayN          ServiceLib/Common/Utils.cs      `{AppName}/{版本}`（无 v 前缀）
//   clash-party  Clash Party     src/main/config/profile.ts      `mihomo.party/v{版本} (clash.meta)`
//   flclash      FlClash         lib/common/package.dart         三段空格分隔，含 Platform/<os>
// 版本号取用户给出的**最低可用版本**；机场若提高门槛，用户可在「自定义」里改。
// 顺序即表单下拉的显示顺序，不要用 pairs 遍历。
M.UA_PRESETS = [
	{ key: 'clash-verge', label: 'Clash Verge', ua: 'clash-verge/v2.5.0' },
	{ key: 'v2rayn',      label: 'v2rayN',      ua: 'v2rayN/7.22.0' },
	{ key: 'clash-party', label: 'Clash Party', ua: 'mihomo.party/v2.0.0 (clash.meta)' },
	{ key: 'flclash',     label: 'FlClash',     ua: 'FlClash/v0.8.93 clash-verge Platform/linux' },
];

const UA_BY_KEY = {};
for (let p in M.UA_PRESETS) UA_BY_KEY[p.key] = p.ua;

// ---------- Lua 语义辅助 ----------

// Lua 的 `a or b`：只有 nil / false 会回退（0 与 "" 是真值）。
// ucode 的 `??` 只处理 null，`||` 又会把 0 / "" 也当成假值，两者都不等价，
// 因此这里显式实现一份。
function lua_or(v, d) {
	return (v == null || v === false) ? d : v;
}

// Lua 的 tonumber：数字原样返回；字符串支持十进制（含指数）与 0x 十六进制；
// 其余（含布尔、null、对象）一律 nil。不能用 ucode 的 int()：int("1e999") == 1。
function lua_tonumber(v) {
	let t = type(v);
	if (t == 'int' || t == 'double')
		return v;
	if (t != 'string')
		return null;

	let s = trim(v);
	if (s == '')
		return null;

	let hm = match(s, /^([+-]?)0[xX]([0-9A-Fa-f]+)$/);
	if (hm) {
		let n = hex(hm[2]);
		if (n == null || isnan(n))
			return null;
		return (hm[1] == '-') ? -n : n;
	}

	if (match(s, /^[+-]?([0-9]+\.?[0-9]*|\.[0-9]+)([eE][+-]?[0-9]+)?$/) == null)
		return null;

	let n = +s;
	if (isnan(n))
		return null;
	return n;
}

// Lua 的 tostring：nil → "nil"，布尔 → "true"/"false"。仅用于日志。
function tostr(v) {
	if (v == null)
		return 'nil';
	if (v === true)
		return 'true';
	if (v === false)
		return 'false';
	return `${v}`;
}

// Lua 的 `type(x) == "table"`：ucode 里数组与对象是不同类型，两者都要算。
function is_table(v) {
	let t = type(v);
	return t == 'object' || t == 'array';
}

// Lua 的 ipairs：数组按顺序取全部值；对象则从 1 开始取连续整数键，遇到缺位即停。
function seq_values(t) {
	let out = [];

	if (type(t) == 'array') {
		for (let v in t)
			push(out, v);
	}
	else if (type(t) == 'object') {
		for (let i = 1; ; i++) {
			let v = t[i];
			if (v == null)
				break;
			push(out, v);
		}
	}

	return out;
}

// 把表单的 (预设 key, 自定义文本) 解析成最终要发送的 UA 字符串。
// 返回 "" 表示不设置（沿用下载工具自带的 UA），nil + err 表示输入非法。
M.resolve_user_agent = function(preset, custom) {
	preset = util.trim(lua_or(preset, ''));
	if (preset == '') return ['', null];
	let ua;
	if (preset == 'custom') {
		ua = util.trim(lua_or(custom, ''));
		// 选了「自定义」却留空 = 明确要求不设置 UA，不是错误。
		if (ua == '') return ['', null];
	}
	else {
		ua = lua_or(UA_BY_KEY[preset], null);
		if (ua == null) return [null, msg.join('Unknown subscription client type: ', preset)];
	}
	return http.validate_user_agent(ua);
};

// 反向：把已存的 UA 字符串映射回预设 key（编辑页回显用）。
// 不在预设里的一律落到 "custom"，由调用方把原值填进自定义输入框。
M.ua_preset_of = function(ua) {
	let s = util.trim(lua_or(ua, ''));
	if (s == '') return '';
	for (let p in M.UA_PRESETS) {
		if (p.ua === s) return p.key;
	}
	return 'custom';
};

function id_is_valid(id) {
	return type(id) == 'string' && id != '' && match(id, /^[A-Za-z0-9_-]+$/) != null;
}

// 目录权限只收紧一次（每进程）。load() 每次读列表都会调用 ensure_dirs()，
// 无条件 chmod 会让每次读取都多 fork 两个子进程。
let dirs_secured = false;
M.ensure_dirs = function() {
	util.ensure_dir(M.DATA_DIR, '700');
	util.ensure_dir(M.NODES_DIR, '700');
	if (!dirs_secured) {
		dirs_secured = true;
		// mkdir -m 只对**本次新建**的目录生效；从旧版本升级上来的机器上目录已存在，
		// 权限仍是当初按 umask 建的（通常 0755），所以这里显式再 chmod 一次。
		// 目录里是订阅 URL、公开下载 token 与节点凭据，0700 只留 root。
		util.chmod(M.DATA_DIR, '700');
		util.chmod(M.NODES_DIR, '700');
	}
};

// 读取订阅列表，返回 seq, items, err。
//
// 必须区分「文件不存在 / 为空」（合法的空列表）与「文件存在但解析失败」
// （内容损坏、被截断、磁盘错误）。后者若按空列表处理，后果是灾难性的：
// M.add / M.add_local / M.add_combo 会在这个空表上追加一条然后整表写回，
// 把用户已有的全部订阅抹掉，并且 _seq 归零后重新发出 s00000001 这种
// 已经用过的 ID。因此损坏时必须显式报错，由调用方拒绝写入。
function load() {
	M.ensure_dirs();

	let [raw] = util.read_file(M.LIST_FILE);
	if (raw == null || raw == '')
		return [0, {}];

	let [data] = util.json_decode(raw);
	if (!is_table(data))
		return [0, {}, msg.join('Subscription list file is corrupted, cannot parse: ', M.LIST_FILE)];

	let seq = lua_or(lua_tonumber(data._seq), 0);

	// items 必须是「id → 元数据」的映射。Lua 没有数组/对象之分，JSON 里的
	// [] 与 {} 解码后都是 table；ucode 区分两者，而给数组挂字符串键会静默
	// 失败（订阅随即在写回时丢失）。所以这里统一复制到一个对象里。
	let items = {};
	let raw_items = data.items;
	if (is_table(raw_items)) {
		for (let k, v in raw_items)
			items[`${k}`] = v;
	}

	// items 的每个值都必须是订阅元数据表。出现别的类型说明文件不是本程序写的
	// （被手工编辑过 / 被截断后又被补全 / 磁盘错误）。此时不能原样返回：
	//   * M.list / M.get 里的 pairs(meta) 会抛
	//     "bad argument #1 to 'pairs' (table expected, got string)" ——
	//     订阅列表页直接 500；cron 路径更糟，core.list() 抛异常会让整轮同步
	//     在打印 "N ok, M failed" 之前中断，substore-cron.sh 据此判为成功。
	//   * 静默丢弃坏条目再返回也不行：调用方会以为列表完好，下一次 save 就把
	//     它们永久抹掉（与 H8 的整体损坏同一个陷阱）。
	// 因此：返回能用的条目，同时带上损坏错误，让写路径（add / save_meta /
	// write_nodes …）拒绝落盘，与上面的整体损坏走同一条路。
	let bad = false;
	let clean = {};
	for (let id, meta in items) {
		if (is_table(meta))
			clean[id] = meta;
		else
			bad = true;
	}
	if (bad)
		return [seq, clean, msg.join('Subscription list file is corrupted, contains an invalid entry: ', M.LIST_FILE)];

	return [seq, items];
}

function save(seq, items) {
	M.ensure_dirs();
	// 0600：列表里有订阅 URL 与公开下载 token
	return util.atomic_write(M.LIST_FILE, util.json_encode({ _seq: seq, items: items }), '600');
}

// 把「读整表 → 改 → 写整表」串行化。
//
// 没有锁时，LuCI 页面保存订阅、cron 定时更新、组合订阅自动重算三者同时发生，
// 后写者会整表覆盖先写者 —— 用户新增的订阅静默消失，且没有任何报错。
//
// **可重入**：save_combo 内部会调 save_meta，两者都要保护。若第二次调用再去
// 抢锁，会把自己挡在门外（mkdir 已被本进程建过）并返回「正被占用」，
// 于是嵌套的调用必定失败。所以本进程已持锁时只加计数、不再取锁。
// 跨进程互斥仍由 util.lock_acquire 的 mkdir 保证。
let lock_depth = 0;
function with_list_lock(f) {
	// 锁目录是 DATA_DIR 的子目录，父目录不存在时 mkdir 直接失败，
	// 而失败在 lock_acquire 眼里等同于「别人正持有」—— 全新安装上第一次
	// 保存订阅就会报「正被另一个进程修改」。所以先把目录建出来。
	M.ensure_dirs();

	if (lock_depth > 0) {
		lock_depth = lock_depth + 1;
		let [a, b] = f();
		lock_depth = lock_depth - 1;
		return [a, b];
	}

	let lock_dir = M.DATA_DIR + '/.lock';
	if (!util.lock_acquire(lock_dir, { stale: M.LOCK_STALE }))
		return [null, 'Subscription list is being modified by another process, please retry later'];

	lock_depth = 1;
	let [a, b] = f();
	lock_depth = 0;
	util.lock_release(lock_dir);
	return [a, b];
}
// 注：f 抛异常时不会走到释放，锁会留在盘上。这是有意不捕获的 —— 用 try/catch
// 包住会把异常改成返回值，调用方（控制器 / cron）看到的错误形态就变了。
// 残留锁由 util.lock_acquire 的陈旧回收兜底：超过 LOCK_STALE 秒后自动可回收。

// 返回 arr, err。err 非空表示列表文件已损坏。
// 整体无法解析时 arr 为空；只有部分条目非法时 arr 仍包含能用的条目
// （坏条目已被 load 过滤掉，否则下面的 pairs(meta) 会抛异常）。
// 追加第二个返回值是向后兼容的：调用方普遍写成 ipairs(core.list()) 或
// local items = core.list()，都只取第一个值。
M.list = function() {
	let [, items, lerr] = load();
	let arr = [];
	for (let id, meta in items) {
		let m = {};
		for (let k, v in meta)
			m[k] = v;
		m.id = id;
		push(arr, m);
	}
	sort(arr, function(a, b) {
		let an = `${lua_or(a.name, '')}`;
		let bn = `${lua_or(b.name, '')}`;
		if (an < bn) return -1;
		if (an > bn) return 1;
		return 0;
	});
	return [arr, lerr];
};

M.get = function(id) {
	if (!id_is_valid(id)) return null;
	let [, items] = load();
	let meta = items[id];
	if (meta == null) return null;
	let m = {};
	for (let k, v in meta)
		m[k] = v;
	m.id = id;
	return m;
};

function add_impl(name, url, opts) {
	name = util.trim(lua_or(name, ''));
	url = util.trim(lua_or(url, ''));
	opts = lua_or(opts, {});
	if (name == '' || url == '') return [null, 'Name/URL must not be empty'];

	let [seq, items, lerr] = load();
	if (lerr != null) return [null, lerr];

	seq = seq + 1;
	let id = sprintf('s%08x', int(seq));
	let cron_time = util.trim(lua_or(opts.cron_time, ''));
	if (!M.cron_time_valid(cron_time)) cron_time = '';

	items[id] = {
		name: name, url: url, enabled: true,
		node_count: 0, error: '', format: '',
		token: util.rnd_hex(16),
		proxy_enable: (opts.proxy_enable === true || opts.proxy_enable === '1') ? '1' : '0',
		proxy: util.trim(lua_or(opts.proxy, '')),
		user_agent: util.trim(lua_or(opts.user_agent, '')),
		cron_enable: (opts.cron_enable === true || opts.cron_enable === '1') ? cron_time != '' : false,
		cron_time: cron_time,
		rules_enable: (opts.rules_enable === true || opts.rules_enable === '1'),
		proto_filter: util.trim(lua_or(opts.proto_filter, '')),
		keyword_include: util.trim(lua_or(opts.keyword_include, '')),
		keyword_exclude: util.trim(lua_or(opts.keyword_exclude, '')),
		dedup: (opts.dedup === true || opts.dedup === '1') ? '1' : '0',
		rename_map: lua_or(opts.rename_map, ''),
		'local': false,
		raw_content: '',
		local_mode: 'text',
	};

	let [ok] = save(seq, items);
	if (!ok) return [null, 'Write failed'];
	return [id, null];
}

function add_local_impl(name, raw_content, local_mode, opts) {
	name = util.trim(lua_or(name, ''));
	raw_content = util.trim(lua_or(raw_content, ''));
	local_mode = lua_or(local_mode, 'text');
	opts = lua_or(opts, {});
	if (name == '' || raw_content == '') return [null, 'Name/Content must not be empty'];

	let [seq, items, lerr] = load();
	if (lerr != null) return [null, lerr];

	seq = seq + 1;
	let id = sprintf('s%08x', int(seq));
	items[id] = {
		name: name, url: '', enabled: true,
		node_count: 0, error: '', format: '',
		token: util.rnd_hex(16),
		proxy_enable: '0', proxy: '', user_agent: '',
		cron_enable: false, cron_time: '',
		rules_enable: (opts.rules_enable === true || opts.rules_enable === '1'),
		proto_filter: util.trim(lua_or(opts.proto_filter, '')),
		keyword_include: util.trim(lua_or(opts.keyword_include, '')),
		keyword_exclude: util.trim(lua_or(opts.keyword_exclude, '')),
		dedup: (opts.dedup === true || opts.dedup === '1') ? '1' : '0',
		rename_map: lua_or(opts.rename_map, ''),
		'local': true,
		raw_content: raw_content,
		local_mode: local_mode,
	};

	let [ok] = save(seq, items);
	if (!ok) return [null, 'Write failed'];
	// 立即解析一次
	M.sync(id);
	return [id, null];
}

// 获取订阅的下载 token；若不存在则生成并持久化
function ensure_token_impl(id) {
	if (!id_is_valid(id)) return [null, null];

	let [seq, items, lerr] = load();
	if (lerr != null) return [null, null];

	let meta = items[id];
	if (meta == null) return [null, null];

	if (meta.token == null || meta.token === false || meta.token === '') {
		let tok = util.rnd_hex(16);
		meta.token = tok;
		// 没落盘的 token 不能交出去：id_by_token 是从磁盘读的，交出去等于给用户
		// 一个必然报「无效的订阅 token」的链接；而且内存表用完即弃，
		// 下一次调用会再生成一个**不同**的 token，链接还会跳来跳去。
		// 失败就返回 nil，由调用方按「拿不到 token」处理。
		let [ok] = save(seq, items);
		if (!ok) return [null, 'Write failed'];
		return [tok, null];
	}
	return [meta.token, null];
}

// 依据 token 查找订阅 ID
function id_by_token(token) {
	if (type(token) != 'string' || token == '') return null;
	let [, items] = load();
	for (let id, meta in items) {
		if (meta != null && meta.token === token) return id;
	}
	return null;
}

// 生成订阅下载内容：按 target 格式转换节点。返回 content, content_type, filename, err
M.generate_link = function(token, target, opts) {
	opts = lua_or(opts, {});
	let id = id_by_token(token);
	if (id == null) return [null, null, null, 'Invalid subscription token'];
	let meta = M.get(id);
	let nodes = M.read_nodes(id);
	if (length(nodes) == 0) return [null, null, null, 'No available nodes (update the subscription first)'];

	const output = require('substore.output');
	let [content, err] = output.generate(nodes, target, opts);
	if (content == null || content === false) return [null, null, null, lua_or(err, 'Failed to generate the target format')];

	let ct = lua_or(lua_or(opts.content_type, output.content_type_for(target)), 'text/plain; charset=utf-8');
	let ext = lua_or(output.extension_for(target), 'txt');
	let base = (meta != null && meta.name != null && meta.name !== false && meta.name != '')
		? meta.name : id;
	let filename = `${base}.${ext}`;
	return [content, ct, filename, null];
};

// save_meta 补丁里的「清除」哨兵值。
// Lua 的 pairs 永远不会产出值为 nil 的键，所以补丁表里写 `k = nil` 等于什么都没写，
// 调用方无法表达「把这个字段删掉」。需要清除时传 M.CLEAR，save_meta 会还原成 nil。
// （ucode 的空对象是独立引用，`===` 即身份比较，可安全当哨兵。）
M.CLEAR = {};

function save_meta_impl(id, patch) {
	if (!id_is_valid(id)) return [false, 'Invalid ID'];

	let [seq, items, lerr] = load();
	if (lerr != null) return [false, lerr];

	let meta = items[id];
	if (meta == null) return [false, 'Subscription not found'];

	for (let k, v in lua_or(patch, {})) {
		// ucode 里显式写了 null 的键会出现在遍历结果里；它对应 Lua 的「键不存在」，
		// 语义上同样是删除，因此与 CLEAR 一样处理。
		if (v == null || v === M.CLEAR)
			delete meta[k];
		else
			meta[k] = v;
	}
	return save(seq, items);
}

function remove_impl(id) {
	if (!id_is_valid(id)) return [false, null];

	let [seq, items, lerr] = load();
	if (lerr != null) return [false, lerr];

	if (items[id] == null) return [false, null];
	delete items[id];

	// 引用这个订阅的组合：把死 id 从 sources 里摘掉，同时记下要重算的组合。
	//
	// 必须**在同一趟里**收集，不能摘完再调 M.refresh_combos(id)：后者是按
	// 「sources 里包含 src_id」来筛组合的，死 id 一旦摘掉就一个都匹配不到，
	// 物化节点会一直是旧的 —— 看着改了，其实没修。
	//
	// 摘掉死 id 而不是留着：留着的话列表页「来源」列会显示 s00000003 这种裸 id
	// （模板用 name_by_id[sid] or sid 兜底），而且当组合的来源被删光时，
	// combo_refresh 看到 #srcs > 0，不会给出「请选择至少一个订阅」，
	// 组合会静默变成 0 节点。与列表同一次写盘落盘，不留下中间状态。
	let affected = [];
	for (let cid, c in items) {
		let srcs = is_table(c.sources) ? seq_values(c.sources) : null;
		if (srcs != null) {
			let kept = [], hit = false;
			for (let s in srcs) {
				if (s === id) hit = true;
				else push(kept, s);
			}
			if (hit) {
				c.sources = kept;
				push(affected, cid);
			}
		}
	}

	// 写盘失败必须中止。`items[id] = nil` 只改了内存里的表，磁盘上这条订阅还在：
	// 继续往下走会删掉它的节点文件，于是订阅「列表里还在、点进去却空了」，
	// 而调用方拿到 true，以为删成功了。
	// 组合的 sources 剪除同理：没落盘的改动不重算（重算只会从磁盘读回旧状态）。
	let [ok, serr] = save(seq, items);
	if (!ok) return [false, lua_or(serr, 'Write failed')];

	unlink(M.nodes_file(id));

	// 组合的物化节点在 nodes/<combo>.json，只有 combo_refresh 会重写它。
	// 不在这里重算的话，组合的下载链接会继续吐已删订阅的节点，一直等到别的源
	// 更新（M.sync 里那次 refresh_combos）才被动纠正。
	//
	// 位置与 M.sync 一致：都在写入口内部调用，由 save_meta 进入临界区
	// （with_list_lock 可重入，见文件末尾的说明）。
	for (let cid in affected)
		M.combo_refresh(cid);

	return [true, null];
}

M.nodes_file = function(id) {
	return M.NODES_DIR + '/' + id + '.json';
};

M.write_nodes = function(id, nodes) {
	M.ensure_dirs();
	// 0600：节点文件里有 uuid / 密码 / 私钥等全部凭据
	return util.atomic_write(M.nodes_file(id), util.json_encode(nodes), '600');
};

M.read_nodes = function(id) {
	if (!id_is_valid(id)) return [];
	let [raw] = util.read_file(M.nodes_file(id));
	if (raw == null || raw == '') return [];
	let [nodes] = util.json_decode(raw);
	// Lua 版只判 type(nodes) == "table"：对象与数组都算。但调用方一律按列表用
	// （#nodes / ipairs），对象在 Lua 里同样表现为 0 个节点，所以这里归一成数组。
	if (type(nodes) != 'array') return [];
	return nodes;
};

// 解析 subscription-userinfo 响应头（upload/download/total/expire），返回数字表或 nil
M.parse_userinfo = function(s) {
	if (type(s) != 'string' || s == '') return null;
	let u = {};
	let pos = 0;
	const n = length(s);
	// Lua 的 gmatch 在整串里找不重叠的匹配；这里用「锚定匹配 + 失败就前进一字节」
	// 复现同样的扫描。
	while (pos < n) {
		let m = match(substr(s, pos), /^([A-Za-z0-9_-]+)\s*=\s*([^;]+)/);
		if (m) {
			let key = lc(m[1]);
			if (key == 'upload' || key == 'download' || key == 'total' || key == 'expire') {
				let num = lua_tonumber(util.trim(m[2]));
				if (num != null) u[key] = num;
			}
			pos += length(m[0]);
		}
		else {
			pos++;
		}
	}
	if (length(keys(u)) == 0) return null;
	return u;
};

// 下载并解析订阅，写入节点文件并更新状态。成功返回 node_count，失败返回 nil, err
M.sync = function(id) {
	let log = function(m) { system('logger -t luci-app-substore ' + util.shq(m)); };
	log('Sync start id=' + tostr(id));

	let meta = M.get(id);
	if (meta == null) { log('Sync fail: subscription not found'); return [null, 'Subscription not found']; }

	// 组合订阅：无下载源，直接重算合并节点
	if (M.is_combo(meta)) {
		log('Sync combo refresh');
		let [cnt, cerr] = M.combo_refresh(id);
		if (cnt == null) log('Combo refresh fail: ' + tostr(cerr));
		return [cnt, cerr];
	}

	// 本地订阅：直接解析 raw_content
	if (meta['local']) {
		log('Sync local subscription');
		let content = lua_or(meta.raw_content, '');
		if (content == '') {
			// 失败路径一律不改 node_count：磁盘上的旧节点仍在，订阅链接仍在下发（§35）
			M.save_meta(id, { error: 'Local subscription content is empty', last_update: time() });
			return [null, 'Local subscription content is empty'];
		}
		let [res, perr] = parser.parse_local(content, lua_or(meta.local_mode, 'text'));
		if (res == null || res.nodes == null) {
			log('Parse local fail: ' + tostr(perr));
			M.save_meta(id, { error: lua_or(perr, 'Failed to parse local content'), last_update: time() });
			return [null, lua_or(perr, 'Failed to parse local content')];
		}
		log('Parse local ok nodes=' + length(res.nodes));
		let nodes = M.apply_rules(res.nodes, meta);
		let [wok] = M.write_nodes(id, nodes);
		if (!wok) {
			M.save_meta(id, { error: 'Failed to write node data', last_update: time() });
			return [null, 'Failed to write node data'];
		}
		let [ok] = M.save_meta(id, {
			node_count: length(nodes), format: lua_or(res.format, 'local'), error: '', last_update: time(),
		});
		if (!ok) return [null, 'Failed to update status'];
		M.refresh_combos(id);
		return [length(nodes), null];
	}

	if (meta.url == null || meta.url === false || meta.url === '') { log('Sync fail: no URL'); return [null, 'No subscription URL']; }

	// 订阅代理：开启时代理地址必须有效。无效就明确失败——
	// 静默直连会让用户以为流量走了代理，属于必须避免的 silent fallback（§12）。
	let proxy = '';
	if (meta.proxy_enable === true || meta.proxy_enable === '1') {
		let [p, perr] = http.parse_proxy(lua_or(meta.proxy, ''));
		if (p == null || p === '') {
			let perr_text = lua_or(perr, 'Proxy address is empty');
			log('Proxy invalid: ' + tostr(perr_text));
			M.save_meta(id, { error: msg.join('Invalid proxy config: ', perr_text), last_update: time() });
			return [null, msg.join('Invalid proxy config: ', perr_text)];
		}
		proxy = p;
	}
	// 日志不记录代理凭据（§39）
	if (proxy !== '') log('Using proxy ' + http.redact_proxy(proxy));

	// 订阅客户端类型（User-Agent）：部分机场按 UA 决定返回真实节点还是占位内容。
	// 与代理一样，**非法值必须明确失败**：静默忽略会让用户以为 UA 已生效，
	// 而实际拿到的是占位节点（§12 禁止 silent fallback）。
	let [ua, uaerr] = http.validate_user_agent(meta.user_agent);
	if (ua == null) {
		log('User-Agent invalid: ' + tostr(uaerr));
		M.save_meta(id, { error: msg.join('Invalid User-Agent: ', uaerr), last_update: time() });
		return [null, msg.join('Invalid User-Agent: ', uaerr)];
	}
	if (ua !== '') log('Using User-Agent ' + ua);

	let [content, headers, err] = http.download(meta.url, { max_size: M.MAX_SIZE, timeout: M.TIMEOUT,
		proxy: proxy, user_agent: ua });
	if (content == null || content === false) {
		// 下载工具的报错可能回显含凭据的 URL，写日志与入库前先抹掉（§39）
		let safe_err = http.scrub_credentials(lua_or(err, 'Download failed'));
		log('Download fail: ' + safe_err);
		M.save_meta(id, { error: safe_err, last_update: time() });
		return [null, safe_err];
	}
	log('Download ok size=' + length(content));

	let ui = M.parse_userinfo(headers != null ? headers['subscription-userinfo'] : null);
	if (ui != null) log('Userinfo total=' + tostr(ui.total) + ' expire=' + tostr(ui.expire));

	let [res, perr] = parser.parse(content);
	if (res == null || res.nodes == null) {
		log('Parse fail: ' + tostr(perr));
		M.save_meta(id, { error: lua_or(perr, 'Parse failed'), last_update: time() });
		return [null, lua_or(perr, 'Parse failed')];
	}
	log('Parse ok nodes=' + length(res.nodes));

	let nodes = M.apply_rules(res.nodes, meta);
	let [wok] = M.write_nodes(id, nodes);
	if (!wok) {
		M.save_meta(id, { error: 'Failed to write node data', last_update: time() });
		return [null, 'Failed to write node data'];
	}

	let [ok] = M.save_meta(id, {
		node_count: length(nodes), format: res.format, error: '', last_update: time(),
		// 机场不再下发 subscription-userinfo 时必须把旧数值清掉，
		// 否则列表页会一直显示早已过期的流量/到期时间。用 M.CLEAR 表达「清除」。
		// （Lua 的 `(ui and ui.upload) or M.CLEAR` 还会把 false 当缺失，这里一并保留。）
		upload: (ui != null && ui.upload != null && ui.upload !== false) ? ui.upload : M.CLEAR,
		download: (ui != null && ui.download != null && ui.download !== false) ? ui.download : M.CLEAR,
		total: (ui != null && ui.total != null && ui.total !== false) ? ui.total : M.CLEAR,
		expire: (ui != null && ui.expire != null && ui.expire !== false) ? ui.expire : M.CLEAR,
	});
	if (!ok) return [null, 'Failed to update status'];

	// 源订阅更新后，刷新引用它的组合订阅
	M.refresh_combos(id);
	return [length(nodes), null];
};

// 对节点应用订阅级规则（rules_enable 为真时生效）；纯函数，便于测试
M.apply_rules = function(nodes, meta) {
	meta = lua_or(meta, {});
	if (!(meta.rules_enable === true || meta.rules_enable === '1')) return nodes;
	let rules = {
		proto_filter: lua_or(meta.proto_filter, ''),
		keyword_include: lua_or(meta.keyword_include, ''),
		keyword_exclude: lua_or(meta.keyword_exclude, ''),
		dedup: lua_or(meta.dedup, '0'),
		rename_map: lua_or(meta.rename_map, ''),
	};
	return node.apply_rules(nodes, rules);
};

// ---------- 单节点编辑 ----------

// 表单管理的字段集合：合并时先从原节点清除，再用表单值覆盖，未出现在表单中的字段（raw/tags 等）保留
const FORM_KEYS = {
	name: true, group: true, server: true, port: true, password: true,
	cipher: true, method: true, protocol: true, obfs: true,
	'obfs-param': true, obfs_param: true, 'protocol-param': true, protocol_param: true,
	udp: true, uuid: true, alterId: true, net: true, network: true,
	headerType: true, path: true, host: true, sni: true, tls: true,
	'skip-cert-verify': true, skip_cert_verify: true, security: true, flow: true,
	'obfs-password': true, obfs_password: true,
	// SIP003 插件串（shadowsocks）。必须在表里：merge_form_node 只清 FORM_KEYS 里
	// 的键，缺了这一项，用户在表单里清空插件输入框也删不掉旧值。
	plugin: true,
	'private-key': true, private_key: true, 'peer-public-key': true, peer_public_key: true,
	'public-key': true, public_key: true, 'pre-shared-key': true, preshared_key: true,
	ip: true, ipv6: true, 'allowed-ips': true, allowed_ips: true,
	reserved: true, 'persistent-keepalive': true, persistent_keepalive: true,
	'listen-port': true, listen_port: true,
	mtu: true, dns: true, 'amnezia-wg-option': true,
	// socks / http 的用户名。必须在表里：下面的 merge_form_node 先按 FORM_KEYS
	// 清空原节点再套用提交值，不在表里的字段会保留旧值——用户在表单里清空用户名
	// 也删不掉（collectNodes 会略过空值），等于改不动。
	username: true,
};

// FORM_KEYS 里同一个语义的多种写法。表单只渲染其中的规范写法，别名必须跟随规范
// 写法一起清空：解析器产出的就是别名（parser_clash_yaml 写 skip_cert_verify、
// parser_json_config 与 parser.uc 写 obfs_param / protocol_param），残留的别名
// 仍会被输出模块读到，表现为「关不掉」——例如 build_tls 在 security 为 "none"
// 时还会退回 n.tls，output_formats.surge_line 同理，于是用户把 vmess 的 TLS
// 关掉之后 Surge 输出里依然是 tls=true。
const FORM_ALIASES = {
	'obfs_param': 'obfs-param',
	'protocol_param': 'protocol-param',
	'skip_cert_verify': 'skip-cert-verify',
	'obfs_password': 'obfs-password',
	'private_key': 'private-key',
	'public_key': 'public-key',
	'peer-public-key': 'public-key',
	'peer_public_key': 'public-key',
	'preshared_key': 'pre-shared-key',
	'allowed_ips': 'allowed-ips',
	'persistent_keepalive': 'persistent-keepalive',
	'listen_port': 'listen-port',
	'network': 'net',
	// normalize 把 tls 归一到 security，两者是同一语义的两种写法
	'tls': 'security',
	// shadowsocks 用 method、vmess/ssr 用 cipher，parse_local 双向互为别名
	'method': 'cipher',
	'cipher': 'method',
};

// 合并表单节点到原节点。
//
// 只有「该协议的表单确实渲染过」的字段才允许被覆盖（含被清空）：表单按
// node.PROTO_FIELDS[proto] 渲染，未渲染的字段根本提交不上来，把它们一并清空
// 就等于用空值覆盖原值 —— vmess 的 security、hysteria2/tuic 的 security、
// WireGuard 的 dns 都是这样被静默抹掉的（详见 node.PROTO_FIELDS 的注释）。
// 别名（FORM_ALIASES）跟随其规范写法一起清空，避免残留值「关不掉」。
//
// 协议未知（不在 PROTO_FIELDS 里）时退回「清空全部表单字段」的旧行为：
// 那时无从判断表单渲染了什么，清空虽然可能丢字段，但至少不会留下用户改不动的旧值。
M.merge_form_node = function(orig, formnode) {
	let out = {};
	for (let k, v in lua_or(orig, {}))
		out[k] = v;

	let fields = (is_table(formnode) && formnode.proto != null)
		? lua_or(node.PROTO_FIELDS[`${formnode.proto}`], null) : null;
	let old_fields = (is_table(orig) && orig.proto != null)
		? lua_or(node.PROTO_FIELDS[`${orig.proto}`], null) : null;

	// 原协议未知（或原节点没有 proto）时不做「只清渲染字段」的裁剪：那种情况下
	// 无从判断原节点里哪些字段是本协议的，退回到清空全部表单字段的旧行为。
	if (fields != null && (orig == null || orig.proto == null || old_fields != null)) {
		let rendered = {};
		for (let k in fields)
			rendered[k] = true;
		// 协议被改过时，旧协议的字段也要清掉（vmess 改成 trojan 不该留着 uuid）。
		// 协议没变时 old_fields == fields，是同一个集合，无副作用。
		for (let k in lua_or(old_fields, []))
			rendered[k] = true;
		for (let k in node.FORM_ALWAYS_FIELDS)
			rendered[k] = true;
		for (let k in FORM_KEYS) {
			// 先看字段本身是否被渲染；只有「别名」才回退到它的规范写法。
			// 顺序不能反：method 与 cipher 互为别名，若一律先查别名表，
			// shadowsocks 渲染的 method 会被判成「cipher 没渲染」而不清空。
			let canon = rendered[k] ? k : lua_or(FORM_ALIASES[k], k);
			if (rendered[canon])
				delete out[k];
		}
	}
	else {
		for (let k in FORM_KEYS)
			delete out[k];
	}

	for (let k, v in lua_or(formnode, {})) {
		// Lua 的 pairs 不会产出值为 nil 的键；ucode 里显式 null 的键等同于「未提交」，
		// 不能拿它覆盖原值（否则表单清不掉的字段会被 null 抹掉）。
		if (k != 'type' && v != null)
			out[k] = v;
	}
	return out;
};

// ---------- 组合订阅（combo） ----------

// 判断是否为组合订阅
M.is_combo = function(meta) {
	return meta != null && (meta.combo === true || is_table(meta.sources));
};

// 物化组合节点：按 sources 顺序合并各源节点，再应用组合自身的规则（复用 per-sub 规则字段）
M.combo_nodes = function(meta) {
	if (!is_table(meta)) return [];
	let srcs = is_table(meta.sources) ? seq_values(meta.sources) : [];
	let merged = [];
	for (let sid in srcs) {
		let ns = M.read_nodes(sid);
		for (let n in ns)
			push(merged, n);
	}
	return M.apply_rules(merged, meta);
};

// 重新计算组合节点并落盘，更新状态。成功返回 node_count，失败返回 nil, err
M.combo_refresh = function(id) {
	if (!id_is_valid(id)) return [null, 'Invalid ID'];
	let meta = M.get(id);
	if (meta == null) return [null, 'Subscription not found'];

	let srcs = is_table(meta.sources) ? seq_values(meta.sources) : [];
	if (length(srcs) == 0) {
		M.save_meta(id, { error: 'Select at least one subscription', node_count: 0, last_update: time() });
		return [null, 'Select at least one subscription'];
	}

	let nodes = M.combo_nodes(meta);
	let [wok] = M.write_nodes(id, nodes);
	if (!wok) {
		M.save_meta(id, { error: 'Failed to write node data', last_update: time() });
		return [null, 'Failed to write node data'];
	}
	M.save_meta(id, { node_count: length(nodes), error: '', last_update: time() });
	return [length(nodes), null];
};

// 源订阅更新后刷新所有引用它的组合，避免组合停留旧数据
M.refresh_combos = function(src_id) {
	if (src_id == null || src_id === false) return;
	let [items] = M.list();
	for (let it in items) {
		let srcs = is_table(it.sources) ? seq_values(it.sources) : [];
		for (let sid in srcs) {
			if (sid === src_id) {
				M.combo_refresh(it.id);
				break;
			}
		}
	}
};

// 创建组合订阅（无 URL，cron/代理禁用）；成功后物化节点。返回 id 或 nil, err
function add_combo_impl(name, sources, opts) {
	name = util.trim(lua_or(name, ''));
	opts = lua_or(opts, {});
	if (name == '') return [null, 'Name cannot be empty'];

	let srcs = [];
	if (is_table(sources)) {
		for (let s0 in seq_values(sources)) {
			let s = util.trim(`${lua_or(s0, '')}`);
			if (s != '' && id_is_valid(s)) push(srcs, s);
		}
	}
	if (length(srcs) == 0) return [null, 'Select at least one subscription'];

	let [seq, items, lerr] = load();
	if (lerr != null) return [null, lerr];

	seq = seq + 1;
	let id = sprintf('s%08x', int(seq));
	items[id] = {
		name: name, url: '', enabled: true, combo: true, sources: srcs,
		node_count: 0, error: '', format: '',
		token: util.rnd_hex(16),
		proxy_enable: '0', proxy: '', user_agent: '',
		cron_enable: false, cron_time: '',
		rules_enable: (opts.rules_enable === true || opts.rules_enable === '1'),
		proto_filter: util.trim(lua_or(opts.proto_filter, '')),
		keyword_include: util.trim(lua_or(opts.keyword_include, '')),
		keyword_exclude: util.trim(lua_or(opts.keyword_exclude, '')),
		dedup: (opts.dedup === true || opts.dedup === '1') ? '1' : '0',
		rename_map: lua_or(opts.rename_map, ''),
	};

	let [ok] = save(seq, items);
	if (!ok) return [null, 'Write failed'];

	M.combo_refresh(id);
	return [id, null];
}

// 编辑组合订阅：更新名称/来源/规则后重算物化节点。成功返回 node_count，失败返回 nil, err
function save_combo_impl(id, name, sources, opts) {
	if (!id_is_valid(id)) return [null, 'Invalid ID'];

	name = util.trim(lua_or(name, ''));
	if (name == '') return [null, 'Name cannot be empty'];

	let srcs = [];
	if (is_table(sources)) {
		for (let s0 in seq_values(sources)) {
			let s = util.trim(`${lua_or(s0, '')}`);
			if (s != '' && id_is_valid(s) && s !== id) push(srcs, s);
		}
	}
	if (length(srcs) == 0) return [null, 'Select at least one subscription'];

	opts = lua_or(opts, {});
	M.save_meta(id, {
		name: name, sources: srcs,
		rules_enable: (opts.rules_enable === true || opts.rules_enable === '1'),
		proto_filter: util.trim(lua_or(opts.proto_filter, '')),
		keyword_include: util.trim(lua_or(opts.keyword_include, '')),
		keyword_exclude: util.trim(lua_or(opts.keyword_exclude, '')),
		dedup: (opts.dedup === true || opts.dedup === '1') ? '1' : '0',
		rename_map: lua_or(opts.rename_map, ''),
	});
	return M.combo_refresh(id);
}

// 合并多个订阅的节点
M.merge = function(ids, opts) {
	opts = lua_or(opts, {});
	let all = [];
	for (let id in seq_values(ids)) {
		let nodes = M.read_nodes(id);
		for (let n in nodes)
			push(all, n);
	}
	// 规则已在各订阅 sync 时按订阅级配置应用；此处仅应用 opts 过滤
	// （Lua 的 `if opts.proto` / `if opts.dedup` 对 "" 与 0 也成立，故用非 nil/false 判断。）
	if (opts.proto != null && opts.proto !== false)
		all = node.filter(all, { proto: opts.proto });
	if (opts.keyword != null && opts.keyword !== false && opts.keyword !== '')
		all = node.filter(all, { keyword: opts.keyword });
	if (opts.dedup != null && opts.dedup !== false)
		all = node.dedup(all);
	if (opts.sort != null && opts.sort !== false)
		all = node.sort(all, opts.sort, opts.desc);
	return all;
};

// 校验 cron 表达式：5 个字段，每个为数字或 *，防 cron 文件命令注入
M.cron_time_valid = function(ct) {
	if (type(ct) != 'string') return false;
	// 控制字符一律拒绝。原先用 `%S+` 取词，它把换行也当分隔符：`"1\n 3 * * *"`
	// 同样切成 5 个合法词元并通过校验，然后被 write_cron 原样写进
	// /etc/cron.d/substore —— 那一行会断成两行，前一行 `1` 不是合法的
	// crontab 条目，cron 每次 reload 都报语法错。分隔符必须是单个空格：
	// 下面改用整串匹配，制表符 / 多空格 / 换行都落不进来。
	for (let i = 0; i < length(ct); i++) {
		let c = ord(substr(ct, i, 1));
		if (c < 32 || c == 127) return false;
	}
	let fields = match(ct, /^(\S+) (\S+) (\S+) (\S+) (\S+)$/);
	if (fields == null) return false;
	for (let i = 1; i <= 5; i++) {
		if (fields[i] != '*' && match(fields[i], /^[0-9]+$/) == null)
			return false;
	}
	return true;
};

// 依据各订阅的 cron 设置生成 /etc/cron.d/substore；无启用项则移除该文件
M.write_cron = function() {
	let lines = ['# luci-app-substore cron (per-subscription)'];
	let [subs] = M.list();
	for (let it in subs) {
		let en = (it.cron_enable === true || it.cron_enable === '1');
		let ct = util.trim(lua_or(it.cron_time, ''));
		if (en && M.cron_time_valid(ct))
			push(lines, ct + ' root /usr/bin/substore-cron.sh ' + it.id + ' >/tmp/substore-cron.log 2>&1');
	}
	if (length(lines) == 1) {
		unlink(M.CRON_FILE);
		return [true, null];
	}
	return util.atomic_write(M.CRON_FILE, join('\n', lines) + '\n');
};

// ---------- 写入口的列表锁 ----------
//
// 逐个函数改名再包一层，而不是在每个函数体里手写 acquire/release：
// 后者一旦有人在中途 return（`if lerr then return nil, lerr end` 这种）就会漏掉
// 释放，而漏释放的症状是「过一会儿自己好了」（陈旧回收），最难查。
// 包在最外层则无论函数从哪条路径返回都会释放。
//
// 只包**写**入口。M.list / M.get / M.read_nodes / M.merge 是只读的（merge 只
// 读各订阅的节点、过滤排序后返回数组，从不写列表），加锁会让每次页面刷新都去
// 抢锁，白白增加失败面 —— 而且失败时它们会返回 nil 而不是原本的数组/表，
// 把「拿不到锁」变成调用方眼里的「没有数据」，比不加锁更糟。
// M.sync / M.combo_refresh / M.refresh_combos 自己不写列表（写列表的是它们内部
// 调用的 M.save_meta），因此也不在此列 —— 它们经由被包住的 save_meta 进入临界区。
//
// Lua 5.1 不允许在内层函数里直接用外层函数的 `...`，先收进表再展开。
// 这些入口的参数都是位置参数且非 nil（可选参数一律排在最后），
// 不存在中间空洞把 unpack 截断的情况。
// ucode 这里没有等价的变参展开，改为逐个显式列出（入参都是位置参数，
// 可选参数一律排在最后），语义与「最外层包一层 with_list_lock」完全一致。
M.add = function(name, url, opts) {
	return with_list_lock(function() { return add_impl(name, url, opts); });
};

M.add_local = function(name, raw_content, local_mode, opts) {
	return with_list_lock(function() { return add_local_impl(name, raw_content, local_mode, opts); });
};

M.ensure_token = function(id) {
	return with_list_lock(function() { return ensure_token_impl(id); });
};

M.save_meta = function(id, patch) {
	return with_list_lock(function() { return save_meta_impl(id, patch); });
};

M.remove = function(id) {
	return with_list_lock(function() { return remove_impl(id); });
};

M.add_combo = function(name, sources, opts) {
	return with_list_lock(function() { return add_combo_impl(name, sources, opts); });
};

M.save_combo = function(id, name, sources, opts) {
	return with_list_lock(function() { return save_combo_impl(id, name, sources, opts); });
};

return M;
