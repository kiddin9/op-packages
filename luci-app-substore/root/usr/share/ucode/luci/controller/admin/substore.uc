// controller/admin/substore.uc — LuCI ucode 路由动作（2.8.0 起替代 Lua 控制器）
//
// 路由注册本身在 /usr/share/luci/menu.d/luci-app-substore.json 里；本文件只导出
// 动作函数，由 dispatcher 按菜单项的 module/function 调用。
//
// 用户可见文案统一走 LuCI 的翻译层：msgid 一律写**英文**，译文放
// po/<lang>/substore.po（编译成 *.lmo 后由 luci.core 按运行时语言加载）。
// dispatcher 会把 `_`、`N_`、`entityencode`、`http`、`ctx`、`dispatcher`、
// `include` 等注入动作函数的执行作用域（见 dispatcher.uc 的 run_action）。
//
// 后端（substore.* 模块）返回的是**语言中立的英文 msgid** —— 它们不能
// require("luci.i18n")（等效物），因为 substore-cron.sh 会在没有 LuCI 环境的
// 独立 ucode 进程里跑 core.sync。翻译在这里做：控制器是 ?err= 这条回显链路的边界。
//
// msg.translate 对**已经翻译过**的串是幂等的（见 msg.uc），所以下面那些
// `err or _("…")` 的 fallback 传进来也不会被二次翻译。

'use strict';

import { urlencode } from 'luci.http';
import { floor } from 'math';

const util = require('substore.util');
const msg = require('substore.msg');

function tmsg(s) {
	return msg.translate(s, _);
}

// 返回列表页。err 非空时把错误带到列表页显示（§18：失败必须让用户看见，
// 不能「失败了却看起来像成功」）。沿用既有的 query + 模板渲染，不引入新 framework。
function back_to_list(err) {
	let url = dispatcher.build_url('admin', 'services', 'substore', 'list');

	if (err != null && `${err}` != '')
		url += '?err=' + urlencode(tmsg(err));

	http.redirect(url);
}

// 表单字段统一取字符串。
//
// LuCI 的 formvalue **不保证返回字符串**：同名字段提交多次时返回的是数组
// （luci/http.uc 的 urldecode_message_body：第二次出现时把值改写成数组）。
// 本项目多处直接对返回值 trim / urlencode，遇到数组会抛错 → HTTP 500。
// 攻击面不限于已登录用户：/substore/download 是**无需登录**的入口（供
// Passwall / OpenClash 拉取），对它 POST 一个重复的 token 字段即可触发。
// 统一收敛后这类输入不再崩溃。
//
// 取值语义：数组取最后一个（与「同名参数后者覆盖前者」的直觉一致），
// null 保持 null（post_ok 依赖这一点区分「无 token」与「空 token」）。
function fv(key) {
	let v = http.formvalue(key);

	if (type(v) == 'array')
		v = length(v) ? v[length(v) - 1] : null;

	if (v == null)
		return null;

	return `${v}`;
}

// post_ok 失败的原因，供调用方回显（§18：失败必须让用户看见）。
// 每个请求是一个独立的 ucode 进程，不存在跨请求残留；同一进程内多次调用时
// post_ok 成功会把它清空，因此不会把上一次的失败带进这一次。
let post_fail_msg = null;

// POST 请求的 token 校验。
//
// 上游 LuCI 渲染表单时，模板变量 `token` 就是 dispatcher 的 ctx.authtoken，
// 所以「提交的 token == authtoken」正是框架自己那套判定（dispatcher.uc 的
// test_post_security），不可能误拒合法表单 —— 合法表单提交的就是 authtoken。
//
// 此前的判定是 `token != null`：`token=`（空串）也能通过，等于没有校验。
// 取不到 authtoken 时（非标准上下文）退回原判定，不能因为拿不到框架内部
// 字段就把所有表单都拒掉。
function post_ok() {
	let tok = fv('token');

	if (tok == null) {
		post_fail_msg = _('Request validation failed (missing token), please refresh the page and try again');
		return false;
	}

	let authtoken = ctx.authtoken;

	if (type(authtoken) == 'string' && authtoken != '' && tok != authtoken) {
		post_fail_msg = _('Request validation failed (token mismatch), please refresh the page and try again');
		return false;
	}

	post_fail_msg = null;
	return true;
}

