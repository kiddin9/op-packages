// probe.uc — 节点网络探测（Ping / TCPing / URL 测试）（纯 ucode，无 luci.* 依赖）
// luci-app-substore
// 依赖 busybox 内置工具：ping、wget、cut；装了 curl 时 TCPing / URL 测试走 curl
//（OpenWrt / ImmortalWrt 均内置前三者，curl 为可选增强）
//
// 原 Lua 版用多返回值（`cmd, parse`），ucode 函数只有一个返回值，内部构造
// 探测任务的 build_url_job / build_job 改为返回数组 `[cmd, parse_fn]`，
// 不适用（非法目标 / 未知模式）时返回 null。对外 API 名保持不变。

import { popen } from 'fs';
import { isnan } from 'math';

const util = require('substore.util');

const M = {};

M.TIMEOUT = 2; // 每个目标的超时（秒）

// 批量探测时同时存在的子进程上限。
// 每个探测占 1 个进程 + 1 个管道 fd，节点数由订阅内容决定（可上千），
// 不限并发会把路由器的 fd/进程额度打满，之后 io.popen 静默失败。
M.MAX_PARALLEL = 16;

// shell 引号：用单引号转义（util.shq），配合 safe_host 校验，双重防命令注入。
// 不能用 string.format("%q")：它生成双引号字符串，sh 在双引号内仍会做 $() / ``
// 命令替换，实测可注入。
function q(s) { return util.shq(s); }

// 校验目标主机名/IP：仅允许 [A-Za-z0-9._-] 与冒号（IPv6），杜绝命令注入
function safe_host(host) {
	if (type(host) != 'string' || host == '') return false;
	if (!match(host, /^[A-Za-z0-9._:-]+$/)) return false;
	// 以 "-" 开头会被 busybox 的 getopt 当成**选项**而不是参数：
	// 命令是 `ping -c 1 -W 2 <host>`，host="--help" / "-c" 会改变 ping 的行为。
	// 引号（util.shq）挡不住这个 —— 引号由 shell 剥掉，getopt 看到的仍是 -x。
	// 合法主机名（RFC 1123 要求首字符为字母或数字）与 IP 都不会以 "-" 开头。
	if (substr(host, 0, 1) == '-') return false;
	return true;
}

// 本机 / 未指定地址：订阅里 UA 不匹配时机场下发的占位节点全是
// 127.0.0.1:1080，从路由器探测必然「成功」（约 0ms），会把假节点显示成
// 最快的节点。探测结果没有意义，一律按失败处理。
function is_local_host(host) {
	let h = lc(host);
	if (h == 'localhost' || match(h, /\.localhost$/)) return true;
	if (match(h, /^127\./)) return true;
	if (h == '0.0.0.0' || h == '::' || h == '::1'
	    || h == '0:0:0:0:0:0:0:0' || h == '0:0:0:0:0:0:0:1')
		return true;
	if (match(h, /^::ffff:127\./)) return true;
	return false;
}

function target_ok(host) {
	return safe_host(host) && !is_local_host(host);
}

// 构造 http URL：IPv6 字面量必须写成 [addr]:port，否则 "2001:db8::1:443" 不是合法 URL，
// curl 直接报 URL rejected（code 000），导致所有 IPv6 节点的 URL 测试恒为失败。
function http_url(server, port) {
	if (index(server, ':') >= 0)
		return 'http://[' + server + ']:' + port + '/';
	return 'http://' + server + ':' + port + '/';
}

function safe_port(port) {
	// tonumber 语义：只接受数字或数字字符串（null / bool 等一律作废）。
	// 注意 ucode 的 `+null` / `+true` 分别是 0 / 1，必须先按类型过滤。
	let t = type(port);
	if (t != 'int' && t != 'double' && t != 'string')
		return null;
	port = +port;
	if (isnan(port) || port < 1 || port > 65535)
		return null;
	return port;
}

// 解析 ping 输出的 time=xx.x ms
M.parse_ping = function(out) {
	out = out ?? '';
	let t = match(out, /time=([0-9.]+)/);
	return t ? +t[1] : null;
};

// 解析 shell 包装输出的 "起始uptime 结束uptime"（单位秒），返回毫秒延迟
M.parse_delta = function(out) {
	out = util.trim(out ?? '');
	let m = match(out, /^([0-9]+\.?[0-9]*)[[:space:]]+([0-9]+\.?[0-9]*)$/);
	if (m) {
		let d = (+m[2] - +m[1]) * 1000;
		if (d >= 0) return d;
	}
	return null;
};

// 可用 HTTP 工具检测（优先 curl，回退 busybox wget），TCPing / URL 测试共用
let http_tool = null;
function detect_http_tool() {
	if (http_tool == null) {
		let f = popen('command -v curl >/dev/null 2>&1 && echo curl || echo wget');
		http_tool = util.trim(f ? (f.read('all') ?? 'wget') : 'wget');
		if (f) f.close();
	}
	return http_tool;
}

function build_url_job(url) {
	if (detect_http_tool() == 'curl') {
		let cmd = 'curl -s -o /dev/null --connect-timeout ' + M.TIMEOUT + ' --max-time ' + M.TIMEOUT
			+ " -w '%{http_code} %{time_total}' " + q(url) + ' 2>/dev/null';
		return [cmd, function(out) {
			// http_code=000 表示连接失败（拒绝/超时），其余状态码均说明对端可用 HTTP 通信
			let m = match(util.trim(out ?? ''), /^([0-9]+)[[:space:]]+([0-9.]+)$/);
			if (!m) return null;
			let code = m[1], t = +m[2];
			if (code != '000' && !isnan(t) && t > 0) return t * 1000;
			return null;
		}];
	}
	let cmd = "a=$(cut -d' ' -f1 /proc/uptime); if wget -q -T " + M.TIMEOUT + ' -O /dev/null ' + q(url)
		+ ' 2>/dev/null; then b=$(cut -d\' \' -f1 /proc/uptime); echo "$a $b"; fi';
	return [cmd, M.parse_delta];
}

