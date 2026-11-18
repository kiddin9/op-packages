/** @typedef {import('../../../share/ucode/hijpass/types/diagnostics.uc').CleanupPlan} CleanupPlan */
/** @typedef {import('../../../share/ucode/hijpass/types/diagnostics.uc').CaptureMetadata} CaptureMetadata */
/** @typedef {import('../../../share/ucode/hijpass/types/diagnostics.uc').TraceIdentity} TraceIdentity */
/** @typedef {import('../../../share/ucode/hijpass/types/diagnostics.uc').PreparedCapture} PreparedCapture */
/** @typedef {import('../../../share/ucode/hijpass/types/diagnostics.uc').LogPosition} LogPosition */
import * as fs from 'fs';
import { logPath } from 'hijpass.config.paths';
import { read } from 'hijpass.uci.read';
import { resolve } from '../network/network.uc';
import { atomic, lines, text, renderTemplate } from 'hijpass.common';
import { run } from 'hijpass.command.runtime';
import { report } from './report.uc';

// Capture 字段：mode 为 client/router；client 为客户端 IP，protocol 为 all/tcp/udp，
// port 为目标端口或 all，seconds 为捕获时长。router 模式的 url/method/host/targetPort
// 描述 curl 请求；addresses 为解析结果。tcpdump/iface/verbose/keep 控制报告与文件保留。
// chain/comment 以当前 PID 隔离 nft 规则；filter 为已校验字段生成的 BPF 表达式。
/**
 * 解析诊断命令参数，校验捕获目标和过滤条件。
 * @param {string[]} args
 * @param {string} [pid]
 * @returns {Capture} 捕获参数对象，含过滤条件和任务专属标识。
 */