// read cron fields from form, validate cron expression, return [cron_enable, cron_time]
function read_cron_fields() {
	const core = require('substore.core');

	let cron_enable = fv('cron_enable') ?? '0';
	let m = fv('cron_min') ?? '0';
	let h = fv('cron_hour') ?? '3';
	let dom = fv('cron_dom') ?? '*';
	let mon = fv('cron_mon') ?? '*';
	let dow = fv('cron_dow') ?? '*';
	let cron_time = join(' ', [m, h, dom, mon, dow]);

	if (!core.cron_time_valid(cron_time)) {
		cron_enable = '0';
		cron_time = '';
	}

	if (cron_enable != '1')
		cron_enable = '0';

	return [cron_enable, cron_time];
}

// read subscription client type (User-Agent) from form, return [ua, err]
//
// 部分机场按 User-Agent 决定返回真实节点还是占位内容。表单提交的是
// 「预设 key（ua_preset）+ 自定义文本（ua_custom）」，这里解析成最终要存的 UA。
// 非法值必须回显（与规则校验同理）：静默存空会让用户以为设置生效了，
// 实际更新出来的仍是占位节点。
function read_ua_fields() {
	const core = require('substore.core');

	return core.resolve_user_agent(fv('ua_preset'), fv('ua_custom'));
}

// read subscription level rules from form, return [rules, err]
//
// 第二个返回值是**用户可见**的校验错误。目前只有重命名规则的正则需要校验：
// 非法 pattern 会被 node.rename_with_rules 静默吞掉，用户看到的是
// 「规则写了但没生效」。在这里拦下来，调用方用 back_to_list(err) 回显。
function read_rules_fields() {
	const core = require('substore.core');
	const node = require('substore.node');

	let proto_list = [];

	// 协议清单来自 core.RULE_PROTOS，与表单模板共用一份（见该常量的说明）
	for (let p in core.RULE_PROTOS)
		if (fv('proto_filter_' + p))
			push(proto_list, p);

	let rules_enable = fv('rules_enable') ?? '0';

	if (rules_enable != '1')
		rules_enable = '0';

	let rename_map = fv('rename_map') ?? '';
	let [vok, verr] = node.validate_rename_map(rename_map);

	if (!vok)
		return [null, verr];

	return [{
		rules_enable: rules_enable,
		proto_filter: join(',', proto_list),
		keyword_include: fv('keyword_include') ?? '',
		keyword_exclude: fv('keyword_exclude') ?? '',
		dedup: fv('dedup') ?? '0',
		rename_map: rename_map,
	}, null];
}

// 节点页返回链接：保留当前筛选参数
// 返回节点页。err 非空时把失败原因带到页面显示（§18：失败必须让用户看见，
// 不能「失败了却看起来像成功」）。与 back_to_list 同一套约定。
function back_to_nodes(err) {
	let id = fv('id') ?? '';
	let qs = '?id=' + urlencode(id);

	for (let k in ['proto', 'keyword', 'group', 'sort', 'desc']) {
		let v = fv(k);
		if (v != null && v != '')
			qs += '&' + k + '=' + urlencode(v);
	}

	if (err != null && `${err}` != '')
		qs += '&err=' + urlencode(tmsg(err));

	http.redirect(dispatcher.build_url('admin', 'services', 'substore', 'nodes') + qs);
}