// TCP 连通测试（TCPing）：取 curl 的 %{time_connect}（TCP 握手耗时）。
// 节点端口一般不是 HTTP 服务，curl 握手成功后读不到 HTTP 响应，http_code 为
// 000 —— 只要 time_connect > 0 就说明 TCP 已连通，与 HTTP 状态无关。
//
// 不用 `nc -z`：BusyBox 的 nc 没有 -z（实测直接打印用法），旧写法在 OpenWrt
// / ImmortalWrt 上恒为失败，这正是 TCPing 结果与客户端差距巨大的原因之一。
function build_tcp_job(url) {
	if (detect_http_tool() == 'curl') {
		let cmd = 'curl -s -o /dev/null --connect-timeout ' + M.TIMEOUT + ' --max-time ' + M.TIMEOUT
			+ " -w '%{time_connect} %{http_code}' " + q(url) + ' 2>/dev/null';
		return [cmd, function(out) {
			let m = match(util.trim(out ?? ''), /^([0-9.]+)[[:space:]]+([0-9]+)$/);
			if (!m) return null;
			let t = +m[1];
			return (!isnan(t) && t > 0) ? t * 1000 : null;
		}];
	}
	// 没有 curl 时只能借 wget 做 HTTP 层计时（BusyBox nc 也无 -z）：
	// 不响应 HTTP 的节点会显示失败，这是缺 curl 时的能力上限。
	let cmd = "a=$(cut -d' ' -f1 /proc/uptime); if wget -q -T " + M.TIMEOUT + ' -O /dev/null ' + q(url)
		+ ' 2>/dev/null; then b=$(cut -d\' \' -f1 /proc/uptime); echo "$a $b"; fi';
	return [cmd, M.parse_delta];
}

// 单节点探测（串行，便于单测）。返回延迟 ms（number）或 nil（失败/超时）
M.ping = function(server) {
	server = util.trim(server ?? '');
	if (!target_ok(server)) return null;
	let f = popen('ping -c 1 -W ' + M.TIMEOUT + ' ' + q(server) + ' 2>/dev/null');
	let out = f ? (f.read('all') ?? '') : '';
	if (f) f.close();
	return M.parse_ping(out);
};

M.tcping = function(server, port) {
	server = util.trim(server ?? '');
	port = safe_port(port);
	if (!target_ok(server) || !port) return null;
	let [cmd, parse] = build_tcp_job(http_url(server, port));
	let f = popen(cmd);
	let out = f ? (f.read('all') ?? '') : '';
	if (f) f.close();
	return parse(out);
};

M.url_test = function(server, port) {
	server = util.trim(server ?? '');
	port = safe_port(port);
	if (!target_ok(server) || !port) return null;
	let url = http_url(server, port);
	let [cmd, parse] = build_url_job(url);
	let f = popen(cmd);
	let out = f ? (f.read('all') ?? '') : '';
	if (f) f.close();
	return parse(out);
};

// 为单个节点构造探测任务：返回 [cmd, parse] 或 nil
function build_job(mode, server, port) {
	server = util.trim(server ?? '');
	if (!target_ok(server)) return null;
	if (mode == 'ping') {
		return ['ping -c 1 -W ' + M.TIMEOUT + ' ' + q(server) + ' 2>/dev/null', M.parse_ping];
	}
	else if (mode == 'tcping') {
		port = safe_port(port);
		if (!port) return null;
		return build_tcp_job(http_url(server, port));
	}
	else if (mode == 'url') {
		port = safe_port(port);
		if (!port) return null;
		return build_url_job(http_url(server, port));
	}
	return null;
}

// 批量探测：mode = "ping" | "tcping" | "url"
// 并行启动所有子进程再统一读取，总耗时≈单节点超时，而非节点数×超时。
// 返回结果数组 { name=, server=, port=, latency=number|nil }
M.probe = function(nodes, mode) {
	// 分批：一批最多 MAX_PARALLEL 个进程，读完并关闭这一批再起下一批。
	//
	// 原来是「先把全部节点的 io.popen 起完，再统一读取」。并行度确实最高
	// （总耗时≈单节点超时），但代价是无界的：每个节点占 1 个进程 + 1 个管道 fd，
	// 而节点数由订阅内容决定（上千个很常见）。路由器上 fd 与进程数都是硬上限，
	// 打满之后 io.popen 直接失败 —— 表现是一大片节点探测不出来，
	// 而不是报错。分批后并发度封顶，总耗时仍是「批数 × 单节点超时」。
	let out = [];
	let batch = [];

	function drain() {
		for (let j in batch) {
			let latency = null;
			if (j.f) {
				let raw = j.f.read('all') ?? '';
				j.f.close();
				// 显式判空：ucode 里 0 是假值，不能照搬 Lua 的
				// `j.parse and j.parse(raw) or nil`（延迟为 0 时会被吞掉）
				latency = j.parse ? j.parse(raw) : null;
			}
			push(out, {
				name: j.name, server: j.server, port: j.port, latency: latency,
			});
		}
		batch = [];
	}

	for (let n in (nodes ?? [])) {
		let job = build_job(mode, n.server, n.port);
		let f = job ? popen(job[0]) : null;
		push(batch, {
			f: f, parse: job ? job[1] : null,
			name: n.name ?? '', server: n.server ?? '', port: n.port ?? '',
		});
		if (length(batch) >= M.MAX_PARALLEL) drain();
	}

	drain();
	return out;
};

return M;