export function parse(args, pid) {
	let capture = { mode: 'router', client: '', protocol: 'all', port: 'all', seconds: '8', method: 'HEAD',
		tcpdump: false, iface: 'any', verbose: false, keep: false, addresses: [] }, urls = [];
	const options = { '-c': 'client', '-n': 'protocol', '-P': 'port', '-t': 'seconds', '-X': 'method', '-i': 'iface' };
	for (let i = 0; i < length(args); i++) {
		let arg = args[i] || '';
		if (options[arg]) {
			if (args[i + 1] == null) {
				die(`missing value for ${arg}`);
			}
			capture[options[arg]] = args[++i];
		}
		else if (arg == '-p') {
			capture.tcpdump = true;
		}
		else if (arg == '-v') {
			capture.verbose = true;
		}
		else if (arg == '-K') {
			capture.keep = true;
		}
		else if (arg == '-h') {
			print('capture.sh [-t 1..120] [-X HEAD|GET] [-p] [-i iface] [-v] [-K] URL\ncapture.sh -c IP [-n all|tcp|udp] [-P port|all] [-t 1..120] [-p] [-i iface] [-v] [-K]\n');
			exit(0);
		}
		else if (substr(arg, 0, 1) == '-') {
			die(`unknown option ${arg}`);
		}
		else {
			push(urls, arg);
		}
	}
	if (!match(capture.seconds, /^[0-9]+$/)) {
		die('timeout must be an integer');
	}
	capture.seconds = int(capture.seconds);
	if (capture.seconds < 1) {
		die('timeout must be >= 1');
	}
	if (capture.seconds > 120) {
		die('timeout must be <= 120');
	}
	if (index(['all', 'tcp', 'udp'], capture.protocol) < 0) {
		die('protocol must be all, tcp or udp');
	}
	if (capture.port != 'all' && (!match(capture.port, /^[0-9]+$/) || int(capture.port) < 1 || int(capture.port) > 65535)) {
		die('invalid destination port');
	}
	if (!match(capture.iface, /^[A-Za-z0-9_.:@-]+$/)) {
		die('invalid tcpdump interface');
	}
	capture.method = uc(capture.method);
	if (index(['HEAD', 'GET'], capture.method) < 0) {
		die('method must be HEAD or GET');
	}
	if (capture.client) {
		capture.mode = 'client';
		if (!iptoarr(capture.client || '')) {
			die('invalid client IP');
		}
		if (length(urls)) {
			die('client mode does not take a URL');
		}
		capture.filter = capture.port == 'all' ? `host ${capture.client}` : `((src host ${capture.client} and dst port ${capture.port}) or (dst host ${capture.client} and src port ${capture.port}))`;
		if (capture.protocol != 'all') {
			capture.filter += ` and ${capture.protocol}`;
		}
		else if (capture.port != 'all') {
			capture.filter += ' and (tcp or udp)';
		}
	}
	else {
		if (length(urls) != 1) {
			die('router mode requires one URL');
		}
		let url = urls[0];
		if (type(url) != 'string') {
			die('invalid HTTP URL');
		}
		capture.url = url;
		let m = match(url, /^(https?):\/\/(\[[A-Fa-f0-9:.]+\]|[A-Za-z0-9_.-]+)(:([0-9]+))?([/?#]|$)/);
		if (!m) {
			die('invalid HTTP URL');
		}
		capture.host = replace(m[2], /^\[|\]$/g, ''); capture.targetPort = int(m[4] || (m[1] == 'https' ? '443' : '80'));
		if (capture.targetPort < 1 || capture.targetPort > 65535) {
			die('invalid URL port');
		}
		capture.filter = `tcp port ${capture.targetPort}`;
	}
	pid ||= fs.readlink('/proc/self'); capture.chain = `trace-${pid}`; capture.comment = `hijpass-trace-${pid}`;
	return capture;
};

/**
 * 记录当前日志位置，供报告提取本次诊断产生的日志。
 * @returns {LogPosition[]} {path, offset, inode} 数组；无日志时为空数组，offset 单位为字节。
 */
function positions(configDirectory) {
	let sections = [];
	// 诊断本身不依赖服务已配置；缺少 UCI 时仍可提供 nft/系统日志报告。
	try { sections = read('hijpass', configDirectory); } catch (e) { return []; }
	return filter(map(uniq(map(sections, s => logPath(s))), path => {
		let stat = path && fs.stat(path);
		return stat?.type == 'file' ? { path, offset: stat.size, inode: stat.inode } : null;
	}), entry => entry != null);
}
// PreparedCapture：包含所有已校验的 Capture 字段及 directory（任务目录）。
// metadata.json 额外保存日志位置快照；Shell 无需解析 UCI 或拼装 nft 表达式。
/**
 * 校验捕获参数并解析目标 IP，返回任务目录和过滤条件；解析失败时告警。
 * 任务元数据和日志起点由 rules 命令在生成追踪规则前写入。
 * @param {string|null} pid 命令参数，可缺失；入口拒绝空值。
 * @param {string[]} args
 * @returns {PreparedCapture} 带 addresses 和 directory 的捕获参数；解析失败时 addresses 为空数组。
 */
export function prepare(pid, args) {
    if (!match(pid || '', /^[0-9]+$/)) {
        die('invalid capture PID');
    }
    let capture = parse(args, pid);
    if (capture.mode == 'router') {
        try { capture.addresses = [resolve(capture.host)]; } catch (e) { warn(`${e.message}\n`); }
    }
    capture.directory = `/tmp/hijpass-trace.${pid}`;
    return capture;
};

/** @typedef {import('../../../share/ucode/hijpass/types/diagnostics.uc').Capture} Capture */
// 这里只生成 nft 文本；Shell 负责真正加载规则以及处理失败清理。
/**
 * 根据捕获参数渲染 nft 追踪规则。
 * @param {Capture} capture
 * @returns {string} 完整的 nft 规则文本。
 */
export function ruleText(capture) {
    return renderTemplate('/usr/lib/hijpass/diagnostics/trace.ut', { capture });
};
/**
 * 校验任务目录，并从目录名还原 nft 规则标识。
 * @param {string|null} directory
 * @returns {TraceIdentity} 任务标识 {chain, comment}。
 */
function identity(directory) {
    if (type(directory) != 'string' || !match(directory, /^\/tmp\/hijpass-trace[.][0-9]+$/)) {
        die('invalid capture directory');
    }
    let pid = substr(directory, length('/tmp/hijpass-trace.'));
    return { chain: `trace-${pid}`, comment: `hijpass-trace-${pid}` };
}
/**
 * 读取诊断元数据，并核对其是否属于当前任务。
 * @param {string|null} directory
 * @returns {CaptureMetadata} {capture, positions}，分别为捕获参数和日志起点。
 */
function metadata(directory) {
    let expected = identity(directory), data;
    try { data = json(text(directory + '/metadata.json')); }
    catch (e) { die(`invalid capture metadata: ${e.message}`); }
    if (type(data) != 'object' || type(data.capture) != 'object') {
        die('invalid capture metadata');
    }
    let capture = data.capture;
    if (capture.chain != expected.chain || capture.comment != expected.comment || (capture.mode != 'client' && capture.mode != 'router')) {
        die('invalid capture identity');
    }
    return data;
}
// CleanupPlan：rules 为 chain/handle 数组；标识从目录提取，不依赖损坏的 metadata。
/**
 * 从 nft 规则快照中找出当前诊断任务需要删除的规则。
 * @param {string|null} directory
 * @param {string} raw
 * @returns {CleanupPlan} {chain, comment, rules}，rules 为 {chain, handle} 数组。
 */
export function cleanupPlan(directory, raw) {
    let expected = identity(directory), rules = [];
    for (let line in lines(raw)) {
        let m = match(line, /^(pre-filter|out-route) (.*)$/);
        if (!m || index(m[2], `comment "${expected.comment}"`) < 0) {
            continue;
        }
        let handle = match(m[2], /# handle ([0-9]+)/);
        if (handle) {
            push(rules, { chain: m[1], handle: handle[1] });
        }
    }
    return { ...expected, rules };
};
/**
 * 分发诊断子命令，生成任务参数、追踪规则或诊断报告。
 * @returns {null} 结果写入 stdout，错误通过 stderr 和退出码报告。
 */
export function main() { run(ARGV,
    /**
     * @param {string[]} args
     * @param {string|null} configDirectory
     */
    function(args, configDirectory) {
    let action = shift(args);
    if (action == 'prepare') {
        let pid = shift(args);
        return prepare(pid, args);
    }
    if (action == 'rules') {
        let raw = args[0];
        if (type(raw) != 'string') {
            die('missing capture data');
        }
        let capture;
        try { capture = json(raw); } catch (e) { die(`invalid capture data: ${e.message}`); }
        if (type(capture) != 'object') {
            die('invalid capture data');
        }
        identity(capture.directory);
        atomic(capture.directory + '/metadata.json', sprintf('%J', { capture, positions: positions(configDirectory) }));
        return ruleText(capture);
    }
    if (action == 'cleanup') {
        let plan = cleanupPlan(args[0], text(args[1])), keep = false;
        // 元数据损坏不能阻断规则清理；保留原来的不保留任务文件行为。
        try { keep = metadata(args[0]).capture.keep === true; }
        catch (e) { }
        return { ...plan, keep };
    }
    if (action == 'report') {
        let directory = args[0];
        if (type(directory) != 'string') {
            die('invalid capture directory');
        }
        let data = metadata(directory), capture = data.capture;
        return report(capture, directory, data.positions) + (capture.keep === true ? `Temporary files kept: ${args[0]}\n` : '');
    }
    if (action == 'task-status') {
        let directory = args[0], active = args[1] == '1';
        return { running: active, code: active ? null : int(fs.readfile(directory + '/exit')),
            stdout: fs.readfile(directory + '/stdout') || '', stderr: fs.readfile(directory + '/stderr') || '' };
    }
    die('unknown capture data action');
});
};