return {
	action_create: function() {
		const core = require('substore.core');

		if (post_ok()) {
			let name = util.trim(fv('name') ?? '');
			let url = util.trim(fv('url') ?? '');
			let proxy_enable = fv('proxy_enable') ?? '0';

			if (proxy_enable != '1')
				proxy_enable = '0';

			let proxy = util.trim(fv('proxy') ?? '');

			if (name == '' || url == '')
				return back_to_list(_('Name and URL cannot be empty'));

			let [cron_enable, cron_time] = read_cron_fields();
			// 规则校验失败（如非法正则）必须回显，否则用户看到的是「规则没生效」
			let [rules, rules_err] = read_rules_fields();

			if (rules == null)
				return back_to_list(rules_err ?? _('Invalid rules'));

			let [user_agent, ua_err] = read_ua_fields();

			if (user_agent == null)
				return back_to_list(ua_err ?? _('Invalid subscription client type'));

			let [id, err] = core.add(name, url, {
				proxy_enable: proxy_enable, proxy: proxy, user_agent: user_agent,
				cron_enable: cron_enable, cron_time: cron_time,
				rules_enable: rules.rules_enable, proto_filter: rules.proto_filter,
				keyword_include: rules.keyword_include, keyword_exclude: rules.keyword_exclude,
				dedup: rules.dedup, rename_map: rules.rename_map,
			});

			if (id == null)
				return back_to_list(err ?? _('Failed to create subscription'));

			core.write_cron();
		}

		back_to_list(post_fail_msg);
	},

	action_save: function() {
		const core = require('substore.core');

		if (post_ok()) {
			let id = fv('id') ?? '';
			let name = util.trim(fv('name') ?? '');
			let url = util.trim(fv('url') ?? '');
			let proxy_enable = fv('proxy_enable') ?? '0';

			if (proxy_enable != '1')
				proxy_enable = '0';

			let proxy = util.trim(fv('proxy') ?? '');

			if (id == '')
				return back_to_list(_('Missing subscription ID'));

			if (name == '' || url == '')
				return back_to_list(_('Name and URL cannot be empty'));

			let [cron_enable, cron_time] = read_cron_fields();
			// 规则校验失败（如非法正则）必须回显，否则用户看到的是「规则没生效」
			let [rules, rules_err] = read_rules_fields();

			if (rules == null)
				return back_to_list(rules_err ?? _('Invalid rules'));

			let [user_agent, ua_err] = read_ua_fields();

			if (user_agent == null)
				return back_to_list(ua_err ?? _('Invalid subscription client type'));

			let [ok, err] = core.save_meta(id, {
				name: name, url: url, proxy_enable: proxy_enable, proxy: proxy,
				user_agent: user_agent,
				cron_enable: cron_enable, cron_time: cron_time,
				rules_enable: rules.rules_enable, proto_filter: rules.proto_filter,
				keyword_include: rules.keyword_include, keyword_exclude: rules.keyword_exclude,
				dedup: rules.dedup, rename_map: rules.rename_map,
			});

			if (!ok)
				return back_to_list(err ?? _('Save failed'));

			core.write_cron();
		}

		back_to_list(post_fail_msg);
	},

	action_local_create: function() {
		const core = require('substore.core');

		if (post_ok()) {
			let name = util.trim(fv('name') ?? '');
			let content = fv('content') ?? '';
			let local_mode = fv('local_mode') ?? 'text';
			// 规则校验失败（如非法正则）必须回显，否则用户看到的是「规则没生效」
			let [rules, rules_err] = read_rules_fields();

			if (rules == null)
				return back_to_list(rules_err ?? _('Invalid rules'));

			// §19：空名称 / 空内容必须明确报错，不能无声创建无效订阅
			if (name == '')
				return back_to_list(_('Name cannot be empty'));

			if (content == '')
				return back_to_list(_('Subscription content cannot be empty'));

			let [id, err] = core.add_local(name, content, local_mode, {
				rules_enable: rules.rules_enable,
				proto_filter: rules.proto_filter,
				keyword_include: rules.keyword_include,
				keyword_exclude: rules.keyword_exclude,
				dedup: rules.dedup,
			});

			if (id == null)
				return back_to_list(err ?? _('Failed to create local subscription'));
		}

		back_to_list(post_fail_msg);
	},

	action_local_save: function() {
		const core = require('substore.core');

		if (post_ok()) {
			let id = fv('id') ?? '';
			let name = util.trim(fv('name') ?? '');
			let content = fv('content') ?? '';
			let local_mode = fv('local_mode') ?? 'text';
			// 规则校验失败（如非法正则）必须回显，否则用户看到的是「规则没生效」
			let [rules, rules_err] = read_rules_fields();

			if (rules == null)
				return back_to_list(rules_err ?? _('Invalid rules'));

			if (id == '')
				return back_to_list(_('Missing subscription ID'));

			if (name == '')
				return back_to_list(_('Name cannot be empty'));

			if (content == '')
				return back_to_list(_('Subscription content cannot be empty'));

			let [ok, err] = core.save_meta(id, {
				name: name,
				raw_content: content,
				local_mode: local_mode,
				rules_enable: rules.rules_enable,
				proto_filter: rules.proto_filter,
				keyword_include: rules.keyword_include,
				keyword_exclude: rules.keyword_exclude,
				dedup: rules.dedup,
			});

			if (!ok)
				return back_to_list(err ?? _('Save failed'));

			// 解析失败会写进 meta.error（列表页 Status 列可见），此处再明确提示一次。
			// 成功时 sync 返回节点数（可能是 0），失败才返回 null —— 不能用
			// `!sok` 判断，ucode 里 0 是假值，会把「解析成功但 0 个节点」误报成失败。
			let [sok, serr] = core.sync(id);

			if (sok == null)
				return back_to_list(serr ?? _('Failed to parse subscription content'));
		}

		back_to_list(post_fail_msg);
	},

	action_delete: function() {
		const core = require('substore.core');

		if (post_ok()) {
			// §18：删除失败必须让用户看见。core.remove 对「非法 ID / 订阅不存在」
			// 返回 false（或 false, err），此前返回值被整个丢弃 —— 用户点了删除，
			// 页面正常跳回，订阅却还在，看起来像「删了但没生效」。
			//
			// id 支持单个（行内删除按钮）或逗号分隔多个（勾选批量删除），
			// 与节点页 action_node_delete 的 idx 同一套约定。订阅 id 是 "s%08x"，
			// 不含逗号，切分不会切坏。
			let ids = [];

			// match(..., /g) 返回的是「每个匹配各自一个数组」（整段在 [0]），
			// 不是字符串数组，所以要取 m[0]。字符类用显式的空格/制表/换行，
			// 不用 \s：ucode 正则不支持 PCRE 的字符类缩写。
			for (let m in match(fv('id') ?? '', /[^, \t\r\n]+/g) ?? [])
				push(ids, m[0]);

			if (length(ids) == 0)
				return back_to_list(_('No subscription selected for deletion'));

			let removed = 0, first_err = null;

			for (let id in ids) {
				let [ok, err] = core.remove(id);

				if (ok)
					removed++;
				else if (first_err == null)
					first_err = err;
			}

			// 部分失败也必须说：勾了 5 个只删掉 3 个却显示「成功」，
			// 用户不会再回头管剩下那 2 个。
			//
			// 只要**有订阅真的被删掉**就要重写 cron —— 部分失败的分支也不例外：
			// 被删掉的订阅的 cron 行若留着，substore-cron.sh 会拿着已不存在的 id
			// 反复执行，每次都以非 0 退出（见脚本末尾的 FAILED 判断），
			// 在日志里刷失败、并让监控误报。
			if (removed > 0)
				core.write_cron();

			if (removed < length(ids)) {
				if (removed == 0)
					return back_to_list(first_err ?? _('Delete failed: subscription not found'));

				return back_to_list(sprintf(_('Deleted %d, %d failed'),
					removed, length(ids) - removed));
			}
		}

		back_to_list(post_fail_msg);
	},

	// 单节点保存：表单 JSON 解析后经 merge_form_node 合并到原节点（保留 raw/tags 等非表单字段）
	action_node_save: function() {
		const core = require('substore.core');
		const parser = require('substore.parser');

		if (post_ok()) {
			let id = fv('id') ?? '';
			// 页面上的 idx 是 1 基的原始数组下标（见 nodes.ut 的 __idx），
			// 存储是 ucode 数组（0 基），进出各转换一次。
			let idx = int(fv('idx') ?? '');
			let content = fv('content') ?? '';
			let nodes = core.read_nodes(id);

			// §18：任何一条失败路径都必须把原因带回页面。
			// 原来只在成功分支里做事，其余情况一律静默重定向，
			// 用户提交了坏数据却看到「已保存」的样子。
			if (!idx || idx < 1 || idx > length(nodes)) {
				back_to_nodes(_('Node not found or invalid index'));
				return;
			}

			if (content == '') {
				back_to_nodes(_('Submitted content is empty'));
				return;
			}

			let [res, perr] = parser.parse_local(content, 'form');
			let newn = res?.nodes?.[0];

			if (newn == null) {
				back_to_nodes(perr ?? _('Failed to parse form data'));
				return;
			}

			nodes[idx - 1] = core.merge_form_node(nodes[idx - 1], newn);

			if (!core.write_nodes(id, nodes)) {
				back_to_nodes(_('Failed to write node data'));
				return;
			}

			core.refresh_combos(id);
		}

		back_to_nodes(post_fail_msg);
	},

	// 节点删除：idx 支持单个（行内删除按钮）或逗号分隔多个（勾选批量删除）
	action_node_delete: function() {
		const core = require('substore.core');

		if (post_ok()) {
			let id = fv('id') ?? '';
			let idx_param = fv('idx') ?? '';
			let nodes = core.read_nodes(id);
			let idxs = [];

			for (let m in match(idx_param, /[0-9]+/g) ?? [])
				push(idxs, int(m[0]));

			// §18：什么都没删掉时必须说清楚，不能静默跳回列表。
			if (length(idxs) == 0) {
				back_to_nodes(_('No node selected for deletion'));
				return;
			}

			// 倒序删除，避免 splice 后下标偏移
			sort(idxs, (a, b) => b - a);

			let removed = false;

			for (let i in idxs) {
				if (i >= 1 && i <= length(nodes)) {
					splice(nodes, i - 1, 1);
					removed = true;
				}
			}

			if (!removed) {
				back_to_nodes(_('Node not found or already deleted'));
				return;
			}

			if (!core.write_nodes(id, nodes)) {
				back_to_nodes(_('Failed to write node data'));
				return;
			}

			core.save_meta(id, { node_count: length(nodes) });
			core.refresh_combos(id);
		}

		back_to_nodes(post_fail_msg);
	},

	// 单节点分组快速设置（XHR，JSON 响应）
	action_node_set_group: function() {
		const core = require('substore.core');

		http.prepare_content('application/json');

		if (!post_ok()) {
			http.write(util.json_encode({ ok: false, err: 'forbidden' }));
			return;
		}

		let id = fv('id') ?? '';
		let idx = int(fv('idx') ?? '');
		let group = util.trim(fv('group') ?? '');
		let nodes = core.read_nodes(id);

		if (!idx || idx < 1 || idx > length(nodes)) {
			http.write(util.json_encode({ ok: false, err: 'node not found' }));
			return;
		}

		if (group != '')
			nodes[idx - 1].group = group;
		else
			delete nodes[idx - 1].group;

		if (!core.write_nodes(id, nodes)) {
			http.write(util.json_encode({ ok: false, err: 'write failed' }));
			return;
		}

		// 与 node_save / node_delete 一致：group 是组合订阅筛选与重命名规则的输入，
		// 改了不同步组合的话，组合的下载链接会一直吐旧分组的数据。
		core.refresh_combos(id);
		http.write(util.json_encode({ ok: true }));
	},

	// combo save: id empty create else edit, sources from src_id checkboxes and reuse rules
	action_combo_save: function() {
		const core = require('substore.core');

		if (post_ok()) {
			let id = util.trim(fv('id') ?? '');
			let name = util.trim(fv('name') ?? '');
			let sources = [];
			let [items] = core.list();

			for (let it in items)
				if (!it.combo && fv('src_' + it.id))
					push(sources, it.id);

			// §18：此前名称留空、或一个来源都没勾选时，这里整段跳过、直接跳回列表 ——
			// 用户填了表单却什么都没发生，页面上也没有任何提示。
			if (name == '')
				return back_to_list(_('Name cannot be empty'));

			// 规则校验失败（如非法正则）必须回显，否则用户看到的是「规则没生效」
			let [rules, rules_err] = read_rules_fields();

			if (rules == null)
				return back_to_list(rules_err ?? _('Invalid rules'));

			let o = {
				rules_enable: rules.rules_enable, proto_filter: rules.proto_filter,
				keyword_include: rules.keyword_include, keyword_exclude: rules.keyword_exclude,
				dedup: rules.dedup,
			};
			// 返回值此前被整个丢弃：add_combo / save_combo 的失败（非法 ID、
			// 未选来源、写入失败）一律静默。
			let nid, err;

			if (id == '')
				[nid, err] = core.add_combo(name, sources, o);
			else
				[nid, err] = core.save_combo(id, name, sources, o);

			if (nid == null)
				return back_to_list(err ?? _('Failed to save combination'));
		}

		back_to_list(post_fail_msg);
	},

	action_update: function() {
		const core = require('substore.core');

		if (post_ok()) {
			let id = fv('id') ?? '';
			let meta = core.get(id);

			if (meta != null && meta['local']) {
				// local subscription does not support auto update
				return;
			}

			// §18：订阅不存在（ID 拼错 / 已被删除）时此前静默跳回列表，
			// 用户点了「更新」却看不到任何反馈。
			if (meta == null)
				return back_to_list(_('Subscription not found'));

			// core.sync 的失败是「返回 null, err」而非抛错，因此检查返回值即可；
			// 抛异常的路径由 dispatcher 的 error500 兜底（与 Lua 版 pcall 的
			// 「异常也必须写回 meta.error」不同：ucode 里捕获异常会把它的类型
			// 变成返回值，破坏调用方约定，这里交给统一错误页）。
			let [res, err] = core.sync(id);

			if (res == null) {
				// 存进 meta.error 的必须是**语言中立的 msgid**（不是 _() 的结果）：
				// 它会一直留在列表文件里，而读它的页面未必是同一个语言环境。
				// 翻译交给读的那一端（视图里的 msg.translate）。
				core.save_meta(id, { error: `${err ?? 'Update failed'}`, last_update: time() });
			}
		}

		back_to_list(post_fail_msg);
	},

	// node probe endpoint: POST id + mode ping tcping url + proto + keyword, return JSON
	action_probe: function() {
		const core = require('substore.core');
		const node = require('substore.node');
		const probe = require('substore.probe');

		if (!post_ok()) {
			http.status(403, 'Forbidden');
			http.prepare_content('text/plain; charset=utf-8');
			http.write('invalid token');
			return;
		}

		let id = util.trim(fv('id') ?? '');
		let mode = util.trim(fv('mode') ?? '');

		if (mode != 'ping' && mode != 'tcping' && mode != 'url') {
			http.status(400, 'Bad Request');
			http.prepare_content('text/plain; charset=utf-8');
			http.write('bad mode');
			return;
		}

		let meta = core.get(id);

		if (meta == null) {
			http.status(404, 'Not Found');
			http.prepare_content('text/plain; charset=utf-8');
			http.write('not found');
			return;
		}

		// 与 nodes 页一致的过滤：按当前 proto / keyword 过滤后逐个探测
		let nodes = core.read_nodes(id);
		let proto = util.trim(fv('proto') ?? '');
		let keyword = util.trim(fv('keyword') ?? '');

		if (proto != '')
			nodes = node.filter(nodes, { proto: proto });

		if (keyword != '')
			nodes = node.filter(nodes, { keyword: keyword });

		nodes = node.sort(nodes, 'name', false);

		let results = probe.probe(nodes, mode);
		let ok_count = 0, sum = 0;

		for (let r in results) {
			if (r.latency != null) {
				ok_count++;
				sum += r.latency;
			}
		}

		let avg = ok_count > 0 ? floor(sum / ok_count + 0.5) : null;

		http.prepare_content('application/json; charset=utf-8');
		http.write(util.json_encode({
			ok: true, mode: mode, total: length(results),
			ok_count: ok_count, avg: avg, results: results,
		}));
	},

	// 公开下载端点：GET /substore/download?token=<token>&target=<format>
	action_download: function() {
		const core = require('substore.core');

		let token = util.trim(fv('token') ?? '');
		let target = util.trim(fv('target') ?? 'ClashMeta');
		let [content, ct, filename, err] = core.generate_link(token, target);

		if (content == null) {
			http.status(404, 'Not Found');
			http.prepare_content('text/plain; charset=utf-8');
			http.write(err ?? 'not found');
			return;
		}

		http.prepare_content(ct);
		// 文件名白名单：剥离引号/换行/控制字符，防 HTTP 头注入
		let safe_name = replace(filename ?? 'subscription.txt', /[^A-Za-z0-9_.-]/g, '_');
		http.header('Content-Disposition',
			'attachment; filename="' + safe_name + '"');
		http.write(content);
	},
};
